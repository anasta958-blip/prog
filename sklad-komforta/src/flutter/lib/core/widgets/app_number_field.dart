import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Numeric editor shared by desktop and web, with explicit unit steppers.
class AppNumberField extends StatefulWidget {
  const AppNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.minimum,
    this.minimumExclusive = false,
    this.enabled = true,
    this.decoration = const InputDecoration(),
    this.style,
    this.validator,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final double? minimum;
  final bool minimumExclusive;
  final bool enabled;
  final InputDecoration decoration;
  final TextStyle? style;
  final FormFieldValidator<String>? validator;
  @override
  State<AppNumberField> createState() => _AppNumberFieldState();
}

class _AppNumberFieldState extends State<AppNumberField> {
  late final input = TextEditingController(text: widget.value);
  double? parse(String text) => double.tryParse(text.replaceAll(',', '.'));
  @override
  void didUpdateWidget(covariant AppNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !(parse(input.text) != null &&
            parse(input.text) == parse(widget.value))) {
      input.text = widget.value;
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void step(int delta) {
    var next = (parse(input.text) ?? 0) + delta;
    if (widget.minimumExclusive &&
        widget.minimum != null &&
        next <= widget.minimum!) {
      return;
    }
    if (widget.minimum != null && next < widget.minimum!) {
      next = widget.minimum!;
    }
    final text = next == next.roundToDouble()
        ? next.toInt().toString()
        : next.toString();
    input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: input,
    enabled: widget.enabled,
    style: widget.style,
    keyboardType: TextInputType.numberWithOptions(
      decimal: true,
      signed: widget.minimum == null || widget.minimum! < 0,
    ),
    inputFormatters: [
      TextInputFormatter.withFunction((oldValue, next) {
        final pattern = widget.minimum != null && widget.minimum! >= 0
            ? RegExp(r'^\d*[.,]?\d*$')
            : RegExp(r'^-?\d*[.,]?\d*$');
        return pattern.hasMatch(next.text) ? next : oldValue;
      }),
    ],
    decoration: widget.decoration.copyWith(
      suffixIconConstraints: const BoxConstraints(
        minWidth: 22,
        maxWidth: 22,
        maxHeight: 32,
      ),
      suffixIcon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final delta in [1, -1])
            SizedBox(
              height: 16,
              width: 22,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: delta == 1 ? 'Увеличить на 1' : 'Уменьшить на 1',
                onPressed: widget.enabled ? () => step(delta) : null,
                icon: Icon(
                  delta == 1 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    ),
    onChanged: widget.onChanged,
    validator: (text) {
      final value = parse(text ?? '');
      if ((text ?? '').isNotEmpty && (value == null || !value.isFinite)) {
        return 'Введите число.';
      }
      if (value != null && widget.minimum != null && value < widget.minimum!) {
        return 'Минимум: ${widget.minimum}';
      }
      if (value != null && widget.minimumExclusive && value == widget.minimum) {
        return 'Значение должно быть больше ${widget.minimum}';
      }
      return widget.validator?.call(text);
    },
  );
}
