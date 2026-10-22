import '../../engine/director/director.dart';
import '../../engine/knowledge/audience.dart';
import '../../engine/knowledge/game_event.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/scenario.dart';
import '../../engine/turn/kp_turn.dart';
import '../ports/llm_gateway.dart';
import 'check_resolver.dart';
import 'event_recorder.dart';

/// 一次或多次检定的完整结算结果。
class CheckFlowResult {
  const CheckFlowResult({
    required this.rolls,
    required this.events,
    required this.narration,
    required this.fatalFumble,
    required this.dramatic,
    required this.humanFailed,
  });

  final List<Roll> rolls;
  final List<GameEvent> events;
  final KpNarration narration;
  final SceneFumble? fatalFumble;
  final bool dramatic;
  final bool humanFailed;
}

/// 检定流程：掷骰 → 组检定事件 → 请 KP 统一叙述 → 组结果事件。
///
/// 只负责一个动作批次，不推进场景、不改 TableState。
final class CheckFlow {
  const CheckFlow({
    required this.llm,
    required this.resolver,
    required this.recorder,
  });

  final LlmGateway llm;
  final CheckResolver resolver;
  final EventRecorder recorder;

  Future<CheckFlowResult> run({
    required List<CheckDecl> decls,
    required Scenario scenario,
    required SceneDef scene,
    required CharacterSheet character,
    required List<ActorRef> participants,
    required List<GameEvent> events,
    required Map<String, String> actorNames,
  }) async {
    final batch = resolver.resolve(
      decls: decls,
      character: character,
      participants: participants,
      scene: scene,
      startSeq: recorder.rollSeq,
    );
    final rolls = batch.rolls;
    if (rolls.isEmpty) {
      throw StateError('没有可结算的检定');
    }
    recorder
      ..setRollSeq(rolls.last.seq)
      ..addRolls(rolls);

    final checkEvents = <GameEvent>[];
    for (var i = 0; i < decls.length; i++) {
      final decl = decls[i];
      final roll = rolls[i];
      final baseSkill = resolver.baseValueFor(
        decl: decl,
        character: character,
        participants: participants,
      );
      checkEvents.add(
        recorder.make(
          EventKind.checkDeclared,
          Audience.public(),
          actorId: decl.actorId,
          payload: <String, dynamic>{
            'skill': decl.label,
            'base_skill': baseSkill,
            'difficulty': decl.difficulty.name,
            'target': roll.target,
            'stakes': decl.stakes,
          },
        ),
      );
      checkEvents.add(
        recorder.make(
          EventKind.roll,
          Audience.public(),
          actorId: decl.actorId,
          payload: roll.toJson(),
        ),
      );
    }

    final narration = await llm.kpNarration(
      scenario: scenario,
      scene: scene,
      rolls: rolls,
      actorNames: actorNames,
      events: <GameEvent>[...events, ...checkEvents],
      fatalConsequence: batch.fatalFumble?.text ?? '',
    );

    final resultEvent = recorder.make(
      EventKind.checkResult,
      Audience.public(),
      payload: <String, dynamic>{
        'outcome': rolls.map((roll) => roll.outcome.name).join(','),
        'text': narration.displayText,
        'speaker': 'KP',
        'rolls': rolls.map((roll) => roll.toJson()).toList(),
      },
    );

    return CheckFlowResult(
      rolls: rolls,
      events: <GameEvent>[...checkEvents, resultEvent],
      narration: narration,
      fatalFumble: batch.fatalFumble,
      dramatic: batch.dramatic,
      humanFailed: batch.humanFailed,
    );
  }
}
