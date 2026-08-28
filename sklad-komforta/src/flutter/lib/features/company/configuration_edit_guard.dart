import 'package:flutter/material.dart';

/// Координирует выход из редактора рабочей конфигурации с внешней навигацией.
///
/// Сам guard не хранит черновик и не решает, есть ли изменения. Активный
/// редактор регистрирует обработчик, который показывает предупреждение и
/// возвращает разрешение или запрет на переход.
final class ConfigurationEditGuard {
  Object? _owner;
  Future<bool> Function(BuildContext context)? _confirmLeave;

  void attach(
    Object owner,
    Future<bool> Function(BuildContext context) confirmLeave,
  ) {
    _owner = owner;
    _confirmLeave = confirmLeave;
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _confirmLeave = null;
  }

  Future<bool> canLeave(BuildContext context) async =>
      await _confirmLeave?.call(context) ?? true;
}
