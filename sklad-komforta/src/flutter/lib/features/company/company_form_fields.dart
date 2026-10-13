import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget companyTextField(
  String label,
  String value,
  ValueChanged<String> changed, {
  bool required = false,
  int maximumLength = 500,
  int maxLines = 1,
  String? Function(String?)? validator,
}) => TextFormField(
  key: ValueKey(label),
  initialValue: value,
  onChanged: changed,
  enableInteractiveSelection: true,
  inputFormatters: [LengthLimitingTextInputFormatter(maximumLength)],
  maxLines: maxLines,
  validator: (value) {
    final normalized = value?.trim() ?? '';
    if (required && normalized.length < 2) {
      return 'Введите не менее двух символов';
    }
    return validator?.call(value);
  },
  decoration: InputDecoration(labelText: required ? '$label *' : label),
);

Widget companyDigitsField(
  String label,
  String value,
  ValueChanged<String> changed, {
  List<int> lengths = const [],
  bool required = false,
  Widget? suffix,
}) => TextFormField(
  key: ValueKey(label),
  initialValue: value,
  onChanged: changed,
  enableInteractiveSelection: true,
  keyboardType: TextInputType.number,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    if (lengths.isNotEmpty)
      LengthLimitingTextInputFormatter(lengths.reduce((a, b) => a > b ? a : b)),
  ],
  validator: (value) {
    final normalized = value?.trim() ?? '';
    if (required && normalized.isEmpty) return 'Заполните поле «$label»';
    if (normalized.isEmpty ||
        lengths.isEmpty ||
        lengths.contains(normalized.length)) {
      return null;
    }
    return lengths.length == 1
        ? '$label должен содержать ${lengths.first} цифр'
        : '$label имеет неверную длину';
  },
  decoration: InputDecoration(
    labelText: required ? '$label *' : label,
    suffixIcon: suffix,
  ),
);

Widget companyEmailField(
  String label,
  String value,
  ValueChanged<String> changed,
) => TextFormField(
  key: ValueKey(label),
  initialValue: value,
  onChanged: changed,
  enableInteractiveSelection: true,
  keyboardType: TextInputType.emailAddress,
  validator: (value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)
        ? null
        : 'Введите корректный email';
  },
  decoration: InputDecoration(labelText: label),
);

Widget companyPhoneField(
  String label,
  String value,
  ValueChanged<String> changed, {
  bool required = false,
}) => TextFormField(
  key: ValueKey(label),
  initialValue: formatRussianPhone(value),
  onChanged: changed,
  enableInteractiveSelection: true,
  keyboardType: TextInputType.phone,
  inputFormatters: const [RussianPhoneInputFormatter()],
  validator: (value) {
    final digits = companyOnlyDigits(value ?? '');
    if (digits.isEmpty) return required ? 'Укажите телефон' : null;
    return digits.length == 11 && digits.startsWith('7')
        ? null
        : 'Введите телефон в формате +7 (999) 123-45-67';
  },
  decoration: InputDecoration(
    labelText: required ? '$label *' : label,
    hintText: '+7 (___) ___-__-__',
  ),
);

/// Адаптивная сетка полей сохраняет широкую форму на desktop и не создаёт
/// горизонтального переполнения на небольших окнах.
final class CompanyFieldRow extends StatelessWidget {
  const CompanyFieldRow({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => CompanyFieldGrid(
    columns: children.whereType<Expanded>().length,
    children: [for (final child in children.whereType<Expanded>()) child.child],
  );
}

final class CompanyFieldGrid extends StatelessWidget {
  const CompanyFieldGrid({
    required this.children,
    required this.columns,
    super.key,
  });

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actualColumns = constraints.maxWidth < 520
          ? 1
          : constraints.maxWidth < 760
          ? columns.clamp(1, 2)
          : columns;
      const gap = 10.0;
      final width =
          (constraints.maxWidth - gap * (actualColumns - 1)) / actualColumns;
      return Wrap(
        spacing: gap,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

String? companyWebsiteValidator(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.contains('.')
      ? null
      : 'Введите адрес сайта с http:// или https://';
}

String companyOnlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

String formatRussianPhone(String value) {
  var digits = companyOnlyDigits(value);
  if (digits.isEmpty) return '';
  if (digits.startsWith('8')) digits = '7${digits.substring(1)}';
  if (!digits.startsWith('7')) digits = '7$digits';
  digits = digits.substring(0, digits.length.clamp(0, 11));

  final buffer = StringBuffer('+7');
  if (digits.length > 1) {
    buffer.write(' (${digits.substring(1, digits.length.clamp(1, 4))}');
  }
  if (digits.length >= 4) buffer.write(')');
  if (digits.length > 4) {
    buffer.write(' ${digits.substring(4, digits.length.clamp(4, 7))}');
  }
  if (digits.length > 7) {
    buffer.write('-${digits.substring(7, digits.length.clamp(7, 9))}');
  }
  if (digits.length > 9) buffer.write('-${digits.substring(9)}');
  return buffer.toString();
}

/// Приводит ввод российского номера к единому виду и не допускает лишние
/// символы или цифры сверх полной маски.
final class RussianPhoneInputFormatter extends TextInputFormatter {
  const RussianPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatRussianPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
