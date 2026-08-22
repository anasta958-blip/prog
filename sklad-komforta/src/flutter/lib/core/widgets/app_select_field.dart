import 'package:flutter/material.dart';

/// Одно значение выпадающего поля. `null` используется для пунктов вроде
/// «Все разделы» или «Не выбрано» и не требует специальных строк-маркеров.
final class AppSelectOption<T> {
  const AppSelectOption({required this.value, required this.label, this.color});

  final T? value;
  final String label;
  final Color? color;
}

/// Единое выпадающее поле приложения.
///
/// [MenuAnchor] удерживает список у границы поля и самостоятельно переносит его
/// над полем, когда ниже не хватает места. Это устраняет перекрытие подписи и
/// разное поведение стандартных Dropdown-компонентов на Web и Desktop.
final class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
    this.validator,
    this.isDense = false,
    this.enabled = true,
    super.key,
  });

  final T? value;
  final List<AppSelectOption<T>> options;
  final String label;
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T?>? validator;
  final bool isDense;
  final bool enabled;

  @override
  Widget build(BuildContext context) => FormField<T?>(
    initialValue: value,
    validator: validator,
    builder: (field) {
      final controller = MenuController();
      final selected = options.where((option) => option.value == value);
      final active = enabled && onChanged != null;

      return MenuAnchor(
        controller: controller,
        crossAxisUnconstrained: false,
        alignmentOffset: const Offset(0, 4),
        menuChildren: [
          for (final option in options)
            MenuItemButton(
              closeOnActivate: true,
              onPressed: active
                  ? () {
                      field.didChange(option.value);
                      onChanged?.call(option.value);
                    }
                  : null,
              leadingIcon: option.value == value
                  ? const Icon(Icons.check, size: 18)
                  : const SizedBox(width: 18),
              child: _OptionContent(option: option),
            ),
        ],
        builder: (context, menuController, _) => InkWell(
          onTap: active
              ? () => menuController.isOpen
                    ? menuController.close()
                    : menuController.open()
              : null,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            isEmpty: selected.isEmpty,
            isFocused: menuController.isOpen,
            decoration: InputDecoration(
              labelText: label,
              isDense: isDense,
              enabled: active,
              errorText: field.errorText,
              suffixIcon: Icon(
                menuController.isOpen
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
              ),
            ),
            child: selected.isEmpty
                ? const SizedBox(height: 20)
                : _OptionContent(option: selected.first),
          ),
        ),
      );
    },
  );
}

final class _OptionContent<T> extends StatelessWidget {
  const _OptionContent({required this.option});
  final AppSelectOption<T> option;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (option.color case final color?) ...[
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 15),
        ),
        const SizedBox(width: 7),
      ],
      Flexible(
        child: Text(option.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}
