import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festisafe/data/storage/secure_storage.dart';

import 'prop_test_helper.dart';

/// Implementación fake de FlutterSecureStorage en memoria — sin mockito.
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
  }) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

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

  // Feature: festisafe-flutter-app, Property 1: Tokens almacenados tras login exitoso
  test('Property 1: tokens no vacíos se persisten tras saveTokens', () async {
    await forAll2(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 100),
      genB: () => genNonEmptyString(maxLen: 100),
      body: (accessToken, refreshToken) async {
        fakeStorage.clear();

        await secureStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );

        final storedAccess = await secureStorage.getAccessToken();
        final storedRefresh = await secureStorage.getRefreshToken();

        expect(storedAccess, isNotEmpty);
        expect(storedRefresh, isNotEmpty);
        expect(storedAccess, equals(accessToken));
        expect(storedRefresh, equals(refreshToken));
      },
    );
  });

  // Feature: festisafe-flutter-app, Property 2: Token_Store vacío tras logout
  test('Property 2: clearTokens elimina todos los tokens', () async {
    await forAll2(
      numRuns: 100,
      genA: () => genNonEmptyString(maxLen: 100),
      genB: () => genNonEmptyString(maxLen: 100),
      body: (accessToken, refreshToken) async {
        fakeStorage.clear();

        await secureStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
        await secureStorage.clearTokens();

        final storedAccess = await secureStorage.getAccessToken();
        final storedRefresh = await secureStorage.getRefreshToken();

        expect(storedAccess, isNull);
        expect(storedRefresh, isNull);
      },
    );
  });
}
