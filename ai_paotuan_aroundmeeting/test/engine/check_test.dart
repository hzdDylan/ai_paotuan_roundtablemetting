import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('targetFor：难度折扣', () {
    test('普通 = 技能值', () {
      expect(targetFor(65, Difficulty.regular), 65);
    });
    test('困难 = 一半（向下取整）', () {
      expect(targetFor(65, Difficulty.hard), 32);
    });
    test('极难 = 五分之一（向下取整）', () {
      expect(targetFor(65, Difficulty.extreme), 13);
    });
  });

  group('宽档（基础技能 ≥ 50）', () {
    test('1–5 是大成功', () {
      for (var die = 1; die <= 5; die++) {
        expect(
          judge(die: die, baseSkill: 80, difficulty: Difficulty.regular),
          Outcome.critical,
          reason: 'die=$die',
        );
      }
    });
    test('6–80 是成功', () {
      for (var die = 6; die <= 80; die++) {
        expect(
          judge(die: die, baseSkill: 80, difficulty: Difficulty.regular),
          Outcome.success,
          reason: 'die=$die',
        );
      }
    });
    test('81–99 是失败', () {
      for (var die = 81; die <= 99; die++) {
        expect(
          judge(die: die, baseSkill: 80, difficulty: Difficulty.regular),
          Outcome.fail,
          reason: 'die=$die',
        );
      }
    });
    test('100 才是大失败', () {
      expect(
        judge(die: 100, baseSkill: 80, difficulty: Difficulty.regular),
        Outcome.fumble,
      );
    });
  });

  group('窄档（基础技能 < 50）', () {
    test('只有 1 是大成功', () {
      expect(
        judge(die: 1, baseSkill: 40, difficulty: Difficulty.regular),
        Outcome.critical,
      );
      for (var die = 2; die <= 5; die++) {
        expect(
          judge(die: die, baseSkill: 40, difficulty: Difficulty.regular),
          isNot(Outcome.critical),
          reason: 'die=$die',
        );
      }
    });
    test('2–40 成功，41–95 失败', () {
      expect(
        judge(die: 2, baseSkill: 40, difficulty: Difficulty.regular),
        Outcome.success,
      );
      expect(
        judge(die: 40, baseSkill: 40, difficulty: Difficulty.regular),
        Outcome.success,
      );
      expect(
        judge(die: 41, baseSkill: 40, difficulty: Difficulty.regular),
        Outcome.fail,
      );
      expect(
        judge(die: 95, baseSkill: 40, difficulty: Difficulty.regular),
        Outcome.fail,
      );
    });
    test('96–100 全是大失败', () {
      for (var die = 96; die <= 100; die++) {
        expect(
          judge(die: die, baseSkill: 40, difficulty: Difficulty.regular),
          Outcome.fumble,
          reason: 'die=$die',
        );
      }
    });
  });

  test('档位按基础技能切换（49 窄档 / 50 宽档）', () {
    expect(isWideTier(49), isFalse);
    expect(isWideTier(50), isTrue);
    // die=96：窄档大失败；宽档只是普通失败（仍可能命中大成功区间之外）。
    expect(
      judge(die: 96, baseSkill: 49, difficulty: Difficulty.regular),
      Outcome.fumble,
    );
    expect(
      judge(die: 96, baseSkill: 50, difficulty: Difficulty.regular),
      Outcome.fail,
    );
    // die=3：宽档大成功；窄档普通成功。
    expect(
      judge(die: 3, baseSkill: 50, difficulty: Difficulty.regular),
      Outcome.critical,
    );
    expect(
      judge(die: 3, baseSkill: 49, difficulty: Difficulty.regular),
      Outcome.success,
    );
  });

  test('目标 ≤ 0 恒失败，且不给大成功', () {
    expect(
      judge(die: 1, baseSkill: 0, difficulty: Difficulty.regular),
      Outcome.fail,
    );
    expect(
      judge(die: 1, baseSkill: 3, difficulty: Difficulty.extreme),
      Outcome.fail,
    );
  });

  test('非法骰值抛 ArgumentError', () {
    expect(
      () => judge(die: 0, baseSkill: 50, difficulty: Difficulty.regular),
      throwsArgumentError,
    );
    expect(
      () => judge(die: 101, baseSkill: 50, difficulty: Difficulty.regular),
      throwsArgumentError,
    );
  });

  test('resolveCheck 记录基础技能、目标与结果', () {
    const decl = CheckDecl(
      actorId: 'bp_stella',
      skill: Skill.persuade,
      difficulty: Difficulty.hard,
      stakes: '失败则他礼貌拒绝',
    );
    final roll = resolveCheck(decl: decl, baseSkill: 65, seq: 1, die: 81);

    expect(roll.baseSkill, 65);
    expect(roll.target, 32);
    expect(roll.outcome, Outcome.fail);
    expect(roll.actorId, 'bp_stella');
    expect(roll.toJson()['skill'], '话术');
  });
}
