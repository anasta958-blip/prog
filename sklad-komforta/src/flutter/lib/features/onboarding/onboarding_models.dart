import 'package:sklad_komforta_app/features/company/company_models.dart';

export 'package:sklad_komforta_app/features/company/company_models.dart';

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
    List<WorkflowCategoryDraft>? categories,
  }) : categories = categories ?? <WorkflowCategoryDraft>[];
  String code;
  String name;
  List<WorkflowColumnDraft> columns;
  List<WorkflowTransitionDraft> transitions;
  List<WorkflowCategoryDraft> categories;
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
    categories: ((json['categories'] as List<dynamic>?) ?? const [])
        .map(
          (item) =>
              WorkflowCategoryDraft.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'columns': columns.map((item) => item.toJson()).toList(),
    'transitions': transitions.map((item) => item.toJson()).toList(),
    'categories': categories.map((item) => item.toJson()).toList(),
  };
}

/// Категория, доступная в конкретном канбане, и поля её карточки.
final class WorkflowCategoryDraft {
  WorkflowCategoryDraft({
    required this.categoryClientId,
    required this.fieldCodes,
  });

  String categoryClientId;
  List<String> fieldCodes;

  factory WorkflowCategoryDraft.fromJson(Map<String, dynamic> json) =>
      WorkflowCategoryDraft(
        categoryClientId: json['categoryClientId'] as String,
        fieldCodes: ((json['fieldCodes'] as List<dynamic>?) ?? const [])
            .cast<String>(),
      );

