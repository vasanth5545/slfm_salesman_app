import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ThemeService {
  static const String _boxName = 'themeBox';
  static const String _themeKey = 'themeMode';

  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  static ThemeMode get themeMode {
    final box = Hive.box(_boxName);
    final themeValue = box.get(_themeKey, defaultValue: 'dark'); // Default to Dark
    
    switch (themeValue) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final box = Hive.box(_boxName);
    String themeValue;
    
    switch (mode) {
      case ThemeMode.light:
        themeValue = 'light';
        break;
      case ThemeMode.dark:
        themeValue = 'dark';
        break;
      case ThemeMode.system:
        themeValue = 'system';
        break;
    }
    await box.put(_themeKey, themeValue);
  }
}
