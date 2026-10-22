import 'dart:io';

import 'package:ai_paotuan_aroundmeeting/data/storage/file_event_store.dart';
import 'package:ai_paotuan_aroundmeeting/data/storage/memory_event_store.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/audience.dart';
import 'package:ai_paotuan_aroundmeeting/engine/knowledge/game_event.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

GameEvent event(int seq, String text) => GameEvent(
  seq: seq,
  kind: EventKind.dialogue,
  audience: const Audience.public(),
  actorId: 'human',
  payload: <String, dynamic>{'text': text},
);

void main() {
  test('内存实现：追加与读取', () async {
    final store = MemoryEventStore();
    await store.appendAll('s1', <GameEvent>[event(1, '第一句')]);
    await store.appendAll('s1', <GameEvent>[event(2, '第二句')]);

    final events = await store.readAll('s1');
    expect(events, hasLength(2));
    expect(events.last.text, '第二句');
    expect(await store.listSessionIds(), <String>['s1']);
  });

  test('文件实现：追加写后能读回', () async {
    final dirs = TempDirs();
    addTearDown(dirs.dispose);

    final store = FileEventStore(dirs.root);
    await store.appendAll('sess_a', <GameEvent>[event(1, '你好')]);
    await store.appendAll('sess_a', <GameEvent>[event(2, '再见')]);

    final events = await store.readAll('sess_a');
    expect(events, hasLength(2));
    expect(events.first.seq, 1);
    expect(events.last.text, '再见');
    expect(await store.listSessionIds(), <String>['sess_a']);
  });

  test('文件实现：损坏的最后一行被丢弃', () async {
    final dirs = TempDirs();
    addTearDown(dirs.dispose);

    final store = FileEventStore(dirs.root);
    await store.appendAll('sess_b', <GameEvent>[event(1, '正常')]);

    final file = File('${dirs.root.path}/sessions/sess_b/events.ndjson');
    await file.writeAsString(
      '{"seq":2,"kind":"dialogue","audience":"public","payload":{"text":"半行"',
      mode: FileMode.append,
    );

    final events = await store.readAll('sess_b');
    expect(events, hasLength(1));
    expect(events.single.text, '正常');
  });
}
