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
  testWidgets('кружок радиокнопки выбирает и снимает выбор варианта', (
    tester,
  ) async {
    await _open(tester, (_) async => _ok(_quote(selected: true)));
    final radio = find.byType(Radio<String>).first;

    await tester.tap(radio);
    await tester.pumpAndSettle();
    expect(find.text('Выбран: Оптимальный вариант с монтажом'), findsOneWidget);

    await tester.tap(radio);
    await tester.pumpAndSettle();
    expect(find.text('Вариант не выбран'), findsOneWidget);

    await tester.tap(radio);
    await tester.pumpAndSettle();
    expect(find.text('Выбран: Оптимальный вариант с монтажом'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('Выберите хотя бы один вариант.'), findsOneWidget);
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

  testWidgets('шапка, частичный выбор и сворачивание типа', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <Map<String, dynamic>>[];
    await _open(tester, (request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _ok(_quote(selected: true));
    }, twoTypes: true);

    expect(find.text('ЗАКАЗЧИК'), findsOneWidget);
    expect(find.text('Тестовый заказчик'), findsOneWidget);
    expect(find.text('ИСПОЛНИТЕЛЬ'), findsOneWidget);
    expect(find.text('Тестовый исполнитель'), findsOneWidget);
    expect(find.text('Вариант не выбран'), findsNWidgets(2));
    expect(find.text('Бойлер'), findsOneWidget);

    // Дополнительная информация — сразу под шапкой, выше типов.
    expect(
      tester
          .getTopLeft(
            find.byKey(const Key('client-quote-additional-information')),
          )
          .dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('client-quote-type-type-1'))).dy,
      ),
    );

    // Нажатие на полосу типа не сворачивает его — только стрелка.
    await tester.tap(find.text('Горячая вода'));
    await tester.pumpAndSettle();
    expect(find.text('Бойлер'), findsOneWidget);
    await tester.tap(find.byKey(const Key('client-quote-type-toggle-type-2')));
    await tester.pumpAndSettle();
    expect(find.text('Бойлер'), findsNothing);
    await tester.tap(find.byKey(const Key('client-quote-type-toggle-type-2')));
    await tester.pumpAndSettle();
    expect(find.text('Бойлер'), findsOneWidget);

    // Вариант сворачивается своей стрелкой; нажатие на полосу его не сворачивает.
    await tester.tap(
      find.byKey(const Key('client-quote-variant-toggle-variant-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Бойлер'), findsNothing);
    expect(find.text('Базовый'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('client-quote-variant-toggle-variant-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Бойлер'), findsOneWidget);

    // Вариант выбирается только в первом типе; повторное нажатие снимает выбор.
    await tester.tap(find.text('Оптимальный вариант с монтажом'));
    await tester.pumpAndSettle();
    expect(find.text('Выбран: Оптимальный вариант с монтажом'), findsOneWidget);
    await tester.tap(find.text('Оптимальный вариант с монтажом'));
    await tester.pumpAndSettle();
    expect(find.text('Вариант не выбран'), findsNWidgets(2));
    await tester.tap(find.text('Оптимальный вариант с монтажом'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Подтвердить выбор'));
    await tester.pumpAndSettle();
    expect(requests.single['variants'], [
      {'proposalTypeId': 'type-1', 'variantId': 'variant-1'},
    ]);
    expect(find.text('Выбор сохранён'), findsOneWidget);
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
    await tester.ensureVisible(find.byType(Radio<String>).first);
    await tester.tap(find.byType(Radio<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить выбор'));
    await tester.pumpAndSettle();
    expect(find.text('Выбор сохранён'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('configured parties appear once before proposal types', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final quote = _quote(twoTypes: true);
    quote['clientName'] = null;
    quote['executorName'] = '';
    quote['headerDocument'] = {
      'template': {
        'blocks': [
          {
            'id': 'client',
            'kind': 'client',
            'x': 30,
            'y': 30,
            'width': 320,
            'height': 150,
          },
          {
            'id': 'executor',
            'kind': 'executor',
            'x': 400,
            'y': 75,
            'width': 320,
            'height': 150,
          },
        ],
      },
      'blocks': [
        {
          'id': 'client',
          'title': 'Заказчик',
          'lines': ['Название: Тестовый заказчик'],
          'tables': [],
        },
        {
          'id': 'executor',
          'title': 'Исполнитель',
          'lines': ['Название: Тестовый исполнитель'],
          'tables': [],
        },
      ],
    };
    for (final type in quote['proposalTypes'] as List) {
      for (final variant
          in (type as Map<String, dynamic>)['variants'] as List) {
        (variant as Map<String, dynamic>)['document'] = {
          'template': {
            'blocks': [
              {
                'id': 'totals',
                'kind': 'totals',
                'x': 30,
                'y': 30,
                'width': 320,
                'height': 150,
              },
            ],
          },
          'blocks': [
            {
              'id': 'totals',
              'title': 'Итоги',
              'lines': ['Итого: 120 000 ₽'],
              'tables': [],
            },
          ],
        };
      }
    }
    final client = MockClient(
      (request) async => _ok({
        'sessionToken': 'client-session',
        'expiresAt': '2030-01-01T00:00:00Z',
        'quote': quote,
      }),
    );
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

    expect(find.text('Название: Тестовый заказчик'), findsOneWidget);
    expect(find.text('Название: Тестовый исполнитель'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Заказчик')).dy,
      tester.getTopLeft(find.text('Исполнитель')).dy,
    );
    expect(
      tester.getTopLeft(find.text('Название: Тестовый заказчик')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('client-quote-type-type-1'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh loads the current saved document', (tester) async {
    var currentRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        return _ok({
          'sessionToken': 'client-session',
          'expiresAt': '2030-01-01T00:00:00Z',
          'quote': _quote(),
        });
      }
      if (request.url.path.endsWith('/current')) {
        currentRequests++;
        expect(request.headers['X-Quote-Client-Session'], 'client-session');
        return _ok({..._quote(), 'title': 'Обновлённое предложение'});
      }
      return _failure(404, 'Неизвестный запрос');
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
    await tester.tap(find.byTooltip('Обновить предложение'));
    await tester.pumpAndSettle();

    expect(currentRequests, 1);
    expect(find.text('Обновлённое предложение'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('variants in one type have distinct headers', (tester) async {
    final quote = _quote();
    final type = (quote['proposalTypes'] as List).first as Map<String, dynamic>;
    final variants = type['variants'] as List;
    variants.add(
      Map<String, Object>.from(variants.first as Map)
        ..['id'] = 'variant-2'
        ..['name'] = 'Базовый',
    );
    final client = MockClient(
      (_) async => _ok({
        'sessionToken': 'client-session',
        'expiresAt': '2030-01-01T00:00:00Z',
        'quote': quote,
      }),
    );
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

    Material header(String id) => tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(Key('client-quote-variant-$id')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(header('variant-1').color, isNot(header('variant-2').color));
    expect((header('variant-2').shape as Border).left.width, 4);
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
  Future<http.Response> Function(http.Request) submit, {
  bool twoTypes = false,
}) async {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/login')) {
      return _ok({
        'sessionToken': 'client-session',
        'expiresAt': '2030-01-01T00:00:00Z',
        'quote': _quote(twoTypes: twoTypes),
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

Map<String, dynamic> _quote({bool selected = false, bool twoTypes = false}) => {
  'id': 'quote-1',
  'quoteKind': 'quote',
  'title': 'Поставка и монтаж оборудования',
  'executorName': 'Тестовый исполнитель',
  'clientName': 'Тестовый заказчик',
  'additionalInformation': twoTypes ? 'Монтаж в течение 5 дней' : null,
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
    if (twoTypes)
      {
        'id': 'type-2',
        'name': 'Горячая вода',
        'selectedVariantId': null,
        'variants': [
          {
            'id': 'variant-2',
            'name': 'Базовый',
            'vatRate': 20,
            'subtotal': 50000,
            'vatAmount': 10000,
            'total': 60000,
            'categories': [
              {
                'name': 'Оборудование',
                'sections': [
                  {
                    'name': 'Бойлеры',
                    'positions': [
                      {
                        'name': 'Бойлер',
                        'marking': 'B-100',
                        'unit': 'шт',
                        'quantity': 1,
                        'unitPrice': 50000,
                        'lineTotal': 50000,
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
