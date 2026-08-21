import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/app/app.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';

void main() {
  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
  );

  testWidgets('после неудачного восстановления показывает форму входа', (
    tester,
  ) async {
    final controller = AuthController(
      config,
      api: _OfflineAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );

    await tester.pumpWidget(
      SkladKomfortaApp(config: config, authController: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('кнопка смены пароля реагирует на совпадение полей', (
    tester,
  ) async {
    final controller = AuthController(
      config,
      api: _OfflineAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    controller.stage = AuthStage.changePassword;

    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pump();

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'ReliablePass1!');
    await tester.enterText(fields.at(1), 'ReliablePass1!');
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Продолжить'),
    );
    expect(button.onPressed, isNotNull);

    controller.dispose();
  });

  testWidgets('Enter в пароле отправляет форму входа', (tester) async {
    final api = _RecordingAuthGateway();
    final controller = AuthController(
      config,
      api: api,
      tokens: _MemoryTokenRepository(),
    );
    controller.stage = AuthStage.login;

    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pump();

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'director');
    await tester.enterText(fields.at(1), 'ReliablePass1!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(api.lastPath, '/auth/login');
    expect(api.lastBody?['login'], 'director');
    final loginField = tester.widget<TextField>(find.byType(TextField).first);
    expect(loginField.enableInteractiveSelection, isTrue);
    expect(loginField.contextMenuBuilder, isNotNull);

    controller.dispose();
  });

  testWidgets('Enter в коде вызывает подтверждение TOTP', (tester) async {
    final api = _RecordingAuthGateway();
    final controller = AuthController(
      config,
      api: api,
      tokens: _MemoryTokenRepository(),
    );
    controller.stage = AuthStage.verifyTotp;
    controller.challengeToken = 'challenge-token';

    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(api.lastPath, '/auth/totp/verify');
    expect(api.lastBody?['code'], '123456');
    expect(controller.stage, AuthStage.organization);

    controller.dispose();
  });

  testWidgets('onboarding использует выбранный семишаговый вариант 2', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final controller = AuthController(
      config,
      api: _OfflineAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    controller.stage = AuthStage.organization;

    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pump();

    expect(find.text('Создание организации'), findsOneWidget);
    expect(find.text('1. Компания'), findsWidgets);
    expect(find.text('Предварительный просмотр'), findsOneWidget);
    expect(find.text('Сохранить и продолжить'), findsOneWidget);

    controller.dispose();
  });
}

/// Тестовый transport без сети: восстановление сессии всегда завершается отказом.
final class _OfflineAuthGateway implements AuthGateway {
  @override
  Future<dynamic> delete(String path, String accessToken) =>
      throw const AuthApiException('offline', 'Нет соединения.');

  @override
  Future<dynamic> get(String path, String accessToken) =>
      throw const AuthApiException('offline', 'Нет соединения.');

  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) => throw const AuthApiException('offline', 'Нет соединения.');

  @override
  void close() {}
}

/// Фиксирует отправку формы и возвращает минимальные валидные ответы Identity.
final class _RecordingAuthGateway implements AuthGateway {
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    lastPath = path;
    lastBody = Map<String, dynamic>.from(body);
    if (path == '/auth/login') {
      return <String, dynamic>{'step': 3, 'challengeToken': 'challenge-token'};
    }
    if (path == '/auth/totp/verify') {
      return <String, dynamic>{
        'tokens': <String, dynamic>{
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
        },
        'recoveryCodes': <String>[],
        'onboardingRequired': true,
      };
    }
    throw AuthApiException('unexpected_request', 'Неожиданный запрос: $path');
  }

  @override
  Future<dynamic> get(String path, String accessToken) =>
      throw const AuthApiException('unexpected_request', 'Неожиданный GET.');

  @override
  Future<dynamic> delete(String path, String accessToken) =>
      throw const AuthApiException('unexpected_request', 'Неожиданный DELETE.');

  @override
  void close() {}
}

/// Изолированное хранилище теста без platform channel secure storage.
final class _MemoryTokenRepository implements TokenRepository {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> readRefreshToken() async => value;

  @override
  Future<void> writeRefreshToken(String? value) async => this.value = value;
}
