import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/reorderable_token_wrap.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/app/app.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_api.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_page.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_field_registry.dart';

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

  test('истёкший access token обновляется перед повтором запроса', () async {
    final api = _RefreshingAuthGateway();
    final tokens = _MemoryTokenRepository()..value = 'refresh-token';
    final controller = AuthController(config, api: api, tokens: tokens)
      ..accessToken = 'expired-access-token'
      ..stage = AuthStage.ready;

    await controller.loadSessions();

    expect(api.sessionRequestTokens, [
      'expired-access-token',
      'renewed-access-token',
    ]);
    expect(controller.accessToken, 'renewed-access-token');
    expect(tokens.value, 'rotated-refresh-token');

    controller.dispose();
  });

  test('параллельные запросы используют одну ротацию refresh-токена', () async {
    final api = _RefreshingAuthGateway(
      refreshDelay: const Duration(milliseconds: 20),
    );
    final tokens = _MemoryTokenRepository()..value = 'refresh-token';
    final controller = AuthController(config, api: api, tokens: tokens)
      ..accessToken = 'expired-access-token'
      ..stage = AuthStage.ready;

    await Future.wait([
      controller.loadSessions(),
      controller.loadSessions(),
      controller.loadSessions(),
    ]);

    expect(api.refreshRequests, 1);
    expect(controller.stage, AuthStage.ready);
    expect(controller.accessToken, 'renewed-access-token');
    expect(tokens.value, 'rotated-refresh-token');

    controller.dispose();
  });

  test('сетевая ошибка при запуске не удаляет refresh-токен', () async {
    final tokens = _MemoryTokenRepository()..value = 'refresh-token';
    final controller = AuthController(
      config,
      api: _OfflineAuthGateway(),
      tokens: tokens,
    );

    await controller.initialize();

    expect(controller.stage, AuthStage.login);
    expect(tokens.value, 'refresh-token');

    controller.dispose();
  });

  test(
    'недействительная refresh-сессия возвращает пользователя на вход',
    () async {
      final api = _RefreshingAuthGateway(refreshFails: true);
      final tokens = _MemoryTokenRepository()..value = 'invalid-refresh-token';
      final controller = AuthController(config, api: api, tokens: tokens)
        ..accessToken = 'expired-access-token'
        ..stage = AuthStage.ready;

      await controller.revokeOtherSessions();

      expect(controller.stage, AuthStage.login);
      expect(controller.accessToken, isNull);
      expect(tokens.value, isNull);
      expect(controller.error, 'Сессия истекла. Войдите снова.');

      controller.dispose();
    },
  );

  testWidgets('индикатор мастера совпадает с порядком десяти шагов', (
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
    expect(find.text('Предварительный просмотр'), findsNothing);
    expect(find.text('Сохранить и продолжить'), findsOneWidget);
    expect(find.text('4. Справочники'), findsOneWidget);
    expect(find.text('6. Правила и расчёты'), findsOneWidget);
    expect(find.text('7. Зависимости'), findsOneWidget);

    for (final scale in [1.0, 1.3]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final width in [1050.0, 1205.0, 1366.0, 1920.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        final first = tester.getCenter(
          find.byKey(const ValueKey('onboarding-step-1')),
        );
        for (var step = 2; step <= 10; step++) {
          final circle = find.byKey(ValueKey('onboarding-step-$step'));
          expect(tester.getCenter(circle).dy, closeTo(first.dy, 0.01));
        }
        expect(tester.takeException(), isNull);
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.view.physicalSize = const Size(600, 1000);
    await tester.pumpAndSettle();
    expect(find.text('1 из 10 · Компания'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('список типа компании открывается под полем', (tester) async {
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
    await tester.pumpAndSettle();

    final dropdown = find.byType(AppSelectField<String>).first;
    final fieldBounds = tester.getRect(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    final menuItemBounds = tester.getRect(
      find.widgetWithText(MenuItemButton, 'ИП'),
    );
    expect(menuItemBounds.top, greaterThanOrEqualTo(fieldBounds.bottom));

    controller.dispose();
  });

  testWidgets('шестой шаг открывает правила и фиксированный денежный порядок', (
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
    controller.onboardingDraft = OrganizationOnboardingDraft.initial()
      ..currentStep = 6;

    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('6. Правила и расчёты'), findsWidgets);
    expect(find.text('Денежные конвейеры'), findsOneWidget);
    expect(find.textContaining('базовая цена → ручная цена'), findsOneWidget);
    expect(find.text('Добавить правило'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('правило не предлагает результат занятого конвейером поля', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final controller = AuthController(
      config,
      api: _OfflineAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    controller.stage = AuthStage.organization;
    final draft = OrganizationOnboardingDraft.initial()..currentStep = 6;
    controller.onboardingDraft = draft;
    draft.categories.add(
      CatalogCategoryDraft(
        clientId: 'equipment',
        name: 'Оборудование',
        sections: [],
        fields: [
          for (final code in [
            'price',
            'pipeline_total',
            'rule_total',
            'free_total',
          ])
            CatalogFieldDraft(
              fieldCode: code,
              label: code,
              fieldType: 'money',
              isVisible: true,
              isRequired: false,
            ),
        ],
      ),
    );
    draft.moneyPipelines.add(
      MoneyPipelineDraft(
        categoryClientId: 'equipment',
        basePriceFieldCode: 'price',
        resultFieldCode: 'pipeline_total',
      ),
    );
    draft.rules.add(
      CalculationRuleDraft(
        clientId: 'r',
        name: 'Копирование',
        categoryClientId: 'equipment',
        eventType: 'row_calculation',
        isEnabled: true,
        actions: [
          RuleActionDraft(
            actionType: 'set_field',
            targetFieldCode: 'rule_total',
            sourceFieldCode: 'price',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Копирование').first);
    await tester.tap(find.bySemanticsLabel('Развернуть блок').last);
    await tester.pumpAndSettle();
    final destination = tester.widget<AppSelectField<String>>(
      find.byWidgetPredicate(
        (w) => w is AppSelectField<String> && w.label == 'Изменить поле',
      ),
    );
    expect(
      destination.options.map((o) => o.value),
      containsAll(['price', 'rule_total', 'free_total']),
    );
    expect(
      destination.options.map((o) => o.value),
      isNot(contains('pipeline_total')),
    );
    final source = tester.widget<AppSelectField<String>>(
      find.byWidgetPredicate(
        (w) => w is AppSelectField<String> && w.label == 'Взять значение из',
      ),
    );
    expect(source.options.map((o) => o.value), contains('pipeline_total'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('компоненты формулы меняют порядок без пересоздания', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.reset);
    final controller = AuthController(
      config,
      api: _OfflineAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    final formula = FormulaDraft(
      tokens: [
        FormulaTokenDraft(tokenType: 'constant', constantValue: 10),
        FormulaTokenDraft(tokenType: 'operator', operator: 'subtract'),
        FormulaTokenDraft(tokenType: 'constant', constantValue: 2),
      ],
    );
    controller.stage = AuthStage.organization;
    controller.onboardingDraft = OrganizationOnboardingDraft.initial()
      ..currentStep = 6;
    controller.onboardingDraft!.categories.add(
      CatalogCategoryDraft(
        clientId: 'equipment',
        name: 'Оборудование',
        sections: [],
        fields: [
          CatalogFieldDraft(
            fieldCode: 'custom_total',
            label: 'Расчёт',
            fieldType: 'calculated_money',
            isVisible: true,
            isRequired: false,
          ),
        ],
      ),
    );
    controller.onboardingDraft!.rules.add(
      CalculationRuleDraft(
        clientId: 'formula-test',
        name: 'Формула для проверки',
        categoryClientId: 'equipment',
        eventType: 'row_calculation',
        isEnabled: true,
        conditions: [],
        actions: [
          RuleActionDraft(
            actionType: 'calculate_field',
            targetFieldCode: 'custom_total',
            formula: formula,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Формула для проверки').first);
    await tester.tap(find.bySemanticsLabel('Развернуть блок').last);
    await tester.pumpAndSettle();
    final list = find.byType(ReorderableTokenWrap);
    expect(list, findsOneWidget);
    final handles = find.descendant(
      of: list,
      matching: find.byIcon(Icons.drag_indicator),
    );
    await tester.ensureVisible(handles.first);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(handles.last));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    final ten = find.descendant(of: list, matching: find.text('10'));
    final two = find.descendant(of: list, matching: find.text('2'));
    expect(tester.getCenter(ten).dx, greaterThan(tester.getCenter(two).dx));
    await tester.tap(
      find
          .descendant(
            of: list,
            matching: find.byTooltip('Удалить компонент формулы'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(ten, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('настроенный канбан сворачивается без показа технического кода', (
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
    controller.onboardingDraft = OrganizationOnboardingDraft.initial()
      ..currentStep = 2
      ..workflows.add(
        WorkflowDraft(
          code: 'workflow_1',
          name: 'Коммерческие предложения',
          columns: [],
          transitions: [],
        ),
      );

    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Название канбана'), findsNothing);
    expect(find.text('Код'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Развернуть канбан'));
    await tester.pumpAndSettle();
    expect(find.text('Название канбана'), findsOneWidget);
    expect(find.text('Тип канбана'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'КП'));
    await tester.pumpAndSettle();
    expect(
      controller.onboardingDraft!.workflows.single.specialization.apiValue,
      'quote',
    );

    await tester.tap(find.widgetWithText(FilterChip, 'КП'));
    await tester.pumpAndSettle();
    expect(
      controller.onboardingDraft!.workflows.single.specialization.apiValue,
      isNull,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'ПКП'));
    await tester.pumpAndSettle();
    expect(
      controller.onboardingDraft!.workflows.single.specialization.apiValue,
      'prequote',
    );

    await tester.tap(find.widgetWithText(FilterChip, 'КП + ПКП'));
    await tester.pumpAndSettle();
    expect(
      controller.onboardingDraft!.workflows.single.specialization.apiValue,
      'quote_and_prequote',
    );

    await tester.tap(find.bySemanticsLabel('Свернуть канбан'));
    await tester.pumpAndSettle();
    expect(find.text('Название канбана'), findsNothing);

    controller.dispose();
  });

  testWidgets(
    'настроенная категория каталога сворачивается без потери данных',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);
      final controller = AuthController(
        config,
        api: _OfflineAuthGateway(),
        tokens: _MemoryTokenRepository(),
      );
      final category = CatalogCategoryDraft(
        clientId: 'equipment',
        name: 'Оборудование',
        sections: [
          CatalogSectionDraft(
            name: 'Вентиляция',
            groups: [CatalogGroupDraft('Приточные установки')],
          ),
        ],
        fields: [],
      );
      controller.stage = AuthStage.organization;
      controller.onboardingDraft = OrganizationOnboardingDraft.initial()
        ..currentStep = 3
        ..categories.add(category);

      await tester.pumpWidget(
        SkladKomfortaApp(
          config: config,
          authController: controller,
          initializeAuthController: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Категория'), findsNothing);
      expect(
        category.sections.single.groups.single.name,
        'Приточные установки',
      );

      await tester.tap(find.bySemanticsLabel('Развернуть категорию'));
      await tester.pumpAndSettle();
      expect(find.text('Категория'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Развернуть раздел'));
      await tester.pumpAndSettle();
      expect(find.text('Название раздела'), findsOneWidget);
      expect(find.text('Группа'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Свернуть раздел'));
      await tester.pumpAndSettle();
      expect(find.text('Название раздела'), findsNothing);
      expect(
        category.sections.single.groups.single.name,
        'Приточные установки',
      );

      controller.dispose();
    },
  );

  testWidgets('поля связывают категорию с конкретным канбаном', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1100);
    addTearDown(tester.view.reset);
    final controller = AuthController(
      config,
      api: _OfflineAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    final category = CatalogCategoryDraft(
      clientId: 'equipment',
      name: 'Оборудование',
      sections: [],
      fields: [
        CatalogFieldDraft(fieldCode: 'name', isVisible: true, isRequired: true),
      ],
    );
    final workflow = WorkflowDraft(
      code: 'quote',
      name: 'Коммерческие предложения',
      columns: [],
      transitions: [],
    );
    controller.stage = AuthStage.organization;
    controller.onboardingDraft = OrganizationOnboardingDraft.initial()
      ..currentStep = 5
      ..categories.add(category)
      ..workflows.add(workflow);

    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Поля карточек категорий'), findsOneWidget);
    expect(find.text('Поля в канбанах'), findsOneWidget);
    expect(find.bySemanticsLabel('Развернуть поля категории'), findsOneWidget);
    expect(find.bySemanticsLabel('Развернуть поля канбана'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Развернуть поля категории'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Системное поле нельзя удалить'), findsNWidgets(5));

    final addFieldButton = find.text('Добавить поле');
    await Scrollable.ensureVisible(
      tester.element(addFieldButton),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: addFieldButton,
        matching: find.byType(PopupMenuButton<OnboardingFieldDefinition>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Число').last);
    await tester.pumpAndSettle();

    final customField = category.fields.last;
    expect(customField.fieldCode, startsWith('custom_'));
    expect(customField.fieldType, 'number');
    expect(customField.label, isEmpty);
    expect(find.byTooltip('Удалить'), findsOneWidget);

    final workflowFieldsToggle = find.bySemanticsLabel(
      'Развернуть поля канбана',
    );
    await Scrollable.ensureVisible(
      tester.element(workflowFieldsToggle),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(workflowFieldsToggle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('Использовать категорию в этом канбане'),
    );
    // Нажатие на строку категории ставит выбор, но не разворачивает её:
    // невыбранная категория была свёрнута и такой остаётся.
    const hint = 'Использовать категорию в этом канбане';
    const fieldsTitle = 'Поля на карточке';
    const expandLabel = 'Развернуть поля категории в канбане';
    const collapseLabel = 'Свернуть поля категории в канбане';
    await tester.tap(find.text(hint));
    await tester.pumpAndSettle();

    expect(workflow.categories.single.categoryClientId, 'equipment');
    expect(workflow.categories.single.fieldCodes, [
      'name',
      'marking',
      'quantity',
      'unit',
      'base_price',
      customField.fieldCode,
    ]);
    expect(find.text(fieldsTitle), findsNothing);

    // Разворачивается только стрелкой.
    await tester.tap(find.bySemanticsLabel(expandLabel));
    await tester.pumpAndSettle();
    expect(find.text(fieldsTitle), findsOneWidget);
    expect(find.text('Расчётное поле'), findsNothing);

    // Снятие выбора не сворачивает блок: он остаётся раскрытым с подсказкой.
    await tester.tap(find.text(hint));
    await tester.pumpAndSettle();
    expect(workflow.categories, isEmpty);
    expect(find.bySemanticsLabel(collapseLabel), findsOneWidget);
    expect(
      find.textContaining('Категория не используется в этом канбане'),
      findsOneWidget,
    );
    await tester.tap(find.text(hint));
    await tester.pumpAndSettle();
    expect(workflow.categories, hasLength(1));
    expect(find.text(fieldsTitle), findsOneWidget);

    // Стрелка сворачивает поля без снятия выбора.
    await tester.tap(find.bySemanticsLabel(collapseLabel));
    await tester.pumpAndSettle();
    expect(find.text(fieldsTitle), findsNothing);
    expect(workflow.categories, hasLength(1));

    final categoryFieldsToggle = find.bySemanticsLabel(
      'Свернуть поля категории',
    );
    await Scrollable.ensureVisible(
      tester.element(categoryFieldsToggle),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(categoryFieldsToggle);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Развернуть поля категории'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('код нового справочника генерируется и не показывается', (
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
    controller.onboardingDraft = OrganizationOnboardingDraft.initial()
      ..currentStep = 4
      ..dictionaries.add(
        DictionaryDraft(code: 'dictionary_2', name: 'Поставщики', items: []),
      );

    await tester.pumpWidget(
      SkladKomfortaApp(
        config: config,
        authController: controller,
        initializeAuthController: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Код'), findsNothing);
    await tester.tap(find.text('Добавить справочник'));
    await tester.pumpAndSettle();

    expect(controller.onboardingDraft!.dictionaries.last.code, 'dictionary_1');
    expect(find.text('Код'), findsNothing);

    controller.dispose();
  });

  testWidgets('каталог использует карточный вариант и постоянный редактор', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final auth = AuthController(
      config,
      api: _OfflineAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';
    final catalog = CatalogController(
      config,
      auth,
      api: _WidgetCatalogGateway(),
    );
    catalog.configuration = _widgetCatalogConfiguration;
    catalog.result = CatalogItemPage(
      items: [_widgetCatalogItem],
      page: 1,
      pageSize: 12,
      total: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: CatalogPage(controller: catalog)),
      ),
    );
    await tester.pump();

    expect(find.text('Каталог товаров'), findsOneWidget);
    expect(find.text('Вентилятор канальный'), findsOneWidget);
    expect(find.byKey(const Key('catalog-create')), findsOneWidget);

    for (final width in [375.0, 1024.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 812);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width == 375) {
        expect(
          find.byKey(const PageStorageKey('catalog-list')),
          findsOneWidget,
        );
      } else {
        final toolbar = find.byKey(const Key('catalog-toolbar'));
        expect(tester.getTopLeft(toolbar), Offset.zero);
        expect(tester.getSize(toolbar).width, width);
        expect(tester.getSize(toolbar).height, greaterThanOrEqualTo(69));
        if (width == 1440) {
          expect(tester.getSize(toolbar).height, 69);
        }
        expect(
          find.text('Карточки и структура текущей организации'),
          findsNothing,
        );
        Finder filter(String label) => find.byWidgetPredicate(
          (w) => w is AppSelectField<String> && w.label == label,
        );
        final categoryY = tester.getTopLeft(filter('Категория')).dy;
        expect(tester.getTopLeft(filter('Раздел')).dy, categoryY);
        expect(tester.getTopLeft(filter('Статус')).dy, categoryY);
        final categorySize = tester.getSize(filter('Категория'));
        expect(categorySize.width, 230);
        expect(categorySize.height, tester.getSize(filter('Раздел')).height);
        expect(categorySize.height, tester.getSize(filter('Статус')).height);
      }
    }
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Вентилятор канальный'));
    await tester.pumpAndSettle();

    expect(find.text('Редактирование товара'), findsOneWidget);
    expect(find.byKey(const Key('catalog-save')), findsOneWidget);
    expect(find.text('Справочник не назначен'), findsOneWidget);
    expect(find.text('шт'), findsNothing);
    expect(find.text('Основное'), findsOneWidget);
    expect(find.text('Цены'), findsOneWidget);
    expect(find.text('Остатки'), findsOneWidget);
    expect(find.text('Изображения'), findsOneWidget);

    final editor = tester.widget<CatalogEditor>(find.byType(CatalogEditor));
    for (final width in [375.0, 1024.0]) {
      tester.view.physicalSize = Size(width, 812);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: editor),
        ),
      );
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('catalog-save'));
      final cancel = find.widgetWithText(OutlinedButton, 'Отмена');
      expect(tester.getSize(save), tester.getSize(cancel));
      for (final button in [save, cancel]) {
        expect(
          tester.getSize(
            find.descendant(of: button, matching: find.byType(Material)).first,
          ),
          const Size(120, 40),
        );
      }
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('Остатки'));
    await tester.pumpAndSettle();
    expect(find.text('Складской учёт ещё не подключён'), findsOneWidget);

    catalog.dispose();
    auth.dispose();
  });
}

final _widgetCatalogConfiguration = CatalogConfiguration(
  categories: [
    CatalogCategory(
      id: '11111111-1111-1111-1111-111111111111',
      name: 'Оборудование',
      sortOrder: 0,
      fields: const [
        CatalogField(
          code: 'name',
          label: 'Наименование',
          fieldType: 'text',
          isVisible: true,
          isRequired: true,
          sortOrder: 0,
        ),
        CatalogField(
          code: 'marking',
          label: 'Маркировка / размер',
          fieldType: 'text',
          isVisible: true,
          isRequired: false,
          sortOrder: 1,
        ),
        CatalogField(
          code: 'base_price',
          label: 'Цена',
          fieldType: 'money',
          isVisible: true,
          isRequired: true,
          sortOrder: 2,
        ),
        CatalogField(
          code: 'unit',
          label: 'Единица измерения',
          fieldType: 'dictionary',
          isVisible: true,
          isRequired: false,
          sortOrder: 3,
        ),
      ],
      sections: const [],
    ),
  ],
  dictionaries: const [
    CatalogDictionary(
      id: '33333333-3333-3333-3333-333333333333',
      code: 'units',
      name: 'Единицы измерения',
      sortOrder: 0,
      items: [
        CatalogDictionaryItem(
          id: '44444444-4444-4444-4444-444444444444',
          value: 'шт',
          sortOrder: 0,
        ),
      ],
    ),
  ],
);

final _widgetCatalogItem = CatalogItem(
  id: '22222222-2222-2222-2222-222222222222',
  categoryId: '11111111-1111-1111-1111-111111111111',
  sectionId: null,
  groupId: null,
  name: 'Вентилятор канальный',
  marking: 'VK-1',
  status: 'approved',
  values: const {'base_price': 15000},
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 2),
);

final class _WidgetCatalogGateway implements CatalogGateway {
  @override
  Future<CatalogItem> createItem(
    String accessToken,
    CatalogItemDraft draft,
  ) async => _widgetCatalogItem;
  @override
  Future<void> deleteItem(String accessToken, String itemId) async {}
  @override
  Future<CatalogConfiguration> getConfiguration(String accessToken) async =>
      _widgetCatalogConfiguration;
  @override
  Future<CatalogItemPage> getItems({
    required String accessToken,
    String? categoryId,
    String? sectionId,
    String? groupId,
    String? status,
    String? search,
    required int page,
    required int pageSize,
    String? sort,
  }) async => CatalogItemPage(
    items: [_widgetCatalogItem],
    page: 1,
    pageSize: pageSize,
    total: 1,
  );
  @override
  Future<CatalogItem> updateItem(
    String accessToken,
    String itemId,
    CatalogItemDraft draft,
  ) async => _widgetCatalogItem;
  @override
  void close() {}
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

/// Имитирует истёкший access token и успешную либо отклонённую refresh-ротацию.
final class _RefreshingAuthGateway implements AuthGateway {
  _RefreshingAuthGateway({
    this.refreshFails = false,
    this.refreshDelay = Duration.zero,
  });

  final bool refreshFails;
  final Duration refreshDelay;
  final List<String> sessionRequestTokens = <String>[];
  int refreshRequests = 0;

  @override
  Future<dynamic> get(String path, String accessToken) async {
    if (path != '/identity/sessions') {
      throw const AuthApiException('unexpected_request', 'Неожиданный GET.');
    }
    sessionRequestTokens.add(accessToken);
    if (accessToken == 'expired-access-token') {
      throw const AuthApiException('session_expired', 'Сессия истекла.', 401);
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    if (path != '/auth/refresh') {
      throw const AuthApiException('unexpected_request', 'Неожиданный POST.');
    }
    refreshRequests += 1;
    if (refreshDelay > Duration.zero) {
      await Future<void>.delayed(refreshDelay);
    }
    if (refreshFails) {
      throw const AuthApiException(
        'session_invalid',
        'Сессия недействительна.',
        401,
      );
    }
    return <String, dynamic>{
      'accessToken': 'renewed-access-token',
      'refreshToken': 'rotated-refresh-token',
      'organizationId': 'organization-id',
    };
  }

  @override
  Future<dynamic> delete(String path, String accessToken) async {
    if (path != '/identity/sessions') {
      throw const AuthApiException('unexpected_request', 'Неожиданный DELETE.');
    }
    throw const AuthApiException('session_expired', 'Сессия истекла.', 401);
  }

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
