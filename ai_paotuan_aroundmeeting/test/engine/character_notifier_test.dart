import 'package:ai_paotuan_aroundmeeting/app/di.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer buildContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('随机分配属性：总和 460，单项 15–90', () {
    final container = buildContainer();
    final notifier = container.read(characterProvider.notifier);

    notifier.randomizeAttributes();
    final sheet = container.read(characterProvider);

    expect(sheet.attributes.total, attributeTotal);
    expect(sheet.attributes.remaining, 0);
    for (final attribute in Attribute.values) {
      expect(
        sheet.attributes[attribute],
        inInclusiveRange(attributeMin, attributeMax),
        reason: '${attribute.label} 越界',
      );
    }
  });

  test('随机分配技能：不超预算，单项 ≤ 70', () {
    final container = buildContainer();
    final notifier = container.read(characterProvider.notifier);

    notifier.randomizeSkills();
    final sheet = container.read(characterProvider);

    expect(
      sheet.skills.allocatedPoints,
      lessThanOrEqualTo(sheet.skills.budgetFor(sheet.attributes)),
    );
    expect(sheet.skills.remainingFor(sheet.attributes), 0);
    for (final skill in Skill.values.where((s) => s.isAllocatable)) {
      expect(sheet.skills[skill], lessThanOrEqualTo(skillMax));
      expect(sheet.skills[skill], greaterThanOrEqualTo(skill.baseValue));
    }
  });

  test('技能点余额为 0 时再加点不会超额（不会出现 -4）', () {
    final container = buildContainer();
    final notifier = container.read(characterProvider.notifier);

    notifier.randomizeSkills();
    final before = container.read(characterProvider).skills[Skill.persuade];

    // 模拟「剩余 0 时点了 +5」。
    notifier.setSkill(Skill.persuade, before + 5);

    final sheet = container.read(characterProvider);
    expect(sheet.skills[Skill.persuade], before);
    expect(sheet.skills.remainingFor(sheet.attributes), 0);
  });

  test('属性点余额为 0 时再加点不会超额', () {
    final container = buildContainer();
    final notifier = container.read(characterProvider.notifier);

    notifier.randomizeAttributes();
    final before = container.read(characterProvider).attributes[Attribute.str];

    notifier.setAttribute(Attribute.str, before + 5);

    final sheet = container.read(characterProvider);
    expect(sheet.attributes[Attribute.str], before);
    expect(sheet.attributes.total, attributeTotal);
  });

  test('余额只剩 1 时，加 5 只会加 1', () {
    final container = buildContainer();
    final notifier = container.read(characterProvider.notifier);

    // 先随机分满，再找一项减 1，得到「只剩 1 点」的局面。
    notifier.randomizeAttributes();
    final filled = container.read(characterProvider);
    final attribute = Attribute.values.firstWhere(
      (item) => filled.attributes[item] > attributeMin,
    );
    notifier.setAttribute(attribute, filled.attributes[attribute] - 1);

    final beforeSheet = container.read(characterProvider);
    expect(beforeSheet.attributes.remaining, 1);

    final before = beforeSheet.attributes[attribute];
    notifier.setAttribute(attribute, before + 5);

    final sheet = container.read(characterProvider);
    expect(sheet.attributes[attribute], before + 1);
    expect(sheet.attributes.total, attributeTotal);
  });
}
