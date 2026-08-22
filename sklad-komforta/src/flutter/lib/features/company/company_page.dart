import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/features/company/company_controller.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/company/company_profile_form.dart';

/// Рабочее пространство реквизитов организации после onboarding.
final class CompanyPage extends StatefulWidget {
  const CompanyPage({required this.controller, super.key});

  final CompanyController controller;

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

final class _CompanyPageState extends State<CompanyPage> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final profile = widget.controller.profile;
      if (widget.controller.loading && profile == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (profile == null) {
        return _CompanyError(
          message: widget.controller.error ?? 'Данные компании не найдены.',
          onRetry: widget.controller.initialize,
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1080;
          final editor = _Editor(
            formKey: _formKey,
            profile: profile,
            controller: widget.controller,
            onSave: _save,
          );
          final preview = _CompanyPreview(profile: profile);
          return ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const Text(
                'Компания',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Реквизиты организации используются в предложениях, документах и печатных формах.',
                style: TextStyle(color: Color(0xFF8FA4C2)),
              ),
              const SizedBox(height: 22),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: editor),
                    const SizedBox(width: 18),
                    Expanded(flex: 2, child: preview),
                  ],
                )
              else ...[
                editor,
                const SizedBox(height: 18),
                preview,
              ],
            ],
          );
        },
      );
    },
  );

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    await widget.controller.save();
  }
}

final class _Editor extends StatelessWidget {
  const _Editor({
    required this.formKey,
    required this.profile,
    required this.controller,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final CompanyProfileDraft profile;
  final CompanyController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Реквизиты организации',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            CompanyProfileForm(
              profile: profile,
              enabled: !controller.saving,
              onChanged: controller.markChanged,
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 14),
              Text(
                controller.error!,
                style: const TextStyle(color: Color(0xFFFF809D)),
              ),
            ],
            if (controller.saved) ...[
              const SizedBox(height: 14),
              const Text(
                'Изменения сохранены.',
                style: TextStyle(color: Color(0xFF50C878)),
              ),
            ],
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: controller.saving ? null : onSave,
                icon: controller.saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _CompanyPreview extends StatelessWidget {
  const _CompanyPreview({required this.profile});
  final CompanyProfileDraft profile;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Предварительный просмотр',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 22),
          const CircleAvatar(
            radius: 34,
            backgroundColor: Color(0xFF1A3152),
            child: Icon(Icons.business_outlined, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            profile.organizationName.trim().isEmpty
                ? 'Название организации'
                : profile.organizationName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          const Divider(),
          _row('Тип компании', profile.companyType),
          _row('Юридическое название', profile.legalName, stacked: true),
          _row('ИНН', profile.inn),
          _row('КПП', profile.kpp),
          _row('ОГРН', profile.ogrn),
          _row('Адрес', profile.address, stacked: true),
          _row('Телефон', profile.phone),
          _row('Email', profile.email),
        ],
      ),
    ),
  );

  Widget _row(String label, String? value, {bool stacked = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF8297B5))),
              const SizedBox(height: 3),
              Text(value?.trim().isNotEmpty == true ? value! : '—'),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Color(0xFF8297B5)),
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Text(value?.trim().isNotEmpty == true ? value! : '—'),
              ),
            ],
          ),
  );
}

final class _CompanyError extends StatelessWidget {
  const _CompanyError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42, color: Color(0xFFFF809D)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
        ],
      ),
    ),
  );
}
