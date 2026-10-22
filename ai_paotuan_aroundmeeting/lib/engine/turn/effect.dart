import '../rules/character_rules.dart';
import '../rules/check.dart';

/// 状态机只描述「该发生什么」，真正做事由 shell 执行这些效果（SE §3.1，D-03 = A）。
sealed class Effect {
  const Effect();
}

/// 调用某个行动者，产出下一段台词。
final class CallActorTurn extends Effect {
  const CallActorTurn(this.actorId);

  final String actorId;
}

/// 请 KP 为某技能声明难度与失败代价（不算目标值）。
final class CallCheckDeclaration extends Effect {
  const CallCheckDeclaration({required this.actorId, required this.skill});

  final String actorId;
  final Skill skill;
}

/// 请 shell 掷骰（骰值由 Dice 产生，不经过 LLM）。
final class CallDiceRoll extends Effect {
  const CallDiceRoll(this.decl);

  final CheckDecl decl;
}

/// 请 KP 按已落定的骰值叙述。
final class CallNarration extends Effect {
  const CallNarration(this.roll);

  final Roll roll;
}

/// 把一段文字显示到对话框（D-12：整段淡入）。
final class ShowSegment extends Effect {
  const ShowSegment(this.text);

  final String text;
}

/// 显示骰子卡。
final class ShowDice extends Effect {
  const ShowDice(this.roll);

  final Roll roll;
}

/// 场景结算：判继续 / 转场 / 结局。
final class EvaluateScene extends Effect {
  const EvaluateScene();
}
