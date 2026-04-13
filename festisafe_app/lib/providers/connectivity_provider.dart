import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';

/// Estado de conectividad de red.
enum ConnectivityStatus { online, offline, unknown }

class ConnectivityNotifier extends StateNotifier<ConnectivityStatus> {
  Timer? _checkTimer;

  ConnectivityNotifier() : super(ConnectivityStatus.unknown) {
    _startMonitoring();
  }

  void _startMonitoring() {
    // Verificar inmediatamente
    _check();
    // Verificar cada 5 segundos
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  Future<void> _check() async {
    try {
      // Usar el host del backend configurado en AppConstants para evitar
      // hardcodear la URL y falsos negativos en redes que bloquean Google
      final host = Uri.parse(AppConstants.apiBaseUrl).host;
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      final isOnline = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      if (mounted) {
        state = isOnline
            ? ConnectivityStatus.online
            : ConnectivityStatus.offline;
      }
    } catch (_) {
      if (mounted) state = ConnectivityStatus.offline;
    }
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
