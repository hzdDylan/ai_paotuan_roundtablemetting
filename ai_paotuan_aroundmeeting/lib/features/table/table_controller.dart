import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di.dart';
import '../../application/ports/app_failure.dart';
import '../../application/table/table_session.dart';
import '../../application/table/table_state.dart';
import '../../engine/archive/archive_record.dart';

export '../../application/table/table_state.dart';

/// 桌面控制器：只负责取值、创建会话、转发命令、订阅快照。
final tableProvider = NotifierProvider<TableController, TableState>(
  TableController.new,
);

final class TableController extends Notifier<TableState> {
  TableSession? _session;
  StreamSubscription<TableState>? _subscription;

  @override
  TableState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _session?.dispose();
    });
    return const TableState();
  }

  Future<void> start() async {
    if (state.busy) return;
    await _disposeSession();

    state = state.copyWith(
      status: TableStatus.loading,
      busy: true,
      segment: '',
      errorCode: null,
      errorMessage: null,
      inputRejected: null,
      ended: false,
    );

    try {
      final scenario = await ref.read(scenarioProvider.future);
      final factory = await ref.read(tableSessionFactoryProvider.future);
      final session = factory.create(
        scenario: scenario,
        character: ref.read(characterProvider),
        config: ref.read(sessionConfigProvider),
      );

      _session = session;
      _subscription = session.updates.listen((next) => state = next);
      await session.start();
    } on AppFailure catch (error) {
      _fail(error.code, error.message);
    } catch (error) {
      _fail('E_UNKNOWN', '$error');
    }
  }

  Future<void> advance() async {
    final session = _session;
    if (session == null) return;
    await session.advance();
  }

  Future<void> submitPlayer(String raw, {String? checkHint}) async {
    final session = _session;
    if (session == null) return;
    await session.submitPlayer(raw, checkHint: checkHint);
  }

  Future<ArchiveRecord?> endAndArchive({
    String endingId = 'auto',
    String endingTitle = '本局结束',
  }) async {
    final session = _session;
    if (session == null) return null;
    return session.endAndArchive(endingId: endingId, endingTitle: endingTitle);
  }

  Future<void> _disposeSession() async {
    await _subscription?.cancel();
    _subscription = null;
    await _session?.dispose();
    _session = null;
  }

  void _fail(String code, String message) {
    state = state.copyWith(
      status: TableStatus.error,
      busy: false,
      errorCode: code,
      errorMessage: message,
    );
  }
}
