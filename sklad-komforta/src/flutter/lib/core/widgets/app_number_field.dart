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
    this.focusNode,
    this.onSubmitted,
    this.groupThousands = false,
  });
  final String value;

  /// Разделители тысяч только для отображения; обработчики получают исходное число.
  final bool groupThousands;
  final ValueChanged<String> onChanged;
  final double? minimum;
  final bool minimumExclusive;
  final bool enabled;
  final InputDecoration decoration;
  final TextStyle? style;
  final FormFieldValidator<String>? validator;

  /// Внешний узел фокуса для клавиатурной навигации между полями строки.
  final FocusNode? focusNode;

  /// Вызывается по Enter с текущим текстом поля.
  final ValueChanged<String>? onSubmitted;
  @override
  State<AppNumberField> createState() => _AppNumberFieldState();
}

class _AppNumberFieldState extends State<AppNumberField> {
  String raw(String text) =>
      widget.groupThousands ? text.replaceAll(RegExp(r'\s'), '') : text;
  String display(String text) {
    if (!widget.groupThousands) return text;
    final parts = raw(text).split(RegExp('[.,]'));
    final integer = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ' ',
    );
    return parts.length == 1 ? integer : '$integer,${parts[1]}';
  }

  late final input = TextEditingController(text: display(widget.value));
  double? parse(String text) => double.tryParse(raw(text).replaceAll(',', '.'));
  @override
  void didUpdateWidget(covariant AppNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !(parse(input.text) != null &&
            parse(input.text) == parse(widget.value))) {
      input.text = display(widget.value);
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
      text: display(text),
      selection: TextSelection.collapsed(offset: display(text).length),
    );
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: input,
    focusNode: widget.focusNode,
    enabled: widget.enabled,
    style: widget.style,
    textInputAction: widget.onSubmitted == null ? null : TextInputAction.next,
    onFieldSubmitted: (text) => widget.onSubmitted?.call(raw(text)),
    keyboardType: TextInputType.numberWithOptions(
      decimal: true,
      signed: widget.minimum == null || widget.minimum! < 0,
    ),
    inputFormatters: [
      TextInputFormatter.withFunction((oldValue, next) {
        if (raw(next.text).isEmpty) {
          return const TextEditingValue(
            text: '0',
            selection: TextSelection(baseOffset: 0, extentOffset: 1),
          );
        }
        final pattern = widget.minimum != null && widget.minimum! >= 0
            ? RegExp(r'^\d*[.,]?\d*$')
            : RegExp(r'^-?\d*[.,]?\d*$');
        if (!pattern.hasMatch(raw(next.text))) return oldValue;
        if (!widget.groupThousands) return next;
        final formatted = display(next.text);
        final offset = next.selection.baseOffset.clamp(0, next.text.length);
        final rawBefore = raw(next.text.substring(0, offset)).length;
        var caret = 0;
        var digits = 0;
        while (caret < formatted.length && digits < rawBefore) {
          if (formatted[caret] != ' ') digits++;
          caret++;
        }
        return next.copyWith(
          text: formatted,
          selection: TextSelection.collapsed(offset: caret),
          composing: TextRange.empty,
        );
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
    onChanged: (text) => widget.onChanged(raw(text)),
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
      return widget.validator?.call(text == null ? null : raw(text));
    },
  );
}
