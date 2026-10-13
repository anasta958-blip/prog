import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'company_models.dart';
import 'company_form_fields.dart';
import 'vat_rates_field.dart';

/// Одна форма юрлица для мастера организации и рабочего раздела компании.
final class LegalEntityFields extends StatelessWidget {
  const LegalEntityFields({
    required this.item,
    required this.onChanged,
    this.lookupButton,
    this.lookupMessages = const [],
    super.key,
  });
  final LegalEntityModel item;
  final VoidCallback onChanged;
  final Widget? lookupButton;
  final List<Widget> lookupMessages;
  void change(VoidCallback update) {
    update();
    onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey(item.companyType),
    mainAxisSize: MainAxisSize.min,
    children: [
      companyTextField(
        'Короткое название',
        item.name,
        (value) => item.name = value,
        required: true,
      ),
      const SizedBox(height: 12),
      AppSelectField<String>(
        value: item.companyType,
        label: 'Тип компании',
        options: const [
          AppSelectOption(value: 'ooo', label: 'ООО'),
          AppSelectOption(value: 'ip', label: 'ИП'),
        ],
        onChanged: (value) => change(() {
          item.companyType = value ?? 'ooo';
          if (item.companyType == 'ip') item.kpp = null;
        }),
      ),
      const SizedBox(height: 12),
      companyTextField(
        item.companyType == 'ip'
            ? 'ФИО индивидуального предпринимателя'
            : 'Юридическое название',
        item.legalName ?? '',
        (value) => item.legalName = value,
        required: true,
      ),
      const SizedBox(height: 12),
      CompanyFieldRow(
        children: [
          Expanded(
            child: companyDigitsField(
              'ИНН',
              item.inn ?? '',
              (value) => item.inn = value,
              required: true,
              lengths: item.companyType == 'ip' ? const [12] : const [10],
              suffix: lookupButton,
            ),
          ),
          if (item.companyType != 'ip') ...[
            const SizedBox(width: 10),
            Expanded(
              child: companyDigitsField(
                'КПП',
                item.kpp ?? '',
                (value) => item.kpp = value,
                required: true,
                lengths: const [9],
              ),
            ),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: companyDigitsField(
              item.companyType == 'ip' ? 'ОГРНИП' : 'ОГРН',
              item.ogrn ?? '',
              (value) => item.ogrn = value,
              required: true,
              lengths: item.companyType == 'ip' ? const [15] : const [13],
            ),
          ),
        ],
      ),
      ...lookupMessages,
      const SizedBox(height: 12),
      companyTextField(
        'Адрес',
        item.address ?? '',
        (value) => item.address = value,
      ),
      const SizedBox(height: 12),
      CompanyFieldRow(
        children: [
          Expanded(
            child: companyPhoneField(
              'Телефон',
              item.phone ?? '',
              (value) => item.phone = value,
              required: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: companyEmailField(
              'Email',
              item.email ?? '',
              (value) => item.email = value,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      companyTextField(
        'Сайт',
        item.website ?? '',
        (value) => item.website = value,
        validator: companyWebsiteValidator,
      ),
      const SizedBox(height: 12),
      CompanyFieldRow(
        children: [
          Expanded(
            child: companyTextField(
              'Директор',
              item.directorName ?? '',
              (value) => item.directorName = value,
              required: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: companyTextField(
              'Подписант',
              item.signatoryName ?? '',
              (value) => item.signatoryName = value,
              required: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: companyTextField(
              'Должность подписанта',
              item.signatoryTitle ?? '',
              (value) => item.signatoryTitle = value,
              required: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      companyTextField(
        'Банк',
        item.bankName ?? '',
        (value) => item.bankName = value,
        required: true,
      ),
      const SizedBox(height: 12),
      CompanyFieldRow(
        children: [
          Expanded(
            child: companyDigitsField(
              'БИК',
              item.bankBik ?? '',
              (value) => item.bankBik = value,
              required: true,
              lengths: const [9],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: companyDigitsField(
              'Расчётный счёт',
              item.bankAccount ?? '',
              (value) => item.bankAccount = value,
              required: true,
              lengths: const [20],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: companyDigitsField(
              'Корреспондентский счёт',
              item.corrAccount ?? '',
              (value) => item.corrAccount = value,
              required: true,
              lengths: const [20],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      companyTextField(
        'Вводный текст по умолчанию',
        item.introDefault ?? '',
        (value) => item.introDefault = value,
        maximumLength: 2000,
      ),
      const SizedBox(height: 12),
      companyTextField(
        'Дополнительный текст по умолчанию',
        item.footerDefault ?? '',
        (value) => item.footerDefault = value,
        maximumLength: 2000,
      ),
      const SizedBox(height: 12),
      VatRatesField(
        initialValue: item.vatRates,
        onChanged: (value) => change(() => item.vatRates = value),
      ),
      CheckboxListTile(
        value: item.isDefault,
        onChanged: (value) => change(() => item.isDefault = value ?? false),
        title: const Text('Исполнитель по умолчанию'),
        contentPadding: EdgeInsets.zero,
      ),
    ],
  );
}
