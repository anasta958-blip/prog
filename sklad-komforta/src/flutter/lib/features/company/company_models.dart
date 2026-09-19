/// Реквизиты организации, общие для первичной настройки и рабочего пространства.
final class CompanyProfileDraft {
  CompanyProfileDraft({required this.organizationName});

  String organizationName;
  String? companyType;
  String? legalName;
  String? inn;
  String? kpp;
  String? ogrn;
  String? address;
  String? phone;
  String? email;

  factory CompanyProfileDraft.fromJson(Map<String, dynamic> json) =>
      CompanyProfileDraft(organizationName: json['organizationName'] as String)
        ..companyType = json['companyType'] as String?
        ..legalName = json['legalName'] as String?
        ..inn = json['inn'] as String?
        ..kpp = json['kpp'] as String?
        ..ogrn = json['ogrn'] as String?
        ..address = json['address'] as String?
        ..phone = json['phone'] as String?
        ..email = json['email'] as String?;

  Map<String, dynamic> toJson() => {
    'organizationName': organizationName,
    'companyType': companyType,
    'legalName': legalName,
    'inn': inn,
    'kpp': kpp,
    'ogrn': ogrn,
    'address': address,
    'phone': phone,
    'email': email,
  };
}

/// Общий срок активности tenant-организации.
final class OrganizationLifecycle {
  const OrganizationLifecycle({
    required this.activeUntil,
    required this.isFrozen,
  });
  final DateTime activeUntil;
  final bool isFrozen;
  factory OrganizationLifecycle.fromJson(Map<String, dynamic> json) =>
      OrganizationLifecycle(
        activeUntil: DateTime.parse(json['activeUntil'] as String).toLocal(),
        isFrozen: json['isFrozen'] as bool? ?? false,
      );
}

/// Запись журнала изменений, уже дополненная сервером именем пользователя.
final class CompanyAuditEntryModel {
  const CompanyAuditEntryModel({
    required this.id,
    required this.entityType,
    required this.action,
    required this.createdAt,
    required this.diff,
    this.actorUserId,
    this.actorName,
    this.entityId,
  });

  final int id;
  final String? actorUserId;
  final String? actorName;
  final String entityType;
  final String? entityId;
  final String action;
  final DateTime createdAt;
  final Map<String, dynamic> diff;

  factory CompanyAuditEntryModel.fromJson(Map<String, dynamic> json) =>
      CompanyAuditEntryModel(
        id: json['id'] as int,
        actorUserId: json['actorUserId'] as String?,
        actorName: json['actorName'] as String?,
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String?,
        action: json['action'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        diff: Map<String, dynamic>.from(
          json['diff'] as Map<String, dynamic>? ?? const {},
        ),
      );
}

/// Юридическое лицо организации, доступное как будущий исполнитель.
final class LegalEntityModel {
  LegalEntityModel({
    required this.id,
    required this.name,
    required this.companyType,
  });
  final String id;
  String name;
  String companyType;
  String? legalName;
  String? inn;
  String? kpp;
  String? ogrn;
  String? address;
  String? phone;
  String? email;
  String? website;
  String? directorName;
  String? signatoryName;
  String? signatoryTitle;
  String? bankName;
  String? bankBik;
  String? bankAccount;
  String? corrAccount;
  String? introDefault;
  String? footerDefault;
  List<double?> vatRates = [20];
  bool isDefault = false;

  factory LegalEntityModel.fromJson(Map<String, dynamic> json) =>
      LegalEntityModel(
          id: json['id'] as String,
          name: json['name'] as String,
          companyType: json['companyType'] as String,
        )
        ..legalName = json['legalName'] as String?
        ..inn = json['inn'] as String?
        ..kpp = json['kpp'] as String?
        ..ogrn = json['ogrn'] as String?
        ..address = json['address'] as String?
        ..phone = json['phone'] as String?
        ..email = json['email'] as String?
        ..website = json['website'] as String?
        ..directorName = json['directorName'] as String?
        ..signatoryName = json['signatoryName'] as String?
        ..signatoryTitle = json['signatoryTitle'] as String?
        ..bankName = json['bankName'] as String?
        ..bankBik = json['bankBik'] as String?
        ..bankAccount = json['bankAccount'] as String?
        ..corrAccount = json['corrAccount'] as String?
        ..introDefault = json['introDefault'] as String?
        ..footerDefault = json['footerDefault'] as String?
        ..vatRates = ((json['vatRates'] as List<dynamic>?) ?? const [20])
            .map((value) => (value as num?)?.toDouble())
            .toList()
        ..isDefault = json['isDefault'] as bool? ?? false;

