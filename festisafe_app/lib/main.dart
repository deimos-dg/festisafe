import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'app.dart';
import 'core/router/app_router.dart';
import 'providers/auth_provider.dart';
import 'data/services/notification_service.dart';

/// EventId pendiente de navegación desde notificación
String? _pendingNavigationEventId;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Firebase
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. Cache mapa offline
    await FMTCObjectBoxBackend().initialise();
    await const FMTCStore('mapCache').manage.create();

    // 3. Notificaciones locales
    await _initLocalNotifications();

    runApp(
      const ProviderScope(
        child: _AppInit(),
      ),
    );
  } catch (e, stack) {
    debugPrint('❌ ERROR EN MAIN: $e');
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text('Error: $e')))));
  }
}

Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings = InitializationSettings(android: androidSettings);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: _onNotificationTap,
  );
}

void _onNotificationTap(NotificationResponse response) {}

class _AppInit extends ConsumerStatefulWidget {
  const _AppInit();
  @override
  ConsumerState<_AppInit> createState() => _AppInitState();
}

class _AppInitState extends ConsumerState<_AppInit> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await ref.read(authProvider.notifier).checkSession();
        await NotificationService().init();
      } catch (e) {
        debugPrint('Error en Init: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) => const FestiSafeApp();
}
