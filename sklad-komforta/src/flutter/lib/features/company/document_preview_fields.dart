import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/core/widgets/preview_table.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

final class DocumentPreviewFields extends InheritedWidget {
  const DocumentPreviewFields({
    required this.board,
    required super.child,
    super.key,
  });
  final KanbanBoard? board;
  static List<KanbanField>? fields(BuildContext context, String? categoryId) =>
      context
          .dependOnInheritedWidgetOfExactType<DocumentPreviewFields>()
          ?.board
          ?.categories
          .where((category) => category.categoryId == categoryId)
          .firstOrNull
          ?.documentFields;
  @override
  bool updateShouldNotify(DocumentPreviewFields oldWidget) =>
      board != oldWidget.board;
}

final class ConfiguredDocumentTable extends StatelessWidget {
  const ConfiguredDocumentTable({
    required this.fields,
    required this.rows,
    this.reorderIds = const {},
    this.order = false,
    super.key,
  });
  final List<KanbanField> fields;
  final List<QuotePositionDraft> rows;
  final Set<String> reorderIds;
  final bool order;
  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return const SizedBox.shrink();
    TableRow line(
      List<String> cells, {
      bool header = false,
      bool reorder = false,
    }) => TableRow(
      decoration: BoxDecoration(
        color: header
            ? const Color(0xFFF0F4F9)
            : reorder
            ? const Color(0xFFFFF4DE)
            : Colors.white,
      ),
      children: cells
          .map(
            (text) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                text,
                style: TextStyle(
                  color: const Color(0xFF172033),
                  fontWeight: header ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
    );
    return PreviewTable(
      minimumWidth: (fields.length * 130.0).clamp(300, double.infinity),
      child: Table(
        border: TableBorder.all(color: const Color(0xFFD8DEE8)),
        children: [
          line(fields.map((field) => field.label).toList(), header: true),
          for (final row in rows)
            line(
              fields
                  .map(
                    (field) => documentFieldText(
                      field,
                      row,
                      order: order,
                      reorder: reorderIds.contains(row.id),
                    ),
                  )
                  .toList(),
              reorder: reorderIds.contains(row.id),
            ),
        ],
      ),
    );
  }
}

String documentFieldText(
  KanbanField field,
  QuotePositionDraft row, {
  bool order = false,
  bool reorder = false,
}) {
  final dynamic value = switch (field.code) {
    'name' => reorder ? '${row.name} (дозаказ)' : row.name,
    'marking' => row.marking,
    'quantity' => row.quantity,
    'unit' => row.unit,
    'base_price' when !order => row.manualPrice ?? row.basePrice,
    'purchase_price' when !order => row.purchasePrice,
    'markup_value' when !order => row.markupPercent,
    'discount_value' when !order => row.discountPercent,
    'line_total' when !order => row.lineTotal,
    'excluded_from_calc' when !order => row.excludeFromTotals,
    _ => row.values[field.code],
  };
  String format(dynamic item) {
    if (item == null || item == '') {
      return field.fieldType == 'dictionary' ? 'Не выбрано' : '';
    }
    if (item is bool) return item ? 'Да' : 'Нет';
    if (item is List) return item.map(format).join(', ');
    if (item is num) {
      if (const {'money', 'calculated_money'}.contains(field.fieldType)) {
        return '${NumberFormat('#,##0.00', 'ru_RU').format(item)} ₽';
      }
      return '${NumberFormat('0.##', 'ru_RU').format(item)}${field.fieldType == 'percent' ? '%' : ''}';
    }
    return field.options
            .where((option) => option.id == item.toString())
            .firstOrNull
            ?.value ??
        item.toString();
  }

  return format(value);
}
