import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

void main() {
  test('НДС начисляется сверху, цена и прибыль остаются без НДС', () {
    final variant = _variant('НДС', 4100)..vatRate = 1;
    expect(variant.clientTotal, 4100);
    expect(variant.vatAmount, 41);
    expect(variant.totalWithVat, 4141);
    final margin = variant.margin;
    variant.vatRate = 20;
    expect(variant.vatAmount, 820);
    expect(variant.totalWithVat, 4920);
    expect(variant.margin, margin);
    variant.vatRate = 0;
    expect(variant.totalWithVat, 4100);
    variant.vatRate = null;
    expect(variant.vatAmount, 0);
    expect(variant.totalWithVat, 4100);
  });
  test('сводка типа суммирует НДС вариантов с разными ставками', () {
    final type = QuoteProposalTypeDraft(
      id: 'type-vat',
      name: 'Тип',
      variants: [
        _variant('Первый', 4100)..vatRate = 1,
        _variant('Второй', 1000)..vatRate = 20,
      ],
    );
    expect(type.clientTotal, 5100);
    expect(type.vatAmount, 241);
    expect(type.totalWithVat, 5341);
    expect(type.systemSummary.subtotal, 5100);
    expect(type.systemSummary.vat, 241);
    expect(type.systemSummary.total, 5341);
  });
  test('новый вариант получает актуальную ставку НДС организации', () {
    final type = QuoteProposalTypeDraft.create(initialVatRate: 22);

    expect(type.variants.single.vatRate, 22);
  });

  test(
    'строка считается в фиксированном порядке цена-наценка-скидка-количество',
    () {
      final position = _position(
        basePrice: 100,
        quantity: 3,
        markupPercent: 20,
        discountPercent: 10,
      );

      expect(position.unitPrice, 108);
      expect(position.lineTotal, 324);

      position.manualPrice = 150;

      expect(position.unitPrice, 162);
      expect(position.lineTotal, 486);
    },
  );

  test('сумма строки округляется независимо от цены единицы', () {
    final position = _position(basePrice: 99.995, quantity: 2);

    expect(position.unitPrice, 100);
    expect(position.lineTotal, 199.99);
  });

  test('денежные итоги округляются до копеек на каждом уровне', () {
    final section = QuoteSectionDraft(
      id: 'section-rounding',
      name: 'Раздел',
      positions: [
        _position(basePrice: 33.335, quantity: 3),
        _position(basePrice: 10.005, quantity: 2),
      ],
    );
    final category = QuoteCategoryDraft(
      id: 'category-rounding',
      name: 'Категория',
      sections: [section],
    );
    final variant = QuoteVariantDraft(
      id: 'variant-rounding',
      name: 'Вариант',
      vatRate: 20,
      categories: [category],
    );

    expect(section.clientTotal, 120.02);
    expect(category.clientTotal, 120.02);
    expect(variant.clientTotal, 120.02);
    expect(variant.vatAmount, 24);
    expect(variant.totalWithVat, 144.02);
  });

  test('исключённая позиция не входит в итоги раздела и варианта', () {
    final included = _position(basePrice: 120, quantity: 2);
    final excluded = _position(
      basePrice: 500,
      quantity: 4,
      excludeFromTotals: true,
    );
    final section = QuoteSectionDraft(
      id: 'section-1',
      name: 'Монтажные работы',
      positions: [included, excluded],
    );
    final variant = QuoteVariantDraft(
      id: 'variant-1',
      name: 'Основной',
      categories: [
        QuoteCategoryDraft(
          id: 'category-1',
          name: 'Работы',
          sections: [section],
        ),
      ],
    );

    expect(section.clientTotal, 240);
    expect(variant.clientTotal, 240);
  });

  test('сводка типа суммирует все входящие варианты', () {
    final type = QuoteProposalTypeDraft(
      id: 'type-1',
      name: 'Кондиционеры',
      variants: [_variant('Бюджетный', 100), _variant('Премиальный', 350)],
    );

    expect(type.clientTotal, 450);
    expect(type.purchaseTotal, 0);
    expect(type.margin, 450);
    expect(type.marginPercent, 0);
  });

  test('отрицательная расчётная цена распознаётся до сохранения', () {
    final position = _position(basePrice: 100, discountPercent: 150);

    expect(position.hasValidCalculatedPrice, isFalse);
    expect(position.unitPrice, -50);
    expect(position.lineTotal, -50);
  });

  test('JSON сохраняет типы, варианты, разделы и дополнительные данные', () {
    final source = QuoteDraft(
      id: 'quote-1',
      kind: QuoteKind.prequote,
      title: 'Проект офиса',
      clientId: 'client-1',
      executorCompanyId: 'company-1',
      managerUserId: 'manager-1',
      selectionMode: 'proposal_type',
      additionalInformation: 'Срок поставки 14 дней',
      proposalTypes: [
        QuoteProposalTypeDraft(
          id: 'type-1',
          name: 'Кондиционеры',
          selectedVariantId: 'variant-1',
          variants: [_variant('Оптимальный', 275)],
        ),
      ],
    );

    final restored = QuoteDraft.fromJson({
      'id': source.id,
      ...source.toJson(),
      'clientSelectedProposalTypeId': 'type-1',
      'clientSelectionSubmittedAt': '2026-09-09T18:30:00Z',
      'proposalTypes': [
        {
          ...source.toJson()['proposalTypes'][0] as Map<String, dynamic>,
          'selectedByClient': true,
        },
      ],
    });

    expect(restored.kind, QuoteKind.prequote);
    expect(restored.selectionMode, 'proposal_type');
    expect(restored.additionalInformation, 'Срок поставки 14 дней');
    expect(restored.clientSelectedProposalTypeId, 'type-1');
    expect(
      restored.clientSelectionSubmittedAt,
      DateTime.utc(2026, 9, 9, 18, 30),
    );
    expect(source.toJson(), isNot(contains('clientSelectedProposalTypeId')));
    expect(restored.proposalTypes.single.name, 'Кондиционеры');
    expect(restored.proposalTypes.single.selectedByClient, isTrue);
    expect(
      restored.proposalTypes.single.toJson(),
      isNot(contains('selectedByClient')),
    );
    expect(restored.proposalTypes.single.variants.single.clientTotal, 275);
  });
}

QuoteVariantDraft _variant(String name, double price) => QuoteVariantDraft(
  id: 'variant-$name',
  name: name,
  categories: [
    QuoteCategoryDraft(
      id: 'category-$name',
      name: 'Оборудование',
      sections: [
        QuoteSectionDraft(
          id: 'section-$name',
          name: 'Вентиляция',
          positions: [_position(basePrice: price)],
        ),
      ],
    ),
  ],
);

QuotePositionDraft _position({
  required double basePrice,
  double quantity = 1,
  double? markupPercent,
  double? discountPercent,
  bool excludeFromTotals = false,
}) => QuotePositionDraft(
  id: newQuoteId(),
  name: 'Позиция',
  marking: 'М-1',
  unit: 'шт',
  quantity: quantity,
  basePrice: basePrice,
  markupPercent: markupPercent,
  discountPercent: discountPercent,
  excludeFromTotals: excludeFromTotals,
  values: const {},
);
