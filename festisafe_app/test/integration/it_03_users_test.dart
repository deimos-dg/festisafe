/// IT-03: Endpoints de usuarios
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'integration_helper.dart';

void main() {
  late String accessToken;
  late Dio authedDio;

  setUpAll(() async {
    final res = await buildDio().post('/auth/login', data: {
      'email': kTestEmail,
      'password': kTestPassword,
    });
    accessToken = res.data['access_token'] as String;
    authedDio = buildDio(accessToken: accessToken);
  });

  group('IT-03 Users', () {
    test('GET /users/me retorna perfil del usuario autenticado', () async {
      final res = await authedDio.get('/users/me');
      expect(res.statusCode, 200);
      expect(res.data['email'], kTestEmail);
      expect(res.data['role'], isIn(['user', 'organizer', 'admin']));
      expect(res.data['id'], isNotEmpty);
    });

    test('GET /users/me sin token retorna 401', () async {
      final res = await buildDio().get('/users/me');
      expect(res.statusCode, 401);
    });

    test('GET /users/{id} retorna solo nombre y rol (sin email ni teléfono)',
        () async {
      // Obtener el propio ID primero
      final meRes = await authedDio.get('/users/me');
      final userId = meRes.data['id'] as String;

      final res = await authedDio.get('/users/$userId');
      expect(res.statusCode, 200);
      expect(res.data['name'], isNotEmpty);
      expect(res.data['role'], isNotEmpty);
      // Verificar que NO expone datos sensibles
      expect(res.data.containsKey('email'), isFalse);
      expect(res.data.containsKey('phone'), isFalse);
      expect(res.data.containsKey('hashed_password'), isFalse);
    });

    test('GET /users/{id} con UUID inexistente retorna 404', () async {
      final res = await authedDio
          .get('/users/00000000-0000-0000-0000-000000000000');
      expect(res.statusCode, 404);
    });

    test('PATCH /users/me actualiza nombre correctamente', () async {
      const newName = 'Test Integration Updated';
      final res = await authedDio.patch('/users/me', data: {'name': newName});
      expect(res.statusCode, 200);
      expect(res.data['name'], newName);

      // Restaurar nombre original
      await authedDio.patch('/users/me', data: {'name': 'dragnyel'});
    });
  });
}
