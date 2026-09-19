import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

abstract interface class CompanyGateway {
  Future<CompanyProfileDraft> getProfile(String accessToken);
  Future<CompanyProfileDraft> updateProfile(
    String accessToken,
    CompanyProfileDraft profile,
  );
  Future<OrganizationOnboardingDraft> getConfiguration(String accessToken);
  Future<CategoryDeletionImpact> getCategoryDeletionImpact(
    String accessToken,
    String categoryClientId,
  );
  Future<OrganizationOnboardingDraft> updateConfiguration(
    String accessToken,
    OrganizationOnboardingDraft draft, {
    List<String> deleteCategoryData = const [],
  });
  void close();
}

/// REST-операции рабочих подпространств компании.
abstract interface class CompanyWorkspaceGateway {
  Future<CompanyProfileDraft> getProfile(String accessToken);
  Future<OrganizationLifecycle> getLifecycle(String accessToken);
  Future<List<CompanyAuditEntryModel>> getAudit(String accessToken);
  Future<List<LegalEntityModel>> getLegalEntities(String accessToken);
  Future<List<CompanyClientModel>> getClients(String accessToken);
  Future<List<EmployeeModel>> getEmployees(String accessToken);
  Future<List<CompanyRoleModel>> getRoles(String accessToken);
  Future<List<CompanyPermissionModel>> getPermissions(String accessToken);
  Future<LegalEntityModel> saveLegalEntity(
    String accessToken,
    LegalEntityModel value, {
    bool create = false,
  });
  Future<void> deleteLegalEntity(String accessToken, String id);
  Future<CompanyClientModel> saveClient(
    String accessToken,
    CompanyClientModel value, {
    bool create = false,
  });
  Future<void> deleteClient(String accessToken, String id);
  Future<EmployeeModel> createEmployee(
    String accessToken,
    CreateEmployeeModel value,
  );
  Future<EmployeeModel> updateEmployee(
    String accessToken,
    String membershipId,
    UpdateEmployeeModel value,
  );
  Future<void> deleteEmployee(String accessToken, String membershipId);
  Future<CompanyRoleModel> saveRole(
    String accessToken,
    CompanyRoleModel value, {
    bool create = false,
  });
  Future<void> deleteRole(String accessToken, String id);
}

