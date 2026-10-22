import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/application/ports/clock.dart';
import 'package:ai_paotuan_aroundmeeting/application/ports/llm_gateway.dart';
import 'package:ai_paotuan_aroundmeeting/application/table/session_config.dart';
import 'package:ai_paotuan_aroundmeeting/application/table/table_session.dart';
import 'package:ai_paotuan_aroundmeeting/application/table/table_state.dart';
import 'package:ai_paotuan_aroundmeeting/data/archive/archiver.dart';
import 'package:ai_paotuan_aroundmeeting/data/archive/file_archive_repository.dart';
import 'package:ai_paotuan_aroundmeeting/data/scenario/scenario_parser.dart';
import 'package:ai_paotuan_aroundmeeting/data/storage/memory_event_store.dart';
import 'package:ai_paotuan_aroundmeeting/engine/dice/dice.dart';
import 'package:ai_paotuan_aroundmeeting/engine/director/director.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/audience.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/game_event.dart';
import 'package:ai_paotuan_aroundmeeting/engine/moderation/moderation.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_sheet.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/action_suggestion.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/actor_turn.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/kp_turn.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

class ScriptedLlm implements LlmGateway {
  KpTurn? kpTurnResponse;
  KpNarration? kpNarrationResponse;
  List<ActionSuggestion> suggestionsResponse = const <ActionSuggestion>[];
  ModerationResult moderationResponse = const ModerationResult(
    verdict: ModerationVerdict.allow,
  );

  final List<GameEvent> suggestionEvents = <GameEvent>[];
  final List<GameEvent> bpEvents = <GameEvent>[];

  @override
  Future<KpTurn> kpTurn({
    required Scenario scenario,
    required SceneDef scene,
    required List<GameEvent> events,
    required Map<String, String> party,
    required String instruction,
    Set<String> flags = const <String>{},
    Set<String> revealedClues = const <String>{},
    Map<String, int> clocks = const <String, int>{},
  }) async => kpTurnResponse!;

  @override
  Future<KpNarration> kpNarration({
    required Scenario scenario,
    required SceneDef scene,
    required List<Roll> rolls,
    required Map<String, String> actorNames,
    required List<GameEvent> events,
    String fatalConsequence = '',
  }) async => kpNarrationResponse!;

  @override
  Future<ActorTurn> bpTurn({
    required Scenario scenario,
    required SceneDef scene,
    required ScenarioActor actor,
    required List<GameEvent> events,
    required List<String> others,
    String? lastSpeaker,
    String? sideChatTo,
  }) {
    bpEvents.addAll(events);
    return Future<ActorTurn>.error(UnimplementedError('bpTurn'));
  }

  @override
  Future<List<ActionSuggestion>> suggestions({
    required Scenario scenario,
    required SceneDef scene,
    required CharacterSheet character,
    required List<GameEvent> events,
    required Set<String> revealedClues,
    required Map<String, int> clocks,
  }) async {
    suggestionEvents
      ..clear()
      ..addAll(events);
    return suggestionsResponse;
  }

  @override
  Future<ModerationResult> moderate({
    required Scenario scenario,
    required String text,
    required List<GameEvent> events,
  }) async => moderationResponse;

  @override
  Future<String> review({
    required Scenario scenario,
    required String endingTitle,
    required String characterName,
    required List<GameEvent> events,
    required List<Roll> rolls,
  }) async => '测试复盘';

  @override
  Future<void> ping() async {}
}

void main() {
  late Scenario scenario;
  late CharacterSheet character;
  late TempDirs temp;
  late TableSession session;
  late ScriptedLlm llm;
  late MemoryEventStore eventStore;

  setUpAll(() {
    scenario = parseScenario(
      File('assets/scenarios/dinner_hale/scenario.yaml').readAsStringSync(),
    );
    character = CharacterSheet.fresh().copyWith(name: '测试者');
  });

  setUp(() async {
    temp = TempDirs();
    llm = ScriptedLlm();
    eventStore = MemoryEventStore();
    session = TableSession(
      scenario: scenario,
      character: character,
      config: const SessionConfig(bpCount: 1),
      llm: llm,
      eventStore: eventStore,
      archives: FileArchiveRepository(Archiver(temp.root)),
      clock: const _FixedClock(),
      rng: SequenceRng(const <int>[0, 1, 2, 3]),
      director: const Director(),
    );
    await session.start();
  });

  tearDown(() async {
    await session.dispose();
    temp.dispose();
  });

  test('提交玩家输入后落库、回应并回到等待输入', () async {
    llm.kpTurnResponse = const KpTurn(narration: '顾先生抬了抬眼皮。');
    llm.suggestionsResponse = const <ActionSuggestion>[
      ActionSuggestion(text: '我问他今晚在等谁'),
    ];

    await session.submitPlayer('我走到门边，先看走廊里有没有人');

    expect(session.state.status, TableStatus.awaitingInput);
    expect(
      session.state.events.where((event) => event.kind == EventKind.dialogue),
      isNotEmpty,
    );
    expect(
      session.state.events.where((event) => event.kind == EventKind.narration),
      isNotEmpty,
    );
    expect(session.state.suggestions, hasLength(1));
    await expectLater(eventStore.readAll(session.state.sessionId), completes);
  });

  test('一次动作里的多个检定会逐条落库，但只叙述一次', () async {
    llm.kpTurnResponse = const KpTurn(
      narration: '',
      checks: <CheckDecl>[
        CheckDecl(
          actorId: 'human',
          skill: Skill.spotHidden,
          difficulty: Difficulty.regular,
        ),
        CheckDecl(
          actorId: 'human',
          attribute: Attribute.pow,
          difficulty: Difficulty.regular,
        ),
      ],
    );
    llm.kpNarrationResponse = const KpNarration(narration: '两件事同时发生了。');

    await session.submitPlayer('我看四周，同时稳住心神');

    final rollEvents = session.state.events
        .where((event) => event.kind == EventKind.roll)
        .toList();
    final resultEvents = session.state.events
        .where((event) => event.kind == EventKind.checkResult)
        .toList();
    expect(rollEvents, hasLength(2));
    expect(resultEvents, hasLength(1));
    expect(session.state.dice, isNotNull);
  });

  test('交给玩家的可见事件不包含 kpOnly 事件', () async {
    llm.kpTurnResponse = const KpTurn(narration: '顾先生没有回答。');
    llm.suggestionsResponse = const <ActionSuggestion>[
      ActionSuggestion(text: '我沉默地坐下'),
    ];

    await session.submitPlayer('我保持沉默');

    expect(
      llm.suggestionEvents.where(
        (event) => event.kind == EventKind.inputAllowed,
      ),
      isEmpty,
      reason: 'input_allowed 是 kpOnly，不应进入玩家建议上下文',
    );
    expect(
      llm.suggestionEvents.where(
        (event) => event.audience.kind == AudienceKind.kp,
      ),
      isEmpty,
    );
  });
}

class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime now() => DateTime(2026, 10, 22, 20);
}
