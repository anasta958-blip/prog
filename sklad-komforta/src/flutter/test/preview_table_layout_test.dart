import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/widgets/preview_table.dart';

void main() {
  for (final width in [375.0, 1024.0, 1440.0]) {
    testWidgets('Таблица предпросмотра занимает доступную ширину $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PreviewTable(
              minimumWidth: 640,
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(40),
                  2: FixedColumnWidth(100),
                },
                children: const [
                  TableRow(
                    children: [Text('№'), Text('Наименование'), Text('Сумма')],
                  ),
                  TableRow(
                    children: [
                      Text('1'),
                      Text('Оборудование'),
                      Text('1 000 ₽'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(Table)).width,
        width < 640 ? 640 : width,
      );
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.scrollDirection, Axis.horizontal);
    });
  }
}
