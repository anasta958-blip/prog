import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/company/company_profile_form.dart';

void main() {
  test('старые плоские реквизиты читаются только в юрлицо', () {
    final profile = CompanyProfileDraft.fromJson({
      'organizationName': 'Склад',
      'companyType': 'ИП',
      'inn': '772994700534',
      'legalName': 'Иванов Иван',
    });
    expect(profile.legalEntity!.companyType, 'ip');
    expect(profile.legalEntity!.inn, '772994700534');
    expect(profile.toJson().keys, ['organizationName', 'legalEntity']);
    expect(CompanyProfileDraft(organizationName: 'Склад').toJson(), {
      'organizationName': 'Склад',
    });
  });
  test('черновик сохраняет реквизиты, банк и НДС первого юрлица', () {
    final profile = CompanyProfileDraft(organizationName: 'Склад');
    profile.ensureLegalEntity()
      ..inn = '7707083893'
      ..bankName = 'Банк'
      ..bankBik = '044525225'
      ..bankAccount = '40702810000000000001'
      ..corrAccount = '30101810000000000225'
      ..vatRates = [null, 20];
    final restored = CompanyProfileDraft.fromJson(profile.toJson());
    expect(restored.legalEntity!.inn, '7707083893');
    expect(profile.toJson().containsKey('inn'), isFalse);
    expect(restored.legalEntity!.bankName, 'Банк');
    expect(restored.legalEntity!.bankBik, '044525225');
    expect(restored.legalEntity!.bankAccount, '40702810000000000001');
    expect(restored.legalEntity!.vatRates, [null, 20]);
    expect(restored.legalEntity!.isDefault, isTrue);
  });

  testWidgets('мастер проверяет обязательные поля и заполняет ИНН из реестра', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1500);
    addTearDown(tester.view.reset);
    final profile = CompanyProfileDraft(organizationName: '');
    final form = GlobalKey<FormState>();
    String? requestedInn;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              key: form,
              child: CompanyProfileForm(
                profile: profile,
                onChanged: () {},
                lookupByInn: (inn) async {
                  requestedInn = inn;
                  return const CompanyRegistryRecord(
                    companyType: 'ooo',
                    name: 'Ромашка',
                    legalName: 'ООО Ромашка',
                    inn: '7707083893',
                    kpp: '770701001',
                    ogrn: '1027700132195',
                    directorName: 'Иванов Иван Иванович',
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await tester.enterText(field('ИНН *'), '7707083893');
    await tester.tap(find.byTooltip('Заполнить по ИНН'));
    await tester.pumpAndSettle();
    expect(requestedInn, '7707083893');
    expect(profile.legalEntity!.legalName, 'ООО Ромашка');
    expect(profile.organizationName, 'Ромашка');
    expect(find.text('ООО Ромашка'), findsOneWidget);
    await tester.enterText(field('Телефон *'), '89991234567');
    expect(profile.legalEntity!.phone, '+7 (999) 123-45-67');
    // Реестр не заменяет обязательное ручное заполнение банковских реквизитов.
    expect(form.currentState!.validate(), isFalse);
    for (final width in [400.0, 1000.0]) {
      tester.view.physicalSize = Size(width, 1500);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
