import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

/// Persiste y recupera el estado del tema usando [SharedPreferences].
class ThemeService {
  static const _modeKey = 'theme_mode';
  static const _paletteKey = 'theme_palette';

  Future<ThemeState> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_modeKey) ?? 0;
    final paletteIndex = prefs.getInt(_paletteKey) ?? 0;
    final mode = AppThemeMode.values[modeIndex.clamp(0, AppThemeMode.values.length - 1)];
    return ThemeState(mode: mode, paletteIndex: paletteIndex.clamp(0, 5));
  }

  Future<void> saveTheme(ThemeState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_modeKey, state.mode.index);
    await prefs.setInt(_paletteKey, state.paletteIndex);
  }
}
