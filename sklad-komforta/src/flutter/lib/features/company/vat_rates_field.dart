import 'package:flutter/material.dart';

class VatRatesField extends StatefulWidget {
  const VatRatesField({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });
  final List<double?> initialValue;
  final ValueChanged<List<double?>> onChanged;
  @override
  State<VatRatesField> createState() => _VatRatesFieldState();
}

class _VatRatesFieldState extends State<VatRatesField> {
  final input = TextEditingController();
  String? inputError;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<List<double?>>(
    initialValue: List.of(widget.initialValue),
    validator: (values) => input.text.trim().isNotEmpty
        ? 'Добавьте введённую ставку кнопкой «+» или очистите поле.'
        : values == null || values.isEmpty
        ? 'Добавьте хотя бы одну ставку.'
        : null,
    builder: (field) {
      final values = field.value ?? <double?>[];
      void update(List<double?> next) {
        field.didChange(next);
        widget.onChanged(next);
      }

      void add(double? value) {
        if (values.contains(value)) {
          setState(() => inputError = 'Такая ставка уже добавлена.');
          return;
        }
        if (values.length >= 20) {
          setState(() => inputError = 'Можно добавить не более 20 ставок.');
          return;
        }
        update([...values, value]);
        input.clear();
        setState(() => inputError = null);
      }

      void submit() {
        final value = double.tryParse(
          input.text.trim().replaceAll(',', '.').replaceAll('%', ''),
        );
        if (value == null || !value.isFinite || value < 0 || value > 100) {
          setState(() => inputError = 'Введите одну ставку от 0 до 100.');
          return;
        }
        add(value);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Доступные ставки НДС',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in values)
                InputChip(
                  label: Text(
                    value == null
                        ? 'Без НДС'
                        : '${value == value.roundToDouble() ? value.toInt() : value}%',
                  ),
                  deleteButtonTooltipMessage: 'Удалить ставку',
                  onDeleted: () =>
                      update(values.where((item) => item != value).toList()),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Новая ставка НДС',
                    hintText: 'Например: 20',
                    suffixText: '%',
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ),
              IconButton(
                tooltip: 'Добавить ставку НДС',
                onPressed: submit,
                icon: const Icon(Icons.add),
              ),
              TextButton(
                onPressed: values.contains(null) ? null : () => add(null),
                child: const Text('Без НДС'),
              ),
            ],
          ),
          if (inputError ?? field.errorText case final String error)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}
