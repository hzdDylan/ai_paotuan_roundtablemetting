import 'package:ai_paotuan_aroundmeeting/engine/director/director.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/audience.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/game_event.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/knowledge_filter.dart';
import 'package:flutter_test/flutter_test.dart';

GameEvent event(int seq, String text, Audience audience) => GameEvent(
  seq: seq,
  kind: EventKind.dialogue,
  audience: audience,
  payload: {'text': text},
);

void main() {
  const filter = KnowledgeFilter();
  const stella = Viewer(id: 'bp_stella', kind: ActorKind.bp);
  const npc = Viewer(id: 'npc_gu', kind: ActorKind.npc);
  const kp = Viewer(id: 'kp', kind: ActorKind.kp);

  final events = <GameEvent>[
    event(1, '公开：你们按了门铃', const Audience.public()),
    event(2, 'Stella 的秘密：她欠顾先生钱', const Audience.privateTo('bp_stella')),
    event(3, '老陈的秘密：他知道地下室', const Audience.privateTo('bp_chen')),
    event(4, '线索：他袖口有泥', const Audience.party()),
    event(5, 'KP 专属：地下室关着人', const Audience.kpOnly()),
  ];

  test('KP 看得到全部事件', () {
    expect(filter.visibleTo(kp, events).length, events.length);
  });

  test('Stella 看不到老陈的秘密', () {
    final corpus = filter.debugCorpus(stella, events);
    expect(corpus, contains('她欠顾先生钱'));
    expect(corpus, isNot(contains('地下室')));
  });

  test('NPC 看不到 party 线索，也看不到 KP 专属', () {
    final corpus = filter.debugCorpus(npc, events);
    expect(corpus, contains('按了门铃'));
    expect(corpus, isNot(contains('袖口有泥')));
    expect(corpus, isNot(contains('关着人')));
  });

  test('BP 能看到 party 线索', () {
    expect(filter.debugCorpus(stella, events), contains('袖口有泥'));
  });

  test('滑窗只取最近 N 条可见事件', () {
    final window = filter.window(stella, events, limit: 2);
    expect(window.length, 2);
    // Stella 可见的是 1、2、4，最后两条是 2、4。
    expect(window.map((e) => e.seq), [2, 4]);
  });

  test('audience 标签往返', () {
    for (final audience in <Audience>[
      const Audience.public(),
      const Audience.kpOnly(),
      const Audience.party(),
      const Audience.privateTo('bp_stella'),
    ]) {
      final restored = Audience.fromTag(audience.toTag());
      expect(restored.kind, audience.kind);
      expect(restored.actorId, audience.actorId);
    }
  });
}
