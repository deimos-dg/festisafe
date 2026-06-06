import 'package:flutter/material.dart';
import 'color_palettes.dart';

/// Modos de tema disponibles.
enum AppThemeMode { light, dark, system, custom }

/// Estado del tema activo.
class ThemeState {
  final AppThemeMode mode;

  /// Índice de paleta activa (0-5), solo relevante en modo [AppThemeMode.custom].
  final int paletteIndex;

  const ThemeState({
    this.mode = AppThemeMode.system,  // por defecto sigue al sistema
    this.paletteIndex = 0,
  });

  ThemeState copyWith({AppThemeMode? mode, int? paletteIndex}) {
    return ThemeState(
      mode: mode ?? this.mode,
      paletteIndex: paletteIndex ?? this.paletteIndex,
    );
  }
}

/// Construye el [ThemeData] correspondiente al [ThemeState] dado.
class AppTheme {
  AppTheme._();

  static ThemeData buildTheme(ThemeState state) {
    switch (state.mode) {
      case AppThemeMode.light:
        return _lightTheme();
      case AppThemeMode.dark:
        return _darkTheme();
      case AppThemeMode.system:
        // En modo system, MaterialApp usa ThemeMode.system que alterna
        // automáticamente entre theme y darkTheme según el dispositivo.
        // buildTheme() se usa solo como tema base (light) en ese caso.
        return _lightTheme();
      case AppThemeMode.custom:
        final palette = kPalettes[state.paletteIndex.clamp(0, kPalettes.length - 1)];
        return _customTheme(palette);
    }
  }

  static ThemeData buildDarkTheme(ThemeState state) {
    if (state.mode == AppThemeMode.custom) {
      final palette = kPalettes[state.paletteIndex.clamp(0, kPalettes.length - 1)];
      // Modo custom dark: usar la paleta como base con brightness oscura
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.primary,
          secondary: palette.secondary,
          tertiary: palette.accent,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true),
      );
    }
    return _darkTheme();
  }

  static ThemeData _lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: const Color(0xFF0D1B4B),
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }

  static ThemeData _darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF0D1B4B),
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }

  static ThemeData _customTheme(ColorPalette palette) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        secondary: palette.secondary,
        tertiary: palette.accent,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }
}
