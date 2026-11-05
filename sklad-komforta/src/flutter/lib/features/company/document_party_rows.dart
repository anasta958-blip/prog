List<({List<String> cells, List<double> widths})> documentPartyRows(
  List<String> lines,
  int columns,
) {
  final rows = <({List<String> cells, List<double> widths})>[];
  for (var start = 0; start < lines.length; start += columns) {
    rows.add((
      cells: List.generate(
        columns,
        (i) => start + i < lines.length ? lines[start + i] : '',
      ),
      widths: List.filled(columns, 1.0),
    ));
  }
  return rows;
}
