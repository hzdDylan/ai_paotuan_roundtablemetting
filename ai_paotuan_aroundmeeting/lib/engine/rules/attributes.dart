import 'dart:math' as math;

import 'character_rules.dart';

/// 8 项基础属性，不可变值对象（SE §3.7）。
///
/// 构造时会把每项夹到 15–90，避免 UI 传进脏值。
class Attributes {
  Attributes(Map<Attribute, int> values)
    : _values = Map<Attribute, int>.unmodifiable({
        for (final attribute in Attribute.values)
          attribute: math.min(
            math.max(values[attribute] ?? attributeBase, attributeMin),
            attributeMax,
          ),
      });

  /// 新角色的初始值：8 项各 50，共 400，余 60 点可分配。
  factory Attributes.initial() => Attributes({
    for (final attribute in Attribute.values) attribute: attributeBase,
  });

  factory Attributes.fromJson(Map<String, dynamic> json) => Attributes({
    for (final attribute in Attribute.values)
      attribute: (json[attribute.name] as num?)?.toInt() ?? attributeBase,
  });

  final Map<Attribute, int> _values;

  int operator [](Attribute attribute) => _values[attribute] ?? attributeBase;

  /// 8 项之和，目标值 460。
  int get total =>
      Attribute.values.fold(0, (sum, attribute) => sum + this[attribute]);

  /// 已分配点数（相对 8 × 50 的基线）。
  int get spent => total - attributeBase * attributeCount;

  /// 还能分配多少（负数表示超支）。
  int get remaining => attributeTotal - total;

  bool get isValid =>
      total == attributeTotal &&
      Attribute.values.every(
        (attribute) =>
            this[attribute] >= attributeMin && this[attribute] <= attributeMax,
      );

  Attributes withValue(Attribute attribute, int value) =>
      Attributes({..._values, attribute: value});

  Attributes withDelta(Attribute attribute, int delta) =>
      withValue(attribute, this[attribute] + delta);

  Map<String, dynamic> toJson() => {
    for (final attribute in Attribute.values) attribute.name: this[attribute],
  };

  @override
  bool operator ==(Object other) {
    if (other is! Attributes) return false;
    return Attribute.values.every(
      (attribute) => other[attribute] == this[attribute],
    );
  }

  @override
  int get hashCode =>
      Object.hashAll(Attribute.values.map((attribute) => this[attribute]));

  @override
  String toString() => 'Attributes(${toJson()})';
}
