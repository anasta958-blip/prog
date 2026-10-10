import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_api.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/company/company_api.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/orders/order_api.dart';
import 'package:sklad_komforta_app/features/orders/order_models.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_api.dart';
import 'package:sklad_komforta_app/features/outbound/outbound_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_api.dart';
import 'package:sklad_komforta_app/features/quotes/quote_controller.dart';
import 'package:sklad_komforta_app/features/quotes/quote_editor_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
  );

  AuthController authorized() => AuthController(
    config,
    api: _NoopAuthGateway(),
    tokens: _MemoryTokenRepository(),
  )..accessToken = 'access-token';

  test('комплектация читается из API и сохраняется без цен', () {
    final order = OrderDocument.fromJson(_orderJson());
    expect(order.title, 'Лесная, 5');
    expect(order.reorderPositionIds, {'row-2'});
    expect(order.fromQuotePositionIds, {'row-1'});
    final rows = order.categories.single.sections.single.positions;
    expect(rows.first.quantity, 3);
    expect(rows.first.values['supplier'], 'ВентАид');

    final json = order.toJson();
    final position =
        ((json['categories'] as List).single['sections'] as List)
                .single['positions']
            as List;
    expect(position.first.keys, {
      'id',
      'catalogItemId',
      'name',
      'marking',
      'unit',
      'quantity',
      'values',
    });
    expect(json['objectType'], 'Дом');

    final restored = OrderDocument.fromJson(order.toSnapshot());
    expect(restored.reorderPositionIds, {'row-2'});
    expect(restored.sourceQuote?.cardNumber, 7);
  });

  test(
    'фильтры по поставщику и статусу, подсветка дозаказа и сохранение',
    () async {
      final auth = authorized();
      final gateway = _MemoryOrderGateway();
      final controller = OrderController(
        config,
        auth,
        orderGateway: gateway,
        catalogGateway: _CatalogGateway(),
        companyGateway: _CompanyGateway(),
      );
      await controller.initializeOrder(board: _orderBoard, card: _card());

      expect(controller.error, isNull);
      expect(controller.showsMoney, isFalse);
      expect(controller.attachesCatalogRelations, isFalse);
      expect(controller.draft!.title, 'Лесная, 5');
      expect(controller.reorderActive, isTrue);
      final rows = controller.activeVariant!.positions.toList();
      expect(controller.isPositionHighlighted(rows[1]), isTrue);
      expect(controller.isPositionHighlighted(rows[0]), isFalse);

      // Значения фильтров: справочник поля и значения в строках, плюс «Не указан».
      expect(controller.supplierOptions, ['ВентАид', 'Turkov', '']);
      expect(controller.shipmentOptions, ['Купить', 'На складе']);
      controller.toggleSupplierFilter('ВентАид');
      expect(controller.positionFiltersActive, isTrue);
      expect(controller.isPositionVisible(rows[0]), isTrue);
      expect(controller.isPositionVisible(rows[1]), isFalse);
      controller.toggleSupplierFilter('');
      expect(controller.isPositionVisible(rows[1]), isTrue);
      controller.toggleShipmentFilter('Купить');
      expect(controller.isPositionVisible(rows[1]), isFalse);
      controller.clearFilters();
      expect(controller.isPositionVisible(rows[1]), isTrue);

      // Новая строка в столбце дозаказа подсвечивается ещё до сохранения.
      final section =
          controller.activeVariant!.categories.single.sections.single;
      final added = controller.addEntryPosition(section)..name = 'Труба';
      expect(controller.isPositionHighlighted(added), isTrue);

      controller.updateDocument((draft) => draft.title = 'Лесная, 7');
      controller.setObjectType('Квартира');
      added.quantity = 0;
      expect(await controller.saveOrder(), isTrue);
      expect(gateway.saved?.title, 'Лесная, 7');
      expect(gateway.saved?.objectType, 'Квартира');
      final savedRows =
          gateway.saved!.categories.single.sections.single.positions;
      expect(savedRows.last.name, 'Труба');
      expect(savedRows.last.quantity, 1);
      expect(controller.dirty, isFalse);

      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets('редактор комплектации: шапка, фильтры, счета и таблица', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 1100);
    addTearDown(tester.view.reset);
    final auth = authorized();
    final gateway = _MemoryOrderGateway();
    final controller = OrderController(
      config,
      auth,
      orderGateway: gateway,
      catalogGateway: _CatalogGateway(),
      companyGateway: _CompanyGateway(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderEditorPage(
            config: config,
            authController: auth,
            board: _orderBoard,
            card: _card(),
            controller: controller,
            onBack: () {},
            pdfViewerBuilder: (context, bytes, title) =>
                Text('Просмотр: $title (${bytes.length} байт)'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Комплектация №12'), findsOneWidget);
    expect(find.byKey(const Key('order-source-quote')), findsOneWidget);
    expect(find.text('Счета (2)'), findsOneWidget);
    expect(find.text('счёт.pdf'), findsOneWidget);
    expect(find.byKey(const Key('order-invoice-upload')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('position-reorder-row-2')),
      findsOneWidget,
    );
    // Менеджер без права смены — только чтение.
    expect(find.byKey(const Key('order-manager')), findsOneWidget);
    expect(find.textContaining('Итого'), findsNothing);
    // «Статус отгрузки» — выбор из справочника канбана, а не ввод текста.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.controller.text == 'Купить',
      ),
      findsNothing,
    );
    expect(find.text('Купить'), findsWidgets);

    // Несколько счетов открываются вместе — вкладками окна просмотра.
    await tester.tap(
      find.byKey(const ValueKey('order-invoice-select-invoice-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('order-invoice-select-invoice-2')),
    );
    await tester.pump();
    expect(find.text('Открыть выбранные (2)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('order-invoice-view-selected')));
    await tester.pumpAndSettle();
    final window = find.byKey(const Key('pdf-viewer-window'));
    expect(window, findsOneWidget);
    expect(find.text('Просмотр: счёт.pdf (4 байт)'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('pdf-viewer-tab-order-invoice-invoice-2')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Просмотр: доставка.pdf (4 байт)').hitTestable(),
      findsOneWidget,
    );

    // Окно перемещается за заголовок и меняет размер за край.
    final before = tester.getRect(window);
    await tester.drag(
      find.byKey(const Key('pdf-viewer-drag')),
      const Offset(-120, 40),
    );
    await tester.pumpAndSettle();
    // Жест теряет порог начала перетаскивания, поэтому сравнение примерное.
    final shift = tester.getRect(window).topLeft - before.topLeft;
    expect(shift.dx, lessThan(-80));
    expect(shift.dy, greaterThan(10));
    final moved = tester.getRect(window);
    await tester.dragFrom(
      moved.centerLeft + const Offset(2, 0),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(window).width, greaterThan(moved.width + 40));

    // Окно не модальное: программа под ним доступна, окно остаётся открытым.
    await tester.tap(find.byKey(const Key('order-title')).hitTestable());
    await tester.pumpAndSettle();
    expect(window, findsOneWidget);
    await tester.tap(find.byKey(const Key('pdf-viewer-close')));
    await tester.pumpAndSettle();
    expect(window, findsNothing);

    await tester.tap(find.byKey(const Key('order-filter-supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turkov').last);
    await tester.pumpAndSettle();
    expect(find.text('Поставщик · 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('position-reorder-row-2')), findsNothing);
    expect(find.byKey(const Key('order-filter-reset')), findsOneWidget);

    for (final width in [1024.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpAndSettle();
      final title = find.byKey(const Key('order-title'));
      final before = tester.getTopLeft(title).dy;
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('order-page-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(80));
      scroll.position.jumpTo(80);
      await tester.pump();
      expect(tester.getTopLeft(title).dy, closeTo(before - 80, 0.1));
      scroll.position.jumpTo(0);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    controller.dispose();
    auth.dispose();
  });

  testWidgets('значение, удалённое из справочника, видно с пометкой', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 1100);
    addTearDown(tester.view.reset);
    final auth = authorized();
    final controller = OrderController(
      config,
      auth,
      orderGateway: _MemoryOrderGateway(
        json: () {
          final json = _orderJson();
          final positions =
              (((json['categories'] as List).first as Map)['sections'] as List)
                      .first['positions']
                  as List;
          (positions.first as Map)['values'] = {'shipment_status': 'В пути'};
          (positions.first as Map)['unit'] = 'шт';
          return json;
        },
      ),
      catalogGateway: _CatalogGateway(),
      companyGateway: _CompanyGateway(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderEditorPage(
            config: config,
            authController: auth,
            board: _orderBoard,
            card: _card(),
            controller: controller,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final missing = find.byKey(const Key('row-select-missing'));
    expect(missing, findsOneWidget);
    expect(tester.widget<Text>(missing).data, 'В пути');
    await tester.tap(missing);
    await tester.pumpAndSettle();
    expect(find.text('В пути (нет в справочнике)'), findsOneWidget);
    await tester.tap(find.widgetWithText(MenuItemButton, 'На складе'));
    await tester.pumpAndSettle();
    expect(missing, findsNothing);
    final first =
        controller.snapshot!.categories.first.sections.first.positions.first;
    expect(first.values['shipment_status'], 'На складе');

    controller.dispose();
    auth.dispose();
  });
  testWidgets('отправка комплектации: несохранённые правки сначала '
      'сохраняются', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 1100);
    addTearDown(tester.view.reset);
    final auth = authorized();
    final orders = _MemoryOrderGateway();
    final outbound = _MemoryOutboundGateway();
    final controller = OrderController(
      config,
      auth,
      orderGateway: orders,
      catalogGateway: _CatalogGateway(),
      companyGateway: _CompanyGateway(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderEditorPage(
            config: config,
            authController: auth,
            board: _orderBoard,
            card: _card(),
            controller: controller,
            onBack: () {},
            outboundGatewayFactory: (_) => outbound,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('order-title')), 'Лесная, 7');
    await tester.pump();
    await tester.tap(find.byKey(const Key('outbound-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('outbound-send-telegram')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('outbound-send-email')));
    await tester.pumpAndSettle();
    expect(find.text('Сохранить и отправить?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('outbound-save-and-send')));
    await tester.pumpAndSettle();

    expect(orders.saved?.title, 'Лесная, 7');
    expect(outbound.sent, [('card-12', OutboundChannel.email)]);
    expect(
      find.textContaining('отправлено на boss@example.com'),
      findsOneWidget,
    );

    controller.dispose();
    auth.dispose();
  });
}

KanbanCard _card() => KanbanCard(
  id: 'card-12',
  number: 12,
  workflowId: 'orders',
  columnId: 'montage',
  title: 'Лесная, 5',
  values: const {},
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, 1),
);

Map<String, dynamic> _orderJson() => {
  'id': 'order-1',
  'cardId': 'card-12',
  'title': 'Лесная, 5',
  'objectType': 'Дом',
  'clientId': 'client-1',
  'executorCompanyId': 'executor-1',
  'managerUserId': 'user-1',
  'salesHeadUserId': null,
  'sourceQuote': {
    'quoteId': 'quote-1',
    'boardId': 'sales',
    'cardId': 'quote-card',
    'cardNumber': 7,
    'title': 'Лесная, 5',
  },
  'canChangeManager': false,
  'canManageInvoices': true,
  'categories': [
    {
      'id': 'category-1',
      'catalogCategoryId': 'equipment',
      'name': 'Оборудование',
      'sections': [
        {
          'id': 'section-1',
          'catalogSectionId': 'blocks',
          'name': 'Блоки',
          'positions': [
            {
              'id': 'row-1',
              'catalogItemId': 'item-1',
              'name': 'Кондиционер',
              'marking': 'AC-24',
              'unit': 'шт',
              'quantity': 3,
              'isReorder': false,
              'fromQuote': true,
              'values': {'supplier': 'ВентАид', 'shipment_status': 'Купить'},
            },
            {
              'id': 'row-2',
              'catalogItemId': 'item-2',
              'name': 'Кронштейн',
              'marking': 'K-1',
              'unit': 'шт',
              'quantity': 2,
              'isReorder': true,
              'fromQuote': false,
              'values': {'shipment_status': 'На складе'},
            },
          ],
        },
      ],
    },
  ],
};

const _orderBoard = KanbanBoard(
  id: 'orders',
  code: 'orders',
  name: 'Комплектация',
  specialization: WorkflowSpecialization.order,
  objectTypes: ['Квартира', 'Дом'],
  columns: [
    KanbanColumn(
      id: 'compose',
      name: 'Составление',
      color: '#4D8DFF',
      sortOrder: 0,
    ),
    KanbanColumn(
      id: 'montage',
      name: 'Монтаж',
      color: '#F59E0B',
      sortOrder: 1,
      reorderFrom: true,
    ),
  ],
  transitions: [],
  categories: [
    KanbanCategory(
      categoryId: 'equipment',
      name: 'Оборудование',
      sortOrder: 0,
      sections: [KanbanSection(id: 'blocks', name: 'Блоки', sortOrder: 0)],
      fields: [
        KanbanField(
          code: 'name',
          label: 'Наименование',
          fieldType: 'text',
          isRequired: true,
          sortOrder: 0,
          options: [],
        ),
        KanbanField(
          code: 'quantity',
          label: 'Количество',
          fieldType: 'number',
          isRequired: false,
          sortOrder: 1,
          options: [],
        ),
        KanbanField(
          code: 'supplier',
          label: 'Поставщик',
          fieldType: 'dictionary',
          isRequired: false,
          sortOrder: 2,
          options: [
            KanbanDictionaryOption(id: 's1', value: 'ВентАид', sortOrder: 0),
            KanbanDictionaryOption(id: 's2', value: 'Turkov', sortOrder: 1),
          ],
        ),
        KanbanField(
          code: 'unit',
          label: 'Единица измерения',
          fieldType: 'dictionary',
          isRequired: false,
          sortOrder: 4,
          options: [],
        ),
        KanbanField(
          code: 'shipment_status',
          label: 'Статус отгрузки',
          fieldType: 'dictionary',
          isRequired: false,
          sortOrder: 3,
          options: [
            KanbanDictionaryOption(id: 'o1', value: 'Купить', sortOrder: 0),
            KanbanDictionaryOption(id: 'o2', value: 'На складе', sortOrder: 1),
          ],
        ),
      ],
    ),
  ],
);

final class _MemoryOrderGateway implements OrderGateway {
  _MemoryOrderGateway({this.json = _orderJson});

  final Map<String, dynamic> Function() json;
  OrderDocument? saved;

  @override
  Future<OrderDocument> getOrder(
    String accessToken,
    String boardId,
    String cardId,
  ) async => OrderDocument.fromJson(json());

  @override
  Future<OrderDocument> saveOrder(
    String accessToken,
    String boardId,
    String cardId,
    OrderDocument order,
  ) async {
    saved = order;
    return OrderDocument.fromJson({
      ...order.toSnapshot(),
      'id': 'order-1',
      'cardId': cardId,
    });
  }

  @override
  Future<OrderDocument> createOrder(
    String accessToken,
    String boardId,
    String columnId,
    OrderDocument order,
  ) => saveOrder(accessToken, boardId, 'new-card', order);

  @override
  Future<List<OrderInvoice>> getInvoices(
    String accessToken,
    String boardId,
    String cardId,
  ) async => [
    OrderInvoice(
      id: 'invoice-1',
      fileName: 'счёт.pdf',
      byteSize: 2048,
      uploadedAt: DateTime.utc(2026, 10, 1, 9),
      uploadedByName: 'Директор',
      downloadUrl: 'https://storage.example.test/invoice',
    ),
    OrderInvoice(
      id: 'invoice-2',
      fileName: 'доставка.pdf',
      byteSize: 1024,
      uploadedAt: DateTime.utc(2026, 10, 1, 10),
      downloadUrl: 'https://storage.example.test/invoice-2',
    ),
  ];

  @override
  Future<OrderInvoice> uploadInvoice(
    String accessToken,
    String boardId,
    String cardId, {
    required String fileName,
    required Uint8List bytes,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteInvoice(
    String accessToken,
    String boardId,
    String cardId,
    String invoiceId,
  ) async {}

  @override
  Future<Uint8List> fetchInvoice(OrderInvoice invoice) async =>
      Uint8List.fromList(const [37, 80, 68, 70]);

  @override
  Future<QuotePdfDownload> downloadPdf(
    String accessToken,
    String boardId,
    String cardId,
  ) => throw UnimplementedError();

  @override
  void close() {}
}

final class _CatalogGateway implements CatalogGateway {
  @override
  Future<CatalogConfiguration> getConfiguration(String accessToken) async =>
      const CatalogConfiguration(categories: [], dictionaries: []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  void close() {}
}

final class _CompanyGateway implements CompanyWorkspaceGateway {
  @override
  Future<List<CompanyClientModel>> getClients(String accessToken) async => [
    CompanyClientModel(id: 'client-1', name: 'Петров Пётр'),
  ];

  @override
  Future<List<LegalEntityModel>> getLegalEntities(String accessToken) async => [
    LegalEntityModel(id: 'executor-1', name: 'Исполнитель', companyType: 'ООО'),
  ];

  @override
  Future<List<EmployeeModel>> getEmployees(String accessToken) async => [
    EmployeeModel(
      membershipId: 'member-1',
      userId: 'user-1',
      login: 'manager',
      displayName: 'Менеджер Иван',
      roleId: 'role',
      roleName: 'Менеджер',
      isDirector: false,
      isActive: true,
      createdAt: DateTime(2026),
      activeUntil: DateTime(2027),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

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

/// Почта настроена с получателем по умолчанию: адрес не спрашивается.
final class _MemoryOutboundGateway implements OutboundGateway {
  final sent = <(String, OutboundChannel)>[];

  @override
  Future<OutboundChannels> getChannels(String accessToken) async =>
      const OutboundChannels(emailReady: true);

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
    sent.add((cardId, channel));
    return const OutboundSendResult(
      destination: 'boss@example.com',
      fileName: 'Лесная, 7 — 03.10.2026.pdf',
    );
  }

  @override
  Future<OutboundSettingsModel> getSettings(String accessToken) =>
      throw UnimplementedError();

  @override
  Future<OutboundSettingsModel> saveSettings(
    String accessToken,
    OutboundSettingsModel settings,
  ) => throw UnimplementedError();

  @override
  Future<String> test(String accessToken, OutboundChannel channel) =>
      throw UnimplementedError();

  @override
  void close() {}
}
