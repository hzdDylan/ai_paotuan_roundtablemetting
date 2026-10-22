import 'dart:convert';
import 'dart:io';

import '../knowledge/game_event.dart';
import '../rules/check.dart';
import '../rules/character_sheet.dart';
import '../scenario/scenario.dart';

/// 归档摘要（列表页用）。
class ArchiveRecord {
  const ArchiveRecord({
    required this.sessionId,
    required this.scenarioTitle,
    required this.endingTitle,
    required this.beatCount,
    required this.partySize,
    required this.endedAt,
    required this.path,
    this.oneLine = '',
    this.lastRoll = '',
    this.review = '',
  });

  final String sessionId;
  final String scenarioTitle;
  final String endingTitle;
  final int beatCount;
  final int partySize;
  final DateTime endedAt;
  final String path;

  /// 结局一句话（取最后一拍叙述）。
  final String oneLine;

  /// 最后一骰的可读描述，如「话术 48 成功」。
  final String lastRoll;

  /// KP 对本局的复盘评价。
  final String review;

  bool get isValid => sessionId.isNotEmpty;
}

/// 归档生成（D-23 = A：全量事件快照；D-24 = D：不导出）。
class Archiver {
  const Archiver(this.root);

  final Directory root;

  /// 整包删除（Q-07：不留摘要）。
  Future<void> delete(String sessionId) async {
    final dir = Directory('${root.path}/sessions/$sessionId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<ArchiveRecord> seal({
    required String sessionId,
    required Scenario scenario,
    required CharacterSheet character,
    required List<GameEvent> events,
    required List<Roll> rolls,
    required DateTime startedAt,
    String endingId = 'unfinished',
    String endingTitle = '未完成的局',
    String oneLine = '你中途离开了。',
    String review = '',
  }) async {
    final endedAt = DateTime.now();
    final dir = Directory('${root.path}/sessions/$sessionId');
    await dir.create(recursive: true);

    final party = <Map<String, dynamic>>[
      {
        'id': 'human',
        'name': character.name.isEmpty ? '无名' : character.name,
        'role': 'player',
        'occupation': character.occupation,
        'attrs': character.attributes.toJson(),
        'skills': character.skills.toJson(),
        'items': character.items.map((item) => item.toJson()).toList(),
      },
      for (final actor in scenario.actors)
        if (actor.kind == ActorKindRef.bp)
          {
            'id': actor.id,
            'name': actor.name,
            'role': 'bp',
            'goal': actor.goal,
          },
      for (final npc in scenario.npcs)
        {'id': npc.id, 'name': npc.name, 'role': 'npc', 'goal': npc.goal},
    ];

    final highlights = _pickHighlights(events);
    final archive = <String, dynamic>{
      'schema_version': 1,
      'meta': {
        'archive_id': 'ar_${sessionId.replaceFirst('sess_', '')}',
        'scenario': {
          'id': scenario.id,
          'version': scenario.version,
          'title': scenario.title,
        },
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_minutes': endedAt.difference(startedAt).inMinutes,
        'beat_count': events.where((e) => e.kind == EventKind.dialogue).length,
        'party_size': scenario.partySize,
      },
      'party': party,
      'events': events.map((event) => event.toJson()).toList(),
      'rolls': rolls.map((roll) => roll.toJson()).toList(),
      'ending': {
        'id': endingId,
        'title': endingTitle,
        'one_line': oneLine,
        'review': review,
        'last_roll': rolls.isEmpty
            ? null
            : {
                'skill': rolls.last.label,
                'die': rolls.last.die,
                'outcome': rolls.last.outcome.label,
                'target': rolls.last.target,
              },
      },
      'highlights': highlights,
    };

    final file = File('${dir.path}/archive.json');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(archive),
      flush: true,
    );
    await tmp.rename(file.path);

    return ArchiveRecord(
      sessionId: sessionId,
      scenarioTitle: scenario.title,
      endingTitle: endingTitle,
      beatCount: (archive['meta'] as Map)['beat_count'] as int,
      partySize: scenario.partySize,
      endedAt: endedAt,
      path: file.path,
    );
  }

  Future<List<ArchiveRecord>> list() async {
    final sessionsDir = Directory('${root.path}/sessions');
    if (!await sessionsDir.exists()) return const <ArchiveRecord>[];

    final records = <ArchiveRecord>[];
    await for (final entity in sessionsDir.list()) {
      if (entity is! Directory) continue;
      final file = File('${entity.path}/archive.json');
      if (!await file.exists()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final meta = decoded['meta'];
        final ending = decoded['ending'];
        final scenario = meta is Map ? meta['scenario'] : null;
        records.add(
          ArchiveRecord(
            sessionId: entity.path.split(Platform.pathSeparator).last,
            scenarioTitle: scenario is Map
                ? (scenario['title']?.toString() ?? '未知剧本')
                : '未知剧本',
            endingTitle: ending is Map
                ? (ending['title']?.toString() ?? '未完成')
                : '未完成',
            beatCount: meta is Map
                ? ((meta['beat_count'] as num?)?.toInt() ?? 0)
                : 0,
            partySize: meta is Map
                ? ((meta['party_size'] as num?)?.toInt() ?? 0)
                : 0,
            endedAt: meta is Map
                ? (DateTime.tryParse(meta['ended_at']?.toString() ?? '') ??
                      DateTime.now())
                : DateTime.now(),
            path: file.path,
            oneLine: ending is Map
                ? (ending['one_line']?.toString() ?? '')
                : '',
            lastRoll: _formatLastRoll(ending),
            review: ending is Map ? (ending['review']?.toString() ?? '') : '',
          ),
        );
      } on FormatException {
        continue;
      }
    }

    records.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return records;
  }

  /// 读取某个归档里的全部事件（记录页复用）。
  Future<List<GameEvent>> readEvents(String archivePath) async {
    final decoded = jsonDecode(await File(archivePath).readAsString());
    if (decoded is! Map) return const <GameEvent>[];
    final raw = decoded['events'];
    if (raw is! List) return const <GameEvent>[];
    return <GameEvent>[
      for (final item in raw)
        if (item is Map)
          GameEvent.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
    ];
  }

  String _formatLastRoll(Object? ending) {
    if (ending is! Map) return '';
    final roll = ending['last_roll'];
    if (roll is! Map) return '';
    final skill = roll['skill']?.toString() ?? '';
    final die = roll['die']?.toString() ?? '';
    final outcome = roll['outcome']?.toString() ?? '';
    if (skill.isEmpty || die.isEmpty) return '';
    return '$skill $die $outcome';
  }

  List<Map<String, dynamic>> _pickHighlights(List<GameEvent> events) {
    final highlights = <Map<String, dynamic>>[];
    for (final event in events) {
      if (highlights.length >= 5) break;
      final intent = event.payload['intent']?.toString();
      final outcome = event.payload['outcome']?.toString();
      if (intent == 'taunt' || intent == 'refuse' || intent == 'shift') {
        highlights.add({
          'seq': event.seq,
          'type': intent,
          'actor': event.actorId,
          'quote': event.text,
        });
      } else if (outcome == 'fumble') {
        highlights.add({
          'seq': event.seq,
          'type': 'fumble',
          'actor': event.actorId,
          'quote': event.text,
        });
      }
    }
    return highlights;
  }
}
