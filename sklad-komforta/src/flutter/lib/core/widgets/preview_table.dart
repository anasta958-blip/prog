import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Таблица предпросмотра растягивается по контейнеру за счёт наименования;
/// при недостатке ширины сохраняет читаемые колонки и прокручивается вбок.
class PreviewTable extends StatelessWidget {
  const PreviewTable({
    super.key,
    required this.child,
    required this.minimumWidth,
  });
  final Table child;
  final double minimumWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: math.max(constraints.maxWidth, minimumWidth),
        child: Table(
          border: child.border,
          defaultVerticalAlignment: child.defaultVerticalAlignment,
          columnWidths: {...?child.columnWidths, 1: const FlexColumnWidth(2.6)},
          defaultColumnWidth: child.defaultColumnWidth,
          children: child.children,
        ),
      ),
    ),
  );
}
