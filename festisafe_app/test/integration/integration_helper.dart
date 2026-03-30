/// Helper compartido para tests de integración contra el backend real.
/// URL: http://festisafe-alb-814303465.us-east-1.elb.amazonaws.com
library;

import 'dart:math';
import 'package:dio/dio.dart';

const String kBaseUrl =
    'http://festisafe-alb-814303465.us-east-1.elb.amazonaws.com/api/v1';

const Duration kTimeout = Duration(seconds: 15);

// Credenciales del usuario de prueba existente en producción
const String kTestEmail = 'dragnyel@hotmail.com';
const String kTestPassword = 'Spidermansuperior98.';
const String kTestEventId = 'e07ffec5-8fc6-4e02-b30a-075812f1e67c';

/// Crea un cliente Dio sin interceptores (para tests directos).
Dio buildDio({String? accessToken}) {
  final dio = Dio(BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: kTimeout,
    receiveTimeout: kTimeout,
    validateStatus: (_) => true, // no lanzar excepción en 4xx/5xx
  ));
  if (accessToken != null) {
    dio.options.headers['Authorization'] = 'Bearer $accessToken';
  }
  return dio;
}

/// Email único para tests que crean usuarios temporales.
String uniqueEmail() {
  final n = Random().nextInt(999999);
  return 'test_integration_$n@festisafe.test';
}

/// Contraseña válida que cumple los requisitos del backend (12+ chars, mayús, minús, dígito, especial).
const String kValidPassword = 'Integration@2026';
