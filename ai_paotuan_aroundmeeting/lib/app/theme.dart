import 'package:flutter/material.dart';

/// 跑团质感配色（SE §4.x / PRD 05 §7）：深木桌、羊皮纸、黄铜、暗红。
abstract final class AppColors {
  static const background = Color(0xFF1A120B);
  static const surface = Color(0xFF2A1D12);
  static const surfaceHigh = Color(0xFF3A291A);
  static const parchment = Color(0xFFF0E2C4);
  static const parchmentInk = Color(0xFF2B2118);
  static const brass = Color(0xFFC9A227);
  static const blood = Color(0xFF8C2F2F);
  static const ink = Color(0xFFEADBC0);
  static const inkMuted = Color(0xFF9C8A72);
  static const success = Color(0xFF5F7A45);
}

/// 标题用系统衬线，正文用系统黑体（D-21 = A：不打包字体）。
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: AppColors.brass,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.brass,
          secondary: AppColors.blood,
          surface: AppColors.surface,
        ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppColors.ink,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x33C9A227),
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0x55C9A227)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0x55C9A227)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.brass, width: 1.4),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.ink),
    ),
  );
}

/// 标题样式：衬线 + 宽字距。
TextStyle titleSerif({double size = 28, Color color = AppColors.ink}) =>
    TextStyle(
      fontFamily: 'serif',
      fontSize: size,
      letterSpacing: 4,
      color: color,
      fontWeight: FontWeight.w600,
    );

/// 小节标题。
TextStyle sectionLabel({Color color = AppColors.brass}) => TextStyle(
  fontSize: 12,
  letterSpacing: 3,
  color: color,
  fontWeight: FontWeight.w600,
);
