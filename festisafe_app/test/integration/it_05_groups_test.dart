/// IT-05: Endpoints de grupos
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'integration_helper.dart';

void main() {
  late Dio authedDio;
  late String eventId;

  setUpAll(() async {
    final loginRes = await buildDio().post('/auth/login', data: {
      'email': kTestEmail,
      'password': kTestPassword,
    });
    final token = loginRes.data['access_token'] as String;
    authedDio = buildDio(accessToken: token);

    // Crear un evento de prueba para los tests de grupo
    final now = DateTime.now().toUtc();
    final eventRes = await authedDio.post('/events/', data: {
      'name': 'IT Group Test Event ${now.millisecondsSinceEpoch}',
      'starts_at': now.add(const Duration(days: 1)).toIso8601String(),
      'ends_at': now.add(const Duration(days: 2)).toIso8601String(),
      'max_participants': 50,
    });
    eventId = eventRes.data['id'] as String;
    await authedDio.post('/events/$eventId/activate');
  });

  tearDownAll(() async {
    // Limpiar el evento de prueba
    await authedDio.delete('/events/$eventId');
  });

  group('IT-05 Groups', () {
    late String groupId;

    test('POST /groups/ crea grupo en el evento', () async {
      final res = await authedDio.post('/groups/', data: {
        'event_id': eventId,
        'name': 'Grupo IT Test',
      });
      expect(res.statusCode, 201);
      groupId = res.data['group_id'] as String;
      expect(groupId, isNotEmpty);
    });

    test('GET /groups/my/{eventId} retorna el grupo del usuario', () async {
      final res = await authedDio.get('/groups/my/$eventId');
      expect(res.statusCode, 200);
      expect(res.data['group_id'], groupId);
      expect(res.data['name'], 'Grupo IT Test');
    });

    test('GET /groups/{id} retorna detalle del grupo', () async {
      final res = await authedDio.get('/groups/$groupId');
      expect(res.statusCode, 200);
      expect(res.data['group_id'], groupId);
      expect(res.data['name'], isNotEmpty);
    });

    test('GET /groups/{id}/members retorna lista de miembros', () async {
      final res = await authedDio.get('/groups/$groupId/members');
      expect(res.statusCode, 200);
      expect(res.data['members'], isList);
      expect((res.data['members'] as List).length, greaterThanOrEqualTo(1));
    });

    test('GET /groups/{id}/members sin pertenecer retorna 403', () async {
      // Crear usuario nuevo que no pertenece al grupo
      final email = uniqueEmail();
      await buildDio().post('/auth/register', data: {
        'name': 'Outsider',
        'email': email,
        'password': kValidPassword,
        'confirm_password': kValidPassword,
        'is_organizer': false,
      });
      final loginRes = await buildDio().post('/auth/login', data: {
        'email': email,
        'password': kValidPassword,
      });
      final outsiderDio =
          buildDio(accessToken: loginRes.data['access_token'] as String);

      final res = await outsiderDio.get('/groups/$groupId/members');
      expect(res.statusCode, 403);
    });

    test('POST /groups/ duplicado en mismo evento retorna 400', () async {
      final res = await authedDio.post('/groups/', data: {
        'event_id': eventId,
        'name': 'Grupo Duplicado',
      });
      expect(res.statusCode, 400);
    });

    test('DELETE /groups/{id} elimina el grupo', () async {
      final res = await authedDio.delete('/groups/$groupId');
      expect(res.statusCode, 200);

      // Verificar que ya no existe
      final getRes = await authedDio.get('/groups/$groupId');
      expect(getRes.statusCode, 404);
    });
  });
}
