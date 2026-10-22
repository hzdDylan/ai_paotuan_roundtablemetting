import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ports/app_failure.dart';
import '../application/ports/archive_repository.dart';
import '../application/ports/clock.dart';
import '../application/ports/connection_tester.dart';
import '../application/ports/event_store.dart';
import '../application/ports/keys.dart';
import '../application/ports/llm_gateway.dart';
import '../application/ports/scenario_repository.dart';
import '../application/table/session_config.dart';
import '../application/table/table_session_factory.dart';
import '../data/llm/connection_tester_impl.dart';
import '../data/llm/llm_gateway_impl.dart';
import '../data/scenario/asset_scenario_repository.dart';
import '../engine/archive/archive_record.dart';
import '../engine/dice/dice.dart';
import '../engine/rules/character_rules.dart';
import '../engine/rules/character_sheet.dart';
import '../engine/scenario/scenario.dart';
import '../llm/llm_client.dart';
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

final eventStoreProvider = Provider<EventStore>(
  (ref) => throw UnimplementedError('EventStore 未注入'),
);

final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => throw UnimplementedError('ArchiveRepository 未注入'),
);

final scenarioRepositoryProvider = Provider<ScenarioRepository>(
  (ref) => const AssetScenarioRepository(paths: scenarioPaths),
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final rngProvider = Provider<RngPort>((ref) => SecureRng());

final connectionTesterProvider = Provider<ConnectionTester>(
  (ref) => const LlmConnectionTester(),
);

/// 当前是否配好 key（首页状态条用）。
final apiKeyProvider = FutureProvider<String?>((ref) async {
  final secret = ref.watch(secretStoreProvider);
  return secret.read(SecretKeys.apiKey);
});

/// 当前设置下可用的 LLM 网关；没有 key 时抛出 E_NO_KEY。
final llmGatewayProvider = FutureProvider<LlmGateway>((ref) async {
  final settings = ref.watch(settingsProvider);
  final secret = ref.watch(secretStoreProvider);
  final key = await secret.read(SecretKeys.apiKey);
  if (key == null || key.trim().isEmpty) {
    throw const AppFailure('E_NO_KEY', '先在设置里填 API key');
  }
  return LlmGatewayImpl(
    client: LlmClient(baseUrl: settings.baseUrl, apiKey: key.trim()),
    kpModel: settings.kpModel,
    bpModel: settings.bpModel,
  );
});

/// 一局会话工厂：组合 LLM、存储、归档、时钟与随机源。
final tableSessionFactoryProvider = FutureProvider<TableSessionFactory>((
  ref,
) async {
  final llm = await ref.watch(llmGatewayProvider.future);
  return TableSessionFactory(
    llm: llm,
    eventStore: ref.watch(eventStoreProvider),
    archives: ref.watch(archiveRepositoryProvider),
    clock: ref.watch(clockProvider),
    rng: ref.watch(rngProvider),
  );
});

/// 本机归档列表（记忆回廊）。
final archiveListProvider = FutureProvider<List<ArchiveRecord>>((ref) async {
  return ref.watch(archiveRepositoryProvider).list();
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
  return ref.watch(scenarioRepositoryProvider).loadCatalog();
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
