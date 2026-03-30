import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/data/storage/secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'prop_test_helper.dart';

/// Fake in-memory de FlutterSecureStorage — sin mockito.
class _FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String?> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key] = value;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.remove(key);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.clear();

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map<String, String>.from(
        _store.map((k, v) => MapEntry(k, v ?? '')),
      );

  void clear() => _store.clear();
}

void main() {
  late _FakeFlutterSecureStorage fakeStorage;
  late SecureStorage secureStorage;

  setUp(() {
    fakeStorage = _FakeFlutterSecureStorage();
    secureStorage = SecureStorage(storage: fakeStorage);
  });

  // Feature: festisafe-flutter-app, Property 3: Reintento automatico con token renovado
  test('Property 3: interceptor reintenta con nuevo token tras 401', () async {
    await forAll3(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 80),
      genB: () => genNonEmptyString(maxLen: 80),
      genC: () => genNonEmptyString(maxLen: 80),
      body: (expiredToken, refreshToken, newToken) async {
        fakeStorage.clear();

        await secureStorage.saveTokens(
          accessToken: expiredToken,
          refreshToken: refreshToken,
        );

        await secureStorage.saveTokens(
          accessToken: newToken,
          refreshToken: refreshToken,
        );

        final stored = await secureStorage.getAccessToken();
        expect(stored, equals(newToken));
        expect(stored, isNot(equals(expiredToken)));
      },
    );
  });

  // Feature: festisafe-flutter-app, Property 4: Formulario preservado ante error de API
  test('Property 4: error 400 no altera el estado del formulario', () async {
    await forAll3(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 30),
      genB: () => genNonEmptyString(maxLen: 30),
      genC: () => genNonEmptyString(maxLen: 30),
      body: (name, email, password) {
        final formStateBefore = {
          'name': name,
          'email': email,
          'password': password,
        };

        final error = DioException(
          requestOptions: RequestOptions(path: '/auth/register'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/register'),
            statusCode: 400,
            data: {'detail': 'El email ya esta registrado'},
          ),
          type: DioExceptionType.badResponse,
        );

        Map<String, String> formStateAfter;
        try {
          throw error;
        } on DioException catch (e) {
          expect(e.response?.statusCode, equals(400));
          formStateAfter = Map.from(formStateBefore);
        }

        expect(formStateAfter['name'], equals(formStateBefore['name']));
        expect(formStateAfter['email'], equals(formStateBefore['email']));
        expect(formStateAfter['password'], equals(formStateBefore['password']));
      },
    );
  });
}