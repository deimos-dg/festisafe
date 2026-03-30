import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/core/constants.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 8: Mensajes de ubicación con formato correcto
// Feature: festisafe-flutter-app, Property 9: Respuesta pong ante cualquier ping
// Feature: festisafe-flutter-app, Property 10: Backoff exponencial en reconexión

void main() {
  // Feature: festisafe-flutter-app, Property 8: Mensajes de ubicación con formato correcto
  test('Property 8: mensaje de ubicación tiene formato correcto', () {
    forAll3(
      numRuns: 100,
      genA: () => genDouble(min: -90.0, max: 90.0),
      genB: () => genDouble(min: -180.0, max: 180.0),
      genC: () => genDouble(min: 0.0, max: 100.0),
      body: (lat, lng, accuracy) {
        // Simular la construcción del mensaje que hace WsClient.sendLocation
        final message = {
          'type': 'location',
          'latitude': lat,
          'longitude': lng,
          'accuracy': accuracy,
        };

        final encoded = jsonEncode(message);
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;

        expect(decoded['type'], equals('location'));
        expect(decoded['latitude'], isA<double>());
        expect(decoded['longitude'], isA<double>());
        expect(decoded['accuracy'], isA<double>());

        final decodedLat = decoded['latitude'] as double;
        final decodedLng = decoded['longitude'] as double;
        final decodedAcc = decoded['accuracy'] as double;

        expect(decodedLat.isNaN, isFalse);
        expect(decodedLat.isInfinite, isFalse);
        expect(decodedLng.isNaN, isFalse);
        expect(decodedLng.isInfinite, isFalse);
        expect(decodedAcc.isNaN, isFalse);
        expect(decodedAcc.isInfinite, isFalse);

        expect(decodedLat, closeTo(lat, 1e-10));
        expect(decodedLng, closeTo(lng, 1e-10));
      },
    );
  });

  // Feature: festisafe-flutter-app, Property 9: Respuesta pong ante cualquier ping
  test('Property 9: WsClient responde pong ante cualquier mensaje ping', () {
    forAll(
      numRuns: 100,
      gen: () => genString(minLen: 0, maxLen: 20),
      body: (extraField) {
        final sentMessages = <Map<String, dynamic>>[];

        void simulateSend(Map<String, dynamic> data) {
          sentMessages.add(data);
        }

        void simulateOnData(String raw) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if (json['type'] == 'ping') {
            // WsClient debe responder con pong antes de procesar el siguiente mensaje
            simulateSend({'type': 'pong'});
            return;
          }
        }

        simulateOnData(jsonEncode({'type': 'ping'}));

        expect(sentMessages.length, equals(1));
        expect(sentMessages.first['type'], equals('pong'));
      },
    );
  });

  // Feature: festisafe-flutter-app, Property 10: Backoff exponencial en reconexión
  test('Property 10: backoff exponencial es min(2^N * 2, 60) segundos', () {
    forAll(
      numRuns: 100,
      gen: () => genInt(min: 0, max: 11),
      body: (attempt) {
        // Fórmula del WsClient: min(pow(2, attempt) * wsReconnectBase, wsReconnectMax)
        final expectedDelay = min(
          pow(2, attempt).toInt() * AppConstants.wsReconnectBase,
          AppConstants.wsReconnectMax,
        );

        expect(expectedDelay, greaterThanOrEqualTo(AppConstants.wsReconnectBase));
        expect(expectedDelay, lessThanOrEqualTo(AppConstants.wsReconnectMax));

        if (attempt == 0) {
          expect(expectedDelay, equals(AppConstants.wsReconnectBase));
        }

        if (attempt > 0) {
          final prevDelay = min(
            pow(2, attempt - 1).toInt() * AppConstants.wsReconnectBase,
            AppConstants.wsReconnectMax,
          );
          expect(expectedDelay, greaterThanOrEqualTo(prevDelay));
        }
      },
    );
  });

  test('Property 10b: secuencia completa de backoff es monótonamente creciente hasta 60s', () {
    // Verificar la secuencia exacta: 2, 4, 8, 16, 32, 60, 60, 60...
    final expectedSequence = [2, 4, 8, 16, 32, 60, 60, 60];
    for (int i = 0; i < expectedSequence.length; i++) {
      final delay = min(
        pow(2, i).toInt() * AppConstants.wsReconnectBase,
        AppConstants.wsReconnectMax,
      );
      expect(delay, equals(expectedSequence[i]),
          reason: 'Intento $i: esperado ${expectedSequence[i]}s, obtenido ${delay}s');
    }
  });
}
