import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/company/vat_rates_field.dart';

void main() {
  testWidgets(
    'VAT list adds individual rates, rejects duplicates and invalid numbers',
    (tester) async {
      var rates = <double?>[null, 20];
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: VatRatesField(
                initialValue: rates,
                onChanged: (value) => rates = value,
              ),
            ),
          ),
        ),
      );
      Future<void> add(String value) async {
        await tester.enterText(find.byType(TextField), value);
        await tester.tap(find.byTooltip('Добавить ставку НДС'));
        await tester.pump();
      }

      await add('5,5');
      expect(rates, [null, 20, 5.5]);
      await add('5.5');
      expect(find.text('Такая ставка уже добавлена.'), findsOneWidget);
      expect(rates.length, 3);
      for (final invalid in ['-1', '101', 'NaN', 'Infinity', '5,10,20']) {
        await add(invalid);
        expect(rates.length, 3);
      }
      await tester.enterText(find.byType(TextField), '7');
      expect(form.currentState!.validate(), isFalse);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byTooltip('Удалить ставку').first);
      await tester.pump();
      expect(rates, [20, 5.5]);
      await tester.tap(find.widgetWithText(TextButton, 'Без НДС'));
      await tester.pump();
      expect(rates, [20, 5.5, null]);
      expect(form.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
