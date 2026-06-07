import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants.dart';
import '../data/models/member_location.dart';
import '../data/services/location_service.dart';
import '../data/services/offline_cache_service.dart';
import 'battery_provider.dart';

/// Estado de la ubicación propia del usuario.
class LocationState {
  final Position? currentPosition;
  final bool isTracking;
  final bool isVisible;

  const LocationState({
    this.currentPosition,
    this.isTracking = false,
    this.isVisible = true,
  });

  LocationState copyWith({Position? currentPosition, bool? isTracking, bool? isVisible}) {
    return LocationState(
      currentPosition: currentPosition ?? this.currentPosition,
      isTracking: isTracking ?? this.isTracking,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  final LocationService _service;
  final Ref _ref;
  StreamSubscription<Position>? _trackingSub;

  LocationNotifier(this._service, this._ref) : super(const LocationState());

  Future<bool> requestPermission() => _service.requestPermission();

  /// Inicia el tracking GPS con frecuencia adaptativa según batería.
  Future<void> startTracking() async {
    // Guard: si ya hay un stream activo, no duplicar
    if (_trackingSub != null) return;

    final battery = _ref.read(batteryProvider).value ?? 100;
    final interval = battery < AppConstants.batteryLowThreshold
        ? AppConstants.locationIntervalLowBattery
        : AppConstants.locationIntervalNormal;

    _trackingSub = _service.startTracking(intervalSeconds: interval).listen((pos) {
      if (mounted) state = state.copyWith(currentPosition: pos, isTracking: true);
    });
    if (mounted) state = state.copyWith(isTracking: true);
  }

  void stopTracking() {
    _trackingSub?.cancel();
    _trackingSub = null;
    if (mounted) state = state.copyWith(isTracking: false);
  }

  void setVisibility(bool visible) {
    if (mounted) state = state.copyWith(isVisible: visible);
  }

  @override
  void dispose() {
    _trackingSub?.cancel();
    super.dispose();
  }
}

final locationProvider = StateNotifierProvider<LocationNotifier, LocationState>(
  (ref) => LocationNotifier(LocationService(), ref),
);

/// Mapa de ubicaciones de los miembros del grupo (userId → MemberLocation).
/// Persiste automáticamente en caché para modo offline.
class MemberLocationsNotifier extends StateNotifier<Map<String, MemberLocation>> {
  final _cache = OfflineCacheService();

  MemberLocationsNotifier() : super({}) {
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.loadLocations();
    if (cached.isNotEmpty && mounted) {
      state = cached;
    }
  }

  void updateLocation(MemberLocation loc) {
    state = {...state, loc.userId: loc};
    // Persistir en background sin bloquear la UI
    _cache.saveLocations(state);
  }

  void removeLocation(String userId) {
    final updated = Map<String, MemberLocation>.from(state);
    updated.remove(userId);
    state = updated;
    _cache.saveLocations(state);
  }

  /// Limpia el caché expirado y recarga. Llamar al reconectar la app.
  Future<void> invalidateIfStale() async {
    final lastSync = await _cache.lastSyncTime();
    if (lastSync == null) return;
    final age = DateTime.now().difference(lastSync);
    if (age > const Duration(hours: 1)) {
      // Caché de más de 1h — limpiar para mostrar datos frescos al reconectar
      await _cache.clearAll();
      if (mounted) state = {};
    }
  }

  void clear() {
    state = {};
    _cache.saveLocations({});
  }
}

final memberLocationsProvider =
    StateNotifierProvider<MemberLocationsNotifier, Map<String, MemberLocation>>(
  (ref) => MemberLocationsNotifier(),
);
