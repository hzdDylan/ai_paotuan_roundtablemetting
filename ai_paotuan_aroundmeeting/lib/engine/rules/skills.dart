import 'dart:math' as math;

import 'attributes.dart';
import 'character_rules.dart';

/// 9 项技能，不可变值对象（SE §3.7）。
///
/// 规则：
/// - 可分配项（除神话）上限 70；
/// - 技能点 = 智力 × 2；
/// - 闪避是派生值，永远等于 `敏捷 ÷ 2`（向下取整），不参与分配；
/// - 神话只能通过接触神话获得，不参与分配。
class Skills {
  Skills(Map<Skill, int> values)
    : _values = Map<Skill, int>.unmodifiable({
        for (final skill in Skill.values)
          skill: _sanitize(skill, values[skill] ?? skill.baseValue),
      });

  factory Skills.initial(Attributes attributes) {
    final values = <Skill, int>{
      for (final skill in Skill.values) skill: skill.baseValue,
    };
    return Skills(values);
  }

  /// 新角色默认值：7 项可分配技能统一 25 点。
  ///
  /// 剩下的预算留给玩家自己加；避免初卡出现话术 5 这种没法用的情况。
  factory Skills.evenlyAllocated(Attributes attributes) {
    final values = <Skill, int>{
      for (final skill in Skill.values) skill: skill.baseValue,
    };
    for (final skill in Skill.values.where((skill) => skill.isAllocatable)) {
      values[skill] = math.min(25, skillMax);
    }
    return Skills(values);
  }

  factory Skills.fromJson(Map<String, dynamic> json, Attributes attributes) {
    final values = <Skill, int>{};
    for (final skill in Skill.values) {
      final raw = json[skill.label] ?? json[skill.name];
      values[skill] = (raw as num?)?.toInt() ?? skill.baseValue;
    }
    return Skills(values);
  }

  final Map<Skill, int> _values;

  static int _sanitize(Skill skill, int value) {
    if (skill.isAllocatable) {
      return math.min(math.max(value, 0), skillMax);
    }
    // 神话理论上不超过 99。
    return math.min(math.max(value, 0), 99);
  }

  int operator [](Skill skill) => _values[skill] ?? skill.baseValue;

  /// 已花掉的技能点（只算可分配项相对基础值的增量）。
  int get allocatedPoints => Skill.values
      .where((skill) => skill.isAllocatable)
      .fold(
        0,
        (sum, skill) => sum + math.max(0, this[skill] - skill.baseValue),
      );

  int budgetFor(Attributes attributes) =>
      attributes[Attribute.intel] * skillPointsPerInt;

  int remainingFor(Attributes attributes) =>
      budgetFor(attributes) - allocatedPoints;

  /// 只能分配可分配项；神话会被忽略。
  Skills withValue(Skill skill, int value) {
    if (!skill.isAllocatable) return this;
    return Skills({..._values, skill: value});
  }

  Skills withDelta(Skill skill, int delta) =>
      withValue(skill, this[skill] + delta);

  List<String> validate(Attributes attributes) {
    final errors = <String>[];
    final budget = budgetFor(attributes);
    if (allocatedPoints > budget) {
      errors.add('技能点超出：已用 $allocatedPoints / 上限 $budget');
    }
    for (final skill in Skill.values.where((s) => s.isAllocatable)) {
      if (this[skill] > skillMax) {
        errors.add('${skill.label} 超过上限 $skillMax');
      }
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
    for (final skill in Skill.values) skill.label: this[skill],
  };

  @override
  bool operator ==(Object other) {
    if (other is! Skills) return false;
    return Skill.values.every((skill) => other[skill] == this[skill]);
  }

  @override
  int get hashCode => Object.hashAll(Skill.values.map((skill) => this[skill]));
}
