import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/ble_service.dart';

/// Estado del servicio BLE.
class BleState {
  final bool isActive;
  final Map<String, BleDevice> nearbyDevices;
  final bool isSupported;

  const BleState({
    this.isActive = false,
    this.nearbyDevices = const {},
    this.isSupported = true,
  });

  /// Dispositivos del grupo que están cerca (<15m estimados).
  List<BleDevice> get nearbyMembers =>
      nearbyDevices.values.where((d) => d.isNearby).toList();

  BleState copyWith({
    bool? isActive,
    Map<String, BleDevice>? nearbyDevices,
    bool? isSupported,
  }) =>
      BleState(
        isActive: isActive ?? this.isActive,
        nearbyDevices: nearbyDevices ?? this.nearbyDevices,
        isSupported: isSupported ?? this.isSupported,
      );
}

class BleNotifier extends StateNotifier<BleState> {
  final BleService _service;
  StreamSubscription? _nearbySub;
  StreamSubscription? _sosSub;

  // Callback para cuando se recibe un SOS por BLE
  void Function(Map<String, dynamic>)? onSosReceived;

  BleNotifier(this._service) : super(const BleState());

  Future<void> start({
    required String userId,
    required String groupId,
    required String eventId,
  }) async {
    await _service.start(userId: userId, groupId: groupId, eventId: eventId);

    _nearbySub = _service.nearbyStream.listen((devices) {
      if (mounted) state = state.copyWith(nearbyDevices: devices, isActive: true);
    });

    _sosSub = _service.sosStream.listen((sosData) {
      onSosReceived?.call(sosData);
    });

    state = state.copyWith(isActive: true);
  }

  Future<void> stop() async {
    await _service.stop();
    _nearbySub?.cancel();
    _sosSub?.cancel();
    state = const BleState(isActive: false);
  }

  @override
  void dispose() {
    _nearbySub?.cancel();
    _sosSub?.cancel();
    super.dispose();
  }
}

final bleProvider = StateNotifierProvider<BleNotifier, BleState>(
  (ref) => BleNotifier(BleService()),
);
