import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/quotes/quote_client_access_api.dart';

void main() {
  test('действующая ссылка возвращает сохранённые токен и пароль', () {
    final status = QuoteClientAccessStatus.fromJson({
      'isActive': true,
      'createdAt': '2026-09-27T10:00:00Z',
      'expiresAt': '2026-10-04T10:00:00Z',
      'lastAccessedAt': null,
      'accessToken': 'token-value',
      'password': 'Pa55word',
    });

    final secrets = status.secrets;
    expect(secrets?.accessToken, 'token-value');
    expect(secrets?.password, 'Pa55word');
    expect(secrets?.expiresAt, DateTime.parse('2026-10-04T10:00:00Z'));
  });

  test('ссылка без сохранённых секретов или отозванная их не показывает', () {
    final legacy = QuoteClientAccessStatus.fromJson({
      'isActive': true,
      'expiresAt': '2026-10-04T10:00:00Z',
    });
    final revoked = QuoteClientAccessStatus.fromJson({
      'isActive': false,
      'accessToken': 'token-value',
      'password': 'Pa55word',
    });

    expect(legacy.secrets, isNull);
    expect(revoked.secrets, isNull);
  });
}
