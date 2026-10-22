import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/engine/archive/archiver.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/audience.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/game_event.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_sheet.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late TempDirs dirs;
  late Scenario scenario;

  setUp(() {
    dirs = TempDirs();
    scenario = parseScenario(
      File('assets/scenarios/dinner_hale/scenario.yaml').readAsStringSync(),
    );
  });

  tearDown(() => dirs.dispose());

  test('归档生成后可以被列出与读回', () async {
    final archiver = Archiver(dirs.root);
    final events = <GameEvent>[
      const GameEvent(
        seq: 1,
        kind: EventKind.narration,
        audience: Audience.public(),
        payload: {'text': '你们按了门铃。'},
      ),
      const GameEvent(
        seq: 2,
        kind: EventKind.dialogue,
        audience: Audience.public(),
        actorId: 'bp_stella',
        payload: {'text': '您好，顾先生。', 'intent': 'taunt'},
      ),
    ];
    final rolls = <Roll>[
      const Roll(
        seq: 1,
        actorId: 'bp_stella',
        skill: Skill.persuade,
        baseSkill: 65,
        difficulty: Difficulty.regular,
        target: 65,
        die: 81,
        outcome: Outcome.fail,
        stakes: '被拒绝',
      ),
    ];

    final record = await archiver.seal(
      sessionId: 'sess_test_001',
      scenario: scenario,
      character: CharacterSheet.fresh().copyWith(name: 'Joe'),
      events: events,
      rolls: rolls,
      startedAt: DateTime.now().subtract(const Duration(minutes: 18)),
      endingTitle: '交易',
      oneLine: '你活着离开。',
      review: '你用一句真话换了一条命。',
    );

    expect(record.sessionId, 'sess_test_001');
    expect(File(record.path).existsSync(), isTrue);
    expect(record.partySize, 4);

    final list = await archiver.list();
    expect(list, hasLength(1));
    expect(list.single.scenarioTitle, contains('顾先生'));
    expect(list.single.endingTitle, '交易');
    expect(list.single.review, '你用一句真话换了一条命。');

    final restored = await archiver.readEvents(record.path);
    expect(restored, hasLength(2));
    expect(restored.first.text, '你们按了门铃。');
  });

  test('没有归档时列表为空', () async {
    final list = await Archiver(dirs.root).list();
    expect(list, isEmpty);
  });

  test('高光会挑出吐槽与大失败', () async {
    final archiver = Archiver(dirs.root);
    final record = await archiver.seal(
      sessionId: 'sess_test_002',
      scenario: scenario,
      character: CharacterSheet.fresh().copyWith(name: 'Joe'),
      events: <GameEvent>[
        const GameEvent(
          seq: 1,
          kind: EventKind.dialogue,
          audience: Audience.public(),
          actorId: 'bp_stella',
          payload: {'text': '……你认真的？', 'intent': 'taunt'},
        ),
        const GameEvent(
          seq: 2,
          kind: EventKind.roll,
          audience: Audience.public(),
          actorId: 'human',
          payload: {'outcome': 'fumble', 'die': 98},
        ),
      ],
      rolls: const <Roll>[],
      startedAt: DateTime.now(),
    );

    final raw = File(record.path).readAsStringSync();
    expect(raw, contains('"highlights"'));
    expect(raw, contains('taunt'));
    expect(raw, contains('fumble'));
  });
}
