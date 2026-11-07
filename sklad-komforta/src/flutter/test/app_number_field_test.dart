import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/widgets/app_number_field.dart';

void main() {
  for (final grouped in [false, true]) {
    testWidgets(
      'clearing numeric input commits selected zero (grouped=$grouped)',
      (tester) async {
        var value = '12500';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => AppNumberField(
                  value: value,
                  groupThousands: grouped,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        );
        final field = find.byType(TextFormField);
        await tester.enterText(field, '');
        await tester.pump();
        final input = tester.widget<TextFormField>(field).controller!;
        expect(value, '0');
        expect(input.text, '0');
        expect(
          input.selection,
          const TextSelection(baseOffset: 0, extentOffset: 1),
        );
        await tester.enterText(field, '2,5');
        await tester.pump();
        expect(value, '2,5');
        expect(input.text, '2,5');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('денежное поле отображает разделители без изменения значения', (
    tester,
  ) async {
    var value = '125000';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppNumberField(
            value: value,
            groupThousands: true,
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );
    final input = tester
        .widget<TextFormField>(find.byType(TextFormField))
        .controller!;
    expect(input.text, '125 000');
    await tester.enterText(find.byType(TextFormField), '125000,50');
    expect(input.text, '125 000,50');
    expect(value, '125000,50');
    await tester.tap(find.byTooltip('Увеличить на 1'));
    expect(value, '125001.5');
    expect(input.text, '125 001,5');
    expect(tester.takeException(), isNull);
  });
  testWidgets('money rejects negative input and steps stop at zero', (
    tester,
  ) async {
    var value = '0';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppNumberField(
            value: value,
            minimum: 0,
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '-25');
    expect(value, '0');
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '0',
    );
    await tester.tap(find.byTooltip('Уменьшить на 1'));
    expect(value, '0');
    await tester.tap(find.byTooltip('Увеличить на 1'));
    expect(value, '1');
    await tester.enterText(find.byType(TextFormField), '2,5');
    await tester.tap(find.byTooltip('Увеличить на 1'));
    expect(value, '3.5');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary numbers allow negative values and external updates', (
    tester,
  ) async {
    var value = '2';
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AppNumberField(
                value: value,
                onChanged: (next) => setState(() => value = next),
              );
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '-2');
    await tester.pump();
    await tester.tap(find.byTooltip('Уменьшить на 1'));
    await tester.pump();
    expect(value, '-3');
    rebuild(() => value = '17');
    await tester.pump();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '17',
    );
    expect(tester.takeException(), isNull);
  });
}
