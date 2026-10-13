import 'package:flutter/material.dart';
import 'company_models.dart';
import 'company_form_fields.dart';
import 'legal_entity_fields.dart';

/// Реквизиты первого юрлица используют ту же форму, что настройки компании.
final class CompanyProfileForm extends StatefulWidget {
  const CompanyProfileForm({
    required this.profile,
    required this.onChanged,
    this.enabled = true,
    this.lookupByInn,
    super.key,
  });
  final CompanyProfileDraft profile;
  final VoidCallback onChanged;
  final bool enabled;
  final Future<CompanyRegistryRecord> Function(String inn)? lookupByInn;
  @override
  State<CompanyProfileForm> createState() => _CompanyProfileFormState();
}

final class _CompanyProfileFormState extends State<CompanyProfileForm> {
  bool lookingUp = false;
  int revision = 0;
  String? message;
  String? error;

  void changed() {
    widget.profile.syncLegalEntity();
    widget.onChanged();
  }

  Future<void> lookup() async {
    if (lookingUp || widget.lookupByInn == null) return;
    final item = widget.profile.ensureLegalEntity();
    final inn = companyOnlyDigits(item.inn ?? '');
    if (inn.length != 10 && inn.length != 12) {
      setState(
        () => error = 'Введите ИНН: 10 цифр для организации или 12 для ИП.',
      );
      return;
    }
    setState(() {
      lookingUp = true;
      error = null;
      message = null;
    });
    try {
      final record = await widget.lookupByInn!(inn);
      if (!mounted) return;
      record.applyToLegalEntity(item);
      if (widget.profile.organizationName.trim().isEmpty) {
        widget.profile.organizationName = record.name;
      }
      changed();
      setState(() {
        revision++;
        message =
            'Реквизиты заполнены из реестра. Проверьте их; банковские реквизиты и недостающие данные заполните вручную.';
      });
    } on Object {
      if (mounted) {
        setState(
          () => error =
              'Не удалось заполнить по ИНН. Проверьте ИНН и подключение, повторите поиск или заполните вручную.',
        );
      }
    } finally {
      if (mounted) setState(() => lookingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.profile.ensureLegalEntity();
    return AbsorbPointer(
      absorbing: !widget.enabled || lookingUp,
      child: Column(
        key: ValueKey(revision),
        children: [
          companyTextField(
            'Название организации',
            widget.profile.organizationName,
            (value) {
              widget.profile.organizationName = value;
              changed();
            },
            required: true,
            maximumLength: 200,
          ),
          const SizedBox(height: 14),
          LegalEntityFields(
            item: item,
            onChanged: () {
              changed();
              setState(() {});
            },
            lookupButton: widget.lookupByInn == null
                ? null
                : lookingUp
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Заполнить по ИНН',
                    onPressed: lookup,
                    icon: const Icon(Icons.manage_search),
                  ),
            lookupMessages: [
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (message != null) Text(message!),
            ],
          ),
        ],
      ),
    );
  }
}
