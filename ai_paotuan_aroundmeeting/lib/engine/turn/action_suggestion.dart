import '../rules/character_rules.dart';

/// LLM 根据当前场景给玩家的推荐行动。
///
/// 每条都附一个最合适的检定依据：技能或基础属性，二选一。
class ActionSuggestion {
  const ActionSuggestion({required this.text, this.skill, this.attribute});

  final String text;
  final Skill? skill;
  final Attribute? attribute;

  String get checkLabel => skill?.label ?? attribute?.label ?? '';

  bool get hasCheck => checkLabel.isNotEmpty;
}
