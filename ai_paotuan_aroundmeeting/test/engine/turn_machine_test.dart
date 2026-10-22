import 'package:ai_paotuan_aroundmeeting/engine/rules/character_rules.dart';
import 'package:ai_paotuan_aroundmeeting/engine/rules/check.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/actor_turn.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/effect.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/turn_event.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/turn_machine.dart';
import 'package:ai_paotuan_aroundmeeting/engine/turn/turn_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const machine = TurnMachine();

  test('完整一拍：从 idle 走到 evaluating', () {
    var state = const BeatState();
    expect(state.phase, BeatPhase.idle);

    var transition = machine.reduce(state, const BeatRequested());
    state = transition.state;
    expect(state.phase, BeatPhase.picking);

    transition = machine.reduce(state, const ActorPicked(actorId: 'bp_stella'));
    state = transition.state;
    expect(state.phase, BeatPhase.generating);
    expect(state.actorId, 'bp_stella');
    expect(transition.effects.whereType<CallActorTurn>(), hasLength(1));

    transition = machine.reduce(
      state,
      const ActorProduced(
        ActorTurn(speech: '您好，顾先生。', wantsCheckSkill: Skill.persuade),
      ),
    );
    state = transition.state;
    expect(state.phase, BeatPhase.declaringCheck);
    expect(transition.effects.whereType<CallCheckDeclaration>(), hasLength(1));
    expect(transition.effects.whereType<ShowSegment>(), hasLength(1));

    const decl = CheckDecl(
      actorId: 'bp_stella',
      skill: Skill.persuade,
      difficulty: Difficulty.regular,
      stakes: '失败则他礼貌拒绝',
    );
    transition = machine.reduce(state, const CheckDeclared(decl));
    state = transition.state;
    expect(state.phase, BeatPhase.rolling);
    expect(transition.effects.whereType<CallDiceRoll>(), hasLength(1));

    final roll = resolveCheck(decl: decl, baseSkill: 65, seq: 1, die: 81);
    transition = machine.reduce(state, DieRolled(roll));
    state = transition.state;
    expect(state.phase, BeatPhase.narrating);
    expect(transition.effects.whereType<ShowDice>(), hasLength(1));
    expect(transition.effects.whereType<CallNarration>(), hasLength(1));

    transition = machine.reduce(state, const NarrationProduced('顾先生礼貌地拒绝了。'));
    state = transition.state;
    expect(state.phase, BeatPhase.applyingState);

    transition = machine.reduce(state, const BeatFinished());
    state = transition.state;
    expect(state.phase, BeatPhase.evaluating);
    expect(state.beatIndex, 1);
    expect(transition.effects.whereType<EvaluateScene>(), hasLength(1));
  });

  test('不需要检定时，直接进入 applyingState', () {
    var state = const BeatState(phase: BeatPhase.picking);
    var transition = machine.reduce(
      state,
      const ActorPicked(actorId: 'bp_chen'),
    );
    state = transition.state;

    transition = machine.reduce(
      state,
      const ActorProduced(ActorTurn(speech: '我不干。')),
    );
    state = transition.state;
    expect(state.phase, BeatPhase.applyingState);
    expect(transition.effects.whereType<CallCheckDeclaration>(), isEmpty);
  });

  test('插话只在 generating 生效（D-08）', () {
    // 生成中：可以打断。
    final generating = const BeatState(
      phase: BeatPhase.generating,
      actorId: 'bp_stella',
    );
    final allowed = machine.reduce(
      generating,
      const InterjectRequested(targetActorId: 'bp_stella'),
    );
    expect(allowed.state.phase, BeatPhase.interrupted);
    expect(allowed.effects.whereType<CancelInFlight>(), hasLength(1));
    expect(allowed.effects.whereType<RecordInterjection>(), hasLength(1));

    // 骰子结算中：不可打断（状态不变、无效果）。
    final rolling = BeatState(
      phase: BeatPhase.rolling,
      decl: const CheckDecl(
        actorId: 'bp_stella',
        skill: Skill.persuade,
        difficulty: Difficulty.regular,
      ),
    );
    final blocked = machine.reduce(
      rolling,
      const InterjectRequested(targetActorId: 'bp_stella'),
    );
    expect(blocked.state.phase, BeatPhase.rolling);
    expect(blocked.effects, isEmpty);

    // KP 叙述中：不可打断。
    final narrating = const BeatState(phase: BeatPhase.narrating);
    final blockedNarration = machine.reduce(
      narrating,
      const InterjectRequested(targetActorId: 'kp'),
    );
    expect(blockedNarration.state.phase, BeatPhase.narrating);
    expect(blockedNarration.effects, isEmpty);
  });

  test('乱序事件会被忽略（状态不变、无效果）', () {
    final state = const BeatState(phase: BeatPhase.generating);
    final transition = machine.reduce(state, const BeatFinished());
    expect(transition.state.phase, BeatPhase.generating);
    expect(transition.effects, isEmpty);
  });

  test('失败会进 Failed 并记下错误码', () {
    final state = const BeatState(phase: BeatPhase.generating);
    final transition = machine.reduce(
      state,
      const BeatFailed(code: 'E_TIMEOUT'),
    );
    expect(transition.state.phase, BeatPhase.failed);
    expect(transition.state.failureCode, 'E_TIMEOUT');
  });

  test('evaluating 可以开下一拍', () {
    final state = const BeatState(phase: BeatPhase.evaluating, beatIndex: 3);
    final transition = machine.reduce(state, const BeatRequested());
    expect(transition.state.phase, BeatPhase.picking);
    expect(transition.state.beatIndex, 3);
  });
}
