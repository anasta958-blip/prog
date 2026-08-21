/// Реквизиты организации, отображаемые в форме и живом предварительном просмотре.
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

/// Столбец канбана с устойчивым клиентским идентификатором для переходов.
final class WorkflowColumnDraft {
  WorkflowColumnDraft({
    required this.clientId,
    required this.name,
    required this.color,
  });
  String clientId;
  String name;
  String color;

  factory WorkflowColumnDraft.fromJson(Map<String, dynamic> json) =>
      WorkflowColumnDraft(
        clientId: json['clientId'] as String,
        name: json['name'] as String,
        color: json['color'] as String,
      );
  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'name': name,
    'color': color,
  };
}

/// Разрешённый направленный переход карточки между столбцами.
final class WorkflowTransitionDraft {
  WorkflowTransitionDraft({
    required this.fromClientId,
    required this.toClientId,
  });
  String fromClientId;
  String toClientId;
  factory WorkflowTransitionDraft.fromJson(Map<String, dynamic> json) =>
      WorkflowTransitionDraft(
        fromClientId: json['fromClientId'] as String,
        toClientId: json['toClientId'] as String,
      );
  Map<String, dynamic> toJson() => {
    'fromClientId': fromClientId,
    'toClientId': toClientId,
  };
}

/// Настраиваемый канбан организации.
final class WorkflowDraft {
  WorkflowDraft({
    required this.code,
    required this.name,
    required this.columns,
    required this.transitions,
  });
  String code;
  String name;
  List<WorkflowColumnDraft> columns;
  List<WorkflowTransitionDraft> transitions;
  factory WorkflowDraft.fromJson(Map<String, dynamic> json) => WorkflowDraft(
    code: json['code'] as String,
    name: json['name'] as String,
    columns: (json['columns'] as List<dynamic>)
        .map(
          (item) => WorkflowColumnDraft.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    transitions: (json['transitions'] as List<dynamic>)
        .map(
          (item) =>
              WorkflowTransitionDraft.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'columns': columns.map((item) => item.toJson()).toList(),
    'transitions': transitions.map((item) => item.toJson()).toList(),
  };
}

/// Группа товаров каталога.
final class CatalogGroupDraft {
  CatalogGroupDraft(this.name);
  String name;
  factory CatalogGroupDraft.fromJson(Map<String, dynamic> json) =>
      CatalogGroupDraft(json['name'] as String);
  Map<String, dynamic> toJson() => {'name': name};
}

/// Раздел категории каталога.
final class CatalogSectionDraft {
  CatalogSectionDraft({required this.name, required this.groups});
  String name;
  List<CatalogGroupDraft> groups;
  factory CatalogSectionDraft.fromJson(Map<String, dynamic> json) =>
      CatalogSectionDraft(
        name: json['name'] as String,
        groups: (json['groups'] as List<dynamic>)
            .map(
              (item) =>
                  CatalogGroupDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
  Map<String, dynamic> toJson() => {
    'name': name,
    'groups': groups.map((item) => item.toJson()).toList(),
  };
}

/// Выбранное системное поле карточки одной категории каталога.
final class CatalogFieldDraft {
  CatalogFieldDraft({
    required this.fieldCode,
    required this.isVisible,
    required this.isRequired,
  });

  String fieldCode;
  bool isVisible;
  bool isRequired;

  factory CatalogFieldDraft.fromJson(Map<String, dynamic> json) =>
      CatalogFieldDraft(
        fieldCode: json['fieldCode'] as String,
        isVisible: json['isVisible'] as bool,
        isRequired: json['isRequired'] as bool,
      );

  Map<String, dynamic> toJson() => {
    'fieldCode': fieldCode,
    'isVisible': isVisible,
    'isRequired': isRequired,
  };
}

/// Категория каталога с вложенной структурой.
final class CatalogCategoryDraft {
  CatalogCategoryDraft({
    required this.clientId,
    required this.name,
    required this.sections,
    required this.fields,
  });
  String clientId;
  String name;
  List<CatalogSectionDraft> sections;
  List<CatalogFieldDraft> fields;
  factory CatalogCategoryDraft.fromJson(Map<String, dynamic> json) =>
      CatalogCategoryDraft(
        clientId: json['clientId'] as String,
        name: json['name'] as String,
        sections: (json['sections'] as List<dynamic>)
            .map(
              (item) =>
                  CatalogSectionDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        fields: (json['fields'] as List<dynamic>)
            .map(
              (item) =>
                  CatalogFieldDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'name': name,
    'sections': sections.map((item) => item.toJson()).toList(),
    'fields': fields.map((item) => item.toJson()).toList(),
  };
}

/// Одно поле строки товара в конкретном бизнес-контексте.
final class EntityFieldDraft {
  EntityFieldDraft({
    required this.contextCode,
    required this.fieldCode,
    required this.label,
    required this.fieldType,
    required this.isVisible,
    required this.isRequired,
  });
  String contextCode;
  String fieldCode;
  String label;
  String fieldType;
  bool isVisible;
  bool isRequired;
  factory EntityFieldDraft.fromJson(Map<String, dynamic> json) =>
      EntityFieldDraft(
        contextCode: json['contextCode'] as String,
        fieldCode: json['fieldCode'] as String,
        label: json['label'] as String,
        fieldType: json['fieldType'] as String,
        isVisible: json['isVisible'] as bool,
        isRequired: json['isRequired'] as bool,
      );
  Map<String, dynamic> toJson() => {
    'contextCode': contextCode,
    'fieldCode': fieldCode,
    'label': label,
    'fieldType': fieldType,
    'isVisible': isVisible,
    'isRequired': isRequired,
  };
}

/// Пользовательская роль и её разрешения.
final class OnboardingRoleDraft {
  OnboardingRoleDraft({required this.name, required this.permissionCodes});
  String name;
  List<String> permissionCodes;
  factory OnboardingRoleDraft.fromJson(Map<String, dynamic> json) =>
      OnboardingRoleDraft(
        name: json['name'] as String,
        permissionCodes: (json['permissionCodes'] as List<dynamic>)
            .cast<String>(),
      );
  Map<String, dynamic> toJson() => {
    'name': name,
    'permissionCodes': permissionCodes,
  };
}

/// Значение пользовательского справочника.
final class DictionaryItemDraft {
  DictionaryItemDraft(this.value);
  String value;
  factory DictionaryItemDraft.fromJson(Map<String, dynamic> json) =>
      DictionaryItemDraft(json['value'] as String);
  Map<String, dynamic> toJson() => {'value': value};
}

/// Тип справочника и его упорядоченные значения.
final class DictionaryDraft {
  DictionaryDraft({
    required this.code,
    required this.name,
    required this.items,
  });
  String code;
  String name;
  List<DictionaryItemDraft> items;
  factory DictionaryDraft.fromJson(Map<String, dynamic> json) =>
      DictionaryDraft(
        code: json['code'] as String,
        name: json['name'] as String,
        items: (json['items'] as List<dynamic>)
            .map(
              (item) =>
                  DictionaryItemDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

/// Полный изменяемый черновик всех семи шагов onboarding.
final class OrganizationOnboardingDraft {
  OrganizationOnboardingDraft({
    required this.currentStep,
    required this.company,
    required this.workflows,
    required this.categories,
    required this.fields,
    required this.roles,
    required this.dictionaries,
  });
  int currentStep;
  CompanyProfileDraft company;
  List<WorkflowDraft> workflows;
  List<CatalogCategoryDraft> categories;
  List<EntityFieldDraft> fields;
  List<OnboardingRoleDraft> roles;
  List<DictionaryDraft> dictionaries;

  /// Создаёт локальную стартовую конфигурацию до появления tenant-схемы.
  factory OrganizationOnboardingDraft.initial() => OrganizationOnboardingDraft(
    currentStep: 1,
    company: CompanyProfileDraft(organizationName: ''),
    workflows: [],
    categories: [],
    fields: [],
    roles: [],
    dictionaries: [],
  );

  factory OrganizationOnboardingDraft.fromJson(
    Map<String, dynamic> json,
  ) => OrganizationOnboardingDraft(
    currentStep: json['currentStep'] as int,
    company: CompanyProfileDraft.fromJson(
      json['company'] as Map<String, dynamic>,
    ),
    workflows: (json['workflows'] as List<dynamic>)
        .map((item) => WorkflowDraft.fromJson(item as Map<String, dynamic>))
        .toList(),
    categories: (json['categories'] as List<dynamic>)
        .map(
          (item) => CatalogCategoryDraft.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    fields: (json['fields'] as List<dynamic>)
        .map((item) => EntityFieldDraft.fromJson(item as Map<String, dynamic>))
        .toList(),
    roles: (json['roles'] as List<dynamic>)
        .map(
          (item) => OnboardingRoleDraft.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    dictionaries: (json['dictionaries'] as List<dynamic>)
        .map((item) => DictionaryDraft.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'currentStep': currentStep,
    'company': company.toJson(),
    'workflows': workflows.map((item) => item.toJson()).toList(),
    'categories': categories.map((item) => item.toJson()).toList(),
    'fields': fields.map((item) => item.toJson()).toList(),
    'roles': roles.map((item) => item.toJson()).toList(),
    'dictionaries': dictionaries.map((item) => item.toJson()).toList(),
  };
}
