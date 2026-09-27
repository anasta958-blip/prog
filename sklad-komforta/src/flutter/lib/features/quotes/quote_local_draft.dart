import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Serializes writes so an older autosave cannot replace a newer one or a delete.
final class QuoteLocalDraft {
  QuoteLocalDraft(this.key, {FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();

  final String key;
  final FlutterSecureStorage storage;
  Future<void> _pending = Future<void>.value();

  Future<QuoteDraft?> read() async {
    await _pending;
    final value = await storage.read(key: key);
    return value == null
        ? null
        : QuoteDraft.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  Future<void> write(QuoteDraft draft) {
    final snapshot = jsonEncode({
      ...draft.toJson(),
      'id': draft.id,
      'cardId': draft.cardId,
      'clientSelectedProposalTypeId': draft.clientSelectedProposalTypeId,
      'clientSelectionSubmittedAt': draft.clientSelectionSubmittedAt
          ?.toIso8601String(),
    });
    return _enqueue(() => storage.write(key: key, value: snapshot));
  }

  Future<void> clear() => _enqueue(() => storage.delete(key: key));

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
