import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

enum AppAccentColor { gold, amber, sage, rose, sky }

class AppSettings extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  static const _accentKey = 'accent_color';

  AppThemeMode _themeMode = AppThemeMode.dark;
  AppAccentColor _accentColor = AppAccentColor.gold;
  bool _loaded = false;

  AppThemeMode get themeMode => _themeMode;
  AppAccentColor get accentColor => _accentColor;
  bool get isLoaded => _loaded;

  ThemeMode get materialThemeMode => switch (_themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeKey);
    // Prefer dark (golden-on-charcoal) as the product default.
    if (raw == null || raw == AppThemeMode.system.name) {
      _themeMode = AppThemeMode.dark;
      await prefs.setString(_themeKey, AppThemeMode.dark.name);
    } else {
      _themeMode = AppThemeMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => AppThemeMode.dark,
      );
    }
    final accentRaw = prefs.getString(_accentKey);
    if (accentRaw != null) {
      _accentColor = AppAccentColor.values.firstWhere(
        (c) => c.name == accentRaw,
        orElse: () => AppAccentColor.gold,
      );
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAccentColor(AppAccentColor color) async {
    _accentColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentKey, color.name);
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }
}
