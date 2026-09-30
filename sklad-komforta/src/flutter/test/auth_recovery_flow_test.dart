import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';

void main() {
  const config = AppConfig(
    apiBaseUrl: 'https://example.test/api/v1',
    environment: 'test',
  );
  for (final restore in [false, true]) {
    test(
      'employee enters workspace without director settings: restore=$restore',
      () async {
        final api = _Gateway();
        final auth = AuthController(config, api: api, tokens: _Tokens())
          ..accessToken = 'access'
          ..organizationProvisioned = true
          ..stage = AuthStage.recoveryCodes
          ..recoveryCodes = ['test-code'];
        if (restore) {
          await auth.initialize();
        } else {
          await auth.continueAfterRecoveryCodes();
          expect(auth.recoveryCodes, isEmpty);
        }
        expect(auth.stage, AuthStage.ready);
        expect(auth.error, isNull);
        expect(api.paths, ['/onboarding/status', '/identity/sessions']);
        auth.dispose();
      },
    );
  }
  test('failure keeps recovery codes and allows retry', () async {
    final api = _Gateway()..fail = true;
    final auth = AuthController(config, api: api, tokens: _Tokens())
      ..accessToken = 'access'
      ..organizationProvisioned = true
      ..stage = AuthStage.recoveryCodes
      ..recoveryCodes = ['test-code'];
    await auth.continueAfterRecoveryCodes();
    expect(auth.stage, AuthStage.recoveryCodes);
    expect(auth.recoveryCodes, ['test-code']);
    expect(auth.error, 'Нет соединения.');
    expect(auth.busy, isFalse);
    api.fail = false;
    await auth.continueAfterRecoveryCodes();
    expect(auth.stage, AuthStage.ready);
    expect(auth.recoveryCodes, isEmpty);
    auth.dispose();
  });
}

class _Gateway implements AuthGateway {
  final paths = <String>[];
  bool fail = false;
  @override
  Future<dynamic> get(String path, String accessToken) async {
    paths.add(path);
    if (fail) throw const AuthApiException('offline', 'Нет соединения.', 503);
    if (path == '/onboarding/status') return {'isCompleted': true};
    if (path == '/identity/sessions') return <dynamic>[];
    throw StateError('Unexpected access to $path');
  }

  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async => {'accessToken': 'access', 'organizationId': 'organization'};
  @override
  Future<dynamic> delete(String path, String accessToken) async => null;
  @override
  void close() {}
}

class _Tokens implements TokenRepository {
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String? value) async {}
  @override
  Future<void> clear() async {}
}
