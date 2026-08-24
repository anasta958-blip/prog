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

      final configurationSaved = await controller.saveConfiguration(
        controller.configuration!,
      );
      expect(configurationSaved, isTrue);
      expect(gateway.savedConfiguration, isNotNull);

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

  @override
  Future<CompanyProfileDraft> getProfile(String accessToken) async =>
      CompanyProfileDraft(organizationName: 'Склад Комфорта')
        ..companyType = 'ООО';

  @override
  Future<OrganizationOnboardingDraft> getConfiguration(
    String accessToken,
  ) async {
    final draft = OrganizationOnboardingDraft.initial();
    draft.company.organizationName = 'Склад Комфорта';
    draft.company.companyType = 'ООО';
    return draft;
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
    OrganizationOnboardingDraft draft,
  ) async {
    savedConfiguration = draft;
    return OrganizationOnboardingDraft.fromJson(draft.toJson());
  }

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