  Map<String, dynamic> toJson() => {
    'categoryClientId': categoryClientId,
    'fieldCodes': fieldCodes,
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
    this.dictionaryCode,
    this.label,
    this.fieldType,
  });

  String fieldCode;
  bool isVisible;
  bool isRequired;
  String? dictionaryCode;
  String? label;
  String? fieldType;

  factory CatalogFieldDraft.fromJson(Map<String, dynamic> json) =>
      CatalogFieldDraft(
        fieldCode: json['fieldCode'] as String,
        isVisible: json['isVisible'] as bool,
        isRequired: json['isRequired'] as bool,
        dictionaryCode: json['fieldCode'] == 'group'
            ? null
            : json['dictionaryCode'] as String?,
        label: json['label'] as String?,
        fieldType: json['fieldType'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'fieldCode': fieldCode,
    'isVisible': isVisible,
    'isRequired': isRequired,
    'dictionaryCode': fieldCode == 'group' ? null : dictionaryCode,
    'label': label,
    'fieldType': fieldType,
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

/// Настраиваемая связь между позициями двух категорий каталога.
final class CategoryDependencyDraft {
  CategoryDependencyDraft({
    required this.clientId,
    required this.sourceCategoryClientId,
    required this.targetCategoryClientId,
    required this.targetFieldCode,
  });

  String clientId;
  String sourceCategoryClientId;
  String targetCategoryClientId;
  String targetFieldCode;

  factory CategoryDependencyDraft.fromJson(Map<String, dynamic> json) =>
      CategoryDependencyDraft(
        clientId: json['clientId'] as String,
        sourceCategoryClientId: json['sourceCategoryClientId'] as String,
        targetCategoryClientId: json['targetCategoryClientId'] as String,
        targetFieldCode: json['targetFieldCode'] as String,
      );

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'sourceCategoryClientId': sourceCategoryClientId,
    'targetCategoryClientId': targetCategoryClientId,
    'targetFieldCode': targetFieldCode,
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
    this.dictionaryCode,
  });
  String contextCode;
  String fieldCode;
  String label;
  String fieldType;
  bool isVisible;
  bool isRequired;
  String? dictionaryCode;
  factory EntityFieldDraft.fromJson(Map<String, dynamic> json) =>
      EntityFieldDraft(
        contextCode: json['contextCode'] as String,
        fieldCode: json['fieldCode'] as String,
        label: json['label'] as String,
        fieldType: json['fieldType'] as String,
        isVisible: json['isVisible'] as bool,
        isRequired: json['isRequired'] as bool,
        dictionaryCode: json['dictionaryCode'] as String?,
      );
  Map<String, dynamic> toJson() => {
    'contextCode': contextCode,
    'fieldCode': fieldCode,
    'label': label,
    'fieldType': fieldType,
    'isVisible': isVisible,
    'isRequired': isRequired,
    'dictionaryCode': dictionaryCode,
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

/// Элемент безопасной формулы: поле, число, операция или скобка.
final class FormulaTokenDraft {
  FormulaTokenDraft({
    required this.tokenType,
    this.fieldCode,
    this.constantValue,
    this.operator,
  });

  String tokenType;
  String? fieldCode;
  num? constantValue;
  String? operator;

  factory FormulaTokenDraft.fromJson(Map<String, dynamic> json) =>
      FormulaTokenDraft(
        tokenType: json['tokenType'] as String,
        fieldCode: json['fieldCode'] as String?,
        constantValue: json['constantValue'] as num?,
        operator: json['operator'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'tokenType': tokenType,
    'fieldCode': fieldCode,
    'constantValue': constantValue,
    'operator': operator,
  };
}

/// Формула и число знаков после запятой в её результате.
final class FormulaDraft {
  FormulaDraft({List<FormulaTokenDraft>? tokens, this.decimalPlaces = 2})
    : tokens = tokens ?? <FormulaTokenDraft>[];

  List<FormulaTokenDraft> tokens;
  int decimalPlaces;

  factory FormulaDraft.fromJson(Map<String, dynamic> json) => FormulaDraft(
    tokens: ((json['tokens'] as List<dynamic>?) ?? const [])
        .map((item) => FormulaTokenDraft.fromJson(item as Map<String, dynamic>))
        .toList(),
    decimalPlaces: (json['decimalPlaces'] as num?)?.toInt() ?? 2,
  );

  Map<String, dynamic> toJson() => {
    'tokens': tokens.map((item) => item.toJson()).toList(),
    'decimalPlaces': decimalPlaces,
  };
}

/// Проверяемое условие событийного правила.
final class RuleConditionDraft {
  RuleConditionDraft({
    required this.fieldCode,
    required this.operator,
    this.comparisonValue,
  });

  String fieldCode;
  String operator;
  String? comparisonValue;

  factory RuleConditionDraft.fromJson(Map<String, dynamic> json) =>
      RuleConditionDraft(
        fieldCode: json['fieldCode'] as String,
        operator: json['operator'] as String,
        comparisonValue: json['comparisonValue'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'fieldCode': fieldCode,
    'operator': operator,
    'comparisonValue': comparisonValue,
  };
}

/// Действие, выполняемое после успешной проверки условий.
final class RuleActionDraft {
  RuleActionDraft({
    required this.actionType,
    this.targetFieldCode,
    this.sourceFieldCode,
    this.constantValue,
    this.booleanValue,
    this.dependencyClientId,
    this.aggregationOperation,
    this.aggregationTarget,
    this.multiplyByQuantity = false,
    this.quantityFieldCode,
    this.message,
    this.formula,
  });

  String actionType;
  String? targetFieldCode;
  String? sourceFieldCode;
  String? constantValue;
  bool? booleanValue;
  String? dependencyClientId;
  String? aggregationOperation;
  String? aggregationTarget;
  bool multiplyByQuantity;
  String? quantityFieldCode;
  String? message;
  FormulaDraft? formula;

  factory RuleActionDraft.fromJson(Map<String, dynamic> json) =>
      RuleActionDraft(
        actionType: json['actionType'] as String,
        targetFieldCode: json['targetFieldCode'] as String?,
        sourceFieldCode: json['sourceFieldCode'] as String?,
        constantValue: json['constantValue'] as String?,
        booleanValue: json['booleanValue'] as bool?,
        dependencyClientId: json['dependencyClientId'] as String?,
        aggregationOperation: json['aggregationOperation'] as String?,
        aggregationTarget: json['aggregationTarget'] as String?,
        multiplyByQuantity: json['multiplyByQuantity'] as bool? ?? false,
        quantityFieldCode: json['quantityFieldCode'] as String?,
        message: json['message'] as String?,
        formula: json['formula'] == null
            ? null
            : FormulaDraft.fromJson(json['formula'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
    'actionType': actionType,
    'targetFieldCode': targetFieldCode,
    'sourceFieldCode': sourceFieldCode,
    'constantValue': constantValue,
    'booleanValue': booleanValue,
    'dependencyClientId': dependencyClientId,
    'aggregationOperation': aggregationOperation,
    'aggregationTarget': aggregationTarget,
    'multiplyByQuantity': multiplyByQuantity,
    'quantityFieldCode': quantityFieldCode,
    'message': message,
    'formula': formula?.toJson(),
  };
}

/// Событийное правило для полей одной категории.
final class CalculationRuleDraft {
  CalculationRuleDraft({
    required this.clientId,
    required this.name,
    required this.categoryClientId,
    required this.eventType,
    required this.isEnabled,
    this.eventFieldCode,
    List<RuleConditionDraft>? conditions,
    List<RuleActionDraft>? actions,
  }) : conditions = conditions ?? <RuleConditionDraft>[],
       actions = actions ?? <RuleActionDraft>[];

  String clientId;
  String name;
  String categoryClientId;
  String eventType;
  bool isEnabled;
  String? eventFieldCode;
  List<RuleConditionDraft> conditions;
  List<RuleActionDraft> actions;

  factory CalculationRuleDraft.fromJson(Map<String, dynamic> json) =>
      CalculationRuleDraft(
        clientId: json['clientId'] as String,
        name: json['name'] as String,
        categoryClientId: json['categoryClientId'] as String,
        eventType: json['eventType'] as String,
        isEnabled: json['isEnabled'] as bool? ?? true,
        eventFieldCode: json['eventFieldCode'] as String?,
        conditions: ((json['conditions'] as List<dynamic>?) ?? const [])
            .map(
              (item) =>
                  RuleConditionDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        actions: ((json['actions'] as List<dynamic>?) ?? const [])
            .map(
              (item) => RuleActionDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'name': name,
    'categoryClientId': categoryClientId,
    'eventType': eventType,
    'isEnabled': isEnabled,
    'eventFieldCode': eventFieldCode,
    'conditions': conditions.map((item) => item.toJson()).toList(),
    'actions': actions.map((item) => item.toJson()).toList(),
  };
}

/// Поля неизменяемого денежного конвейера одной категории.
final class MoneyPipelineDraft {
  MoneyPipelineDraft({
    String? clientId,
    required this.categoryClientId,
    required this.basePriceFieldCode,
    required this.resultFieldCode,
    this.manualPriceFieldCode,
    this.markupFieldCode,
    this.discountFieldCode,
    this.quantityFieldCode,
    this.decimalPlaces = 2,
    this.includeResultInTotals = true,
  }) : clientId =
           clientId ?? 'pipeline_${DateTime.now().microsecondsSinceEpoch}';

  String clientId;
  String categoryClientId;
  String basePriceFieldCode;
  String? manualPriceFieldCode;
  String? markupFieldCode;
  String? discountFieldCode;
  String? quantityFieldCode;
  String resultFieldCode;
  int decimalPlaces;
  bool includeResultInTotals;

  factory MoneyPipelineDraft.fromJson(Map<String, dynamic> json) =>
      MoneyPipelineDraft(
        clientId:
            json['clientId'] as String? ??
            'pipeline_${json['categoryClientId']}_${json['resultFieldCode']}',
        categoryClientId: json['categoryClientId'] as String,
        basePriceFieldCode: json['basePriceFieldCode'] as String,
        manualPriceFieldCode: json['manualPriceFieldCode'] as String?,
        markupFieldCode: json['markupFieldCode'] as String?,
        discountFieldCode: json['discountFieldCode'] as String?,
        quantityFieldCode: json['quantityFieldCode'] as String?,
        resultFieldCode: json['resultFieldCode'] as String,
        decimalPlaces: (json['decimalPlaces'] as num?)?.toInt() ?? 2,
        includeResultInTotals: json['includeResultInTotals'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'categoryClientId': categoryClientId,
    'basePriceFieldCode': basePriceFieldCode,
    'manualPriceFieldCode': manualPriceFieldCode,
    'markupFieldCode': markupFieldCode,
    'discountFieldCode': discountFieldCode,
    'quantityFieldCode': quantityFieldCode,
    'resultFieldCode': resultFieldCode,
    'decimalPlaces': decimalPlaces,
    'includeResultInTotals': includeResultInTotals,
  };
}

/// Полный изменяемый черновик всех девяти шагов onboarding.
final class OrganizationOnboardingDraft {
  OrganizationOnboardingDraft({
    required this.currentStep,
    required this.company,
    required this.workflows,
    required this.categories,
    required this.fields,
    required this.roles,
    required this.dictionaries,
    required this.dependencies,
    List<CalculationRuleDraft>? rules,
    List<MoneyPipelineDraft>? moneyPipelines,
  }) : rules = rules ?? <CalculationRuleDraft>[],
       moneyPipelines = moneyPipelines ?? <MoneyPipelineDraft>[];
  int currentStep;
  CompanyProfileDraft company;
  List<WorkflowDraft> workflows;
  List<CatalogCategoryDraft> categories;
  List<EntityFieldDraft> fields;
  List<OnboardingRoleDraft> roles;
  List<DictionaryDraft> dictionaries;
  List<CategoryDependencyDraft> dependencies;
  List<CalculationRuleDraft> rules;
  List<MoneyPipelineDraft> moneyPipelines;

  /// Создаёт локальную стартовую конфигурацию до появления tenant-схемы.
  factory OrganizationOnboardingDraft.initial() => OrganizationOnboardingDraft(
    currentStep: 1,
    company: CompanyProfileDraft(organizationName: ''),
    workflows: [],
    categories: [],
    fields: [],
    roles: [],
    dictionaries: [],
    dependencies: [],
    rules: [],
    moneyPipelines: [],
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
    dependencies: ((json['dependencies'] as List<dynamic>?) ?? const [])
        .map(
          (item) =>
              CategoryDependencyDraft.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    rules: ((json['rules'] as List<dynamic>?) ?? const [])
        .map(
          (item) => CalculationRuleDraft.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
    moneyPipelines: ((json['moneyPipelines'] as List<dynamic>?) ?? const [])
        .map(
          (item) => MoneyPipelineDraft.fromJson(item as Map<String, dynamic>),
        )
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
    'dependencies': dependencies.map((item) => item.toJson()).toList(),
    'rules': rules.map((item) => item.toJson()).toList(),
    'moneyPipelines': moneyPipelines.map((item) => item.toJson()).toList(),
  };
}

/// Количество рабочих данных, которые зависят от удаляемой категории.
final class CategoryDeletionImpact {
  const CategoryDeletionImpact({
    required this.categoryClientId,
    required this.categoryName,
    required this.itemCount,
    required this.imageCount,
    required this.relationCount,
  });

  final String categoryClientId;
  final String categoryName;
  final int itemCount;
  final int imageCount;
  final int relationCount;

  bool get hasData => itemCount > 0 || imageCount > 0 || relationCount > 0;

  factory CategoryDeletionImpact.fromJson(Map<String, dynamic> json) =>
      CategoryDeletionImpact(
        categoryClientId: json['categoryClientId'] as String,
        categoryName: json['categoryName'] as String,
        itemCount: (json['itemCount'] as num).toInt(),
        imageCount: (json['imageCount'] as num).toInt(),
        relationCount: (json['relationCount'] as num).toInt(),
      );
}
