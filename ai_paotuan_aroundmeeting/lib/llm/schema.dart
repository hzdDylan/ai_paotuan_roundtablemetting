import '../engine/moderation/moderation.dart';
import '../engine/rules/character_rules.dart';
import '../engine/rules/check.dart';
import '../engine/turn/action_suggestion.dart';
import '../engine/turn/actor_turn.dart';
import '../engine/turn/kp_turn.dart';

/// 输出不合规。
class SchemaException implements Exception {
  const SchemaException(this.message);

  final String message;

  @override
  String toString() => 'SchemaException: $message';
}

const List<String> _forbiddenPhrases = <String>[
  '作为AI',
  '作为 AI',
  '我是AI',
  '语言模型',
  '系统提示',
  '提示词',
];

const int _maxSpeechLength = 400;
const int _maxNarrationLength = 500;

/// 解析 BP 输出（SE §4.10）。
ActorTurn parseBpTurn(
  Map<String, dynamic> json, {
  required String selfName,
  required Set<String> knownNames,
}) {
  final speech = (json['speech'] as String? ?? '').trim();
  if (speech.isEmpty) throw const SchemaException('缺少 speech');
  _guardForbidden(speech);

  Skill? skill;
  final wantsCheck = json['wants_check'];
  if (wantsCheck is Map) {
    final label = wantsCheck['skill']?.toString().trim() ?? '';
    if (label.isNotEmpty) {
      skill = skillByLabel(label);
      if (skill == null) throw SchemaException('未知技能「$label」');
      if (!skill.isAllocatable) {
        throw SchemaException('${skill.label} 不可主动申请检定');
      }
    }
  }

  final target = (json['target'] as String? ?? '').trim();

  return ActorTurn(
    speech: _clip(speech, _maxSpeechLength),
    action: (json['action'] as String? ?? '').trim(),
    intent: TurnIntentInfo.parse(json['intent'] as String?),
    target: target,
    wantsCheckSkill: skill,
    privateNote: (json['private_note'] as String? ?? '').trim(),
  );
}

/// 解析 KP 输出。
///
/// 模型经常把行动者写成 `player` / `玩家` / `你`，所以这里做一次别名归一；
/// 仍然认不出来时不抛错，只是放弃这次检定（避免整拍崩掉）。
KpTurn parseKpTurn(
  Map<String, dynamic> json, {
  required Set<String> npcNames,
  required Set<String> actorIds,
  Set<String> sceneIds = const <String>{},
  String humanId = 'human',
}) {
  final narratorText = (json['narration'] as String? ?? '').trim();
  final npcLines = _parseNpcLines(json['npc_lines'], npcNames);

  if (narratorText.isEmpty && npcLines.isEmpty) {
    throw const SchemaException('KP 既没有旁白也没有 NPC 台词');
  }
  _guardForbidden(narratorText);
  for (final line in npcLines) {
    _guardForbidden(line.line);
  }

  final checks = <CheckDecl>[];
  final rawChecks = json['checks'];
  if (rawChecks is List) {
    for (final item in rawChecks) {
      if (item is! Map) continue;
      final decl = _parseDecl(item, actorIds: actorIds, humanId: humanId);
      if (decl != null) checks.add(decl);
    }
  }
  // 兼容只返回单个 check 的模型。
  if (checks.isEmpty) {
    final rawCheck = json['check'];
    if (rawCheck is Map) {
      final decl = _parseDecl(rawCheck, actorIds: actorIds, humanId: humanId);
      if (decl != null) checks.add(decl);
    }
  }

  final scene = _parseScene(json['scene']?.toString(), sceneIds);
  return KpTurn(
    narration: _clip(narratorText, _maxNarrationLength),
    npcLines: npcLines,
    checks: checks,
    state: _parseState(json['state']),
    signal: scene.signal,
    nextSceneId: scene.nextSceneId,
  );
}

CheckDecl? _parseDecl(
  Map<Object?, Object?> raw, {
  required Set<String> actorIds,
  required String humanId,
}) {
  final actorId = _resolveActorId(
    raw['actor']?.toString().trim() ?? '',
    actorIds,
    humanId,
  );
  if (actorId == null) return null;

  final skill = skillByLabel(raw['skill']?.toString().trim() ?? '');
  final attribute = attributeByLabel(raw['attribute']?.toString().trim() ?? '');
  if (skill == null && attribute == null) return null;
  // 神话没有基础值，不适合作为检定。
  if (skill == Skill.mythos) return null;

  return CheckDecl(
    actorId: actorId,
    skill: skill,
    attribute: skill == null ? attribute : null,
    difficulty: parseDifficulty(raw['difficulty']?.toString()),
    stakes: (raw['stakes'] as String? ?? '').trim(),
  );
}

String? _resolveActorId(String raw, Set<String> actorIds, String humanId) {
  if (raw.isEmpty) return null;
  if (actorIds.contains(raw)) return raw;

  final lower = raw.toLowerCase();
  const humanAliases = <String>{
    'player',
    'human',
    'pc',
    '玩家',
    '你',
    '主角',
    '调查员',
  };
  if (humanAliases.contains(lower) || humanAliases.contains(raw)) {
    return actorIds.contains(humanId) ? humanId : null;
  }
  return null;
}

