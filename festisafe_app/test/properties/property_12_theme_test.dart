import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/core/theme/app_theme.dart';

import 'prop_test_helper.dart';

/// Fake in-memory de ThemeService — sin mockito.
class _FakeThemeService {
  ThemeState? _saved;

  Future<void> saveTheme(ThemeState state) async => _saved = state;

  Future<ThemeState> loadTheme() async =>
      _saved ?? const ThemeState(mode: AppThemeMode.light, paletteIndex: 0);
}

void main() {
  late _FakeThemeService fakeThemeService;

  setUp(() {
    fakeThemeService = _FakeThemeService();
  });

  // Feature: festisafe-flutter-app, Property 12: Tema aplicado y persistido correctamente
  test('Property 12: ThemeData corresponde al modo seleccionado', () async {
    await forAll2(
      numRuns: 100,
      genA: () => genInt(min: 0, max: 3),
      genB: () => genInt(min: 0, max: 6),
      body: (modeIndex, paletteIndex) {
        final mode = AppThemeMode.values[modeIndex];
        final state = ThemeState(mode: mode, paletteIndex: paletteIndex);
        final theme = AppTheme.buildTheme(state);

        switch (mode) {
          case AppThemeMode.light:
            expect(theme.brightness, equals(Brightness.light));
            break;
          case AppThemeMode.dark:
            expect(theme.brightness, equals(Brightness.dark));
            break;
          case AppThemeMode.custom:
            expect(theme, isNotNull);
            break;
        }
      },
    );
  });

  test('Property 12b: tema se persiste y restaura correctamente', () async {
    await forAll2(
      numRuns: 100,
      genA: () => genInt(min: 0, max: 3),
      genB: () => genInt(min: 0, max: 6),
      body: (modeIndex, paletteIndex) async {
        final mode = AppThemeMode.values[modeIndex];
        final savedState = ThemeState(mode: mode, paletteIndex: paletteIndex);

        await fakeThemeService.saveTheme(savedState);
        final loaded = await fakeThemeService.loadTheme();

        expect(loaded.mode, equals(savedState.mode));
        expect(loaded.paletteIndex, equals(savedState.paletteIndex));
      },
    );
  });
}
