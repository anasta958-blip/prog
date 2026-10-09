import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/onboarding/organization_onboarding_page.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_api.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_models.dart';

void main() {
  testWidgets('столбец-триггер переноса и дозаказ настраиваются в канбанах', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(tester.view.reset);
    final auth = AuthController(
      const AppConfig(
        apiBaseUrl: 'https://example.test/api/v1',
        environment: 'test',
      ),
      api: _Gateway(),
      tokens: _Tokens(),
    );
    final saved = <OrganizationOnboardingDraft>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrganizationOnboardingPage(
            controller: auth,
            settingsDraft: _draft(),
            onSettingsSave: (draft, {deleteCategoryData = const []}) async {
              saved.add(draft);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Раздел «Внешняя отправка» есть среди вкладок настроек.
    expect(find.text('Внешняя отправка'), findsOneWidget);
    for (final toggle
        in find.bySemanticsLabel('Развернуть канбан').evaluate().toList()) {
      await tester.tap(find.byWidget(toggle.widget));
      await tester.pumpAndSettle();
    }

    // Справочники комплектации и дозаказ есть только у канбана комплектации.
    expect(find.text('Типы объекта'), findsOneWidget);
    expect(find.text('Статусы отгрузки'), findsOneWidget);
    expect(find.byKey(const ValueKey('reorder-from-montage')), findsOneWidget);
    expect(find.byKey(const ValueKey('reorder-from-buy')), findsNothing);
    for (final width in [375.0, 1024.0]) {
      tester.view.physicalSize = Size(width, 2400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final name = find.widgetWithText(TextFormField, 'Столбец 1').first;
      expect(tester.getSize(name).width, greaterThan(100));
    }
    tester.view.physicalSize = const Size(1400, 2400);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('reorder-from-montage')),
    );
    await tester.tap(find.byKey(const ValueKey('reorder-from-montage')));
    await tester.pumpAndSettle();

    final transfer = find.byKey(const ValueKey('transfer-buy'));
    await tester.ensureVisible(transfer);
    await tester.tap(transfer);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Комплектация → Составление').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сохранить изменения').first);
    await tester.pumpAndSettle();
    final sales = saved.last.workflows.first;
    final orders = saved.last.workflows.last;
    expect(sales.columns[1].transferTo?.workflowCode, 'orders');
    expect(sales.columns[1].transferTo?.columnClientId, 'compose');
    expect(orders.columns[1].reorderFrom, isTrue);

    // Снятие специализации удаляет перенос из этого канбана. После
    // сохранения блоки свёрнуты — разворачиваем первый канбан.
    await tester.tap(find.bySemanticsLabel('Развернуть канбан').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('КП').first);
    await tester.tap(find.widgetWithText(FilterChip, 'КП').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить изменения').first);
    await tester.pumpAndSettle();
    expect(saved.last.workflows.first.columns[1].transferTo, isNull);
    auth.dispose();
  });
  testWidgets('вкладка «Внешняя отправка» открывается и сохраняет раздел', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(tester.view.reset);
    final auth = AuthController(
      const AppConfig(
        apiBaseUrl: 'https://example.test/api/v1',
        environment: 'test',
      ),
      api: _Gateway(),
      tokens: _Tokens(),
    )..accessToken = 'access-token';
    final outbound = _Outbound();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrganizationOnboardingPage(
            controller: auth,
            settingsDraft: _draft(),
            outboundGateway: outbound,
            onSettingsSave: (draft, {deleteCategoryData = const []}) async =>
                true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Внешняя отправка'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Внешняя отправка'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Telegram'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('outbound-chat-id-1')),
      '-1001234567890',
    );
    await tester.tap(find.text('Сохранить изменения').first);
    await tester.pumpAndSettle();
    expect(outbound.saved?.chatId, '-1001234567890');
    auth.dispose();
  });
}

OrganizationOnboardingDraft _draft() => OrganizationOnboardingDraft.initial()
  ..workflows.clear()
  ..workflows.addAll([
    WorkflowDraft(
      code: 'sales',
      name: 'Предложения',
      specialization: WorkflowSpecialization.quote,
      columns: [
        WorkflowColumnDraft(
          clientId: 'start',
          name: 'Подготовка',
          color: '#4D8DFF',
          creationActions: [WorkflowCreationAction.quote],
        ),
        WorkflowColumnDraft(clientId: 'buy', name: 'Закупка', color: '#F59E0B'),
      ],
      transitions: [],
    ),
    WorkflowDraft(
      code: 'orders',
      name: 'Комплектация',
      specialization: WorkflowSpecialization.order,
      columns: [
        WorkflowColumnDraft(
          clientId: 'compose',
          name: 'Составление',
          color: '#4D8DFF',
          creationActions: [WorkflowCreationAction.order],
        ),
        WorkflowColumnDraft(
          clientId: 'montage',
          name: 'Монтаж',
          color: '#22C55E',
        ),
      ],
      transitions: [],
    ),
  ]);

/// Сеть в этом тесте не нужна: страница работает с переданным черновиком.
final class _Gateway implements AuthGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _Tokens implements TokenRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

final class _Outbound implements OutboundGateway {
  OutboundSettingsModel? saved;

  @override
  Future<OutboundSettingsModel> getSettings(String accessToken) async =>
      OutboundSettingsModel();

  @override
  Future<OutboundSettingsModel> saveSettings(
    String accessToken,
    OutboundSettingsModel settings,
  ) async => saved = settings.copy();

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
