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
    final payload = draft.toJson();
    final types = payload['proposalTypes'] as List;
    for (
      var typeIndex = 0;
      typeIndex < draft.proposalTypes.length;
      typeIndex++
    ) {
      final variants =
          (types[typeIndex] as Map<String, dynamic>)['variants'] as List;
      final sourceType = draft.proposalTypes[typeIndex];
      for (
        var variantIndex = 0;
        variantIndex < sourceType.variants.length;
        variantIndex++
      ) {
        final categories =
            (variants[variantIndex] as Map<String, dynamic>)['categories']
                as List;
        final sourceVariant = sourceType.variants[variantIndex];
        for (
          var categoryIndex = 0;
          categoryIndex < sourceVariant.categories.length;
          categoryIndex++
        ) {
          final sections =
              (categories[categoryIndex] as Map<String, dynamic>)['sections']
                  as List;
          final sourceCategory = sourceVariant.categories[categoryIndex];
          for (
            var sectionIndex = 0;
            sectionIndex < sourceCategory.sections.length;
            sectionIndex++
          ) {
            final positions =
                (sections[sectionIndex] as Map<String, dynamic>)['positions']
                    as List;
            final sourceSection = sourceCategory.sections[sectionIndex];
            for (
              var positionIndex = 0;
              positionIndex < sourceSection.positions.length;
              positionIndex++
            ) {
              (positions[positionIndex] as Map<String, dynamic>)['lineTotal'] =
                  sourceSection.positions[positionIndex].lineTotal;
            }
          }
        }
      }
    }
    final snapshot = jsonEncode({
      ...payload,
      'id': draft.id,
      'cardId': draft.cardId,
      'clientSelectedProposalTypeId': draft.clientSelectedProposalTypeId,
      'clientSelectionSubmittedAt': draft.clientSelectionSubmittedAt
          ?.toIso8601String(),
      'canChangeManager': draft.canChangeManager,
      'calculationVersion': draft.calculationVersion,
      'currentCalculationVersion': draft.currentCalculationVersion,
      'updatedAt': draft.updatedAt?.toIso8601String(),
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
