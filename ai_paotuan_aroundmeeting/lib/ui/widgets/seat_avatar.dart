import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 座位头像（通用头像，V-8：不做自定义上传）。
class SeatAvatar extends StatelessWidget {
  const SeatAvatar({
    super.key,
    required this.name,
    this.role,
    this.initial,
    this.colorSeed = 0,
    this.highlighted = false,
    this.muted = false,
    this.size = 54,
  });

  final String name;
  final String? role;
  final String? initial;
  final int colorSeed;
  final bool highlighted;
  final bool muted;
  final double size;

  Color get _color {
    final hue = (colorSeed.abs() % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.38, muted ? 0.28 : 0.45).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final letter = (initial ?? (name.isEmpty ? '?' : name.characters.first))
        .toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _color,
            border: Border.all(
              color: highlighted ? AppColors.brass : const Color(0x55C9A227),
              width: highlighted ? 2.4 : 1,
            ),
            boxShadow: highlighted
                ? const [
                    BoxShadow(
                      color: Color(0x88C9A227),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: size * 0.42,
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name.trim().isEmpty ? '无名' : name,
          style: TextStyle(
            fontSize: 12,
            color: muted ? AppColors.inkMuted : AppColors.ink,
          ),
        ),
        if (role != null)
          Text(
            role!,
            style: const TextStyle(fontSize: 10, color: AppColors.brass),
          ),
      ],
    );
  }
}
