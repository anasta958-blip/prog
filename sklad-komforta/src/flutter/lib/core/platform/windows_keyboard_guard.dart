import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Regularizes modifier events before Flutter queues them with raw Windows
/// messages. Track pending events too: HardwareKeyboard updates only on flush.
final class WindowsModifierKeyGuard {
  WindowsModifierKeyGuard({Map<int, int> initiallyPressed = const {}})
    : _pressed = Map.of(initiallyPressed);

  final Map<int, int> _pressed;

  ui.KeyData? normalize(ui.KeyData data) {
    if (data.physical < 0x700e0 || data.physical > 0x700e7) return data;
    final previous = _pressed[data.physical];
    if (data.type == ui.KeyEventType.down && previous != null) return null;
    if (data.type == ui.KeyEventType.up && previous == null) return null;
    final type = data.type == ui.KeyEventType.repeat && previous == null
        ? ui.KeyEventType.down
        : data.type;
    final logical = previous ?? data.logical;
    if (type == ui.KeyEventType.up) {
      _pressed.remove(data.physical);
    } else {
      _pressed[data.physical] = logical;
    }
    if (type == data.type && logical == data.logical) return data;
    return ui.KeyData(
      timeStamp: data.timeStamp,
      type: type,
      physical: data.physical,
      logical: logical,
      character: data.character,
      synthesized: data.synthesized,
      deviceType: data.deviceType,
    );
  }
}

Future<void> installWindowsKeyboardGuard() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  final binding = WidgetsBinding.instance;
  // ServicesBinding installs onKeyData asynchronously after its initial sync.
  for (var attempt = 0; attempt < 120; attempt++) {
    final original = binding.platformDispatcher.onKeyData;
    if (original != null) {
      final keyboard = HardwareKeyboard.instance;
      final guard = WindowsModifierKeyGuard(
        initiallyPressed: {
          for (final key in keyboard.physicalKeysPressed)
            key.usbHidUsage: keyboard.lookUpLayout(key)!.keyId,
        },
      );
      binding.platformDispatcher.onKeyData = (data) {
        final normalized = guard.normalize(data);
        return normalized == null ? false : original(normalized);
      };
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: StateError('Windows keyboard handler was not initialized.'),
      library: 'windows keyboard guard',
    ),
  );
}
