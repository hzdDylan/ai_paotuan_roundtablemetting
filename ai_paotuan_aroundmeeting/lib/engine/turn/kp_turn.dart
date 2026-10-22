import '../rules/character_rules.dart';
import '../rules/check.dart';

/// KP 扮演的 NPC 台词。
class KpNpcLine {
  const KpNpcLine({
    required this.npc,
    required this.line,
    this.attitudeDelta = 0,
  });

  final String npc;
  final String line;
  final int attitudeDelta;
}

/// 时钟变化。
class ClockDelta {
  const ClockDelta({required this.id, required this.delta});

  final String id;
  final int delta;
}

/// KP 对世界状态的修改（SE §4.10）。
class KpStateDelta {
  const KpStateDelta({
    this.clocks = const <ClockDelta>[],
    this.clues = const <String>[],
    this.flags = const <String>[],
  });

  final List<ClockDelta> clocks;
  final List<String> clues;

  /// 剧本标记：由 KP 根据剧情授予，用于打开后续场景出口。
  final List<String> flags;

  bool get isEmpty => clocks.isEmpty && clues.isEmpty && flags.isEmpty;
}

/// 场景信号。
enum SceneSignal { continueRun, endScene, transition }

/// KP 的一轮输出。
class KpTurn {
  const KpTurn({
    required this.narration,
    this.npcLines = const <KpNpcLine>[],
    this.checks = const <CheckDecl>[],
    this.state = const KpStateDelta(),
    this.signal = SceneSignal.continueRun,
    this.nextSceneId,
  });

  final String narration;
  final List<KpNpcLine> npcLines;

  /// 这一拍要发起的检定；一句话里多个动作会有多条。
  final List<CheckDecl> checks;

  /// 单检定的便捷读取。
  CheckDecl? get check => checks.isEmpty ? null : checks.first;

  final KpStateDelta state;
  final SceneSignal signal;

  /// `scene` 填了合法场景 id 时，目标场景；否则为空。
  final String? nextSceneId;

  String get displayText {
    final buffer = StringBuffer();
    if (narration.isNotEmpty) buffer.write(narration);
    for (final line in npcLines) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('${line.npc}：「${line.line}」');
    }
    return buffer.toString();
  }
}

/// 骰值落定后，KP 的叙述输出。
class KpNarration {
  const KpNarration({
    required this.narration,
    this.npcLines = const <KpNpcLine>[],
    this.state = const KpStateDelta(),
    this.signal = SceneSignal.continueRun,
    this.nextSceneId,
  });

  final String narration;
  final List<KpNpcLine> npcLines;
  final KpStateDelta state;
  final SceneSignal signal;

  /// `scene` 填了合法场景 id 时，目标场景；否则为空。
  final String? nextSceneId;

  String get displayText {
    final buffer = StringBuffer();
    if (narration.isNotEmpty) buffer.write(narration);
    for (final line in npcLines) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('${line.npc}：「${line.line}」');
    }
    return buffer.toString();
  }
}

/// 常用技能标签，供 prompt 列出。
String skillLabelsForPrompt() => Skill.values
    .where((skill) => skill.isAllocatable)
    .map((skill) => skill.label)
    .join('、');
