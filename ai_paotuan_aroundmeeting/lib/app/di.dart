import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/archive/archiver.dart';
import '../engine/moderation/moderation.dart';
import '../engine/rules/character_rules.dart';
import '../engine/rules/character_sheet.dart';
import '../engine/scenario/scenario.dart';
import '../engine/scenario/scenario_parser.dart';
import '../llm/action_suggester.dart';
import '../platform/ports.dart';

// ---------------------------------------------------------------------------
// 基础设施（在 main() 的 ProviderScope 里注入；忘了注入会立刻抛错）
// ---------------------------------------------------------------------------

final fileDirsProvider = Provider<FileDirsPort>(
  (ref) => throw UnimplementedError('FileDirsPort 未注入'),
);

final settingsStoreProvider = Provider<SettingsPort>(
  (ref) => throw UnimplementedError('SettingsPort 未注入'),
);

final secretStoreProvider = Provider<SecretPort>(
  (ref) => throw UnimplementedError('SecretPort 未注入'),
);

/// 当前是否配好 key（首页状态条用）。
final apiKeyProvider = FutureProvider<String?>((ref) async {
  final secret = ref.watch(secretStoreProvider);
  return secret.read(SecretKeys.apiKey);
});

/// 本机归档列表（记忆回廊）。
final archiveListProvider = FutureProvider<List<ArchiveRecord>>((ref) async {
  final dirs = ref.watch(fileDirsProvider);
  final root = await dirs.appData();
  return Archiver(root).list();
});

// ---------------------------------------------------------------------------
// 剧本（随包资源，D-19 / D-20）
// ---------------------------------------------------------------------------

const String dinnerHalePath = 'assets/scenarios/dinner_hale/scenario.yaml';

/// 内置剧本目录：新增剧本时只改这里和 pubspec 的 assets。
const Map<String, String> scenarioPaths = <String, String>{
  'dinner_hale': dinnerHalePath,
  'mist_dock': 'assets/scenarios/mist_dock/scenario.yaml',
  'paramount_last_dance': 'assets/scenarios/paramount_last_dance/scenario.yaml',
  'xiafei_47': 'assets/scenarios/xiafei_47/scenario.yaml',
};

final scenarioCatalogProvider = FutureProvider<List<Scenario>>((ref) async {
  final loaded = await Future.wait(
    scenarioPaths.values.map((path) async {
      final source = await rootBundle.loadString(path);
      return parseScenario(source);
    }),
  );
  return List<Scenario>.unmodifiable(loaded);
});

/// 当前选中的剧本 id；切换剧本只改这里。
class SelectedScenarioNotifier extends Notifier<String> {
  @override
  String build() => 'dinner_hale';

  void select(String id) {
    if (scenarioPaths.containsKey(id)) state = id;
  }
}

final selectedScenarioIdProvider =
    NotifierProvider<SelectedScenarioNotifier, String>(
      SelectedScenarioNotifier.new,
    );

/// 玩家是从「选择剧本」点进来、还没制卡的：制卡完成后直接回到该剧本。
final pendingScenarioProvider = NotifierProvider<PendingScenarioNotifier, bool>(
  PendingScenarioNotifier.new,
);

class PendingScenarioNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void mark() => state = true;

  bool consume() {
    final value = state;
    state = false;
    return value;
  }
}

final scenarioProvider = FutureProvider<Scenario>((ref) async {
  final id = ref.watch(selectedScenarioIdProvider);
  final all = await ref.watch(scenarioCatalogProvider.future);
  return all.firstWhere(
    (scenario) => scenario.id == id,
    orElse: () => all.first,
  );
});

/// 审核器依赖当前剧本的 content_scope。
final moderatorProvider = Provider<LocalModerator>((ref) {
  final scenario = ref.watch(scenarioProvider).valueOrNull;
  return LocalModerator(scope: scenario?.contentScope ?? const ContentScope());
});

/// 玩家行动建议的生成器；测试可覆盖为固定返回。
final actionSuggesterProvider = Provider<ActionSuggester>(
  (ref) => suggestActions,
);

// ---------------------------------------------------------------------------
// 角色卡草稿
// ---------------------------------------------------------------------------

final characterProvider = NotifierProvider<CharacterNotifier, CharacterSheet>(
  CharacterNotifier.new,
);

class CharacterNotifier extends Notifier<CharacterSheet> {
  @override
  CharacterSheet build() => CharacterSheet.fresh();

  void rename(String value) => state = state.copyWith(name: value);

  void setOccupation(String value) => state = state.copyWith(occupation: value);

  void setAge(int value) => state = state.copyWith(age: value);

  void setAttribute(Attribute attribute, int value) {
    final current = state.attributes[attribute];
    final remaining = state.attributes.remaining;
    // 还有余额时最多加到「当前值 + 余额」；余额耗尽只能减。
    final ceiling = remaining > 0
        ? math.min(attributeMax, current + remaining)
        : current;
    final next = value > ceiling ? ceiling : value;
    state = state.withAttribute(
      attribute,
      next < attributeMin ? attributeMin : next,
    );
  }

  void setSkill(Skill skill, int value) {
    final current = state.skills[skill];
    final remaining = state.skills.remainingFor(state.attributes);
    final ceiling = remaining > 0 ? current + remaining : current;
    final next = value > ceiling ? ceiling : value;
    state = state.withSkill(
      skill,
      next < skill.baseValue ? skill.baseValue : next,
    );
  }

  void setItem(int index, Item item) => state = state.withItemAt(index, item);

