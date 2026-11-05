import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/orders/order_models.dart';
import 'package:sklad_komforta_app/features/orders/order_preview_page.dart';

void main() {
  testWidgets('order preview requires a configured document layout', (
    tester,
  ) async {
    final board = KanbanBoard(
      id: 'board',
      code: 'order',
      name: 'Комплектация',
      columns: const [],
      transitions: const [],
      categories: const [],
    );
    final order = OrderDocument(
      title: 'Объект',
      clientId: 'client',
      executorCompanyId: 'executor',
      categories: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OrderPreviewPage(order: order, board: board),
      ),
    );
    expect(find.textContaining('Внешний вид не настроен'), findsOneWidget);
    expect(find.text('КОМПЛЕКТАЦИЯ'), findsNothing);
  });
}
