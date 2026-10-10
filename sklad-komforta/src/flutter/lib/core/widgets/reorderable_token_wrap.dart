import 'package:flutter/material.dart';

class _TokenMove {
  const _TokenMove(this.source, this.index);
  final List<Widget> source;
  final int index;
}

/// Переносимая формула: все компоненты видны, порядок меняется перетаскиванием.
/// Индексы onReorder совпадают с контрактом ReorderableListView.
class ReorderableTokenWrap extends StatelessWidget {
  const ReorderableTokenWrap({
    super.key,
    required this.children,
    required this.onReorder,
  });
  final List<Widget> children;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < children.length; index++)
          DragTarget<_TokenMove>(
            onWillAcceptWithDetails: (details) =>
                identical(details.data.source, children) &&
                details.data.index != index,
            onAcceptWithDetails: (details) => onReorder(
              details.data.index,
              index > details.data.index ? index + 1 : index,
            ),
            builder: (context, candidates, rejected) => Draggable<_TokenMove>(
              data: _TokenMove(children, index),
              feedback: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: children[index],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: candidates.isEmpty
                        ? Colors.transparent
                        : Theme.of(context).colorScheme.primary,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth - 2,
                  ),
                  child: children[index],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
