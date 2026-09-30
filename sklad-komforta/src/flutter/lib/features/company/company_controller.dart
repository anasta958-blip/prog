import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/network/realtime_client.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/company/company_api.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

/// Состояние рабочего пространства компании и безопасное обновление токена.
final class CompanyController extends ChangeNotifier {
  /// Без [api] контроллер работает с сервером и сам подписывается на
  /// уведомления об изменениях пространства; в тестах источник передаётся
  /// через [realtime].
  CompanyController(
    AppConfig config,
    this._auth, {
    CompanyGateway? api,
    CompanyWorkspaceGateway? workspaceApi,
    CompanyRegistryGateway? registryApi,
    RealtimeSource? realtime,
    this.realtimeDebounce = const Duration(milliseconds: 300),
  }) : _api = api ?? CompanyApi(config),
       _workspaceApi = workspaceApi,
       _registryApi = registryApi,
       _ownsApi = api == null,
       _realtime =
           realtime ??
           (api == null
               ? RealtimeClient(
                   config: config,
                   topic: 'company',
                   ticketPath: '/company/realtime-ticket',
                   authorized: _auth.executeAuthorized,
                 )
               : null),
       _ownsRealtime = realtime == null && api == null {
    if (_workspaceApi == null && _api is CompanyWorkspaceGateway) {
      _workspaceApi = _api as CompanyWorkspaceGateway;
    }
    if (_registryApi == null && _api is CompanyRegistryGateway) {
      _registryApi = _api as CompanyRegistryGateway;
    }
  }

  final AuthController _auth;
  final CompanyGateway _api;
  CompanyWorkspaceGateway? _workspaceApi;
  CompanyRegistryGateway? _registryApi;
  final bool _ownsApi;

  /// Пауза, за которую серия сигналов сливается в одно перечитывание.
  final Duration realtimeDebounce;
  final RealtimeSource? _realtime;
  final bool _ownsRealtime;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  Timer? _realtimeTimer;
  bool _realtimeConfigurationChanged = false;
  bool _disposed = false;

  /// Авторизационный контекст нужен общему редактору onboarding-настроек.
  AuthController get authController => _auth;

  CompanyProfileDraft? profile;
  OrganizationOnboardingDraft? configuration;
  OrganizationLifecycle? lifecycle;
  List<LegalEntityModel> legalEntities = const [];
  List<CompanyClientModel> clients = const [];
  List<EmployeeModel> employees = const [];
  List<CompanyRoleModel> roles = const [];
  List<CompanyPermissionModel> permissions = const [];
  List<CompanyAuditEntryModel> auditEntries = const [];
  bool canViewLegalEntities = true;
  bool canViewClients = true;
  bool canViewEmployees = true;
  bool canViewAccess = true;
  bool canViewAudit = true;
  bool loading = false;
  bool saving = false;
  String? error;
  bool saved = false;
  final Set<String> _approvedCategoryDataDeletions = <String>{};

  /// Сохраняет подтверждение удаления непустой категории до успешной записи
  /// конфигурации. Оно не теряется при переходе между вкладками и повторном
  /// создании экрана настроек.
  void approveCategoryDataDeletion(String categoryClientId) {
    _approvedCategoryDataDeletions.add(categoryClientId);
  }

  /// Отзывает неподтверждённые сервером разрешения вместе со сброшенным
  /// локальным черновиком.
  void discardCategoryDataDeletionApprovals() {
    _approvedCategoryDataDeletions.clear();
  }

