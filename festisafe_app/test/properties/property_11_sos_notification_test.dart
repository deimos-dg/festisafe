import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/data/models/sos_alert.dart';
import 'package:festisafe/data/models/ws_message.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 11: Notificación SOS contiene datos del emisor

void main() {
  // Feature: festisafe-flutter-app, Property 11: Notificación SOS contiene datos del emisor
  test('Property 11: SosAlert.fromWsMessage preserva nombre, ubicación y batería', () {
    forAll3(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 40),
      genB: () => genNonEmptyString(maxLen: 40),
      genC: () => genInt(min: 0, max: 101),
      body: (userName, userId, battery) {
        final lat = genDouble(min: -90.0, max: 90.0);
        final lng = genDouble(min: -180.0, max: 180.0);

        final payload = {
          'type': 'sos',
          'user_id': userId,
          'name': userName,
          'latitude': lat,
          'longitude': lng,
          'battery_level': battery,
        };

        final wsMessage = WsMessage.fromJson(payload);
        expect(wsMessage.type, equals(WsMessageType.sos));

        final alert = SosAlert.fromWsMessage(wsMessage.payload);

        // La notificación debe contener todos los datos del emisor
        expect(alert.userName, isNotEmpty);
        expect(alert.userName, equals(userName));
        expect(alert.userId, equals(userId));
        expect(alert.latitude, closeTo(lat, 1e-10));
        expect(alert.longitude, closeTo(lng, 1e-10));
        expect(alert.batteryLevel, equals(battery));
      },
    );
  });

  test('Property 11b: SosAlert.fromWsMessage usa "Desconocido" si falta el nombre', () {
    forAll(
      numRuns: 100,
      gen: () => genNonEmptyString(maxLen: 40),
      body: (userId) {
        final payload = {
          'type': 'sos',
          'user_id': userId,
          'latitude': 40.0,
          'longitude': -3.0,
          'battery_level': 50,
        };

        final alert = SosAlert.fromWsMessage(payload);

        expect(alert.userName, isNotEmpty);
        expect(alert.userName, equals('Desconocido'));
      },
    );
  });
}
