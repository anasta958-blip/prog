import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'document_template.dart';
import 'document_paper_surface.dart';
import 'document_party_rows.dart';

/// Read-only rendering of server-projected, explicitly selected document data.
class DocumentCanvasView extends StatefulWidget {
  const DocumentCanvasView({
    required this.document,
    this.compact = false,
    this.clientLink = false,
    super.key,
  });
  final Map<String, dynamic> document;
  final bool compact;
  final bool clientLink;

  @override
  State<DocumentCanvasView> createState() => _DocumentCanvasViewState();
}

class _DocumentCanvasViewState extends State<DocumentCanvasView> {
  final Set<String> _collapsedCategories = {};

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final compact = widget.compact;
    final clientLink = widget.clientLink;
    final template = DocumentTemplate.fromJson(
      document['template'] as Map<String, dynamic>,
    );
    final data = (document['blocks'] as List).cast<Map<String, dynamic>>();
    final blocks = [...template.blocks]
      ..sort((a, b) {
        final y = a.y.compareTo(b.y);
        return y == 0 ? a.x.compareTo(b.x) : y;
      });
    final partyBlocks =
        blocks
            .where(
              (block) => block.kind == 'client' || block.kind == 'executor',
            )
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));
    final pairedParties = clientLink && partyBlocks.length == 2;
    const partyGap = 16.0;
    final partyWidth = (template.width - template.margin * 2 - partyGap) / 2;
    final children = <Widget>[];
    final completed = <({DocumentBlock block, double bottom})>[];
    var height = compact ? 0.0 : template.height;
    final topOffset = compact && !clientLink && blocks.isNotEmpty
        ? blocks.map((block) => block.y).reduce(math.min) - template.margin
        : 0.0;
    double? currentRow;
    var rowTop = 12.0;
    var rowBottom = 12.0;
    for (final block in blocks) {
      final content = data.where((item) => item['id'] == block.id).firstOrNull;
      if (content == null) continue;
      final style = TextStyle(
        color: const Color(0xFF172033),
        fontSize: block.fontSize,
        height: template.lineHeight,
        fontFamily: template.fontFamily == 'serif' ? 'Georgia' : 'Roboto',
      );
      final align = switch (block.align) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.left,
      };
      var y = block.y - topOffset;
      final party = block.kind == 'client' || block.kind == 'executor';
      final linkTable = clientLink && block.kind == 'table';
      final rowKey = pairedParties && party ? double.negativeInfinity : block.y;
      if (clientLink) {
        if (currentRow != rowKey) {
          if (currentRow != null) rowTop = rowBottom + 12;
          currentRow = rowKey;
        }
        y = rowTop;
      } else {
        for (final previous in completed) {
          final prior = previous.block;
          if (prior.y + prior.height <= block.y + .01 &&
              prior.x < block.x + block.width &&
              prior.x + prior.width > block.x) {
            y = math.max(y, previous.bottom + block.y - prior.y - prior.height);
          }
        }
      }
      final displayWidth = linkTable
          ? template.width
          : pairedParties && party
          ? partyWidth
          : block.width;
      final displayX = linkTable
          ? 0.0
          : pairedParties && party
          ? template.margin +
                partyBlocks.indexOf(block) * (partyWidth + partyGap)
          : block.x;
      final displayPadding = linkTable ? 0.0 : block.padding;
      final width = displayWidth - displayPadding * 2;
      final rows = <Widget>[];
      var contentHeight = 0.0;
      double measure(String text, double width, TextStyle textStyle) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: math.max(1, width));
        final result = math.max(
          textStyle.fontSize! * template.lineHeight,
          painter.height,
        );
        painter.dispose();
        return result;
      }

      void addRow(
        List<String> cells,
        List<double> weights, {
        bool heading = false,
        bool border = false,
        bool category = false,
        bool section = false,
        String? categoryKey,
      }) {
        if (cells.isEmpty) return;
        final textStyle = category
            ? style.copyWith(color: Colors.white, fontWeight: FontWeight.bold)
            : heading || section
            ? style.copyWith(fontWeight: FontWeight.bold)
            : style;
        final total = weights.fold<double>(0, (sum, w) => sum + w);
        final widths = weights.map((w) => width * w / total).toList();
        final h =
            List.generate(
              cells.length,
              (i) => measure(
                cells[i],
                widths[i] - 8 - (categoryKey != null && i == 0 ? 18 : 0),
                textStyle,
              ),
            ).fold<double>(0, math.max) +
            8;
        contentHeight += h;
        final row = SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cells.length; i++)
                Container(
                  width: widths[i],
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: category
                        ? const Color(0xFF243A56)
                        : section
                        ? const Color(0xFFDFE8F3)
                        : heading && border
                        ? const Color(0xFFF0F4F9)
                        : null,
                    border: border
                        ? Border.all(color: const Color(0xFFD8DEE8), width: .5)
                        : null,
                  ),
                  child: categoryKey != null && i == 0
                      ? Row(
                          children: [
                            Icon(
                              _collapsedCategories.contains(categoryKey)
                                  ? Icons.chevron_right
                                  : Icons.expand_more,
                              color: Colors.white,
                              size: 18,
                            ),
                            Expanded(
                              child: Text(
                                cells[i],
                                style: textStyle,
                                textScaler: TextScaler.noScaling,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          cells[i],
                          textAlign: cells.length > 1 && i == cells.length - 1
                              ? TextAlign.right
                              : category || section
                              ? TextAlign.left
                              : align,
                          style: textStyle,
                          textScaler: TextScaler.noScaling,
                        ),
                ),
            ],
          ),
        );
        rows.add(
          categoryKey == null
              ? row
              : InkWell(
                  onTap: () => setState(() {
                    if (!_collapsedCategories.remove(categoryKey)) {
                      _collapsedCategories.add(categoryKey);
                    }
                  }),
                  child: row,
                ),
        );
      }

      final title = content['title'] as String;
      if (title.isNotEmpty) addRow([title], [1], heading: true);
      for (final row in documentPartyRows(
        (content['lines'] as List).cast<String>(),
        (block.kind == 'client' || block.kind == 'executor')
            ? block.effectiveFieldColumns
            : 1,
      )) {
        addRow(row.cells, row.widths);
      }
      String? lastCategory;
      for (final raw in content['tables'] as List) {
        final table = raw as Map<String, dynamic>;
        final tableTitle = table['title'] as String;
        if (block.kind == 'table' &&
            (clientLink ||
                table['categoryTotal'] != null ||
                table['sectionTotal'] != null)) {
          final separator = tableTitle.indexOf(' / ');
          final categoryName = separator < 0
              ? tableTitle
              : tableTitle.substring(0, separator);
          final sectionName = separator < 0
              ? ''
              : tableTitle.substring(separator + 3);
          final categoryKey = '${table['categoryId'] ?? categoryName}';
          if (lastCategory != categoryKey) {
            if (lastCategory != null) {
              rows.add(const SizedBox(height: 8));
              contentHeight += 8;
            }
            final categoryTotal = (table['categoryTotal'] as num?)?.toDouble();
            addRow(
              [categoryName, if (categoryTotal != null) _money(categoryTotal)],
              categoryTotal == null ? [1] : [3, 1],
              category: true,
              categoryKey: clientLink ? categoryKey : null,
            );
            lastCategory = categoryKey;
          }
          if (clientLink && _collapsedCategories.contains(categoryKey)) {
            continue;
          }
          rows.add(const SizedBox(height: 5));
          contentHeight += 5;
          final sectionTotal = (table['sectionTotal'] as num?)?.toDouble();
          addRow(
            [
              sectionName.isEmpty || sectionName == categoryName
                  ? 'Позиции'
                  : sectionName,
              if (sectionTotal != null) _money(sectionTotal),
            ],
            sectionTotal == null ? [1] : [3, 1],
            section: true,
          );
        } else {
          addRow([tableTitle], [1], heading: true);
        }
        final widths = (table['widths'] as List)
            .map((v) => (v as num).toDouble())
            .toList();
        addRow(
          (table['columns'] as List).cast<String>(),
          widths,
          heading: true,
          border: true,
        );
        for (final row in table['rows'] as List) {
          addRow((row as List).cast<String>(), widths, border: true);
        }
        rows.add(const SizedBox(height: 12));
        contentHeight += 12;
      }
      final blockHeight = clientLink
          ? contentHeight + displayPadding * 2
          : math.max(block.height, contentHeight + block.padding * 2);
      completed.add((block: block, bottom: y + blockHeight));
      if (clientLink) rowBottom = math.max(rowBottom, y + blockHeight);
      height = math.max(
        height,
        y + blockHeight + (clientLink ? 12 : template.margin),
      );
      children.add(
        Positioned(
          left: displayX,
          top: y,
          width: displayWidth,
          child: Padding(
            padding: EdgeInsets.all(displayPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      );
    }
    return DocumentPaperSurface(
      width: template.width,
      height: math.max(height, template.margin * 2),
      zoom: clientLink ? 1.2 : 1,
      fillWidth: clientLink,
      child: ColoredBox(
        key: const ValueKey('document-preview-paper'),
        color: Colors.white,
        child: Stack(children: children),
      ),
    );
  }
}

final _moneyFormat = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 2,
);

String _money(double value) => _moneyFormat.format(value);
