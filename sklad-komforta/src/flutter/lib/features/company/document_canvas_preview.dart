import 'package:intl/intl.dart';
import '../kanban/kanban_models.dart';
import '../quotes/quote_models.dart';
import 'document_preview_fields.dart';
import 'document_template.dart';

Map<String, dynamic> documentCanvasPreview({
  required KanbanBoard board,
  required List<QuoteCategoryDraft> categories,
  required List<String> totals,
  Map<String, dynamic>? client,
  Map<String, dynamic>? executor,
  bool order = false,
  Set<String> reorderIds = const {},
  bool partiesOnly = false,
  bool excludeParties = false,
}) {
  final template = DocumentTemplate.fromJson(board.documentTemplate!);
  final visibleBlocks = template.blocks.where((block) {
    final party = block.kind == 'client' || block.kind == 'executor';
    return partiesOnly ? party : !excludeParties || !party;
  }).toList();
  final tableBlock = template.blocks
      .where((b) => b.kind == 'table')
      .firstOrNull;
  final tables = <Map<String, dynamic>>[];
  final ordered = categories.indexed.toList()
    ..sort((a, b) {
      final rank = (tableBlock?.categoryRank(a.$2.catalogCategoryId) ?? 0)
          .compareTo(tableBlock?.categoryRank(b.$2.catalogCategoryId) ?? 0);
      return rank == 0 ? a.$1.compareTo(b.$1) : rank;
    });
  for (final (_, category) in ordered) {
    final fields =
        board.categories
            .where((c) => c.categoryId == category.catalogCategoryId)
            .firstOrNull
            ?.documentFields ??
        [];
    if (fields.isEmpty) continue;
    for (final section in category.sections) {
      tables.add({
        'title': '${category.name} / ${section.name}',
        'columns': fields.map((f) => f.label).toList(),
        'widths': fields
            .map(
              (f) =>
                  tableBlock
                      ?.columnWidths['${category.catalogCategoryId}/${f.code}'] ??
                  1,
            )
            .toList(),
        'rows': section.positions
            .map(
              (p) => fields
                  .map(
                    (f) => documentFieldText(
                      f,
                      p,
                      order: order,
                      reorder: reorderIds.contains(p.id),
                    ),
                  )
                  .toList(),
            )
            .toList(),
      });
    }
  }
  String? partyValue(Map<String, dynamic>? party, String code) {
    final key = code.replaceAllMapped(
      RegExp(r'_([a-z])'),
      (m) => m[1]!.toUpperCase(),
    );
    return party?[key]?.toString();
  }

  return {
    'template': {
      ...template.toJson(),
      'blocks': visibleBlocks.map((block) => block.toJson()).toList(),
    },
    'blocks': [
      for (final block in visibleBlocks)
        {
          'id': block.id,
          'title': block.kind == 'table' ? '' : documentBlockNames[block.kind],
          'lines': block.kind == 'totals'
              ? totals
              : block.kind == 'table'
              ? <String>[]
              : [
                  for (final code in block.fields)
                    '${documentPartyFields.firstWhere((f) => f.code == code).label}: ${partyValue(block.kind == 'client' ? client : executor, code) ?? '—'}',
                ],
          'tables': block.kind == 'table' ? tables : <Map<String, dynamic>>[],
        },
    ],
  };
}

List<String> documentVariantTotals(QuoteVariantDraft variant) {
  String money(double n) => '${NumberFormat('#,##0.00', 'ru_RU').format(n)} ₽';
  return [
    'НДС: ${money(variant.vatAmount)}',
    'Сумма без НДС: ${money(variant.clientTotal)}',
    'Итого для клиента: ${money(variant.totalWithVat)}',
  ];
}
