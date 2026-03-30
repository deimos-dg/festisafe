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
import 'data/services/background_service.dart';

/// EventId pendiente de navegación desde notificación — se consume en _AppInitState.
String? _pendingNavigationEventId;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializar Firebase primero para FCM
  await Firebase.initializeApp();
  
  // 2. Handler para mensajes cuando la app está CERRADA o en BACKGROUND
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 3. Inicializar caché de tiles del mapa (Offline)
  await FMTCObjectBoxBackend().initialise();
  await const FMTCStore('mapCache').manage.create();

  // 4. Configurar Notificaciones Locales
  await _initLocalNotifications();

  // 5. Iniciar servicio de ubicación en segundo plano
  await initBackgroundService();

  runApp(
    const ProviderScope(
      child: _AppInit(),
    ),
  );
}

Future<void> _initLocalNotifications() async {
  // NOTA: Usamos el icono de la app por defecto para evitar errores si no existe ic_notification
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher'); 
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
    onDidReceiveNotificationResponse: _onNotificationTap,
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  // Crear Canales en Android (Usa constantes definidas en NotificationService)
  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    kSosChannelId,
    kSosChannelName,
    description: 'Notificaciones de emergencia del grupo',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  ));

  await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
    'festisafe_chat',
    'Mensajes del grupo',
    description: 'Mensajes recibidos mientras la app está en segundo plano',
    importance: Importance.defaultImportance,
    playSound: false,
  ));
}

void _onNotificationTap(NotificationResponse response) {
  if (response.payload == null) return;
  try {
    final data = jsonDecode(response.payload!) as Map<String, dynamic>;
    if (data['type'] == 'sos' && data['eventId'] != null) {
      _pendingNavigationEventId = data['eventId'];
    }
  } catch (_) {}
}

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
      // Verificar sesión
      await ref.read(authProvider.notifier).checkSession();
      
      // Inicializar listeners de FCM (foreground/opened)
      await NotificationService().init();

      final auth = ref.read(authProvider);
      if (auth is AuthAuthenticated || auth is AuthGuest) {
        await NotificationService().registerTokenInBackend();
      }

      // Navegar al mapa si la app fue abierta desde una notificación SOS
      if (_pendingNavigationEventId != null && mounted) {
        final eventId = _pendingNavigationEventId!;
        _pendingNavigationEventId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(routerProvider).push('/map/$eventId');
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => const FestiSafeApp();
}
