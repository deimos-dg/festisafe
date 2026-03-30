// Feature: password-recovery, Property 14: Loading state on form submit
// Validates: Requirements 6.2

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/data/models/password_reset_result.dart';
import 'package:festisafe/data/services/password_recovery_service.dart';
import 'package:festisafe/providers/password_recovery_provider.dart';

import '../properties/prop_test_helper.dart';

// ---------------------------------------------------------------------------
// Mock service that never completes — used to capture the intermediate
// PasswordRecoveryLoading state before any response arrives.
// ---------------------------------------------------------------------------

class _NeverCompletingService extends PasswordRecoveryService {
  _NeverCompletingService() : super(client: null);

  @override
  Future<PasswordResetResult> forgotPassword(String email) =>
      Completer<PasswordResetResult>().future;

  @override
  Future<PasswordResetResult> resetPassword(
          String token, String newPassword) =>
      Completer<PasswordResetResult>().future;

  @override
  Future<PasswordResetResult> changePassword(
          String currentPassword, String newPassword) =>
      Completer<PasswordResetResult>().future;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Generates a valid-looking token (64 hex chars).
String genToken() {
  const hex = '0123456789abcdef';
  return List.generate(64, (_) => hex[rng.nextInt(hex.length)]).join();
}

/// Generates a password that meets basic requirements (12+ chars, mixed).
String genPassword() {
  // Fixed suffix ensures policy compliance regardless of random prefix.
  final prefix = genString(minLen: 4, maxLen: 8);
  return '${prefix}Aa1!secure';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Feature: password-recovery, Property 14: Loading state on form submit
  group('Property 14: Loading state on form submit', () {
    test(
        'forgotPassword: state transitions to PasswordRecoveryLoading '
        'synchronously before async operation completes', () async {
      await forAll<String>(
        numRuns: 100,
        gen: () => '${genString(minLen: 3, maxLen: 10)}@example.com',
        body: (email) async {
          final notifier =
              PasswordRecoveryNotifier(_NeverCompletingService());

          expect(notifier.state, isA<PasswordRecoveryIdle>(),
              reason: 'Initial state must be Idle');

          // Start the async call but do NOT await it — we want to inspect
          // the intermediate state.
          final future = notifier.forgotPassword(email);

          // The state must already be Loading (synchronous transition).
          expect(notifier.state, isA<PasswordRecoveryLoading>(),
              reason:
                  'State must be PasswordRecoveryLoading immediately after '
                  'calling forgotPassword, before the Future resolves');

          // Clean up: cancel the pending future by disposing the notifier.
          notifier.dispose();
          // Ignore the never-completing future.
          future.ignore();
        },
      );
    });

    test(
        'resetPassword: state transitions to PasswordRecoveryLoading '
        'synchronously before async operation completes', () async {
      await forAll2<String, String>(
        numRuns: 100,
        genA: genToken,
        genB: genPassword,
        body: (token, password) async {
          final notifier =
              PasswordRecoveryNotifier(_NeverCompletingService());

          expect(notifier.state, isA<PasswordRecoveryIdle>());

          final future = notifier.resetPassword(token, password);

          expect(notifier.state, isA<PasswordRecoveryLoading>(),
              reason:
                  'State must be PasswordRecoveryLoading immediately after '
                  'calling resetPassword, before the Future resolves');

          notifier.dispose();
          future.ignore();
        },
      );
    });

    test(
        'changePassword: state transitions to PasswordRecoveryLoading '
        'synchronously before async operation completes', () async {
      await forAll2<String, String>(
        numRuns: 100,
        genA: genPassword,
        genB: genPassword,
        body: (currentPw, newPw) async {
          final notifier =
              PasswordRecoveryNotifier(_NeverCompletingService());

          expect(notifier.state, isA<PasswordRecoveryIdle>());

          final future = notifier.changePassword(currentPw, newPw);

          expect(notifier.state, isA<PasswordRecoveryLoading>(),
              reason:
                  'State must be PasswordRecoveryLoading immediately after '
                  'calling changePassword, before the Future resolves');

          notifier.dispose();
          future.ignore();
        },
      );
    });

    test(
        'Loading state is set regardless of the initial state '
        '(idempotency across multiple calls)', () async {
      await forAll<String>(
        numRuns: 50,
        gen: () => '${genString(minLen: 3, maxLen: 10)}@example.com',
        body: (email) async {
          final notifier =
              PasswordRecoveryNotifier(_NeverCompletingService());

          // Simulate a prior error state.
          // We use reset() to go back to Idle, then call forgotPassword.
          notifier.reset();
          expect(notifier.state, isA<PasswordRecoveryIdle>());

          final future = notifier.forgotPassword(email);

          expect(notifier.state, isA<PasswordRecoveryLoading>());

          notifier.dispose();
          future.ignore();
        },
      );
    });
  });
}