/// REST-клиент рабочего профиля организации.
final class CompanyApi implements CompanyGateway, CompanyWorkspaceGateway {
  CompanyApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  @override
  Future<CompanyProfileDraft> getProfile(String accessToken) async {
    final data = await _send('GET', accessToken);
    return CompanyProfileDraft.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<CompanyProfileDraft> updateProfile(
    String accessToken,
    CompanyProfileDraft profile,
  ) async {
    final data = await _send('PUT', accessToken, body: profile.toJson());
    return CompanyProfileDraft.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<OrganizationOnboardingDraft> getConfiguration(
    String accessToken,
  ) async {
    final data = await _sendPath('GET', '/company/configuration', accessToken);
    return OrganizationOnboardingDraft.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<OrganizationOnboardingDraft> updateConfiguration(
    String accessToken,
    OrganizationOnboardingDraft draft, {
    List<String> deleteCategoryData = const [],
  }) async {
    final data = await _sendPath(
      'PUT',
      '/company/configuration',
      accessToken,
      body: {'draft': draft.toJson(), 'deleteCategoryData': deleteCategoryData},
    );
    return OrganizationOnboardingDraft.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<CategoryDeletionImpact> getCategoryDeletionImpact(
    String accessToken,
    String categoryClientId,
  ) async {
    final data = await _sendPath(
      'GET',
      '/company/configuration/categories/${Uri.encodeComponent(categoryClientId)}/deletion-impact',
      accessToken,
    );
    return CategoryDeletionImpact.fromJson(data as Map<String, dynamic>);
  }

  Future<dynamic> _send(
    String method,
    String accessToken, {
    Map<String, dynamic>? body,
  }) async {
    return _sendPath(method, '/company/profile', accessToken, body: body);
  }

  Future<dynamic> _sendPath(
    String method,
    String path,
    String accessToken, {
    Map<String, dynamic>? body,
  }) async {
    final request =
        http.Request(method, Uri.parse('${_config.apiBaseUrl}$path'))
          ..headers.addAll({
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          });
    if (body != null) request.body = jsonEncode(body);
    final response = await _client.send(request);
    return decodeApiResponse(await http.Response.fromStream(response));
  }

  Future<dynamic> _workspace(
    String method,
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) => _sendPath(method, path, token, body: body);

  @override
  Future<OrganizationLifecycle> getLifecycle(String token) async =>
      OrganizationLifecycle.fromJson(
        await _workspace('GET', '/company/lifecycle', token)
            as Map<String, dynamic>,
      );

  @override
  Future<List<CompanyAuditEntryModel>> getAudit(String token) async =>
      ((await _workspace('GET', '/company/audit', token)) as List)
          .cast<Map<String, dynamic>>()
          .map(CompanyAuditEntryModel.fromJson)
          .toList();

  @override
  Future<List<LegalEntityModel>> getLegalEntities(String token) async =>
      ((await _workspace('GET', '/company/legal-entities', token)) as List)
          .cast<Map<String, dynamic>>()
          .map(LegalEntityModel.fromJson)
          .toList();

  @override
  Future<List<CompanyClientModel>> getClients(String token) async =>
      ((await _workspace('GET', '/company/clients', token)) as List)
          .cast<Map<String, dynamic>>()
          .map(CompanyClientModel.fromJson)
          .toList();

  @override
  Future<List<EmployeeModel>> getEmployees(String token) async =>
      ((await _workspace('GET', '/company/employees', token)) as List)
          .cast<Map<String, dynamic>>()
          .map(EmployeeModel.fromJson)
          .toList();

  @override
  Future<List<CompanyRoleModel>> getRoles(String token) async =>
      ((await _workspace('GET', '/settings/access/roles', token)) as List)
          .cast<Map<String, dynamic>>()
          .map(CompanyRoleModel.fromJson)
          .toList();

  @override
  Future<List<CompanyPermissionModel>> getPermissions(String token) async =>
      ((await _workspace('GET', '/settings/access/permissions', token)) as List)
          .cast<Map<String, dynamic>>()
          .map(CompanyPermissionModel.fromJson)
          .toList();

  @override
  Future<LegalEntityModel> saveLegalEntity(
    String token,
    LegalEntityModel value, {
    bool create = false,
  }) async => LegalEntityModel.fromJson(
    await _workspace(
          create ? 'POST' : 'PUT',
          create
              ? '/company/legal-entities'
              : '/company/legal-entities/${value.id}',
          token,
          body: value.toJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteLegalEntity(String token, String id) async {
    await _workspace('DELETE', '/company/legal-entities/$id', token);
  }

  @override
  Future<CompanyClientModel> saveClient(
    String token,
    CompanyClientModel value, {
    bool create = false,
  }) async => CompanyClientModel.fromJson(
    await _workspace(
          create ? 'POST' : 'PUT',
          create ? '/company/clients' : '/company/clients/${value.id}',
          token,
          body: value.toJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteClient(String token, String id) async {
    await _workspace('DELETE', '/company/clients/$id', token);
  }

  @override
  Future<EmployeeModel> createEmployee(
    String token,
    CreateEmployeeModel value,
  ) async => EmployeeModel.fromJson(
    await _workspace('POST', '/company/employees', token, body: value.toJson())
        as Map<String, dynamic>,
  );

  @override
  Future<EmployeeModel> updateEmployee(
    String token,
    String membershipId,
    UpdateEmployeeModel value,
  ) async => EmployeeModel.fromJson(
    await _workspace(
          'PUT',
          '/company/employees/$membershipId',
          token,
          body: value.toJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteEmployee(String token, String membershipId) async {
    await _workspace('DELETE', '/company/employees/$membershipId', token);
  }

  @override
  Future<CompanyRoleModel> saveRole(
    String token,
    CompanyRoleModel value, {
    bool create = false,
  }) async => CompanyRoleModel.fromJson(
    await _workspace(
          create ? 'POST' : 'PUT',
          create
              ? '/settings/access/roles'
              : '/settings/access/roles/${value.id}',
          token,
          body: {
            'name': value.name,
            'permissionCodes': value.permissionCodes,
            'subordinateRoleIds': value.subordinateRoleIds,
            'cardVisibilityMode': value.cardVisibilityMode,
            'cardVisibilityMembershipIds': value.cardVisibilityMembershipIds,
          },
        )
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteRole(String token, String id) async {
    await _workspace('DELETE', '/settings/access/roles/$id', token);
  }

  @override
  void close() => _client.close();
}
