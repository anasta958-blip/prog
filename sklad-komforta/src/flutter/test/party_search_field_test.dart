import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/quotes/party_search_field.dart';

void main() {
  for (final type in ['ip', 'ooo']) {
    test('business customer $type displays phone without duplicate name', () {
      final client =
          CompanyClientModel(id: type, name: 'Название', companyType: type)
            ..companyName = 'Название'
            ..phone = '+7 (999) 123-45-67';
      expect(
        PartySearchOption.client(client).label,
        'Название — +7 (999) 123-45-67',
      );
      client.phone = '  ';
      expect(PartySearchOption.client(client).label, 'Название');
    });
  }
  test(
    'party labels include company name or phone and match partial input',
    () {
      final company = CompanyClientModel(
        id: 'company',
        name: 'Ромашка',
        companyType: 'ooo',
      )..companyName = 'ООО Ромашка и партнёры';
      final person = CompanyClientModel(id: 'person', name: 'Иван Иванов')
        ..phone = '+7 (999) 123-45-67';
      final ip = LegalEntityModel(id: 'ip', name: 'Мастер', companyType: 'ip')
        ..legalName = 'ИП Петров Пётр';
      final companyOption = PartySearchOption.client(company);
      final personOption = PartySearchOption.client(person);
      final ipOption = PartySearchOption.executor(ip);

      expect(companyOption.label, 'Ромашка — ООО Ромашка и партнёры');
      expect(companyOption.matches('партнё'), isTrue);
      expect(personOption.label, 'Иван Иванов — +7 (999) 123-45-67');
      expect(personOption.matches('12345'), isTrue);
      expect(personOption.matches('Иван'), isTrue);
      expect(ipOption.label, 'Мастер — ИП Петров Пётр');
      expect(ipOption.matches('Петр'), isTrue);
      expect(ipOption.matches('Петров'), isTrue);
      expect(ipOption.matches('отсутствует'), isFalse);
    },
  );

  testWidgets('typing clears selection until an existing party is chosen', (
    tester,
  ) async {
    String? selected = 'one';
    final options = [
      const PartySearchOption(
        id: 'one',
        title: 'Ромашка',
        detail: 'ООО Ромашка',
        searchTerms: ['Ромашка', 'ООО Ромашка'],
      ),
      const PartySearchOption(
        id: 'two',
        title: 'Иван Иванов',
        detail: '+7 999 123-45-67',
        searchTerms: ['Иван Иванов', '+7 999 123-45-67'],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 420,
              child: PartySearchField(
                value: selected,
                options: options,
                label: 'Заказчик',
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PartySearchField));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('party-search-Заказчик')),
      'несуществующий',
    );
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Совпадений нет'), findsOneWidget);
    expect(find.text('Выберите запись из списка'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('party-search-Заказчик')),
      '12345',
    );
    await tester.pumpAndSettle();
    expect(find.text('Иван Иванов — +7 999 123-45-67'), findsOneWidget);
    await tester.tap(find.text('Иван Иванов — +7 999 123-45-67'));
    await tester.pumpAndSettle();
    expect(selected, 'two');
    expect(find.text('Выберите запись из списка'), findsNothing);
  });
}
