import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/company/company_api.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/company/company_page.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

void main() {
  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
  );

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
      expect(controller.configuration!.rules.single.clientId, 'rule-save-check');
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

      await tester.pumpWidget(
        MaterialApp(home: CompanyPage(controller: controller)),
      );

      expect(find.text('Настройки организации'), findsOneWidget);
      expect(find.text('Клиенты'), findsNothing);
      expect(find.text('Сотрудники и структура'), findsNothing);
      expect(find.text('Права доступа'), findsNothing);
      expect(find.text('Юридические лица'), findsOneWidget);
      expect(find.text('Рабочая конфигурация'), findsOneWidget);

      await tester.tap(find.text('Рабочая конфигурация'));
      await tester.pumpAndSettle();
      expect(find.text('Канбаны'), findsWidgets);
      expect(find.text('Каталог'), findsOneWidget);

      controller.dispose();
      auth.dispose();
    },
  );

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
    await tester.tap(find.byTooltip('Свернуть ветку'));
    await tester.pumpAndSettle();
    expect(find.text('Подчинённый сотрудник'), findsNothing);
    expect(find.text('Директор'), findsWidgets);

    controller.dispose();
    auth.dispose();
  });
}

final class _MemoryCompanyGateway implements CompanyGateway {
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
      CompanyProfileDraft(organizationName: 'Склад Комфорта')
        ..companyType = 'ООО';

  @override
  Future<OrganizationOnboardingDraft> getConfiguration(
    String accessToken,
  ) async {
    final draft = configurationValue ?? OrganizationOnboardingDraft.initial();
    draft.company.organizationName = 'Склад Комфорта';
    draft.company.companyType = 'ООО';
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
  Future<List<EmployeeModel>> getEmployees(String accessToken) async => [
    director,
    subordinate,
  ];

  @override
  Future<List<CompanyRoleModel>> getRoles(String accessToken) async => const [
    CompanyRoleModel(
      id: 'director-role',
      name: 'Директор',
      isSystem: true,
      permissionCodes: [],
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
