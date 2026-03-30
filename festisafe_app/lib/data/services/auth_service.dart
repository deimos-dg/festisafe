import 'package:dio/dio.dart';
import '../models/auth_tokens.dart';
import '../models/user.dart';
import '../storage/secure_storage.dart';
import 'api_client.dart';

/// Servicio de autenticación: registro, login, invitado, refresh y logout.
class AuthService {
  final ApiClient _client;
  final SecureStorage _storage;

  AuthService({ApiClient? client, SecureStorage? storage})
      : _client = client ?? ApiClient(),
        _storage = storage ?? SecureStorage();

  /// Registra un nuevo usuario.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    bool isOrganizer = false,
  }) async {
    await _client.dio.post('/auth/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'confirm_password': password,
      if (phone != null) 'phone': phone,
      'is_organizer': isOrganizer,
    });
  }

  /// Inicia sesión y persiste los tokens.
  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final tokens = AuthTokens.fromJson(response.data as Map<String, dynamic>);
    await _storage.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    return tokens;
  }

  /// Canjea un código de 6 dígitos para acceder como invitado.
  Future<Map<String, dynamic>> guestLogin(String code) async {
    final response = await _client.dio.post('/auth/guest-login', data: {'code': code});
    final data = response.data as Map<String, dynamic>;
    await _storage.saveTokens(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      isGuest: true,
    );
    return data;
  }

  /// Convierte la cuenta de invitado en cuenta permanente.
  Future<void> convertGuest({
    required String email,
    required String password,
    String? phone,
  }) async {
    await _client.dio.post('/auth/convert-guest', data: {
      'email': email,
      'password': password,
      if (phone != null) 'phone': phone,
    });
    // Actualizar flag de invitado en storage
    final access = await _storage.getAccessToken();
    final refresh = await _storage.getRefreshToken();
    if (access != null && refresh != null) {
      await _storage.saveTokens(
        accessToken: access,
        refreshToken: refresh,
        isGuest: false,
      );
    }
  }

  /// Cierra sesión y revoca el token.
  Future<void> logout() async {
    try {
      await _client.dio.post('/auth/logout');
    } catch (_) {
      // Ignorar errores de red al cerrar sesión
    } finally {
      await _storage.clearTokens();
    }
  }

  /// Obtiene los datos del usuario autenticado.
  Future<UserModel> getMe() async {
    final response = await _client.dio.get('/users/me');
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Verifica si hay una sesión válida almacenada.
  /// Retorna el [UserModel] si la sesión es válida, o null si no lo es.
  /// Intenta refresh automáticamente si el access_token está expirado (via interceptor).
  Future<UserModel?> validateStoredSession() async {
    final hasTokens = await _storage.hasTokens();
    if (!hasTokens) return null;
    try {
      return await getMe();
    } on DioException {
      return null;
    }
  }
}
