import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/application/ports/llm_gateway.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/game_event.dart';
import 'package:ai_paotuan_aroundmeeting/engine/moderation/moderation.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/character_sheet.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:ai_paotuan_aroundmeeting/engine/scenario/scenario.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/action_suggestion.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/actor_turn.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/kp_turn.dart';
import 'package:ai_paotuan_aroundmeeting/platform/ports.dart';

/// 测试用：内存版密钥仓。
class FakeSecret implements SecretPort {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// 测试用：内存版设置。
class FakeSettings implements SettingsPort {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

/// 测试用：临时目录（调用方负责删除）。
class TempDirs implements FileDirsPort {
  TempDirs() : _root = Directory.systemTemp.createTempSync('party_of_ais_test');

  final Directory _root;

  Directory get root => _root;

  @override
  Future<Directory> appData() async => _root;

  @override
  Future<Directory> cache() async => _root;

  void dispose() {
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  }
}

/// 测试用 LLM 网关：默认拒绝调用；需要时在具体测试里覆盖。
class FakeLlmGateway implements LlmGateway {
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
  }) => throw UnimplementedError('kpTurn');

  @override
  Future<KpNarration> kpNarration({
    required Scenario scenario,
    required SceneDef scene,
    required List<Roll> rolls,
    required Map<String, String> actorNames,
    required List<GameEvent> events,
    String fatalConsequence = '',
  }) => throw UnimplementedError('kpNarration');

  @override
  Future<ActorTurn> bpTurn({
    required Scenario scenario,
    required SceneDef scene,
    required ScenarioActor actor,
    required List<GameEvent> events,
    required List<String> others,
    String? lastSpeaker,
    String? sideChatTo,
  }) => throw UnimplementedError('bpTurn');

  @override
  Future<List<ActionSuggestion>> suggestions({
    required Scenario scenario,
    required SceneDef scene,
    required CharacterSheet character,
    required List<GameEvent> events,
    required Set<String> revealedClues,
    required Map<String, int> clocks,
  }) => throw UnimplementedError('suggestions');

  @override
  Future<ModerationResult> moderate({
    required Scenario scenario,
    required String text,
    required List<GameEvent> events,
  }) => throw UnimplementedError('moderate');

  @override
  Future<String> review({
    required Scenario scenario,
    required String endingTitle,
    required String characterName,
    required List<GameEvent> events,
    required List<Roll> rolls,
  }) => throw UnimplementedError('review');

  @override
  Future<void> ping() => throw UnimplementedError('ping');
}
