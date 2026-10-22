import 'character_rules.dart';

/// 检定难度（SE §3.3）。
enum Difficulty { regular, hard, extreme }

extension DifficultyInfo on Difficulty {
  String get label => switch (this) {
    Difficulty.regular => '普通',
    Difficulty.hard => '困难',
    Difficulty.extreme => '极难',
  };

  /// 难度对目标值的折扣。
  double get multiplier => switch (this) {
    Difficulty.regular => 1.0,
    Difficulty.hard => 0.5,
    Difficulty.extreme => 0.2,
  };
}

/// 检定结果（SE §3.3）。
enum Outcome { critical, success, fail, fumble }

extension OutcomeInfo on Outcome {
  String get label => switch (this) {
    Outcome.critical => '大成功',
    Outcome.success => '成功',
    Outcome.fail => '失败',
    Outcome.fumble => '大失败',
  };

  bool get isSuccess => this == Outcome.critical || this == Outcome.success;
}

/// 宽档 / 窄档：只看**基础技能值**（Q-09）。
bool isWideTier(int baseSkill) => baseSkill >= wideTierThreshold;

/// 难度折扣后的目标值。目标 ≤ 0 表示「不可能成功」。
int targetFor(int baseSkill, Difficulty difficulty) => switch (difficulty) {
  Difficulty.regular => baseSkill,
  Difficulty.hard => baseSkill ~/ 2,
  Difficulty.extreme => baseSkill ~/ 5,
};

/// 大成功上沿：宽档 5，窄档 1。
int critHighFor(int baseSkill) =>
    isWideTier(baseSkill) ? wideTierCritHigh : narrowTierCritHigh;

/// 大失败下沿：宽档 100，窄档 96。
int fumbleLowFor(int baseSkill) =>
    isWideTier(baseSkill) ? wideTierFumbleLow : narrowTierFumbleLow;

/// d100 roll-under 评级。
///
/// 顺序很重要：先判大失败，再判大成功，最后按目标值判普通成败。
/// `target <= 0` 直接失败，避免「神话 0 掷出 1 也算大成功」。
Outcome judge({
  required int die,
  required int baseSkill,
  required Difficulty difficulty,
}) {
  if (die < 1 || die > 100) {
    throw ArgumentError.value(die, 'die', 'd100 的取值范围是 1–100');
  }

  final target = targetFor(baseSkill, difficulty);
  if (target <= 0) return Outcome.fail;
  if (die >= fumbleLowFor(baseSkill)) return Outcome.fumble;
  if (die <= critHighFor(baseSkill)) return Outcome.critical;
  return die <= target ? Outcome.success : Outcome.fail;
}

/// 一次检定的声明（KP 给，不含目标值 —— 目标由角色卡算）。
///
/// 检定依据二选一：技能（[skill]）或基础属性（[attribute]）。
class CheckDecl {
  const CheckDecl({
    required this.actorId,
    this.skill,
    this.attribute,
    required this.difficulty,
    this.stakes = '',
  }) : assert(skill != null || attribute != null, '检定必须有技能或属性');

  final String actorId;
  final Skill? skill;
  final Attribute? attribute;
  final Difficulty difficulty;

  /// 失败代价（一句话，给 KP 叙述用）。
  final String stakes;

  String get label => skill?.label ?? attribute?.label ?? '';
}

/// 一次已落定的掷骰（骰值不可变）。
class Roll {
  const Roll({
    required this.seq,
    required this.actorId,
    this.skill,
    this.attribute,
    required this.baseSkill,
    required this.difficulty,
    required this.target,
    required this.die,
    required this.outcome,
    this.stakes = '',
  });

  final int seq;
  final String actorId;
  final Skill? skill;
  final Attribute? attribute;

  /// 基础技能/属性值，决定大成功/大失败档位。
  final int baseSkill;

  final Difficulty difficulty;

  /// 折扣后的目标值。
  final int target;

  final int die;
  final Outcome outcome;
  final String stakes;

  bool get isSuccess => outcome.isSuccess;

  String get label => skill?.label ?? attribute?.label ?? '';

  Map<String, dynamic> toJson() => {
    'roll_seq': seq,
    'actor': actorId,
    'skill': label,
    if (attribute != null) 'attribute': attribute!.name,
    'base_skill': baseSkill,
    'difficulty': difficulty.name,
    'target': target,
    'die': die,
    'outcome': outcome.name,
    'stakes': stakes,
  };
}

/// 声明 + 基础技能 + 骰值 → 一条落定的 Roll。
Roll resolveCheck({
  required CheckDecl decl,
  required int baseSkill,
  required int seq,
  required int die,
}) {
  final target = targetFor(baseSkill, decl.difficulty);
  return Roll(
    seq: seq,
    actorId: decl.actorId,
    skill: decl.skill,
    attribute: decl.attribute,
    baseSkill: baseSkill,
    difficulty: decl.difficulty,
    target: target,
    die: die,
    outcome: judge(die: die, baseSkill: baseSkill, difficulty: decl.difficulty),
    stakes: decl.stakes,
  );
}
