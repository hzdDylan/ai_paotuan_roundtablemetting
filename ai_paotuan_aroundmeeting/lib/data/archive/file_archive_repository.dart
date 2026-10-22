import '../../application/ports/archive_repository.dart';
import '../../engine/archive/archive_record.dart';
import '../../engine/knowledge/game_event.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/scenario.dart';
import 'archiver.dart';

/// 文件归档端口实现。
final class FileArchiveRepository implements ArchiveRepository {
  const FileArchiveRepository(this._archiver);

  final Archiver _archiver;

  @override
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
  }) => _archiver.seal(
    sessionId: sessionId,
    scenario: scenario,
    character: character,
    events: events,
    rolls: rolls,
    startedAt: startedAt,
    endingId: endingId,
    endingTitle: endingTitle,
    oneLine: oneLine,
    review: review,
  );

  @override
  Future<List<ArchiveRecord>> list() => _archiver.list();

  @override
  Future<List<GameEvent>> readEvents(String archivePath) =>
      _archiver.readEvents(archivePath);

  @override
  Future<void> delete(String sessionId) => _archiver.delete(sessionId);
}
