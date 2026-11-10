import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_configured_calculation.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Calculation-only timings; excludes rendering and persistence.
List<String> runCalculationBenchmark() {
  final output = <String>[];
  for (final kind in QuoteKind.values) {
    for (final complex in [false, true]) {
      final configuration = CatalogConfiguration(
        categories: const [
          CatalogCategory(
            id: 'category',
            clientId: 'equipment',
            name: 'Equipment',
            sortOrder: 0,
            fields: [],
            sections: [],
          ),
        ],
        dictionaries: const [],
        moneyPipelines: complex
            ? [
                MoneyPipelineDraft(
                  categoryClientId: 'equipment',
                  basePriceFieldCode: 'base_price',
                  quantityFieldCode: 'quantity',
                  resultFieldCode: 'line_total',
                ),
              ]
            : const [],
        rules: complex
            ? [
                CalculationRuleDraft(
                  clientId: 'variant',
                  name: 'Variant total',
                  categoryClientId: 'equipment',
                  eventType: 'variant_calculation',
                  isEnabled: true,
                  conditions: const [],
                  actions: [
                    RuleActionDraft(
                      actionType: 'set_field',
                      targetFieldCode: 'note',
                      sourceFieldCode: 'variant_total',
                    ),
                  ],
                ),
              ]
            : const [],
      );
      final engine = QuoteConfiguredCalculationEngine(configuration);
      for (final count in [100, 500, 1000]) {
        final document = QuoteDraft(
          kind: kind,
          title: 'Benchmark',
          clientId: 'client',
          executorCompanyId: 'executor',
          selectionMode: 'variant',
          proposalTypes: [
            QuoteProposalTypeDraft(
              id: 'type',
              name: 'Type',
              variants: [
                QuoteVariantDraft(
                  id: 'variant',
                  name: 'Variant',
                  categories: [
                    QuoteCategoryDraft(
                      id: 'category',
                      catalogCategoryId: 'category',
                      name: 'Equipment',
                      sections: [
                        QuoteSectionDraft(
                          id: 'section',
                          name: 'Section',
                          positions: [
                            for (var i = 0; i < count; i++)
                              QuotePositionDraft(
                                id: 'position-$i',
                                name: 'Position $i',
                                marking: '',
                                unit: 'pcs',
                                quantity: 1,
                                basePrice: 10,
                                values: {},
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        engine.calculateDocument(document);
        final fullDocument = QuoteDraft.fromJson(document.toJson());
        engine.calculateDocument(fullDocument);
        final row = document
            .proposalTypes
            .single
            .variants
            .single
            .categories
            .single
            .sections
            .single
            .positions[count ~/ 2];
        final category =
            document.proposalTypes.single.variants.single.categories.single;
        final fullRow = fullDocument
            .proposalTypes
            .single
            .variants
            .single
            .categories
            .single
            .sections
            .single
            .positions[count ~/ 2];
        final partial = <int>[];
        final full = <int>[];
        for (var i = 0; i < 15; i++) {
          row.quantity = i.isEven ? 2 : 3;
          fullRow.quantity = row.quantity;
          var watch = Stopwatch()..start();
          engine.calculateDocument(
            document,
            changedPosition: row,
            changedVariant: document.proposalTypes.single.variants.single,
            changedCategory: category,
            changedFieldCode: 'quantity',
          );
          watch.stop();
          if (i >= 5) partial.add(watch.elapsedMicroseconds);
          watch = Stopwatch()..start();
          engine.calculateDocument(fullDocument);
          watch.stop();
          if (i >= 5) full.add(watch.elapsedMicroseconds);
        }
        partial.sort();
        full.sort();
        output.add(
          'CALC kind=${kind.apiValue} complex=$complex rows=$count '
          'partial_p50_us=${partial[partial.length ~/ 2]} '
          'full_p50_us=${full[full.length ~/ 2]}',
        );
      }
    }
  }
  return output;
}
