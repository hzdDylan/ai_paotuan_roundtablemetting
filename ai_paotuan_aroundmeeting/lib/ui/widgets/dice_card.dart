import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../engine/rules/check.dart';
import 'parchment_panel.dart';

/// 骰子卡：技能 / 目标 / 骰值 / 结果 / 失败代价（PRD 05 §4.6）。
class DiceCard extends StatelessWidget {
  const DiceCard({super.key, required this.roll, this.onContinue});

  final Roll roll;
  final VoidCallback? onContinue;

  Color get _accent => switch (roll.outcome) {
    Outcome.critical => const Color(0xFFB8860B),
    Outcome.success => AppColors.success,
    Outcome.fail => const Color(0xFF7A5230),
    Outcome.fumble => AppColors.blood,
  };

  @override
  Widget build(BuildContext context) {
    return ParchmentPanel(
      label: '检定',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '【${roll.label}】',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '目标 ${roll.target}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B4E2E)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${roll.die}',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 42,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('/ 100', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _accent.withValues(alpha: 0.6)),
                ),
                child: Text(
                  roll.outcome.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '基础 ${roll.baseSkill} · ${roll.difficulty.label}难度'
            '${roll.stakes.isEmpty ? '' : ' · ${roll.stakes}'}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B4E2E)),
          ),
          if (onContinue != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onContinue,
                child: const Text('继续 ▼'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
