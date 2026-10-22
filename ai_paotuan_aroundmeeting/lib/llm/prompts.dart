import '../engine/knowledge/game_event.dart';
import '../engine/moderation/moderation.dart';
import '../engine/rules/character_rules.dart';
import '../engine/rules/character_sheet.dart';
import '../engine/rules/check.dart';
import '../engine/scenario/scenario.dart';
import '../engine/scenario/scene_flow.dart';
import '../engine/turn/kp_turn.dart';

/// Prompt 组装（SE §4.10）。纯函数，便于测试与审查。
class PromptBuilder {
  const PromptBuilder();

  /// BP / 玩家角色的一轮。
  List<Map<String, String>> bpTurn({
    required Scenario scenario,
    required SceneDef scene,
    required ScenarioActor actor,
    required List<GameEvent> events,
    required List<String> others,
    String? lastSpeaker,
    String? sideChatTo,
  }) {
    final system =
        '''
你在一场中文跑团里扮演玩家角色「${actor.name}」。你不是助手，你是这个角色本人。
身份：${actor.tags.isEmpty ? '（未设定）' : actor.tags.join('、')}
本场目标：${actor.goal.isEmpty ? '（未设定）' : actor.goal}
秘密（不可主动说出）：${actor.secret.isEmpty ? '（无）' : actor.secret}
吐槽示例（只借语气，不要照念）：${actor.quip.isEmpty ? '（无）' : actor.quip}
善变诱因（被触及时可以改口，但要有代价）：${actor.switchTrigger.isEmpty ? '（无）' : actor.switchTrigger}
地点与场景：${scenario.title} · ${scene.name}（目标：${scene.goal}）
在场：${others.join('、')}
${sideChatTo == null ? '' : '你正在对「$sideChatTo」低声说话（侧聊），不是对玩家；像朋友间交换眼色，短、带潜台词。'}
规则：d100 判定，成败由系统掷骰决定，你不能宣布结果；只能替自己说话；不要提"AI/模型/系统"。
技能：全部 55（只用于系统判定，不要在台词里报数值）。
文风：口语短句，像真人张嘴说话。台词最多 2 句、每句 ≤ 25 字；动作一句话写完；不要排比、不要比喻堆砌、不用文言、不要网络梗。
输出：只输出一个 JSON 对象，不要多余文字：
{"speech":"1–3 句台词","action":"你做了什么","intent":"persuade|probe|refuse|taunt|shift|act|observe","target":"对谁","wants_check":{"skill":"话术"}|null,"private_note":"内心一句"}
可用技能：${skillLabelsForPrompt()}''';

    final user = StringBuffer()
      ..writeln('最近的桌上对话：')
      ..writeln(renderRecent(events))
      ..writeln()
      ..writeln(lastSpeaker == null ? '现在轮到你。' : '上一句是 $lastSpeaker。现在轮到你。')
      ..writeln('如果你要说服、试探、欺骗或动手，可以设 wants_check。');

    return <Map<String, String>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user.toString()},
    ];
  }

  /// KP 回应（可能包含检定声明）。
  ///
  /// [party] 是 `id → 名字`：必须把 id 明写给模型，否则它会自己编
  /// `player` / `你` 这类不存在的行动者 id（真机上因此报过 E_PARSE）。
  List<Map<String, String>> kpTurn({
    required Scenario scenario,
    required SceneDef scene,
    required List<GameEvent> events,
    required Map<String, String> party,
    required String instruction,
    Set<String> flags = const <String>{},
    Set<String> revealedClues = const <String>{},
    Map<String, int> clocks = const <String, int>{},
  }) {
    final clockLine = _clockLine(scene, clocks);
    final clues = scene.clues
        .where((clue) => !revealedClues.contains(clue.id))
        .map((clue) => '${clue.id}（${clue.text}）')
        .join('、');
    final npcs = scenario.npcs.map((npc) => npc.name).join('、');
    final partyLine = party.entries
        .map((entry) => '${entry.key}（${entry.value}）')
        .join('、');
    final exits = _exitLines(scenario, scene);

    final system =
        '''
你是中文跑团的守秘人（KP）。你拥有全场视野，但不能替玩家做决定，也不能更改骰值。
剧本：${scenario.title}（${scenario.subtitle}）
当前场景：${scene.id} · ${scene.name}；目标：${scene.goal}
时钟：$clockLine
可揭示线索：${clues.isEmpty ? '无（或已全部揭示）' : clues}
已获得标记：${flags.isEmpty ? '无' : flags.join('、')}
出口（转场时 scene 只能填这里的场景 id）：
$exits
NPC：${npcs.isEmpty ? '无' : npcs}
在场（id（名字））：$partyLine
可检定属性：${Attribute.values.map((a) => a.label).join('、')}
风格：像真人说话，短。NPC 一句话 ≤ 25 字，最多 2 句；旁白每段 ≤ 60 字；不排比、不堆比喻、不用文言；不评价玩家本人；不说"作为AI"。
不要把场景 id、标记名、线索 id 原样写进旁白或台词。
若玩家行为离谱但合理，用世界或 NPC 的反应点破它，而不是说"不允许"。
节奏：为了把局开起来，前 5 拍不要返回 end；一次普通失败只推进不结束（门还开着、话还能接）。
只有大失败、或出口已全部封死 / 关键人物离场 / 目标已不可能达成时，才可以收场；收场要写清为什么没法继续。
检定难度优先 regular，不要一上来就 extreme。
转场：只有出口条件满足时才把 scene 填成目标场景 id；条件没满足就 continue，不要硬跳。
开场与第一拍不要转场；至少让玩家有一次明确行动，或有一次检定结果推动，再转场。
输出：只输出一个 JSON 对象：
{"narration":"1–3 段旁白","npc_lines":[{"npc":"${scenario.npcs.isEmpty ? 'NPC' : scenario.npcs.first.name}","line":"台词","attitude_delta":0}],"checks":[{"actor":"上面列出的行动者 id","skill":"话术","difficulty":"regular|hard|extreme","stakes":"失败后果"}],"state":{"clocks":[{"id":"${scene.clocks.isEmpty ? 'clock_id' : scene.clocks.first.id}","delta":-1}],"clues":["clue_id"],"flags":["flag_name"]},"scene":"continue|end|出口场景id"}
一句话里有多个动作（比如挣脱、侦查、说服）时，checks 里给多条，每条一个动作；不需要检定时给空数组 []。
检定依据二选一：技能字段（skill）或属性字段（attribute，如「敏捷」「力量」），不要同时填。
注意：checks[].actor 只能填上面括号外的 id，不能写 player / 玩家 / 你。''';

    final user = StringBuffer()
      ..writeln('最近的桌上对话：')
      ..writeln(renderRecent(events))
      ..writeln()
      ..writeln(instruction);

    return <Map<String, String>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user.toString()},
    ];
  }

  /// 骰值落定后，KP 按结果叙述（可能一次结算多个动作）。
  List<Map<String, String>> kpNarration({
    required Scenario scenario,
    required SceneDef scene,
    required List<Roll> rolls,
    required String actorName,
    required List<GameEvent> events,
    String fatalConsequence = '',
  }) {
    final exits = _exitLines(scenario, scene);
    final fatalBlock = fatalConsequence.trim().isEmpty
        ? ''
        : '''
这次大失败是致命收场：$fatalConsequence
系统会在你叙述后直接结束本局。你只负责把后果写清楚，scene 填 continue 即可。
''';
    final system =
        '''
你是中文跑团的守秘人（KP）。骰值已经落定，你只能叙述结果，不能修改它。
场景：${scene.id} · ${scene.name}（目标：${scene.goal}）
出口（转场时 scene 只能填这里的场景 id）：
$exits
文风：口语、短。1–2 段旁白，每段 ≤ 60 字；NPC 一句话 ≤ 25 字；不排比、不堆比喻、不用文言；不说"作为AI"。
不要把场景 id、标记名、线索 id 原样写进旁白或台词。
失败要"失败前进"：事情更糟或更复杂，不要卡住；普通失败不要返回 end。
只有大失败、或出口已全部封死 / 关键人物离场 / 目标已不可能达成时，才可以收场；收场要写清为什么没法继续。
$fatalBlock
输出：只输出一个 JSON 对象：
{"narration":"结果叙述","npc_lines":[],"state":{"clocks":[],"clues":[],"flags":[]},"scene":"continue|end|出口场景id"}''';

    final user = StringBuffer()
      ..writeln('最近对话：')
      ..writeln(renderRecent(events))
      ..writeln()
      ..writeln('这一拍共 ${rolls.length} 个动作，逐个检定：');
    for (final roll in rolls) {
      user.writeln(
        '- $actorName 的【${roll.label}】检定：'
        '基础 ${roll.baseSkill}，${roll.difficulty.label}难度目标 ${roll.target}，'
        '骰值 ${roll.die}，结果「${roll.outcome.label}」。'
        '${roll.stakes.isEmpty ? '' : '失败代价：${roll.stakes}'}',
      );
    }
    user.writeln('请把所有结果合成一段叙述：成功与失败都要落进同一段后果里，不要逐条复述。');

    return <Map<String, String>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user.toString()},
    ];
  }

  /// 结局后的 KP 复盘评价。
  List<Map<String, String>> kpReview({
    required Scenario scenario,
    required String endingTitle,
    required String characterName,
    required List<GameEvent> events,
    required List<Roll> rolls,
  }) {
    final system =
        '''
你是这场中文跑团的守秘人（KP）。本局已经结束。
剧本：${scenario.title}
结局：$endingTitle
玩家角色：$characterName
请写 2–3 句复盘评价：这一局玩家做成了什么、付出了什么代价、这个结局留下了什么。
冷面、具体、有画面；不夸赞、不训诫；只评价已经发生的事，不提未发生的分支；不说"作为AI"。
输出：只输出一个 JSON 对象：
{"review":"2–3 句评价"}''';

    final rollLines = rolls.isEmpty
        ? '（本局没有检定）'
        : rolls
              .map(
                (roll) =>
                    '- ${roll.label} ${roll.die} ${roll.outcome.label}'
                    '${roll.stakes.isEmpty ? '' : '（${roll.stakes}）'}',
              )
              .join('\n');
    final user = StringBuffer()
      ..writeln('最近事件：')
      ..writeln(renderRecent(events, limit: 30))
      ..writeln()
      ..writeln('检定记录：')
      ..writeln(rollLines);

    return <Map<String, String>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user.toString()},
    ];
  }

  /// 给玩家的 2–4 条可选行动；只做建议，不推进剧情。
  List<Map<String, String>> actionSuggestions({
    required Scenario scenario,
    required SceneDef scene,
    required CharacterSheet character,
    required List<GameEvent> events,
    required Set<String> revealedClues,
    required Map<String, int> clocks,
  }) {
    final revealed = <String>[];
    for (final other in scenario.scenes) {
      for (final clue in other.clues) {
        if (revealedClues.contains(clue.id)) revealed.add(clue.text);
      }
    }
    final clueLine = revealed.isEmpty ? '（还没有确认的线索）' : revealed.join('、');
    final clockLine = scene.clocks.isEmpty
        ? '无'
        : scene.clocks
              .map(
                (clock) =>
                    '${clock.label}剩 ${clocks[clock.id] ?? clock.max}/${clock.max} 格',
              )
              .join('、');
    final skillLabels = Skill.values
        .where((skill) => skill != Skill.mythos)
        .map((skill) => skill.label)
        .join('、');
    final attributeLabels = Attribute.values.map((a) => a.label).join('、');

    final system =
        '''
你是这场中文跑团的副 KP，只负责给玩家推荐「现在可以做什么」，不推进剧情、不掷骰、不替玩家说话。
剧本：${scenario.title}（${scenario.subtitle}）
时代与题材：${scenario.contentScope.era} · ${scenario.contentScope.genre}
当前场景：${scene.name}；目标：${scene.goal}
玩家角色：${character.name.isEmpty ? '无名' : character.name}，${character.occupation}
当前时钟：$clockLine
已确认线索：$clueLine
在场 NPC：${scenario.npcs.map((npc) => npc.name).join('、')}
最近发生的事：
${renderRecent(events, limit: 10)}
要求：
- 给 2–4 条具体、可立即执行的动作，第一人称，贴合当前场景与时代；不要通用套话。
- 不引用未确认线索，不提前提未来场景，不写现代科技、网络梗、出戏元话语。
- 每条动作附一个最适合的检定依据：技能或基础属性，二选一。
- 技能只能从：$skillLabels；属性只能从：$attributeLabels。
- 不要宣布结果，不要写掷骰。
输出：只输出一个 JSON 对象：
{"actions":[{"text":"我走到门边，先看走廊里有没有人","skill":"侦查"},{"text":"我把杯放下，直接问他今晚在等谁","attribute":"意志"}]}''';

    return <Map<String, String>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': '请给出现在最合理的 2–4 个行动。'},
    ];
  }

  /// 审核兜底（只判玩家输入）。
  List<Map<String, String>> moderation({
    required ContentScope scope,
    required String text,
    required List<GameEvent> events,
  }) {
    final system =
        '''
你是跑团的口径审核员。判断玩家这句话是否「在本剧本的时空与题材内，且不违法」。
${scope.toPromptBlock()}

判定标准：
- 离谱、恶搞、开玩笑 → allow（这是游戏的乐趣）
- 明显出戏（现代科技、元话语）→ reject
- 违法、露骨、未成年、虐待细节 → reject
- 拿不准 → reject（安全优先）
输出：只输出一个 JSON 对象：
{"verdict":"allow|reject","category":"anachronism|metaTalk|illegal|sexual|minor|violence|none","reason":"一句话"}''';

    final user = StringBuffer()
      ..writeln('最近对话：')
      ..writeln(renderRecent(events, limit: 4))
      ..writeln()
      ..writeln('玩家这句话：$text');

    return <Map<String, String>>[
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user.toString()},
    ];
  }
}

String _clockLine(SceneDef scene, Map<String, int> values) {
  if (scene.clocks.isEmpty) return '无';
  return scene.clocks
      .map((clock) {
        final left = values[clock.id] ?? clock.max;
        return '${clock.label}（${clock.id}，剩 $left/${clock.max}）';
      })
      .join('、');
}

String _exitLines(Scenario scenario, SceneDef scene) {
  if (scene.exits.isEmpty) return '（无；本幕只能 end）';
  return scene.exits
      .map((exit) {
        final target = scenario.sceneById(exit.to);
        final name = target?.name ?? exit.to;
        return '- $name（${exit.to}）：${describeExitCondition(exit.when)}';
      })
      .join('\n');
}

/// 把最近事件渲染成「谁：说了什么」。
String renderRecent(List<GameEvent> events, {int limit = 12}) {
  final recent = events.length <= limit
      ? events
      : events.sublist(events.length - limit);
  if (recent.isEmpty) return '（还没有对话）';
  return recent
      .map((event) {
        final who = event.actorId ?? '旁白';
        final text = event.text;
        return text.isEmpty ? '$who：（无文本）' : '$who：$text';
      })
      .join('\n');
}
