import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/theme.dart';
import '../../ui/widgets/wood_button.dart';

/// 首页（PRD 05 §2）：五个木牌入口 + 当前状态。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiAsync = ref.watch(apiKeyProvider);
    final character = ref.watch(characterProvider);
    final hasKey = (apiAsync.valueOrNull ?? '').isNotEmpty;
    final hasCharacter = character.name.trim().isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          const _Backdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
              children: [
                const _Ornament(),
                const SizedBox(height: 14),
                const Text(
                  '一 人 成 团',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 34,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'WE SAVED YOU A SEAT',
                  textAlign: TextAlign.center,
                  style: sectionLabel(),
                ),
                const SizedBox(height: 12),
                const Text(
                  '一个人也能有趣地跑团。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: _StatusChip(
                        icon: hasKey ? Icons.key : Icons.key_off,
                        label: hasKey ? 'API 已配置' : '未配置 API',
                        ok: hasKey,
                        onTap: () => context.go('/settings'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatusChip(
                        icon: hasCharacter
                            ? Icons.person_outline
                            : Icons.person_off_outlined,
                        label: hasCharacter
                            ? '${character.name} · ${character.occupation}'
                            : '还没有角色',
                        ok: hasCharacter,
                        onTap: () => context.go('/sheet'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                WoodButton(
                  label: '选择剧本',
                  subtitle: '顾先生的晚宴 · 自定义剧本',
                  icon: Icons.casino_outlined,
                  onTap: () => context.go('/scenarios'),
                ),
                const SizedBox(height: 14),
                WoodButton(
                  label: '游戏说明',
                  subtitle: '怎么玩 / 骰子 / 吐槽与拒绝',
                  icon: Icons.menu_book_outlined,
                  onTap: () => context.go('/how-to-play'),
                ),
                const SizedBox(height: 14),
                WoodButton(
                  label: '记忆回廊',
                  subtitle: '本机归档，只在这里读',
                  icon: Icons.hourglass_bottom,
                  onTap: () => context.go('/journal'),
                ),
                const SizedBox(height: 14),
                WoodButton(
                  label: '制卡',
                  subtitle: '属性 / 技能 / 随身物品',
                  icon: Icons.badge_outlined,
                  onTap: () => context.go('/sheet'),
                ),
                const SizedBox(height: 14),
                WoodButton(
                  label: '设置',
                  subtitle: 'API key / 模型 / 呈现方式',
                  icon: Icons.settings_outlined,
                  onTap: () => context.go('/settings'),
                ),
                const SizedBox(height: 30),
                const _Ornament(),
                const SizedBox(height: 12),
                const Text(
                  'v0.1.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 背景：深木底色 + 两团烛光。
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF33200F), AppColors.background],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -60,
            child: _Glow(color: Color(0x33C9A227), size: 260),
          ),
          Positioned(
            bottom: -120,
            right: -80,
            child: _Glow(color: Color(0x228C2F2F), size: 320),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

/// 装饰分隔线：— ◆ —
class _Ornament extends StatelessWidget {
  const _Ornament();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 54, height: 1, color: const Color(0x55C9A227)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.change_history, size: 8, color: AppColors.brass),
        ),
        Container(width: 54, height: 1, color: const Color(0x55C9A227)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.ok,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool ok;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.brass : const Color(0xFFB07A6A);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0x33000000),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
