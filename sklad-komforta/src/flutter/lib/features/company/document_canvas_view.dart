import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'document_template.dart';

/// Read-only rendering of server-projected, explicitly selected document data.
class DocumentCanvasView extends StatelessWidget {
  const DocumentCanvasView({required this.document, super.key});
  final Map<String, dynamic> document;

  @override
  Widget build(BuildContext context) {
    final template = DocumentTemplate.fromJson(
      document['template'] as Map<String, dynamic>,
    );
    final data = (document['blocks'] as List).cast<Map<String, dynamic>>();
    final blocks = [...template.blocks]
      ..sort((a, b) {
        final y = a.y.compareTo(b.y);
        return y == 0 ? a.x.compareTo(b.x) : y;
      });
    final children = <Widget>[];
    final completed = <({DocumentBlock block, double bottom})>[];
    var height = template.height;
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
      var y = block.y;
      for (final previous in completed) {
        final prior = previous.block;
        if (prior.y + prior.height <= block.y + .01 &&
            prior.x < block.x + block.width &&
            prior.x + prior.width > block.x) {
          y = math.max(y, previous.bottom + block.y - prior.y - prior.height);
        }
      }
      final width = block.width - block.padding * 2;
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
      }) {
        if (cells.isEmpty) return;
        final textStyle = heading
            ? style.copyWith(fontWeight: FontWeight.bold)
            : style;
        final total = weights.fold<double>(0, (sum, w) => sum + w);
        final widths = weights.map((w) => width * w / total).toList();
        final h =
            List.generate(
              cells.length,
              (i) => measure(cells[i], widths[i] - 8, textStyle),
            ).fold<double>(0, math.max) +
            8;
        contentHeight += h;
        rows.add(
          SizedBox(
            height: h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cells.length; i++)
                  Container(
                    width: widths[i],
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: heading && border ? const Color(0xFFF0F4F9) : null,
                      border: border
                          ? Border.all(
                              color: const Color(0xFFD8DEE8),
                              width: .5,
                            )
                          : null,
                    ),
                    child: Text(
                      cells[i],
                      textAlign: align,
                      style: textStyle,
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      final title = content['title'] as String;
      if (title.isNotEmpty) addRow([title], [1], heading: true);
      for (final line in (content['lines'] as List).cast<String>()) {
        addRow([line], [1]);
      }
      for (final raw in content['tables'] as List) {
        final table = raw as Map<String, dynamic>;
        addRow([table['title'] as String], [1], heading: true);
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
      final blockHeight = math.max(
        block.height,
        contentHeight + block.padding * 2,
      );
      completed.add((block: block, bottom: y + blockHeight));
      height = math.max(height, y + blockHeight + template.margin);
      children.add(
        Positioned(
          left: block.x,
          top: y,
          width: block.width,
          child: Padding(
            padding: EdgeInsets.all(block.padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: template.width,
        height: height,
        child: ColoredBox(
          color: Colors.white,
          child: Stack(children: children),
        ),
      ),
    );
  }
}
