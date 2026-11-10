import 'dart:async';
import 'package:sklad_komforta_app/core/network/realtime_client.dart';

final class CalculationRealtime implements RealtimeSource {
  final controller = StreamController<RealtimeEvent>.broadcast();
  @override
  Stream<RealtimeEvent> get events => controller.stream;
  @override
  void start() {}
  @override
  Future<void> close() => controller.close();
  void emit(String kind) =>
      controller.add(RealtimeEvent(topic: 'catalog', kind: kind));
}
