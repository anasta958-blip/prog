import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/app/app.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/workspace/workspace_page.dart';

const _config = AppConfig(
  apiBaseUrl: 'https://example.test/api/v1',
  environment: 'test',
);

void main() {
  testWidgets('боковая панель сворачивается до иконок и разворачивается', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final auth = AuthController(
      _config,
      api: _OfflineAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: WorkspacePage(config: _config, authController: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Склад Комфорта'), findsOneWidget);
    expect(find.text('РАБОЧЕЕ ПРОСТРАНСТВО'), findsOneWidget);
    expect(find.text('Каталог товаров'), findsWidgets);
    final expandedWidth = tester
        .getSize(find.byKey(const Key('workspace-sidebar')))
        .width;

    await tester.tap(find.byTooltip('Свернуть панель'));
    // Промежуточные кадры анимации не должны давать переполнения.
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('workspace-sidebar'))).width,
      lessThan(expandedWidth),
    );
    expect(find.text('Склад Комфорта'), findsNothing);
    expect(find.text('РАБОЧЕЕ ПРОСТРАНСТВО'), findsNothing);
    expect(find.text('Соединение защищено'), findsNothing);
    expect(find.byTooltip('Каталог товаров'), findsOneWidget);
    expect(find.byTooltip('Компания'), findsOneWidget);

    // Пункты работают и в свёрнутом виде.
    await tester.tap(find.byTooltip('Компания'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Сотрудники и структура'), findsOneWidget);

    await tester.tap(find.byTooltip('Развернуть панель'));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.text('Склад Комфорта'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('workspace-sidebar'))).width,
      expandedWidth,
    );
    expect(tester.takeException(), isNull);
  });
}

final class _OfflineAuthGateway implements AuthGateway {
  @override
  Future<dynamic> delete(String path, String accessToken) async => null;
  @override
  Future<dynamic> get(String path, String accessToken) async => const [];
  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async => null;
  @override
  void close() {}
}

final class _MemoryTokenRepository implements TokenRepository {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String? value) async {}
}
