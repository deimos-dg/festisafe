import '../models/event.dart';
import '../models/guest_code.dart';
import 'api_client.dart';

/// Servicio de eventos: búsqueda, unión, gestión y códigos de invitado.
class EventService {
  final ApiClient _client;

  EventService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<List<EventModel>> searchEvents({String? query, bool activeOnly = true}) async {
    final response = await _client.dio.get('/events/search', queryParameters: {
      if (query != null && query.isNotEmpty) 'q': query,
      'active_only': activeOnly,
    });
    final list = (response.data as List<dynamic>)
        .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
        .toList();
    // Ordenar por fecha de inicio ascendente (invariante Propiedad 5)
    list.sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }

  Future<List<EventModel>> getMyEvents() async {
    final response = await _client.dio.get('/events/my');
    return (response.data as List<dynamic>)
        .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<EventModel>> getOrganizedEvents() async {
    final response = await _client.dio.get('/events/organized');
    return (response.data as List<dynamic>)
        .map((e) => EventModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> joinEvent(String eventId) async {
    await _client.dio.post('/events/$eventId/join');
  }

  Future<void> leaveEvent(String eventId) async {
    await _client.dio.post('/events/$eventId/leave');
  }

  Future<EventModel> createEvent(Map<String, dynamic> data) async {
    final response = await _client.dio.post('/events/', data: data);
    return EventModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteEvent(String eventId) async {
    await _client.dio.delete('/events/$eventId');
  }

  Future<void> activateEvent(String eventId) async {
    await _client.dio.post('/events/$eventId/activate');
  }

  Future<void> deactivateEvent(String eventId) async {
    await _client.dio.post('/events/$eventId/deactivate');
  }

  Future<List<Map<String, dynamic>>> getParticipants(String eventId) async {
    final response = await _client.dio.get('/events/$eventId/participants');
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> setMeetingPoint(String eventId, double lat, double lng) async {
    await _client.dio.patch('/events/$eventId', data: {
      'meeting_point_lat': lat,
      'meeting_point_lng': lng,
    });
  }

  Future<GuestCodeModel> generateGuestCode(
    String eventId, {
    int expiresHours = 24,
  }) async {
    final response = await _client.dio.post(
      '/events/$eventId/guest-code',
      queryParameters: {'expires_hours': expiresHours},
    );
    return GuestCodeModel.fromJson(response.data as Map<String, dynamic>);
  }
}