/// 解析骰后叙述。
KpNarration parseKpNarration(
  Map<String, dynamic> json, {
  required Set<String> npcNames,
  Set<String> sceneIds = const <String>{},
}) {
  final narration = (json['narration'] as String? ?? '').trim();
  final npcLines = _parseNpcLines(json['npc_lines'], npcNames);
  if (narration.isEmpty && npcLines.isEmpty) {
    throw const SchemaException('叙述为空');
  }
  _guardForbidden(narration);

  final scene = _parseScene(json['scene']?.toString(), sceneIds);
  return KpNarration(
    narration: _clip(narration, _maxNarrationLength),
    npcLines: npcLines,
    state: _parseState(json['state']),
    signal: scene.signal,
    nextSceneId: scene.nextSceneId,
  );
}

/// 解析 LLM 给玩家的行动建议。
///
/// 不合规的条目会被跳过；只有 1 条也接受（先让玩家有得选）。
List<ActionSuggestion> parseActionSuggestions(Map<String, dynamic> json) {
  final raw = json['actions'] ?? json['suggestions'];
  if (raw is! List) return const <ActionSuggestion>[];
  final result = <ActionSuggestion>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final text = (item['text']?.toString() ?? '').trim();
    if (text.isEmpty || seen.contains(text)) continue;
    try {
      _guardForbidden(text);
    } on SchemaException {
      continue;
    }

    Skill? skill;
    final skillLabel = (item['skill']?.toString() ?? '').trim();
    if (skillLabel.isNotEmpty) {
      skill = skillByLabel(skillLabel);
      if (skill == Skill.mythos) skill = null;
    }
    Attribute? attribute;
    if (skill == null) {
      final attributeLabel = (item['attribute']?.toString() ?? '').trim();
      if (attributeLabel.isNotEmpty) {
        attribute = attributeByLabel(attributeLabel);
      }
    }

    seen.add(text);
    result.add(
      ActionSuggestion(
        text: _clip(text, 80),
        skill: skill,
        attribute: attribute,
      ),
    );
    if (result.length >= 4) break;
  }
  return result;
}

/// 解析审核输出。
ModerationVerdict parseModerationVerdict(Map<String, dynamic> json) {
  final raw = (json['verdict'] as String? ?? '').toLowerCase();
  return switch (raw) {
    'allow' => ModerationVerdict.allow,
    'reject' => ModerationVerdict.reject,
    _ => ModerationVerdict.reject,
  };
}

ModerationCategory parseModerationCategory(Object? raw) {
  final value = (raw?.toString() ?? '').toLowerCase();
  for (final category in ModerationCategory.values) {
    if (category.name.toLowerCase() == value) return category;
  }
  return ModerationCategory.none;
}

Difficulty parseDifficulty(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  return switch (value) {
    'hard' || '困难' => Difficulty.hard,
    'extreme' || '极难' => Difficulty.extreme,
    _ => Difficulty.regular,
  };
}

SceneSignal parseSceneSignal(String? raw) {
  return switch ((raw ?? '').trim().toLowerCase()) {
    'end' || 'end_scene' || '结束' => SceneSignal.endScene,
    'transition' || '转场' => SceneSignal.transition,
    _ => SceneSignal.continueRun,
  };
}

class _SceneDirective {
  const _SceneDirective(this.signal, this.nextSceneId);

  final SceneSignal signal;
  final String? nextSceneId;
}

/// `scene` 既可能是 continue/end，也可能直接是下一幕的 id。
_SceneDirective _parseScene(String? raw, Set<String> sceneIds) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) {
    return const _SceneDirective(SceneSignal.continueRun, null);
  }
  if (sceneIds.contains(value)) {
    return _SceneDirective(SceneSignal.transition, value);
  }
  return _SceneDirective(parseSceneSignal(value), null);
}

List<KpNpcLine> _parseNpcLines(Object? raw, Set<String> npcNames) {
  if (raw is! List) return const <KpNpcLine>[];
  final lines = <KpNpcLine>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['npc']?.toString().trim() ?? '';
    final line = item['line']?.toString().trim() ?? '';
    if (name.isEmpty || line.isEmpty) continue;
    if (!npcNames.contains(name)) {
      throw SchemaException('NPC「$name」不在剧本里');
    }
    lines.add(
      KpNpcLine(
        npc: name,
        line: _clip(line, 120),
        attitudeDelta: (item['attitude_delta'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return lines;
}

KpStateDelta _parseState(Object? raw) {
  if (raw is! Map) return const KpStateDelta();

  final clocks = <ClockDelta>[];
  final rawClocks = raw['clocks'];
  if (rawClocks is List) {
    for (final item in rawClocks) {
      if (item is! Map) continue;
      final id = item['id']?.toString().trim() ?? '';
      final delta = (item['delta'] as num?)?.toInt() ?? 0;
      if (id.isNotEmpty && delta != 0) {
        clocks.add(ClockDelta(id: id, delta: delta));
      }
    }
  }

  final clues = <String>[];
  final rawClues = raw['clues'];
  if (rawClues is List) {
    for (final item in rawClues) {
      final id = item?.toString().trim() ?? '';
      if (id.isNotEmpty) clues.add(id);
    }
  }

  final flags = <String>[];
  final rawFlags = raw['flags'];
  if (rawFlags is List) {
    for (final item in rawFlags) {
      final flag = item?.toString().trim() ?? '';
      if (flag.isNotEmpty) flags.add(flag);
    }
  }

  return KpStateDelta(clocks: clocks, clues: clues, flags: flags);
}

void _guardForbidden(String text) {
  for (final phrase in _forbiddenPhrases) {
    if (text.contains(phrase)) {
      throw SchemaException('出现禁语「$phrase」');
    }
  }
}

String _clip(String text, int maxLength) =>
    text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';
