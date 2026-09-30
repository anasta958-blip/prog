import 'package:flutter/material.dart';

import '../../core/widgets/app_notice.dart';
import 'company_controller.dart';
import 'company_models.dart';

class EmployeePasswordDialog extends StatefulWidget {
  const EmployeePasswordDialog({
    super.key,
    required this.employee,
    required this.controller,
  });

  final EmployeeModel employee;
  final CompanyController controller;

  @override
  State<EmployeePasswordDialog> createState() => _EmployeePasswordDialogState();
}

class _EmployeePasswordDialogState extends State<EmployeePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Сменить пароль сотрудника'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.employee.displayName} · ${widget.employee.login}'),
              const SizedBox(height: 12),
              const Text(
                'Все активные сессии сотрудника будут завершены. Двухфакторная защита сохранится.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Новый пароль',
                  helperText:
                      'Не менее 12 символов, буквы разных регистров, цифра и спецсимвол.',
                  helperMaxLines: 3,
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    (value ?? '').length < 12 ? 'Не менее 12 символов.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmation,
                enabled: !_busy,
                obscureText: _obscure,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Подтвердите пароль',
                ),
                validator: (value) =>
                    value != _password.text ? 'Пароли не совпадают.' : null,
                onFieldSubmitted: (_) {
                  if (!_busy) _submit();
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Сохранение…' : 'Сменить пароль'),
        ),
      ],
    ),
  );

  Future<void> _submit() async {
    if (_form.currentState?.validate() != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final changed = await widget.controller.changeEmployeePassword(
      widget.employee.membershipId,
      _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (changed) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const AppSnackBar(content: Text('Пароль сотрудника изменён.')),
      );
    } else {
      setState(
        () => _error = widget.controller.error ?? 'Не удалось изменить пароль.',
      );
    }
  }
}
