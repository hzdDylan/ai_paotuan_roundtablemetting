import '../rules/check.dart';
import 'actor_turn.dart';

/// beat 级事件（SE §3.1）。
sealed class TurnEvent {
  const TurnEvent();
}

/// 请求推进下一拍（由 shell 在 idle / evaluating 时发出）。
final class BeatRequested extends TurnEvent {
  const BeatRequested();
}

/// Director 已选出行动者。
final class ActorPicked extends TurnEvent {
  const ActorPicked({required this.actorId, this.reason = ''});

  final String actorId;
  final String reason;
}

/// 行动者已产出（BP 台词 / KP 回应）。
final class ActorProduced extends TurnEvent {
  const ActorProduced(this.turn);

  final ActorTurn turn;
}

/// KP 已声明检定（技能 + 难度 + 代价）。
final class CheckDeclared extends TurnEvent {
  const CheckDeclared(this.decl);

  final CheckDecl decl;
}

/// 骰值已落定。
final class DieRolled extends TurnEvent {
  const DieRolled(this.roll);

  final Roll roll;
}

/// KP 已按骰值叙述完毕。
final class NarrationProduced extends TurnEvent {
  const NarrationProduced(this.text);

  final String text;
}

/// 玩家插话（只在 BP/NPC 说话时允许，由 shell 先判 D-08）。
final class InterjectRequested extends TurnEvent {
  const InterjectRequested({required this.targetActorId});

  final String targetActorId;
}

/// 本拍失败。
final class BeatFailed extends TurnEvent {
  const BeatFailed({required this.code, this.message = ''});

  final String code;
  final String message;
}

/// 本拍收尾（状态变化已应用）。
final class BeatFinished extends TurnEvent {
  const BeatFinished();
}

/// 场景结算完毕，进入转场。
final class SceneClosed extends TurnEvent {
  const SceneClosed();
}