  Map<String, dynamic> toJson() => {
    'name': name,
    'companyType': companyType,
    'legalName': legalName,
    'inn': inn,
    'kpp': kpp,
    'ogrn': ogrn,
    'address': address,
    'phone': phone,
    'email': email,
    'website': website,
    'directorName': directorName,
    'signatoryName': signatoryName,
    'signatoryTitle': signatoryTitle,
    'bankName': bankName,
    'bankBik': bankBik,
    'bankAccount': bankAccount,
    'corrAccount': corrAccount,
    'introDefault': introDefault,
    'footerDefault': footerDefault,
    'vatRates': vatRates,
    'isDefault': isDefault,
  };
}

/// Клиент, хранящийся отдельно от карточек будущих КП и ПКП.
final class CompanyClientModel {
  CompanyClientModel({
    required this.id,
    required this.name,
    this.companyType = 'person',
  });
  final String id;
  String name;
  String companyType;
  String? companyName;
  String? legalName;
  String? inn;
  String? kpp;
  String? ogrn;
  String? contactName;
  String? phone;
  String? email;
  String? address;
  String? objectType;
  String? objectAddress;
  String? recipientName;
  String? salutation;
  String? proposalTitle;
  String? introText;
  String? bankName;
  String? bankBik;
  String? bankAccount;
  String? corrAccount;
  String? passportSeries;
  String? passportNumber;
  String? passportIssuedBy;
  String? note;

  factory CompanyClientModel.fromJson(Map<String, dynamic> json) =>
      CompanyClientModel(
          id: json['id'] as String,
          name: json['name'] as String,
          companyType: json['companyType'] as String? ?? 'person',
        )
        ..companyName = json['companyName'] as String?
        ..legalName = json['legalName'] as String?
        ..inn = json['inn'] as String?
        ..kpp = json['kpp'] as String?
        ..ogrn = json['ogrn'] as String?
        ..contactName = json['contactName'] as String?
        ..phone = json['phone'] as String?
        ..email = json['email'] as String?
        ..address = json['address'] as String?
        ..objectType = json['objectType'] as String?
        ..objectAddress = json['objectAddress'] as String?
        ..recipientName = json['recipientName'] as String?
        ..salutation = json['salutation'] as String?
        ..proposalTitle = json['proposalTitle'] as String?
        ..introText = json['introText'] as String?
        ..bankName = json['bankName'] as String?
        ..bankBik = json['bankBik'] as String?
        ..bankAccount = json['bankAccount'] as String?
        ..corrAccount = json['corrAccount'] as String?
        ..passportSeries = json['passportSeries'] as String?
        ..passportNumber = json['passportNumber'] as String?
        ..passportIssuedBy = json['passportIssuedBy'] as String?
        ..note = json['note'] as String?;

