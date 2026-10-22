import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scene_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const flags = <String>{'gu_accepted_invite', 'back_gate'};
  const clues = <String>{'clue_cuff_mud'};
  const clocks = <String, int>{'gu_patience': 0, 'night_watch': 3};

  bool open(String when) => isExitOpen(
    SceneExit(id: 'e', to: 'next', when: when),
    flags: flags,
    clues: clues,
    clocks: clocks,
  );

  test('空条件与 always 永远可走', () {
    expect(open(''), isTrue);
    expect(open('always'), isTrue);
  });

  test('flag / clue / clock_zero 条件', () {
    expect(open('flag:gu_accepted_invite'), isTrue);
    expect(open('flag:not_happened'), isFalse);
    expect(open('clue:clue_cuff_mud'), isTrue);
    expect(open('clock_zero:gu_patience'), isTrue);
    expect(open('clock_zero:night_watch'), isFalse);
  });

  test('取反、且、或', () {
    expect(open('!flag:not_happened'), isTrue);
    expect(open('!flag:gu_accepted_invite'), isFalse);
    expect(open('flag:gu_accepted_invite && clue:clue_cuff_mud'), isTrue);
    expect(open('flag:not_happened && clue:clue_cuff_mud'), isFalse);
    expect(open('flag:not_happened || clock_zero:gu_patience'), isTrue);
  });

  test('未知条件按未满足处理', () {
    expect(open('moon_phase:full'), isFalse);
  });

  test('条件可以翻译成中文', () {
    expect(describeExitCondition('always'), '随时');
    expect(
      describeExitCondition(
        'flag:gu_accepted_invite && clock_zero:gu_patience',
      ),
      contains('已获得标记'),
    );
    expect(describeExitCondition('!flag:not_happened'), contains('未获得'));
  });

  test('致命检定只对玩家的大失败触发', () {
    const scene = SceneDef(
      id: 'porch',
      name: '门廊',
      goal: '进门',
      checks: [
        SceneCheck(
          skill: Skill.persuade,
          difficulty: Difficulty.regular,
          onFumble: SceneFumble(ending: 'ending_silence', text: '门关了。'),
        ),
      ],
    );
    const roll = Roll(
      seq: 1,
      actorId: 'human',
      skill: Skill.persuade,
      baseSkill: 50,
      difficulty: Difficulty.regular,
      target: 50,
      die: 100,
      outcome: Outcome.fumble,
    );
    expect(fatalFumbleFor(scene, roll, 'human')?.ending, 'ending_silence');
    expect(fatalFumbleFor(scene, roll, 'bp_stella'), isNull);
    expect(
      fatalFumbleFor(
        scene,
        Roll(
          seq: 2,
          actorId: 'human',
          skill: Skill.persuade,
          baseSkill: 50,
          difficulty: Difficulty.regular,
          target: 50,
          die: 80,
          outcome: Outcome.fail,
        ),
        'human',
      ),
      isNull,
    );
  });
}
