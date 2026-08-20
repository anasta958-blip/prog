/// Неизменяемая конфигурация одного запуска Flutter-клиента.
///
/// Значения задаются на этапе сборки через `--dart-define`, поэтому один и тот
/// же исходный код подключается к development, staging и production API без
/// захардкоженных платформенных адресов.
final class AppConfig {
  /// Создаёт уже проверенный набор параметров запуска.
  const AppConfig({required this.apiBaseUrl, required this.environment});

  /// Читает параметры из compile-time environment и использует безопасные
  /// локальные значения только для development-запуска без аргументов.
  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080/api/v1',
    ),
    environment: String.fromEnvironment(
      'APP_ENVIRONMENT',
      defaultValue: 'development',
    ),
  );

  /// Базовый URL версионированного REST API.
  final String apiBaseUrl;

  /// Логическое имя среды, используемое диагностикой и выбором конфигурации.
  final String environment;
}
