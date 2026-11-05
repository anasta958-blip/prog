import 'package:flutter/material.dart';
import '../company/document_canvas_preview.dart';
import '../company/document_canvas_view.dart';
import 'package:sklad_komforta_app/features/company/document_preview_fields.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/core/widgets/preview_table.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

const _previewBackground = Color(0xFF0B1119);
const _paperText = Color(0xFF172033);
const _paperMuted = Color(0xFF5E6B7E);
const _paperBorder = Color(0xFFD8DEE8);
const _paperHeader = Color(0xFFF0F4F9);

/// Нередактируемое представление текущего состояния КП/ПКП.
///
/// Экран получает черновик напрямую из редактора, поэтому показывает ещё не
/// сохранённые изменения. Закупочные цены намеренно не входят в клиентскую
/// таблицу и остаются доступными только в рабочем редакторе.
///
/// Как и печать, предпросмотр показывает то, что выбрал пользователь: один
/// вариант ([proposalTypeId] и [variantId]), все варианты одного типа (только
/// [proposalTypeId]) либо весь документ (оба не указаны или не найдены).
final class QuotePreviewPage extends StatelessWidget {
  const QuotePreviewPage({
    required this.draft,
    this.board,
    this.client,
    this.executor,
    this.managerName,
    this.salesHeadName,
    this.cardNumber,
    this.proposalTypeId,
    this.variantId,
    super.key,
  });

