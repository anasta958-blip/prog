import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/company/document_preview_fields.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_client_access_api.dart';

void main() {
  test(
    'public document decodes ordered cells and independent section total',
    () {
      final section = QuoteClientSection.fromJson({
        'name': 'Раздел',
        'total': 120,
        'columns': [
          {'code': 'custom_note', 'label': 'Примечание'},
        ],
        'positions': [
          {
            'name': '',
            'quantity': 0,
            'unitPrice': 0,
            'lineTotal': 0,
            'cells': ['Текст'],
          },
        ],
      });
      expect(section.columns, ['Примечание']);
      expect(section.positions.single.cells, ['Текст']);
      expect(section.total, 120);
    },
  );

  testWidgets(
    'configured preview hides unselected fields and keeps column order',
    (tester) async {
      const fields = [
        KanbanField(
          code: 'quantity',
          label: 'Количество',
          fieldType: 'number',
          isRequired: false,
          sortOrder: 0,
          options: [],
        ),
        KanbanField(
          code: 'custom_note',
          label: 'Примечание',
          fieldType: 'text',
          isRequired: false,
          sortOrder: 1,
          options: [],
        ),
      ];
      final row = QuotePositionDraft(
        id: 'row',
        name: 'Скрытый товар',
        marking: 'Скрытая маркировка',
        unit: 'шт',
        quantity: 3,
        basePrice: 100,
        values: {'custom_note': 'Открытый текст'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConfiguredDocumentTable(fields: fields, rows: [row]),
          ),
        ),
      );
      expect(find.text('Скрытый товар'), findsNothing);
      expect(find.text('Скрытая маркировка'), findsNothing);
      expect(find.text('Открытый текст'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Количество')).dx,
        lessThan(tester.getTopLeft(find.text('Примечание')).dx),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConfiguredDocumentTable(fields: const [], rows: [row]),
          ),
        ),
      );
      expect(find.byType(Table), findsNothing);
    },
  );
}
