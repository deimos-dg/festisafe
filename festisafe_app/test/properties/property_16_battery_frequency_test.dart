import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/core/constants.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 16: Frecuencia de ubicación según nivel de batería

/// Calcula el intervalo de tracking según el nivel de batería.
/// Replica la lógica de LocationNotifier.startTracking.
int computeTrackingInterval(int batteryLevel) {
  if (batteryLevel < AppConstants.batteryLowThreshold) {
    return AppConstants.locationIntervalLowBattery;
  }
  return AppConstants.locationIntervalNormal;
}

/// Determina si se debe restaurar la frecuencia normal al cargar.
bool shouldRestoreNormalFrequency(int batteryLevel) {
  return batteryLevel >= AppConstants.batteryRestoreThreshold;
}

void main() {
  // Feature: festisafe-flutter-app, Property 16: Frecuencia de ubicación según nivel de batería
  test('Property 16: intervalo de ubicación es 10s si batería >= 20%, 30s si < 20%', () {
    forAll(
      numRuns: 100,
      gen: () => genInt(min: 0, max: 101),
      body: (batteryLevel) {
        final interval = computeTrackingInterval(batteryLevel);

        if (batteryLevel >= AppConstants.batteryLowThreshold) {
          expect(interval, equals(AppConstants.locationIntervalNormal),
              reason:
                  'Batería $batteryLevel% >= ${AppConstants.batteryLowThreshold}%: '
                  'esperado ${AppConstants.locationIntervalNormal}s, obtenido ${interval}s');
        } else {
          expect(interval, equals(AppConstants.locationIntervalLowBattery),
              reason:
                  'Batería $batteryLevel% < ${AppConstants.batteryLowThreshold}%: '
                  'esperado ${AppConstants.locationIntervalLowBattery}s, obtenido ${interval}s');
        }
      },
    );
  });

  test('Property 16b: frecuencia normal se restaura al superar el 25%', () {
    forAll(
      numRuns: 100,
      gen: () => genInt(min: 0, max: 101),
      body: (batteryLevel) {
        final shouldRestore = shouldRestoreNormalFrequency(batteryLevel);

        if (batteryLevel >= AppConstants.batteryRestoreThreshold) {
          expect(shouldRestore, isTrue,
              reason:
                  'Batería $batteryLevel% >= ${AppConstants.batteryRestoreThreshold}%: debe restaurar frecuencia normal');
        } else {
          expect(shouldRestore, isFalse,
              reason:
                  'Batería $batteryLevel% < ${AppConstants.batteryRestoreThreshold}%: no debe restaurar');
        }
      },
    );
  });

  test('Property 16c: límites exactos de los umbrales de batería', () {
    expect(computeTrackingInterval(19), equals(AppConstants.locationIntervalLowBattery));
    expect(computeTrackingInterval(20), equals(AppConstants.locationIntervalNormal));
    expect(shouldRestoreNormalFrequency(24), isFalse);
    expect(shouldRestoreNormalFrequency(25), isTrue);
  });
}
