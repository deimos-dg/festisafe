import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/offline_cache_service.dart';

// ---------------------------------------------------------------------------
// UUIDs del servicio BLE de FestiSafe
// Deben ser únicos para no colisionar con otros servicios BLE.
// ---------------------------------------------------------------------------

/// UUID del servicio principal FestiSafe BLE.
const String kFestiSafeServiceUuid = 'f3e5a1b0-1234-5678-abcd-festisafe0001';

/// Característica de presencia — anuncia userId + groupId.
const String kPresenceCharUuid    = 'f3e5a1b0-1234-5678-abcd-festisafe0002';

/// Característica de SOS — payload de alerta SOS para relay.
const String kSosRelayCharUuid    = 'f3e5a1b0-1234-5678-abcd-festisafe0003';

// ---------------------------------------------------------------------------
// Modelo de dispositivo BLE detectado
// ---------------------------------------------------------------------------

class BleDevice {
  final String userId;
  final String groupId;
  final int rssi;           // señal en dBm — más cercano a 0 = más cerca
  final DateTime lastSeen;

  const BleDevice({
    required this.userId,
    required this.groupId,
    required this.rssi,
    required this.lastSeen,
  });

  /// Distancia estimada en metros basada en RSSI.
  /// Fórmula: d = 10^((TxPower - RSSI) / (10 * n))
  /// TxPower típico BLE: -59 dBm a 1m, n=2 (espacio libre)
  double get estimatedMeters {
    const txPower = -59;
    const n = 2.5; // factor de atenuación (entorno con personas)
    return pow(10, (txPower - rssi) / (10 * n)).toDouble();
  }

  bool get isNearby => estimatedMeters <= 15.0;

  BleDevice copyWith({int? rssi, DateTime? lastSeen}) => BleDevice(
        userId: userId,
        groupId: groupId,
        rssi: rssi ?? this.rssi,
        lastSeen: lastSeen ?? this.lastSeen,
      );
}

// ---------------------------------------------------------------------------
// Servicio BLE
// ---------------------------------------------------------------------------

class BleService {
  static final BleService _instance = BleService._();
  factory BleService() => _instance;
  BleService._();

  StreamSubscription? _scanSub;
  Timer? _scanTimer;
  Timer? _advertiseTimer;

  String? _myUserId;
  String? _myGroupId;
  String? _myEventId;

  bool _isRunning = false;

  // Mapa de dispositivos detectados: userId → BleDevice
  final Map<String, BleDevice> _nearbyDevices = {};
  final _nearbyController = StreamController<Map<String, BleDevice>>.broadcast();

  // Stream de SOS recibidos por BLE
  final _sosController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, BleDevice>> get nearbyStream => _nearbyController.stream;
  Stream<Map<String, dynamic>> get sosStream => _sosController.stream;
  Map<String, BleDevice> get nearbyDevices => Map.unmodifiable(_nearbyDevices);

  // ---------------------------------------------------------------------------
  // Iniciar / detener
  // ---------------------------------------------------------------------------

  Future<void> start({
    required String userId,
    required String groupId,
    required String eventId,
  }) async {
    if (_isRunning) return;
    _myUserId = userId;
    _myGroupId = groupId;
    _myEventId = eventId;
    _isRunning = true;

    // Verificar que BLE está disponible
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      // BLE no disponible — no lanzar error, simplemente no iniciar
      _isRunning = false;
      return;
    }

    _startScanning();
    _startAdvertising();

