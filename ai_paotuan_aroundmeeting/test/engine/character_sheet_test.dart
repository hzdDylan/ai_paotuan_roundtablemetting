import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_sheet.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/skills.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('新角色：属性总和 400，还差 150 点', () {
    final sheet = CharacterSheet.fresh();
    expect(sheet.attributes.total, 400);
    expect(sheet.attributes.remaining, 150);
    expect(
      sheet.validate().any((error) => error.contains('550')),
      isTrue,
      reason: '未分配完 150 点时，保存应被拦下',
    );
  });

  test('分配满 150 点后属性校验通过', () {
    var sheet = CharacterSheet.fresh().copyWith(name: 'Joe');
    sheet = sheet.withAttribute(Attribute.str, 90); // +40
    sheet = sheet.withAttribute(Attribute.dex, 90); // +40
    sheet = sheet.withAttribute(Attribute.con, 90); // +40
    sheet = sheet.withAttribute(Attribute.pow, 80); // +30

    expect(sheet.attributes.total, 550);
    expect(sheet.attributes.remaining, 0);
    expect(sheet.validate(), isEmpty);
  });

  test('属性越界会被夹到 15–90', () {
    final sheet = CharacterSheet.fresh()
        .withAttribute(Attribute.str, 999)
        .withAttribute(Attribute.con, -5);
    expect(sheet.attributes[Attribute.str], 90);
    expect(sheet.attributes[Attribute.con], 15);
  });

  test('派生值：HP / MP / SAN', () {
    final sheet = CharacterSheet.fresh();
    expect(sheet.hp, 15); // 体质 50 ÷ 5 + 5
    expect(sheet.mp, 10); // 意志 50 ÷ 5
    expect(sheet.sanMax, 50);
  });

  test('技能点预算 = 智力 × 6', () {
    final sheet = CharacterSheet.fresh().copyWith(name: 'Joe');
    expect(sheet.skills.budgetFor(sheet.attributes), 300);

    // 从「基础值」开始算，避免把初卡的默认分配算进去。
    final base = sheet.copyWith(skills: Skills.initial(sheet.attributes));

    // 六项拉到 70：45 + 50 + 50 + 50 + 60 + 60 = 315，超预算。
    final overspent = base
        .withSkill(Skill.spotHidden, 70)
        .withSkill(Skill.listen, 70)
        .withSkill(Skill.libraryUse, 70)
        .withSkill(Skill.stealth, 70)
        .withSkill(Skill.psychology, 70)
        .withSkill(Skill.sleightOfHand, 70);
    expect(overspent.skills.allocatedPoints, 315);
    expect(
      overspent.validate().any((error) => error.contains('技能点超出')),
      isTrue,
    );
  });

  test('技能点刚好用满时通过', () {
    var sheet = CharacterSheet.fresh().copyWith(name: 'Joe');
    sheet = sheet.withAttribute(Attribute.str, 90);
    sheet = sheet.withAttribute(Attribute.dex, 90);
    sheet = sheet.withAttribute(Attribute.con, 90);
    sheet = sheet.withAttribute(Attribute.pow, 80);
    final base = sheet.copyWith(skills: Skills.initial(sheet.attributes));
    final spent = base
        .withSkill(Skill.spotHidden, 70) // 45
        .withSkill(Skill.listen, 70) // 50
        .withSkill(Skill.libraryUse, 70) // 50
        .withSkill(Skill.stealth, 70) // 50
        .withSkill(Skill.psychology, 70) // 60
        .withSkill(Skill.persuade, 50); // 45 → 合计 300
    expect(spent.skills.allocatedPoints, 300);
    expect(spent.validate(), isEmpty);
  });

  test('初卡技能默认每项 25 点，话术不再是 5', () {
    final sheet = CharacterSheet.fresh();
    for (final skill in Skill.values.where((s) => s.isAllocatable)) {
      expect(sheet.skills[skill], 25, reason: skill.label);
    }
    expect(sheet.skills[Skill.persuade], 25);
    // 预算 300，已用 65，还剩 235 给玩家自己加。
    expect(sheet.skills.remainingFor(sheet.attributes), 235);
  });

  test('神话与闪避不可分配', () {
    final sheet = CharacterSheet.fresh().withSkill(Skill.mythos, 40);
    expect(sheet.skills[Skill.mythos], 0);
  });

  test('姓名与物品上限', () {
    final longName = CharacterSheet.fresh().copyWith(name: '一二三四五六七八九十十一十二十三');
    expect(longName.validate().any((error) => error.contains('姓名不超过')), isTrue);

    final tooManyItems = CharacterSheet.fresh().copyWith(
      items: List<Item>.generate(6, (index) => Item(name: '物品$index')),
    );
    expect(
      tooManyItems.validate().any((error) => error.contains('最多')),
      isTrue,
    );
  });

  test('SAN 不能超过意志，也不能为负', () {
    final over = CharacterSheet.fresh().copyWith(sanCurrent: 60);
    expect(over.validate().any((error) => error.contains('SAN')), isTrue);

    final negative = CharacterSheet.fresh().copyWith(sanCurrent: -1);
    expect(negative.validate().any((error) => error.contains('SAN')), isTrue);
  });

  test('JSON 往返保持数值', () {
    final sheet = CharacterSheet.fresh().copyWith(
      name: 'Joe',
      items: const [Item(name: '笔记本', note: '记东西')],
    );
    final restored = CharacterSheet.fromJson(sheet.toJson());
    expect(restored.name, 'Joe');
    expect(restored.attributes.total, sheet.attributes.total);
    expect(restored.skills[Skill.spotHidden], sheet.skills[Skill.spotHidden]);
    expect(restored.items.single.name, '笔记本');
  });
}
