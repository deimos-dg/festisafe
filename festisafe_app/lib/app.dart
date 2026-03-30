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

    return MaterialApp.router(
      title: 'FestiSafe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(themeState),
      routerConfig: router,
    );
  }
}
