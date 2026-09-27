import 'dart:async';

import 'package:flutter/material.dart';

const appNoticeDuration = Duration(seconds: 5);

class AppSnackBar extends SnackBar {
  const AppSnackBar({super.key, required super.content})
    : super(duration: appNoticeDuration);
}

/// Hides only the presentation; validation and operation state stay intact.
class AutoDismissNotice extends StatefulWidget {
  const AutoDismissNotice({
    super.key,
    required this.message,
    required this.child,
  });
  final String message;
  final Widget child;

  @override
  State<AutoDismissNotice> createState() => _AutoDismissNoticeState();
}

class _AutoDismissNoticeState extends State<AutoDismissNotice> {
  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _visible = true;
    _timer = Timer(appNoticeDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void didUpdateWidget(covariant AutoDismissNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _visible ? widget.child : const SizedBox.shrink();
}
