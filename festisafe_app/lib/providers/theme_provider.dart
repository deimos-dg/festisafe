import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';
import '../core/theme/app_theme.dart';
import '../data/services/theme_service.dart';

class ThemeNotifier extends StateNotifier<ThemeState> {
  final ThemeService _service;

  ThemeNotifier(this._service) : super(const ThemeState()) {
    _load();
  }

  Future<void> _load() async {
    final saved = await _service.loadTheme();
    state = saved;
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _service.saveTheme(state);
  }

  Future<void> setPalette(int index) async {
    state = state.copyWith(paletteIndex: index.clamp(0, 5));
    await _service.saveTheme(state);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>(
  (ref) => ThemeNotifier(ThemeService()),
);
