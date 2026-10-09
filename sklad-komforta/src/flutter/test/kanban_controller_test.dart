import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/features/quotes/quote_client_access_api.dart';
import 'package:sklad_komforta_app/features/quotes/quote_editor_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/realtime_client.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_api.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_page.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_api.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
  );

  testWidgets('карточка комплектации: сводка, дозаказ и связь с КП', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _authorizedController(config);
    final gateway = _MemoryKanbanGateway()
      ..specialization = WorkflowSpecialization.order;
    gateway.cards['quote-first'] = [
      KanbanCard.fromJson({
        'id': 'order-card',
        'number': 15,
        'workflowId': 'board-quotes',
        'columnId': 'quote-first',
        'title': 'Лесная, 5',
        'values': <String, dynamic>{},
        'createdByName': 'Иван Бочаров',
        'createdAt': '2026-10-01T09:00:00Z',
        'updatedAt': '2026-10-01T10:00:00Z',
        'order': {
          'clientName': 'Петров Пётр',
          'managerName': 'Иван Бочаров',
          'objectType': 'Дом',
          'positionCount': 4,
          'reorderCount': 1,
          'invoiceCount': 2,
          'sourceQuoteNumber': 7,
        },
        'linkedCards': [
          {
            'boardId': 'board-sales',
            'boardName': 'Предложения',
            'specialization': 'quote',
            'cardId': 'quote-card',
            'cardNumber': 7,
            'columnName': 'Завершено',
          },
        ],
      }),
    ];
    final outbound = _MemoryOutboundGateway();
    final controller = KanbanController(config, auth, gateway: gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KanbanPage(
            controller: controller,
            config: config,
            authController: auth,
            outboundGatewayFactory: (_) => outbound,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Комплектация №15 · из КП №7'), findsOneWidget);
    expect(find.text('Позиций: 4'), findsOneWidget);
    expect(find.text('Дозаказ: 1'), findsOneWidget);
    expect(find.text('Счетов: 2'), findsOneWidget);
    expect(find.text('В КП №7 · Завершено'), findsOneWidget);
    expect(find.textContaining('Дом'), findsOneWidget);

    // Меню карточки: отправка PDF в настроенные способы.
    await tester.tap(find.byTooltip('Действия карточки'));
    await tester.pumpAndSettle();
    expect(find.text('В Telegram'), findsOneWidget);
    await tester.tap(find.text('На почту'));
    await tester.pumpAndSettle();
    expect(outbound.sent, [
      ('board-quotes', 'order-card', OutboundChannel.email),
    ]);
    expect(
      find.textContaining('отправлено на boss@example.com'),
      findsOneWidget,
    );

    controller.dispose();
    auth.dispose();
  });

  testWidgets('карточка КП показывает стороны, выбор, просмотры и историю', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _authorizedController(config);
    final gateway = _MemoryKanbanGateway()
      ..specialization = WorkflowSpecialization.quote;
    gateway.cards['quote-first'] = [
      KanbanCard.fromJson({
        'id': 'quote-card',
        'number': 72,
        'workflowId': 'board-quotes',
        'columnId': 'quote-first',
        'categoryId': null,
        'title': 'Шелепихинская набережная, д.38к5',
        'values': <String, dynamic>{},
        'createdBy': 'user-1',
        'createdByName': 'Иван Бочаров',
        'createdByRole': 'Менеджер',
        'createdAt': '2026-06-22T09:41:00Z',
        'updatedBy': 'user-1',
        'updatedByName': 'Иван Бочаров',
        'updatedByRole': 'Менеджер',
        'updatedAt': '2026-06-22T16:41:00Z',
        'movedBy': 'user-2',
        'movedByName': 'Скорняков Павел',
        'movedByRole': 'РОП',
        'movedAt': '2026-06-29T11:27:00Z',
        'quote': {
          'quoteKind': 'quote',
          'clientName': 'Скорняков Павел',
          'executorName': 'ООО Комфорт',
          'selectionMode': 'variant',
          'selections': [
            {
              'proposalTypeName': 'Фанкойлы',
              'variantName': 'Фанкойлы',
              'total': 904250,
            },
          ],
          'linkViews': 12,
          'lastViewedAt': '2026-06-25T10:00:00Z',
        },
      }),
    ];
    gateway.cards['quote-first']!.add(
      KanbanCard.fromJson({
        'id': 'quote-empty',
        'number': 73,
        'workflowId': 'board-quotes',
        'columnId': 'quote-first',
        'title': 'Новый объект',
        'values': <String, dynamic>{},
        'createdAt': '2026-06-23T09:41:00Z',
        'updatedAt': '2026-06-23T09:41:00Z',
        'quote': {
          'quoteKind': 'prequote',
          'selectionMode': 'variant',
          'selections': <Object>[],
          'linkViews': 0,
        },
      }),
    );
    gateway.selectedTotal = 904250;
    final controller = KanbanController(config, auth, gateway: gateway);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KanbanPage(
            controller: controller,
            config: config,
            authController: auth,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Шелепихинская набережная, д.38к5'), findsOneWidget);
    expect(find.text('Не выбрано'), findsOneWidget);
    expect(find.text('Ссылку ещё не открывали'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('kanban-column-total-quote-first')),
          )
          .data,
      startsWith('Выбрано на 904'),
    );
    expect(find.text('КП №72'), findsOneWidget);
    expect(find.textContaining('ООО Комфорт'), findsOneWidget);
    expect(find.textContaining('Скорняков Павел'), findsWidgets);
    expect(find.textContaining('Иван Бочаров · Менеджер'), findsWidgets);
    expect(find.text('Фанкойлы: Фанкойлы'), findsOneWidget);
    expect(find.textContaining('904'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('kanban-quote-views-quote-card')))
          .data,
      startsWith('Просмотров ссылки: 12'),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('kanban-quote-moved-quote-card')))
          .data,
      startsWith('Статус изменил: Скорняков Павел · РОП'),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('kanban-quote-updated-quote-card')),
          )
          .data,
      startsWith('Изменил: Иван Бочаров · Менеджер'),
    );

    // Поиск уходит на сервер после паузы ввода и работает по номеру.
    await tester.enterText(find.byKey(const Key('kanban-card-search')), '73');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(gateway.lastSearch, '73');
    expect(find.text('Новый объект'), findsOneWidget);
    expect(find.text('Шелепихинская набережная, д.38к5'), findsNothing);
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pumpAndSettle();
    expect(gateway.lastSearch, isNull);
    expect(find.text('Шелепихинская набережная, д.38к5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
    auth.dispose();
  });

  for (final create in [false, true]) {
    testWidgets(
      'quote editor hides toolbar and pins source board (create=$create)',
      (tester) async {
        final auth = _authorizedController(config);
        final gateway = _MemoryKanbanGateway()
          ..specialization = WorkflowSpecialization.quoteAndPrequote
          ..creationActions = [WorkflowCreationAction.prequote];
        final controller = KanbanController(config, auth, gateway: gateway);
        await controller.initialize();
        if (!create) {
          await controller.saveCard(
            KanbanCardDraft(
              columnId: 'quote-first',
              categoryId: 'equipment',
              title: 'Предложение',
            ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: KanbanPage(
                controller: controller,
                config: config,
                authController: auth,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Рабочий канбан'), findsOneWidget);
        await tester.tap(
          find.text(
            create ? WorkflowCreationAction.prequote.label : 'Предложение',
          ),
        );
        await tester.pump();
        expect(find.byType(QuoteEditorPage), findsOneWidget);
        expect(find.text('Рабочий канбан'), findsNothing);
        expect(find.text('Карточки пользователя'), findsNothing);
        expect(find.byTooltip('Обновить'), findsNothing);
        final editor = tester.widget<QuoteEditorPage>(
          find.byType(QuoteEditorPage),
        );
        expect(editor.board.id, 'board-quotes');
        await controller.selectBoard('board-orders');
        await tester.pump();
        expect(
          tester.widget<QuoteEditorPage>(find.byType(QuoteEditorPage)).board.id,
          'board-quotes',
        );
        editor.onBack();
        await tester.pumpAndSettle();
        expect(find.byType(QuoteEditorPage), findsNothing);
        expect(find.text('Рабочий канбан'), findsOneWidget);
        expect(controller.board?.id, 'board-orders');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        auth.dispose();
      },
    );
  }

  testWidgets(
    'quote menu exposes link and shared dialog loads existing secrets',
    (tester) async {
      final auth = _authorizedController(config);
      final gateway = _MemoryKanbanGateway()
        ..specialization = WorkflowSpecialization.quote;
      final controller = KanbanController(config, auth, gateway: gateway);
      await controller.initialize();
      await controller.saveCard(
        KanbanCardDraft(
          columnId: 'quote-first',
          categoryId: 'equipment',
          title: 'КП',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanPage(
              controller: controller,
              config: config,
              authController: auth,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Действия карточки'));
      await tester.pumpAndSettle();
      expect(find.text('Ссылка'), findsOneWidget);
      expect(find.text('В архив'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      final api = QuoteClientAccessApi(
        config,
        client: MockClient((request) async {
          final extending = request.url.path.endsWith('/client-access/extend');
          expect(request.method, extending ? 'POST' : 'GET');
          if (extending) expect(jsonDecode(request.body)['additionalDays'], 7);
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'isActive': true,
                'accessToken': 'existing-token',
                'password': 'existing-password',
                'createdAt': '2026-09-01T12:00:00Z',
                'expiresAt': extending
                    ? '2027-09-08T12:00:00Z'
                    : '2027-09-01T12:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showQuoteClientAccessDialog(
                  context: context,
                  config: config,
                  auth: auth,
                  boardId: 'board-quotes',
                  cardId: 'card-1',
                  api: api,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('existing-password'), findsOneWidget);
      await tester.tap(find.text('Продлить'));
      await tester.pumpAndSettle();
      expect(find.text('existing-password'), findsOneWidget);
      expect(
        find.text('Срок ссылки продлён. Адрес и пароль не изменились.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'archive hides cards, persists after reload and restores content',
    (tester) async {
      final auth = _authorizedController(config);
      final gateway = _MemoryKanbanGateway();
      final controller = KanbanController(config, auth, gateway: gateway);
      await controller.initialize();
      await controller.saveCard(
        KanbanCardDraft(
          columnId: 'quote-first',
          categoryId: 'equipment',
          title: 'Архивная карточка',
          values: {'note': 'Сохранить'},
        ),
      );
      final card = controller.pageFor('quote-first')!.items.single;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: KanbanPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final menuButton = find.byTooltip('Действия карточки');
      final deleteButton = find.byTooltip('Удалить');
      final menuRect = tester.getRect(menuButton);
      expect(menuRect.size, const Size(30, 30));
      expect(tester.getRect(deleteButton).size, menuRect.size);
      expect(tester.getRect(deleteButton).center.dy, menuRect.center.dy);
      await tester.tap(find.byTooltip('Действия карточки'));
      await tester.pumpAndSettle();
      final menuItem = tester.getRect(find.byType(PopupMenuItem<String>));
      expect(menuItem.top, greaterThanOrEqualTo(menuRect.bottom + 4));
      expect(menuItem.width, 112);
      expect(menuItem.height, inInclusiveRange(32, 40));
      await tester.tap(find.text('В архив'));
      await tester.pumpAndSettle();
      expect(controller.pageFor('quote-first')!.items, isEmpty);
      expect(controller.archiveFor('quote-first')!.total, 1);
      expect(find.text('Архивная карточка'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await controller.reload();
      await tester.pumpAndSettle();
      expect(controller.archiveFor('quote-first')!.total, 1);
      await tester.tap(find.text('Архив').first);
      await tester.pumpAndSettle();
      expect(find.text('Архивная карточка'), findsOneWidget);
      final archived = controller.archiveFor('quote-first')!.items.single;
      expect(controller.canMoveCard(archived, 'quote-second'), isFalse);
      await tester.tap(find.text('Из архива'));
      await tester.pumpAndSettle();
      final restored = controller.pageFor('quote-first')!.items.single;
      expect(restored.id, card.id);
      expect(restored.values, card.values);
      expect(controller.archiveFor('quote-first')!.total, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      auth.dispose();
    },
  );

  test('контроллер открывает первый настроенный канбан', () async {
    final auth = _authorizedController(config);
    final gateway = _MemoryKanbanGateway();
    final controller = KanbanController(config, auth, gateway: gateway);

    await controller.initialize();

    expect(controller.boards, hasLength(2));
    expect(controller.board?.name, 'Коммерческие предложения');
    expect(controller.board?.columns, hasLength(2));
    expect(controller.error, isNull);

    controller.dispose();
    auth.dispose();
  });

  test('выбор загружает другой канбан без повторного списка', () async {
    final auth = _authorizedController(config);
    final gateway = _MemoryKanbanGateway();
    final controller = KanbanController(config, auth, gateway: gateway);
    await controller.initialize();

    await controller.selectBoard('board-orders');

    expect(controller.board?.name, 'Комплектация объекта');
    expect(gateway.listRequests, 1);
    expect(gateway.boardRequests, 2);

    controller.dispose();
    auth.dispose();
  });

  test('фильтр карточек передаёт выбранного пользователя на сервер', () async {
    final auth = _authorizedController(config);
    final gateway = _MemoryKanbanGateway();
    final controller = KanbanController(config, auth, gateway: gateway);
    await controller.initialize();

    await controller.selectAuthorFilter('user:manager-user');

    expect(controller.authorFilterKey, 'user:manager-user');
    expect(gateway.lastAuthorUserId, 'manager-user');
    expect(gateway.lastIncludeOwn, isFalse);

    await controller.selectAuthorFilter('own:manager-user');

    expect(controller.authorFilterKey, 'own:manager-user');
    expect(gateway.lastAuthorUserId, 'manager-user');
    expect(gateway.lastIncludeOwn, isTrue);

    controller.dispose();
    auth.dispose();
  });

  testWidgets('экран показывает настроенные столбцы', (tester) async {
    final auth = _authorizedController(config);
    final controller = KanbanController(
      config,
      auth,
      gateway: _MemoryKanbanGateway(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: KanbanPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Составить КП'), findsOneWidget);
    expect(find.text('Согласование'), findsOneWidget);
    expect(find.text('В этом столбце пока нет карточек'), findsWidgets);
    expect(find.byType(AppSelectField<String>), findsNWidgets(2));

    controller.dispose();
    auth.dispose();
  });

  testWidgets('карточка переносится за всю поверхность без отдельной ручки', (
    tester,
  ) async {
    final auth = _authorizedController(config);
    final controller = KanbanController(
      config,
      auth,
      gateway: _MemoryKanbanGateway(),
    );
    await controller.initialize();
    await controller.saveCard(
      KanbanCardDraft(
        columnId: 'quote-first',
        categoryId: 'equipment',
        title: 'Карточка для переноса',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: KanbanPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    final draggable = find.byWidgetPredicate(
      (widget) => widget is Draggable,
      description: 'перетаскиваемая карточка',
    );
    expect(draggable, findsOneWidget);
    expect(
      find.descendant(
        of: draggable,
        matching: find.text('Карточка для переноса'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.drag_indicator), findsNothing);

    controller.dispose();
    auth.dispose();
  });

  testWidgets('канбан прокручивается по горизонтали зажатой мышью', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 600);
    addTearDown(tester.view.reset);
    final auth = _authorizedController(config);
    final controller = KanbanController(
      config,
      auth,
      gateway: _MemoryKanbanGateway(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: KanbanPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    // Горизонтальная прокрутка доски (у поля поиска своя, внутренняя).
    final boardScroll = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    final scrollable = find
        .descendant(of: boardScroll, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(boardScroll));
    await gesture.moveBy(const Offset(-120, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));

    controller.dispose();
    auth.dispose();
  });

  test('создание карточки обновляет только затронутый столбец', () async {
    final auth = _authorizedController(config);
    final gateway = _MemoryKanbanGateway();
    final controller = KanbanController(config, auth, gateway: gateway);
    await controller.initialize();
    final firstRequests = gateway.cardRequests['quote-first']!;
    final secondRequests = gateway.cardRequests['quote-second']!;

    final saved = await controller.saveCard(
      KanbanCardDraft(
        columnId: 'quote-first',
        categoryId: 'equipment',
        title: 'Новая карточка',
      ),
    );

    expect(saved, isTrue);
    expect(controller.pageFor('quote-first')?.total, 1);
    expect(gateway.cardRequests['quote-first'], firstRequests + 1);
    expect(gateway.cardRequests['quote-second'], secondRequests);

    controller.dispose();
    auth.dispose();
  });

  test(
    'изменения других пользователей появляются без ручного обновления',
    () async {
      final auth = _authorizedController(config);
      final gateway = _MemoryKanbanGateway();
      final realtime = _FakeRealtime();
      final controller = KanbanController(
        config,
        auth,
        gateway: gateway,
        realtime: realtime,
        realtimeDebounce: Duration.zero,
      );
      await controller.initialize();
      expect(realtime.started, isTrue);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 20));

      // Другой пользователь создал карточку прямо на сервере.
      await gateway.createCard(
        'token',
        'board-quotes',
        KanbanCardDraft(
          columnId: 'quote-first',
          categoryId: 'equipment',
          title: 'Карточка коллеги',
        ),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      // Сигнал другого канбана не перечитывает открытый.
      realtime.emit(RealtimeEvent.changed, boardId: 'board-orders');
      await settle();
      expect(controller.pageFor('quote-first')!.items, isEmpty);
      expect(notifications, 0);

      realtime.emit(RealtimeEvent.changed, boardId: 'board-quotes');
      await settle();
      expect(
        controller.pageFor('quote-first')!.items.single.title,
        'Карточка коллеги',
      );
      expect(notifications, 1);

      // После обрыва связи данные перечитываются, даже без канбана в сигнале.
      await gateway.createCard(
        'token',
        'board-quotes',
        KanbanCardDraft(
          columnId: 'quote-second',
          categoryId: 'equipment',
          title: 'Пока не было связи',
        ),
      );
      realtime.emit(RealtimeEvent.resync);
      await settle();
      expect(controller.pageFor('quote-second')!.items, hasLength(1));

      // Изменение настроек перечитывает список и структуру канбанов.
      final listRequests = gateway.listRequests;
      realtime.emit(RealtimeEvent.configuration);
      await settle();
      expect(gateway.listRequests, listRequests + 1);

      controller.dispose();
      await realtime.close();
      auth.dispose();
    },
  );

  test('перенос обновляет только исходный и целевой столбцы', () async {
    final auth = _authorizedController(config);
    final gateway = _MemoryKanbanGateway();
    final controller = KanbanController(config, auth, gateway: gateway);
    await controller.initialize();
    await controller.saveCard(
      KanbanCardDraft(
        columnId: 'quote-first',
        categoryId: 'equipment',
        title: 'Карточка для переноса',
      ),
    );
    final card = controller.pageFor('quote-first')!.items.single;
    final firstRequests = gateway.cardRequests['quote-first']!;
    final secondRequests = gateway.cardRequests['quote-second']!;

    final moved = await controller.moveCard(card, 'quote-second', 0);

    expect(moved, isTrue);
    expect(controller.pageFor('quote-first')!.items, isEmpty);
    expect(controller.pageFor('quote-second')!.items.single.id, card.id);
    expect(gateway.cardRequests['quote-first'], firstRequests + 1);
    expect(gateway.cardRequests['quote-second'], secondRequests + 1);

    controller.dispose();
    auth.dispose();
  });
}

/// Источник сигналов, которым управляет тест.
final class _FakeRealtime implements RealtimeSource {
  final _controller = StreamController<RealtimeEvent>.broadcast();
  bool started = false;

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  void start() => started = true;

  @override
  Future<void> close() => _controller.close();

  void emit(String kind, {String? boardId, String? entityId}) =>
      _controller.add(
        RealtimeEvent(
          topic: 'kanban',
          kind: kind,
          boardId: boardId,
          entityId: entityId,
        ),
      );
}

final class _MemoryKanbanGateway implements KanbanGateway {
  WorkflowSpecialization specialization = WorkflowSpecialization.standard;
  List<WorkflowCreationAction> creationActions = [];
  int listRequests = 0;
  int boardRequests = 0;
  int nextNumber = 1;
  final Map<String, int> cardRequests = {};
  final Map<String, List<KanbanCard>> cards = {};
  String? lastAuthorUserId;
  String? lastSearch;
  double? selectedTotal;
  bool? lastIncludeOwn;

  static const boards = [
    KanbanBoardSummary(
      id: 'board-quotes',
      code: 'quotes',
      name: 'Коммерческие предложения',
      sortOrder: 0,
      columnCount: 2,
    ),
    KanbanBoardSummary(
      id: 'board-orders',
      code: 'orders',
      name: 'Комплектация объекта',
      sortOrder: 1,
      columnCount: 1,
    ),
  ];

  @override
  Future<List<KanbanBoardSummary>> getBoards(String accessToken) async {
    listRequests++;
    return boards;
  }

  @override
  Future<List<KanbanCardAuthor>> getCardAuthors(String accessToken) async =>
      const [
        KanbanCardAuthor(
          userId: 'current-user',
          displayName: 'Текущий пользователь',
          isCurrentUser: true,
        ),
        KanbanCardAuthor(
          userId: 'manager-user',
          displayName: 'Иван Бочаров',
          isCurrentUser: false,
        ),
      ];

  @override
  Future<KanbanBoard> getBoard(String accessToken, String boardId) async {
    boardRequests++;
    if (boardId == 'board-orders') {
      return const KanbanBoard(
        id: 'board-orders',
        code: 'orders',
        name: 'Комплектация объекта',
        columns: [
          KanbanColumn(
            id: 'order-first',
            name: 'Новая заявка',
            color: '#4D8DFF',
            sortOrder: 0,
          ),
        ],
        transitions: [],
        categories: [],
      );
    }
    return KanbanBoard(
      id: 'board-quotes',
      specialization: specialization,
      code: 'quotes',
      name: 'Коммерческие предложения',
      columns: [
        KanbanColumn(
          id: 'quote-first',
          creationActions: creationActions,
          name: 'Составить КП',
          color: '#4D8DFF',
          sortOrder: 0,
        ),
        KanbanColumn(
          id: 'quote-second',
          name: 'Согласование',
          color: '#06B6D4',
          sortOrder: 1,
        ),
      ],
      transitions: [
        KanbanTransition(
          fromColumnId: 'quote-first',
          toColumnId: 'quote-second',
        ),
      ],
      categories: [
        KanbanCategory(
          categoryId: 'equipment',
          name: 'Оборудование',
          sortOrder: 0,
          fields: [],
        ),
      ],
    );
  }

  @override
  Future<KanbanCardPage> getCards(
    String accessToken,
    String boardId,
    String columnId, {
    required int page,
    required int pageSize,
    String? authorUserId,
    bool includeOwn = true,
    bool archived = false,
    String? search,
  }) async {
    lastAuthorUserId = authorUserId;
    lastSearch = search;
    lastIncludeOwn = includeOwn;
    if (!archived) cardRequests[columnId] = (cardRequests[columnId] ?? 0) + 1;
    final needle = search?.toLowerCase();
    final source = (cards[columnId] ?? const <KanbanCard>[])
        .where((card) => card.isArchived == archived)
        .where(
          (card) =>
              needle == null ||
              card.title.toLowerCase().contains(needle) ||
              '${card.number}' == needle,
        )
        .toList();
    final start = (page - 1) * pageSize;
    return KanbanCardPage(
      items: start >= source.length
          ? const []
          : source.skip(start).take(pageSize).toList(growable: false),
      page: page,
      pageSize: pageSize,
      total: source.length,
      selectedTotal: archived ? null : selectedTotal,
    );
  }

  @override
  Future<void> setArchived(
    String accessToken,
    String boardId,
    String cardId,
    bool archived,
  ) async {
    for (final source in cards.values) {
      final index = source.indexWhere((card) => card.id == cardId);
      if (index < 0) continue;
      final card = source[index];
      source[index] = KanbanCard(
        id: card.id,
        number: card.number,
        workflowId: card.workflowId,
        columnId: card.columnId,
        categoryId: card.categoryId,
        sectionId: card.sectionId,
        title: card.title,
        values: card.values,
        createdAt: card.createdAt,
        updatedAt: card.updatedAt,
        isArchived: archived,
      );
      return;
    }
    throw StateError('Card not found');
  }

  @override
  Future<KanbanCard> createCard(
    String accessToken,
    String boardId,
    KanbanCardDraft draft,
  ) async {
    final now = DateTime.utc(2026, 8, 28);
    final card = KanbanCard(
      id: 'card-$nextNumber',
      number: nextNumber++,
      workflowId: boardId,
      columnId: draft.columnId,
      categoryId: draft.categoryId,
      sectionId: draft.sectionId,
      title: draft.title,
      values: Map.of(draft.values),
      createdAt: now,
      updatedAt: now,
    );
    cards.putIfAbsent(draft.columnId, () => []).insert(0, card);
    return card;
  }

  @override
  Future<KanbanCard> updateCard(
    String accessToken,
    String boardId,
    String cardId,
    KanbanCardDraft draft,
  ) async {
    final source = cards[draft.columnId] ?? [];
    final index = source.indexWhere((item) => item.id == cardId);
    if (index < 0) throw StateError('Карточка не найдена');
    final previous = source[index];
    final updated = KanbanCard(
      id: previous.id,
      number: previous.number,
      workflowId: previous.workflowId,
      columnId: draft.columnId,
      categoryId: draft.categoryId,
      sectionId: draft.sectionId,
      title: draft.title,
      values: Map.of(draft.values),
      createdAt: previous.createdAt,
      updatedAt: DateTime.utc(2026, 8, 28, 1),
    );
    source[index] = updated;
    return updated;
  }

  @override
  Future<KanbanCard> moveCard(
    String accessToken,
    String boardId,
    String cardId,
    String targetColumnId,
    int targetIndex,
  ) async {
    KanbanCard? sourceCard;
    for (final source in cards.values) {
      final index = source.indexWhere((item) => item.id == cardId);
      if (index >= 0) sourceCard = source.removeAt(index);
    }
    if (sourceCard == null) throw StateError('Карточка не найдена');
    final moved = KanbanCard(
      id: sourceCard.id,
      number: sourceCard.number,
      workflowId: sourceCard.workflowId,
      columnId: targetColumnId,
      categoryId: sourceCard.categoryId,
      sectionId: sourceCard.sectionId,
      title: sourceCard.title,
      values: sourceCard.values,
      createdBy: sourceCard.createdBy,
      createdByName: sourceCard.createdByName,
      createdAt: sourceCard.createdAt,
      updatedBy: sourceCard.updatedBy,
      updatedByName: sourceCard.updatedByName,
      updatedAt: DateTime.utc(2026, 8, 28, 2),
    );
    final target = cards.putIfAbsent(targetColumnId, () => []);
    target.insert(targetIndex.clamp(0, target.length), moved);
    return moved;
  }

  @override
  Future<void> deleteCard(
    String accessToken,
    String boardId,
    String cardId,
  ) async {
    for (final source in cards.values) {
      source.removeWhere((item) => item.id == cardId);
    }
  }

  @override
  void close() {}
}

AuthController _authorizedController(AppConfig config) => AuthController(
  config,
  api: _NoopAuthGateway(),
  tokens: _MemoryTokenRepository(),
)..accessToken = 'access-token';

final class _NoopAuthGateway implements AuthGateway {
  @override
  Future<dynamic> delete(String path, String accessToken) async => null;
  @override
  Future<dynamic> get(String path, String accessToken) async => null;
  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async => null;
  @override
  void close() {}
}

final class _MemoryTokenRepository implements TokenRepository {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String? value) async {}
}

/// Telegram и почта настроены со значениями по умолчанию.
final class _MemoryOutboundGateway implements OutboundGateway {
  final sent = <(String, String, OutboundChannel)>[];

  @override
  Future<OutboundChannels> getChannels(String accessToken) async =>
      const OutboundChannels(telegramReady: true, emailReady: true);

  @override
  Future<OutboundSendResult> send(
    String accessToken, {
    required String boardId,
    required String cardId,
    required OutboundChannel channel,
    int? topicId,
    String? recipient,
    String? proposalTypeId,
    String? variantId,
  }) async {
    sent.add((boardId, cardId, channel));
    return const OutboundSendResult(
      destination: 'boss@example.com',
      fileName: 'Лесная, 5 — 03.10.2026.pdf',
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
