import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/theme_provider.dart';

class FestiSafeApp extends ConsumerWidget {
  const FestiSafeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);

    // Determinar ThemeMode según la preferencia del usuario
    final themeMode = switch (themeState.mode) {
      AppThemeMode.light  => ThemeMode.light,
      AppThemeMode.dark   => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,  // sigue al dispositivo
      AppThemeMode.custom => ThemeMode.light,   // custom usa tema claro base
    };

    return MaterialApp.router(
      title: 'FestiSafe',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.buildTheme(themeState.copyWith(mode: AppThemeMode.light)),
      darkTheme: AppTheme.buildDarkTheme(themeState),
      routerConfig: router,
    );
  }
}
