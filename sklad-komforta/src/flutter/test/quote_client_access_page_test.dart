import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/features/quotes/quote_client_access_api.dart';
import 'package:sklad_komforta_app/features/quotes/quote_client_access_page.dart';

const _config = AppConfig(
  apiBaseUrl: 'https://example.test/api/v1',
  environment: 'test',
);

void main() {
  testWidgets('ошибка выбора видна, повторная попытка сохраняет выбор', (
    tester,
  ) async {
    var attempts = 0;
    final requests = <Map<String, dynamic>>[];
    await _open(tester, (request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (attempts++ == 0) {
        return _failure(409, 'Выбранный вариант недоступен.');
      }
      return _ok(_quote(selected: true));
    });

    await tester.tap(find.text('Подтвердить выбор'));
    await tester.pumpAndSettle();
    expect(
      find.text('Выберите по одному варианту в каждом типе.'),
      findsOneWidget,
    );
    expect(requests, isEmpty);

    await tester.tap(find.byType(Radio<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить выбор'));
    await tester.pumpAndSettle();
    expect(find.text('Выбранный вариант недоступен.'), findsOneWidget);

    await tester.tap(find.text('Подтвердить выбор'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.first, requests.last);
    expect(find.text('Выбор сохранён'), findsOneWidget);
    expect(find.text('Выбранный вариант недоступен.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('клиентское предложение помещается на экране 360 пикселей', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _open(tester, (_) async => _ok(_quote(selected: true)));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Radio<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить выбор'));
    await tester.pumpAndSettle();
    expect(find.text('Выбор сохранён'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('истёкшая сессия позволяет войти повторно и сохранить выбор', (
    tester,
  ) async {
    var attempts = 0;
    await _open(tester, (_) async {
      if (attempts++ == 0) {
        return _failure(401, 'Сессия истекла. Введите пароль повторно.');
      }
      return _ok(_quote(selected: true));
    });
    await tester.tap(find.byType(Radio<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить выбор'));
    await tester.pumpAndSettle();
    expect(
      find.text('Сессия истекла. Введите пароль повторно.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    await _login(tester);
    await tester.tap(find.text('Подтвердить выбор'));
    await tester.pumpAndSettle();
    expect(find.text('Выбор сохранён'), findsOneWidget);
    expect(attempts, 2);
  });
}

Future<void> _open(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) submit,
) async {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/login')) {
      return _ok({
        'sessionToken': 'client-session',
        'expiresAt': '2030-01-01T00:00:00Z',
        'quote': _quote(),
      });
    }
    return submit(request);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: QuoteClientAccessPage(
        config: _config,
        accessToken: 'test-link',
        api: QuoteClientAccessApi(_config, client: client),
      ),
    ),
  );
  await _login(tester);
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'test-password');
  await tester.tap(find.text('Открыть предложение'));
  await tester.pumpAndSettle();
}

http.Response _ok(Object data) => http.Response(
  jsonEncode({'ok': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _failure(int status, String message) => http.Response(
  jsonEncode({
    'ok': false,
    'error': {'code': 'test_failure', 'message': message},
  }),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _quote({bool selected = false}) => {
  'id': 'quote-1',
  'quoteKind': 'quote',
  'title': 'Поставка и монтаж оборудования',
  'executorName': 'Тестовый исполнитель',
  'selectionMode': 'variant',
  'updatedAt': '2026-09-13T10:00:00Z',
  'selectionSubmittedAt': selected ? '2026-09-13T10:00:00Z' : null,
  'proposalTypes': [
    {
      'id': 'type-1',
      'name': 'Кондиционирование',
      'selectedVariantId': selected ? 'variant-1' : null,
      'variants': [
        {
          'id': 'variant-1',
          'name': 'Оптимальный вариант с монтажом',
          'vatRate': 20,
          'subtotal': 100000,
          'vatAmount': 20000,
          'total': 120000,
          'categories': [
            {
              'name': 'Оборудование',
              'sections': [
                {
                  'name': 'Внутренние блоки',
                  'positions': [
                    {
                      'name': 'Кондиционер',
                      'marking': 'AC-24',
                      'unit': 'шт',
                      'quantity': 1,
                      'unitPrice': 100000,
                      'lineTotal': 100000,
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};
