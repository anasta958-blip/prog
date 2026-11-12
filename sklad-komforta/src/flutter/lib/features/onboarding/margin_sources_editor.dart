import 'package:flutter/material.dart';

import '../../core/widgets/app_select_field.dart';
import 'onboarding_field_registry.dart';
import 'onboarding_models.dart';

/// Edits the sources of the fixed margin formula without changing its calculation.
final class MarginSourcesEditor extends StatelessWidget {
  const MarginSourcesEditor({
    required this.category,
    required this.settings,
    required this.onChanged,
    super.key,
  });

  final CatalogCategoryDraft category;
  final MarginSettingsDraft? settings;
  final ValueChanged<MarginSettingsDraft?> onChanged;

  void _update(void Function(MarginSettingsDraft) edit) {
    final next = settings == null
        ? MarginSettingsDraft(categoryClientId: category.clientId)
        : MarginSettingsDraft.fromJson(settings!.toJson());
    edit(next);
    onChanged(
      next.revenueFields.isEmpty && next.costFields.isEmpty ? null : next,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sources(context, true),
      const Divider(height: 28),
      _sources(context, false),
      if (settings != null && !settings!.hasRequiredSources)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Для сохранения выберите хотя бы одно поле выручки и одно поле затрат.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  Widget _sources(BuildContext context, bool revenue) {
    final title = revenue ? 'Выручка' : 'Затраты';
    final key = revenue ? 'revenue' : 'cost';
    final selected =
        (revenue ? settings?.revenueFields : settings?.costFields) ??
        <MarginFieldDraft>[];
    final available = category.fields
        .where(
          (field) =>
              const [
                'money',
                'calculated_money',
              ].contains(catalogFieldType(field)) &&
              !selected.any((source) => source.fieldCode == field.fieldCode),
        )
        .toList();
    List<MarginFieldDraft> target(MarginSettingsDraft value) =>
        revenue ? value.revenueFields : value.costFields;
    final theme = Theme.of(context);
    String label(String code) {
      final field = category.fields
          .where((field) => field.fieldCode == code)
          .firstOrNull;
      return field == null ? code : catalogFieldLabel(field);
    }

    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Text('$title =', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (var index = 0; index < selected.length; index++) ...[
            if (index > 0) const Text('+', style: TextStyle(fontSize: 18)),
            Container(
              key: ValueKey('margin-$key-${selected[index].fieldCode}'),
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth.clamp(0, 320),
              ),
              padding: const EdgeInsets.only(
                left: 12,
                right: 4,
                top: 4,
                bottom: 4,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label(selected[index].fieldCode),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip:
                            'Убрать поле из ${revenue ? 'выручки' : 'затрат'}',
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _update((value) => target(value).removeAt(index)),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: ValueKey(
                          'margin-$key-quantity-${selected[index].fieldCode}',
                        ),
                        value: selected[index].multiplyByQuantity,
                        visualDensity: VisualDensity.compact,
                        onChanged: (checked) => _update(
                          (value) => target(value)[index].multiplyByQuantity =
                              checked ?? false,
                        ),
                      ),
                      const Flexible(
                        child: Text(
                          '× количество',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          SizedBox(
            width: constraints.maxWidth.clamp(0, 240),
            child: AppSelectField<String>(
              key: ValueKey('margin-$key-add-${selected.length}'),
              value: null,
              label: available.isEmpty
                  ? 'Нет доступных полей'
                  : 'Добавить поле',
              isDense: true,
              enabled: available.isNotEmpty,
              options: [
                for (final field in available)
                  AppSelectOption(
                    value: field.fieldCode,
                    label: catalogFieldLabel(field),
                  ),
              ],
              onChanged: (code) {
                if (code == null ||
                    !available.any((field) => field.fieldCode == code)) {
                  return;
                }
                _update((value) {
                  if (!target(value).any((field) => field.fieldCode == code)) {
                    target(value).add(MarginFieldDraft(fieldCode: code));
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
