/// Ошибка REST API со стабильным машинным кодом и безопасным сообщением.
class ApiException implements Exception {
  const ApiException(this.code, this.message, [this.statusCode, this.target]);

  final String code;
  final String message;
  final int? statusCode;
  final String? target;

  @override
  String toString() => message;
}
