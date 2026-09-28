import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_api.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
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
      await tester.tap(find.byTooltip('Действия карточки'));
      await tester.pumpAndSettle();
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

    final scrollable = find.byType(Scrollable);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(find.byType(SingleChildScrollView)));
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

final class _MemoryKanbanGateway implements KanbanGateway {
  int listRequests = 0;
  int boardRequests = 0;
  int nextNumber = 1;
  final Map<String, int> cardRequests = {};
  final Map<String, List<KanbanCard>> cards = {};
  String? lastAuthorUserId;
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
      code: 'quotes',
      name: 'Коммерческие предложения',
      columns: [
        KanbanColumn(
          id: 'quote-first',
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
  }) async {
    lastAuthorUserId = authorUserId;
    lastIncludeOwn = includeOwn;
    if (!archived) cardRequests[columnId] = (cardRequests[columnId] ?? 0) + 1;
    final source = (cards[columnId] ?? const <KanbanCard>[])
        .where((card) => card.isArchived == archived)
        .toList();
    final start = (page - 1) * pageSize;
    return KanbanCardPage(
      items: start >= source.length
          ? const []
          : source.skip(start).take(pageSize).toList(growable: false),
      page: page,
      pageSize: pageSize,
      total: source.length,
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
