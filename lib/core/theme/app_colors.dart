import 'package:flutter/material.dart';

class AppColors {
  final bool isDark;
  AppColors(this.isDark);

  static AppColors of(BuildContext context) {
    return AppColors(Theme.of(context).brightness == Brightness.dark);
  }

  Color get bg => isDark ? const Color(0xFF060818) : const Color(0xFFF8F9FF);
  Color get surface => isDark ? const Color(0xFF0D1025) : Colors.white;
  Color get primary => const Color(0xFFA67C52);
  Color get gold => const Color(0xFFFFD700);
  Color get goldDark => const Color(0xFFD4AF37);
  Color get silver => const Color(0xFFC0C0C0);
  Color get bronze => const Color(0xFFCD7F32);
  Color get neonBlue => isDark ? const Color(0xFF0091FF) : const Color(0xFF0066FF);
  Color get neonPurple =>
      isDark ? const Color(0xFFAA00FF) : const Color(0xFF7700FF);
  Color get textPrimary => isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1A1C1E);
  Color get textSecondary =>
      isDark ? const Color(0xFF8A8A9A) : const Color(0xFF44474E);
  Color get divider => isDark ? const Color(0xFF2A2A3A) : const Color(0xFFD1D5DB);
  Color get success => const Color(0xFF4CAF50);
  Color get cardBg => isDark ? const Color(0xFF0F1228) : Colors.white;
}
