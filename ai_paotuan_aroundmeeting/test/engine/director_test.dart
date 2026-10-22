import 'package:ai_paotuan_aroundmeeting/engine/director/director.dart';
import 'package:flutter_test/flutter_test.dart';

const human = ActorRef(
  id: 'human',
  name: 'Joe',
  kind: ActorKind.human,
  tags: {'话术', '心理学'},
);
const stella = ActorRef(
  id: 'bp_stella',
  name: 'Stella',
  kind: ActorKind.bp,
  tags: {'话术'},
);
const chen = ActorRef(
  id: 'bp_chen',
  name: '老陈',
  kind: ActorKind.bp,
  tags: {'侦查'},
);
const gu = ActorRef(id: 'npc_gu', name: '顾先生', kind: ActorKind.npc);

Director buildDirector() => Director();

void main() {
  test('玩家点名 → 立刻轮到玩家', () {
    final pick = buildDirector().pick(
      const DirectorContext(
        participants: [human, stella, chen, gu],
        humanId: 'human',
        humanRequested: true,
      ),
    )!;
    expect(pick.actorId, 'human');
    expect(pick.reason, PickReason.playerRequested);
  });

  test('玩家 3 拍没说话 → 提示式轮到玩家', () {
    final pick = buildDirector().pick(
      const DirectorContext(
        participants: [human, stella, chen],
        humanId: 'human',
        beatsSinceHuman: 3,
        beatsSince: {'bp_stella': 0, 'bp_chen': 1},
      ),
    )!;
    expect(pick.actorId, 'human');
    expect(pick.reason, PickReason.humanSilentThree);
  });

  test('玩家上一拍失败 → BP 补位', () {
    final pick = buildDirector().pick(
      const DirectorContext(
        participants: [human, stella, chen, gu],
        humanId: 'human',
        lastHumanFailed: true,
        beatsSinceHuman: 1,
        beatsSince: {'bp_stella': 1, 'bp_chen': 4, 'npc_gu': 2},
      ),
    )!;
    expect(pick.actorId, 'bp_chen', reason: '最久没说话的 BP 优先补位');
    expect(pick.reason, PickReason.backupAfterFail);
  });

  test('没有 BP 时，补位退化为 NPC', () {
    final pick = buildDirector().pick(
      const DirectorContext(
        participants: [human, gu],
        humanId: 'human',
        lastHumanFailed: true,
        beatsSinceHuman: 1,
        beatsSince: {'npc_gu': 1},
      ),
    )!;
    expect(pick.actorId, 'npc_gu');
    expect(pick.reason, PickReason.backupAfterFail);
  });

  test('只有玩家时直接交回玩家', () {
    final pick = buildDirector().pick(
      const DirectorContext(
        participants: [human],
        humanId: 'human',
        beatsSinceHuman: 1,
      ),
    )!;
    expect(pick.actorId, 'human');
    expect(pick.reason, PickReason.handBack);
  });

  test('空桌返回 null', () {
    expect(
      buildDirector().pick(
        const DirectorContext(participants: [], humanId: 'human'),
      ),
      isNull,
    );
  });

  group('P1 发言冲动', () {
    test('被点名的人接话', () {
      final pick = buildDirector().pick(
        const DirectorContext(
          participants: [human, stella, chen, gu],
          humanId: 'human',
          beatsSinceHuman: 1,
          initiative: {'bp_stella': 0, 'bp_chen': 0, 'npc_gu': 0},
          lastUtterance: 'Stella，你怎么看？',
          beatsSince: {'bp_stella': 1, 'bp_chen': 3, 'npc_gu': 2},
        ),
      )!;
      expect(pick.actorId, 'bp_stella');
      expect(pick.reason, PickReason.initiative);
    });

    test('没人憋不住就交回玩家，不搞轮流', () {
      final pick = buildDirector().pick(
        const DirectorContext(
          participants: [human, stella, chen, gu],
          humanId: 'human',
          beatsSinceHuman: 1,
          initiative: {'bp_stella': 2, 'bp_chen': 0, 'npc_gu': 1},
          lastUtterance: '门开了。',
          beatsSince: {'bp_stella': 1, 'bp_chen': 3, 'npc_gu': 2},
        ),
      )!;
      expect(pick.actorId, 'human');
      expect(pick.reason, PickReason.handBack);
    });

    test('憋满 10 的人会被社交压力顶出来', () {
      final pick = buildDirector().pick(
        const DirectorContext(
          participants: [human, stella, chen, gu],
          humanId: 'human',
          beatsSinceHuman: 1,
          initiative: {'bp_stella': 10, 'bp_chen': 0, 'npc_gu': 0},
          lastUtterance: '门开了。',
        ),
      )!;
      expect(pick.actorId, 'bp_stella');
      expect(pick.reason, PickReason.initiative);
    });

    test('侧聊：对另一个 BP 低声说', () {
      final pick = buildDirector().pick(
        const DirectorContext(
          participants: [human, stella, chen, gu],
          humanId: 'human',
          beatsSinceHuman: 1,
          initiative: {'bp_stella': 6, 'bp_chen': 8, 'npc_gu': 0},
          lastUtterance: '门开了。',
          lastEventDramatic: true,
          allowSideChat: true,
        ),
      )!;
      expect(pick.actorId, 'bp_chen');
      expect(pick.reason, PickReason.sideChat);
      expect(pick.sideChatTargetId, 'bp_stella');
    });

    test('不允许侧聊时走普通开口', () {
      final pick = buildDirector().pick(
        const DirectorContext(
          participants: [human, stella, chen, gu],
          humanId: 'human',
          beatsSinceHuman: 1,
          initiative: {'bp_stella': 6, 'bp_chen': 8, 'npc_gu': 0},
          lastUtterance: '门开了。',
          lastEventDramatic: true,
        ),
      )!;
      expect(pick.actorId, isNot('human'));
      expect(pick.sideChatTargetId, isNull);
    });
  });
}
