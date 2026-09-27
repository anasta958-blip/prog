import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_preview_page.dart';

void main() {
  testWidgets('предпросмотр показывает текущий черновик и рассчитанный итог', (
    tester,
  ) async {
    final draft = _draft();
    draft.title = 'Изменённое без сохранения КП';

    await tester.pumpWidget(
      MaterialApp(home: QuotePreviewPage(draft: draft, cardNumber: 17)),
    );

    expect(find.byKey(const Key('quote-preview-page')), findsOneWidget);
    expect(find.text('Изменённое без сохранения КП'), findsOneWidget);
    expect(find.text('Кассетный кондиционер'), findsOneWidget);
    expect(find.text('24\u00A0000,00 ₽'), findsWidgets);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('quote-preview-section-total-section-1')),
          )
          .data,
      '24\u00A0000,00 ₽',
    );
    expect(find.textContaining('Итого: '), findsWidgets);
    expect(find.textContaining('Итого для клиента'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('предпросмотр не переполняется на узком экране', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: QuotePreviewPage(draft: _draft())),
    );
    await tester.pump();

    expect(find.byKey(const Key('quote-preview-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('предпросмотр показывает только открытые тип и вариант', (
    tester,
  ) async {
    final draft = _draft();
    draft.proposalTypes.first.variants.add(
      QuoteVariantDraft(id: 'variant-2', name: 'Премиум', categories: []),
    );
    draft.proposalTypes.add(
      QuoteProposalTypeDraft(
        id: 'type-2',
        name: 'Бойлеры',
        variants: [
          QuoteVariantDraft(id: 'variant-3', name: 'Базовый', categories: []),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuotePreviewPage(
          draft: draft,
          proposalTypeId: 'type-1',
          variantId: 'variant-2',
        ),
      ),
    );

    expect(find.byKey(const Key('quote-preview-type-type-1')), findsOneWidget);
    expect(find.byKey(const Key('quote-preview-type-type-2')), findsNothing);
    expect(
      find.byKey(const Key('quote-preview-variant-variant-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('quote-preview-variant-variant-1')),
      findsNothing,
    );
    expect(find.text('Сводка типа'), findsNothing);
  });

  testWidgets('без выбранного варианта показывается весь документ', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuotePreviewPage(draft: _draft(), variantId: 'missing'),
      ),
    );

    expect(
      find.byKey(const Key('quote-preview-variant-variant-1')),
      findsOneWidget,
    );
    expect(find.text('Сводка типа'), findsOneWidget);
  });
}

QuoteDraft _draft() {
  final position = QuotePositionDraft(
    id: 'position-1',
    name: 'Кассетный кондиционер',
    marking: 'AC-24',
    unit: 'шт',
    quantity: 2,
    purchasePrice: 8000,
    basePrice: 12000,
    values: {},
  );
  final section = QuoteSectionDraft(
    id: 'section-1',
    name: 'Внутренние блоки',
    positions: [position],
  );
  final category = QuoteCategoryDraft(
    id: 'category-1',
    name: 'Оборудование',
    sections: [section],
  );
  final variant = QuoteVariantDraft(
    id: 'variant-1',
    name: 'Оптимальный',
    categories: [category],
    vatRate: 20,
  );
  final type = QuoteProposalTypeDraft(
    id: 'type-1',
    name: 'Кондиционеры',
    variants: [variant],
    selectedVariantId: variant.id,
  );
  return QuoteDraft(
    kind: QuoteKind.quote,
    title: 'Тестовое КП',
    clientId: '',
    executorCompanyId: '',
    selectionMode: 'variant',
    proposalTypes: [type],
  );
}
