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
