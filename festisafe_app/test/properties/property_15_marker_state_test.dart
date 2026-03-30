import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/core/constants.dart';
import 'package:festisafe/data/models/member_location.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 15: Estado visual del marcador según tiempo de inactividad

void main() {
  // Feature: festisafe-flutter-app, Property 15: Estado visual del marcador según tiempo de inactividad
  test('Property 15: markerState corresponde al tiempo transcurrido', () {
    forAll(
      numRuns: 100,
      gen: () => genInt(min: 0, max: 3601),
      body: (secondsAgo) {
        final updatedAt = DateTime.now().subtract(Duration(seconds: secondsAgo));
        final loc = MemberLocation(
          userId: 'user-1',
          name: 'Test',
          latitude: 0.0,
          longitude: 0.0,
          updatedAt: updatedAt,
        );

        final minutesAgo = secondsAgo ~/ 60;
        final state = loc.markerState;

        if (minutesAgo >= AppConstants.markerNoSignalMinutes) {
          expect(state, equals(MarkerState.noSignal),
              reason:
                  '$minutesAgo min transcurridos, esperado noSignal (>= ${AppConstants.markerNoSignalMinutes} min)');
        } else if (minutesAgo >= AppConstants.markerDimMinutes) {
          expect(state, equals(MarkerState.dimmed),
              reason:
                  '$minutesAgo min transcurridos, esperado dimmed (>= ${AppConstants.markerDimMinutes} min)');
        } else {
          expect(state, equals(MarkerState.normal),
              reason:
                  '$minutesAgo min transcurridos, esperado normal (< ${AppConstants.markerDimMinutes} min)');
        }
      },
    );
  });

  test('Property 15b: límites exactos de transición de estado', () {
    final cases = [
      (seconds: 0, expected: MarkerState.normal),
      (seconds: 299, expected: MarkerState.normal),   // 4m59s → normal
      (seconds: 300, expected: MarkerState.dimmed),   // 5m00s → dimmed
      (seconds: 899, expected: MarkerState.dimmed),   // 14m59s → dimmed
      (seconds: 900, expected: MarkerState.noSignal), // 15m00s → noSignal
      (seconds: 3600, expected: MarkerState.noSignal),
    ];

    for (final c in cases) {
      final updatedAt = DateTime.now().subtract(Duration(seconds: c.seconds));
      final loc = MemberLocation(
        userId: 'user-1',
        name: 'Test',
        latitude: 0.0,
        longitude: 0.0,
        updatedAt: updatedAt,
      );
      expect(loc.markerState, equals(c.expected),
          reason: '${c.seconds}s → esperado ${c.expected}');
    }
  });
}
