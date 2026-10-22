import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/kp_turn.dart';
import 'package:ai_paotuan_aroundmeeting/llm/schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BP 输出', () {
    test('正常解析', () {
      final turn = parseBpTurn(
        <String, dynamic>{
          'speech': '您好，顾先生。',
          'action': '递上名片',
          'intent': 'persuade',
          'target': '顾先生',
          'wants_check': <String, dynamic>{'skill': '话术'},
          'private_note': '不能让他拒绝',
        },
        selfName: 'Stella',
        knownNames: {'顾先生', 'Joe'},
      );

      expect(turn.speech, '您好，顾先生。');
      expect(turn.intent.name, 'persuade');
      expect(turn.wantsCheckSkill, Skill.persuade);
    });

    test('缺少 speech 报错', () {
      expect(
        () => parseBpTurn(
          <String, dynamic>{'action': '站着'},
          selfName: 'Stella',
          knownNames: const <String>{},
        ),
        throwsA(isA<SchemaException>()),
      );
    });

    test('禁语会被拦下', () {
      expect(
        () => parseBpTurn(
          <String, dynamic>{'speech': '作为AI，我不能这么做'},
          selfName: 'Stella',
          knownNames: const <String>{},
        ),
        throwsA(isA<SchemaException>()),
      );
    });

    test('未知技能报错', () {
      expect(
        () => parseBpTurn(
          <String, dynamic>{
            'speech': '我来试试。',
            'wants_check': <String, dynamic>{'skill': '驾驶'},
          },
          selfName: 'Stella',
          knownNames: const <String>{},
        ),
        throwsA(isA<SchemaException>()),
      );
    });

    test('神话不可主动申请', () {
      expect(
        () => parseBpTurn(
          <String, dynamic>{
            'speech': '我念咒。',
            'wants_check': <String, dynamic>{'skill': '神话'},
          },
          selfName: 'Stella',
          knownNames: const <String>{},
        ),
        throwsA(isA<SchemaException>()),
      );
    });
  });

  group('KP 输出', () {
    test('解析检定与状态变化', () {
      final turn = parseKpTurn(
        <String, dynamic>{
          'narration': '顾先生扶着门框。',
          'npc_lines': [
            {'npc': '顾先生', 'line': '按礼节，我不该拒绝。', 'attitude_delta': -1},
          ],
          'check': {
            'actor': 'bp_stella',
            'skill': '话术',
            'difficulty': 'hard',
            'stakes': '他会礼貌拒绝',
          },
          'state': {
            'clocks': [
              {'id': 'gu_patience', 'delta': -1},
            ],
            'clues': ['clue_cuff_mud'],
          },
          'scene': 'continue',
        },
        npcNames: {'顾先生'},
        actorIds: {'bp_stella', 'human'},
      );

      expect(turn.npcLines.single.npc, '顾先生');
      expect(turn.check!.skill, Skill.persuade);
      expect(turn.check!.difficulty, Difficulty.hard);
      expect(turn.state.clocks.single.delta, -1);
      expect(turn.state.clues.single, 'clue_cuff_mud');
      expect(turn.displayText, contains('顾先生：「按礼节'));
    });

    test('NPC 不在剧本里报错', () {
      expect(
        () => parseKpTurn(
          <String, dynamic>{
            'narration': '一个陌生人走进来。',
            'npc_lines': [
              {'npc': '陌生人', 'line': '你好。'},
            ],
          },
          npcNames: {'顾先生'},
          actorIds: const <String>{},
        ),
        throwsA(isA<SchemaException>()),
      );
    });

    test('未知行动者会被忽略而不是让整拍崩掉', () {
      final turn = parseKpTurn(
        <String, dynamic>{
          'narration': '有人要掷骰。',
          'check': {'actor': 'nobody', 'skill': '话术'},
        },
        npcNames: const <String>{},
        actorIds: {'human'},
      );
      expect(turn.check, isNull);
    });

    test('player / 玩家 / 你 会被归一成 human', () {
      for (final alias in <String>['player', '玩家', '你', 'Player']) {
        final turn = parseKpTurn(
          <String, dynamic>{
            'narration': '他要掷骰。',
            'check': {'actor': alias, 'skill': '话术'},
          },
          npcNames: const <String>{},
          actorIds: {'human', 'bp_stella'},
          humanId: 'human',
        );
        expect(turn.check?.actorId, 'human', reason: 'alias=$alias');
      }
    });

    test('既无旁白也无台词报错', () {
      expect(
        () => parseKpTurn(
          <String, dynamic>{'narration': '   '},
          npcNames: const <String>{},
          actorIds: const <String>{},
        ),
        throwsA(isA<SchemaException>()),
      );
    });

    test('scene 信号解析', () {
      expect(parseSceneSignal('end'), SceneSignal.endScene);
      expect(parseSceneSignal('transition'), SceneSignal.transition);
      expect(parseSceneSignal('continue'), SceneSignal.continueRun);
      expect(parseSceneSignal(null), SceneSignal.continueRun);
    });

    test('scene 填合法场景 id 时解析为转场目标', () {
      final turn = parseKpTurn(
        <String, dynamic>{'narration': '顾先生侧身让开门。', 'scene': 'dining_room'},
        npcNames: const <String>{},
        actorIds: const <String>{'human'},
        sceneIds: const <String>{'porch', 'dining_room'},
      );
      expect(turn.signal, SceneSignal.transition);
      expect(turn.nextSceneId, 'dining_room');
    });

    test('未知场景 id 不会被当成转场', () {
      final turn = parseKpTurn(
        <String, dynamic>{'narration': '门外没有声音。', 'scene': 'nowhere'},
        npcNames: const <String>{},
        actorIds: const <String>{},
        sceneIds: const <String>{'porch'},
      );
      expect(turn.signal, SceneSignal.continueRun);
      expect(turn.nextSceneId, isNull);
    });

    test('flags 进入状态增量', () {
      final turn = parseKpTurn(
        <String, dynamic>{
          'narration': '顾先生把门让开。',
          'state': {
            'flags': <String>['gu_accepted_invite', 'seen_service_door'],
          },
        },
        npcNames: const <String>{},
        actorIds: const <String>{},
      );
      expect(
        turn.state.flags,
        containsAll(<String>['gu_accepted_invite', 'seen_service_door']),
      );
    });
  });

  test('骰后叙述解析', () {
    final narration = parseKpNarration(<String, dynamic>{
      'narration': '顾先生沉默了三秒，把门让开一条缝。',
      'scene': 'continue',
    }, npcNames: const <String>{});
    expect(narration.narration, contains('门让开'));
    expect(narration.signal, SceneSignal.continueRun);
  });

  test('骰后叙述可以转场', () {
    final narration = parseKpNarration(
      <String, dynamic>{'narration': '门在你们身后合上。', 'scene': 'dining_room'},
      npcNames: const <String>{},
      sceneIds: const <String>{'porch', 'dining_room'},
    );
    expect(narration.signal, SceneSignal.transition);
    expect(narration.nextSceneId, 'dining_room');
  });

  test('一句话多个动作可解析成多个检定，且支持属性', () {
    final turn = parseKpTurn(
      <String, dynamic>{
        'narration': '你同时做了三件事。',
        'checks': [
          {'actor': 'human', 'skill': '侦查'},
          {'actor': 'human', 'skill': '话术', 'difficulty': 'hard'},
          {'actor': 'human', 'attribute': '敏捷'},
        ],
      },
      npcNames: const <String>{},
      actorIds: const <String>{'human'},
      humanId: 'human',
    );
    expect(turn.checks, hasLength(3));
    expect(turn.checks[1].difficulty, Difficulty.hard);
    expect(turn.checks[2].label, '敏捷');
  });
}
