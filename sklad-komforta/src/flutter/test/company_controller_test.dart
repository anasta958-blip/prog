import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/network/realtime_client.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/company/company_api.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/company/company_page.dart';
import 'package:sklad_komforta_app/features/company/employee_password_dialog.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

void main() {
  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
  );

  testWidgets(
    'роль директора показывает полный доступ на узкой и широкой раскладке',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = CompanyController(
        config,
        auth,
        api: _MemoryCompanyGateway(),
        workspaceApi: _PartialWorkspaceGateway(),
      );
      await controller.initialize();
      for (final width in [375.0, 1024.0]) {
        tester.view.physicalSize = Size(width, 812);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CompanyPage(
                controller: controller,
                section: CompanySection.access,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Полный доступ'), findsWidgets);
        expect(find.textContaining('1 прав'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets('смена пароля проверяет подтверждение и отправляет запрос', (
    tester,
  ) async {
    final gateway = _PartialWorkspaceGateway();
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';
    final controller = CompanyController(
      config,
      auth,
      api: _MemoryCompanyGateway(),
      workspaceApi: gateway,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => EmployeePasswordDialog(
                  employee: _PartialWorkspaceGateway.subordinate,
                  controller: controller,
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'New-password-123!',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Different-password',
    );
    await tester.tap(find.text('Сменить пароль'));
    await tester.pumpAndSettle();
    expect(find.text('Пароли не совпадают.'), findsOneWidget);
    expect(gateway.newPassword, isNull);
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'New-password-123!',
    );
    await tester.tap(find.text('Сменить пароль'));
    await tester.pumpAndSettle();
    expect(gateway.passwordMembershipId, 'employee-membership');
    expect(gateway.newPassword, 'New-password-123!');
    expect(find.byType(EmployeePasswordDialog), findsNothing);
    expect(find.text('Пароль сотрудника изменён.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    controller.dispose();
    auth.dispose();
  });

  test(
    'профиль компании загружается и сохраняется через общий токен',
    () async {
      final gateway = _MemoryCompanyGateway();
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = CompanyController(config, auth, api: gateway);

      await controller.initialize();
      expect(controller.profile?.organizationName, 'Склад Комфорта');
      expect(controller.configuration, isNotNull);

      controller.profile!.organizationName = 'Новая компания';
      final result = await controller.save();

      expect(result, isTrue);
      expect(gateway.saved?.organizationName, 'Новая компания');
      expect(controller.saved, isTrue);
      expect(controller.error, isNull);

      controller.configuration!.rules.add(
        CalculationRuleDraft(
          clientId: 'rule-save-check',
          name: 'Проверка сохранения',
          categoryClientId: 'equipment',
          eventType: 'card_saving',
          isEnabled: true,
          actions: [
            RuleActionDraft(
              actionType: 'block_save',
              message: 'Заполните данные.',
            ),
          ],
        ),
      );
      final configurationSaved = await controller.saveConfiguration(
        controller.configuration!,
        deleteCategoryData: const ['category-1'],
      );
      expect(configurationSaved, isTrue);
      expect(gateway.savedConfiguration, isNotNull);
      expect(
        controller.configuration!.rules.single.clientId,
        'rule-save-check',
      );
      expect(gateway.deletedCategoryData, const ['category-1']);

      controller.approveCategoryDataDeletion('category-2');
      final persistedApproval = await controller.saveConfiguration(
        controller.configuration!,
      );
      expect(persistedApproval, isTrue);
      expect(gateway.deletedCategoryData, const ['category-2']);

      final impact = await controller.getCategoryDeletionImpact('category-1');
      expect(impact?.categoryClientId, 'category-1');
      expect(impact?.hasData, isFalse);

      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'раздел компании показывает вкладки настройки без внутреннего меню',
    (tester) async {
      final gateway = _MemoryCompanyGateway();
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = CompanyController(config, auth, api: gateway);
      await controller.initialize();

      tester.view.physicalSize = const Size(1700, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: CompanyPage(controller: controller)),
      );

      expect(
        tester.getSize(find.byKey(const Key('company-section-header'))).height,
        71,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(800, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Настройки организации'), findsNothing);
      expect(find.text('Клиенты'), findsNothing);
      expect(find.text('Сотрудники и структура'), findsNothing);
      expect(find.text('Права доступа'), findsNothing);
      expect(find.text('Юридические лица'), findsOneWidget);
      await tester.tap(find.text('Юридические лица'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Рабочая конфигурация'));
      await tester.pumpAndSettle();
      expect(find.text('Канбаны'), findsWidgets);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is AppSelectField<int> && widget.label == 'Раздел',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Каталог'), findsOneWidget);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Канбаны'));
      await tester.pumpAndSettle();
      for (final width in [375.0, 1024.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 812);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      controller.dispose();
      auth.dispose();
    },
  );

  for (final section in CompanySection.values) {
    testWidgets('компактная шапка компании: ${section.name}', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = CompanyController(
        config,
        auth,
        api: _MemoryCompanyGateway(),
      );
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyPage(controller: controller, section: section),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('company-section-header'))).height,
        71,
      );
      expect(
        find.text(
          section == CompanySection.employees
              ? 'Дерево иерархии сотрудников'
              : section.label,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(800, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      auth.dispose();
    });
  }

  testWidgets(
    'непустая категория удаляется только после явного подтверждения',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final draft = OrganizationOnboardingDraft.initial()
        ..currentStep = 9
        ..categories.add(
          CatalogCategoryDraft(
            clientId: 'equipment',
            name: 'Оборудование',
            sections: [],
            fields: [],
          ),
        );
      final gateway = _MemoryCompanyGateway()
        ..configurationValue = draft
        ..impact = const CategoryDeletionImpact(
          categoryClientId: 'equipment',
          categoryName: 'Оборудование',
          itemCount: 3,
          imageCount: 2,
          relationCount: 1,
        );
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = CompanyController(config, auth, api: gateway);
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(home: CompanyPage(controller: controller)),
      );
      await tester.tap(find.text('Рабочая конфигурация'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Каталог'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      expect(find.text('Категория не пуста'), findsOneWidget);
      expect(find.textContaining('3 карточек'), findsOneWidget);
      expect(find.text('Оборудование'), findsWidgets);

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.text('Оборудование'), findsWidgets);

      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить всё'));
      await tester.pumpAndSettle();
      expect(find.text('Оборудование'), findsNothing);

      await tester.tap(find.text('Юридические лица'));
      await tester.pumpAndSettle();
      expect(find.text('Изменения не сохранены'), findsOneWidget);
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Сохранить изменения'));
      await tester.pumpAndSettle();
      expect(gateway.deletedCategoryData, const ['equipment']);

      // Любое следующее изменение остаётся локальным. При подтверждённом
      // выходе оно отбрасывается и не меняет сохранённую конфигурацию.
      await tester.tap(find.text('Добавить категорию'));
      await tester.pumpAndSettle();
      expect(find.text('Новая категория'), findsWidgets);
      await tester.tap(find.text('Юридические лица'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выйти без сохранения'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Рабочая конфигурация'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Каталог'));
      await tester.pumpAndSettle();
      expect(find.text('Новая категория'), findsNothing);

      controller.dispose();
      auth.dispose();
    },
  );

  test('изменения пространства компании подгружаются сами', () async {
    final gateway = _MemoryCompanyGateway();
    final workspace = _PartialWorkspaceGateway();
    final realtime = _FakeRealtime();
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';
    final controller = CompanyController(
      config,
      auth,
      api: gateway,
      workspaceApi: workspace,
      realtime: realtime,
      realtimeDebounce: Duration.zero,
    );
    await controller.initialize();
    expect(realtime.started, isTrue);
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));
    final employeeRequests = workspace.employeeRequests;
    final configurationRequests = gateway.configurationRequests;

    // Другой пользователь добавил сотрудника: списки перечитываются, а
    // конфигурация — нет.
    realtime.emit('employees');
    await settle();
    expect(workspace.employeeRequests, employeeRequests + 1);
    expect(gateway.configurationRequests, configurationRequests);

    // Изменение настроек перечитывает и конфигурацию с профилем.
    gateway.configurationValue = OrganizationOnboardingDraft.initial()
      ..company.organizationName = 'Новое название';
    final previous = controller.configuration;
    realtime.emit('configuration');
    await settle();
    expect(gateway.configurationRequests, configurationRequests + 1);
    expect(identical(controller.configuration, previous), isFalse);
    expect(controller.profile?.organizationName, 'Новое название');

    controller.dispose();
    await realtime.close();
    auth.dispose();
  });

  test(
    'запрет одного раздела не блокирует остальные данные компании',
    () async {
      final gateway = _MemoryCompanyGateway();
      final workspace = _PartialWorkspaceGateway();
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = CompanyController(
        config,
        auth,
        api: gateway,
        workspaceApi: workspace,
      );

      await controller.initialize();

      expect(controller.error, isNull);
      expect(controller.canViewClients, isFalse);
      expect(controller.canViewEmployees, isTrue);
      expect(controller.employees, hasLength(2));

      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets('руководитель сворачивает только свою ветку дерева', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _MemoryCompanyGateway();
    final workspace = _PartialWorkspaceGateway();
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';
    final controller = CompanyController(
      config,
      auth,
      api: gateway,
      workspaceApi: workspace,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyPage(
            controller: controller,
            section: CompanySection.employees,
          ),
        ),
      ),
    );

    expect(find.text('Подчинённый сотрудник'), findsOneWidget);
    for (final width in [375.0, 1024.0]) {
      tester.view.physicalSize = Size(width, 812);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Свернуть ветку'));
    await tester.pumpAndSettle();
    expect(find.text('Подчинённый сотрудник'), findsNothing);
    expect(find.text('Директор'), findsWidgets);

    controller.dispose();
    auth.dispose();
  });

  group('заполнение реквизитов по ИНН', () {
    const sberbank = CompanyRegistryRecord(
      companyType: 'ooo',
      name: 'ПАО СБЕРБАНК',
      legalName: 'ПУБЛИЧНОЕ АКЦИОНЕРНОЕ ОБЩЕСТВО "СБЕРБАНК РОССИИ"',
      inn: '7707083893',
      kpp: '773601001',
      ogrn: '1027700132195',
      address: '117312, Г.МОСКВА, УЛ. ВАВИЛОВА, Д.19',
      email: 'info@sberbank.ru',
      directorName: 'Греф Герман Оскарович',
      directorTitle: 'Президент, председатель правления',
    );

    test('юрлицо получает реквизиты, а заполненный подписант сохраняется', () {
      final entity = LegalEntityModel(id: '', name: '', companyType: 'ooo')
        ..signatoryName = 'Иванов И. И.'
        ..bankBik = '044525225';

      sberbank.applyToLegalEntity(entity);

      expect(entity.name, 'ПАО СБЕРБАНК');
      expect(entity.legalName, sberbank.legalName);
      expect(entity.kpp, '773601001');
      expect(entity.address, sberbank.address);
      expect(entity.email, 'info@sberbank.ru');
      expect(entity.directorName, 'Греф Герман Оскарович');
      expect(entity.signatoryName, 'Иванов И. И.');
      expect(entity.signatoryTitle, 'Президент, председатель правления');
      expect(entity.bankBik, '044525225');
    });

    test('ИП не получает КПП, а пустой адрес не стирает введённый', () {
      final client = CompanyClientModel(id: '', name: '', companyType: 'ooo')
        ..kpp = '123456789'
        ..address = 'Введённый адрес'
        ..email = 'old@example.ru';
      const individual = CompanyRegistryRecord(
        companyType: 'ip',
        name: 'ИП Иванов Иван Иванович',
        legalName: 'Иванов Иван Иванович',
        inn: '500123456750',
        ogrn: '304500116000157',
        email: 'aircooling_skornyakov@mail.ru',
      );

      individual.applyToClient(client);

      expect(client.companyType, 'ip');
      expect(client.name, 'ИП Иванов Иван Иванович');
      expect(client.companyName, client.name);
      expect(client.kpp, isNull);
      expect(client.address, 'Введённый адрес');
      expect(client.email, 'aircooling_skornyakov@mail.ru');
      expect(registryLookupNotice(individual), contains('ЕГРИП'));
      expect(registryLookupNotice(individual), contains('не публикуется'));
    });

    test(
      'контроллер возвращает ошибку сервера, не меняя общее состояние',
      () async {
        final registry = _MemoryRegistryGateway()
          ..failure = const ApiException(
            'registry_not_found',
            'В ЕГРЮЛ/ЕГРИП нет записи с таким ИНН.',
            404,
          );
        final auth = AuthController(
          config,
          api: _NoopAuthGateway(),
          tokens: _MemoryTokenRepository(),
        )..accessToken = 'access-token';
        final controller = CompanyController(
          config,
          auth,
          api: _MemoryCompanyGateway(),
          registryApi: registry,
        );

        final missing = await controller.lookupByInn(
          '7707083893',
          CompanyRegistryScope.client,
        );
        expect(missing.record, isNull);
        expect(missing.error, 'В ЕГРЮЛ/ЕГРИП нет записи с таким ИНН.');
        expect(controller.error, isNull);
        expect(registry.lastScope, CompanyRegistryScope.client);

        registry
          ..failure = null
          ..record = sberbank;
        final found = await controller.lookupByInn(
          '7707083893',
          CompanyRegistryScope.legalEntity,
        );
        expect(found.record?.name, 'ПАО СБЕРБАНК');
        expect(registry.lastInn, '7707083893');

        controller.dispose();
        auth.dispose();
      },
    );

    testWidgets('кнопка в карточке юрлица заполняет поля формы', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = CompanyController(
        config,
        auth,
        api: _MemoryCompanyGateway(),
        workspaceApi: _PartialWorkspaceGateway(),
        registryApi: _MemoryRegistryGateway()..record = sberbank,
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CompanyPage(controller: controller)),
        ),
      );
      await tester.tap(find.text('Добавить юридическое лицо'));
      await tester.pumpAndSettle();
      for (final width in [375.0, 1024.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final inn = find.widgetWithText(TextFormField, 'ИНН *');
        expect(tester.getSize(inn).width, greaterThan(150));
      }
      tester.view.physicalSize = const Size(1400, 900);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'ИНН *'),
        '7707083893',
      );
      await tester.tap(find.byTooltip('Заполнить по ИНН'));
      await tester.pumpAndSettle();

      expect(find.text('ПАО СБЕРБАНК'), findsOneWidget);
      expect(find.text('773601001'), findsOneWidget);
      expect(find.text('info@sberbank.ru'), findsOneWidget);
      expect(find.text('117312, Г.МОСКВА, УЛ. ВАВИЛОВА, Д.19'), findsOneWidget);
      expect(
        find.textContaining('Реквизиты заполнены из ЕГРЮЛ'),
        findsOneWidget,
      );

      controller.dispose();
      auth.dispose();
    });
  });
}

final class _MemoryRegistryGateway implements CompanyRegistryGateway {
  CompanyRegistryRecord? record;
  ApiException? failure;
  String? lastInn;
  CompanyRegistryScope? lastScope;

  @override
  Future<CompanyRegistryRecord> lookupByInn(
    String accessToken,
    String inn,
    CompanyRegistryScope scope,
  ) async {
    lastInn = inn;
    lastScope = scope;
    if (failure != null) throw failure!;
    return record!;
  }
}

/// Источник сигналов, которым управляет тест.
final class _FakeRealtime implements RealtimeSource {
  final _controller = StreamController<RealtimeEvent>.broadcast();
  bool started = false;

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  void start() => started = true;

  @override
  Future<void> close() => _controller.close();

  void emit(String section) => _controller.add(
    RealtimeEvent(topic: 'company', kind: 'changed', section: section),
  );
}

final class _MemoryCompanyGateway implements CompanyGateway {
  int configurationRequests = 0;
  CompanyProfileDraft? saved;
  OrganizationOnboardingDraft? savedConfiguration;
  List<String> deletedCategoryData = const [];
  OrganizationOnboardingDraft? configurationValue;
  CategoryDeletionImpact impact = const CategoryDeletionImpact(
    categoryClientId: 'category',
    categoryName: 'Категория',
    itemCount: 0,
    imageCount: 0,
    relationCount: 0,
  );

  @override
  Future<CompanyProfileDraft> getProfile(String accessToken) async =>
      CompanyProfileDraft(organizationName: 'Склад Комфорта');

  @override
  Future<OrganizationOnboardingDraft> getConfiguration(
    String accessToken,
  ) async {
    configurationRequests++;
    final draft = configurationValue ?? OrganizationOnboardingDraft.initial();
    if (draft.company.organizationName.isEmpty) {
      draft.company.organizationName = 'Склад Комфорта';
    }
    return OrganizationOnboardingDraft.fromJson(draft.toJson());
  }

  @override
  Future<CompanyProfileDraft> updateProfile(
    String accessToken,
    CompanyProfileDraft profile,
  ) async {
    saved = profile;
    return CompanyProfileDraft.fromJson(profile.toJson());
  }

  @override
  Future<OrganizationOnboardingDraft> updateConfiguration(
    String accessToken,
    OrganizationOnboardingDraft draft, {
    List<String> deleteCategoryData = const [],
  }) async {
    savedConfiguration = draft;
    deletedCategoryData = deleteCategoryData;
    return OrganizationOnboardingDraft.fromJson(draft.toJson());
  }

  @override
  Future<CategoryDeletionImpact> getCategoryDeletionImpact(
    String accessToken,
    String categoryClientId,
  ) async => CategoryDeletionImpact(
    categoryClientId: categoryClientId,
    categoryName: impact.categoryName,
    itemCount: impact.itemCount,
    imageCount: impact.imageCount,
    relationCount: impact.relationCount,
  );

  @override
  void close() {}
}

final class _PartialWorkspaceGateway implements CompanyWorkspaceGateway {
  int employeeRequests = 0;
  String? passwordMembershipId;
  String? newPassword;

  @override
  Future<void> changeEmployeePassword(
    String accessToken,
    String membershipId,
    String password,
  ) async {
    passwordMembershipId = membershipId;
    newPassword = password;
  }

  static final director = EmployeeModel(
    membershipId: 'director-membership',
    userId: 'director-user',
    login: 'director',
    displayName: 'Директор',
    roleId: 'director-role',
    roleName: 'Директор',
    isDirector: true,
    isActive: true,
    createdAt: DateTime(2026),
    activeUntil: DateTime(2027),
  );

  static final subordinate = EmployeeModel(
    membershipId: 'employee-membership',
    userId: 'employee-user',
    login: 'employee',
    displayName: 'Подчинённый сотрудник',
    roleId: 'employee-role',
    roleName: 'Менеджер',
    supervisorMembershipId: director.membershipId,
    isDirector: false,
    isActive: true,
    createdAt: DateTime(2026),
    activeUntil: DateTime(2027),
  );

  @override
  Future<CompanyProfileDraft> getProfile(String accessToken) async =>
      CompanyProfileDraft(organizationName: 'Склад Комфорта');

  @override
  Future<OrganizationLifecycle> getLifecycle(String accessToken) async =>
      OrganizationLifecycle(activeUntil: DateTime(2027), isFrozen: false);

  @override
  Future<List<CompanyAuditEntryModel>> getAudit(String accessToken) async =>
      const [];

  @override
  Future<List<LegalEntityModel>> getLegalEntities(String accessToken) async =>
      const [];

  @override
  Future<List<CompanyClientModel>> getClients(String accessToken) =>
      throw const ApiException('forbidden', 'Нет прав.', 403);

  @override
  Future<List<EmployeeModel>> getEmployees(String accessToken) async {
    employeeRequests++;
    return [director, subordinate];
  }

  @override
  Future<List<CompanyRoleModel>> getRoles(String accessToken) async => const [
    CompanyRoleModel(
      id: 'director-role',
      name: 'Директор',
      isSystem: true,
      permissionCodes: ['system.full_access'],
      subordinateRoleIds: ['employee-role'],
    ),
  ];

  @override
  Future<List<CompanyPermissionModel>> getPermissions(
    String accessToken,
  ) async => const [];

  @override
  Future<LegalEntityModel> saveLegalEntity(
    String accessToken,
    LegalEntityModel value, {
    bool create = false,
  }) async => value;

  @override
  Future<void> deleteLegalEntity(String accessToken, String id) async {}

  @override
  Future<CompanyClientModel> saveClient(
    String accessToken,
    CompanyClientModel value, {
    bool create = false,
  }) async => value;

  @override
  Future<void> deleteClient(String accessToken, String id) async {}

  @override
  Future<EmployeeModel> createEmployee(
    String accessToken,
    CreateEmployeeModel value,
  ) async => subordinate;

  @override
  Future<EmployeeModel> updateEmployee(
    String accessToken,
    String membershipId,
    UpdateEmployeeModel value,
  ) async => subordinate;

  @override
  Future<void> deleteEmployee(String accessToken, String membershipId) async {}

  @override
  Future<CompanyRoleModel> saveRole(
    String accessToken,
    CompanyRoleModel value, {
    bool create = false,
  }) async => value;

  @override
  Future<void> deleteRole(String accessToken, String id) async {}
}

final class _NoopAuthGateway implements AuthGateway {
  @override
  Future<dynamic> delete(String path, String accessToken) async => null;
  @override
  Future<dynamic> get(String path, String accessToken) async => null;
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
