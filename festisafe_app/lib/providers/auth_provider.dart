import 'package:dio/dio.dart';
import '../data/models/user.dart';
import '../data/services/auth_service.dart';
import '../data/services/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:state_notifier/state_notifier.dart';

/// Estados posibles de la sesión.
sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);
}

class AuthGuest extends AuthState {
  final UserModel user;
  final String eventId;
  const AuthGuest(this.user, this.eventId);
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

class AuthMustChangePassword extends AuthState {
  final String email;
  const AuthMustChangePassword(this.email);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _service;

  AuthNotifier(this._service) : super(const AuthInitial());

  Future<void> checkSession() async {
    state = const AuthLoading();
    try {
      // validateStoredSession llama getMe() internamente — reutilizamos ese resultado
      final user = await _service.validateStoredSession();
      if (user != null) {
        state = AuthAuthenticated(user);
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> login(String email, String password) async {
    state = const AuthLoading();
    try {
      await _service.login(email: email, password: password);
      final user = await _service.getMe();
      state = AuthAuthenticated(user);
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] as String? ?? 'Error al iniciar sesión';
      if (e.response?.statusCode == 403 &&
          msg == 'Debes cambiar tu contraseña antes de continuar') {
        state = AuthMustChangePassword(email);
      } else {
        state = AuthError(msg);
      }
    } catch (_) {
      state = const AuthError('Error de conexión. Verifica tu internet.');
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    bool isOrganizer = false,
    String? folio,
  }) async {
    state = const AuthLoading();
    try {
      await _service.register(
        name: name,
        email: email,
        password: password,
        phone: phone,
        isOrganizer: isOrganizer,
        folio: folio,
      );
      state = const AuthUnauthenticated();
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] as String? ?? 'Error al registrarse';
      state = AuthError(msg);
    } catch (_) {
      state = const AuthError('Error de conexión. Verifica tu internet.');
    }
  }

  Future<String?> guestLogin(String code) async {
    state = const AuthLoading();
    try {
      final data = await _service.guestLogin(code);
      final user = await _service.getMe();
      final eventId = data['event_id'] as String;
      state = AuthGuest(user, eventId);
      return eventId;
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] as String? ?? 'Código inválido o expirado';
      state = AuthError(msg);
      return null;
    }
  }

  Future<void> convertGuest({
    required String email,
    required String password,
    String? phone,
  }) async {
    try {
      await _service.convertGuest(email: email, password: password, phone: phone);
      final user = await _service.getMe();
      state = AuthAuthenticated(user);
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] as String? ?? 'Error al convertir cuenta';
      state = AuthError(msg);
    }
  }

  /// Limpia el estado de error para que la UI pueda reaccionar a nuevos intentos.
  void clearError() {
    if (state is AuthError) state = const AuthUnauthenticated();
  }

  Future<void> logout() async {
    await NotificationService().unregisterTokenFromBackend();
    await _service.logout();
    state = const AuthUnauthenticated();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(AuthService()),
);
