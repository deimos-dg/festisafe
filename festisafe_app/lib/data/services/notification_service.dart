import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show Color;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_client.dart';
import '../../main.dart';

const String kSosChannelId = 'festisafe_sos';
const String kSosChannelName = 'Alertas SOS';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _messaging = FirebaseMessaging.instance;

  // ================= INIT =================
  Future<void> init() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpenedApp);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleMessage(initial);
  }

  Future<String?> getDeviceToken() => _messaging.getToken();

  Stream<String> get tokenRefreshStream => _messaging.onTokenRefresh;

  Future<void> registerTokenInBackend() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      final platform =
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

      await ApiClient().dio.post('/users/me/fcm-token', data: {
        'token': token,
        'platform': platform,
      });

      _messaging.onTokenRefresh.listen((newToken) {
        ApiClient().dio.post('/users/me/fcm-token', data: {
          'token': newToken,
          'platform': platform,
        }).catchError((_) {});
      });
    } catch (_) {}
  }

  Future<void> unregisterTokenFromBackend() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      await ApiClient().dio.delete(
        '/users/me/fcm-token',
        data: {'token': token, 'platform': 'android'},
      );
    } catch (_) {}
  }

  // ================= NOTIFICACIONES =================

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
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
          color: const Color(0xFFD32F2F),
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode({'type': 'sos', 'eventId': eventId}),
    );
  }

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
        ),
      ),
      payload: jsonEncode({'type': 'chat', 'eventId': eventId}),
    );
  }

  // ================= FCM =================

  void _onForegroundMessage(RemoteMessage message) {
    _handleMessage(message);
  }

  void _onNotificationOpenedApp(RemoteMessage message) {
    _handleMessage(message);
  }

  void _handleMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'];

    if (type == 'sos') {
      showSosAlert(
        userName: data['user_name'] ?? 'Un compañero',
        eventId: data['event_id'] ?? '',
        groupId: data['group_id'],
      );
    }
  }

  int _sosId(String userName) => userName.hashCode.abs() % 10000;
}

// 🔥 ESTE ES CLAVE (te faltaba bien definido)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final type = message.data['type'];

  if (type == 'sos') {
    await NotificationService().showSosAlert(
      userName: message.data['user_name'] ?? 'Un compañero',
      eventId: message.data['event_id'] ?? '',
    );
  }
}