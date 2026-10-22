import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 羊皮纸面板：对话框、骰子卡、详情页共用。
class ParchmentPanel extends StatelessWidget {
  const ParchmentPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.label,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final content = DefaultTextStyle.merge(
      style: const TextStyle(
        color: AppColors.parchmentInk,
        fontSize: 16,
        height: 1.6,
      ),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x99C9A227)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B4E2E),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0x336B4E2E)),
              const SizedBox(height: 8),
            ],
            content,
          ],
        ),
      ),
    );
  }
}