  Map<String, dynamic> toJson() => {
    'name': name,
    'companyType': companyType,
    'companyName': companyName,
    'legalName': legalName,
    'inn': inn,
    'kpp': kpp,
    'ogrn': ogrn,
    'contactName': contactName,
    'phone': phone,
    'email': email,
    'address': address,
    'objectType': objectType,
    'objectAddress': objectAddress,
    'recipientName': recipientName,
    'salutation': salutation,
    'proposalTitle': proposalTitle,
    'introText': introText,
    'bankName': bankName,
    'bankBik': bankBik,
    'bankAccount': bankAccount,
    'corrAccount': corrAccount,
    'passportSeries': passportSeries,
    'passportNumber': passportNumber,
    'passportIssuedBy': passportIssuedBy,
    'note': note,
  };
}

/// Роль вместе с правами и ролями, которыми она может руководить.
final class CompanyRoleModel {
  const CompanyRoleModel({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.permissionCodes,
    required this.subordinateRoleIds,
    this.cardVisibilityMode = 'own',
    this.cardVisibilityMembershipIds = const [],
  });
  final String id;
  final String name;
  final bool isSystem;
  final List<String> permissionCodes;
  final List<String> subordinateRoleIds;
  final String cardVisibilityMode;
  final List<String> cardVisibilityMembershipIds;
  factory CompanyRoleModel.fromJson(Map<String, dynamic> json) =>
      CompanyRoleModel(
        id: json['id'] as String,
        name: json['name'] as String,
        isSystem: json['isSystem'] as bool? ?? false,
        permissionCodes: (json['permissionCodes'] as List? ?? const [])
            .cast<String>(),
        subordinateRoleIds: (json['subordinateRoleIds'] as List? ?? const [])
            .cast<String>(),
        cardVisibilityMode: json['cardVisibilityMode'] as String? ?? 'own',
        cardVisibilityMembershipIds:
            (json['cardVisibilityMembershipIds'] as List? ?? const [])
                .cast<String>(),
      );
}

/// Назначаемое роли разрешение, сгруппированное сервером по рабочему разделу.
final class CompanyPermissionModel {
  const CompanyPermissionModel({
    required this.code,
    required this.name,
    required this.groupName,
  });
  final String code;
  final String name;
  final String groupName;
  factory CompanyPermissionModel.fromJson(Map<String, dynamic> json) =>
      CompanyPermissionModel(
        code: json['code'] as String,
        name: json['name'] as String,
        groupName: json['groupName'] as String,
      );
}

/// Сотрудник с единственной ролью и единственным непосредственным руководителем.
final class EmployeeModel {
  const EmployeeModel({
    required this.membershipId,
    required this.userId,
    required this.login,
    required this.displayName,
    required this.roleId,
    required this.roleName,
    required this.isDirector,
    required this.isActive,
    required this.createdAt,
    required this.activeUntil,
    this.supervisorMembershipId,
    this.email,
    this.phone,
    this.telegram,
    this.createdBy,
  });
  final String membershipId;
  final String userId;
  final String login;
  final String displayName;
  final String roleId;
  final String roleName;
  final String? supervisorMembershipId;
  final bool isDirector;
  final bool isActive;
  final String? email;
  final String? phone;
  final String? telegram;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime activeUntil;
  factory EmployeeModel.fromJson(Map<String, dynamic> json) => EmployeeModel(
    membershipId: json['membershipId'] as String,
    userId: json['userId'] as String,
    login: json['login'] as String,
    displayName: json['displayName'] as String,
    roleId: json['roleId'] as String,
    roleName: json['roleName'] as String,
    supervisorMembershipId: json['supervisorMembershipId'] as String?,
    isDirector: json['isDirector'] as bool? ?? false,
    isActive: json['isActive'] as bool? ?? false,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    telegram: json['telegram'] as String?,
    createdBy: json['createdBy'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    activeUntil: DateTime.parse(json['activeUntil'] as String).toLocal(),
  );
}

/// Данные обязательной учётной записи нового сотрудника.
final class CreateEmployeeModel {
  const CreateEmployeeModel({
    required this.login,
    required this.displayName,
    required this.temporaryPassword,
    required this.roleId,
    this.supervisorMembershipId,
    this.email,
    this.phone,
    this.telegram,
  });
  final String login;
  final String displayName;
  final String temporaryPassword;
  final String roleId;
  final String? supervisorMembershipId;
  final String? email;
  final String? phone;
  final String? telegram;
  Map<String, dynamic> toJson() => {
    'login': login,
    'displayName': displayName,
    'temporaryPassword': temporaryPassword,
    'roleId': roleId,
    'supervisorMembershipId': supervisorMembershipId,
    'email': email,
    'phone': phone,
    'telegram': telegram,
  };
}

/// Изменяемые данные существующего сотрудника без логина и срока организации.
final class UpdateEmployeeModel {
  const UpdateEmployeeModel({
    required this.displayName,
    required this.roleId,
    required this.isActive,
    this.supervisorMembershipId,
    this.email,
    this.phone,
    this.telegram,
  });

  final String displayName;
  final String roleId;
  final String? supervisorMembershipId;
  final bool isActive;
  final String? email;
  final String? phone;
  final String? telegram;

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'roleId': roleId,
    'supervisorMembershipId': supervisorMembershipId,
    'isActive': isActive,
    'email': email,
    'phone': phone,
    'telegram': telegram,
  };
}
