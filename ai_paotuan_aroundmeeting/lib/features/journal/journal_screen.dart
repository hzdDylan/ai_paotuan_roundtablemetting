import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme.dart';
import '../../engine/archive/archiver.dart';
import '../../engine/knowledge/game_event.dart';

/// 记忆回廊（PRD 05 §5）：本机归档，只读、不导出。
class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archives = ref.watch(archiveListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          '记 忆 回 廊',
          style: TextStyle(fontSize: 16, letterSpacing: 4),
        ),
      ),
      body: archives.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取归档失败：$error')),
        data: (records) {
          if (records.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hourglass_empty,
                      size: 48,
                      color: AppColors.inkMuted,
                    ),
                    SizedBox(height: 16),
                    Text('还没有归档。跑一局，回来看看。'),
                    SizedBox(height: 8),
                    Text(
                      '归档只保存在本机，不提供导出。',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final record = records[index];
              return Dismissible(
                key: ValueKey<String>(record.sessionId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: AppColors.blood,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete_outline),
                ),
                confirmDismiss: (_) => _confirmDelete(context, record),
                onDismissed: (_) => _deleteArchive(ref, record),
                child: _ArchiveCard(
                  record: record,
                  onTap: () => _showArchive(context, ref, record),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    ArchiveRecord record,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('删除归档？', style: TextStyle(fontSize: 16)),
        content: Text('「${record.scenarioTitle}」这一局会被彻底删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.blood),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteArchive(WidgetRef ref, ArchiveRecord record) async {
    final root = await ref.read(fileDirsProvider).appData();
    await Archiver(root).delete(record.sessionId);
    ref.invalidate(archiveListProvider);
  }

  Future<void> _showArchive(
    BuildContext context,
    WidgetRef ref,
    ArchiveRecord record,
  ) async {
    final root = await ref.read(fileDirsProvider).appData();
    final events = await Archiver(root).readEvents(record.path);
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.92,
        builder: (innerContext, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.scenarioTitle,
                          style: const TextStyle(
                            fontFamily: 'serif',
                            fontSize: 18,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      Text(
                        record.endingTitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.brass,
                        ),
                      ),
                    ],
                  ),
                  if (record.oneLine.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      record.oneLine,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                  if (record.review.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'KP 评价',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: AppColors.brass,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.review,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                  if (record.lastRoll.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '最后一骰：${record.lastRoll}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.brass,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: events.length,
                itemBuilder: (context, index) =>
                    _ArchiveEventRow(event: events[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.record, required this.onTap});

  final ArchiveRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = record.endedAt;
    final stamp =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        ' ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x44C9A227)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.scenarioTitle,
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontSize: 17,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Text(
                  record.endingTitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.brass),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$stamp · ${record.partySize} 人 · ${record.beatCount} 拍',
              style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
            ),
            if (record.oneLine.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                record.oneLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.ink,
                ),
              ),
            ],
            if (record.lastRoll.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '最后一骰：${record.lastRoll}',
                style: const TextStyle(fontSize: 11, color: AppColors.brass),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArchiveEventRow extends StatelessWidget {
  const _ArchiveEventRow({required this.event});

  final GameEvent event;

  @override
  Widget build(BuildContext context) {
    switch (event.kind) {
      case EventKind.roll:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '骰子：${event.payload['skill'] ?? ''} '
            '${event.payload['die']} · ${event.payload['outcome']}',
            style: const TextStyle(fontSize: 11, color: AppColors.brass),
          ),
        );
      case EventKind.inputAllowed:
      case EventKind.inputRejected:
      case EventKind.sessionStart:
      case EventKind.sceneStart:
      case EventKind.checkDeclared:
        return const SizedBox.shrink();
      case EventKind.interjection:
        return const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            '……（插话）',
            style: TextStyle(fontSize: 11, color: AppColors.blood),
          ),
        );
      default:
        final text = event.text;
        if (text.isEmpty) return const SizedBox.shrink();
        final baseSpeaker =
            event.payload['speaker']?.toString() ?? event.actorId ?? '旁白';
        final setupFor = event.payload['setup_for']?.toString();
        final speaker = setupFor == null || setupFor.isEmpty
            ? baseSpeaker
            : '$baseSpeaker · 要检定（$setupFor）';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                speaker,
                style: const TextStyle(fontSize: 10, color: AppColors.inkMuted),
              ),
              Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ),
        );
    }
  }
}
