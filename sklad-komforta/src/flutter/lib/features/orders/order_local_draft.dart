import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sklad_komforta_app/features/orders/order_models.dart';

/// Локальный черновик комплектации на устройстве. Записи выполняются по
/// очереди, поэтому старое автосохранение не перезапишет более новое.
final class OrderLocalDraft {
  OrderLocalDraft(this.key, {FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();

  final String key;
  final FlutterSecureStorage storage;
  Future<void> _pending = Future<void>.value();

  Future<OrderDocument?> read() async {
    await _pending;
    final value = await storage.read(key: key);
    return value == null
        ? null
        : OrderDocument.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  Future<void> write(OrderDocument order) {
    final snapshot = jsonEncode(order.toSnapshot());
    return _enqueue(() => storage.write(key: key, value: snapshot));
  }

  Future<void> clear() => _enqueue(() => storage.delete(key: key));

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
