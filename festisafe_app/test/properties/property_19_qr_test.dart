import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/data/models/guest_code.dart';

import 'prop_test_helper.dart';

// Feature: festisafe-flutter-app, Property 19: Extracción correcta de código desde QR

/// Simula la codificación del QR: QrImageView(data: code)
String encodeQr(String code) => code;

/// Simula la extracción del código desde el QR escaneado.
/// MobileScanner devuelve el string codificado tal cual.
String? extractCodeFromQr(String? scannedData) {
  if (scannedData == null || scannedData.isEmpty) return null;
  final trimmed = scannedData.trim();
  if (RegExp(r'^\d{6}$').hasMatch(trimmed)) return trimmed;
  return null;
}

void main() {
  // Feature: festisafe-flutter-app, Property 19: Extracción correcta de código desde QR
  test('Property 19: escanear QR extrae exactamente el código de 6 dígitos codificado', () {
    forAll(
      numRuns: 100,
      gen: () => genGuestCode(),
      body: (code) {
        expect(code.length, equals(6));
        expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);

        final qrData = encodeQr(code);
        final extracted = extractCodeFromQr(qrData);

        expect(extracted, isNotNull,
            reason: 'El código "$code" no pudo ser extraído del QR');
        expect(extracted, equals(code),
            reason: 'Código original: "$code", extraído: "$extracted"');
      },
    );
  });

  test('Property 19b: GuestCodeModel preserva el código de 6 dígitos', () {
    forAll(
      numRuns: 100,
      gen: () => genGuestCode(),
      body: (code) {
        final guestCode = GuestCodeModel(
          code: code,
          expiresAt: DateTime.now().add(const Duration(hours: 24)),
          remainingUses: 1,
          eventId: 'evt-1',
        );

        expect(guestCode.code, equals(code));
        expect(guestCode.code.length, equals(6));
        expect(RegExp(r'^\d{6}$').hasMatch(guestCode.code), isTrue);

        final extracted = extractCodeFromQr(encodeQr(guestCode.code));
        expect(extracted, equals(code));
      },
    );
  });

  test('Property 19c: extractCodeFromQr rechaza datos que no son 6 dígitos', () {
    // Casos inválidos conocidos
    final invalidCases = [
      '',
      '12345',    // 5 dígitos
      '1234567',  // 7 dígitos
      'abc123',   // letras
      '12 345',   // espacio
      'ABCDEF',   // letras mayúsculas
    ];

    for (final invalid in invalidCases) {
      expect(extractCodeFromQr(invalid), isNull,
          reason: '"$invalid" no es un código válido de 6 dígitos');
    }
  });
}