  Future<void> initialize() async {
    _listenRealtime();
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (configuration == null) {
        configuration = await _auth.executeAuthorized(_api.getConfiguration);
        profile = configuration!.company;
      }
      await reloadWorkspace();
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось загрузить данные компании. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Подписывается на изменения пространства, сделанные другими
  /// пользователями или в другой вкладке.
  void _listenRealtime() {
    final source = _realtime;
    if (source == null || _realtimeSubscription != null) return;
    _realtimeSubscription = source.events.listen((event) {
      if (event.section == 'configuration' ||
          event.section == 'profile' ||
          event.kind == RealtimeEvent.resync) {
        _realtimeConfigurationChanged = true;
      }
      _realtimeTimer?.cancel();
      _realtimeTimer = Timer(realtimeDebounce, _applyRealtimeChanges);
    });
    source.start();
  }

  /// Тихо перечитывает списки пространства (юрлица, клиенты, сотрудники, роли,
  /// аудит), а при изменении настроек или профиля — и конфигурацию. Открытые
  /// формы работают со своими копиями: экран настроек не затирает
  /// несохранённые правки, а предупреждает о чужом изменении.
  Future<void> _applyRealtimeChanges() async {
    if (_disposed) return;
    if (loading || saving) {
      _realtimeTimer = Timer(realtimeDebounce, _applyRealtimeChanges);
      return;
    }
    try {
      if (_realtimeConfigurationChanged && configuration != null) {
        _realtimeConfigurationChanged = false;
        configuration = await _auth.executeAuthorized(_api.getConfiguration);
        profile = configuration!.company;
      }
      if (!_disposed) await reloadWorkspace();
    } on Object {
      // Сеть недоступна: данные обновятся после переподключения (resync).
    }
  }

  /// Обновляет независимые списки пространства, не перезагружая onboarding-конфигурацию.
  Future<void> reloadWorkspace() async {
    final api = _workspaceApi;
    if (api == null) return;
    final values = await Future.wait<dynamic>([
      _auth.executeAuthorized(api.getLifecycle),
      _loadPermitted(api.getLegalEntities),
      _loadPermitted(api.getClients),
      _loadPermitted(api.getEmployees),
      _loadPermitted(api.getRoles),
      _loadPermitted(api.getPermissions),
      _loadPermitted(api.getAudit),
    ]);
    lifecycle = values[0] as OrganizationLifecycle;

    final legalResult = values[1] as _PermittedResult<List<LegalEntityModel>>;
    canViewLegalEntities = legalResult.allowed;
    legalEntities = legalResult.value ?? const [];

    final clientsResult =
        values[2] as _PermittedResult<List<CompanyClientModel>>;
    canViewClients = clientsResult.allowed;
    clients = clientsResult.value ?? const [];

    final employeesResult = values[3] as _PermittedResult<List<EmployeeModel>>;
    canViewEmployees = employeesResult.allowed;
    employees = employeesResult.value ?? const [];

    final rolesResult = values[4] as _PermittedResult<List<CompanyRoleModel>>;
    final permissionsResult =
        values[5] as _PermittedResult<List<CompanyPermissionModel>>;
    canViewAccess = rolesResult.allowed && permissionsResult.allowed;
    roles = rolesResult.value ?? const [];
    permissions = permissionsResult.value ?? const [];
    final auditResult =
        values[6] as _PermittedResult<List<CompanyAuditEntryModel>>;
    canViewAudit = auditResult.allowed;
    auditEntries = auditResult.value ?? const [];
    notifyListeners();
  }

  /// Возвращает пустой раздел при отсутствии права, не скрывая остальные данные компании.
  Future<_PermittedResult<T>> _loadPermitted<T>(
    Future<T> Function(String token) request,
  ) async {
    try {
      return _PermittedResult(true, await _auth.executeAuthorized(request));
    } on ApiException catch (exception) {
      if (exception.statusCode == 403) {
        return const _PermittedResult(false, null);
      }
      rethrow;
    }
  }

  Future<bool> saveLegalEntity(LegalEntityModel value, {bool create = false}) =>
      _mutate(() async {
        await _auth.executeAuthorized(
          (token) =>
              _workspaceApi!.saveLegalEntity(token, value, create: create),
        );
        legalEntities = await _auth.executeAuthorized(
          _workspaceApi!.getLegalEntities,
        );
      });

  Future<bool> deleteLegalEntity(String id) => _mutate(() async {
    await _auth.executeAuthorized(
      (token) => _workspaceApi!.deleteLegalEntity(token, id),
    );
    legalEntities = await _auth.executeAuthorized(
      _workspaceApi!.getLegalEntities,
    );
  });

  Future<bool> saveClient(CompanyClientModel value, {bool create = false}) =>
      _mutate(() async {
        await _auth.executeAuthorized(
          (token) => _workspaceApi!.saveClient(token, value, create: create),
        );
        clients = await _auth.executeAuthorized(_workspaceApi!.getClients);
      });

  Future<bool> deleteClient(String id) => _mutate(() async {
    await _auth.executeAuthorized(
      (token) => _workspaceApi!.deleteClient(token, id),
    );
    clients = await _auth.executeAuthorized(_workspaceApi!.getClients);
  });

  Future<bool> createEmployee(CreateEmployeeModel value) => _mutate(() async {
    await _auth.executeAuthorized(
      (token) => _workspaceApi!.createEmployee(token, value),
    );
    employees = await _auth.executeAuthorized(_workspaceApi!.getEmployees);
  });

  Future<bool> updateEmployee(String membershipId, UpdateEmployeeModel value) =>
      _mutate(() async {
        await _auth.executeAuthorized(
          (token) => _workspaceApi!.updateEmployee(token, membershipId, value),
        );
        employees = await _auth.executeAuthorized(_workspaceApi!.getEmployees);
      });

  Future<bool> deleteEmployee(String membershipId) => _mutate(() async {
    await _auth.executeAuthorized(
      (token) => _workspaceApi!.deleteEmployee(token, membershipId),
    );
    employees = await _auth.executeAuthorized(_workspaceApi!.getEmployees);
  });

  Future<bool> changeEmployeePassword(String membershipId, String password) =>
      _mutate(() async {
        await _auth.executeAuthorized(
          (token) => _workspaceApi!.changeEmployeePassword(
            token,
            membershipId,
            password,
          ),
        );
      });

  Future<bool> saveRole(CompanyRoleModel value, {bool create = false}) =>
      _mutate(() async {
        await _auth.executeAuthorized(
          (token) => _workspaceApi!.saveRole(token, value, create: create),
        );
        roles = await _auth.executeAuthorized(_workspaceApi!.getRoles);
      });

  Future<bool> deleteRole(String id) => _mutate(() async {
    await _auth.executeAuthorized(
      (token) => _workspaceApi!.deleteRole(token, id),
    );
    roles = await _auth.executeAuthorized(_workspaceApi!.getRoles);
  });

  /// Ищет реквизиты по ИНН для открытой формы. Не меняет общее состояние
  /// контроллера: ошибка возвращается вызывающему диалогу, а не в [error].
  Future<({CompanyRegistryRecord? record, String? error})> lookupByInn(
    String inn,
    CompanyRegistryScope scope,
  ) async {
    final registry = _registryApi;
    if (registry == null) {
      return (record: null, error: 'Поиск по ИНН недоступен.');
    }
    try {
      final record = await _auth.executeAuthorized(
        (token) => registry.lookupByInn(token, inn, scope),
      );
      return (record: record, error: null);
    } on ApiException catch (exception) {
      return (record: null, error: exception.message);
    } on Object {
      return (
        record: null,
        error: 'Не удалось выполнить поиск по ИНН. Проверьте подключение.',
      );
    }
  }

  Future<bool> _mutate(Future<void> Function() action) async {
    if (saving || _workspaceApi == null) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await action();
      saved = true;
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось сохранить изменения. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void markChanged() {
    if (saved) {
      saved = false;
      notifyListeners();
    }
  }

  Future<bool> save() async {
    final value = profile;
    if (value == null || saving) return false;
    saving = true;
    saved = false;
    error = null;
    notifyListeners();
    try {
      profile = await _auth.executeAuthorized(
        (token) => _api.updateProfile(token, value),
      );
      saved = true;
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось сохранить данные компании. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<CategoryDeletionImpact?> getCategoryDeletionImpact(
    String categoryClientId,
  ) async {
    error = null;
    notifyListeners();
    try {
      return await _auth.executeAuthorized(
        (token) => _api.getCategoryDeletionImpact(token, categoryClientId),
      );
    } on ApiException catch (exception) {
      error = exception.message;
      notifyListeners();
      return null;
    } on Object {
      error = 'Не удалось проверить содержимое категории.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> saveConfiguration(
    OrganizationOnboardingDraft draft, {
    List<String> deleteCategoryData = const [],
  }) async {
    if (saving) return false;
    saving = true;
    saved = false;
    error = null;
    notifyListeners();
    final retainedCategoryIds = draft.categories
        .map((category) => category.clientId)
        .toSet();
    _approvedCategoryDataDeletions.removeWhere(retainedCategoryIds.contains);
    final approvedDeletions =
        <String>{..._approvedCategoryDataDeletions, ...deleteCategoryData}
            .where((clientId) => !retainedCategoryIds.contains(clientId))
            .toList(growable: false);
    try {
      configuration = await _auth.executeAuthorized(
        (token) => _api.updateConfiguration(
          token,
          draft,
          deleteCategoryData: approvedDeletions,
        ),
      );
      profile = configuration!.company;
      _approvedCategoryDataDeletions.removeAll(approvedDeletions);
      saved = true;
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error =
          'Не удалось сохранить настройки организации. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _realtimeTimer?.cancel();
    unawaited(_realtimeSubscription?.cancel());
    if (_ownsRealtime) unawaited(_realtime?.close());
    if (_ownsApi) _api.close();
    super.dispose();
  }
}

final class _PermittedResult<T> {
  const _PermittedResult(this.allowed, this.value);

  final bool allowed;
  final T? value;
}
