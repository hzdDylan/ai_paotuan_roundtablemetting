import '../../engine/dice/dice.dart';
import '../../engine/director/director.dart';
import '../../engine/rules/character_rules.dart';
import '../../engine/rules/character_sheet.dart';
import '../../engine/rules/check.dart';
import '../../engine/scenario/scenario.dart';
import '../../engine/scenario/scene_flow.dart';

/// 一次动作的检定结果集合。
class CheckBatch {
  const CheckBatch({
    required this.rolls,
    required this.fatalFumble,
    required this.humanFailed,
    required this.dramatic,
  });

  final List<Roll> rolls;
  final SceneFumble? fatalFumble;
  final bool humanFailed;
  final bool dramatic;

  bool get isEmpty => rolls.isEmpty;
}

/// 检定计算：基础值、掷骰、大失败映射。纯计算，不碰 I/O。
final class CheckResolver {
  const CheckResolver({required this.rng});

  final RngPort rng;

  int baseValueFor({
    required CheckDecl decl,
    required CharacterSheet character,
    required List<ActorRef> participants,
  }) {
    if (decl.actorId == 'human') {
      if (decl.skill != null) return character.skills[decl.skill!];
      return character.attributes[decl.attribute!];
    }
    final isBp = participants.any(
      (actor) => actor.id == decl.actorId && actor.kind == ActorKind.bp,
    );
    if (isBp) return bpSkillValue;
    return decl.skill?.baseValue ?? attributeBase;
  }

  CheckBatch resolve({
    required List<CheckDecl> decls,
    required CharacterSheet character,
    required List<ActorRef> participants,
    required SceneDef scene,
    required int startSeq,
  }) {
    final rolls = <Roll>[];
    var seq = startSeq;
    SceneFumble? fatal;
    var humanFailed = false;
    var dramatic = false;

    for (final decl in decls) {
      final roll = resolveCheck(
        decl: decl,
        baseSkill: baseValueFor(
          decl: decl,
          character: character,
          participants: participants,
        ),
        seq: ++seq,
        die: rollDie(rng),
      );
      rolls.add(roll);
      if (!roll.outcome.isSuccess) dramatic = true;
      if (roll.actorId == 'human' && roll.outcome == Outcome.fail) {
        humanFailed = true;
      }
      fatal ??= fatalFumbleFor(scene, roll, roll.actorId);
    }

    return CheckBatch(
      rolls: rolls,
      fatalFumble: fatal,
      humanFailed: humanFailed,
      dramatic: dramatic,
    );
  }
}
