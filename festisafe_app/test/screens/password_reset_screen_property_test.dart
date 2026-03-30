// Feature: password-recovery, Property 17: Local password match validation prevents API call
// Validates: Requirements 6.6

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/data/models/password_reset_result.dart';
import 'package:festisafe/data/services/password_recovery_service.dart';
import 'package:festisafe/presentation/screens/password_reset_screen.dart';
import 'package:festisafe/providers/password_recovery_provider.dart';

import '../properties/prop_test_helper.dart';

// ---------------------------------------------------------------------------
// Mock service that returns an error result — used to assert that the token
// field is preserved when the backend returns an error.
// ---------------------------------------------------------------------------

class _ErrorService extends PasswordRecoveryService {
  final String errorMessage;

  _ErrorService(this.errorMessage) : super(client: null);

  @override
  Future<PasswordResetResult> forgotPassword(String email) async =>
      PasswordResetResult(success: false, message: errorMessage);

  @override
  Future<PasswordResetResult> resetPassword(
          String token, String newPassword) async =>
      PasswordResetResult(success: false, message: errorMessage);

  @override
  Future<PasswordResetResult> changePassword(
          String currentPassword, String newPassword) async =>
      PasswordResetResult(success: false, message: errorMessage);
}

// ---------------------------------------------------------------------------
// Mock service that tracks calls and never completes — used to assert that
// no API call is made when passwords don't match.
// ---------------------------------------------------------------------------

class _TrackingService extends PasswordRecoveryService {
  int callCount = 0;

  _TrackingService() : super(client: null);

  @override
  Future<PasswordResetResult> forgotPassword(String email) =>
      Completer<PasswordResetResult>().future;

  @override
  Future<PasswordResetResult> resetPassword(
      String token, String newPassword) async {
    callCount++;
    return Completer<PasswordResetResult>().future;
  }

