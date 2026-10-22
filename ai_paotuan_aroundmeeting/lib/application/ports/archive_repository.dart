import '../../engine/archive/archive_record.dart';
import '../../engine/knowledge/game_event.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/scenario.dart';

/// 归档端口：列表、详情、删除、封存。
abstract interface class ArchiveRepository {
  Future<ArchiveRecord> seal({
    required String sessionId,
    required Scenario scenario,
    required CharacterSheet character,
    required List<GameEvent> events,
    required List<Roll> rolls,
    required DateTime startedAt,
    String endingId = 'unfinished',
    String endingTitle = '未完成的局',
    String oneLine = '你中途离开了。',
    String review = '',
  });

  Future<List<ArchiveRecord>> list();

  Future<List<GameEvent>> readEvents(String archivePath);

  Future<void> delete(String sessionId);
}
