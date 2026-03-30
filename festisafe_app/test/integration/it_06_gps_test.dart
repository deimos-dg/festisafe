/// IT-06: Endpoints de GPS / ubicación
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
    authedDio = buildDio(accessToken: res.data['access_token'] as String);
  });

  group('IT-06 GPS', () {
    test('POST /gps/location/{eventId} actualiza ubicación', () async {
      final res = await authedDio.post('/gps/location/$kTestEventId', data: {
        'latitude': 51.0893,
        'longitude': 4.3722,
        'accuracy': 5.0,
      });
      expect(res.statusCode, 200);
      expect(res.data['latitude'], closeTo(51.0893, 0.0001));
      expect(res.data['longitude'], closeTo(4.3722, 0.0001));
    });

    test('POST /gps/location con coordenadas inválidas retorna 422', () async {
      final res = await authedDio.post('/gps/location/$kTestEventId', data: {
        'latitude': 999.0, // fuera de rango
        'longitude': 4.3722,
      });
      expect(res.statusCode, 422);
    });

    test('POST /gps/location con accuracy negativa retorna 422', () async {
      final res = await authedDio.post('/gps/location/$kTestEventId', data: {
        'latitude': 51.0893,
        'longitude': 4.3722,
        'accuracy': -10.0, // inválido
      });
      expect(res.statusCode, 422);
    });

    test('GET /gps/location/{eventId} retorna ubicaciones del grupo', () async {
      final res = await authedDio.get('/gps/location/$kTestEventId');
      expect(res.statusCode, 200);
      expect(res.data, isList);
      // Cada ubicación debe tener los campos requeridos
      for (final loc in res.data as List) {
        expect(loc['user_id'], isNotEmpty);
        expect(loc['latitude'], isNotNull);
        expect(loc['longitude'], isNotNull);
      }
    });

    test('PATCH /gps/visibility/{eventId} cambia visibilidad', () async {
      // Desactivar visibilidad
      final hideRes = await authedDio.patch(
        '/gps/visibility/$kTestEventId',
        queryParameters: {'visible': false},
      );
      expect(hideRes.statusCode, 200);
      expect(hideRes.data['is_visible'], isFalse);

      // Reactivar visibilidad
      final showRes = await authedDio.patch(
        '/gps/visibility/$kTestEventId',
        queryParameters: {'visible': true},
      );
      expect(showRes.statusCode, 200);
      expect(showRes.data['is_visible'], isTrue);
    });

    test('GET /gps/location sin token retorna 401', () async {
      final res = await buildDio().get('/gps/location/$kTestEventId');
      expect(res.statusCode, 401);
    });
  });
}
