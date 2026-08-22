import 'package:flutter/material.dart';
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

  testWidgets('onboarding использует выбранный восьмишаговый вариант 2', (
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
    expect(find.text('5. Зависимости'), findsOneWidget);

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

    expect(find.text('Название канбана'), findsOneWidget);
    expect(find.text('Код'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Свернуть канбан'));
    await tester.pumpAndSettle();
    expect(find.text('Название канбана'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Развернуть канбан'));
    await tester.pumpAndSettle();
    expect(find.text('Название канбана'), findsOneWidget);

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

      expect(find.text('Категория'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Свернуть категорию'));
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
      ..currentStep = 4
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
    await tester.ensureVisible(
      find.text('Использовать категорию в этом канбане'),
    );
    await tester.tap(
      find.ancestor(
        of: find.text('Использовать категорию в этом канбане'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    await tester.pumpAndSettle();

    expect(workflow.categories.single.categoryClientId, 'equipment');
    expect(workflow.categories.single.fieldCodes, ['name']);
    expect(find.text('Расчётное поле'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Свернуть поля категории'));
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
      ..currentStep = 7
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

    await tester.tap(find.text('Вентилятор канальный'));
    await tester.pumpAndSettle();

    expect(find.text('Редактирование товара'), findsOneWidget);
    expect(find.byKey(const Key('catalog-save')), findsOneWidget);

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
      ],
      sections: const [],
    ),
  ],
  dictionaries: const [],
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
    String? status,
    String? search,
    required int page,
    required int pageSize,
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
  _RefreshingAuthGateway({this.refreshFails = false});

  final bool refreshFails;
  final List<String> sessionRequestTokens = <String>[];

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
