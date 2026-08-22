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
    code: 'price_type',
    label: 'Тип цены',
    fieldType: 'enum',
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
    code: 'invoice_check',
    label: 'Проверка счёта',
    fieldType: 'enum',
    group: 'Комплектация',
  ),
  OnboardingFieldDefinition(
    code: 'shipment_status',
    label: 'Статус отгрузки',
    fieldType: 'enum',
    group: 'Комплектация',
  ),
];

final onboardingFieldByCode = <String, OnboardingFieldDefinition>{
  for (final definition in onboardingFieldDefinitions)
    definition.code: definition,
};

const defaultCatalogFieldCodes = <String>[
  'group',
  'name',
  'marking',
  'note',
  'quantity',
  'unit',
  'supplier',
  'purchase_price',
  'minimal_price',
  'base_price',
  'excluded_from_calc',
  'linked_services',
];
