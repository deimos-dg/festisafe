import 'package:dio/dio.dart';
import '../models/password_reset_result.dart';
import 'api_client.dart';

/// Servicio de recuperación de contraseña: forgot, reset y change.
class PasswordRecoveryService {
  final ApiClient _client;

  PasswordRecoveryService({ApiClient? client})
      : _client = client ?? ApiClient();

  /// Solicita el envío de un email de recuperación para [email].
  /// Siempre retorna éxito (el backend es anti-enumeración).
  Future<PasswordResetResult> forgotPassword(String email) async {
    try {
      final response = await _client.dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
      final message = (response.data as Map<String, dynamic>)['message'] as String? ??
          'Si el email existe, recibirás un enlace de recuperación.';
      return PasswordResetResult(success: true, message: message);
    } on DioException catch (e) {
      return PasswordResetResult(
        success: false,
        message: _mapDioError(e),
      );
    }
  }

  /// Restablece la contraseña usando un [token] de un solo uso.
  Future<PasswordResetResult> resetPassword(
    String token,
    String newPassword,
  ) async {
    try {
      final response = await _client.dio.post(
        '/auth/reset-password',
        data: {
          'token': token,
          'new_password': newPassword,
          'confirm_password': newPassword,
        },
      );
      final message = (response.data as Map<String, dynamic>)['message'] as String? ??
          'Contraseña restablecida correctamente.';
      return PasswordResetResult(success: true, message: message);
    } on DioException catch (e) {
      return PasswordResetResult(
        success: false,
        message: _mapDioError(e),
      );
    }
  }

  /// Cambia la contraseña del usuario autenticado (flujo obligatorio).
  Future<PasswordResetResult> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      final response = await _client.dio.post(
        '/auth/change-password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
          'confirm_password': newPassword,
        },
      );
      final message = (response.data as Map<String, dynamic>)['message'] as String? ??
          'Contraseña actualizada correctamente.';
      return PasswordResetResult(success: true, message: message);
    } on DioException catch (e) {
      return PasswordResetResult(
        success: false,
        message: _mapDioError(e),
      );
    }
  }

  /// Mapea un [DioException] a un mensaje legible en español.
  String _mapDioError(DioException e) {
    // Errores de red / sin conexión
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Error de conexión. Verifica tu internet.';
    }

    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    // Intentar extraer el mensaje del cuerpo de la respuesta
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }

    switch (statusCode) {
      case 400:
        return 'Token inválido o expirado.';
      case 401:
        return 'No autorizado. Inicia sesión de nuevo.';
      case 422:
        return 'La contraseña no cumple los requisitos de seguridad.';
      case 429:
        return 'Demasiadas solicitudes. Inténtalo más tarde.';
      case 503:
        return 'No se pudo enviar el email de recuperación. Inténtalo más tarde.';
      default:
        return 'Ocurrió un error inesperado. Inténtalo de nuevo.';
    }
  }
}
