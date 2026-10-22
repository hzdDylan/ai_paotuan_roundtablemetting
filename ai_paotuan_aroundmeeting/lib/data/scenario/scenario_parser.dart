import 'package:yaml/yaml.dart';

import '../../engine/moderation/moderation.dart';
import '../../engine/rules/character_rules.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/scenario.dart';

/// 解析剧本 YAML（D-19 = A，随包资源）。
///
/// 失败一律抛 [FormatException]，带上出错路径，方便做 lint 时定位。
Scenario parseScenario(String source) {
  final doc = loadYaml(source);
  final root = _asMap(doc, 'root');

  final contentScopeRaw = _asMap(root['content_scope'], 'content_scope');

  final actors = <ScenarioActor>[];
  for (final item in _asList(root['cast'], 'cast')) {
    final map = _asMap(item, 'cast[]');
    actors.add(
      ScenarioActor(
        id: _string(map['id'], 'cast[].id'),
        kind: _actorKind(map['kind'], 'cast[].kind'),
        name: _string(map['name'], 'cast[].name'),
        goal: _optString(map['goal']),
        secret: _optString(map['secret']),
        tags: _stringSet(map['tags']),
        quip: _optString(map['quip']),
        switchTrigger: _optString(map['switch_trigger']),
      ),
    );
  }

  final npcs = <ScenarioNpc>[];
  for (final item in _asList(root['npcs'], 'npcs')) {
    final map = _asMap(item, 'npcs[]');
    npcs.add(
      ScenarioNpc(
        id: _string(map['id'], 'npcs[].id'),
        name: _string(map['name'], 'npcs[].name'),
        goal: _optString(map['goal']),
        secret: _optString(map['secret']),
        tags: _stringSet(map['tags']),
      ),
    );
  }

  final scenes = <SceneDef>[];
  for (final item in _asList(root['scenes'], 'scenes')) {
    final map = _asMap(item, 'scenes[]');
    final sceneId = _string(map['id'], 'scenes[].id');

    final clocks = <SceneClock>[];
    for (final raw in _asList(map['clocks'], 'scenes[$sceneId].clocks')) {
      final clock = _asMap(raw, 'scenes[$sceneId].clocks[]');
      clocks.add(
        SceneClock(
          id: _string(clock['id'], 'clock.id'),
          label: _optString(clock['label']),
          max: _int(clock['max'], 3),
          onZero: _optString(clock['on_zero']),
        ),
      );
    }

    final clues = <SceneClue>[];
    for (final raw in _asList(map['clues'], 'scenes[$sceneId].clues')) {
      final clue = _asMap(raw, 'scenes[$sceneId].clues[]');
      clues.add(
        SceneClue(
          id: _string(clue['id'], 'clue.id'),
          text: _optString(clue['text']),
        ),
      );
    }

    final exits = <SceneExit>[];
    for (final raw in _asList(map['exits'], 'scenes[$sceneId].exits')) {
      final exit = _asMap(raw, 'scenes[$sceneId].exits[]');
      exits.add(
        SceneExit(
          id: _string(exit['id'], 'exit.id'),
          to: _optString(exit['to']),
          when: _optString(exit['when']),
        ),
      );
    }

    final checks = <SceneCheck>[];
    for (final raw in _asList(map['checks'], 'scenes[$sceneId].checks')) {
      final check = _asMap(raw, 'scenes[$sceneId].checks[]');
      final rawFumble = check['on_fumble'];
      SceneFumble? onFumble;
      if (rawFumble is Map || rawFumble is YamlMap) {
        final fumble = _asMap(rawFumble, 'scenes[$sceneId].checks[].on_fumble');
        onFumble = SceneFumble(
          ending: _optString(fumble['ending']),
          text: _optString(fumble['text']),
        );
      }
      final skillLabel = _optString(check['skill']);
      final attributeLabel = _optString(check['attribute']);
      final skill = skillLabel.isEmpty ? null : _skill(skillLabel);
      final attribute = attributeLabel.isEmpty
          ? null
          : attributeByLabel(attributeLabel);
      if (skill == null && attribute == null) {
        throw FormatException(
          'scenes[$sceneId].checks 需要 skill 或 attribute（收到 "$skillLabel" / "$attributeLabel"）',
        );
      }
      checks.add(
        SceneCheck(
          skill: skill,
          attribute: attribute,
          difficulty: _difficulty(check['difficulty']),
          stakes: _optString(check['stakes']),
          onFumble: onFumble,
        ),
      );
    }

    scenes.add(
      SceneDef(
        id: sceneId,
        name: _optString(map['name'], sceneId),
        goal: _optString(map['goal']),
        clocks: clocks,
        clues: clues,
        exits: exits,
        checks: checks,
        fixedActions: <String>[
          for (final action in _asList(
            map['fixed_actions'],
            'scenes[$sceneId].fixed_actions',
          ))
            _optString(action),
        ].where((text) => text.isNotEmpty).toList(),
        ending: map['ending'] == true,
      ),
    );
  }

  return Scenario(
    id: _string(root['id'], 'id'),
    version: _optString(root['version'], '0.0.0'),
    title: _string(root['title'], 'title'),
    subtitle: _optString(root['subtitle']),
    minutes: _optString(root['minutes']),
    rating: _optString(root['rating']),
    partyMax: _int(root['party_max'], 4),
    opening: _optString(root['opening']),
    contentScope: ContentScope.fromJson(contentScopeRaw),
    actors: actors,
    npcs: npcs,
    scenes: scenes,
  );
}

// ---------------------------------------------------------------------------
// 解析辅助
// ---------------------------------------------------------------------------

Map<String, dynamic> _asMap(Object? raw, String path) {
  if (raw is YamlMap) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('$path 应该是映射（map），实际是 ${raw.runtimeType}');
}

List<Object?> _asList(Object? raw, String path) {
  if (raw is YamlList) return raw.toList();
  if (raw is List) return raw;
  if (raw == null) return const <Object?>[];
  throw FormatException('$path 应该是列表（list），实际是 ${raw.runtimeType}');
}

String _string(Object? raw, String path) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('$path 不能为空');
  return value;
}

String _optString(Object? raw, [String fallback = '']) =>
    raw?.toString().trim() ?? fallback;

int _int(Object? raw, int fallback) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

Set<String> _stringSet(Object? raw) {
  final list = _asList(raw, 'tags');
  return list.map((item) => item.toString()).toSet();
}

ActorKindRef _actorKind(Object? raw, String path) {
  final value = _optString(raw, 'human').toLowerCase();
  return switch (value) {
    'human' || 'player' => ActorKindRef.human,
    'bp' || 'ai' => ActorKindRef.bp,
    _ => throw FormatException('$path: 未知角色类型「$value」'),
  };
}

Skill _skill(Object? raw) {
  final label = _optString(raw);
  final skill = skillByLabel(label);
  if (skill == null) {
    final known = Skill.values.map((s) => s.label).join('、');
    throw FormatException('未知技能「$label」；可用：$known');
  }
  return skill;
}

Difficulty _difficulty(Object? raw) {
  final value = _optString(raw, 'regular').toLowerCase();
  return switch (value) {
    'regular' || '普通' => Difficulty.regular,
    'hard' || '困难' => Difficulty.hard,
    'extreme' || '极难' => Difficulty.extreme,
    _ => throw FormatException('未知难度「$value」；可用：regular / hard / extreme'),
  };
}
