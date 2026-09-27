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
}
