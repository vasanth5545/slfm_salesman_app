import 'package:flutter/material.dart';
import 'theme_service.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode = ThemeService.themeMode;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await ThemeService.setThemeMode(mode);
    notifyListeners();
  }
}

// Global instance
final themeNotifier = ThemeNotifier();
