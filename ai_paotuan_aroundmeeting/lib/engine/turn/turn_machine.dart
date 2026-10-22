import 'effect.dart';
import 'turn_event.dart';
import 'turn_state.dart';

/// 一次状态转移的结果：新状态 + 要执行的效果。
class TurnTransition {
  const TurnTransition(this.state, this.effects);

  final BeatState state;
  final List<Effect> effects;
}

/// 回合状态机（SE §3.1，D-03 = A）。
///
/// 纯函数：不 await、不碰 I/O、不调 LLM。
/// 所有副作用都变成 [Effect]，由 shell 执行。
class TurnMachine {
  const TurnMachine();

  TurnTransition reduce(BeatState state, TurnEvent event) {
    switch (event) {
      case BeatRequested():
        if (state.phase != BeatPhase.idle &&
            state.phase != BeatPhase.evaluating) {
          return _ignore(state);
        }
        return TurnTransition(
          state.copyWith(phase: BeatPhase.picking),
          const <Effect>[],
        );

      case ActorPicked():
        if (state.phase != BeatPhase.picking) return _ignore(state);
        return TurnTransition(
          state.copyWith(phase: BeatPhase.generating, actorId: event.actorId),
          <Effect>[CallActorTurn(event.actorId)],
        );

      case ActorProduced():
        if (state.phase != BeatPhase.generating) return _ignore(state);
        final turn = event.turn;
        final actorId = state.actorId;
        if (actorId == null) return _ignore(state);

        if (turn.wantsCheckSkill != null) {
          return TurnTransition(
            state.copyWith(
              phase: BeatPhase.declaringCheck,
              pendingCheckSkill: turn.wantsCheckSkill,
            ),
            <Effect>[
              if (turn.speech.isNotEmpty) ShowSegment(turn.speech),
              CallCheckDeclaration(
                actorId: actorId,
                skill: turn.wantsCheckSkill!,
              ),
            ],
          );
        }

        return TurnTransition(
          state.copyWith(phase: BeatPhase.applyingState),
          <Effect>[if (turn.speech.isNotEmpty) ShowSegment(turn.speech)],
        );

      case CheckDeclared():
        if (state.phase != BeatPhase.declaringCheck) return _ignore(state);
        return TurnTransition(
          state.copyWith(phase: BeatPhase.rolling, decl: event.decl),
          <Effect>[CallDiceRoll(event.decl)],
        );

      case DieRolled():
        if (state.phase != BeatPhase.rolling) return _ignore(state);
        return TurnTransition(
          state.copyWith(phase: BeatPhase.narrating, roll: event.roll),
          <Effect>[ShowDice(event.roll), CallNarration(event.roll)],
        );

      case NarrationProduced():
        if (state.phase != BeatPhase.narrating) return _ignore(state);
        return TurnTransition(
          state.copyWith(phase: BeatPhase.applyingState),
          <Effect>[if (event.text.isNotEmpty) ShowSegment(event.text)],
        );

      case BeatFinished():
        if (state.phase != BeatPhase.applyingState) return _ignore(state);
        return TurnTransition(
          state.copyWith(
            phase: BeatPhase.evaluating,
            beatIndex: state.beatIndex + 1,
          ),
          const <Effect>[EvaluateScene()],
        );

      case SceneClosed():
        if (state.phase != BeatPhase.evaluating) return _ignore(state);
        return TurnTransition(
          state.copyWith(phase: BeatPhase.transitioning),
          const <Effect>[],
        );

      case BeatFailed():
        return TurnTransition(
          state.copyWith(phase: BeatPhase.failed, failureCode: event.code),
          const <Effect>[],
        );
    }
  }

  TurnTransition _ignore(BeatState state) =>
      TurnTransition(state, const <Effect>[]);
}
