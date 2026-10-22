import '../../engine/dice/dice.dart';
import '../../engine/director/director.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/scenario/scenario.dart';
import '../ports/archive_repository.dart';
import '../ports/clock.dart';
import '../ports/event_store.dart';
import '../ports/llm_gateway.dart';
import 'session_config.dart';
import 'table_session.dart';

/// 为一次对局组装 TableSession；控制器只负责取值与订阅。
final class TableSessionFactory {
  const TableSessionFactory({
    required this.llm,
    required this.eventStore,
    required this.archives,
    required this.clock,
    required this.rng,
    this.director = const Director(),
  });

  final LlmGateway llm;
  final EventStore eventStore;
  final ArchiveRepository archives;
  final Clock clock;
  final RngPort rng;
  final Director director;

  TableSession create({
    required Scenario scenario,
    required CharacterSheet character,
    required SessionConfig config,
  }) => TableSession(
    scenario: scenario,
    character: character,
    config: config,
    llm: llm,
    eventStore: eventStore,
    archives: archives,
    clock: clock,
    rng: rng,
    director: director,
  );
}
