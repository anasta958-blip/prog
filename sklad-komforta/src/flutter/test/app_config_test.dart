import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';

void main() {
  test('публичный адрес локальной Web-сборки выводится из адреса API', () {
    const config = AppConfig(
      apiBaseUrl: 'http://192.168.1.25:8080/api/v1',
      environment: 'development',
    );

    expect(config.resolvedPublicAppBaseUrl, 'http://192.168.1.25:3000');
  });

  test('production API без порта использует тот же публичный хост', () {
    const config = AppConfig(
      apiBaseUrl: 'https://app.example.com/api/v1',
      environment: 'production',
    );

    expect(config.resolvedPublicAppBaseUrl, 'https://app.example.com');
  });

  test('явный публичный адрес имеет приоритет', () {
    const config = AppConfig(
      apiBaseUrl: 'https://api.example.com/api/v1',
      publicAppBaseUrl: 'https://quotes.example.com',
      environment: 'production',
    );

    expect(config.resolvedPublicAppBaseUrl, 'https://quotes.example.com');
  });
}
