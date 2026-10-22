import 'dart:math' as math;

/// 行动者类型（SE §3.2）。
enum ActorKind { human, bp, npc, kp }

extension ActorKindInfo on ActorKind {
  bool get isPlayerSide => this == ActorKind.human || this == ActorKind.bp;
  bool get isBp => this == ActorKind.bp;
}

/// 桌上的一位行动者（不含 KP 的座位）。
class ActorRef {
  const ActorRef({
    required this.id,
    required this.name,
    required this.kind,
    this.tags = const <String>{},
  });

  final String id;
  final String name;
  final ActorKind kind;

  /// 用于相关性打分的标签（如「话术」「心理学」「记者」）。
  final Set<String> tags;
}

/// 选择下一个行动者的理由码（会进日志与 UI 提示）。
enum PickReason {
  playerRequested,
  humanSilentThree,
  backupAfterFail,
  initiative,
  sideChat,
  handBack,
}

extension PickReasonInfo on PickReason {
  String get label => switch (this) {
    PickReason.playerRequested => '玩家点名',
    PickReason.humanSilentThree => '玩家已 3 拍没说话',
    PickReason.backupAfterFail => '玩家失败，队友补位',
    PickReason.initiative => '发言冲动最高',
    PickReason.sideChat => '侧聊（对另一个 BP 说）',
    PickReason.handBack => '没人接话，回玩家',
  };
}

/// 一次选人的输入快照。
class DirectorContext {
  const DirectorContext({
    required this.participants,
    required this.humanId,
    this.lastSpeakerId,
    this.humanRequested = false,
    this.lastHumanFailed = false,
    this.beatsSinceHuman = 0,
    this.beatsSince = const <String, int>{},
    this.sceneTags = const <String>{},
    this.initiative = const <String, int>{},
    this.lastUtterance = '',
    this.lastEventDramatic = false,
    this.allowSideChat = false,
  });

  /// 桌上参与者（玩家 + BP + NPC），**不含 KP**。
  final List<ActorRef> participants;

  final String humanId;
  final String? lastSpeakerId;

  /// 玩家是否明确要求自己行动。
  final bool humanRequested;

  /// 上一拍是否是玩家且失败（用于「队友补位」）。
  final bool lastHumanFailed;

  final int beatsSinceHuman;

  /// 每个行动者距离上次发言过了几拍。
  final Map<String, int> beatsSince;

  /// 当前场景的标签，用于相关性打分。
  final Set<String> sceneTags;

  /// 每个行动者的「发言冲动」0–10（P1）。为空时走旧的轮流逻辑。
  final Map<String, int> initiative;

  /// 上一句台词，用于判断「被点名 / 被提到」。
  final String lastUtterance;

  /// 刚发生失败、线索揭示等有情绪的事件。
  final bool lastEventDramatic;

  /// 本拍是否允许 BP 之间侧聊（低频）。
  final bool allowSideChat;
}

/// 选人结果。
class DirectorPick {
  const DirectorPick({
    required this.actorId,
    required this.reason,
    required this.score,
    this.detail = '',
    this.sideChatTargetId,
  });

  final String actorId;
  final PickReason reason;
  final int score;
  final String detail;

  /// 非空表示这一句是对这位 BP 低声说的（侧聊）。
  final String? sideChatTargetId;

  @override
  String toString() => 'DirectorPick($actorId, ${reason.name}, $score)';
}

/// 导演：只决定「谁来说话」，不参与演出（SE §3.2，D-04 = A）。
class Director {
  /// 纯决策，不需要随机源：抖动已去掉，避免「轮流感」。
  Director();

