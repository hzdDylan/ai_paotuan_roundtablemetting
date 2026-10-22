import 'attributes.dart';
import 'character_rules.dart';
import 'skills.dart';

/// 随身物品（SE §3.7，上限 5 格）。
class Item {
  const Item({required this.name, this.note = ''});

  factory Item.fromJson(Map<String, dynamic> json) => Item(
    name: json['name'] as String? ?? '',
    note: json['note'] as String? ?? '',
  );

  final String name;
  final String note;

  Item copyWith({String? name, String? note}) =>
      Item(name: name ?? this.name, note: note ?? this.note);

  Map<String, dynamic> toJson() => {'name': name, 'note': note};
}

/// 角色卡（SE §3.7）。不可变；所有修改都返回新实例。
class CharacterSheet {
  CharacterSheet({
    required this.name,
    required this.occupation,
    required this.age,
    required this.attributes,
    required this.skills,
    required List<Item> items,
    required this.sanCurrent,
  }) : items = List<Item>.unmodifiable(items);

  /// 空白角色：属性全 50、技能平均分配、SAN = 意志。
  factory CharacterSheet.fresh() {
    final attributes = Attributes.initial();
    final skills = Skills.evenlyAllocated(attributes);
    return CharacterSheet(
      name: '',
      occupation: '记者',
      age: 28,
      attributes: attributes,
      skills: skills,
      items: const [],
      sanCurrent: sanMaxFor(attributes[Attribute.pow]),
    );
  }

  final String name;
  final String occupation;
  final int age;
  final Attributes attributes;
  final Skills skills;
  final List<Item> items;

  /// 当前 SAN：可损，上限为意志（Q-03）。
  final int sanCurrent;

  int get hp => hpFor(attributes[Attribute.con]);

  int get mp => mpFor(attributes[Attribute.pow]);

  int get sanMax => sanMaxFor(attributes[Attribute.pow]);

  /// 通用头像的首字符（V-8：不做自定义头像）。
  String get avatarInitial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  /// 通用头像的颜色种子，保证同名角色颜色稳定。
  int get avatarColorSeed => name.trim().hashCode;

  CharacterSheet copyWith({
    String? name,
    String? occupation,
    int? age,
    Attributes? attributes,
    Skills? skills,
    List<Item>? items,
    int? sanCurrent,
  }) => CharacterSheet(
    name: name ?? this.name,
    occupation: occupation ?? this.occupation,
    age: age ?? this.age,
    attributes: attributes ?? this.attributes,
    skills: skills ?? this.skills,
    items: items ?? this.items,
    sanCurrent: sanCurrent ?? this.sanCurrent,
  );

  /// 改属性（SAN 上限随意志钳制）。
  CharacterSheet withAttribute(Attribute attribute, int value) {
    final nextAttributes = attributes.withValue(attribute, value);
    return copyWith(
      attributes: nextAttributes,
      // 意志下降不自动扣 SAN（SAN 可独立受损），但意志上升时给回上限。
      sanCurrent: sanCurrent > sanMaxFor(nextAttributes[Attribute.pow])
          ? sanMaxFor(nextAttributes[Attribute.pow])
          : sanCurrent,
    );
  }

  CharacterSheet withSkill(Skill skill, int value) =>
      copyWith(skills: skills.withValue(skill, value));

  CharacterSheet withItemAt(int index, Item item) {
    if (index < 0 || index >= itemSlots) return this;
    final next = [...items];
    if (index < next.length) {
      next[index] = item;
    } else {
      next.add(item);
    }
    return copyWith(items: next);
  }

  CharacterSheet removeItemAt(int index) {
    if (index < 0 || index >= items.length) return this;
    final next = [...items]..removeAt(index);
    return copyWith(items: next);
  }

  /// 保存前校验；返回空列表表示可以保存（SE §3.7）。
  List<String> validate() {
    final errors = <String>[];

    if (name.trim().isEmpty) {
      errors.add('请填写姓名');
    } else if (name.trim().length > maxNameLength) {
      errors.add('姓名不超过 $maxNameLength 字');
    }

    if (occupation.trim().isEmpty) {
      errors.add('请填写职业');
    } else if (occupation.trim().length > maxOccupationLength) {
      errors.add('职业不超过 $maxOccupationLength 字');
    }

    if (age < minAge || age > maxAge) {
      errors.add('年龄需在 $minAge–$maxAge 之间');
    }

    if (attributes.total != attributeTotal) {
      errors.add(
        '属性总和需为 $attributeTotal，当前 ${attributes.total}'
        '（${attributes.remaining >= 0 ? '还差 ${attributes.remaining}' : '超出 ${-attributes.remaining}'}）',
      );
    }

    errors.addAll(skills.validate(attributes));

    if (items.length > itemSlots) {
      errors.add('随身物品最多 $itemSlots 件');
    }

    if (sanCurrent < 0 || sanCurrent > sanMax) {
      errors.add('SAN 需在 0–$sanMax 之间');
    }

    return errors;
  }

  bool get isReadyToPlay => validate().isEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'occupation': occupation,
    'age': age,
    'attributes': attributes.toJson(),
    'skills': skills.toJson(),
    'items': items.map((item) => item.toJson()).toList(),
    'sanCurrent': sanCurrent,
  };

  factory CharacterSheet.fromJson(Map<String, dynamic> json) {
    final attributes = Attributes.fromJson(
      json['attributes'] as Map<String, dynamic>? ?? {},
    );
    return CharacterSheet(
      name: json['name'] as String? ?? '',
      occupation: json['occupation'] as String? ?? '',
      age: (json['age'] as num?)?.toInt() ?? 28,
      attributes: attributes,
      skills: Skills.fromJson(
        json['skills'] as Map<String, dynamic>? ?? {},
        attributes,
      ),
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => Item.fromJson(item as Map<String, dynamic>))
          .toList(),
      sanCurrent:
          (json['sanCurrent'] as num?)?.toInt() ??
          sanMaxFor(attributes[Attribute.pow]),
    );
  }
}
