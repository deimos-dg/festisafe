/// Constantes globales de la app FestiSafe.
class AppConstants {
  AppConstants._();

  // ---------------------------------------------------------------------------
  // URLs del backend — configurables via --dart-define en build
  // ---------------------------------------------------------------------------
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/api/v1',
  );
  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/ws',
  );

  // ---------------------------------------------------------------------------
  // Timeouts HTTP
  // ---------------------------------------------------------------------------
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // ---------------------------------------------------------------------------
  // Grupos
  // ---------------------------------------------------------------------------
  static const int maxGroupMembers = 8;

  // ---------------------------------------------------------------------------
  // WebSocket / ubicación
  // ---------------------------------------------------------------------------
  /// Intervalo normal de envío de ubicación (segundos).
  static const int locationIntervalNormal = 10;

  /// Intervalo en modo batería baja (segundos).
  static const int locationIntervalLowBattery = 30;

  /// Intervalo de fallback HTTP cuando WS no está disponible (segundos).
  static const int locationFallbackInterval = 30;

  /// Tiempo máximo de backoff exponencial en reconexión WS (segundos).
  static const int wsReconnectMax = 60;

  /// Tiempo base de backoff exponencial (segundos).
  static const int wsReconnectBase = 2;

  // ---------------------------------------------------------------------------
  // Batería
  // ---------------------------------------------------------------------------
  /// Umbral para activar modo batería baja (%).
  static const int batteryLowThreshold = 20;

  /// Umbral para desactivar modo batería baja al cargar (%).
  static const int batteryRestoreThreshold = 25;

  /// Umbral crítico para sugerir SOS preventivo (%).
  static const int batteryCriticalThreshold = 10;

  // ---------------------------------------------------------------------------
  // Marcadores de ubicación
  // ---------------------------------------------------------------------------
  /// Minutos sin actualización para atenuar marcador.
  static const int markerDimMinutes = 5;

  /// Minutos sin actualización para mostrar "Sin señal".
  static const int markerNoSignalMinutes = 15;

  // ---------------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------------
  static const int chatMaxLength = 100;

  /// Duración del banner de reacción rápida (segundos).
  static const int reactionBannerSeconds = 3;

  // ---------------------------------------------------------------------------
  // Avatares
  // ---------------------------------------------------------------------------
  /// Cantidad de avatares predefinidos (iconos).
  static const int avatarCount = 12;

  /// Índice especial que indica "foto personalizada del usuario".
  static const int avatarCustomPhoto = 99;

  // ---------------------------------------------------------------------------
  // Códigos de cierre WebSocket
  // ---------------------------------------------------------------------------
  static const int wsCloseInvalidToken = 4001;
  static const int wsCloseAccessDenied = 4003;
}