  /// 返回 null 表示没有可选行动者（配置错误）。
  DirectorPick? pick(DirectorContext context) {
    if (context.participants.isEmpty) return null;

    final human = _findHuman(context);
    if (human == null) return null;

    final nonHumans = context.participants
        .where((a) => a.kind != ActorKind.human)
        .toList();

    // 硬规则 1：玩家点名。
    if (context.humanRequested) {
      return DirectorPick(
        actorId: human.id,
        reason: PickReason.playerRequested,
        score: 1000,
      );
    }

    // 硬规则 2：玩家已 3 拍没说话。
    if (context.beatsSinceHuman >= 3) {
      return DirectorPick(
        actorId: human.id,
        reason: PickReason.humanSilentThree,
        score: 800,
      );
    }

    // 硬规则 4：玩家刚失败 → 队友补位（0 BP 时退化为 NPC，再退化回玩家）。
    if (context.lastHumanFailed) {
      final backup = _backupFor(context, nonHumans);
      if (backup != null) {
        return DirectorPick(
          actorId: backup.id,
          reason: PickReason.backupAfterFail,
          score: 700,
        );
      }
    }

    // P1：按「发言冲动」决定谁开口；没人憋不住就交回玩家。
    if (context.initiative.isNotEmpty) {
      final best = _bestDesire(context, nonHumans);
      if (best != null && best.desire >= 6) {
        if (context.allowSideChat &&
            best.actor.kind == ActorKind.bp &&
            !_isMentioned(best.actor, context)) {
          final target = _sideChatTarget(context, best.actor, nonHumans);
          if (target != null) {
            return DirectorPick(
              actorId: best.actor.id,
              reason: PickReason.sideChat,
              score: best.desire.round(),
              sideChatTargetId: target.id,
              detail: '对 ${target.name} 低声说',
            );
          }
        }
        return DirectorPick(
          actorId: best.actor.id,
          reason: PickReason.initiative,
          score: best.desire.round(),
        );
      }

      // 憋太久：社交压力兜底。
      final overfull = nonHumans
          .where((a) => (context.initiative[a.id] ?? 0) >= 10)
          .toList();
      if (overfull.isNotEmpty) {
        overfull.sort((a, b) {
          final bySince = (context.initiative[b.id] ?? 0).compareTo(
            context.initiative[a.id] ?? 0,
          );
          return bySince != 0 ? bySince : a.id.compareTo(b.id);
        });
        return DirectorPick(
          actorId: overfull.first.id,
          reason: PickReason.initiative,
          score: 10,
        );
      }

      return DirectorPick(
        actorId: human.id,
        reason: PickReason.handBack,
        score: 0,
      );
    }

    // 没有冲动数据（异常/旧调用）：不猜，直接交回玩家。
    return DirectorPick(
      actorId: human.id,
      reason: PickReason.handBack,
      score: 0,
    );
  }

  ActorRef? _findHuman(DirectorContext context) {
    for (final actor in context.participants) {
      if (actor.id == context.humanId || actor.kind == ActorKind.human) {
        return actor;
      }
    }
    return null;
  }

  /// 补位优先级：BP（最久没说话的）→ NPC（最久没说话的）→ null。
  ActorRef? _backupFor(DirectorContext context, List<ActorRef> nonHumans) {
    for (final kind in <ActorKind>[ActorKind.bp, ActorKind.npc]) {
      final candidates = nonHumans.where((a) => a.kind == kind).toList();
      if (candidates.isEmpty) continue;
      candidates.sort((a, b) {
        final aSince = context.beatsSince[a.id] ?? 99;
        final bSince = context.beatsSince[b.id] ?? 99;
        final bySince = bSince.compareTo(aSince);
        if (bySince != 0) return bySince;
        return a.id.compareTo(b.id);
      });
      return candidates.first;
    }
    return null;
  }

  ({ActorRef actor, double desire})? _bestDesire(
    DirectorContext context,
    List<ActorRef> nonHumans,
  ) {
    ({ActorRef actor, double desire})? best;
    for (final actor in nonHumans) {
      final desire = _desire(actor, context);
      if (best == null ||
          desire > best.desire ||
          (desire == best.desire && actor.id.compareTo(best.actor.id) < 0)) {
        best = (actor: actor, desire: desire);
      }
    }
    return best;
  }

  /// P1 的反应欲：谁被点到、谁被事件戳到、谁憋得久。
  double _desire(ActorRef actor, DirectorContext context) {
    final initiative = (context.initiative[actor.id] ?? 0) * 0.5;
    final mentioned = _isMentioned(actor, context) ? 6.0 : 0.0;
    final dramatic = context.lastEventDramatic && actor.kind == ActorKind.bp
        ? 3.0
        : 0.0;
    final relevance = _relevance(actor, context.sceneTags) * 2.0;
    final repeat = actor.id == context.lastSpeakerId ? -4.0 : 0.0;
    return initiative + mentioned + dramatic + relevance + repeat;
  }

  bool _isMentioned(ActorRef actor, DirectorContext context) =>
      actor.name.isNotEmpty && context.lastUtterance.contains(actor.name);

  /// 侧聊对象：另一个 BP，优先选也快憋不住的那个。
  ActorRef? _sideChatTarget(
    DirectorContext context,
    ActorRef speaker,
    List<ActorRef> nonHumans,
  ) {
    final candidates = nonHumans
        .where((a) => a.kind == ActorKind.bp && a.id != speaker.id)
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final byInitiative = (context.initiative[b.id] ?? 0).compareTo(
        context.initiative[a.id] ?? 0,
      );
      return byInitiative != 0 ? byInitiative : a.id.compareTo(b.id);
    });
    return candidates.first;
  }

  /// 标签重合度，归一到 0–1。
  double _relevance(ActorRef actor, Set<String> sceneTags) {
    if (sceneTags.isEmpty || actor.tags.isEmpty) return 0;
    final overlap = actor.tags.where(sceneTags.contains).length;
    return math.min(1.0, overlap / 3);
  }
}
