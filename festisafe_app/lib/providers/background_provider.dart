import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../data/services/background_service.dart';

/// Estado del servicio de background.
class BackgroundState {
  final bool isActive;
  final String? activeEventId;

  const BackgroundState({this.isActive = false, this.activeEventId});
}

class BackgroundNotifier extends StateNotifier<BackgroundState> {
  BackgroundNotifier() : super(const BackgroundState()) {
    _syncState();
  }

  Future<void> _syncState() async {
    final running = await isBackgroundTrackingActive();
    if (running != state.isActive) {
      state = BackgroundState(isActive: running);
    }
  }

  Future<void> start({
    required String eventId,
    required String accessToken,
    required String wsBaseUrl,
    required String apiBaseUrl,
  }) async {
    await startBackgroundTracking(
      eventId: eventId,
      accessToken: accessToken,
      wsBaseUrl: wsBaseUrl,
      apiBaseUrl: apiBaseUrl,
    );
    state = BackgroundState(isActive: true, activeEventId: eventId);
  }

  Future<void> stop() async {
    await stopBackgroundTracking();
    state = const BackgroundState(isActive: false);
  }

  /// Actualiza el token JWT en el servicio cuando se renueva.
  void updateToken(String newToken) {
    if (!state.isActive) return;
    FlutterBackgroundService().invoke('updateToken', {'accessToken': newToken});
  }
}

final backgroundProvider =
    StateNotifierProvider<BackgroundNotifier, BackgroundState>(
  (ref) => BackgroundNotifier(),
);
