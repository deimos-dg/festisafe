/// IT-04: Endpoints de eventos
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'integration_helper.dart';

void main() {
  late Dio authedDio;

  setUpAll(() async {
    final res = await buildDio().post('/auth/login', data: {
      'email': kTestEmail,
      'password': kTestPassword,
    });
    final token = res.data['access_token'] as String;
    authedDio = buildDio(accessToken: token);
  });

  group('IT-04 Events — lectura', () {
    test('GET /events/public retorna lista de eventos activos', () async {
      final res = await buildDio().get('/events/public');
      expect(res.statusCode, 200);
      expect(res.data, isList);
    });

    test('GET /events/public con query q filtra por nombre', () async {
      final res = await buildDio().get('/events/public',
          queryParameters: {'q': 'Tomorrowland'});
      expect(res.statusCode, 200);
      final list = res.data as List;
      if (list.isNotEmpty) {
        expect(
          list.every((e) =>
              (e['name'] as String)
                  .toLowerCase()
                  .contains('tomorrowland') ||
              ((e['location_name'] ?? '') as String)
                  .toLowerCase()
                  .contains('tomorrowland')),
          isTrue,
        );
      }
    });

    test('GET /events/my retorna eventos del usuario autenticado', () async {
      final res = await authedDio.get('/events/my');
      expect(res.statusCode, 200);
      expect(res.data, isList);
    });

    test('GET /events/{id} retorna detalle del evento de prueba', () async {
      final res = await authedDio.get('/events/$kTestEventId');
      expect(res.statusCode, 200);
      expect(res.data['id'], kTestEventId);
      expect(res.data['name'], isNotEmpty);
    });

    test('GET /events/{id} con UUID inválido retorna 404', () async {
      final res =
          await authedDio.get('/events/00000000-0000-0000-0000-000000000000');
      expect(res.statusCode, 404);
    });

    test('GET /events/my sin token retorna 401', () async {
      final res = await buildDio().get('/events/my');
      expect(res.statusCode, 401);
    });
  });

  group('IT-04 Events — creación y ciclo de vida', () {
    late String createdEventId;

    test('POST /events/ crea evento y organizador queda inscrito', () async {
      final now = DateTime.now().toUtc();
      final res = await authedDio.post('/events/', data: {
        'name': 'IT Test Event ${now.millisecondsSinceEpoch}',
        'starts_at': now.add(const Duration(days: 1)).toIso8601String(),
        'ends_at': now.add(const Duration(days: 2)).toIso8601String(),
        'max_participants': 10,
      });
      expect(res.statusCode, 201);
      createdEventId = res.data['id'] as String;
      expect(createdEventId, isNotEmpty);

      // El organizador debe aparecer en /events/my
      final myEvents = await authedDio.get('/events/my');
      final ids = (myEvents.data as List).map((e) => e['id']).toList();
      expect(ids, contains(createdEventId));
    });

    test('POST /events/{id}/activate activa el evento', () async {
      final res = await authedDio.post('/events/$createdEventId/activate');
      expect(res.statusCode, 200);
      expect(res.data['is_active'], isTrue);
    });

    test('POST /events/{id}/deactivate desactiva el evento', () async {
      final res = await authedDio.post('/events/$createdEventId/deactivate');
      expect(res.statusCode, 200);
      expect(res.data['is_active'], isFalse);
    });

    test('DELETE /events/{id} elimina el evento', () async {
      final res = await authedDio.delete('/events/$createdEventId');
      expect(res.statusCode, 200);

      // Verificar que ya no existe
      final getRes = await authedDio.get('/events/$createdEventId');
      expect(getRes.statusCode, 404);
    });

    test('POST /events/ con ends_at <= starts_at retorna 400', () async {
      final now = DateTime.now().toUtc();
      final res = await authedDio.post('/events/', data: {
        'name': 'Bad Dates Event',
        'starts_at': now.add(const Duration(days: 2)).toIso8601String(),
        'ends_at': now.add(const Duration(days: 1)).toIso8601String(),
        'max_participants': 10,
      });
      expect(res.statusCode, 400);
    });
  });
}
