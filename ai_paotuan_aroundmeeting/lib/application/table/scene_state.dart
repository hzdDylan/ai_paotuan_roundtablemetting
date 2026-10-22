import 'dart:collection';

import '../../engine/scenario/scenario.dart';
import '../../engine/scenario/scene_flow.dart';
import '../../engine/turn/kp_turn.dart';

/// 场景状态：当前场景、时钟、标记、线索。
///
/// 只维护状态与条件判断，不负责发事件或归档。
final class SceneState {
  SceneState(SceneDef initial) : _scene = initial {
    _resetClocks(initial);
  }

  SceneDef _scene;
  final Set<String> _flags = <String>{};
  final Set<String> _clues = <String>{};
  final Map<String, int> _clocks = <String, int>{};

  SceneDef get scene => _scene;

  String get sceneId => _scene.id;

  Set<String> get flags => UnmodifiableSetView<String>(_flags);

  Set<String> get clues => UnmodifiableSetView<String>(_clues);

  Map<String, int> get clocks => UnmodifiableMapView<String, int>(_clocks);

  void enter(SceneDef next) {
    _scene = next;
    _resetClocks(next);
  }

  void apply(KpStateDelta delta) {
    if (delta.isEmpty) return;
    final knownClocks = _scene.clocks.map((clock) => clock.id).toSet();
    for (final change in delta.clocks) {
      if (!knownClocks.contains(change.id)) continue;
      final max = _scene.clocks
          .firstWhere((clock) => clock.id == change.id)
          .max;
      final current = _clocks[change.id] ?? max;
      final next = current + change.delta;
      _clocks[change.id] = next < 0 ? 0 : (next > max ? max : next);
    }
    _clues.addAll(delta.clues);
    _flags.addAll(delta.flags);
  }

  String? clockZeroTarget() {
    for (final clock in _scene.clocks) {
      if ((_clocks[clock.id] ?? clock.max) <= 0 && clock.onZero.isNotEmpty) {
        return clock.onZero;
      }
    }
    return null;
  }

  bool isOpen(SceneExit exit) =>
      isExitOpen(exit, flags: _flags, clues: _clues, clocks: _clocks);

  /// 只接受「当前场景确实有、且条件已满足」的出口；防止 KP 硬跳。
  String? validatedExit(String? requested) {
    if (requested == null || requested.isEmpty) return null;
    if (requested == _scene.id) return null;
    for (final exit in _scene.exits) {
      if (exit.to != requested) continue;
      if (isOpen(exit)) return exit.to;
    }
    return null;
  }

  String? firstOpenExit() {
    for (final exit in _scene.exits) {
      if (isOpen(exit)) return exit.to;
    }
    return null;
  }

  void _resetClocks(SceneDef scene) {
    _clocks
      ..clear()
      ..addEntries(scene.clocks.map((clock) => MapEntry(clock.id, clock.max)));
  }
}
