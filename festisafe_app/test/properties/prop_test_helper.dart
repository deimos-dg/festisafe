import 'dart:async';
import 'dart:math';

/// Helper de property-based testing sin dependencias externas.
/// Ejecuta [body] con [numRuns] entradas generadas aleatoriamente.

final Random _rng = Random(42); // seed fijo para reproducibilidad

Random get rng => _rng;

/// Ejecuta un test de propiedad con 1 parámetro generado.
/// Soporta body síncrono y asíncrono.
Future<void> forAll<A>({
  int numRuns = 100,
  required A Function() gen,
  required FutureOr<void> Function(A) body,
}) async {
  for (int i = 0; i < numRuns; i++) {
    await body(gen());
  }
}

/// Ejecuta un test de propiedad con 2 parámetros generados.
Future<void> forAll2<A, B>({
  int numRuns = 100,
  required A Function() genA,
  required B Function() genB,
  required FutureOr<void> Function(A, B) body,
}) async {
  for (int i = 0; i < numRuns; i++) {
    await body(genA(), genB());
  }
}

/// Ejecuta un test de propiedad con 3 parámetros generados.
Future<void> forAll3<A, B, C>({
  int numRuns = 100,
  required A Function() genA,
  required B Function() genB,
  required C Function() genC,
  required FutureOr<void> Function(A, B, C) body,
}) async {
  for (int i = 0; i < numRuns; i++) {
    await body(genA(), genB(), genC());
  }
}

// ---------------------------------------------------------------------------
// Generadores de valores aleatorios
// ---------------------------------------------------------------------------

/// Entero en [min, max) (max exclusivo).
int genInt({int min = 0, int max = 100}) =>
    min + _rng.nextInt(max - min);

/// Double en [min, max).
double genDouble({double min = 0.0, double max = 1.0}) =>
    min + _rng.nextDouble() * (max - min);

/// String alfanumérico de longitud aleatoria en [minLen, maxLen].
/// Solo caracteres visibles — sin espacios — para evitar strings vacíos tras trim.
String genString({int minLen = 1, int maxLen = 20}) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final len = minLen + _rng.nextInt((maxLen - minLen + 1).clamp(1, maxLen));
  return List.generate(len, (_) => chars[_rng.nextInt(chars.length)]).join();
}

/// String no vacío (mínimo 1 carácter visible).
String genNonEmptyString({int maxLen = 20}) => genString(minLen: 1, maxLen: maxLen);

/// Bool aleatorio.
bool genBool() => _rng.nextBool();

/// Lista de enteros de longitud aleatoria en [minLen, maxLen].
List<int> genIntList({int minLen = 0, int maxLen = 10, int min = 0, int max = 100}) {
  final len = minLen + _rng.nextInt((maxLen - minLen + 1).clamp(1, maxLen + 1));
  return List.generate(len, (_) => genInt(min: min, max: max));
}

/// Lista de strings de longitud aleatoria.
List<String> genStringList({int minLen = 0, int maxLen = 10}) {
  final len = minLen + _rng.nextInt((maxLen - minLen + 1).clamp(1, maxLen + 1));
  return List.generate(len, (_) => genString());
}

/// Código de invitado de exactamente 6 dígitos.
String genGuestCode() => genInt(min: 0, max: 1000000).toString().padLeft(6, '0');
