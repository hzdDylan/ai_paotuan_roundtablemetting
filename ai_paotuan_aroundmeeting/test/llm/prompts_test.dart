import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/data/scenario/scenario_parser.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/audience.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/game_event.dart';
import 'package:ai_paotuan_aroundmeeting/engine/moderation/moderation.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_sheet.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/llm/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Scenario scenario;
  late SceneDef scene;

  setUpAll(() {
    scenario = parseScenario(
      File('assets/scenarios/dinner_hale/scenario.yaml').readAsStringSync(),
    );
    scene = scenario.scenes.first;
  });

  const builder = PromptBuilder();

  test('BP prompt 带上身份、目标与场景', () {
    final stella = scenario.actorById('bp_stella')!;
    final messages = builder.bpTurn(
      scenario: scenario,
      scene: scene,
      actor: stella,
      events: const <GameEvent>[],
      others: const <String>['Joe', '老陈', '顾先生'],
    );

    final system = messages.first['content']!;
    expect(system, contains('Stella'));
    expect(system, contains('让顾先生接受邀请'));
    expect(system, contains('门廊'));
    expect(system, contains('不要提'));
    expect(system, contains('吐槽示例'));
    expect(system, contains('善变诱因'));
    expect(messages.last['content'], contains('现在轮到你'));
  });

  test('BP prompt 不泄露别人的秘密', () {
    final stella = scenario.actorById('bp_stella')!;
    final messages = builder.bpTurn(
      scenario: scenario,
      scene: scene,
      actor: stella,
      events: const <GameEvent>[],
      others: const <String>['Joe', '老陈'],
    );
    final corpus = messages.map((m) => m['content']).join('\n');
    // 老陈的秘密是「地下室」，不应该出现在 Stella 的 prompt 里。
    expect(corpus, isNot(contains('地下室')));
  });

  test('KP prompt 带时钟、线索与输出契约', () {
    final messages = builder.kpTurn(
      scenario: scenario,
      scene: scene,
      events: const <GameEvent>[],
      party: const <String, String>{'human': 'Joe', 'bp_stella': 'Stella'},
      instruction: '请开场。',
    );
    final system = messages.first['content']!;
    expect(system, contains('守秘人'));
    expect(system, contains('顾先生的耐心'));
    expect(system, contains('他袖口有泥'));
    expect(system, contains('"checks"'));
    expect(system, contains('dining_room'));
    expect(system, contains('"flags"'));
    expect(system, contains('已获得标记'));
  });

  test('骰后叙述 prompt 明确骰值不可改', () {
    final messages = builder.kpNarration(
      scenario: scenario,
      scene: scene,
      rolls: const <Roll>[
        Roll(
          seq: 1,
          actorId: 'bp_stella',
          skill: Skill.persuade,
          baseSkill: 65,
          difficulty: Difficulty.regular,
          target: 65,
          die: 81,
          outcome: Outcome.fail,
          stakes: '他会拒绝',
        ),
      ],
      actorNames: const <String, String>{'bp_stella': 'Stella'},
      events: const <GameEvent>[],
    );
    final system = messages.first['content']!;
    expect(system, contains('不能修改'));
    expect(messages.last['content'], contains('骰值 81'));
    expect(messages.last['content'], contains('Stella'));
    expect(messages.last['content'], contains('失败'));
  });

  test('致命大失败会告诉 KP 这是收场拍', () {
    final messages = builder.kpNarration(
      scenario: scenario,
      scene: scene,
      rolls: const <Roll>[
        Roll(
          seq: 1,
          actorId: 'human',
          skill: Skill.persuade,
          baseSkill: 50,
          difficulty: Difficulty.regular,
          target: 50,
          die: 100,
          outcome: Outcome.fumble,
        ),
      ],
      actorNames: const <String, String>{'human': 'Joe'},
      events: const <GameEvent>[],
      fatalConsequence: '顾先生把门关上。',
    );
    final system = messages.first['content']!;
    expect(system, contains('致命收场'));
    expect(system, contains('顾先生把门关上'));
    expect(system, contains('系统会在你叙述后直接结束本局'));
  });

  test('行动建议 prompt 只带已揭示线索，并要求技能或属性', () {
    final messages = builder.actionSuggestions(
      scenario: scenario,
      scene: scene,
      character: CharacterSheet.fresh().copyWith(name: 'Joe'),
      events: const <GameEvent>[],
      revealedClues: const <String>{'clue_cuff_mud'},
      clocks: const <String, int>{'gu_patience': 3},
    );
    final system = messages.first['content']!;
    expect(system, contains('2–4 条'));
    expect(system, contains('他袖口有泥'));
    expect(system, isNot(contains('地下室关着人')));
    expect(system, contains('技能或基础属性'));
    expect(system, contains('"actions"'));
  });

  test('KP 复盘 prompt 要求评价本局', () {
    final messages = builder.kpReview(
      scenario: scenario,
      endingTitle: '体面收场',
      characterName: 'Joe',
      events: const <GameEvent>[],
      rolls: const <Roll>[],
    );
    final system = messages.first['content']!;
    expect(system, contains('复盘评价'));
    expect(system, contains('体面收场'));
    expect(system, contains('"review"'));
  });

  test('审核 prompt 带剧本人边界与玩家原话', () {
    final messages = builder.moderation(
      scope: scenario.contentScope,
      text: '我掏出手机打电话',
      events: const <GameEvent>[],
    );
    final system = messages.first['content']!;
    expect(system, contains('1935'));
    expect(system, contains('禁止'));
    expect(messages.last['content'], contains('手机'));
  });

  test('renderRecent 只保留最近若干条', () {
    final events = <GameEvent>[
      for (var index = 1; index <= 20; index++)
        GameEvent(
          seq: index,
          kind: EventKind.dialogue,
          audience: const Audience.public(),
          actorId: 'human',
          payload: <String, dynamic>{'text': '第$index句'},
        ),
    ];
    final rendered = renderRecent(events, limit: 5);
    expect(rendered, isNot(contains('第15句')));
    expect(rendered, contains('第20句'));
  });

  test('ContentScope 空时也能生成 prompt', () {
    final messages = builder.moderation(
      scope: const ContentScope(),
      text: '你好',
      events: const <GameEvent>[],
    );
    expect(messages.first['content'], isNotEmpty);
  });

  test('四个剧本的 BP prompt 都不泄露别人的秘密', () {
    for (final path in _allPaths) {
      final current = parseScenario(File(path).readAsStringSync());
      for (final bp in current.bpActors) {
        final messages = builder.bpTurn(
          scenario: current,
          scene: current.scenes.first,
          actor: bp,
          events: const <GameEvent>[],
          others: const <String>['其他人'],
        );
        final corpus = messages.map((message) => message['content']).join('\n');
        for (final other in current.bpActors) {
          if (other.id == bp.id || other.secret.isEmpty) continue;
          expect(
            corpus,
            isNot(contains(other.secret)),
            reason: '${current.id}/${bp.id} 泄露了 ${other.id} 的秘密',
          );
        }
        for (final npc in current.npcs) {
          if (npc.secret.isEmpty) continue;
          expect(
            corpus,
            isNot(contains(npc.secret)),
            reason: '${current.id}/${bp.id} 泄露了 ${npc.id} 的秘密',
          );
        }
      }
    }
  });

  test('KP prompt 只带当前场景线索，不提前泄露别的场景', () {
    for (final path in _allPaths) {
      final current = parseScenario(File(path).readAsStringSync());
      for (final currentScene in current.scenes) {
        final messages = builder.kpTurn(
          scenario: current,
          scene: currentScene,
          events: const <GameEvent>[],
          party: const <String, String>{'human': '你'},
          instruction: '继续。',
        );
        final corpus = messages.map((message) => message['content']).join('\n');
        for (final other in current.scenes) {
          if (other.id == currentScene.id) continue;
          for (final clue in other.clues) {
            expect(
              corpus,
              isNot(contains(clue.text)),
              reason: '${current.id}/${currentScene.id} 泄露了 ${clue.id}',
            );
          }
        }
      }
    }
  });
}

const List<String> _allPaths = <String>[
  'assets/scenarios/dinner_hale/scenario.yaml',
  'assets/scenarios/mist_dock/scenario.yaml',
  'assets/scenarios/paramount_last_dance/scenario.yaml',
  'assets/scenarios/xiafei_47/scenario.yaml',
];
