// Widget tests for PasswordResetScreen
// Feature: password-recovery

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:festisafe/data/models/auth_tokens.dart';
import 'package:festisafe/data/models/password_reset_result.dart';
import 'package:festisafe/data/models/user.dart';
import 'package:festisafe/data/services/auth_service.dart';
import 'package:festisafe/data/services/password_recovery_service.dart';
import 'package:festisafe/presentation/screens/password_reset_screen.dart';
import 'package:festisafe/providers/auth_provider.dart';
import 'package:festisafe/providers/password_recovery_provider.dart';

// ---------------------------------------------------------------------------
// Mock services
// ---------------------------------------------------------------------------

/// Service that never completes — used to capture the loading state.
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

/// Service that always returns success.
class _SuccessService extends PasswordRecoveryService {
  _SuccessService() : super(client: null);

  @override
  Future<PasswordResetResult> forgotPassword(String email) async =>
      const PasswordResetResult(success: true, message: 'OK');

  @override
  Future<PasswordResetResult> resetPassword(
          String token, String newPassword) async =>
      const PasswordResetResult(success: true, message: 'Contraseña restablecida');

  @override
  Future<PasswordResetResult> changePassword(
          String currentPassword, String newPassword) async =>
      const PasswordResetResult(success: true, message: 'Contraseña cambiada');
}

/// AuthService mock that records login calls and returns a fake user.
class _MockAuthService extends AuthService {
  int loginCallCount = 0;
  String? lastLoginEmail;
  String? lastLoginPassword;

  _MockAuthService() : super(client: null, storage: null);

  @override
  Future<AuthTokens> login({required String email, required String password}) async {
    loginCallCount++;
    lastLoginEmail = email;
    lastLoginPassword = password;
    // Return a minimal AuthTokens — AuthNotifier calls getMe() after login
    return const AuthTokens(accessToken: 'fake-access', refreshToken: 'fake-refresh');
  }

  @override
  Future<UserModel> getMe() async {
    return const UserModel(
      id: 'test-id',
      name: 'Test User',
      email: 'test@example.com',
      role: 'user',
    );
  }
}

// ---------------------------------------------------------------------------
// Valid test inputs
// ---------------------------------------------------------------------------

// 64-char token (must be a runtime string — Dart doesn't support 'a' * 64 as const)
final _validToken = 'a' * 64;
const _validPassword = 'ValidPass1!secure'; // 12+ chars, mixed

// ---------------------------------------------------------------------------
// Widget builders
// ---------------------------------------------------------------------------

