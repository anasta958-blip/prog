import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

void main() {
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

  test('сводка типа использует максимальную сумму среди его вариантов', () {
    final type = QuoteProposalTypeDraft(
      id: 'type-1',
      name: 'Кондиционеры',
      variants: [_variant('Бюджетный', 100), _variant('Премиальный', 350)],
    );

    expect(type.clientTotal, 350);
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

    final restored = QuoteDraft.fromJson({'id': source.id, ...source.toJson()});

    expect(restored.kind, QuoteKind.prequote);
    expect(restored.selectionMode, 'proposal_type');
    expect(restored.additionalInformation, 'Срок поставки 14 дней');
    expect(restored.proposalTypes.single.name, 'Кондиционеры');
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
