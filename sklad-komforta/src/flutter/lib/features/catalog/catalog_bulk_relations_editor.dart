import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_editor.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

/// A selection snapshot keeps in-flight edits independent of later selection changes.
class CatalogBulkRelationsEditor extends StatefulWidget {
  const CatalogBulkRelationsEditor({
    required this.controller,
    required this.items,
    required this.onClose,
    super.key,
  });

  final CatalogController controller;
  final List<CatalogItem> items;
  final VoidCallback onClose;

  @override
  State<CatalogBulkRelationsEditor> createState() =>
      _CatalogBulkRelationsEditorState();
}

class _CatalogBulkRelationsEditorState
    extends State<CatalogBulkRelationsEditor> {
  bool busy = true;
  bool loaded = false;
  String? error;
  Map<String, List<CatalogItemRelation>> links = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.controller.loadBulkRelations(widget.items);
      if (!mounted) return;
      setState(() {
        links = result;
        loaded = true;
      });
    } on Object catch (exception) {
      if (!mounted) return;
      setState(() {
        loaded = false;
        error = exception is ApiException
            ? exception.message
            : 'Не удалось загрузить связи. Повторите попытку.';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _edit(String dependencyId, String sourceId, bool remove) async {
    if (busy || !loaded) return false;
    final dependency = widget.controller.configuration!.dependencies.firstWhere(
      (item) => item.id == dependencyId,
    );
    final targets = widget.items
        .where((item) => item.categoryId == dependency.targetCategoryId)
        .toList();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.editBulkRelation(
        targets,
        dependencyId,
        sourceId,
        remove: remove,
      );
    } on Object catch (exception) {
      if (mounted) {
        setState(() {
          busy = false;
          error = exception is ApiException
              ? exception.message
              : 'Не удалось сохранить связи. Повторите попытку.';
        });
      }
      return false;
    }
    if (mounted) await _load();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final unique = <String, CatalogItemRelation>{};
    final counts = <String, int>{};
    for (final relations in links.values) {
      for (final relation in relations) {
        final key = '${relation.dependencyId}/${relation.sourceItemId}';
        unique[key] = relation;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return PopScope(
      canPop: !busy,
      child: Column(
        children: [
          if (!loaded && !busy)
            TextButton(
              onPressed: _load,
              child: const Text('Повторить загрузку связей'),
            ),
          Expanded(
            child: CatalogEditor(
              draft: CatalogItemDraft.fromItem(widget.items.first),
              configuration: widget.controller.configuration!,
              saving: busy,
              error: null,
              isNew: false,
              images: const [],
              imagesLoading: false,
              relations: unique.values.toList(),
              relationsLoading: busy,
              relationsError: error,
              bulkItems: widget.items,
              relationCounts: counts,
              onClose: widget.onClose,
              onSave: () async => false,
              onSearchRelations: widget.controller.searchRelationCandidates,
              onAddRelation: !loaded
                  ? null
                  : (dependency, candidate) =>
                        _edit(dependency.id, candidate.id, false),
              onRemoveRelation: !loaded
                  ? null
                  : (dependency, source) => _edit(dependency, source, true),
            ),
          ),
        ],
      ),
    );
  }
}
