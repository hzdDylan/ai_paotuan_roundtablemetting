import '../rules/character_rules.dart';

/// 一次发言的意图，用于评估与高光识别（SE §9.7）。
enum TurnIntent { persuade, probe, refuse, taunt, shift, act, observe }

extension TurnIntentInfo on TurnIntent {
  String get label => switch (this) {
    TurnIntent.persuade => '说服',
    TurnIntent.probe => '试探',
    TurnIntent.refuse => '拒绝',
    TurnIntent.taunt => '吐槽',
    TurnIntent.shift => '善变',
    TurnIntent.act => '行动',
    TurnIntent.observe => '观察',
  };

  static TurnIntent parse(String? raw, {TurnIntent fallback = TurnIntent.act}) {
    if (raw == null) return fallback;
    for (final intent in TurnIntent.values) {
      if (intent.name == raw) return intent;
    }
    return fallback;
  }
}

/// 一个行动者的本轮输出（对应 §4.10 的 BP schema）。
class ActorTurn {
  const ActorTurn({
    required this.speech,
    this.action = '',
    this.intent = TurnIntent.act,
    this.target = '',
    this.wantsCheckSkill,
    this.privateNote = '',
  });

  factory ActorTurn.fromJson(Map<String, dynamic> json) => ActorTurn(
    speech: json['speech'] as String? ?? '',
    action: json['action'] as String? ?? '',
    intent: TurnIntentInfo.parse(json['intent'] as String?),
    target: json['target'] as String? ?? '',
    wantsCheckSkill: _skillFromJson(json['wants_check']),
    privateNote: json['private_note'] as String? ?? '',
  );

  final String speech;
  final String action;
  final TurnIntent intent;
  final String target;

  /// 非空表示这个行动者想发起检定（由 KP 决定难度与代价）。
  final Skill? wantsCheckSkill;

  final String privateNote;

  bool get wantsCheck => wantsCheckSkill != null;

  static Skill? _skillFromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['skill']?.toString() ?? '';
    return skillByLabel(label);
  }

  Map<String, dynamic> toJson() => {
    'speech': speech,
    'action': action,
    'intent': intent.name,
    'target': target,
    if (wantsCheckSkill != null)
      'wants_check': {'skill': wantsCheckSkill!.label},
    'private_note': privateNote,
  };
}
