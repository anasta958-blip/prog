import 'package:flutter/material.dart';
import 'document_layout_models.dart';

/// Selected fields precede available ones; dragging never enables a hidden field.
class DocumentFieldPicker extends StatelessWidget {
  const DocumentFieldPicker({
    required this.fields,
    required this.codes,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final List<DocumentLayoutField> fields;
  final List<String> codes;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = codes
        .where((code) => fields.any((f) => f.code == code))
        .toList();
    final ordered = [
      ...selected,
      ...fields.where((f) => !selected.contains(f.code)).map((f) => f.code),
    ];
    void move(int from, int to) {
      final next = [...selected];
      next.insert(to, next.removeAt(from));
      onChanged(next);
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: ordered.length,
      onReorder: (from, to) {
        if (!enabled || from >= selected.length) return;
        if (to > from) to--;
        move(from, to.clamp(0, selected.length - 1));
      },
      itemBuilder: (context, index) {
        final code = ordered[index];
        final checked = selected.contains(code);
        return Material(
          key: ValueKey(code),
          color: Colors.transparent,
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                enabled: enabled && checked,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_indicator,
                    color: checked ? null : Colors.grey,
                  ),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(fields.firstWhere((f) => f.code == code).label),
                  value: checked,
                  onChanged: !enabled
                      ? null
                      : (value) => onChanged(
                          value == true
                              ? [...selected, code]
                              : selected.where((item) => item != code).toList(),
                        ),
                ),
              ),
              if (checked) ...[
                IconButton(
                  tooltip: 'Переместить выше',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: !enabled || index == 0
                      ? null
                      : () => move(index, index - 1),
                ),
                IconButton(
                  tooltip: 'Переместить ниже',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: !enabled || index == selected.length - 1
                      ? null
                      : () => move(index, index + 1),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
