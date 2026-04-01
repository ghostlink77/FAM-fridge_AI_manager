import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFFF9800);
  static const Color primaryLight = Color(0xFFFFCC80);
  static const Color primaryDark = Color(0xFF5D4037);
  static const Color primaryPale = Color(0xFFFFF3E0);

  static const Color background = Color(0xFFFAF6F0);
  static const Color surface = Color(0xFFFAF6F0);
  static const Color surfaceDark = Color(0xFFE8DFD0);

  static const Color fresh = Color(0xFF66BB6A);   // 여유 (D-4+)
  static const Color warning = Color(0xFFF57C00);   // 임박 (D-1~3)
  static const Color danger = Color(0xFFE53935);   // 만료

  static const Color freshBg = Color(0xFFE8F5E9);   // 여유 배경
  static const Color warningBg = Color(0xFFFFF3E0);   // 임박 배경
  static const Color dangerBg = Color(0xFFFFEBEE);   // 만료 배경

  static const Color accent = Color(0xFF4CAF50);
  static const Color brown = Color(0xFF5D4037);
  static const Color warmBrown = Color(0xFF8D6E63);
  static const Color cream = Color(0xFFFFF8E1);

  static const Color textPrimary   = Color(0xFF2E2E2E);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textOnPrimary = Colors.white;
}