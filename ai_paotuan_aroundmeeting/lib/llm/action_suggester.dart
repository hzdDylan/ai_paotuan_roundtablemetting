import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../engine/knowledge/game_event.dart';
import '../engine/rules/character_sheet.dart';
import '../engine/scenario/scenario.dart';
import '../engine/turn/action_suggestion.dart';
import 'llm_client.dart';
import 'prompts.dart';
import 'schema.dart';

/// 生成玩家可选行动的依赖；测试里可替换成假实现。
typedef ActionSuggester =
    Future<List<ActionSuggestion>> Function({
      required LlmClient client,
      required String model,
      required Scenario scenario,
      required SceneDef scene,
      required CharacterSheet character,
      required List<GameEvent> events,
      required Set<String> revealedClues,
      required Map<String, int> clocks,
    });

/// 默认实现：一次短 LLM 调用，只产出建议，不推进剧情。
Future<List<ActionSuggestion>> suggestActions({
  required LlmClient client,
  required String model,
  required Scenario scenario,
  required SceneDef scene,
  required CharacterSheet character,
  required List<GameEvent> events,
  required Set<String> revealedClues,
  required Map<String, int> clocks,
}) async {
  final cancel = CancelToken();
  final timer = Timer(
    const Duration(seconds: 8),
    () => cancel.cancel('suggestion timeout'),
  );
  try {
    final result = await client.chatJson(
      model: model,
      messages: const PromptBuilder().actionSuggestions(
        scenario: scenario,
        scene: scene,
        character: character,
        events: events,
        revealedClues: revealedClues,
        clocks: clocks,
      ),
      temperature: 0.95,
      maxTokens: 420,
      cancelToken: cancel,
    );
    return parseActionSuggestions(result.json);
  } catch (error) {
    // 建议失败不能挡住玩家输入，但要看得到原因。
    debugPrint('行动建议生成失败：$error');
    return const <ActionSuggestion>[];
  } finally {
    timer.cancel();
  }
}
