import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 属性 / 技能条：左标签、中间进度、右侧加减与数值。
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.ratioMin,
    this.ratioMax,
    this.onChanged,
    this.step = 5,
    this.readOnly = false,
    this.hint,
  });

  final String label;
  final int value;
  final int min;

  /// 可编辑的上限（超过它 + 号置灰）。
  final int max;

  /// 进度条画到哪：默认从 [min] 起、到 [ratioMax] 止。
  /// 技能要从 0 画起（20 的侦查也应显示一截），但减号最低只到基础值。
  final int? ratioMin;

  /// 进度条的量程上限；不填则等同 [max]。
  ///
  /// 为什么要分开：余额为 0 时 `max` 会等于当前值，若拿它算比例，
  /// 每一条都会显示成满的（这就是之前「进度条全满」的原因）。
  final int? ratioMax;
  final ValueChanged<int>? onChanged;
  final int step;
  final bool readOnly;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final low = ratioMin ?? min;
    final high = ratioMax ?? max;
    final ratio = high <= low
        ? 0.0
        : ((value - low) / (high - low)).clamp(0, 1);
    final canEdit = !readOnly && onChanged != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
            ),
          ),
          _StepButton(
            icon: Icons.remove,
            enabled: canEdit && value > min,
            onTap: () => onChanged!(value - step),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio.toDouble(),
                    minHeight: 7,
                    backgroundColor: const Color(0x33FFFFFF),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.brass,
                    ),
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    hint!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 26,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _StepButton(
            icon: Icons.add,
            enabled: canEdit && value < max,
            onTap: () => onChanged!(value + step),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: enabled
                  ? const Color(0x66C9A227)
                  : const Color(0x22FFFFFF),
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? AppColors.ink : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}
