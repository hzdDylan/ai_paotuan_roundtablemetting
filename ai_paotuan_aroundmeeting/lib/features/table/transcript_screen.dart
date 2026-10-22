import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../engine/knowledge/game_event.dart';
import 'table_controller.dart';

/// 对话历史（半模态）：不跳路由，避免回来时对局被重置。
class TranscriptSheet extends ConsumerWidget {
  const TranscriptSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);
    final events = state.events;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Text('记 录', style: sectionLabel()),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x33C9A227)),
          Flexible(
            child: events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      '还没有记录。',
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) =>
                        _EventRow(event: events[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final GameEvent event;

  @override
  Widget build(BuildContext context) {
    if (event.kind == EventKind.roll) {
      final die = event.payload['die'];
      final outcome = event.payload['outcome'];
      return _Bubble(
        accent: AppColors.brass,
        speaker: '骰子',
        text: '骰值 $die · $outcome',
      );
    }

    if (event.kind == EventKind.inputAllowed ||
        event.kind == EventKind.inputRejected ||
        event.kind == EventKind.sessionStart ||
        event.kind == EventKind.sceneStart ||
        event.kind == EventKind.checkDeclared) {
      return const SizedBox.shrink();
    }

    final baseSpeaker =
        event.payload['speaker']?.toString() ?? event.actorId ?? '旁白';
    final setupFor = event.payload['setup_for']?.toString();
    final speaker = setupFor == null || setupFor.isEmpty
        ? baseSpeaker
        : '$baseSpeaker · 要检定（$setupFor）';
    return _Bubble(speaker: speaker, text: event.text);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.speaker,
    required this.text,
    this.accent = AppColors.inkMuted,
  });

  final String speaker;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x22C9A227)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            speaker,
            style: TextStyle(fontSize: 11, letterSpacing: 1, color: accent),
          ),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}