  void removeItem(int index) => state = state.removeItemAt(index);

  /// 把剩余属性点随机分配到 8 项（单项不超过 90）。
  void randomizeAttributes() {
    var left = state.attributes.remaining;
    if (left <= 0) return;

    final random = math.Random();
    var attributes = state.attributes;

    while (left > 0) {
      final candidates = Attribute.values
          .where((attribute) => attributes[attribute] < attributeMax)
          .toList(growable: false);
      if (candidates.isEmpty) break;

      final pick = candidates[random.nextInt(candidates.length)];
      final room = attributeMax - attributes[pick];
      final take = left < room ? left : room;
      final chunk = take <= 1 ? 1 : random.nextInt(take) + 1;
      attributes = attributes.withValue(pick, attributes[pick] + chunk);
      left -= chunk;
    }

    // 意志变了 SAN 上限会变，一并钳制。
    final sanCeiling = sanMaxFor(attributes[Attribute.pow]);
    state = state.copyWith(
      attributes: attributes,
      sanCurrent: state.sanCurrent > sanCeiling ? sanCeiling : state.sanCurrent,
    );
  }

  /// 把**剩余**技能点随机加到各技能（只加不减，单项不超过 70）。
  void randomizeSkills() {
    var left = state.skills.remainingFor(state.attributes);
    if (left <= 0) return;

    final allocatable = Skill.values
        .where((skill) => skill.isAllocatable)
        .toList(growable: false);
    final random = math.Random();
    var skills = state.skills;

    while (left > 0) {
      final candidates = allocatable
          .where((skill) => skills[skill] < skillMax)
          .toList(growable: false);
      if (candidates.isEmpty) break;

      final pick = candidates[random.nextInt(candidates.length)];
      final room = skillMax - skills[pick];
      final take = left < room ? left : room;
      final chunk = take <= 1 ? 1 : random.nextInt(take) + 1;
      skills = skills.withValue(pick, skills[pick] + chunk);
      left -= chunk;
    }

    state = state.copyWith(skills: skills);
  }

  void reset() => state = CharacterSheet.fresh();
}

// ---------------------------------------------------------------------------
// 设置
// ---------------------------------------------------------------------------

class AppSettings {
  const AppSettings({
    this.baseUrl = defaultBaseUrl,
    this.kpModel = 'deepseek-chat',
    this.bpModel = 'deepseek-chat',
    this.fadeSegments = true,
    this.motion = true,
  });

  static const String defaultBaseUrl = 'https://api.deepseek.com/v1';

  final String baseUrl;
  final String kpModel;
  final String bpModel;
  final bool fadeSegments;
  final bool motion;

  AppSettings copyWith({
    String? baseUrl,
    String? kpModel,
    String? bpModel,
    bool? fadeSegments,
    bool? motion,
  }) => AppSettings(
    baseUrl: baseUrl ?? this.baseUrl,
    kpModel: kpModel ?? this.kpModel,
    bpModel: bpModel ?? this.bpModel,
    fadeSegments: fadeSegments ?? this.fadeSegments,
    motion: motion ?? this.motion,
  );
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final store = ref.watch(settingsStoreProvider);
    return AppSettings(
      baseUrl: store.read(SettingsKeys.baseUrl) ?? AppSettings.defaultBaseUrl,
      kpModel: store.read(SettingsKeys.kpModel) ?? 'deepseek-chat',
      bpModel: store.read(SettingsKeys.bpModel) ?? 'deepseek-chat',
      fadeSegments: (store.read(SettingsKeys.presentation) ?? 'fade') == 'fade',
      motion: (store.read(SettingsKeys.motion) ?? 'on') == 'on',
    );
  }

  void setBaseUrl(String value) {
    state = state.copyWith(baseUrl: value);
    ref.read(settingsStoreProvider).write(SettingsKeys.baseUrl, value);
  }

  void setKpModel(String value) {
    state = state.copyWith(kpModel: value);
    ref.read(settingsStoreProvider).write(SettingsKeys.kpModel, value);
  }

  void setBpModel(String value) {
    state = state.copyWith(bpModel: value);
    ref.read(settingsStoreProvider).write(SettingsKeys.bpModel, value);
  }

  void setFadeSegments(bool value) {
    state = state.copyWith(fadeSegments: value);
    ref
        .read(settingsStoreProvider)
        .write(SettingsKeys.presentation, value ? 'fade' : 'instant');
  }

  void setMotion(bool value) {
    state = state.copyWith(motion: value);
    ref
        .read(settingsStoreProvider)
        .write(SettingsKeys.motion, value ? 'on' : 'off');
  }
}

// ---------------------------------------------------------------------------
// 对局设置（AI 玩家数量与名字）
// ---------------------------------------------------------------------------

class SessionConfig {
  const SessionConfig({this.bpCount = 1, this.bpNames = const <String>[]});

  final int bpCount;
  final List<String> bpNames;

  SessionConfig copyWith({int? bpCount, List<String>? bpNames}) =>
      SessionConfig(
        bpCount: bpCount ?? this.bpCount,
        bpNames: bpNames ?? this.bpNames,
      );
}

final sessionConfigProvider =
    NotifierProvider<SessionConfigNotifier, SessionConfig>(
      SessionConfigNotifier.new,
    );

class SessionConfigNotifier extends Notifier<SessionConfig> {
  @override
  SessionConfig build() => const SessionConfig();

  void apply(SessionConfig config) => state = config;

  void setBpCount(int value) => state = state.copyWith(bpCount: value);
}
