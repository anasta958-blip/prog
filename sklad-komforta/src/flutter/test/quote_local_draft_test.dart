import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/quotes/quote_local_draft.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final kind in QuoteKind.values) {
    test(
      'черновик ${kind.label} восстанавливается отдельно от другого документа',
      () async {
        final store = QuoteLocalDraft('user.board.card');
        final draft = QuoteDraft(
          id: 'quote',
          cardId: 'card',
          kind: kind,
          title: 'Не завершено',
          clientId: '',
          executorCompanyId: '',
          selectionMode: 'variant',
          proposalTypes: [QuoteProposalTypeDraft.create()],
        );
        await store.write(draft);
        final restored = await QuoteLocalDraft('user.board.card').read();
        expect(restored!.title, draft.title);
        expect(restored.kind, kind);
        expect(restored.cardId, 'card');
        expect(restored.toJson(), draft.toJson());
        expect(await QuoteLocalDraft('other-user.board.card').read(), isNull);
        draft.title = 'Последняя версия';
        final write = store.write(draft);
        final clear = store.clear();
        await write;
        await clear;
        expect(await store.read(), isNull);
      },
    );
  }

  test('локальный черновик сохраняет версию и сумму старого расчёта', () async {
    final position = QuotePositionDraft(
      id: 'position',
      name: 'Позиция',
      marking: '',
      unit: 'шт',
      quantity: 1,
      basePrice: 100,
      values: {},
    )..configuredLineTotal = 150;
    final draft = QuoteDraft(
      id: 'quote',
      cardId: 'card',
      kind: QuoteKind.quote,
      title: 'КП',
      clientId: 'client',
      executorCompanyId: 'executor',
      selectionMode: 'variant',
      calculationVersion: 'old',
      currentCalculationVersion: 'new',
      updatedAt: DateTime.utc(2026, 11, 9),
      proposalTypes: [
        QuoteProposalTypeDraft(
          id: 'type',
          name: 'Тип',
          variants: [
            QuoteVariantDraft(
              id: 'variant',
              name: 'Вариант',
              categories: [
                QuoteCategoryDraft(
                  id: 'category',
                  name: 'Категория',
                  sections: [
                    QuoteSectionDraft(
                      id: 'section',
                      name: 'Раздел',
                      positions: [position],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final store = QuoteLocalDraft('outdated.quote');
    await store.write(draft);
    final restored = (await store.read())!;
    expect(restored.needsRecalculation, isTrue);
    expect(restored.updatedAt, draft.updatedAt);
    expect(
      restored
          .proposalTypes
          .single
          .variants
          .single
          .categories
          .single
          .sections
          .single
          .positions
          .single
          .lineTotal,
      150,
    );
  });
}
