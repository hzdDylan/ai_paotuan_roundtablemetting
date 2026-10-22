import '../../application/ports/event_store.dart';
import '../../engine/knowledge/game_event.dart';

/// 内存实现：测试与回放用。
class MemoryEventStore implements EventStore {
  final Map<String, List<GameEvent>> _sessions = <String, List<GameEvent>>{};

  @override
  Future<void> appendAll(String sessionId, List<GameEvent> events) async {
    _sessions.putIfAbsent(sessionId, () => <GameEvent>[]).addAll(events);
  }

  @override
  Future<List<GameEvent>> readAll(String sessionId) async =>
      List<GameEvent>.unmodifiable(_sessions[sessionId] ?? const <GameEvent>[]);

  @override
  Future<List<String>> listSessionIds() async => _sessions.keys.toList();
}
