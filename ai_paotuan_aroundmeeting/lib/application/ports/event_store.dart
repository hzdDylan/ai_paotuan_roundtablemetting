import '../../engine/knowledge/game_event.dart';

/// 事件存储端口：一局的事件按 session 追加写入。
abstract interface class EventStore {
  Future<void> appendAll(String sessionId, List<GameEvent> events);

  Future<List<GameEvent>> readAll(String sessionId);

  Future<List<String>> listSessionIds();
}
