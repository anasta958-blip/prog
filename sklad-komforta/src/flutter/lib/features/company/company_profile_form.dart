import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';

/// Единая форма реквизитов: используется и при создании организации, и позже.
final class CompanyProfileForm extends StatelessWidget {
  const CompanyProfileForm({
    required this.profile,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final CompanyProfileDraft profile;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _responsive([
        _field(
          'Название организации',
          profile.organizationName,
          (value) => profile.organizationName = value,
          validator: (value) =>
              value.trim().length < 2 ? 'Введите не менее двух символов' : null,
        ),
        AppSelectField<String>(
          value: profile.companyType,
          label: 'Тип компании',
          options: const [
            AppSelectOption(value: 'ООО', label: 'ООО'),
            AppSelectOption(value: 'ИП', label: 'ИП'),
            AppSelectOption(value: 'АО', label: 'АО'),
          ],
          enabled: enabled,
          onChanged: (value) {
            profile.companyType = value;
            onChanged();
          },
        ),
      ]),
      const SizedBox(height: 14),
      _field('Юридическое название', profile.legalName ?? '', (value) {
        profile.legalName = value;
      }),
      const SizedBox(height: 14),
      _responsive([
        _field(
          'ИНН',
          profile.inn ?? '',
          (value) => profile.inn = value,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          validator: (value) => _validateDigits(value, const {
            10,
            12,
          }, 'ИНН должен содержать 10 или 12 цифр'),
        ),
        _field(
          'КПП',
          profile.kpp ?? '',
          (value) => profile.kpp = value,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          validator: (value) =>
              _validateDigits(value, const {9}, 'КПП должен содержать 9 цифр'),
        ),
        _field(
          'ОГРН',
          profile.ogrn ?? '',
          (value) => profile.ogrn = value,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(15),
          ],
          validator: (value) => _validateDigits(value, const {
            13,
            15,
          }, 'ОГРН должен содержать 13 или 15 цифр'),
        ),
      ]),
      const SizedBox(height: 22),
      const Divider(),
      const SizedBox(height: 18),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Контактные данные',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: 14),
      _field(
        'Адрес',
        profile.address ?? '',
        (value) => profile.address = value,
      ),
      const SizedBox(height: 14),
      _responsive([
        _field(
          'Телефон',
          profile.phone ?? '',
          (value) => profile.phone = value,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-\s]')),
            LengthLimitingTextInputFormatter(24),
          ],
          validator: _validatePhone,
        ),
        _field(
          'Email',
          profile.email ?? '',
          (value) => profile.email = value,
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
        ),
      ]),
    ],
  );

  Widget _field(
    String label,
    String value,
    ValueChanged<String> update, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String value)? validator,
  }) => TextFormField(
    initialValue: value,
    enabled: enabled,
    onChanged: (value) {
      update(value);
      onChanged();
    },
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: validator == null ? null : (value) => validator(value ?? ''),
    enableInteractiveSelection: true,
    decoration: InputDecoration(labelText: label),
  );

  static String? _validateDigits(
    String value,
    Set<int> lengths,
    String message,
  ) {
    final normalized = value.trim();
    return normalized.isEmpty || lengths.contains(normalized.length)
        ? null
        : message;
  }

  static String? _validatePhone(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final count = normalized.replaceAll(RegExp(r'\D'), '').length;
    return count >= 10 && count <= 15
        ? null
        : 'Телефон должен содержать от 10 до 15 цифр';
  }

  static String? _validateEmail(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    return RegExp(
          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
          caseSensitive: false,
        ).hasMatch(normalized)
        ? null
        : 'Введите корректный email';
  }

  Widget _responsive(List<Widget> fields) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 620
        ? Column(
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                fields[index],
                if (index + 1 < fields.length) const SizedBox(height: 12),
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                Expanded(child: fields[index]),
                if (index + 1 < fields.length) const SizedBox(width: 12),
              ],
            ],
          ),
  );
}
