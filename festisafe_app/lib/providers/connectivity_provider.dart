import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';
import '../core/constants.dart';

/// Estado de conectividad de red.
enum ConnectivityStatus { online, offline, unknown }

class ConnectivityNotifier extends StateNotifier<ConnectivityStatus> {
  Timer? _checkTimer;
  ConnectivityStatus _previousStatus = ConnectivityStatus.unknown;

  ConnectivityNotifier() : super(ConnectivityStatus.unknown) {
    _startMonitoring();
  }

  void _startMonitoring() {
    _check();
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  Future<void> _check() async {
    try {
      final host = Uri.parse(AppConstants.apiBaseUrl).host;
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      final isOnline = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      if (!mounted) return;

      final newStatus =
          isOnline ? ConnectivityStatus.online : ConnectivityStatus.offline;

      // Detectar reconexión (offline → online) para notificar a otros providers
      if (_previousStatus == ConnectivityStatus.offline &&
          newStatus == ConnectivityStatus.online) {
        _onReconnected();
      }

      _previousStatus = newStatus;
      state = newStatus;
    } catch (_) {
      if (mounted) state = ConnectivityStatus.offline;
    }
  }

  /// Se llama automáticamente al detectar que la conexión se restauró.
  void _onReconnected() {
    // El mapa y el WS se reconectan solos via backoff exponencial.
    // Aquí notificamos a quien esté escuchando onReconnect.
    _reconnectCallbacks.forEach((cb) => cb());
  }

  final List<void Function()> _reconnectCallbacks = [];

  /// Registra un callback que se llama al restaurar la conexión.
  void addReconnectListener(void Function() callback) {
    _reconnectCallbacks.add(callback);
  }

  void removeReconnectListener(void Function() callback) {
    _reconnectCallbacks.remove(callback);
  }

  /// Forzar una verificación inmediata.
  Future<void> refresh() => _check();

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }
}

final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>(
  (ref) => ConnectivityNotifier(),
);

/// Shorthand — true si hay internet.
final isOnlineProvider = Provider<bool>(
  (ref) => ref.watch(connectivityProvider) == ConnectivityStatus.online,
);
