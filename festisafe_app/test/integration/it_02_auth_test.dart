/// IT-02: Flujos de autenticación
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'integration_helper.dart';

void main() {
  final dio = buildDio();

  group('IT-02 Auth — registro y login', () {
    late String testEmail;

    setUp(() => testEmail = uniqueEmail());

    // -----------------------------------------------------------------------
    test('POST /auth/register crea usuario y retorna user_id', () async {
      final res = await dio.post('/auth/register', data: {
        'name': 'Test Integration',
        'email': testEmail,
        'password': kValidPassword,
        'confirm_password': kValidPassword,
        'is_organizer': false,
      });
      expect(res.statusCode, 201);
      expect(res.data['user_id'], isNotEmpty);
    });

    // -----------------------------------------------------------------------
    test('POST /auth/register con email duplicado retorna 400', () async {
      // Primer registro
      await dio.post('/auth/register', data: {
        'name': 'Test Dup',
        'email': testEmail,
        'password': kValidPassword,
        'confirm_password': kValidPassword,
        'is_organizer': false,
      });
      // Segundo intento con el mismo email
      final res = await dio.post('/auth/register', data: {
        'name': 'Test Dup 2',
        'email': testEmail,
        'password': kValidPassword,
        'confirm_password': kValidPassword,
        'is_organizer': false,
      });
      expect(res.statusCode, 400);
    });

    // -----------------------------------------------------------------------
    test('POST /auth/register con contraseña débil retorna 422', () async {
      final res = await dio.post('/auth/register', data: {
        'name': 'Test Weak',
        'email': testEmail,
        'password': '1234',
        'confirm_password': '1234',
        'is_organizer': false,
      });
      expect(res.statusCode, 422);
    });

    // -----------------------------------------------------------------------
    test('POST /auth/login con credenciales válidas retorna tokens', () async {
      final res = await dio.post('/auth/login', data: {
        'email': kTestEmail,
        'password': kTestPassword,
      });
      expect(res.statusCode, 200);
      expect(res.data['access_token'], isNotEmpty);
      expect(res.data['refresh_token'], isNotEmpty);
      expect(res.data['token_type'], 'bearer');
    });

    // -----------------------------------------------------------------------
    test('POST /auth/login con contraseña incorrecta retorna 401', () async {
      final res = await dio.post('/auth/login', data: {
        'email': kTestEmail,
        'password': 'WrongPassword999!',
      });
      expect(res.statusCode, 401);
    });

    // -----------------------------------------------------------------------
    test('POST /auth/login con email inexistente retorna 401', () async {
      final res = await dio.post('/auth/login', data: {
        'email': 'noexiste_${uniqueEmail()}',
        'password': kValidPassword,
      });
      expect(res.statusCode, 401);
    });
  });

  // -------------------------------------------------------------------------
  group('IT-02 Auth — refresh y logout', () {
    late String accessToken;
    late String refreshToken;

    setUp(() async {
      final res = await dio.post('/auth/login', data: {
        'email': kTestEmail,
        'password': kTestPassword,
      });
      accessToken = res.data['access_token'] as String;
      refreshToken = res.data['refresh_token'] as String;
    });

    test('POST /auth/refresh renueva tokens correctamente', () async {
      final res = await dio.post(
        '/auth/refresh',
        options: _bearer(refreshToken),
      );
      expect(res.statusCode, 200);
      expect(res.data['access_token'], isNotEmpty);
      expect(res.data['refresh_token'], isNotEmpty);
      // El nuevo access token debe ser diferente al anterior
      expect(res.data['access_token'], isNot(equals(accessToken)));
    });

    test('POST /auth/refresh con access token retorna 401', () async {
      // Usar access token donde se espera refresh token
      final res = await dio.post(
        '/auth/refresh',
        options: _bearer(accessToken),
      );
      expect(res.statusCode, 401);
    });

    test('POST /auth/logout revoca el token', () async {
      final res = await dio.post(
        '/auth/logout',
        options: _bearer(accessToken),
      );
      expect(res.statusCode, 200);

      // Después del logout, el token ya no debe funcionar
      final meRes = await buildDio(accessToken: accessToken).get('/users/me');
      expect(meRes.statusCode, 401);
    });
  });
}

_bearer(String token) => Options(headers: {'Authorization': 'Bearer $token'});
