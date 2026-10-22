import 'dart:collection';

import '../../engine/knowledge/audience.dart';
import '../../engine/knowledge/game_event.dart';
import '../../engine/rules/check.dart';
import '../ports/clock.dart';
import '../ports/event_store.dart';

/// 事件与骰值的写入端：负责序号、时间戳、落盘，不参与剧情判断。
final class EventRecorder {
  EventRecorder({required EventStore store, required Clock clock})
    : _store = store,
      _clock = clock;

  final EventStore _store;
  final Clock _clock;
  final List<GameEvent> _events = <GameEvent>[];
  final List<Roll> _rolls = <Roll>[];

  String _sessionId = '';
  String _sceneId = '';
  int _seq = 0;
  int _rollSeq = 0;

  List<GameEvent> get events => UnmodifiableListView<GameEvent>(_events);

  List<Roll> get rolls => UnmodifiableListView<Roll>(_rolls);

  int get rollSeq => _rollSeq;

  int get seq => _seq;

  void reset({required String sessionId, required String sceneId}) {
    _sessionId = sessionId;
    _sceneId = sceneId;
    _seq = 0;
    _rollSeq = 0;
    _events.clear();
    _rolls.clear();
  }

  void setSceneId(String sceneId) => _sceneId = sceneId;

  void setRollSeq(int value) => _rollSeq = value;

  void addRoll(Roll roll) => _rolls.add(roll);

  void addRolls(Iterable<Roll> rolls) => _rolls.addAll(rolls);

  GameEvent make(
    String kind,
    Audience audience, {
    String? actorId,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    _seq += 1;
    return GameEvent(
      seq: _seq,
      kind: kind,
      audience: audience,
      actorId: actorId,
      sceneId: _sceneId,
      beat: _seq,
      payload: payload,
      createdAt: _clock.now().millisecondsSinceEpoch,
    );
  }

  Future<void> append(List<GameEvent> events) async {
    if (events.isEmpty) return;
    _events.addAll(events);
    if (_sessionId.isNotEmpty) {
      await _store.appendAll(_sessionId, events);
    }
  }
}
