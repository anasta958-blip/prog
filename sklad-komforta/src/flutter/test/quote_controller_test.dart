import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/security/token_store.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_api.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_api.dart';
import 'package:sklad_komforta_app/features/quotes/quote_controller.dart';
import 'package:sklad_komforta_app/features/quotes/quote_editor_page.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

void main() {
  const config = AppConfig(
    apiBaseUrl: 'https://api.example.test/api/v1',
    environment: 'test',
  );

  test(
    'повторная связанная работа увеличивает количество без сброса ручных значений',
    () async {
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = QuoteController(
        config,
        auth,
        catalogGateway: _CatalogGatewayWithRelations(),
      );
      final equipmentSection = QuoteSectionDraft(
        id: 'quote-equipment-section',
        catalogSectionId: _equipmentSection.id,
        name: _equipmentSection.name,
        positions: [],
      );
      final equipmentCategory = QuoteCategoryDraft(
        id: 'quote-equipment-category',
        catalogCategoryId: _equipmentCategory.id,
        name: _equipmentCategory.name,
        sections: [equipmentSection],
      );
      final variant = QuoteVariantDraft(
        id: 'variant',
        name: 'Основной',
        categories: [equipmentCategory],
      );
      final proposalType = QuoteProposalTypeDraft(
        id: 'type',
        name: 'Основное предложение',
        variants: [variant],
      );
      controller
        ..catalog = _configuration
        ..draft = QuoteDraft(
          kind: QuoteKind.quote,
          title: 'Тестовое КП',
          clientId: 'client',
          executorCompanyId: 'executor',
          selectionMode: 'variant',
          proposalTypes: [proposalType],
        )
        ..activeTypeId = proposalType.id
        ..activeVariantId = variant.id;

      await controller.addCatalogPosition(
        equipmentCategory,
        equipmentSection,
        _equipmentItem,
      );

      final workPosition = variant.positions.singleWhere(
        (item) => item.catalogItemId == _workItemId,
      );
      expect(workPosition.quantity, 1);
      expect(workPosition.purchasePrice, 40);
      expect(workPosition.basePrice, 100);
      expect(workPosition.values['auto_added'], isTrue);
      expect(workPosition.values['group'], 'Монтаж');
      expect(equipmentSection.positions.single.values['linked_works'], [
        'Монтаж оборудования / M-1',
      ]);

      workPosition
        ..quantity = 4
        ..manualPrice = 150
        ..markupPercent = 12
        ..discountPercent = 7;

      await controller.addCatalogPosition(
        equipmentCategory,
        equipmentSection,
        _equipmentItem,
      );

      final workPositions = variant.positions
          .where((item) => item.catalogItemId == _workItemId)
          .toList();
      expect(workPositions, hasLength(1));
      expect(workPositions.single.quantity, 5);
      expect(workPositions.single.manualPrice, 150);
      expect(workPositions.single.markupPercent, 12);
      expect(workPositions.single.discountPercent, 7);
      expect(equipmentSection.positions, hasLength(2));

      equipmentSection.positions.first.selected = true;
      controller.applyPercent(equipmentSection, value: 9, markup: false);
      expect(equipmentSection.positions.first.discountPercent, 9);
      expect(equipmentSection.positions.last.discountPercent, isNull);

      controller.setSectionSelection(equipmentSection, true);
      expect(
        equipmentSection.positions.every((position) => position.selected),
        isTrue,
      );
      controller.removeSelectedPositions(equipmentSection);
      expect(equipmentSection.positions, isEmpty);

      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets('ПКП использует поля канбана и раскрывает загруженный вариант', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';
    final controller = QuoteController(
      config,
      auth,
      catalogGateway: _CatalogGatewayWithRelations(),
    );
    final section = QuoteSectionDraft(
      id: 'quote-equipment-section',
      catalogSectionId: _equipmentSection.id,
      name: _equipmentSection.name,
      positions: [
        QuotePositionDraft(
          id: 'position',
          catalogItemId: _equipmentItem.id,
          name: _equipmentItem.name,
          marking: _equipmentItem.marking,
          unit: 'шт',
          quantity: 1,
          basePrice: 1200,
          values: Map<String, dynamic>.from(_equipmentItem.values),
        ),
      ],
    );
    final category = QuoteCategoryDraft(
      id: 'quote-equipment-category',
      catalogCategoryId: _equipmentCategory.id,
      name: _equipmentCategory.name,
      sections: [section],
    );
    final variant = QuoteVariantDraft(
      id: 'variant',
      name: 'Основной',
      categories: [category],
    );
    final proposalType = QuoteProposalTypeDraft(
      id: 'type',
      name: 'Основное предложение',
      variants: [variant],
    );
    controller
      ..catalog = _configuration
      ..draft = QuoteDraft(
        kind: QuoteKind.prequote,
        title: 'Тестовое ПКП',
        clientId: 'client',
        executorCompanyId: 'executor',
        selectionMode: 'variant',
        proposalTypes: [proposalType],
      )
      ..activeTypeId = proposalType.id
      ..activeVariantId = variant.id;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1500,
            height: 900,
            child: QuoteEditorPage(
              config: config,
              authController: auth,
              board: _quoteBoard,
              controller: controller,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Оборудование'), findsOneWidget);
    expect(find.text('Вентиляция'), findsOneWidget);
    expect(find.text('Вентилятор'), findsOneWidget);
    expect(find.text('НАИМЕНОВАНИЕ'), findsOneWidget);
    expect(find.text('ЦЕНА'), findsOneWidget);
    expect(find.text('ГРУППА'), findsNothing);
    expect(find.text('СВЯЗАННЫЕ РАБОТЫ'), findsNothing);
    expect(tester.takeException(), isNull);

    final nameColumn = find.byKey(const ValueKey('quote-column-name')).first;
    final resizeHandle = find
        .byKey(const ValueKey('quote-column-resize-name'))
        .first;
    final widthBefore = tester.getSize(nameColumn).width;
    await tester.drag(resizeHandle, const Offset(40, 0));
    await tester.pump();
    final widthAfterExpansion = tester.getSize(nameColumn).width;
    expect(widthAfterExpansion, closeTo(widthBefore + 40, 1));

    await tester.drag(resizeHandle, const Offset(-70, 0));
    await tester.pump();
    final persistedWidth = widthAfterExpansion - 70;
    expect(tester.getSize(nameColumn).width, closeTo(persistedWidth, 1));
    expect(
      find.byKey(
        const ValueKey('quote-section-scrollbar-quote-equipment-section'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1500,
            height: 900,
            child: QuoteEditorPage(
              config: config,
              authController: auth,
              board: _quoteBoard,
              controller: controller,
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('quote-column-name')).first)
          .width,
      closeTo(persistedWidth, 1),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    controller.dispose();
    auth.dispose();
  });

  test(
    'правила связей не дублируют строку и удаляют только свой вклад',
    () async {
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      )..accessToken = 'access-token';
      final controller = QuoteController(
        config,
        auth,
        catalogGateway: _CatalogGatewayWithRelations(),
      );
      final equipmentSection = QuoteSectionDraft(
        id: 'equipment-section',
        catalogSectionId: _equipmentSection.id,
        name: _equipmentSection.name,
        positions: [],
      );
      final equipmentCategory = QuoteCategoryDraft(
        id: 'equipment-category',
        catalogCategoryId: _equipmentCategory.id,
        name: _equipmentCategory.name,
        sections: [equipmentSection],
      );
      final variant = QuoteVariantDraft(
        id: 'variant',
        name: 'Основной',
        categories: [equipmentCategory],
      );
      controller
        ..catalog = CatalogConfiguration(
          categories: _configuration.categories,
          dictionaries: const [],
          dependencies: const [_dependency],
          rules: [
            CalculationRuleDraft(
              clientId: 'add-work',
              name: 'Добавить работу',
              categoryClientId: 'equipment',
              eventType: 'field_changed',
              eventFieldCode: 'requires_work',
              isEnabled: true,
              conditions: [
                RuleConditionDraft(
                  fieldCode: 'requires_work',
                  operator: 'is_true',
                ),
              ],
              actions: [
                RuleActionDraft(
                  actionType: 'add_related_cards',
                  dependencyClientId: _dependency.clientId,
                ),
              ],
            ),
            CalculationRuleDraft(
              clientId: 'remove-work',
              name: 'Удалить работу',
              categoryClientId: 'equipment',
              eventType: 'field_changed',
              eventFieldCode: 'requires_work',
              isEnabled: true,
              conditions: [
                RuleConditionDraft(
                  fieldCode: 'requires_work',
                  operator: 'is_false',
                ),
              ],
              actions: [
                RuleActionDraft(
                  actionType: 'remove_related_cards',
                  dependencyClientId: _dependency.clientId,
                ),
              ],
            ),
          ],
        )
        ..draft = QuoteDraft(
          kind: QuoteKind.quote,
          title: 'Тестовое КП',
          clientId: 'client',
          executorCompanyId: 'executor',
          selectionMode: 'variant',
          proposalTypes: [
            QuoteProposalTypeDraft(
              id: 'type',
              name: 'Основное предложение',
              variants: [variant],
            ),
          ],
        )
        ..activeTypeId = 'type'
        ..activeVariantId = variant.id;

      await controller.addCatalogPosition(
        equipmentCategory,
        equipmentSection,
        _equipmentItem,
      );
      final primary = equipmentSection.positions.single;
      expect(variant.positions, hasLength(1));

      primary.values['requires_work'] = true;
      await controller.positionChanged(
        position: primary,
        fieldCode: 'requires_work',
      );
      await controller.positionChanged(
        position: primary,
        fieldCode: 'requires_work',
      );
      final work = variant.positions.singleWhere(
        (item) => item.catalogItemId == _workItemId,
      );
      expect(work.quantity, 1);

      work.quantity = 4;
      primary.values['requires_work'] = false;
      await controller.positionChanged(
        position: primary,
        fieldCode: 'requires_work',
      );
      expect(work.quantity, 3);

      controller.dispose();
      auth.dispose();
    },
  );

  test('PDF доступен только для сохранённой версии предложения', () async {
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';
    final gateway = _RecordingQuoteGateway();
    final controller = QuoteController(
      config,
      auth,
      quoteGateway: gateway,
      catalogGateway: _CatalogGatewayWithRelations(),
    )..persistedCardId = 'card-id';

    controller.dirty = true;
    expect(await controller.downloadPdf(board: _quoteBoard), isNull);
    expect(controller.error, 'Сохраните изменения перед печатью.');
    expect(gateway.downloadCalls, 0);

    controller.dirty = false;
    final file = await controller.downloadPdf(board: _quoteBoard);
    expect(file?.fileName, 'КП.pdf');
    expect(file?.bytes, [0x25, 0x50, 0x44, 0x46]);
    expect(gateway.downloadCalls, 1);
    expect(gateway.lastBoardId, _quoteBoard.id);
    expect(gateway.lastCardId, 'card-id');

    controller.dispose();
    auth.dispose();
  });
}

final class _RecordingQuoteGateway implements QuoteGateway {
  int downloadCalls = 0;
  String? lastBoardId;
  String? lastCardId;

  @override
  Future<QuotePdfDownload> downloadPdf(
    String accessToken,
    String boardId,
    String cardId,
  ) async {
    downloadCalls++;
    lastBoardId = boardId;
    lastCardId = cardId;
    return QuotePdfDownload(
      fileName: 'КП.pdf',
      bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
    );
  }

  @override
  Future<QuoteDraft> createQuote(
    String accessToken,
    String boardId,
    String columnId,
    QuoteDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<QuoteDraft> getQuote(
    String accessToken,
    String boardId,
    String cardId,
  ) => throw UnimplementedError();

  @override
  Future<QuoteDraft> saveQuote(
    String accessToken,
    String boardId,
    String cardId,
    QuoteDraft draft,
  ) => throw UnimplementedError();

  @override
  void close() {}
}

const _quoteBoard = KanbanBoard(
  id: 'quote-board',
  code: 'quotes',
  name: 'Коммерческие предложения',
  specialization: WorkflowSpecialization.quote,
  columns: [],
  transitions: [],
  categories: [
    KanbanCategory(
      categoryId: 'equipment-category',
      name: 'Оборудование',
      sortOrder: 0,
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
          code: 'marking',
          label: 'Маркировка / размер',
          fieldType: 'text',
          isRequired: true,
          sortOrder: 1,
          options: [],
        ),
        KanbanField(
          code: 'quantity',
          label: 'Количество',
          fieldType: 'number',
          isRequired: true,
          sortOrder: 2,
          options: [],
        ),
        KanbanField(
          code: 'unit',
          label: 'Единица измерения',
          fieldType: 'dictionary',
          isRequired: true,
          sortOrder: 3,
          options: [
            KanbanDictionaryOption(id: 'unit-piece', value: 'шт', sortOrder: 0),
          ],
        ),
        KanbanField(
          code: 'base_price',
          label: 'Цена',
          fieldType: 'money',
          isRequired: true,
          sortOrder: 4,
          options: [],
        ),
      ],
      sections: [
        KanbanSection(
          id: 'equipment-section',
          name: 'Вентиляция',
          sortOrder: 0,
        ),
      ],
    ),
  ],
);

const _equipmentSection = CatalogSection(
  id: 'equipment-section',
  name: 'Вентиляция',
  sortOrder: 0,
  groups: [],
);

const _workSection = CatalogSection(
  id: 'work-section',
  name: 'Монтажные работы',
  sortOrder: 0,
  groups: [CatalogGroup(id: 'work-group', name: 'Монтаж', sortOrder: 0)],
);

const _equipmentCategory = CatalogCategory(
  id: 'equipment-category',
  clientId: 'equipment',
  name: 'Оборудование',
  sortOrder: 0,
  fields: [
    CatalogField(
      code: 'group',
      label: 'Группа',
      fieldType: 'dictionary',
      isVisible: true,
      isRequired: false,
      sortOrder: 0,
    ),
    CatalogField(
      code: 'name',
      label: 'Наименование',
      fieldType: 'text',
      isVisible: true,
      isRequired: true,
      sortOrder: 1,
    ),
    CatalogField(
      code: 'linked_works',
      label: 'Связанные работы',
      fieldType: 'relation',
      isVisible: true,
      isRequired: false,
      sortOrder: 2,
    ),
    CatalogField(
      code: 'base_price',
      label: 'Цена',
      fieldType: 'money',
      isVisible: true,
      isRequired: true,
      sortOrder: 3,
    ),
  ],
  sections: [_equipmentSection],
);

const _workCategory = CatalogCategory(
  id: 'work-category',
  clientId: 'works',
  name: 'Работы',
  sortOrder: 1,
  fields: [],
  sections: [_workSection],
);

const _dependency = CatalogDependency(
  id: 'dependency',
  clientId: 'works-to-equipment',
  sourceCategoryId: 'work-category',
  targetCategoryId: 'equipment-category',
  targetFieldCode: 'linked_works',
  sortOrder: 0,
);

const _configuration = CatalogConfiguration(
  categories: [_equipmentCategory, _workCategory],
  dictionaries: [],
  dependencies: [_dependency],
);

final _equipmentItem = CatalogItem(
  id: 'equipment-item',
  categoryId: _equipmentCategory.id,
  sectionId: _equipmentSection.id,
  groupId: null,
  name: 'Вентилятор',
  marking: 'V-1',
  status: 'approved',
  values: const {
    'unit': 'шт',
    'purchase_price': 800,
    'base_price': 1200,
    'linked_works': <dynamic>['Монтаж оборудования / M-1'],
  },
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);

const _workItemId = 'work-item';

final class _CatalogGatewayWithRelations
    implements CatalogGateway, CatalogRelationGateway {
  @override
  Future<List<CatalogItemRelation>> getRelations(
    String accessToken,
    String itemId,
  ) async => const [
    CatalogItemRelation(
      dependencyId: 'dependency',
      sourceItemId: _workItemId,
      sourceName: 'Монтаж оборудования',
      sourceMarking: 'M-1',
      sortOrder: 0,
      sourceCategoryId: 'work-category',
      sourceSectionId: 'work-section',
      sourceGroupId: 'work-group',
      sourceValues: {'unit': 'шт', 'purchase_price': 40, 'base_price': 100},
    ),
  ];

  @override
  Future<CatalogConfiguration> getConfiguration(String accessToken) async =>
      _configuration;

  @override
  Future<CatalogItemPage> getItems({
    required String accessToken,
    String? categoryId,
    String? sectionId,
    String? status,
    String? search,
    required int page,
    required int pageSize,
  }) async => const CatalogItemPage(items: [], page: 1, pageSize: 50, total: 0);

  @override
  Future<List<CatalogRelationCandidate>> searchRelationCandidates({
    required String accessToken,
    required String dependencyId,
    required String search,
  }) async => const [];

  @override
  Future<List<CatalogItemRelation>> replaceRelations({
    required String accessToken,
    required String itemId,
    required List<CatalogItemRelation> relations,
  }) async => relations;

  @override
  Future<CatalogItem> createItem(String accessToken, CatalogItemDraft draft) =>
      throw UnimplementedError();

  @override
  Future<CatalogItem> updateItem(
    String accessToken,
    String itemId,
    CatalogItemDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteItem(String accessToken, String itemId) async {}

  @override
  void close() {}
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
