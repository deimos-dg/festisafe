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
    final ThemeMode themeMode;
    switch (themeState.mode) {
      case AppThemeMode.light:
        themeMode = ThemeMode.light;
      case AppThemeMode.dark:
        themeMode = ThemeMode.dark;
      case AppThemeMode.system:
        themeMode = ThemeMode.system;
      case AppThemeMode.custom:
        themeMode = ThemeMode.light;
    }

    return MaterialApp.router(
      title: 'FestiSafe',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      // theme se usa para light y como base en system/custom
      theme: AppTheme.buildTheme(themeState),
      // darkTheme se usa cuando el dispositivo está en modo oscuro (system) o dark
      darkTheme: AppTheme.buildDarkTheme(themeState),
      routerConfig: router,
    );
  }
}
