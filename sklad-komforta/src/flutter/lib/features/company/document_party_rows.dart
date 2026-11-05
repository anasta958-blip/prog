import 'dart:math' as math;
import 'package:flutter/material.dart';

List<({List<String> cells, List<double> widths})> documentPartyRows(
  List<String> lines,
  double width,
  TextStyle style,
  bool flow,
) {
  final rows = <({List<String> cells, List<double> widths})>[];
  var cells = <String>[];
  var widths = <double>[];
  var used = 0.0;
  for (final line in lines) {
    final painter = TextPainter(
      text: TextSpan(text: line, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final size = flow ? math.min(width, painter.width + 16) : width;
    painter.dispose();
    if (cells.isNotEmpty && used + size > width) {
      rows.add((cells: cells, widths: widths));
      cells = [];
      widths = [];
      used = 0;
    }
    cells.add(line);
    widths.add(size);
    used += size;
  }
  if (cells.isNotEmpty) rows.add((cells: cells, widths: widths));
  return rows;
}
