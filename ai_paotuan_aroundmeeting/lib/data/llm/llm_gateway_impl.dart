import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../application/ports/app_failure.dart';
import '../../application/ports/llm_gateway.dart';
import '../../engine/knowledge/game_event.dart';
import '../../engine/moderation/moderation.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/scenario.dart';
import '../../engine/turn/action_suggestion.dart';
import '../../engine/turn/actor_turn.dart';
import '../../engine/turn/kp_turn.dart';
import '../../llm/llm_client.dart';
import '../../llm/prompts.dart';
import '../../llm/schema.dart';

/// LlmGateway 的生产实现：Prompt、HTTP、JSON 解析都留在这一层。
final class LlmGatewayImpl implements LlmGateway {
  LlmGatewayImpl({
    required LlmClient client,
    required this.kpModel,
    required this.bpModel,
    PromptBuilder prompts = const PromptBuilder(),
  }) : _client = client,
       _prompts = prompts;

  final LlmClient _client;
  final String kpModel;
  final String bpModel;
  final PromptBuilder _prompts;

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
  }) async {
    return _guard(() async {
      final result = await _client.chatJson(
        model: kpModel,
        messages: _prompts.kpTurn(
          scenario: scenario,
          scene: scene,
          events: events,
          party: party,
          instruction: instruction,
          flags: flags,
          revealedClues: revealedClues,
          clocks: clocks,
        ),
      );
      return parseKpTurn(
        result.json,
        npcNames: scenario.npcs.map((npc) => npc.name).toSet(),
        actorIds: party.keys.toSet(),
        sceneIds: scenario.scenes.map((scene) => scene.id).toSet(),
        humanId: 'human',
      );
    });
  }

  @override
  Future<KpNarration> kpNarration({
    required Scenario scenario,
    required SceneDef scene,
    required List<Roll> rolls,
    required Map<String, String> actorNames,
    required List<GameEvent> events,
    String fatalConsequence = '',
  }) async {
    return _guard(() async {
      final result = await _client.chatJson(
        model: kpModel,
        messages: _prompts.kpNarration(
          scenario: scenario,
          scene: scene,
          rolls: rolls,
          actorNames: actorNames,
          events: events,
          fatalConsequence: fatalConsequence,
        ),
      );
      return parseKpNarration(
        result.json,
        npcNames: scenario.npcs.map((npc) => npc.name).toSet(),
        sceneIds: scenario.scenes.map((scene) => scene.id).toSet(),
      );
    });
  }

  @override
  Future<ActorTurn> bpTurn({
    required Scenario scenario,
    required SceneDef scene,
    required ScenarioActor actor,
    required List<GameEvent> events,
    required List<String> others,
    String? lastSpeaker,
    String? sideChatTo,
  }) async {
    return _guard(() async {
      final result = await _client.chatJson(
        model: bpModel,
        messages: _prompts.bpTurn(
          scenario: scenario,
          scene: scene,
          actor: actor,
          events: events,
          others: others,
          lastSpeaker: lastSpeaker,
          sideChatTo: sideChatTo,
        ),
      );
      return parseBpTurn(
        result.json,
        selfName: actor.name,
        knownNames: others.toSet(),
      );
    });
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
    try {
      final result = await _chat(
        model: kpModel,
        messages: _prompts.actionSuggestions(
          scenario: scenario,
          scene: scene,
          character: character,
          events: events,
          revealedClues: revealedClues,
          clocks: clocks,
        ),
        temperature: 0.95,
        maxTokens: 420,
        timeout: const Duration(seconds: 8),
      );
      return parseActionSuggestions(result.json);
    } on LlmException catch (error) {
      developer.log('行动建议生成失败：${error.message}', name: 'LlmGateway');
      return const <ActionSuggestion>[];
    } on SchemaException catch (error) {
      developer.log('行动建议解析失败：${error.message}', name: 'LlmGateway');
      return const <ActionSuggestion>[];
    }
  }

  @override
  Future<ModerationResult> moderate({
    required Scenario scenario,
    required String text,
    required List<GameEvent> events,
  }) async {
    try {
      final result = await _chat(
        model: bpModel,
        messages: _prompts.moderation(
          scope: scenario.contentScope,
          text: text,
          events: events,
        ),
        temperature: 0.1,
        maxTokens: 120,
        timeout: const Duration(seconds: 8),
      );
      return ModerationResult(
        verdict: parseModerationVerdict(result.json),
        category: parseModerationCategory(result.json['category']),
        stage: ModerationStage.llm,
        reason: result.json['reason']?.toString() ?? '',
      );
    } on LlmException {
      return const ModerationResult(
        verdict: ModerationVerdict.reject,
        category: ModerationCategory.none,
        reason: '审核不可用',
      );
    }
  }

  @override
  Future<String> review({
    required Scenario scenario,
    required String endingTitle,
    required String characterName,
    required List<GameEvent> events,
    required List<Roll> rolls,
  }) async {
    try {
      final result = await _chat(
        model: kpModel,
        messages: _prompts.kpReview(
          scenario: scenario,
          endingTitle: endingTitle,
          characterName: characterName,
          events: events,
          rolls: rolls,
        ),
        temperature: 0.7,
        maxTokens: 220,
        timeout: const Duration(seconds: 8),
      );
      final text = result.json['review']?.toString().trim() ?? '';
      if (text.isEmpty) return '';
      return text.length <= 180 ? text : '${text.substring(0, 180)}…';
    } on LlmException {
      return '';
    } on SchemaException {
      return '';
    }
  }

  @override
  Future<void> ping() => _guard(() => _client.ping(model: kpModel));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on LlmException catch (error) {
      throw AppFailure(error.code, error.message);
    } on SchemaException catch (error) {
      throw AppFailure('E_PARSE', error.message);
    }
  }

  Future<LlmResult> _chat({
    required String model,
    required List<Map<String, String>> messages,
    required double temperature,
    required int maxTokens,
    required Duration timeout,
  }) async {
    final cancel = CancelToken();
    final timer = Timer(timeout, () => cancel.cancel('llm timeout'));
    try {
      return await _client.chatJson(
        model: model,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        cancelToken: cancel,
      );
    } finally {
      timer.cancel();
    }
  }
}
