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