    // Limpiar dispositivos que no se han visto en 30s
    _scanTimer = Timer.periodic(const Duration(seconds: 30), (_) => _cleanStale());
  }

  Future<void> stop() async {
    _isRunning = false;
    _scanSub?.cancel();
    _scanTimer?.cancel();
    _advertiseTimer?.cancel();
    await _stopAdvertising();
    await FlutterBluePlus.stopScan();
    _nearbyDevices.clear();
    _nearbyController.add({});
  }

  void dispose() {
    stop();
    _nearbyController.close();
    _sosController.close();
  }

  // ---------------------------------------------------------------------------
  // Escaneo (A — detección de proximidad)
  // ---------------------------------------------------------------------------

  void _startScanning() {
    // Escanear continuamente con filtro por nombre de servicio
    FlutterBluePlus.startScan(
      withServices: [Guid(kFestiSafeServiceUuid)],
      continuousUpdates: true,
      removeIfGone: const Duration(seconds: 15),
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        _processScanResult(result);
      }
    });
  }

  void _processScanResult(ScanResult result) {
    // Leer el manufacturer data o service data para extraer userId + groupId
    final serviceData = result.advertisementData.serviceData;
    final rawData = serviceData[Guid(kFestiSafeServiceUuid)];
    if (rawData == null || rawData.isEmpty) return;

    try {
      final payload = _decodePayload(rawData);
      final userId = payload['u'] as String?;
      final groupId = payload['g'] as String?;
      final type = payload['t'] as String?;

      if (userId == null || groupId == null) return;

      // Solo procesar dispositivos del mismo grupo
      if (groupId != _myGroupId) return;

      if (type == 'sos') {
        // D — SOS recibido por BLE
        _handleBlesSos(payload, userId);
        return;
      }

      // A — actualizar presencia
      final existing = _nearbyDevices[userId];
      _nearbyDevices[userId] = BleDevice(
        userId: userId,
        groupId: groupId,
        rssi: result.rssi,
        lastSeen: DateTime.now(),
      );

      // Solo notificar si cambió algo relevante
      if (existing?.rssi != result.rssi || existing == null) {
        _nearbyController.add(Map.unmodifiable(_nearbyDevices));
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Advertising (A — anunciar presencia via plugin nativo Android)
  // ---------------------------------------------------------------------------

  static const _advertiserChannel = MethodChannel('com.festisafe/ble_advertiser');

  void _startAdvertising() {
    _advertise();
    _advertiseTimer = Timer.periodic(const Duration(seconds: 30), (_) => _advertise());
  }

  Future<void> _advertise() async {
    if (_myUserId == null || _myGroupId == null) return;
    try {
      final supported = await _advertiserChannel.invokeMethod<bool>('isSupported') ?? false;
      if (!supported) return;
      final payload = buildPresencePayload();
      await _advertiserChannel.invokeMethod('startAdvertising', {'payload': Uint8List.fromList(payload)});
    } catch (_) {
      // BLE advertising no disponible en este dispositivo — continuar sin él
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await _advertiserChannel.invokeMethod('stopAdvertising');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // D — SOS por BLE (relay)
  // ---------------------------------------------------------------------------

  void _handleBlesSos(Map<String, dynamic> payload, String senderUserId) {
    final eventId = payload['e'] as String? ?? _myEventId;
    if (eventId == null) return;

    // Notificar a la UI
    _sosController.add({
      'userId': senderUserId,
      'eventId': eventId,
      'latitude': payload['lat'],
      'longitude': payload['lng'],
      'batteryLevel': payload['b'] ?? 100,
      'source': 'ble',
    });

    // Intentar relay al servidor si hay internet
    _relaySosToServer(
      eventId: eventId,
      userId: senderUserId,
      payload: payload,
    );
  }

  Future<void> _relaySosToServer({
    required String eventId,
    required String userId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      // Guardar en caché offline por si no hay internet ahora
      await OfflineCacheService().savePendingSos(
        eventId: eventId,
        latitude: (payload['lat'] as num?)?.toDouble() ?? 0,
        longitude: (payload['lng'] as num?)?.toDouble() ?? 0,
        accuracy: (payload['acc'] as num?)?.toDouble() ?? 0,
        batteryLevel: payload['b'] as int? ?? 100,
      );
    } catch (_) {}
  }

  /// Construye el payload BLE de presencia para advertising.
  /// Formato compacto: {'u': userId, 'g': groupId, 't': 'presence'}
  List<int> buildPresencePayload() {
    if (_myUserId == null || _myGroupId == null) return [];
    return _encodePayload({'u': _myUserId!, 'g': _myGroupId!, 't': 'p'});
  }

  /// Construye el payload BLE de SOS para advertising.
  List<int> buildSosPayload({
    required double lat,
    required double lng,
    required int batteryLevel,
  }) {
    return _encodePayload({
      'u': _myUserId ?? '',
      'g': _myGroupId ?? '',
      'e': _myEventId ?? '',
      't': 'sos',
      'lat': lat,
      'lng': lng,
      'b': batteryLevel,
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<int> _encodePayload(Map<String, dynamic> data) {
    final json = jsonEncode(data);
    return utf8.encode(json);
  }

  Map<String, dynamic> _decodePayload(List<int> bytes) {
    final json = utf8.decode(bytes);
    return jsonDecode(json) as Map<String, dynamic>;
  }

  void _cleanStale() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
    _nearbyDevices.removeWhere((_, d) => d.lastSeen.isBefore(cutoff));
    _nearbyController.add(Map.unmodifiable(_nearbyDevices));
  }
}
