import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/preview_table.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/orders/order_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

const _paper = Color(0xFFFFFFFF);
const _paperText = Color(0xFF172033);
const _paperMuted = Color(0xFF5E6B7E);
const _paperBorder = Color(0xFFD8DEE8);
const _paperHeader = Color(0xFFF0F4F9);
const _reorderShade = Color(0xFFFFF4DE);
const _systemFields = {'name', 'marking', 'quantity', 'unit'};

/// Предпросмотр комплектации в виде листа. Макет повторяет серверный PDF
/// (`OrderPdfDocumentRenderer`): при изменении одного обновляйте и другой.
final class OrderPreviewPage extends StatelessWidget {
  const OrderPreviewPage({
    required this.order,
    required this.board,
    this.clientName,
    this.executorName,
    this.managerName,
    this.salesHeadName,
    this.cardNumber,
    super.key,
  });

  final OrderDocument order;
  final KanbanBoard board;
  final String? clientName;
  final String? executorName;
  final String? managerName;
  final String? salesHeadName;
  final int? cardNumber;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (cardNumber != null) '№ $cardNumber',
      if (order.objectType?.trim().isNotEmpty ?? false)
        order.objectType!.trim(),
      if (order.sourceQuote != null) 'из КП № ${order.sourceQuote!.cardNumber}',
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0B1119),
      appBar: AppBar(title: const Text('Предпросмотр комплектации')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.all(34),
                child: DefaultTextStyle(
                  style: const TextStyle(color: _paperText, fontSize: 12.5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'КОМПЛЕКТАЦИЯ',
                        style: TextStyle(
                          color: _paperMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        order.title.trim().isEmpty
                            ? 'Без адреса'
                            : order.title.trim(),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle.join(' · '),
                          style: const TextStyle(color: _paperMuted),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 28,
                        runSpacing: 12,
                        children: [
                          _Meta('ЗАКАЗЧИК', clientName),
                          _Meta('ИСПОЛНИТЕЛЬ', executorName),
                          _Meta('МЕНЕДЖЕР', managerName),
                          _Meta('РОП', salesHeadName),
                        ],
                      ),
                      for (final category in order.categories)
                        for (final section in category.sections)
                          _SectionTable(
                            categoryName: category.name,
                            sectionName: section.name,
                            rows: section.positions,
                            reorderIds: order.reorderPositionIds,
                            fields: _extraFields(category.catalogCategoryId),
                          ),
                      if (order.categories.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 22),
                          child: Text(
                            'Позиции не добавлены.',
                            style: TextStyle(color: _paperMuted),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<KanbanField> _extraFields(String? catalogCategoryId) {
    final category = board.categories
        .where((item) => item.categoryId == catalogCategoryId)
        .firstOrNull;
    return [
      for (final field in category?.fields ?? const <KanbanField>[])
        if (!_systemFields.contains(field.code)) field,
    ]..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  }
}

final class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _paperMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          (value?.trim().isEmpty ?? true) ? 'Не указан' : value!.trim(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

final class _SectionTable extends StatelessWidget {
  const _SectionTable({
    required this.categoryName,
    required this.sectionName,
    required this.rows,
    required this.reorderIds,
    required this.fields,
  });

  final String categoryName;
  final String sectionName;
  final List<QuotePositionDraft> rows;
  final Set<String> reorderIds;
  final List<KanbanField> fields;

  @override
  Widget build(BuildContext context) {
    final title =
        sectionName.trim().toLowerCase() == categoryName.trim().toLowerCase()
        ? categoryName
        : '$categoryName · $sectionName';
    final headers = [
      '№',
      'Наименование',
      'Маркировка / размер',
      'Кол-во',
      'Ед.',
      for (final field in fields) field.label,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          PreviewTable(
            minimumWidth: 640 + fields.length * 100.0,
            child: Table(
              border: TableBorder.all(color: _paperBorder, width: 0.8),
              columnWidths: {
                0: const FixedColumnWidth(34),
                1: const FlexColumnWidth(2.6),
                2: const FlexColumnWidth(1.7),
                3: const FixedColumnWidth(62),
                4: const FixedColumnWidth(48),
                for (var index = 0; index < fields.length; index++)
                  5 + index: const FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: _paperHeader),
                  children: [for (final header in headers) _cell(header, true)],
                ),
                for (var index = 0; index < rows.length; index++)
                  _row(index, rows[index]),
                if (rows.isEmpty)
                  TableRow(
                    children: [
                      for (var index = 0; index < headers.length; index++)
                        _cell(index == 1 ? 'Позиции не добавлены' : '', false),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _row(int index, QuotePositionDraft position) {
    final reorder = reorderIds.contains(position.id);
    final quantity = position.quantity;
    return TableRow(
      decoration: reorder ? const BoxDecoration(color: _reorderShade) : null,
      children: [
        _cell('${index + 1}', false),
        _cell(reorder ? '${position.name} (дозаказ)' : position.name, false),
        _cell(position.marking, false),
        _cell(
          quantity == quantity.roundToDouble()
              ? quantity.toStringAsFixed(0)
              : quantity.toString(),
          false,
        ),
        _cell(position.unit, false),
        for (final field in fields)
          _cell(_format(position.values[field.code]), false),
      ],
    );
  }

  static String _format(dynamic value) => switch (value) {
    null => '',
    true => 'Да',
    false => 'Нет',
    final List<dynamic> list => list.join(', '),
    _ => '$value',
  };

  static Widget _cell(String text, bool header) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: header ? 11 : 11.5,
        fontWeight: header ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
  );
}
