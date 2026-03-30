import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Nombre del canal de notificación persistente del servicio.
const String kBgChannelId = 'festisafe_background';
const String kBgChannelName = 'FestiSafe activo';
const int kBgNotificationId = 888;

/// Inicializa y configura el servicio de background.
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  const channel = AndroidNotificationChannel(
    kBgChannelId,
    kBgChannelName,
    description: 'FestiSafe está compartiendo tu ubicación en segundo plano',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );
  final notif = FlutterLocalNotificationsPlugin();
  await notif
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onBackgroundStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: kBgChannelId,
      initialNotificationTitle: 'FestiSafe',
      initialNotificationContent: 'Compartiendo ubicación en segundo plano…',
      foregroundServiceNotificationId: kBgNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onBackgroundStart,
      onBackground: _onIosBackground,
    ),
  );
}

/// Arranca el servicio pasando el eventId y el token JWT.
Future<void> startBackgroundTracking({
  required String eventId,
  required String accessToken,
  required String wsBaseUrl,
  required String apiBaseUrl,
}) async {
  final service = FlutterBackgroundService();
  final running = await service.isRunning();
  if (!running) await service.startService();

  service.invoke('start', {
    'eventId': eventId,
    'accessToken': accessToken,
    'wsBaseUrl': wsBaseUrl,
    'apiBaseUrl': apiBaseUrl,
  });
}

/// Detiene el servicio de background.
Future<void> stopBackgroundTracking() async {
  FlutterBackgroundService().invoke('stop');
}

/// Retorna true si el servicio está corriendo.
Future<bool> isBackgroundTrackingActive() =>
    FlutterBackgroundService().isRunning();

// ---------------------------------------------------------------------------
// Entrypoints del isolate de background
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void _onBackgroundStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notif = FlutterLocalNotificationsPlugin();
  await notif.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  final tracker = _BgTracker(service: service, notif: notif);

  service.on('start').listen((data) {
    if (data == null) return;
    tracker.configure(
      eventId: data['eventId'] as String?,
      accessToken: data['accessToken'] as String?,
      wsBaseUrl: data['wsBaseUrl'] as String?,
      apiBaseUrl: data['apiBaseUrl'] as String?,
    );
  });

  service.on('stop').listen((_) => tracker.cleanup());

  service.on('updateToken').listen((data) {
    if (data == null) return;
    tracker.updateToken(data['accessToken'] as String?);
  });
}

// ---------------------------------------------------------------------------
// Clase que encapsula el estado y la lógica del tracker en background.
// Usar una clase evita los dead_code warnings por type promotion en closures.
// ---------------------------------------------------------------------------

/// Parámetros de backoff exponencial con jitter — idénticos al WsClient foreground.
const int _kReconnectBase = 2;   // segundos base
const int _kReconnectMax  = 60;  // techo máximo en segundos
const int _kJitterMax     = 3;   // jitter aleatorio máximo en segundos

class _BgTracker {
  final ServiceInstance service;
  final FlutterLocalNotificationsPlugin notif;
  final _rng = Random();

  String? eventId;
  String? accessToken;
  String? wsBaseUrl;
  String? apiBaseUrl;
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? wsSub;
  StreamSubscription<Position>? gpsSub;
  Timer? _reconnectTimer;
  bool wsConnected = false;
  int _reconnectAttempt = 0;   // contador de intentos consecutivos fallidos
  bool _destroyed = false;     // evita reconexiones tras cleanup()

  _BgTracker({required this.service, required this.notif});

  // -------------------------------------------------------------------------
  // API pública
  // -------------------------------------------------------------------------

  void configure({
    String? eventId,
    String? accessToken,
    String? wsBaseUrl,
    String? apiBaseUrl,
  }) {
    this.eventId = eventId;
    this.accessToken = accessToken;
    this.wsBaseUrl = wsBaseUrl;
    this.apiBaseUrl = apiBaseUrl;

    if (eventId == null || accessToken == null) return;

    _reconnectAttempt = 0;
    _updateNotification('Iniciando…');
    _connectWs();
    _startGps();
  }

  void updateToken(String? newToken) {
    accessToken = newToken;
    wsConnected = false;
    _reconnectAttempt = 0;
    _connectWs();
  }

  void cleanup() {
    _destroyed = true;
    gpsSub?.cancel();
    wsSub?.cancel();
    _reconnectTimer?.cancel();
    channel?.sink.close();
    service.stopSelf();
  }

  // -------------------------------------------------------------------------
  // WebSocket con backoff exponencial + jitter
  // -------------------------------------------------------------------------

  void _connectWs() {
    if (_destroyed) return;
    if (wsBaseUrl == null || eventId == null || accessToken == null) return;

    try {
      channel?.sink.close();
      wsSub?.cancel();
      _reconnectTimer?.cancel();

      final uri = Uri.parse('$wsBaseUrl/location/$eventId?token=$accessToken');
      channel = WebSocketChannel.connect(uri);

      wsSub = channel!.stream.listen(
        _onWsMessage,
        onError: (_) => _scheduleReconnect(reason: 'error'),
        onDone: ()  => _scheduleReconnect(reason: 'done'),
      );
    } catch (_) {
      _scheduleReconnect(reason: 'exception');
    }
  }

  void _scheduleReconnect({required String reason}) {
    if (_destroyed) return;
    wsConnected = false;

    _reconnectTimer?.cancel();

    // Backoff exponencial: min(base * 2^N, max) + jitter aleatorio
    final expDelay = min(
      _kReconnectBase * pow(2, _reconnectAttempt).toInt(),
      _kReconnectMax,
    );
    final jitter = _rng.nextInt(_kJitterMax + 1);
    final delay = expDelay + jitter;
    _reconnectAttempt++;

    _updateNotification('Sin señal · reconectando en ${delay}s…');

    _reconnectTimer = Timer(Duration(seconds: delay), _connectWs);
  }

  void _onWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final msgType = data['type'] as String?;
      if (msgType == 'ping') {
        channel?.sink.add(jsonEncode({'type': 'pong'}));
      } else if (msgType == 'connected') {
        // Reconexión exitosa — resetear contador
        wsConnected = true;
        _reconnectAttempt = 0;
        _reconnectTimer?.cancel();
        _updateNotification('Conectado al evento · compartiendo ubicación');
      }
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Notificación persistente
  // -------------------------------------------------------------------------

  void _updateNotification(String content) {
    notif.show(
      kBgNotificationId,
      'FestiSafe activo',
      content,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kBgChannelId,
          kBgChannelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          icon: '@drawable/ic_notification',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Fallback HTTP cuando WS no está disponible
  // -------------------------------------------------------------------------

  Future<void> _sendLocationHttp(Position pos) async {
    final base = apiBaseUrl;
    final ev = eventId;
    final tok = accessToken;
    if (base == null || ev == null || tok == null) return;
    try {
      final dio = Dio(BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Authorization': 'Bearer $tok'},
      ));
      await dio.post('/gps/location/$ev', data: {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
      });
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // GPS
  // -------------------------------------------------------------------------

  void _startGps() {
    gpsSub?.cancel();

    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 3,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: const Duration(seconds: 10),
        distanceFilter: 3,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'FestiSafe está compartiendo tu ubicación',
          notificationTitle: 'FestiSafe activo',
          enableWakeLock: true,
        ),
      );
    }

    gpsSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_onGpsPosition);
  }

  void _onGpsPosition(Position pos) {
    if (wsConnected) {
      channel?.sink.add(jsonEncode({
        'type': 'location',
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
      }));
    } else {
      // Fallback HTTP mientras el WS reconecta
      _sendLocationHttp(pos);
    }
  }
}
