import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show Color;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_client.dart';
import '../../main.dart';

/// Canal de alta prioridad para alertas SOS.
const String kSosChannelId = 'festisafe_sos';
const String kSosChannelName = 'Alertas SOS';

/// Servicio centralizado de notificaciones (locales + push FCM).
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _messaging = FirebaseMessaging.instance;

  // -------------------------------------------------------------------------
  // Inicialización
  // -------------------------------------------------------------------------

  Future<void> init() async {
    // Solicitar permiso de notificaciones (iOS + Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true, // para SOS
    );

    // Manejar mensajes FCM en foreground
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Manejar tap en notificación cuando la app estaba en background
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpenedApp);

    // Manejar mensaje que abrió la app desde terminada
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleMessage(initial);
  }

  /// Retorna el FCM token del dispositivo para registrarlo en el backend.
  Future<String?> getDeviceToken() => _messaging.getToken();

  /// Stream de renovación de token FCM.
  Stream<String> get tokenRefreshStream => _messaging.onTokenRefresh;

  /// Registra el token FCM en el backend. Llamar tras login exitoso.
  Future<void> registerTokenInBackend() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      await ApiClient().dio.post('/users/me/fcm-token', data: {
        'token': token,
        'platform': platform,
      });
      // Escuchar renovaciones automáticas del token
      _messaging.onTokenRefresh.listen((newToken) {
        ApiClient().dio.post('/users/me/fcm-token', data: {
          'token': newToken,
          'platform': platform,
        }).catchError((_) => Response(requestOptions: RequestOptions()));
      });
    } catch (_) {
      // No crítico — se reintentará en el próximo inicio
    }
  }

  /// Elimina el token FCM del backend al hacer logout.
  Future<void> unregisterTokenFromBackend() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await ApiClient().dio.delete('/users/me/fcm-token', data: {'token': token, 'platform': 'android'});
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Notificaciones locales (SOS, chat, sistema)
  // -------------------------------------------------------------------------

  /// Muestra una notificación de alerta SOS.
  Future<void> showSosAlert({
    required String userName,
    required String eventId,
    String? groupId,
  }) async {
    await flutterLocalNotificationsPlugin.show(
      _sosId(userName),
      '🆘 Alerta SOS',
      '$userName necesita ayuda',
      NotificationDetails(
        android: AndroidNotificationDetails(
          kSosChannelId,
          kSosChannelName,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true, // muestra aunque el teléfono esté bloqueado
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
          color: const Color(0xFFD32F2F),
          icon: '@drawable/ic_notification',
          ticker: 'SOS de $userName',
        ),
      ),
      payload: jsonEncode({'type': 'sos', 'eventId': eventId}),
    );
  }

  /// Muestra una notificación de SOS cancelado.
  Future<void> showSosCancelled(String userName) async {
    await flutterLocalNotificationsPlugin.show(
      _sosId(userName),
      '✅ SOS cancelado',
      '$userName ya está bien',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kSosChannelId,
          kSosChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
        ),
      ),
    );
  }

  /// Muestra una notificación de mensaje de chat (solo en background).
  Future<void> showChatMessage({
    required String senderName,
    required String text,
    required String eventId,
  }) async {
    await flutterLocalNotificationsPlugin.show(
      42,
      senderName,
      text,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'festisafe_chat',
          'Mensajes del grupo',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          groupKey: 'festisafe_chat_$eventId',
          setAsGroupSummary: false,
        ),
      ),
      payload: jsonEncode({'type': 'chat', 'eventId': eventId}),
    );
  }

  // -------------------------------------------------------------------------
  // Handlers FCM
  // -------------------------------------------------------------------------

  void _onForegroundMessage(RemoteMessage message) {
    // En foreground mostramos notificación local porque FCM no la muestra sola
    _handleMessage(message);
  }

  void _onNotificationOpenedApp(RemoteMessage message) {
    _handleMessage(message);
  }

  void _handleMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;

    if (type == 'sos') {
      showSosAlert(
        userName: data['user_name'] ?? 'Un compañero',
        eventId: data['event_id'] ?? '',
        groupId: data['group_id'],
      );
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// ID único por usuario para poder actualizar/cancelar la notificación.
  int _sosId(String userName) => userName.hashCode.abs() % 10000;
}

// Necesario para recibir FCM en background/terminado — debe ser top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final type = message.data['type'] as String?;
  if (type == 'sos') {
    await NotificationService().showSosAlert(
      userName: message.data['user_name'] ?? 'Un compañero',
      eventId: message.data['event_id'] ?? '',
    );
  }
}
