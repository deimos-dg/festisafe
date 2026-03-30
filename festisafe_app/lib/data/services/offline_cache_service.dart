import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/member_location.dart';

/// Servicio de caché offline.
/// Persiste las últimas ubicaciones conocidas del grupo y las alertas SOS
/// pendientes de envío para cuando no hay conexión a internet.
class OfflineCacheService {
  static const _keyLocations = 'offline_member_locations';
  static const _keyPendingSos = 'offline_pending_sos';
  static const _keyLastSync = 'offline_last_sync';

  // ---------------------------------------------------------------------------
  // Ubicaciones del grupo
  // ---------------------------------------------------------------------------

  /// Guarda el mapa completo de ubicaciones del grupo.
  Future<void> saveLocations(Map<String, MemberLocation> locations) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = locations.map(
      (k, v) => MapEntry(k, {
        'userId': v.userId,
        'name': v.name,
        'latitude': v.latitude,
        'longitude': v.longitude,
        'updatedAt': v.updatedAt.toIso8601String(),
      }),
    );
    await prefs.setString(_keyLocations, jsonEncode(encoded));
    await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
  }

  /// Carga las últimas ubicaciones guardadas. Retorna mapa vacío si no hay.
  Future<Map<String, MemberLocation>> loadLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLocations);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(
          k,
          MemberLocation(
            userId: m['userId'] as String,
            name: m['name'] as String,
            latitude: (m['latitude'] as num).toDouble(),
            longitude: (m['longitude'] as num).toDouble(),
            updatedAt: DateTime.parse(m['updatedAt'] as String),
          ),
        );
      });
    } catch (_) {
      return {};
    }
  }

  /// Retorna cuándo fue la última sincronización. null si nunca.
  Future<DateTime?> lastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLastSync);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  // ---------------------------------------------------------------------------
  // SOS pendientes
  // ---------------------------------------------------------------------------

  /// Guarda una alerta SOS pendiente de envío (cuando no hay internet).
  Future<void> savePendingSos({
    required String eventId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required int batteryLevel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = _loadPendingList(prefs);
    existing.add({
      'eventId': eventId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'batteryLevel': batteryLevel,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await prefs.setString(_keyPendingSos, jsonEncode(existing));
  }

  /// Retorna la lista de SOS pendientes.
  Future<List<Map<String, dynamic>>> loadPendingSos() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadPendingList(prefs);
  }

  /// Elimina todos los SOS pendientes (tras sincronizar).
  Future<void> clearPendingSos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPendingSos);
  }

  List<Map<String, dynamic>> _loadPendingList(SharedPreferences prefs) {
    final raw = prefs.getString(_keyPendingSos);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Limpieza
  // ---------------------------------------------------------------------------

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLocations);
    await prefs.remove(_keyPendingSos);
    await prefs.remove(_keyLastSync);
  }
}
