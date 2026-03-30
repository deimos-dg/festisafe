import 'package:geolocator/geolocator.dart';
import 'api_client.dart';

/// Servicio de ubicación GPS con gestión de permisos y fallback HTTP.
class LocationService {
  final ApiClient _client;

  LocationService({ApiClient? client}) : _client = client ?? ApiClient();

  /// Solicita permiso de ubicación. Devuelve true si fue concedido.
  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Obtiene la posición GPS actual.
  Future<Position> getCurrentPosition() async {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
  }

  /// Stream de posiciones GPS con el intervalo especificado (segundos).
  Stream<Position> startTracking({int intervalSeconds = 10}) {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: Duration(seconds: intervalSeconds),
        distanceFilter: 3,
      ),
    );
  }

  /// Activa o desactiva la visibilidad de la ubicación del usuario.
  Future<void> setVisibility(String eventId, bool visible) async {
    await _client.dio.patch(
      '/gps/visibility/$eventId',
      queryParameters: {'visible': visible},
    );
  }

  /// Envía la ubicación por HTTP como fallback cuando el WS no está disponible.
  Future<void> sendFallbackLocation(
    String eventId,
    Position position,
  ) async {
    await _client.dio.post('/gps/location/$eventId', data: {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
    });
  }

  /// Obtiene las últimas ubicaciones conocidas del grupo vía HTTP.
  Future<List<Map<String, dynamic>>> getGroupLocations(String eventId) async {
    final response = await _client.dio.get('/gps/location/$eventId');
    return (response.data as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }
}
