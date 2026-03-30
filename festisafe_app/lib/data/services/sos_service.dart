import 'package:geolocator/geolocator.dart';
import '../models/sos_alert.dart';
import 'api_client.dart';

/// Servicio de alertas SOS.
class SosService {
  final ApiClient _client;

  SosService({ApiClient? client}) : _client = client ?? ApiClient();

  /// Activa una alerta SOS. La posición es opcional — si no hay GPS el backend
  /// usa la última ubicación conocida del usuario.
  Future<void> activate({
    required String eventId,
    Position? position,
    int batteryLevel = 100,
  }) async {
    await _client.dio.post('/sos/$eventId/activate', data: {
      if (position != null) 'latitude': position.latitude,
      if (position != null) 'longitude': position.longitude,
      if (position != null) 'accuracy': position.accuracy,
      'battery_level': batteryLevel,
    });
  }

  /// Activa un SOS guardado offline (con coordenadas explícitas).
  Future<void> activateOffline({
    required String eventId,
    required double latitude,
    required double longitude,
    required double accuracy,
    required int batteryLevel,
  }) async {
    await _client.dio.post('/sos/$eventId/activate', data: {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'battery_level': batteryLevel,
    });
  }

  /// Desactiva la alerta SOS activa.
  Future<void> deactivate(String eventId) async {
    await _client.dio.post('/sos/$eventId/deactivate');
  }

  /// Obtiene la lista de SOS activos en el evento (para organizadores).
  Future<List<SosAlert>> getActiveSos(String eventId) async {
    final response = await _client.dio.get('/sos/$eventId/active');
    return (response.data as List<dynamic>)
        .map((e) => SosAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Escala un SOS activo (solo organizadores).
  Future<void> escalateSos(String eventId, String userId) async {
    await _client.dio.post('/sos/$eventId/escalate/$userId');
  }
}
