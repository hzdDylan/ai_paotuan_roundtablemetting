import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/app/di.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/game_event.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario_parser.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/action_suggestion.dart';
import 'package:ai_paotuan_aroundmeeting/features/table/table_notifier.dart';
import 'package:ai_paotuan_aroundmeeting/platform/ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  late Scenario scenario;

  setUpAll(() {
    scenario = parseScenario(
      File('assets/scenarios/dinner_hale/scenario.yaml').readAsStringSync(),
    );
  });

  test('固定开场后只轮到玩家，BP 不抢在玩家之前行动', () async {
    final temp = TempDirs();
    addTearDown(temp.dispose);
    final secret = FakeSecret();
    await secret.write(SecretKeys.apiKey, 'sk-test');

    final container = ProviderContainer(
      overrides: [
        fileDirsProvider.overrideWithValue(temp),
        settingsStoreProvider.overrideWithValue(FakeSettings()),
        secretStoreProvider.overrideWithValue(secret),
        scenarioProvider.overrideWith((ref) async => scenario),
        actionSuggesterProvider.overrideWithValue(
          ({
            required client,
            required model,
            required scenario,
            required scene,
            required character,
            required events,
            required revealedClues,
            required clocks,
          }) async => const <ActionSuggestion>[
            ActionSuggestion(text: '我盯着他的袖口', skill: Skill.spotHidden),
            ActionSuggestion(text: '我先把邀请函收好', attribute: Attribute.pow),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(tableProvider.notifier).start();
    final state = container.read(tableProvider);

    expect(state.status, TableStatus.awaitingInput, reason: state.errorMessage);
    expect(state.speaker, 'KP');
    expect(state.segment, contains('顾公馆'));
    expect(state.suggestions, hasLength(3), reason: '第一拍用剧本固定动作');
    expect(state.suggestions.first.text, '我把邀请函递过去，说只想讨一杯酒');
    expect(state.suggestions.last.text, '我提起刚才离开的那位客人，看他怎么接');

    final dialogue = state.events.where(
      (event) => event.kind == EventKind.dialogue,
    );
    expect(dialogue, isEmpty, reason: '开场拍不应有 BP 或玩家台词');
  });
}
