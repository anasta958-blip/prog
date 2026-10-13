/// Неизменяемая конфигурация одного запуска Flutter-клиента.
///
/// Значения задаются на этапе сборки через `--dart-define`, поэтому один и тот
/// же исходный код подключается к development, staging и production API без
/// захардкоженных платформенных адресов.
final class AppConfig {
  /// Создаёт уже проверенный набор параметров запуска.
  const AppConfig({
    required this.apiBaseUrl,
    required this.environment,
    this.publicAppBaseUrl = '',
  });

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
    publicAppBaseUrl: String.fromEnvironment(
      'PUBLIC_APP_BASE_URL',
      defaultValue: '',
    ),
  );

  /// Базовый URL версионированного REST API.
  final String apiBaseUrl;

  /// Логическое имя среды, используемое диагностикой и выбором конфигурации.
  final String environment;

  /// Публичный адрес Web-приложения, который передаётся внешнему клиенту.
  final String publicAppBaseUrl;

  /// Использует явный Web-адрес либо безопасно выводит его из адреса API.
  /// Для локального API на 8080 Flutter Web запускается на согласованном 3000.
  String get resolvedPublicAppBaseUrl => resolvePublicAppBaseUrl(Uri.base);

  /// Относительный Web API использует origin открытой страницы, не пустой host.
  String resolvePublicAppBaseUrl(Uri pageUri) {
    final configured = publicAppBaseUrl.trim();
    if (configured.isNotEmpty) return configured;
    final api = Uri.parse(apiBaseUrl);
    if (!api.hasScheme && !api.hasAuthority) {
      return Uri(
        scheme: pageUri.scheme,
        host: pageUri.host,
        port: pageUri.hasPort ? pageUri.port : null,
      ).toString();
    }
    return Uri(
      scheme: api.scheme,
      host: api.host,
      port: api.hasPort ? (api.port == 8080 ? 3000 : api.port) : null,
    ).toString();
  }
}
