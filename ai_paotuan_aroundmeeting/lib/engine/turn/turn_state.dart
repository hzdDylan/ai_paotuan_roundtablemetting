import '../rules/character_rules.dart';
import '../rules/check.dart';

/// beat 级状态（SE §3.1）。会话级状态不在这里。
enum BeatPhase {
  idle,
  picking,
  buildingContext,
  generating,
  declaringCheck,
  rolling,
  narrating,
  applyingState,
  evaluating,
  transitioning,
  ending,
  failed,
}

extension BeatPhaseInfo on BeatPhase {
  bool get isActive =>
      this != BeatPhase.idle &&
      this != BeatPhase.failed &&
      this != BeatPhase.ending;
}

const Object _keep = Object();

/// 一拍的状态快照（不可变）。
class BeatState {
  const BeatState({
    this.phase = BeatPhase.idle,
    this.beatIndex = 0,
    this.actorId,
    this.decl,
    this.roll,
    this.pendingCheckSkill,
    this.failureCode,
  });

  final BeatPhase phase;
  final int beatIndex;
  final String? actorId;
  final CheckDecl? decl;
  final Roll? roll;

  /// 行动者想检定的技能（等 KP 声明难度与代价）。
  final Skill? pendingCheckSkill;

  final String? failureCode;

  BeatState copyWith({
    BeatPhase? phase,
    int? beatIndex,
    Object? actorId = _keep,
    Object? decl = _keep,
    Object? roll = _keep,
    Object? pendingCheckSkill = _keep,
    Object? failureCode = _keep,
  }) => BeatState(
    phase: phase ?? this.phase,
    beatIndex: beatIndex ?? this.beatIndex,
    actorId: identical(actorId, _keep) ? this.actorId : actorId as String?,
    decl: identical(decl, _keep) ? this.decl : decl as CheckDecl?,
    roll: identical(roll, _keep) ? this.roll : roll as Roll?,
    pendingCheckSkill: identical(pendingCheckSkill, _keep)
        ? this.pendingCheckSkill
        : pendingCheckSkill as Skill?,
    failureCode: identical(failureCode, _keep)
        ? this.failureCode
        : failureCode as String?,
  );

  /// 拍结束、进入下一拍前清掉本拍的临时数据。
  BeatState nextBeat() =>
      BeatState(phase: BeatPhase.idle, beatIndex: beatIndex);

  @override
  String toString() =>
      'BeatState(${phase.name}, beat=$beatIndex, actor=$actorId)';
}