  @override
  Future<PasswordResetResult> changePassword(
      String currentPassword, String newPassword) async {
    callCount++;
    return Completer<PasswordResetResult>().future;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Generates a valid 64-char hex token.
String _genToken() {
  const hex = '0123456789abcdef';
  return List.generate(64, (_) => hex[rng.nextInt(hex.length)]).join();
}

/// Generates a password that passes the minimum 12-char validator.
String _genValidPassword(String suffix) {
  final prefix = genString(minLen: 4, maxLen: 8);
  return '${prefix}Aa1!${suffix}secure';
}

/// Generates two passwords that are guaranteed to be different.
/// Returns (passwordA, passwordB) where passwordA != passwordB.
(String, String) _genMismatchedPasswords() {
  // Use distinct suffixes to guarantee they differ.
  final a = _genValidPassword('AAA');
  final b = _genValidPassword('BBB');
  // Ensure they are actually different (they always will be given distinct suffixes,
  // but be defensive).
  if (a == b) {
    return (a, '${b}X');
  }
  return (a, b);
}

// ---------------------------------------------------------------------------
// Widget builder
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required _TrackingService service,
  required String token,
}) {
  final notifier = PasswordRecoveryNotifier(service);

  return ProviderScope(
    overrides: [
      passwordRecoveryProvider.overrideWith((_) => notifier),
    ],
    child: MaterialApp(
      home: PasswordResetScreen(
        mode: PasswordResetMode.resetWithToken,
        token: token,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Feature: password-recovery, Property 16: Deep link token pre-fill
  // Validates: Requirements 6.5
  group('Property 16: Deep link token pre-fill', () {
    testWidgets(
      'token from deep link pre-fills the token field exactly',
      (WidgetTester tester) async {
        // Generates random 64-char hex tokens and verifies the field is pre-filled.
        const hex = '0123456789abcdef';

        int runIndex = 0;
        await forAll<String>(
          numRuns: 30,
          gen: () => List.generate(64, (_) => hex[rng.nextInt(hex.length)]).join(),
          body: (String generatedToken) async {
            final service = _TrackingService();

            // Use a unique key per run to force a full widget rebuild,
            // ensuring the TextEditingController is re-initialized with the new token.
            await tester.pumpWidget(KeyedSubtree(
              key: ValueKey(runIndex++),
              child: _buildScreen(service: service, token: generatedToken),
            ));
            await tester.pumpAndSettle();

            // The token field labeled 'Token de recuperación' must contain exactly the generated token.
            final tokenField = find.widgetWithText(TextFormField, 'Token de recuperación');
            expect(tokenField, findsOneWidget,
                reason: 'Token de recuperación field must be present');

            final controller = (tester.widget<TextFormField>(tokenField).controller)!;
            expect(
              controller.text,
              equals(generatedToken),
              reason:
                  'Token field must contain exactly the deep link token value. '
                  'Expected: "$generatedToken"',
            );
          },
        );
      },
    );
  });

  // Feature: password-recovery, Property 15: Token field preserved on error
  // Validates: Requirements 6.4, 7.4
  group('Property 15: Token field preserved on error', () {
    testWidgets(
      'token field is not cleared when backend returns an error',
      (WidgetTester tester) async {
        int runIndex = 0;
        await forAll2<String, String>(
          numRuns: 30,
          genA: _genToken,
          genB: () => genNonEmptyString(maxLen: 40),
          body: (String token, String errorMessage) async {
            final service = _ErrorService(errorMessage);
            final notifier = PasswordRecoveryNotifier(service);

            final password = _genValidPassword('SAME');

            await tester.pumpWidget(KeyedSubtree(
              key: ValueKey('p15-${runIndex++}'),
              child: ProviderScope(
                overrides: [
                  passwordRecoveryProvider.overrideWith((_) => notifier),
                ],
                child: MaterialApp(
                  home: PasswordResetScreen(
                    mode: PasswordResetMode.resetWithToken,
                    token: token,
                  ),
                ),
              ),
            ));
            await tester.pumpAndSettle();

            // Enter matching passwords so local validation passes.
            final newPassField =
                find.widgetWithText(TextFormField, 'Nueva contraseña');
            await tester.enterText(newPassField, password);

            final confirmPassField =
                find.widgetWithText(TextFormField, 'Confirmar nueva contraseña');
            await tester.enterText(confirmPassField, password);

            // Tap submit and wait for the error state to settle.
            final submitButton =
                find.widgetWithText(FilledButton, 'Restablecer contraseña');
            await tester.tap(submitButton);
            await tester.pumpAndSettle();

            // Assert: token field still contains the original token.
            final tokenField =
                find.widgetWithText(TextFormField, 'Token de recuperación');
            expect(tokenField, findsOneWidget,
                reason: 'Token de recuperación field must be present');

            final controller =
                (tester.widget<TextFormField>(tokenField).controller)!;
            expect(
              controller.text,
              equals(token),
              reason:
                  'Token field must be preserved after a backend error. '
                  'Expected: "$token"',
            );

            // Assert: the error message is shown inline.
            expect(find.text(errorMessage), findsOneWidget,
                reason:
                    'Inline error message "$errorMessage" must be shown after '
                    'a backend error');
          },
        );
      },
    );
  });

  // Feature: password-recovery, Property 17: Local password match validation prevents API call
  group('Property 17: Local password match validation prevents API call', () {
    testWidgets(
      'mismatched passwords: no API call is made and error message is shown',
      (WidgetTester tester) async {
        // Run property test with multiple generated pairs of mismatched passwords.
        // We use a reduced numRuns because each run pumps a full widget tree.
        const numRuns = 30;

        for (int i = 0; i < numRuns; i++) {
          final service = _TrackingService();
          final token = _genToken();
          final (passwordA, passwordB) = _genMismatchedPasswords();

          // Ensure passwords are actually different (property precondition).
          assert(passwordA != passwordB,
              'Generator must produce different passwords');

          await tester.pumpWidget(_buildScreen(service: service, token: token));
          await tester.pumpAndSettle();

          // Enter the first (new) password.
          final newPassField = find.widgetWithText(TextFormField, 'Nueva contraseña');
          expect(newPassField, findsOneWidget,
              reason: 'Nueva contraseña field must be present');
          await tester.enterText(newPassField, passwordA);

          // Enter a different confirm password.
          final confirmPassField =
              find.widgetWithText(TextFormField, 'Confirmar nueva contraseña');
          expect(confirmPassField, findsOneWidget,
              reason: 'Confirmar nueva contraseña field must be present');
          await tester.enterText(confirmPassField, passwordB);

          // Tap the submit button.
          final submitButton =
              find.widgetWithText(FilledButton, 'Restablecer contraseña');
          expect(submitButton, findsOneWidget,
              reason: 'Submit button must be present');
          await tester.tap(submitButton);
          await tester.pumpAndSettle();

          // Assert: no API call was made.
          expect(service.callCount, equals(0),
              reason:
                  'No API call should be made when passwords do not match. '
                  'Passwords were: "$passwordA" and "$passwordB"');

          // Assert: a validation error message is shown.
          expect(find.text('Las contraseñas no coinciden'), findsOneWidget,
              reason:
                  'Error message "Las contraseñas no coinciden" must be shown '
                  'when passwords do not match');
        }
      },
    );

    testWidgets(
      'matching passwords: API call IS made (control case)',
      (WidgetTester tester) async {
        // This control test verifies the inverse: matching passwords DO trigger
        // an API call, confirming the mock and widget wiring are correct.
        final service = _TrackingService();
        final token = _genToken();
        final password = _genValidPassword('SAME');

        await tester.pumpWidget(_buildScreen(service: service, token: token));
        await tester.pumpAndSettle();

        final newPassField =
            find.widgetWithText(TextFormField, 'Nueva contraseña');
        await tester.enterText(newPassField, password);

        final confirmPassField =
            find.widgetWithText(TextFormField, 'Confirmar nueva contraseña');
        await tester.enterText(confirmPassField, password);

        final submitButton =
            find.widgetWithText(FilledButton, 'Restablecer contraseña');
        await tester.tap(submitButton);
        await tester.pump(); // Don't settle — service never completes.

        // The API call should have been made.
        expect(service.callCount, equals(1),
            reason:
                'API call should be made when passwords match (control case)');
      },
    );
  });
}
