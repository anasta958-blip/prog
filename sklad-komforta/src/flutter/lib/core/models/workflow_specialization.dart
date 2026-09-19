/// Подключаемый бизнес-модуль канбана. Стандартный режим хранится как `null`.
enum WorkflowSpecialization {
  standard(null),
  quote('quote'),
  quoteAndPrequote('quote_and_prequote'),
  order('order');

  const WorkflowSpecialization(this.apiValue);

  final String? apiValue;

  static WorkflowSpecialization fromApi(String? value) => switch (value) {
    'quote' => quote,
    'quote_and_prequote' => quoteAndPrequote,
    'order' => order,
    _ => standard,
  };
}

/// Действие создания документа, назначенное конкретному столбцу канбана.
enum WorkflowCreationAction {
  quote('quote', 'Создать КП'),
  prequote('prequote', 'Создать ПКП'),
  order('order', 'Создать комплектацию');

  const WorkflowCreationAction(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static WorkflowCreationAction? tryFromApi(String value) {
    for (final action in values) {
      if (action.apiValue == value) return action;
    }
    return null;
  }
}
