import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sklad_komforta_app/core/platform/windows_keyboard_guard.dart';

ui.KeyData event(
  ui.KeyEventType type, {
  int physical = 0x700e0,
  int logical = 0x200000100,
  bool synthesized = false,
}) => ui.KeyData(
  timeStamp: const Duration(seconds: 1),
  type: type,
  character: null,
  physical: physical,
  logical: logical,
  synthesized: synthesized,
);

void main() {
  test(
    'modifier duplicate downs and unmatched ups are removed before batching',
    () {
      final guard = WindowsModifierKeyGuard();
      expect(guard.normalize(event(ui.KeyEventType.down)), isNotNull);
      expect(guard.normalize(event(ui.KeyEventType.down)), isNull);
      expect(
        guard.normalize(event(ui.KeyEventType.down, synthesized: true)),
        isNull,
      );
      expect(
        guard.normalize(event(ui.KeyEventType.repeat))!.type,
        ui.KeyEventType.repeat,
      );
      expect(guard.normalize(event(ui.KeyEventType.up)), isNotNull);
      expect(guard.normalize(event(ui.KeyEventType.up)), isNull);
      expect(guard.normalize(event(ui.KeyEventType.down)), isNotNull);
    },
  );

  test('initial pressed state and missing down are handled', () {
    final guard = WindowsModifierKeyGuard(
      initiallyPressed: {0x700e0: 0x200000100},
    );
    expect(guard.normalize(event(ui.KeyEventType.down)), isNull);
    expect(guard.normalize(event(ui.KeyEventType.up))!.logical, 0x200000100);
    expect(
      guard.normalize(event(ui.KeyEventType.repeat))!.type,
      ui.KeyEventType.down,
    );
  });

  test('text and Pause events pass unchanged', () {
    final guard = WindowsModifierKeyGuard();
    for (final physical in [0x70004, 0x70048, 0]) {
      for (final type in ui.KeyEventType.values) {
        final data = event(type, physical: physical, logical: physical);
        expect(guard.normalize(data), same(data));
      }
    }
  });

  test(
    'Shift Pause and injected Ctrl form a valid HardwareKeyboard sequence',
    () {
      final guard = WindowsModifierKeyGuard();
      final keyboard = HardwareKeyboard();
      final events = [
        event(ui.KeyEventType.down, physical: 0x700e1, logical: 0x200000102),
        event(ui.KeyEventType.down, physical: 0x70048, logical: 0x100000509),
        event(ui.KeyEventType.down),
        event(ui.KeyEventType.down),
        event(ui.KeyEventType.down, synthesized: true),
        event(ui.KeyEventType.up),
        event(ui.KeyEventType.up),
        event(ui.KeyEventType.up, physical: 0x70048, logical: 0x100000509),
        event(ui.KeyEventType.up, physical: 0x700e1, logical: 0x200000102),
      ];
      for (final data in events.map(guard.normalize).whereType<ui.KeyData>()) {
        final physical = PhysicalKeyboardKey(data.physical);
        final logical = LogicalKeyboardKey(data.logical);
        keyboard.handleKeyEvent(
          data.type == ui.KeyEventType.down
              ? KeyDownEvent(
                  physicalKey: physical,
                  logicalKey: logical,
                  timeStamp: data.timeStamp,
                )
              : KeyUpEvent(
                  physicalKey: physical,
                  logicalKey: logical,
                  timeStamp: data.timeStamp,
                ),
        );
      }
      expect(keyboard.physicalKeysPressed, isEmpty);
      expect(keyboard.logicalKeysPressed, isEmpty);
    },
  );
}