/// Builds PasswordResetScreen in resetWithToken mode with a GoRouter that
/// records navigation events.
Widget _buildResetWithTokenScreen({
  required PasswordRecoveryService service,
  String? token,
  List<String>? navigatedRoutes,
}) {
  final resolvedToken = token ?? ('a' * 64);
  final notifier = PasswordRecoveryNotifier(service);

  final router = GoRouter(
    initialLocation: '/reset-password',
    routes: [
      GoRoute(
        path: '/reset-password',
        builder: (_, __) => PasswordResetScreen(
          mode: PasswordResetMode.resetWithToken,
          token: resolvedToken,
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) {
          navigatedRoutes?.add('/login');
          return const Scaffold(body: Text('Login Screen'));
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      passwordRecoveryProvider.overrideWith((_) => notifier),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Builds PasswordResetScreen in changeObligatory mode with a GoRouter that
/// records navigation events.
Widget _buildChangeObligatoryScreen({
  required PasswordRecoveryService service,
  AuthService? authService,
  String email = 'test@example.com',
  List<String>? navigatedRoutes,
}) {
  final recoveryNotifier = PasswordRecoveryNotifier(service);
  final authNotifier = AuthNotifier(authService ?? _MockAuthService());

  final router = GoRouter(
    initialLocation: '/change-password',
    routes: [
      GoRoute(
        path: '/change-password',
        builder: (_, __) => PasswordResetScreen(
          mode: PasswordResetMode.changeObligatory,
          email: email,
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) {
          navigatedRoutes?.add('/home');
          return const Scaffold(body: Text('Home Screen'));
        },
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) {
          navigatedRoutes?.add('/login');
          return const Scaffold(body: Text('Login Screen'));
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      passwordRecoveryProvider.overrideWith((_) => recoveryNotifier),
      authProvider.overrideWith((_) => authNotifier),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Feature: password-recovery, Requirement 6.1
  group('Test 1: resetWithToken mode shows required fields', () {
    testWidgets(
      'shows token field, new password field, confirm password field, and submit button',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildResetWithTokenScreen(service: _NeverCompletingService()),
        );
        await tester.pumpAndSettle();

        // Token field must be present
        expect(
          find.widgetWithText(TextFormField, 'Token de recuperación'),
          findsOneWidget,
          reason: 'Token de recuperación field must be present in resetWithToken mode',
        );

        // New password field must be present
        expect(
          find.widgetWithText(TextFormField, 'Nueva contraseña'),
          findsOneWidget,
          reason: 'Nueva contraseña field must be present',
        );

        // Confirm password field must be present
        expect(
          find.widgetWithText(TextFormField, 'Confirmar nueva contraseña'),
          findsOneWidget,
          reason: 'Confirmar nueva contraseña field must be present',
        );

        // Submit button must be present
        expect(
          find.widgetWithText(FilledButton, 'Restablecer contraseña'),
          findsOneWidget,
          reason: 'Submit button must be present in resetWithToken mode',
        );

        // Current password field must NOT be present in this mode
        expect(
          find.widgetWithText(TextFormField, 'Contraseña actual'),
          findsNothing,
          reason: 'Contraseña actual field must NOT be present in resetWithToken mode',
        );
      },
    );
  });

  // Feature: password-recovery, Requirement 7.2
  group('Test 2: changeObligatory mode shows required fields', () {
    testWidgets(
      'shows current password field, new password field, confirm password field, submit button — no token field',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildChangeObligatoryScreen(service: _NeverCompletingService()),
        );
        await tester.pumpAndSettle();

        // Current password field must be present
        expect(
          find.widgetWithText(TextFormField, 'Contraseña actual'),
          findsOneWidget,
          reason: 'Contraseña actual field must be present in changeObligatory mode',
        );

        // New password field must be present
        expect(
          find.widgetWithText(TextFormField, 'Nueva contraseña'),
          findsOneWidget,
          reason: 'Nueva contraseña field must be present',
        );

        // Confirm password field must be present
        expect(
          find.widgetWithText(TextFormField, 'Confirmar nueva contraseña'),
          findsOneWidget,
          reason: 'Confirmar nueva contraseña field must be present',
        );

        // Submit button must be present
        expect(
          find.widgetWithText(FilledButton, 'Cambiar contraseña'),
          findsOneWidget,
          reason: 'Submit button must be present in changeObligatory mode',
        );

        // Token field must NOT be present in this mode
        expect(
          find.widgetWithText(TextFormField, 'Token de recuperación'),
          findsNothing,
          reason: 'Token de recuperación field must NOT be present in changeObligatory mode',
        );
      },
    );
  });

  // Feature: password-recovery, Property 14
  group('Test 3: Loading state when submit is tapped with valid inputs', () {
    testWidgets(
      'state transitions to PasswordRecoveryLoading after tapping submit in resetWithToken mode',
      (WidgetTester tester) async {
        final service = _NeverCompletingService();
        final notifier = PasswordRecoveryNotifier(service);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              passwordRecoveryProvider.overrideWith((_) => notifier),
            ],
            child: MaterialApp(
              home: PasswordResetScreen(
                mode: PasswordResetMode.resetWithToken,
                token: _validToken,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Enter matching valid passwords
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nueva contraseña'),
          _validPassword,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirmar nueva contraseña'),
          _validPassword,
        );

        // Tap submit
        await tester.tap(find.widgetWithText(FilledButton, 'Restablecer contraseña'));
        // pump once — do NOT settle, service never completes
        await tester.pump();

        // State must be loading
        expect(
          notifier.state,
          isA<PasswordRecoveryLoading>(),
          reason: 'Provider state must be PasswordRecoveryLoading after submit',
        );

        // The submit button must be disabled (shows CircularProgressIndicator)
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: 'CircularProgressIndicator must be shown while loading',
        );
      },
    );

    testWidgets(
      'state transitions to PasswordRecoveryLoading after tapping submit in changeObligatory mode',
      (WidgetTester tester) async {
        final service = _NeverCompletingService();
        final notifier = PasswordRecoveryNotifier(service);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              passwordRecoveryProvider.overrideWith((_) => notifier),
            ],
            child: MaterialApp(
              home: PasswordResetScreen(
                mode: PasswordResetMode.changeObligatory,
                email: 'test@example.com',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Enter current password and matching new passwords
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Contraseña actual'),
          'OldPass1!secure',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nueva contraseña'),
          _validPassword,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirmar nueva contraseña'),
          _validPassword,
        );

        // Tap submit
        await tester.tap(find.widgetWithText(FilledButton, 'Cambiar contraseña'));
        await tester.pump();

        expect(
          notifier.state,
          isA<PasswordRecoveryLoading>(),
          reason: 'Provider state must be PasswordRecoveryLoading after submit in changeObligatory mode',
        );
      },
    );
  });

  // Feature: password-recovery, Requirement 6.3
  group('Test 4: Navigation to /login on successful reset', () {
    testWidgets(
      'navigates to /login after successful resetPassword',
      (WidgetTester tester) async {
        final navigatedRoutes = <String>[];

        await tester.pumpWidget(
          _buildResetWithTokenScreen(
            service: _SuccessService(),
            token: _validToken,
            navigatedRoutes: navigatedRoutes,
          ),
        );
        await tester.pumpAndSettle();

        // Enter matching valid passwords
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nueva contraseña'),
          _validPassword,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirmar nueva contraseña'),
          _validPassword,
        );

        // Tap submit and wait for navigation
        await tester.tap(find.widgetWithText(FilledButton, 'Restablecer contraseña'));
        await tester.pumpAndSettle();

        // Should have navigated to /login
        expect(
          find.text('Login Screen'),
          findsOneWidget,
          reason: 'Should navigate to /login after successful reset',
        );
      },
    );
  });

  // Feature: password-recovery, Requirement 7.3
  group('Test 5: Auto-login and navigation to /home after obligatory change', () {
    testWidgets(
      'calls authProvider.login() and navigates to /home after successful changePassword',
      (WidgetTester tester) async {
        final mockAuthService = _MockAuthService();
        final navigatedRoutes = <String>[];

        await tester.pumpWidget(
          _buildChangeObligatoryScreen(
            service: _SuccessService(),
            authService: mockAuthService,
            email: 'test@example.com',
            navigatedRoutes: navigatedRoutes,
          ),
        );
        await tester.pumpAndSettle();

        // Enter current password and matching new passwords
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Contraseña actual'),
          'OldPass1!secure',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nueva contraseña'),
          _validPassword,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirmar nueva contraseña'),
          _validPassword,
        );

        // Tap submit and wait for navigation
        await tester.tap(find.widgetWithText(FilledButton, 'Cambiar contraseña'));
        await tester.pumpAndSettle();

        // authService.login() must have been called with the correct email
        expect(
          mockAuthService.loginCallCount,
          equals(1),
          reason: 'authService.login() must be called once for auto-login',
        );
        expect(
          mockAuthService.lastLoginEmail,
          equals('test@example.com'),
          reason: 'auto-login must use the email passed to PasswordResetScreen',
        );
        expect(
          mockAuthService.lastLoginPassword,
          equals(_validPassword),
          reason: 'auto-login must use the new password',
        );

        // Should have navigated to /home
        expect(
          find.text('Home Screen'),
          findsOneWidget,
          reason: 'Should navigate to /home after successful obligatory change',
        );
      },
    );
  });
}
