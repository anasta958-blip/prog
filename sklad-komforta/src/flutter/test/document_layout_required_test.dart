import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/widgets/document_layout_required.dart';

void main() {
  testWidgets('missing layout offers a route to document settings', (
    tester,
  ) async {
    var openedSettings = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDocumentLayoutRequiredDialog(
                context,
                documentName: 'PDF комплектации',
                onOpenSettings: () async {
                  openedSettings = true;
                },
              ),
              child: const Text('Печать'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Печать'));
    await tester.pumpAndSettle();
    expect(find.text('Внешний вид не настроен'), findsOneWidget);
    expect(find.textContaining('PDF комплектации'), findsOneWidget);
    await tester.tap(find.text('Перейти в настройки'));
    await tester.pumpAndSettle();
    expect(openedSettings, isTrue);
    expect(find.text('Внешний вид не настроен'), findsNothing);
  });
}
