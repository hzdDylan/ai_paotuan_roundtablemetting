import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme.dart';
import '../../engine/scenario/scenario.dart';
import '../table/table_notifier.dart';

/// 选择剧本（PRD 05 §2.4）：只有两个入口。
class ScenarioSelectScreen extends ConsumerWidget {
  const ScenarioSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(scenarioCatalogProvider);
    final selectedId = ref.watch(selectedScenarioIdProvider);
    final character = ref.watch(characterProvider);
    final hasCharacter = character.name.trim().isNotEmpty;
    final table = ref.watch(tableProvider);
    final inProgress = table.sessionId.isNotEmpty && !table.ended;

    Future<void> openScenario(Scenario scenario) async {
      if (inProgress && table.scenarioId != scenario.id) {
        await ref.read(tableProvider.notifier).endAndArchive();
        ref.invalidate(archiveListProvider);
      }
      ref.read(selectedScenarioIdProvider.notifier).select(scenario.id);
      // 等新剧本加载完再进对局设置，避免沿用上一个剧本的 BP 上限。
      await ref.read(scenarioProvider.future);
      if (!context.mounted) return;
      if (hasCharacter) {
        context.go('/session-config');
      } else {
        ref.read(pendingScenarioProvider.notifier).mark();
        context.go('/sheet');
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text(
          '选 择 剧 本',
          style: TextStyle(fontSize: 16, letterSpacing: 4),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          catalogAsync.when(
            data: (catalog) => Column(
              children: [
                for (final scenario in catalog) ...[
                  _ScenarioCard(
                    scenario: scenario,
                    selected: scenario.id == selectedId,
                    hasCharacter: hasCharacter,
                    inProgress: inProgress && table.scenarioId == scenario.id,
                    onArchive: () async {
                      await ref.read(tableProvider.notifier).endAndArchive();
                      ref.invalidate(archiveListProvider);
                      // 只刷新列表，不自动开新局。
                    },
                    onConfigure: () async {
                      ref
                          .read(selectedScenarioIdProvider.notifier)
                          .select(scenario.id);
                      await ref.read(scenarioProvider.future);
                      if (context.mounted) context.go('/session-config');
                    },
                    onEnter: () => openScenario(scenario),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _ErrorCard(message: '$error'),
          ),
          const SizedBox(height: 4),
          _CustomCard(
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                backgroundColor: AppColors.surfaceHigh,
                title: const Text('自定义剧本', style: TextStyle(fontSize: 16)),
                content: const Text('开发中。先玩四个内置剧本。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '当前有 ${scenarioPaths.length} 个内置剧本。',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.selected,
    required this.hasCharacter,
    required this.inProgress,
    required this.onEnter,
    this.onArchive,
    this.onConfigure,
  });

  final Scenario scenario;
  final bool selected;
  final bool hasCharacter;
  final bool inProgress;
  final VoidCallback onEnter;
  final VoidCallback? onArchive;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final scene = scenario.scenes.isEmpty ? null : scenario.scenes.first;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? const [Color(0xFF46321F), Color(0xFF2A1A0A)]
              : const [Color(0xFF3A291A), Color(0xFF241708)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.brass : const Color(0x66C9A227),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scenario.title,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 22,
              letterSpacing: 2,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            scenario.subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                text: scenario.minutes.isEmpty ? '15–20 分钟' : scenario.minutes,
              ),
              _Chip(text: scenario.rating.isEmpty ? '16+' : scenario.rating),
              _Chip(text: '${scenario.partySize} 人局'),
              _Chip(text: '${scenario.scenes.length} 幕'),
              if (scene != null) _Chip(text: scene.name),
              if (selected) _Chip(text: '已选', highlight: true),
              if (inProgress) _Chip(text: '进行中', highlight: true),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  hasCharacter ? '角色已就绪' : '还没有角色，进入后会先去制卡',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
              if (inProgress && onArchive != null) ...[
                TextButton(
                  onPressed: onArchive,
                  child: const Text(
                    '归档',
                    style: TextStyle(fontSize: 12, color: AppColors.blood),
                  ),
                ),
                // 和「进入」拉开距离，避免误触归档。
                const SizedBox(width: 28),
              ],
              FilledButton(
                onPressed: onEnter,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brass,
                  foregroundColor: AppColors.parchmentInk,
                ),
                child: Text(hasCharacter ? '进入' : '先制卡'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomCard extends StatelessWidget {
  const _CustomCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x33C9A227)),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '自定义剧本',
                    style: TextStyle(fontSize: 17, letterSpacing: 2),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '形态待设计',
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0x44FFFFFF)),
              ),
              child: const Text(
                '开发中',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.blood : AppColors.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? AppColors.blood.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.blood.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.blood.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '剧本加载失败',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
