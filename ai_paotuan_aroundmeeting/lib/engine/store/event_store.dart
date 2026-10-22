import 'dart:convert';
import 'dart:io';

import '../knowledge/game_event.dart';

/// 事件存储（D-22 = D：纯文件 NDJSON）。
abstract interface class EventStore {
  Future<void> appendAll(String sessionId, List<GameEvent> events);

  Future<List<GameEvent>> readAll(String sessionId);

  Future<List<String>> listSessionIds();
}

/// 内存实现（测试用）。
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

/// 文件实现：`{root}/sessions/{id}/events.ndjson`，追加写。
class FileEventStore implements EventStore {
  const FileEventStore(this.root);

  final Directory root;

  Directory _sessionDir(String sessionId) =>
      Directory('${root.path}/sessions/$sessionId');

  @override
  Future<void> appendAll(String sessionId, List<GameEvent> events) async {
    if (events.isEmpty) return;
    final dir = _sessionDir(sessionId);
    await dir.create(recursive: true);
    final file = File('${dir.path}/events.ndjson');
    final sink = file.openWrite(mode: FileMode.append);
    try {
      for (final event in events) {
        sink.writeln(jsonEncode(event.toJson()));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<List<GameEvent>> readAll(String sessionId) async {
    final file = File('${_sessionDir(sessionId).path}/events.ndjson');
    if (!await file.exists()) return const <GameEvent>[];
    final lines = await file.readAsLines();
    final events = <GameEvent>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          events.add(
            GameEvent.fromJson(
              decoded.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      } on FormatException {
        // 截断的最后一行直接丢弃（SE §5.3）。
      }
    }
    return events;
  }

  @override
  Future<List<String>> listSessionIds() async {
    final sessionsDir = Directory('${root.path}/sessions');
    if (!await sessionsDir.exists()) return const <String>[];
    final ids = <String>[];
    await for (final entity in sessionsDir.list()) {
      if (entity is Directory) {
        ids.add(entity.path.split(Platform.pathSeparator).last);
      }
    }
    ids.sort();
    return ids;
  }
}