  final QuoteDraft draft;
  final KanbanBoard? board;
  final String? proposalTypeId;
  final String? variantId;
  final CompanyClientModel? client;
  final LegalEntityModel? executor;
  final String? managerName;
  final String? salesHeadName;
  final int? cardNumber;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('quote-preview-page'),
    backgroundColor: _previewBackground,
    appBar: AppBar(
      backgroundColor: const Color(0xFF0F1722),
      foregroundColor: Colors.white,
      title: Text(
        cardNumber == null
            ? 'Предпросмотр ${draft.kind.label}'
            : 'Предпросмотр ${draft.kind.label} №$cardNumber',
      ),
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        if (board?.documentTemplate != null) {
          final visible = _visible();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(draft.title),
              for (final type in visible.types)
                for (final variant
                    in visible.onlyVariant == null
                        ? type.variants
                        : [visible.onlyVariant!]) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${type.name} / ${variant.name}'),
                  ),
                  DocumentCanvasView(
                    document: documentCanvasPreview(
                      board: board!,
                      categories: variant.categories,
                      totals: documentVariantTotals(variant),
                      client: client?.toJson(),
                      executor: executor?.toJson(),
                    ),
                  ),
                ],
            ],
          );
        }
        final compact = constraints.maxWidth < 720;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 28,
            24,
            compact ? 12 : 28,
            48,
          ),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1040),
              padding: EdgeInsets.all(compact ? 20 : 48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(compact ? 8 : 12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: DefaultTextStyle(
                style: const TextStyle(color: _paperText, height: 1.35),
                child: DocumentPreviewFields(
                  board: board,
                  child: _Document(
                    draft: draft,
                    visible: _visible(),
                    client: client,
                    executor: executor,
                    managerName: managerName,
                    salesHeadName: salesHeadName,
                    cardNumber: cardNumber,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  /// Показываемые типы и, если выбран вариант, единственный вариант типа.
  _Visible _visible() {
    if (variantId != null) {
      for (final type in draft.proposalTypes) {
        if (proposalTypeId != null && type.id != proposalTypeId) continue;
        for (final variant in type.variants) {
          if (variant.id == variantId) {
            return _Visible([type], variant);
          }
        }
      }
    } else if (proposalTypeId != null) {
      for (final type in draft.proposalTypes) {
        if (type.id == proposalTypeId) return _Visible([type], null);
      }
    }
    return _Visible(draft.proposalTypes, null);
  }
}

/// Что выводит предпросмотр: типы и (для режима «вариант») единственный вариант.
final class _Visible {
  const _Visible(this.types, this.onlyVariant);

  final List<QuoteProposalTypeDraft> types;
  final QuoteVariantDraft? onlyVariant;
}

final class _Document extends StatelessWidget {
  const _Document({
    required this.draft,
    required this.visible,
    required this.client,
    required this.executor,
    required this.managerName,
    required this.salesHeadName,
    required this.cardNumber,
    required this.compact,
  });

  final QuoteDraft draft;
  final _Visible visible;
  final CompanyClientModel? client;
  final LegalEntityModel? executor;
  final String? managerName;
  final String? salesHeadName;
  final int? cardNumber;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        draft.kind == QuoteKind.quote
            ? 'КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ'
            : 'ПРЕДВАРИТЕЛЬНОЕ КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ',
        style: const TextStyle(
          color: _paperMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        draft.title.trim().isEmpty ? 'Без названия' : draft.title.trim(),
        key: const Key('quote-preview-title'),
        style: TextStyle(
          color: _paperText,
          fontSize: compact ? 24 : 32,
          fontWeight: FontWeight.w800,
        ),
      ),
      if (cardNumber != null) ...[
        const SizedBox(height: 5),
        Text('№ $cardNumber', style: const TextStyle(color: _paperMuted)),
      ],
      const SizedBox(height: 26),
      _MetadataGrid(
        compact: compact,
        clientName: client?.name,
        executorName: executor?.legalName ?? executor?.name,
        managerName: managerName,
        salesHeadName: salesHeadName,
      ),
      if (_text(client?.salutation) case final salutation?) ...[
        const SizedBox(height: 28),
        Text(salutation),
      ],
      if (_text(client?.introText) case final intro?) ...[
        const SizedBox(height: 12),
        Text(intro),
      ],
      const SizedBox(height: 30),
      ...visible.types.map(
        (type) => Padding(
          padding: const EdgeInsets.only(bottom: 30),
          child: _ProposalType(
            type: type,
            selectionMode: draft.selectionMode,
            onlyVariant: visible.onlyVariant,
          ),
        ),
      ),
      if (_text(draft.additionalInformation) case final information?) ...[
        const Divider(height: 42, color: _paperBorder),
        const Text(
          'Дополнительная информация',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(information),
      ],
      if (_text(executor?.footerDefault) case final footer?) ...[
        const SizedBox(height: 30),
        Text(footer, style: const TextStyle(color: _paperMuted)),
      ],
    ],
  );
}

final class _MetadataGrid extends StatelessWidget {
  const _MetadataGrid({
    required this.compact,
    required this.clientName,
    required this.executorName,
    required this.managerName,
    required this.salesHeadName,
  });

  final bool compact;
  final String? clientName;
  final String? executorName;
  final String? managerName;
  final String? salesHeadName;

  @override
  Widget build(BuildContext context) {
    final entries = [
      ('Заказчик', clientName),
      ('Исполнитель', executorName),
      ('Менеджер', managerName),
      ('РОП', salesHeadName),
    ];
    return Wrap(
      spacing: 18,
      runSpacing: 14,
      children: entries
          .map(
            (entry) => SizedBox(
              width: compact ? double.infinity : 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.$1.toUpperCase(),
                    style: const TextStyle(
                      color: _paperMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _text(entry.$2) ?? 'Не указан',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

final class _ProposalType extends StatelessWidget {
  const _ProposalType({
    required this.type,
    required this.selectionMode,
    this.onlyVariant,
  });

  final QuoteProposalTypeDraft type;
  final String selectionMode;

  /// Единственный показываемый вариант. Сводка типа при этом не выводится:
  /// она совпала бы с итогом варианта.
  final QuoteVariantDraft? onlyVariant;

  @override
  Widget build(BuildContext context) => Column(
    key: Key('quote-preview-type-${type.id}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        color: _paperText,
        child: Row(
          children: [
            Expanded(
              child: Text(
                type.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              selectionMode == 'proposal_type'
                  ? 'Выбирается тип целиком'
                  : 'Выбирается один вариант',
              style: const TextStyle(color: Color(0xFFCED7E5), fontSize: 11),
            ),
          ],
        ),
      ),
      ...(onlyVariant == null ? type.variants : [onlyVariant!]).map(
        (variant) => _Variant(
          variant: variant,
          selected: type.selectedVariantId == variant.id,
        ),
      ),
      if (onlyVariant == null)
        _Summary(
          title: 'Сводка типа',
          aggregate: true,
          clientTotal: type.clientTotal,
          vatAmount: type.vatAmount,
        ),
    ],
  );
}

final class _Variant extends StatelessWidget {
  const _Variant({required this.variant, required this.selected});

  final QuoteVariantDraft variant;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('quote-preview-variant-${variant.id}'),
    decoration: const BoxDecoration(
      border: Border(
        left: BorderSide(color: _paperBorder),
        right: BorderSide(color: _paperBorder),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          color: selected ? const Color(0xFFE8F1FF) : const Color(0xFFF8FAFC),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_text(variant.subtitle) case final subtitle?)
                      Text(
                        subtitle,
                        style: const TextStyle(color: _paperMuted),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Text(
                  'ВЫБРАН',
                  style: TextStyle(
                    color: Color(0xFF2368C4),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
            ],
          ),
        ),
        ...variant.categories.expand(
          (category) => category.sections.map(
            (section) => _PositionTable(
              categoryName: category.name,
              categoryId: category.catalogCategoryId,
              section: section,
            ),
          ),
        ),
        _Summary(
          title: 'Итого по варианту',
          clientTotal: variant.clientTotal,
          vatAmount: variant.vatAmount,
          vatRate: variant.vatRate,
        ),
      ],
    ),
  );
}

/// Сумма фиксированных ширин колонок таблицы позиций.
const double _positionTableWidth = 38 + 205 + 145 + 70 + 65 + 100 + 75 + 105;

final class _PositionTable extends StatelessWidget {
  const _PositionTable({
    required this.categoryName,
    required this.section,
    this.categoryId,
  });
  final String? categoryId;

  final String categoryName;
  final QuoteSectionDraft section;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(15, 14, 15, 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ширина строки ограничена шириной таблицы, чтобы сумма раздела стояла
        // над колонкой «Сумма», а на узком экране не уходила за край.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _positionTableWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  section.name.trim().toLowerCase() ==
                          categoryName.trim().toLowerCase()
                      ? categoryName
                      : '$categoryName · ${section.name}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _money(section.clientTotal),
                key: Key('quote-preview-section-total-${section.id}'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (DocumentPreviewFields.fields(context, categoryId)
            case final fields?)
          ConfiguredDocumentTable(fields: fields, rows: section.positions)
        else
          PreviewTable(
            minimumWidth: _positionTableWidth,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder.all(color: _paperBorder),
              columnWidths: const {
                0: FixedColumnWidth(38),
                1: FixedColumnWidth(205),
                2: FixedColumnWidth(145),
                3: FixedColumnWidth(70),
                4: FixedColumnWidth(65),
                5: FixedColumnWidth(100),
                6: FixedColumnWidth(75),
                7: FixedColumnWidth(105),
              },
              children: [
                _row(const [
                  '№',
                  'Наименование',
                  'Маркировка / размер',
                  'Кол-во',
                  'Ед.',
                  'Цена',
                  'Скидка',
                  'Сумма',
                ], header: true),
                ...section.positions.indexed.map(
                  (entry) => _row([
                    '${entry.$1 + 1}',
                    entry.$2.name,
                    entry.$2.marking,
                    _quantity(entry.$2.quantity),
                    entry.$2.unit,
                    _money(entry.$2.unitPrice),
                    _percent(entry.$2.discountPercent),
                    entry.$2.excludeFromTotals
                        ? 'Не учитывается'
                        : _money(entry.$2.lineTotal),
                  ]),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

TableRow _row(List<String> values, {bool header = false}) => TableRow(
  decoration: BoxDecoration(color: header ? _paperHeader : Colors.white),
  children: values
      .map(
        (value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          child: Text(
            value,
            style: TextStyle(
              color: _paperText,
              fontSize: 11,
              fontWeight: header ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
        ),
      )
      .toList(),
);

final class _Summary extends StatelessWidget {
  const _Summary({
    required this.title,
    required this.clientTotal,
    required this.vatAmount,
    this.vatRate,
    this.aggregate = false,
  });

  final String title;
  final double clientTotal;
  final double vatAmount;
  final double? vatRate;
  final bool aggregate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: const BoxDecoration(
      color: _paperHeader,
      border: Border(bottom: BorderSide(color: _paperBorder)),
    ),
    child: Wrap(
      alignment: WrapAlignment.end,
      spacing: 26,
      runSpacing: 6,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('Сумма без НДС: ${_money(clientTotal)}'),
        Text(
          vatRate == null
              ? (aggregate ? 'НДС: ${_money(vatAmount)}' : 'Без НДС')
              : 'НДС ${_percent(vatRate)}: ${_money(vatAmount)}',
        ),
        Text('Итого: ${_money(clientTotal + vatAmount)}'),
      ],
    ),
  );
}

final _moneyFormat = NumberFormat('#,##0.00', 'ru_RU');

String _money(double value) => '${_moneyFormat.format(value)} ₽';

String _quantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

String _percent(double? value) => value == null ? '0%' : '${_quantity(value)}%';

String? _text(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
