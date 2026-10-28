import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:flutter/services.dart';
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

  for (final order in [false, true]) {
    test(
      'structure reorder preserves content and serialized order, order=$order',
      () {
        final auth = AuthController(
          config,
          api: _NoopAuthGateway(),
          tokens: _MemoryTokenRepository(),
        );
        final controller = order
            ? OrderController(config, auth)
            : QuoteController(config, auth);
        final variant = QuoteVariantDraft.create();
        final first = QuoteCategoryDraft(
          id: 'first',
          name: 'First',
          sections: [
            QuoteSectionDraft(id: 's1', name: 'One', positions: []),
            QuoteSectionDraft(id: 's2', name: 'Two', positions: []),
          ],
        );
        final second = QuoteCategoryDraft(
          id: 'second',
          name: 'Second',
          sections: [],
        );
        variant.categories.addAll([first, second]);
        controller.reorderCategory(variant, 0, 2);
        controller.reorderSection(first, 0, 2);
        expect(variant.categories, [second, first]);
        expect(first.sections.map((s) => s.id), ['s2', 's1']);
        expect(controller.dirty, isTrue);
        final restored = QuoteVariantDraft.fromJson(variant.toJson());
        expect(restored.categories.map((c) => c.id), ['second', 'first']);
        expect(restored.categories.last.sections.map((s) => s.id), [
          's2',
          's1',
        ]);
        controller.reorderCategory(variant, 1, 0);
        expect(variant.categories, [first, second]);
        controller.saving = true;
        controller.reorderCategory(variant, 0, 2);
        expect(variant.categories, [first, second]);
        controller.saving = false;
        controller.reorderSection(first, -1, 2);
        expect(first.sections.map((s) => s.id), ['s2', 's1']);
        controller.dispose();
        auth.dispose();
      },
    );
  }

  testWidgets('category move menu changes the document order', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1600);
    addTearDown(tester.view.reset);
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    final controller = QuoteController(config, auth);
    final type = QuoteProposalTypeDraft.create();
    final variant = type.variants.first;
    variant.categories.addAll([
      QuoteCategoryDraft(
        id: 'first',
        name: 'First',
        sections: [
          QuoteSectionDraft(id: 's1', name: 'One', positions: []),
          QuoteSectionDraft(id: 's2', name: 'Two', positions: []),
        ],
      ),
      QuoteCategoryDraft(id: 'second', name: 'Second', sections: []),
    ]);
    controller
      ..draft = QuoteDraft(
        kind: QuoteKind.quote,
        title: 'Test',
        clientId: '',
        executorCompanyId: '',
        selectionMode: 'variant',
        proposalTypes: [type],
      )
      ..activeTypeId = type.id
      ..activeVariantId = variant.id;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuoteEditorPage(
            config: config,
            authController: auth,
            board: _quoteBoard,
            controller: controller,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menu = find.byTooltip('Переместить категорию').first;
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ниже'));
    await tester.pumpAndSettle();
    expect(variant.categories.map((c) => c.id), ['second', 'first']);
    expect(find.byTooltip('Перетащить категорию'), findsNWidgets(2));
    final sectionMenu = find.byTooltip('Переместить раздел').first;
    await tester.ensureVisible(sectionMenu);
    await tester.tap(sectionMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ниже'));
    await tester.pumpAndSettle();
    expect(variant.categories.last.sections.map((s) => s.id), ['s2', 's1']);
    final sectionHandles = find.byTooltip('Перетащить раздел');
    await tester.dragFrom(
      tester.getCenter(sectionHandles.last),
      tester.getCenter(sectionHandles.first) -
          tester.getCenter(sectionHandles.last),
    );
    await tester.pumpAndSettle();
    expect(variant.categories.last.sections.map((s) => s.id), ['s1', 's2']);
    final categoryHandles = find.byTooltip('Перетащить категорию');
    await tester.dragFrom(
      tester.getCenter(categoryHandles.last),
      tester.getCenter(categoryHandles.first) -
          tester.getCenter(categoryHandles.last),
    );
    await tester.pumpAndSettle();
    expect(variant.categories.map((c) => c.id), ['first', 'second']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    auth.dispose();
  });

  testWidgets('типы и варианты доступны списками на всех ширинах', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    final controller = QuoteController(config, auth);
    final types = [
      for (var i = 0; i < 18; i++)
        QuoteProposalTypeDraft.create()..name = 'Тип предложения $i',
    ];
    controller
      ..draft = QuoteDraft(
        kind: QuoteKind.prequote,
        title: 'Тест',
        clientId: '',
        executorCompanyId: '',
        selectionMode: 'variant',
        proposalTypes: types,
      )
      ..activeTypeId = types.first.id
      ..activeVariantId = types.first.variants.first.id;
    for (var i = 0; i < 15; i++) {
      controller.addVariant();
    }
    types.first
      ..selectedByClient = true
      ..selectedVariantId = types.first.variants.first.id;
    types[1]
      ..selectedByClient = true
      ..selectedVariantId = types[1].variants.first.id;
    controller.activeVariant!.categories.addAll([
      for (var i = 0; i < 10; i++)
        QuoteCategoryDraft(id: 'layout-$i', name: 'Категория $i', sections: []),
    ]);
    for (final kind in [QuoteKind.quote, QuoteKind.prequote]) {
      controller.draft!.kind = kind;
      for (final width in [320.0, 375.0, 600.0, 800.0, 1024.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuoteEditorPage(
                config: config,
                authController: auth,
                board: _quoteBoard,
                controller: controller,
                onBack: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final type = tester.widget<AppSelectField<String>>(
          find.byWidgetPredicate(
            (w) => w is AppSelectField<String> && w.label == 'Тип предложения',
          ),
        );
        final variant = tester.widget<AppSelectField<String>>(
          find.byWidgetPredicate(
            (w) => w is AppSelectField<String> && w.label == 'Вариант',
          ),
        );
        expect(type.options, hasLength(18));
        expect(variant.options, hasLength(16));
        expect(type.options.first.highlighted, isTrue);
        expect(type.options[1].highlighted, isFalse);
        expect(type.options[1].label, contains('Выбран клиентом'));
        expect(type.options[2].highlighted, isFalse);
        expect(variant.options.first.highlighted, isFalse);
        expect(variant.options.first.label, contains('Выбран клиентом'));
        expect(variant.options.last.highlighted, isTrue);
        expect(variant.options[1].highlighted, isFalse);
        final typeField = find.byWidgetPredicate(
          (w) => w is AppSelectField<String> && w.label == 'Тип предложения',
        );
        final variantField = find.byWidgetPredicate(
          (w) => w is AppSelectField<String> && w.label == 'Вариант',
        );
        if (width >= 1024) {
          expect(
            tester.getTopLeft(typeField).dy,
            tester.getTopLeft(variantField).dy,
          );
          final metadata = find.byType(TextFormField).first;
          final before = tester.getTopLeft(metadata).dy;
          final scroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('quote-page-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          scroll.position.jumpTo(80);
          await tester.pump();
          expect(tester.getTopLeft(metadata).dy, closeTo(before - 80, 0.1));
          scroll.position.jumpTo(0);
          await tester.pump();
        }
        final heading = find.byKey(
          const Key('quote-category-heading-layout-0'),
        );
        await tester.ensureVisible(heading);
        await tester.pumpAndSettle();
        expect(
          tester
              .getCenter(
                find.descendant(
                  of: heading,
                  matching: find.byIcon(Icons.folder_outlined),
                ),
              )
              .dy,
          closeTo(tester.getCenter(find.text('Категория 0')).dy, 0.1),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    auth.dispose();
  });

  testWidgets('повторный выбор канбанов вызывает штатный выход редактора', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    final controller = QuoteController(config, auth);
    final type = QuoteProposalTypeDraft.create();
    controller
      ..draft = QuoteDraft(
        kind: QuoteKind.prequote,
        title: 'Тест',
        clientId: '',
        executorCompanyId: '',
        selectionMode: 'variant',
        proposalTypes: [type],
      )
      ..activeTypeId = type.id
      ..activeVariantId = type.variants.first.id;
    var exits = 0;
    Widget editor(int request) => MaterialApp(
      home: Scaffold(
        body: QuoteEditorPage(
          config: config,
          authController: auth,
          board: _quoteBoard,
          controller: controller,
          backRequest: request,
          onBack: () => exits++,
        ),
      ),
    );
    await tester.pumpWidget(editor(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(editor(1));
    await tester.pumpAndSettle();
    expect(exits, 1);
    controller.updateDocument((draft) => draft.title = 'Изменено');
    await tester.pumpWidget(editor(2));
    await tester.pumpAndSettle();
    expect(find.text('Есть несохранённые изменения'), findsOneWidget);
    await tester.tap(find.text('Остаться'));
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    auth.dispose();
  });

  testWidgets(
    'уведомление о черновике исчезает через 5 секунд и не стирает новое',
    (tester) async {
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      );
      final controller = QuoteController(config, auth);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.showDraftRestoredMessage();
      await tester.pump(const Duration(seconds: 4));
      expect(controller.successMessage, 'Восстановлен локальный черновик');
      await tester.pump(const Duration(seconds: 1));
      expect(controller.successMessage, isNull);
      expect(notifications, 2);
      controller.showDraftRestoredMessage();
      await tester.pump(const Duration(seconds: 3));
      controller.successMessage = 'Сохранено';
      await tester.pump(const Duration(seconds: 4));
      expect(controller.successMessage, 'Сохранено');
      await tester.pump(const Duration(seconds: 1));
      expect(controller.successMessage, isNull);
      controller.showDraftRestoredMessage();
      controller.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
      auth.dispose();
    },
  );

  test('позиции добавляются прямо в категорию без разделов', () {
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    );
    final controller = QuoteController(config, auth);
    final type = QuoteProposalTypeDraft.create();
    expect(type.selectedVariantId, isNull);
    final category = QuoteCategoryDraft(
      id: 'category',
      name: 'Расходники',
      sections: [],
    );
    type.variants.single.categories.add(category);
    controller.draft = QuoteDraft(
      kind: QuoteKind.quote,
      title: 'КП',
      clientId: 'client',
      executorCompanyId: 'executor',
      selectionMode: 'variant',
      proposalTypes: [type],
    );

    expect(controller.canAddDirectPosition(category), isTrue);
    final direct = controller.ensureDirectSection(category);
    expect(direct.catalogSectionId, isNull);
    expect(direct.name, 'Расходники');
    expect(controller.ensureDirectSection(category), same(direct));
    controller.addEntryPosition(direct);
    expect(category.sections.single.positions, hasLength(1));
    expect(controller.canAddDirectPosition(category), isTrue);

    category.sections.add(
      QuoteSectionDraft(
        id: 'section',
        catalogSectionId: 'catalog-section',
        name: 'Раздел',
        positions: [],
      ),
    );
    expect(controller.canAddDirectPosition(category), isFalse);
    controller.dispose();
    auth.dispose();
  });

  test(
    'удаление типов и вариантов исправляет выбор и защищает последние вкладки',
    () {
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      );
      final controller = QuoteController(config, auth);
      final first = QuoteProposalTypeDraft.create(name: 'Первый');
      final second = QuoteProposalTypeDraft.create(name: 'Второй');
      controller.draft = QuoteDraft(
        kind: QuoteKind.quote,
        title: 'КП',
        clientId: 'client',
        executorCompanyId: 'executor',
        selectionMode: 'variant',
        proposalTypes: [first, second],
      );
      controller.selectType(second.id);
      final variant = controller.addVariant();
      second.selectedVariantId = variant.id;
      second.selectedByClient = true;
      controller.dirty = false;
      controller.removeVariant(second.id, variant.id);
      expect(second.variants, hasLength(1));
      expect(controller.activeVariantId, second.variants.single.id);
      expect(second.selectedVariantId, isNull);
      expect(second.selectedByClient, isFalse);
      expect(controller.dirty, isTrue);
      controller.dirty = false;
      controller.removeVariant(second.id, second.variants.single.id);
      expect(second.variants, hasLength(1));
      expect(controller.dirty, isFalse);
      controller.draft!.clientSelectedProposalTypeId = second.id;
      controller.removeType(second.id);
      expect(controller.activeTypeId, first.id);
      expect(controller.activeVariantId, first.variants.single.id);
      expect(controller.draft!.clientSelectedProposalTypeId, isNull);
      expect(controller.dirty, isTrue);
      controller.dirty = false;
      controller.removeType(first.id);
      expect(controller.draft!.proposalTypes, hasLength(1));
      expect(controller.dirty, isFalse);
      controller.dispose();
      auth.dispose();
    },
  );

  test(
    'массовые проценты применяются ко всему разделу или выделенным строкам',
    () {
      final auth = AuthController(
        config,
        api: _NoopAuthGateway(),
        tokens: _MemoryTokenRepository(),
      );
      final controller = QuoteController(config, auth);
      final section = QuoteSectionDraft(
        id: 'section',
        name: 'Раздел',
        positions: [
          for (var i = 0; i < 3; i++)
            QuotePositionDraft(
              id: '$i',
              name: 'Товар',
              marking: '',
              unit: 'шт',
              quantity: 1,
              basePrice: 100,
              values: {},
            ),
        ],
      );
      controller.applyPercent(section, value: 12, markup: true);
      controller.applyPercent(section, value: 5, markup: false);
      expect(section.positions.map((p) => p.markupPercent), [12, 12, 12]);
      expect(section.positions.map((p) => p.discountPercent), [5, 5, 5]);
      section.positions[1].selected = true;
      controller.applyPercent(section, value: 20, markup: true);
      controller.applyPercent(section, value: 0, markup: false);
      expect(section.positions.map((p) => p.markupPercent), [12, 20, 12]);
      expect(section.positions.map((p) => p.discountPercent), [5, 0, 5]);
      controller.applyPercent(
        section,
        value: 17,
        markup: true,
        fieldCode: 'custom_markup',
      );
      expect(section.positions.map((p) => p.values['custom_markup']), [
        null,
        17,
        null,
      ]);
      section.positions[1].selected = false;
      controller.applyPercent(
        section,
        value: 3,
        markup: false,
        fieldCode: 'custom_discount',
      );
      expect(section.positions.map((p) => p.values['custom_discount']), [
        3,
        3,
        3,
      ]);
      expect(section.positions.map((p) => p.markupPercent), [12, 20, 12]);
      expect(section.positions.map((p) => p.discountPercent), [5, 0, 5]);
      controller.dispose();
      auth.dispose();
    },
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
      expect(equipmentSection.positions, hasLength(1));
      expect(equipmentSection.positions.single.quantity, 2);

      equipmentSection.positions.first.selected = true;
      controller.applyPercent(equipmentSection, value: 9, markup: false);
      expect(equipmentSection.positions.first.discountPercent, 9);
      expect(equipmentSection.positions.single.discountPercent, 9);

      controller.setSectionSelection(equipmentSection, true);
      expect(
        equipmentSection.positions.every((position) => position.selected),
        isTrue,
      );
      controller.removeSelectedPositions(equipmentSection);
      expect(equipmentSection.positions, isEmpty);
      expect(workPositions.single.quantity, 3);

      for (final deleteCategory in [false, true]) {
        final extraSection = QuoteSectionDraft(
          id: newQuoteId(),
          name: 'Удаляемый раздел',
          positions: [],
        );
        equipmentCategory.sections.add(extraSection);
        await controller.addCatalogPosition(
          equipmentCategory,
          extraSection,
          _equipmentItem,
        );
        expect(workPositions.single.quantity, 4);
        controller.dirty = false;
        if (deleteCategory) {
          controller.removeCategory(equipmentCategory);
          expect(variant.categories, isNot(contains(equipmentCategory)));
        } else {
          controller.removeSection(extraSection);
          expect(equipmentCategory.sections, isNot(contains(extraSection)));
        }
        expect(workPositions.single.quantity, 3);
        expect(workPositions.single.manualPrice, 150);
        expect(controller.dirty, isTrue);
        expect(variant.positions, contains(workPositions.single));
      }

      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets('ПКП использует поля канбана и раскрывает загруженный вариант', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetViewInsets);
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

    final fields = _quoteBoard.categories.single.fields.toList();
    final testBoard = KanbanBoard(
      id: _quoteBoard.id,
      code: _quoteBoard.code,
      name: _quoteBoard.name,
      specialization: _quoteBoard.specialization,
      columns: [],
      transitions: [],
      categories: [
        KanbanCategory(
          categoryId: _quoteBoard.categories.single.categoryId,
          name: 'Оборудование',
          sortOrder: 0,
          fields: fields,
          sections: _quoteBoard.categories.single.sections,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SizedBox(
            width: 1500,
            height: 900,
            child: QuoteEditorPage(
              config: config,
              authController: auth,
              board: testBoard,
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
    expect(find.text('Наценка'), findsNothing);
    expect(find.text('Скидка'), findsNothing);
    expect(find.text('Применить'), findsNothing);
    for (final codes in [
      ['markup_value'],
      ['discount_value'],
      ['markup_value', 'discount_value'],
      ['custom_markup'],
      ['custom_discount'],
      ['custom_markup', 'custom_discount'],
    ]) {
      fields.removeWhere((field) => field.fieldType == 'percent');
      fields.addAll([
        for (final code in codes)
          KanbanField(
            code: code,
            label: code.contains('markup') ? 'Наценка' : 'Скидка',
            fieldType: 'percent',
            isRequired: false,
            sortOrder: 10,
            options: [],
          ),
      ]);
      await controller.positionChanged();
      await tester.pump();
      expect(
        find.text('Наценка'),
        codes.any((code) => code.contains('markup'))
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.text('Скидка'),
        codes.any((code) => code.contains('discount'))
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.text('Применить'), findsNWidgets(codes.length));
      final addX = tester.getTopRight(find.byTooltip('Добавить позицию')).dx;
      final deleteX = tester.getTopLeft(find.byTooltip('Удалить раздел')).dx;
      for (final label in ['Наценка', 'Скидка', 'Итого']) {
        if (find.text(label).evaluate().isEmpty) continue;
        expect(tester.getTopLeft(find.text(label)).dx, greaterThan(addX));
        expect(tester.getTopRight(find.text(label)).dx, lessThan(deleteX));
      }
      expect(tester.takeException(), isNull);
    }
    fields.removeWhere((field) => field.fieldType == 'percent');
    await controller.positionChanged();
    await tester.pump();
    expect(
      tester.getCenter(find.byTooltip('Добавить раздел')).dx,
      greaterThan(tester.getTopRight(find.text('Оборудование')).dx),
    );
    expect(
      tester.getCenter(find.byTooltip('Добавить позицию')).dx,
      greaterThan(tester.getTopRight(find.text('Вентиляция')).dx),
    );
    expect(
      tester
          .getTopLeft(find.widgetWithText(OutlinedButton, 'Добавить категорию'))
          .dx,
      lessThan(tester.getTopLeft(find.text('Оборудование')).dx),
    );
    expect(find.text('Вентилятор'), findsOneWidget);
    expect(find.text('НАИМЕНОВАНИЕ'), findsOneWidget);
    expect(find.text('ЦЕНА'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Закупка')).dx,
      greaterThan(tester.getTopRight(find.byTooltip('Добавить раздел')).dx),
    );
    expect(
      tester.getTopRight(find.text('Розница')).dx,
      lessThan(tester.getTopLeft(find.byTooltip('Удалить категорию')).dx),
    );
    expect(find.text('ГРУППА'), findsNothing);
    expect(find.text('СВЯЗАННЫЕ РАБОТЫ'), findsNothing);
    final variantSummary = tester.getTopLeft(find.text('Сводка варианта'));
    final typeSummary = tester.getTopLeft(find.text('Сводка типа'));
    expect(typeSummary.dy, variantSummary.dy);
    expect(typeSummary.dx, greaterThan(variantSummary.dx));
    expect(tester.takeException(), isNull);
    section.positions.single.marking = 'changed-by-rule';
    await controller.positionChanged();
    await tester.pump();
    expect(find.text('changed-by-rule'), findsOneWidget);

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
    for (final code in ['base_price', 'unit']) {
      final before = {
        for (final field in fields)
          field.code: tester
              .getSize(find.byKey(ValueKey('quote-column-${field.code}')).first)
              .width,
      };
      await tester.drag(
        find.byKey(ValueKey('quote-column-resize-$code')).first,
        const Offset(-25, 0),
      );
      await tester.pump();
      for (final field in fields) {
        final width = tester
            .getSize(find.byKey(ValueKey('quote-column-${field.code}')).first)
            .width;
        expect(
          width,
          closeTo(before[field.code]! - (field.code == code ? 25 : 0), 1),
        );
      }
    }
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
              board: testBoard,
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

    final originalType = controller.activeType!;
    await tester.tap(find.byTooltip('Добавить вариант'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Удалить вариант').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(originalType.variants, hasLength(2));
    await tester.tap(find.byTooltip('Удалить вариант').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(originalType.variants, hasLength(1));
    expect(find.byTooltip('Нельзя удалить последний вариант'), findsOneWidget);
    await tester.tap(find.byTooltip('Добавить тип'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Удалить тип').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(controller.activeType, same(originalType));
    expect(find.byTooltip('Нельзя удалить последний тип'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Удалить раздел'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(category.sections, contains(section));
    await tester.tap(find.byTooltip('Удалить раздел'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(category.sections, isEmpty);
    expect(variant.systemSummary.total, 0);
    await tester.tap(find.byTooltip('Удалить категорию'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(variant.categories, contains(category));
    await tester.tap(find.byTooltip('Удалить категорию'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(variant.categories, isEmpty);
    expect(controller.dirty, isTrue);
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

  test(
    'строка ввода заполняется из каталога, пустые строки не сохраняются',
    () async {
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
      final section = QuoteSectionDraft(
        id: 'entry-section',
        catalogSectionId: _equipmentSection.id,
        name: _equipmentSection.name,
        positions: [],
      );
      final category = QuoteCategoryDraft(
        id: 'entry-category',
        catalogCategoryId: _equipmentCategory.id,
        name: _equipmentCategory.name,
        sections: [section],
      );
      final variant = QuoteVariantDraft(
        id: 'entry-variant',
        name: 'Основной',
        categories: [category],
      );
      final type = QuoteProposalTypeDraft(
        id: 'entry-type',
        name: 'Основное предложение',
        variants: [variant],
      );
      controller
        ..catalog = _configuration
        ..draft = QuoteDraft(
          kind: QuoteKind.quote,
          title: 'КП',
          clientId: 'client',
          executorCompanyId: 'executor',
          selectionMode: 'variant',
          proposalTypes: [type],
        )
        ..activeTypeId = type.id
        ..activeVariantId = variant.id;

      final row = controller.addEntryPosition(section);
      expect(controller.focusRequestPositionId, row.id);
      expect(
        controller.catalogGroups(category, section).map((group) => group.name),
        ['Вентиляторы'],
      );

      await controller.lookupCatalogItems(
        category: category,
        section: section,
        groupName: 'вентиляторы',
        search: 'вент',
      );
      expect(_CatalogGatewayWithRelations.lastGroupId, 'equipment-group');

      row
        ..name = ' вентилятор '
        ..quantity = 3;
      final item = await controller.resolveEntryItem(
        category: category,
        section: section,
        position: row,
      );
      expect(item?.id, _equipmentItem.id);
      await controller.applyCatalogItem(category, section, row, item!);
      expect(row.catalogItemId, _equipmentItem.id);
      expect(row.name, 'Вентилятор');
      expect(row.marking, 'V-1');
      expect(row.unit, 'шт');
      expect(row.basePrice, 1200);
      expect(row.quantity, 3);

      row.marking = 'другая';
      expect(
        await controller.resolveEntryItem(
          category: category,
          section: section,
          position: row,
        ),
        isNull,
      );
      controller.detachCatalogItem(row);
      expect(row.catalogItemId, isNull);
      row.marking = 'V-1';

      controller.addEntryPosition(section);
      expect(section.positions, hasLength(2));
      expect(await controller.save(board: _quoteBoard), isTrue);
      final saved = gateway.savedDraft!.proposalTypes.single.variants.single;
      final savedSection = saved.categories
          .firstWhere((item) => item.id == category.id)
          .sections
          .single;
      expect(savedSection.positions.map((item) => item.id), [row.id]);

      controller.dispose();
      auth.dispose();
    },
  );

  testWidgets('group column is omitted only for sections without groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthController(
      config,
      api: _NoopAuthGateway(),
      tokens: _MemoryTokenRepository(),
    )..accessToken = 'access-token';
    final controller = QuoteController(config, auth);
    const emptySection = CatalogSection(
      id: 'no-groups',
      name: 'Без групп',
      sortOrder: 1,
      groups: [],
    );
    controller.catalog = CatalogConfiguration(
      categories: [
        CatalogCategory(
          id: _equipmentCategory.id,
          clientId: 'equipment',
          name: 'Оборудование',
          sortOrder: 0,
          fields: _equipmentCategory.fields,
          sections: [_equipmentSection, emptySection],
        ),
      ],
      dictionaries: [],
      dependencies: [],
    );
    // Сохранённая позиция, уже связанная с каталогом (как после повторного
    // открытия редактора).
    final saved = QuotePositionDraft(
      id: 'saved',
      catalogItemId: _equipmentItem.id,
      name: 'Вентилятор',
      marking: 'V-1',
      unit: 'шт',
      quantity: 1,
      basePrice: 1200,
      values: <String, dynamic>{},
    );
    final sections = [
      for (final source in [_equipmentSection, emptySection])
        QuoteSectionDraft(
          id: source.id,
          catalogSectionId: source.id,
          name: source.name,
          positions: [if (source == _equipmentSection) saved],
        ),
    ];
    final category = QuoteCategoryDraft(
      id: 'category',
      catalogCategoryId: _equipmentCategory.id,
      name: 'Оборудование',
      sections: sections,
    );
    final variant = QuoteVariantDraft(
      id: 'variant',
      name: 'Вариант',
      categories: [category],
    );
    final type = QuoteProposalTypeDraft(
      id: 'type',
      name: 'Тип',
      variants: [variant],
    );
    controller
      ..draft = QuoteDraft(
        kind: QuoteKind.quote,
        title: 'КП',
        clientId: 'client',
        executorCompanyId: 'executor',
        selectionMode: 'variant',
        proposalTypes: [type],
      )
      ..activeTypeId = type.id
      ..activeVariantId = variant.id;
    final board = KanbanBoard(
      id: _quoteBoard.id,
      code: _quoteBoard.code,
      name: _quoteBoard.name,
      specialization: _quoteBoard.specialization,
      columns: [],
      transitions: [],
      categories: [
        KanbanCategory(
          categoryId: _equipmentCategory.id,
          name: 'Оборудование',
          sortOrder: 0,
          sections: [],
          fields: [
            const KanbanField(
              code: 'group',
              label: 'Группа',
              fieldType: 'dictionary',
              isRequired: true,
              sortOrder: -1,
              options: [],
            ),
            ..._quoteBoard.categories.single.fields,
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuoteEditorPage(
            config: config,
            authController: auth,
            board: board,
            controller: controller,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ГРУППА'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quote-entry-saved-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('quote-entry-saved-marking')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Добавить позицию').last);
    await tester.pumpAndSettle();
    final row = sections.last.positions.single;
    expect(find.byKey(ValueKey('quote-entry-${row.id}-group')), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'quote-entry-${row.id}-name',
    );
    expect(row.values.containsKey('group'), isFalse);
    expect(sections.first.positions, [saved]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    auth.dispose();
  });

  testWidgets('позиция вводится в строке: автопоиск, Enter и новая строка', (
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
      id: 'entry-section',
      catalogSectionId: _equipmentSection.id,
      name: _equipmentSection.name,
      positions: [],
    );
    final category = QuoteCategoryDraft(
      id: 'entry-category',
      catalogCategoryId: _equipmentCategory.id,
      name: _equipmentCategory.name,
      sections: [section],
    );
    final variant = QuoteVariantDraft(
      id: 'entry-variant',
      name: 'Основной',
      categories: [category],
    );
    final type = QuoteProposalTypeDraft(
      id: 'entry-type',
      name: 'Основное предложение',
      variants: [variant],
    );
    controller
      ..catalog = _configuration
      ..draft = QuoteDraft(
        kind: QuoteKind.quote,
        title: 'КП',
        clientId: 'client',
        executorCompanyId: 'executor',
        selectionMode: 'variant',
        proposalTypes: [type],
      )
      ..activeTypeId = type.id
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

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    Finder input(String positionId, String code) => find.descendant(
      of: find.byKey(ValueKey('quote-entry-$positionId-$code')),
      matching: find.byType(TextField),
    );

    await tester.tap(find.byTooltip('Добавить позицию'));
    await tester.pumpAndSettle();
    expect(section.positions, hasLength(1));
    final row = section.positions.single;
    expect(focused(), 'quote-entry-${row.id}-name');
    variant.categories.add(
      QuoteCategoryDraft(id: 'extra-category', name: 'Extra', sections: []),
    );
    row.unit = '';
    controller.positionChanged();
    await tester.pumpAndSettle();
    expect(find.text('Не выбрано'), findsWidgets);

    await tester.enterText(input(row.id, 'name'), 'вент');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(_CatalogGatewayWithRelations.lastSearch, 'вент');
    expect(
      find.byKey(const ValueKey('quote-entry-option-Вентилятор')),
      findsOneWidget,
    );
    final nameOption = find.byKey(
      const ValueKey('quote-entry-option-Вентилятор'),
    );
    expect(
      tester.getTopLeft(nameOption).dy,
      greaterThan(tester.getBottomLeft(input(row.id, 'name')).dy),
    );
    tester.view.viewInsets = FakeViewPadding(
      bottom: 1200 - tester.getBottomLeft(input(row.id, 'name')).dy - 12,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(nameOption).dy,
      lessThan(tester.getTopLeft(input(row.id, 'name')).dy),
    );
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();

    // Enter выбирает подсвеченный вариант; единственная карточка с таким
    // наименованием сразу заполняет строку, фокус переходит в маркировку.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(row.catalogItemId, _equipmentItem.id);
    expect(row.basePrice, 1200);
    expect(focused(), 'quote-entry-${row.id}-marking');
    expect(
      tester.widget<TextField>(input(row.id, 'marking')).controller!.text,
      'V-1',
    );

    // Стрелка открывает маркировки выбранного наименования.
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('quote-entry-${row.id}-marking')),
        matching: find.byTooltip('Показать варианты'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('quote-entry-option-V-1')),
      findsOneWidget,
    );
    tester.view.viewInsets = FakeViewPadding(
      bottom: 1200 - tester.getBottomLeft(input(row.id, 'marking')).dy - 12,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('quote-entry-option-V-1')))
          .dy,
      lessThan(tester.getTopLeft(input(row.id, 'marking')).dy),
    );
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final dragHandle = find.byTooltip('Перетащить категорию').first;
    await tester.ensureVisible(dragHandle);
    final gesture = await tester.startGesture(tester.getCenter(dragHandle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 35));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('quote-entry-option-V-1')), findsNothing);
    await tester.ensureVisible(input(row.id, 'marking'));
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('quote-entry-${row.id}-marking')),
        matching: find.byTooltip('Показать варианты'),
      ),
    );
    await tester.pumpAndSettle();
    final moveMenu = find.byTooltip('Переместить категорию').first;
    await tester.ensureVisible(moveMenu);
    await tester.tap(moveMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ниже'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(row.marking, 'V-1');
    final categoryOrder = variant.categories.map((c) => c.id).toList();
    expect(categoryOrder.take(2), ['extra-category', category.id]);
    final upwardHandles = find.byTooltip('Перетащить категорию');
    await tester.ensureVisible(upwardHandles.first);
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getCenter(upwardHandles.at(1)),
      tester.getCenter(upwardHandles.first) -
          tester.getCenter(upwardHandles.at(1)),
    );
    await tester.pumpAndSettle();
    expect(variant.categories.map((c) => c.id), [
      category.id,
      'extra-category',
      ...categoryOrder.skip(2),
    ]);
    expect(section.positions.single, same(row));
    expect(row.name, 'Вентилятор');
    expect(row.marking, 'V-1');
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(input(row.id, 'marking'));
    await tester.tap(input(row.id, 'marking'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(focused(), 'quote-entry-${row.id}-quantity');

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(section.positions, hasLength(2));
    final next = section.positions.last;
    expect(next.name, isEmpty);
    expect(focused(), 'quote-entry-${next.id}-name');

    // Enter в количестве пустой строки не плодит новые строки.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(focused(), 'quote-entry-${next.id}-marking');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(section.positions, hasLength(2));
    expect(focused(), 'quote-entry-${next.id}-name');
    expect(tester.takeException(), isNull);

    controller.dispose();
    auth.dispose();
  });

  testWidgets('предпросмотр и печать спрашивают: вариант, тип или всё', (
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
    final gateway = _RecordingQuoteGateway();
    final controller = QuoteController(
      config,
      auth,
      quoteGateway: gateway,
      catalogGateway: _CatalogGatewayWithRelations(),
    );
    controller
      ..catalog = _configuration
      ..draft = _twoTypeDraft()
      ..activeTypeId = 'type-conditioners'
      ..activeVariantId = 'variant-premium';
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

    Future<void> openPreviewWith(String optionKey) async {
      await tester.tap(find.text('Предпросмотр'));
      await tester.pumpAndSettle();
      expect(find.text('Что показать?'), findsOneWidget);
      await tester.tap(find.byKey(Key(optionKey)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quote-preview-page')), findsOneWidget);
    }

    // Окно называет то, что откроется, и считает содержимое.
    await tester.tap(find.text('Предпросмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Вариант «Премиум»'), findsOneWidget);
    expect(find.text('Тип «Кондиционеры»'), findsWidgets);
    expect(find.text('Все варианты типа: 2 варианта'), findsOneWidget);
    expect(find.text('Все типы и варианты: 2 типа'), findsOneWidget);
    await tester.tap(find.byKey(const Key('print-scope-variant')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('quote-preview-variant-variant-premium')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('quote-preview-variant-variant-economy')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('quote-preview-type-type-boilers')),
      findsNothing,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openPreviewWith('print-scope-type');
    expect(
      find.byKey(const Key('quote-preview-variant-variant-premium')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('quote-preview-variant-variant-economy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('quote-preview-type-type-boilers')),
      findsNothing,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openPreviewWith('print-scope-all');
    expect(
      find.byKey(const Key('quote-preview-type-type-boilers')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('quote-preview-variant-variant-economy')),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Печать: несохранённый документ не даёт выбрать — сразу понятная причина.
    await tester.tap(find.text('Печать'));
    await tester.pumpAndSettle();
    expect(find.text('Что напечатать?'), findsNothing);
    expect(controller.error, 'Сначала сохраните предложение.');

    controller.persistedCardId = 'card-id';
    await tester.tap(find.text('Печать'));
    await tester.pumpAndSettle();
    expect(find.text('Что напечатать?'), findsOneWidget);
    // Отмена выбора ничего не печатает.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Что напечатать?'), findsNothing);
    expect(gateway.downloadCalls, 0);
    expect(tester.takeException(), isNull);

    controller.dispose();
    auth.dispose();
  });

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

    controller
      ..draft = _twoTypeDraft()
      ..activeTypeId = 'type-conditioners'
      ..activeVariantId = 'variant-premium';

    controller.dirty = true;
    expect(
      await controller.downloadPdf(
        board: _quoteBoard,
        scope: QuotePrintScope.all,
      ),
      isNull,
    );
    expect(controller.error, 'Сохраните изменения перед печатью.');
    expect(gateway.downloadCalls, 0);

    controller.dirty = false;
    final file = await controller.downloadPdf(
      board: _quoteBoard,
      scope: QuotePrintScope.variant,
    );
    expect(file?.fileName, 'КП.pdf');
    expect(file?.bytes, [0x25, 0x50, 0x44, 0x46]);
    expect(gateway.downloadCalls, 1);
    expect(gateway.lastBoardId, _quoteBoard.id);
    expect(gateway.lastCardId, 'card-id');
    expect(gateway.lastProposalTypeId, 'type-conditioners');
    expect(gateway.lastVariantId, 'variant-premium');

    // «Тип»: только тип, без варианта — сервер вернёт все его варианты.
    await controller.downloadPdf(
      board: _quoteBoard,
      scope: QuotePrintScope.type,
    );
    expect(gateway.lastProposalTypeId, 'type-conditioners');
    expect(gateway.lastVariantId, isNull);

    // «Всё»: без ограничений.
    await controller.downloadPdf(
      board: _quoteBoard,
      scope: QuotePrintScope.all,
    );
    expect(gateway.lastProposalTypeId, isNull);
    expect(gateway.lastVariantId, isNull);
    expect(gateway.downloadCalls, 3);

    controller.dispose();
    auth.dispose();
  });
}

/// Документ с двумя типами: «Кондиционеры» (два варианта) и «Бойлеры».
QuoteDraft _twoTypeDraft() => QuoteDraft(
  kind: QuoteKind.quote,
  title: 'КП',
  clientId: 'client',
  executorCompanyId: 'executor',
  selectionMode: 'variant',
  proposalTypes: [
    QuoteProposalTypeDraft(
      id: 'type-conditioners',
      name: 'Кондиционеры',
      variants: [
        QuoteVariantDraft(
          id: 'variant-economy',
          name: 'Эконом',
          categories: [],
        ),
        QuoteVariantDraft(
          id: 'variant-premium',
          name: 'Премиум',
          categories: [],
        ),
      ],
    ),
    QuoteProposalTypeDraft(
      id: 'type-boilers',
      name: 'Бойлеры',
      variants: [
        QuoteVariantDraft(id: 'variant-basic', name: 'Базовый', categories: []),
      ],
    ),
  ],
);

final class _RecordingQuoteGateway implements QuoteGateway {
  int downloadCalls = 0;
  String? lastBoardId;
  String? lastCardId;
  String? lastProposalTypeId;
  String? lastVariantId;

  @override
  Future<QuotePdfDownload> downloadPdf(
    String accessToken,
    String boardId,
    String cardId, {
    String? proposalTypeId,
    String? variantId,
  }) async {
    downloadCalls++;
    lastBoardId = boardId;
    lastCardId = cardId;
    lastProposalTypeId = proposalTypeId;
    lastVariantId = variantId;
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

  QuoteDraft? savedDraft;

  @override
  Future<QuoteDraft> saveQuote(
    String accessToken,
    String boardId,
    String cardId,
    QuoteDraft draft,
  ) async => savedDraft = draft;

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
  groups: [
    CatalogGroup(id: 'equipment-group', name: 'Вентиляторы', sortOrder: 0),
  ],
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
  static String? lastSearch;
  static String? lastGroupId;
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
    String? groupId,
    String? status,
    String? search,
    required int page,
    required int pageSize,
    String? sort,
  }) async {
    lastSearch = search;
    lastGroupId = groupId;
    final needle = (search ?? '').trim().toLowerCase();
    final items = [_equipmentItem]
        .where(
          (item) =>
              (categoryId == null || item.categoryId == categoryId) &&
              (sectionId == null || item.sectionId == sectionId) &&
              (groupId == null || item.groupId == groupId) &&
              (needle.isEmpty ||
                  item.name.toLowerCase().contains(needle) ||
                  item.marking.toLowerCase().contains(needle)),
        )
        .toList();
    return CatalogItemPage(
      items: items,
      page: 1,
      pageSize: pageSize,
      total: items.length,
    );
  }

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
