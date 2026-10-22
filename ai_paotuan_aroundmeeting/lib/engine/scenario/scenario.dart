import '../moderation/moderation.dart';
import '../rules/check.dart';
import '../rules/character_rules.dart';

/// 剧本里的一个行动者声明（玩家 / BP）。
class ScenarioActor {
  const ScenarioActor({
    required this.id,
    required this.kind,
    required this.name,
    this.goal = '',
    this.secret = '',
    this.tags = const <String>{},
    this.quip = '',
    this.switchTrigger = '',
  });

  final String id;
  final ActorKindRef kind;
  final String name;
  final String goal;
  final String secret;
  final Set<String> tags;

  /// 一句吐槽示例，用来给 BP 定语气（不进入公开文本）。
  final String quip;

  /// 善变诱因：什么会让他/她临时改口或换边。
  final String switchTrigger;
}

/// 避免 scenario 依赖 director：剧本只关心 human / bp 两种。
enum ActorKindRef { human, bp }

/// 剧本里的 NPC 声明。
class ScenarioNpc {
  const ScenarioNpc({
    required this.id,
    required this.name,
    this.goal = '',
    this.secret = '',
    this.tags = const <String>{},
  });

  final String id;
  final String name;
  final String goal;
  final String secret;
  final Set<String> tags;
}

/// 场景时钟（3–5 格，到 0 触发出口）。
class SceneClock {
  const SceneClock({
    required this.id,
    required this.label,
    required this.max,
    this.onZero = '',
  });

  final String id;
  final String label;
  final int max;
  final String onZero;
}

/// 线索：命中条件由 KP 输出或结算规则触发。
class SceneClue {
  const SceneClue({required this.id, required this.text});

  final String id;
  final String text;
}

/// 场景出口。
class SceneExit {
  const SceneExit({required this.id, required this.to, this.when = ''});

  final String id;
  final String to;
  final String when;
}

/// 大失败后的致命收场。只有玩家的大失败会触发。
class SceneFumble {
  const SceneFumble({required this.ending, this.text = ''});

  /// 目标终幕 id；运行时会转场并归档。
  final String ending;

  /// 给 KP 的收场提示，必须写清「为什么这一局没法继续」。
  final String text;
}

/// 剧本允许的检定：只写技能/属性、难度、失败代价，**不写目标值**（D-05）。
class SceneCheck {
  const SceneCheck({
    this.skill,
    this.attribute,
    required this.difficulty,
    this.stakes = '',
    this.onFumble,
  }) : assert(skill != null || attribute != null, '检定必须有技能或属性');

  final Skill? skill;
  final Attribute? attribute;
  final Difficulty difficulty;
  final String stakes;

  String get label => skill?.label ?? attribute?.label ?? '';

  /// 可选：玩家在这项检定上大失败时，直接进入终幕。
  final SceneFumble? onFumble;
}

/// 一个场景。
class SceneDef {
  const SceneDef({
    required this.id,
    required this.name,
    required this.goal,
    this.clocks = const <SceneClock>[],
    this.clues = const <SceneClue>[],
    this.exits = const <SceneExit>[],
    this.checks = const <SceneCheck>[],
    this.fixedActions = const <String>[],
    this.ending = false,
  });

  final String id;
  final String name;
  final String goal;
  final List<SceneClock> clocks;
  final List<SceneClue> clues;
  final List<SceneExit> exits;
  final List<SceneCheck> checks;

  /// 首幕固定可选动作：开局第一拍直接给玩家，不调用 LLM。
  final List<String> fixedActions;

  /// 终幕：转场到这里即归档收束，不再需要出口与检定。
  final bool ending;
}

/// 完整剧本（只读资源，随包，D-19 / D-20）。
class Scenario {
  const Scenario({
    required this.id,
    required this.version,
    required this.title,
    this.subtitle = '',
    this.minutes = '',
    this.rating = '',
    this.partyMax = 4,
    this.opening = '',
    required this.contentScope,
    required this.actors,
    required this.npcs,
    required this.scenes,
  });

  final String id;
  final String version;
  final String title;
  final String subtitle;
  final String minutes;
  final String rating;

  /// 本剧本的桌上人数上限（不含 KP）：顾先生的晚宴为 2–4 人局。
  final int partyMax;

  /// 固定开场白：有则直接播，不再让 LLM 现编。
  final String opening;

  /// 审核判据（SE §3.9）。
  final ContentScope contentScope;

  final List<ScenarioActor> actors;
  final List<ScenarioNpc> npcs;
  final List<SceneDef> scenes;

  ScenarioActor? actorById(String id) {
    for (final actor in actors) {
      if (actor.id == id) return actor;
    }
    return null;
  }

  ScenarioNpc? npcById(String id) {
    for (final npc in npcs) {
      if (npc.id == id) return npc;
    }
    return null;
  }

  SceneDef? sceneById(String id) {
    for (final scene in scenes) {
      if (scene.id == id) return scene;
    }
    return null;
  }

  ScenarioActor? get human {
    for (final actor in actors) {
      if (actor.kind == ActorKindRef.human) return actor;
    }
    return null;
  }

  List<ScenarioActor> get bpActors =>
      actors.where((a) => a.kind == ActorKindRef.bp).toList(growable: false);

  /// 桌上人数（不含 KP，Q-01）：玩家 + BP + NPC。
  int get partySize => actors.length + npcs.length;
}
