import 'dart:async';
import 'package:dio/dio.dart';
import '../../core/constants.dart';
import '../storage/secure_storage.dart';

/// Cliente HTTP centralizado con interceptores JWT y refresh automático.
class ApiClient {
  late final Dio _dio;
  final SecureStorage _storage;

  /// Expone el [Dio] subyacente para uso en servicios.
  Dio get dio => _dio;

  ApiClient({SecureStorage? storage})
      : _storage = storage ?? SecureStorage() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(_AuthInterceptor(_storage, _dio));
  }
}

/// Interceptor que adjunta el Bearer token y gestiona el refresh automático.
class _AuthInterceptor extends Interceptor {
  final SecureStorage _storage;
  final Dio _dio;
  bool _isRefreshing = false;
  // Completer compartido para serializar múltiples 401 simultáneos
  Completer<String?>? _refreshCompleter;

  _AuthInterceptor(this._storage, this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Solo intentar refresh ante 401
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Si ya hay un refresh en curso, esperar su resultado
    if (_isRefreshing) {
      final newToken = await _refreshCompleter!.future;
      if (newToken != null) {
        final opts = err.requestOptions;
        opts.headers['Authorization'] = 'Bearer $newToken';
        try {
          handler.resolve(await _dio.fetch(opts));
        } catch (e) {
          handler.next(err);
        }
      } else {
        handler.next(err);
      }
      return;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null) {
        await _storage.clearTokens();
        _refreshCompleter!.complete(null);
        handler.next(err);
        return;
      }

      // Llamada directa sin interceptor para evitar bucle
      // Timeout explícito para no colgar si el servidor no responde
      final refreshDio = Dio(BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final response = await refreshDio.post(
        '/auth/refresh',
        options: Options(headers: {'Authorization': 'Bearer $refreshToken'}),
      );

      final newAccess = response.data['access_token'] as String;
      final newRefresh = response.data['refresh_token'] as String;
      final isGuest = await _storage.getIsGuest();

      await _storage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
        isGuest: isGuest,
      );

      _refreshCompleter!.complete(newAccess);

      // Reintentar la petición original con el nuevo token
      final opts = err.requestOptions;
      opts.headers['Authorization'] = 'Bearer $newAccess';
      final retryResponse = await _dio.fetch(opts);
      handler.resolve(retryResponse);
    } catch (_) {
      // Refresh falló — limpiar tokens y dejar pasar el error
      await _storage.clearTokens();
      _refreshCompleter!.complete(null);
      handler.next(err);
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }
}
