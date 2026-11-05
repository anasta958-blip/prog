import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Keeps the whole sheet in the page scroll flow, including at manual zoom.
class DocumentPaperSurface extends StatelessWidget {
  const DocumentPaperSurface({
    required this.width,
    required this.height,
    required this.child,
    this.fitWidth = false,
    this.fillWidth = false,
    this.zoom = 1,
    super.key,
  });

  final double width, height, zoom;
  final bool fitWidth;
  final bool fillWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : width;
      final scale = fillWidth
          ? math.max(zoom, available / width)
          : (fitWidth ? math.min(1.0, available / width) : 1.0) * zoom;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        primary: false,
        child: SizedBox(
          width: math.max(available, width * scale),
          height: height * scale,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width * scale,
              height: height * scale,
              child: FittedBox(
                child: SizedBox(width: width, height: height, child: child),
              ),
            ),
          ),
        ),
      );
    },
  );
}
