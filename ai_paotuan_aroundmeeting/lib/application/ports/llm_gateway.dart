import '../../engine/knowledge/game_event.dart';
import '../../engine/moderation/moderation.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/scenario.dart';
import '../../engine/turn/action_suggestion.dart';
import '../../engine/turn/actor_turn.dart';
import '../../engine/turn/kp_turn.dart';

/// LLM 端口：应用层只描述“要什么”，不关心 Prompt 与 HTTP。
///
/// 把 `Map<String, String> messages`、`CancelToken`、JSON 解析都留在 data 层。
abstract interface class LlmGateway {
  Future<KpTurn> kpTurn({
    required Scenario scenario,
    required SceneDef scene,
    required List<GameEvent> events,
    required Map<String, String> party,
    required String instruction,
    Set<String> flags = const <String>{},
    Set<String> revealedClues = const <String>{},
    Map<String, int> clocks = const <String, int>{},
  });

  Future<KpNarration> kpNarration({
    required Scenario scenario,
    required SceneDef scene,
    required List<Roll> rolls,
    required Map<String, String> actorNames,
    required List<GameEvent> events,
    String fatalConsequence = '',
  });

  Future<ActorTurn> bpTurn({
    required Scenario scenario,
    required SceneDef scene,
    required ScenarioActor actor,
    required List<GameEvent> events,
    required List<String> others,
    String? lastSpeaker,
    String? sideChatTo,
  });

  Future<List<ActionSuggestion>> suggestions({
    required Scenario scenario,
    required SceneDef scene,
    required CharacterSheet character,
    required List<GameEvent> events,
    required Set<String> revealedClues,
    required Map<String, int> clocks,
  });

  Future<ModerationResult> moderate({
    required Scenario scenario,
    required String text,
    required List<GameEvent> events,
  });

  Future<String> review({
    required Scenario scenario,
    required String endingTitle,
    required String characterName,
    required List<GameEvent> events,
    required List<Roll> rolls,
  });

  Future<void> ping();
}
