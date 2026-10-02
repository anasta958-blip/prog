import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';

/// Описание системного поля, для которого backend реализует хранение и логику.
final class OnboardingFieldDefinition {
  const OnboardingFieldDefinition({
    required this.code,
    required this.label,
    required this.fieldType,
    required this.group,
    this.canBeRequired = true,
    this.isCalculated = false,
  });

  final String code;
  final String label;
  final String fieldType;
  final String group;
  final bool canBeRequired;
  final bool isCalculated;
}

/// Типы, из которых пользователь может создавать собственные поля карточки.
const customCatalogFieldTypes = <OnboardingFieldDefinition>[
  OnboardingFieldDefinition(
    code: 'text',
    label: 'Текст',
    fieldType: 'text',
    group: 'Тип поля',
  ),
  OnboardingFieldDefinition(
    code: 'number',
    label: 'Число',
    fieldType: 'number',
    group: 'Тип поля',
  ),
  OnboardingFieldDefinition(
    code: 'money',
    label: 'Денежное значение',
    fieldType: 'money',
    group: 'Тип поля',
  ),
  OnboardingFieldDefinition(
    code: 'percent',
    label: 'Процент',
    fieldType: 'percent',
    group: 'Тип поля',
  ),
  OnboardingFieldDefinition(
    code: 'dictionary',
    label: 'Справочник',
    fieldType: 'dictionary',
    group: 'Тип поля',
  ),
  OnboardingFieldDefinition(
    code: 'boolean',
    label: 'Флажок',
    fieldType: 'boolean',
    group: 'Тип поля',
  ),
  OnboardingFieldDefinition(
    code: 'relation',
    label: 'Связанные карточки',
    fieldType: 'relation',
    group: 'Тип поля',
  ),
  OnboardingFieldDefinition(
    code: 'calculated_money',
    label: 'Расчётная сумма',
    fieldType: 'calculated_money',
    group: 'Тип поля',
    canBeRequired: false,
    isCalculated: true,
  ),
];

/// Клиентское зеркало серверного реестра. Сервер остаётся источником истины и
/// отклоняет неизвестные коды или изменённые метаданные.
const onboardingFieldDefinitions = <OnboardingFieldDefinition>[
  OnboardingFieldDefinition(
    code: 'group',
    label: 'Группа',
    fieldType: 'dictionary',
    group: 'Основные',
  ),
  OnboardingFieldDefinition(
    code: 'name',
    label: 'Наименование',
    fieldType: 'text',
    group: 'Основные',
    canBeRequired: true,
  ),
  OnboardingFieldDefinition(
    code: 'marking',
    label: 'Маркировка / размер',
    fieldType: 'text',
    group: 'Основные',
  ),
  OnboardingFieldDefinition(
    code: 'note',
    label: 'Примечание',
    fieldType: 'text',
    group: 'Основные',
  ),
  OnboardingFieldDefinition(
    code: 'completion',
    label: 'Комплектация',
    fieldType: 'text',
    group: 'Основные',
  ),
  OnboardingFieldDefinition(
    code: 'quantity',
    label: 'Количество',
    fieldType: 'number',
    group: 'Основные',
    canBeRequired: true,
  ),
  OnboardingFieldDefinition(
    code: 'unit',
    label: 'Единица измерения',
    fieldType: 'dictionary',
    group: 'Основные',
  ),
  OnboardingFieldDefinition(
    code: 'supplier',
    label: 'Поставщик',
    fieldType: 'dictionary',
    group: 'Основные',
  ),
  OnboardingFieldDefinition(
    code: 'purchase_price',
    label: 'Закупочная цена',
    fieldType: 'money',
    group: 'Цены и расчёты',
  ),
  OnboardingFieldDefinition(
    code: 'minimal_price',
    label: 'Минимальная цена',
    fieldType: 'money',
    group: 'Цены и расчёты',
  ),
  OnboardingFieldDefinition(
    code: 'markup_value',
    label: 'Наценка',
    fieldType: 'percent',
    group: 'Цены и расчёты',
  ),
  OnboardingFieldDefinition(
    code: 'base_price',
    label: 'Цена',
    fieldType: 'money',
    group: 'Цены и расчёты',
  ),
  OnboardingFieldDefinition(
    code: 'discount_value',
    label: 'Скидка',
    fieldType: 'percent',
    group: 'Цены и расчёты',
  ),
  OnboardingFieldDefinition(
    code: 'line_total',
    label: 'Сумма',
    fieldType: 'calculated_money',
    group: 'Цены и расчёты',
    canBeRequired: false,
    isCalculated: true,
  ),
  OnboardingFieldDefinition(
    code: 'excluded_from_calc',
    label: 'Не считать',
    fieldType: 'boolean',
    group: 'Служебные',
  ),
  OnboardingFieldDefinition(
    code: 'technical_note',
    label: 'Техническая информация',
    fieldType: 'text',
    group: 'Служебные',
  ),
  OnboardingFieldDefinition(
    code: 'linked_services',
    label: 'Связанные позиции',
    fieldType: 'relation',
    group: 'Служебные',
  ),
  OnboardingFieldDefinition(
    code: 'shipment_status',
    label: 'Статус отгрузки',
    fieldType: 'dictionary',
    group: 'Комплектация',
  ),
];

final onboardingFieldByCode = <String, OnboardingFieldDefinition>{
  for (final definition in onboardingFieldDefinitions)
    definition.code: definition,
};

const defaultCatalogFieldCodes = <String>[
  'name',
  'marking',
  'quantity',
  'unit',
  'base_price',
];

/// Системные поля присутствуют в каждой категории и не удаляются из неё.
bool isFixedCatalogField(String code) =>
    defaultCatalogFieldCodes.contains(code);

bool isCustomCatalogField(String code) => code.startsWith('custom_');

String catalogFieldType(CatalogFieldDraft field) =>
    onboardingFieldByCode[field.fieldCode]?.fieldType ??
    field.fieldType ??
    'text';

OnboardingFieldDefinition catalogFieldDefinition(CatalogFieldDraft field) {
  final systemDefinition = onboardingFieldByCode[field.fieldCode];
  if (systemDefinition != null) return systemDefinition;
  final type = catalogFieldType(field);
  return OnboardingFieldDefinition(
    code: field.fieldCode,
    label: catalogFieldLabel(field),
    fieldType: type,
    group: 'Пользовательские',
    canBeRequired: type != 'calculated_money',
    isCalculated: type == 'calculated_money',
  );
}

/// Пользовательское название поля с совместимым fallback для старых черновиков.
String catalogFieldLabel(CatalogFieldDraft field) {
  final customLabel = field.label?.trim();
  if (customLabel != null && customLabel.isNotEmpty) return customLabel;
  return onboardingFieldByCode[field.fieldCode]?.label ?? '';
}
