import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper de [FlutterSecureStorage] para gestionar tokens JWT.
class SecureStorage {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _isGuestKey = 'is_guest';

  final FlutterSecureStorage _storage;

  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Persiste el par de tokens en almacenamiento seguro.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    bool isGuest = false,
  }) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: accessToken),
      _storage.write(key: _refreshKey, value: refreshToken),
      _storage.write(key: _isGuestKey, value: isGuest.toString()),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessKey);

  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  Future<bool> getIsGuest() async {
    final val = await _storage.read(key: _isGuestKey);
    return val == 'true';
  }

  /// Elimina todos los tokens del almacenamiento seguro.
  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _isGuestKey),
    ]);
  }

  /// Devuelve true si existe un access_token almacenado.
  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
