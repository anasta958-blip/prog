import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sklad_komforta_app/core/widgets/app_notice.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/core/widgets/app_select_field.dart';
import 'package:sklad_komforta_app/core/widgets/app_number_field.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_controller.dart';
import 'package:sklad_komforta_app/features/quotes/quote_client_access_api.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_local_draft.dart';
import 'package:sklad_komforta_app/features/quotes/quote_preview_page.dart';

const _background = Color(0xFF0B1119);
const _surface = Color(0xFF111A27);
const _surfaceRaised = Color(0xFF162131);
const _border = Color(0xFF293A51);
const _muted = Color(0xFF8FA4C2);
const _accent = Color(0xFF4D8DFF);

/// Полноэкранный редактор специализированного содержимого карточки КП/ПКП.
final class QuoteEditorPage extends StatefulWidget {
  const QuoteEditorPage({
    required this.config,
    required this.authController,
    required this.board,
    this.card,
    this.creationColumnId,
    this.createKind,
    required this.onBack,
    this.controller,
    super.key,
  });

  final AppConfig config;
  final AuthController authController;
  final KanbanBoard board;
  final KanbanCard? card;
  final String? creationColumnId;
  final QuoteKind? createKind;
  final VoidCallback onBack;
  final QuoteController? controller;

  @override
  State<QuoteEditorPage> createState() => _QuoteEditorPageState();
}

final class _QuoteEditorPageState extends State<QuoteEditorPage> {
  late final QuoteController controller;
  late final bool ownsController;
  final Set<String> expandedCategories = <String>{};
  final Set<String> expandedSections = <String>{};
  final Set<String> initializedExpansionVariants = <String>{};
  final ScrollController variantScrollController = ScrollController();
  late final _ColumnWidthStore columnWidthStore;
  late final QuoteClientAccessApi clientAccessApi;
  bool creatingClientAccess = false;
  QuoteLocalDraft? localDraft;
  bool draftReady = false;
  bool hadLocalChanges = false;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        QuoteController(widget.config, widget.authController);
    clientAccessApi = QuoteClientAccessApi(widget.config);
    columnWidthStore = _ColumnWidthStore(
      storageKey: _columnWidthStorageKey(
        widget.authController.accessToken,
        widget.board.id,
      ),
    );
    if (ownsController) {
      localDraft = QuoteLocalDraft(
        '${_columnWidthStorageKey(widget.authController.accessToken, widget.board.id)}'
        '.draft.${widget.card?.id ?? 'new.${widget.creationColumnId}.${widget.createKind?.apiValue}'}',
      );
    }
    _initializeEditor();
  }

  Future<void> _initializeEditor() async {
    await controller.initialize(
      board: widget.board,
      card: widget.card,
      createKind: widget.createKind,
    );
    if (!mounted) return;
    try {
      final restored = await localDraft?.read();
      if (!mounted) return;
      if (restored != null && controller.draft != null) {
        controller.draft = restored;
        controller.updateDocument((_) {});
        controller.showDraftRestoredMessage();
        hadLocalChanges = true;
      }
    } on Object {
      controller.error = 'Не удалось прочитать локальный черновик.';
    }
    if (!mounted) return;
    controller.addListener(_persistLocalDraft);
    setState(() => draftReady = true);
  }

  void _persistLocalDraft() {
    final store = localDraft;
    final draft = controller.draft;
    if (store == null || draft == null) return;
    if (controller.dirty) {
      hadLocalChanges = true;
      unawaited(_writeLocalDraft());
    } else if (hadLocalChanges) {
      hadLocalChanges = false;
      unawaited(
        store.clear().catchError((Object _) {
          if (mounted) {
            setState(
              () =>
                  controller.error = 'Не удалось удалить сохранённый черновик.',
            );
          }
        }),
      );
      final cardId = controller.persistedCardId;
      if (cardId != null) {
        final key =
            '${_columnWidthStorageKey(widget.authController.accessToken, widget.board.id)}.draft.$cardId';
        if (store.key != key) localDraft = QuoteLocalDraft(key);
      }
    }
  }

  Future<bool> _writeLocalDraft() async {
    try {
      final draft = controller.draft;
      if (draft != null) await localDraft?.write(draft);
      return true;
    } on Object {
      if (mounted) {
        setState(
          () => controller.error =
              'Не удалось сохранить локальный черновик. Не закрывайте редактор.',
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    controller.removeListener(_persistLocalDraft);
    variantScrollController.dispose();
    columnWidthStore.dispose();
    clientAccessApi.close();
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if ((ownsController && !draftReady) ||
          (controller.loading && controller.draft == null)) {
        return const ColoredBox(
          color: _background,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (controller.draft == null) {
        return _LoadFailure(
          message: controller.error ?? 'Предложение не загружено.',
          onBack: widget.onBack,
        );
      }
      _initializeExpansionForActiveVariant();
      return ColoredBox(
        color: _background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            return Column(
              children: [
                _CommandBar(
                  controller: controller,
                  card: widget.card,
                  board: widget.board,
                  compact: compact,
                  onBack: _requestBack,
                  onPreview: _openPreview,
                  onPrint: _printPdf,
                  onShare: creatingClientAccess ? null : _manageClientAccess,
                  onSave: () => controller.save(
                    board: widget.board,
                    card: widget.card,
                    creationColumnId: widget.creationColumnId,
                  ),
                ),
                if (controller.error case final message?)
                  _MessageBanner(message: message, error: true),
                if (controller.successMessage case final message?)
                  _MessageBanner(message: message),
                Expanded(
                  child: _body(compact: compact, constraints: constraints),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  Widget _body({required bool compact, required BoxConstraints constraints}) {
    if (compact) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _MetadataPanel(controller: controller, board: widget.board),
          const SizedBox(height: 12),
          _TypeTabs(controller: controller),
          const SizedBox(height: 10),
          _VariantTabs(controller: controller),
          const SizedBox(height: 10),
          if (controller.activeVariant case final variant?) ...[
            _VariantContent(
              controller: controller,
              board: widget.board,
              variant: variant,
              expandedCategories: expandedCategories,
              expandedSections: expandedSections,
              onToggleCategory: _toggleCategory,
              onToggleSection: _toggleSection,
              onAddCategory: _addCategory,
              onAddSection: _addSection,
              onAddPosition: _addPosition,
              columnWidthStore: columnWidthStore,
            ),
            const SizedBox(height: 12),
            _SummaryColumn(controller: controller, variant: variant),
          ],
        ],
      );
    }

    final variant = controller.activeVariant;
    final horizontalSummaries = constraints.maxWidth >= 1400;
    final summaryWidth = horizontalSummaries
        ? 552.0
        : constraints.maxWidth < 1180
        ? 230.0
        : 270.0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 14, 0),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _MetadataPanel(
                          controller: controller,
                          board: widget.board,
                        ),
                        const SizedBox(height: 12),
                        _TypeTabs(controller: controller),
                        const SizedBox(height: 10),
                        _VariantTabs(controller: controller),
                      ],
                    ),
                  ),
                  if (variant != null) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: summaryWidth,
                      child: _SummaryColumn(
                        controller: controller,
                        variant: variant,
                        horizontal: horizontalSummaries,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: variantScrollController,
            thumbVisibility: true,
            child: ListView(
              controller: variantScrollController,
              padding: const EdgeInsets.fromLTRB(18, 0, 14, 24),
              children: [
                if (variant != null)
                  _VariantContent(
                    controller: controller,
                    board: widget.board,
                    variant: variant,
                    expandedCategories: expandedCategories,
                    expandedSections: expandedSections,
                    onToggleCategory: _toggleCategory,
                    onToggleSection: _toggleSection,
                    onAddCategory: _addCategory,
                    onAddSection: _addSection,
                    onAddPosition: _addPosition,
                    columnWidthStore: columnWidthStore,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openPreview() {
    final draft = controller.draft;
    if (draft == null) return;

    final client = controller.clients
        .where((item) => item.id == draft.clientId)
        .firstOrNull;
    final executor = controller.executors
        .where((item) => item.id == draft.executorCompanyId)
        .firstOrNull;
    final manager = controller.employees
        .where((item) => item.userId == draft.managerUserId)
        .firstOrNull;
    final salesHead = controller.employees
        .where((item) => item.userId == draft.salesHeadUserId)
        .firstOrNull;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuotePreviewPage(
          draft: draft,
          client: client,
          executor: executor,
          managerName: manager?.displayName,
          salesHeadName: salesHead?.displayName,
          cardNumber: widget.card?.number,
          proposalTypeId: controller.activeTypeId,
          variantId: controller.activeVariantId,
        ),
      ),
    );
  }

  Future<void> _printPdf() async {
    final file = await controller.downloadPdf(
      board: widget.board,
      card: widget.card,
    );
    if (file == null || !mounted) return;
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Сохранить PDF',
        fileName: file.fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: file.bytes,
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(content: Text('Не удалось сохранить PDF.')),
      );
    }
  }

  Future<void> _manageClientAccess() async {
    if (controller.dirty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(
          content: Text(
            'Сначала сохраните изменения. Ссылка открывает только сохранённую версию предложения.',
          ),
        ),
      );
      return;
    }
    final cardId = controller.persistedCardId ?? widget.card?.id;
    if (cardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(
          content: Text('Сначала сохраните новое предложение.'),
        ),
      );
      return;
    }

    setState(() => creatingClientAccess = true);
    try {
      final status = await widget.authController.executeAuthorized(
        (token) =>
            clientAccessApi.getLinkStatus(token, widget.board.id, cardId),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _ClientAccessDialog(
          initialStatus: status,
          publicAppBaseUrl: widget.config.resolvedPublicAppBaseUrl,
          onCreate: (lifetimeDays) => widget.authController.executeAuthorized(
            (token) => clientAccessApi.createLink(
              token,
              widget.board.id,
              cardId,
              lifetimeDays: lifetimeDays,
            ),
          ),
          onRevoke: () => widget.authController.executeAuthorized(
            (token) =>
                clientAccessApi.revokeLink(token, widget.board.id, cardId),
          ),
        ),
      );
    } on ApiException catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(AppSnackBar(content: Text(exception.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const AppSnackBar(
            content: Text('Не удалось открыть управление клиентской ссылкой.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => creatingClientAccess = false);
    }
  }

  void _toggleCategory(String id) {
    setState(() {
      expandedCategories.contains(id)
          ? expandedCategories.remove(id)
          : expandedCategories.add(id);
    });
  }

  /// Первый показ каждого варианта раскрывает всю его структуру. После этого
  /// ручное состояние пользователя сохраняется и не сбрасывается перестроением.
  void _initializeExpansionForActiveVariant() {
    final variant = controller.activeVariant;
    if (variant == null || !initializedExpansionVariants.add(variant.id)) {
      return;
    }
    expandedCategories.addAll(variant.categories.map((item) => item.id));
    expandedSections.addAll(
      variant.categories.expand(
        (category) => category.sections.map((section) => section.id),
      ),
    );
  }

  void _toggleSection(String id) {
    setState(() {
      expandedSections.contains(id)
          ? expandedSections.remove(id)
          : expandedSections.add(id);
    });
  }

  Future<void> _requestBack() async {
    if (!controller.dirty) {
      widget.onBack();
      return;
    }
    final leave = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Есть несохранённые изменения'),
        content: const Text(
          'Изменения останутся в локальном черновике на этом устройстве. Серверная версия изменится только после нажатия «Сохранить».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Удалить черновик и выйти'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'draft'),
            child: const Text('Сохранить черновик и выйти'),
          ),
        ],
      ),
    );
    if (leave == 'discard') {
      try {
        await localDraft?.clear();
        if (mounted) widget.onBack();
      } on Object {
        if (mounted) {
          setState(() => controller.error = 'Не удалось удалить черновик.');
        }
      }
    } else if (leave == 'draft' && await _writeLocalDraft() && mounted) {
      widget.onBack();
    }
  }

  Future<void> _addCategory() async {
    final variant = controller.activeVariant;
    final configuration = controller.catalog;
    if (variant == null || configuration == null) return;
    final allowedCategoryIds = widget.board.categories
        .map((item) => item.categoryId)
        .toSet();
    final available = configuration.categories
        .where(
          (candidate) =>
              allowedCategoryIds.contains(candidate.id) &&
              !variant.categories.any(
                (existing) => existing.catalogCategoryId == candidate.id,
              ),
        )
        .toList();
    final selected = await _selectDialog<CatalogCategory>(
      title: 'Добавить категорию',
      values: available,
      label: (item) => item.name,
    );
    if (selected != null) {
      controller.addCategory(selected);
      expandedCategories.add(
        variant.categories
            .firstWhere((item) => item.catalogCategoryId == selected.id)
            .id,
      );
    }
  }

  Future<void> _addSection(QuoteCategoryDraft category) async {
    final source = controller.catalog?.categories
        .where((item) => item.id == category.catalogCategoryId)
        .firstOrNull;
    if (source == null) return;
    final available = source.sections
        .where(
          (candidate) => !category.sections.any(
            (existing) => existing.catalogSectionId == candidate.id,
          ),
        )
        .toList();
    final selected = await _selectDialog<CatalogSection>(
      title: 'Добавить раздел',
      values: available,
      label: (item) => item.name,
    );
    if (selected != null) {
      controller.addSection(category, selected);
      expandedSections.add(
        category.sections
            .firstWhere((item) => item.catalogSectionId == selected.id)
            .id,
      );
    }
  }

  Future<T?> _selectDialog<T>({
    required String title,
    required List<T> values,
    required String Function(T item) label,
  }) => showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: values.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Доступных элементов нет.'),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: values.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => ListTile(
                  title: Text(label(values[index])),
                  onTap: () => Navigator.pop(context, values[index]),
                ),
              ),
      ),
    ),
  );

  Future<void> _addPosition(
    QuoteCategoryDraft category,
    QuoteSectionDraft section,
  ) async {
    final categoryId = category.catalogCategoryId;
    if (categoryId == null) return;
    if (!mounted) return;
    final item = await showDialog<CatalogItem>(
      context: context,
      builder: (dialogContext) => _CatalogPickerDialog(
        controller: controller,
        categoryId: categoryId,
        sectionId: section.catalogSectionId,
      ),
    );
    if (item != null) {
      await controller.addCatalogPosition(category, section, item);
    }
  }
}

final class _CommandBar extends StatelessWidget {
  const _CommandBar({
    required this.controller,
    required this.card,
    required this.board,
    required this.compact,
    required this.onBack,
    required this.onPreview,
    required this.onPrint,
    required this.onShare,
    required this.onSave,
  });

  final QuoteController controller;
  final KanbanCard? card;
  final KanbanBoard board;
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onPreview;
  final VoidCallback onPrint;
  final VoidCallback? onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1722),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, color: _accent),
            const SizedBox(width: 9),
            Text(
              card == null
                  ? 'Новая ${draft.kind.label}'
                  : '${draft.kind.label} №${card!.number}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (!compact) ...[
              const SizedBox(width: 18),
              const Text(
                'Коммерческие предложения',
                style: TextStyle(color: _muted),
              ),
            ],
            const Spacer(),
            if (board.specialization == WorkflowSpecialization.quoteAndPrequote)
              SizedBox(
                width: 130,
                child: AppSelectField<QuoteKind>(
                  value: draft.kind,
                  label: 'Документ',
                  isDense: true,
                  options: QuoteKind.values
                      .map(
                        (value) =>
                            AppSelectOption(value: value, label: value.label),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      controller.updateDocument((draft) => draft.kind = value);
                    }
                  },
                ),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: controller.saving ? null : onSave,
              icon: controller.saving
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(compact ? '' : 'Сохранить'),
            ),
            if (compact) ...[
              const SizedBox(width: 7),
              IconButton.outlined(
                onPressed: onPreview,
                tooltip: 'Предпросмотр выбранного варианта',
                icon: const Icon(Icons.visibility_outlined, size: 18),
              ),
              const SizedBox(width: 7),
              IconButton.outlined(
                onPressed: controller.printing ? null : onPrint,
                tooltip: 'Печать выбранного варианта',
                icon: controller.printing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined, size: 18),
              ),
              const SizedBox(width: 7),
              IconButton.outlined(
                onPressed: onShare,
                tooltip: 'Ссылка для клиента',
                icon: const Icon(Icons.link, size: 18),
              ),
            ],
            if (!compact) ...[
              const SizedBox(width: 7),
              _CommandAction(
                icon: Icons.visibility_outlined,
                label: 'Предпросмотр',
                onPressed: onPreview,
              ),
              _CommandAction(
                icon: Icons.print_outlined,
                label: 'Печать',
                onPressed: controller.printing ? null : onPrint,
              ),
              _CommandAction(
                icon: Icons.link,
                label: 'Ссылка',
                onPressed: onShare,
              ),
            ],
            const SizedBox(width: 7),
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(compact ? '' : 'Назад'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CommandAction extends StatelessWidget {
  const _CommandAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 7),
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
    ),
  );
}

final class _ClientAccessDialog extends StatefulWidget {
  const _ClientAccessDialog({
    required this.initialStatus,
    required this.publicAppBaseUrl,
    required this.onCreate,
    required this.onRevoke,
  });

  final QuoteClientAccessStatus initialStatus;
  final String publicAppBaseUrl;
  final Future<CreatedQuoteClientAccess> Function(int lifetimeDays) onCreate;
  final Future<void> Function() onRevoke;

  @override
  State<_ClientAccessDialog> createState() => _ClientAccessDialogState();
}

final class _ClientAccessDialogState extends State<_ClientAccessDialog> {
  static const _lifetimes = [1, 3, 7, 14, 30];
  late QuoteClientAccessStatus status = widget.initialStatus;
  int lifetimeDays = 7;
  bool loading = false;
  String? error;

  /// Секреты действующей ссылки: только что созданной либо полученной при
  /// повторном открытии окна.
  late CreatedQuoteClientAccess? created = widget.initialStatus.secrets;

  /// Ссылка была создана в этом окне, а не восстановлена из сохранённой.
  bool createdNow = false;

  String get link {
    final baseUri = Uri.parse(widget.publicAppBaseUrl);
    return baseUri
        .replace(
          queryParameters: {
            ...baseUri.queryParameters,
            'quoteAccessToken': created!.accessToken,
          },
        )
        .toString();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.lock_outline, color: _accent),
        SizedBox(width: 10),
        Expanded(child: Text('Доступ клиента к предложению')),
      ],
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Клиент входит по отдельной ссылке и паролю. Учётная запись сотрудника ему не требуется.',
            style: TextStyle(color: _muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          _ClientAccessStatusPanel(status: status),
          if (created case final access?) ...[
            const SizedBox(height: 16),
            _ClientAccessValue(
              label: createdNow ? 'Новая ссылка' : 'Ссылка',
              value: link,
              onCopy: () => _copy(context, link, 'Ссылка скопирована'),
            ),
            const SizedBox(height: 12),
            _ClientAccessValue(
              label: 'Пароль',
              value: access.password,
              onCopy: () =>
                  _copy(context, access.password, 'Пароль скопирован'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Ссылку и пароль можно снова открыть в этом окне, пока ссылка действует. Просмотр записывается в журнал изменений.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ] else if (status.isActive) ...[
            const SizedBox(height: 12),
            const Text(
              'Эта ссылка создана до обновления системы, поэтому её нельзя показать повторно. Создайте новую ссылку, чтобы отправить её клиенту.',
              style: TextStyle(
                color: Color(0xFFE6B86D),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          if (created == null || !createdNow) ...[
            const SizedBox(height: 16),
            AppSelectField<int>(
              value: lifetimeDays,
              label: 'Срок новой ссылки',
              options: [
                for (final days in _lifetimes)
                  AppSelectOption(value: days, label: _daysLabel(days)),
              ],
              onChanged: loading
                  ? null
                  : (value) => setState(() => lifetimeDays = value ?? 7),
            ),
            if (status.isActive) ...[
              const SizedBox(height: 10),
              const Text(
                'При создании новой ссылки текущая ссылка и открытая по ней клиентская сессия будут отозваны.',
                style: TextStyle(
                  color: Color(0xFFE6B86D),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
          if (error case final message?) ...[
            const SizedBox(height: 12),
            AutoDismissNotice(
              message: message,
              child: Text(
                message,
                style: const TextStyle(color: Color(0xFFFF718A)),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      if (status.isActive && !createdNow)
        TextButton.icon(
          onPressed: loading ? null : _revoke,
          icon: const Icon(Icons.link_off, size: 18),
          label: const Text('Отозвать'),
        ),
      if (!createdNow)
        FilledButton.icon(
          onPressed: loading ? null : _create,
          icon: loading
              ? const SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_link, size: 18),
          label: Text(status.isActive ? 'Создать новую' : 'Создать ссылку'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  );

  Future<void> _create() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.onCreate(lifetimeDays);
      if (!mounted) return;
      setState(() {
        created = value;
        createdNow = true;
        status = QuoteClientAccessStatus(
          isActive: true,
          createdAt: DateTime.now(),
          expiresAt: value.expiresAt,
          lastAccessedAt: null,
        );
      });
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } on Object {
      if (mounted) {
        setState(() => error = 'Не удалось создать клиентскую ссылку.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _revoke() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отозвать доступ?'),
        content: const Text(
          'Ссылка и уже открытая по ней клиентская сессия сразу перестанут работать.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.onRevoke();
      if (!mounted) return;
      setState(() {
        created = null;
        status = const QuoteClientAccessStatus(
          isActive: false,
          createdAt: null,
          expiresAt: null,
          lastAccessedAt: null,
        );
      });
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } on Object {
      if (mounted) {
        setState(() => error = 'Не удалось отозвать клиентскую ссылку.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  static String _daysLabel(int days) {
    if (days == 1) return '1 день';
    if (days == 3) return '3 дня';
    return '$days дней';
  }

  static Future<void> _copy(
    BuildContext context,
    String value,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(AppSnackBar(content: Text(message)));
  }
}

final class _ClientAccessStatusPanel extends StatelessWidget {
  const _ClientAccessStatusPanel({required this.status});

  final QuoteClientAccessStatus status;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: status.isActive
          ? const Color(0xFF102A23)
          : const Color(0xFF151E2A),
      border: Border.all(
        color: status.isActive ? const Color(0xFF28674F) : _border,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status.isActive ? Icons.verified_user_outlined : Icons.link_off,
            color: status.isActive ? const Color(0xFF71E6AD) : _muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.isActive ? 'Доступ активен' : 'Активной ссылки нет',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (status.expiresAt case final expiresAt?) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Действует до ${_formatDate(expiresAt)}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
                if (status.lastAccessedAt case final accessedAt?) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Последнее открытие: ${_formatDate(accessedAt)}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ] else if (status.isActive) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Клиент ещё не открывал ссылку',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  static String _formatDate(DateTime value) =>
      DateFormat('dd.MM.yyyy HH:mm').format(value.toLocal());
}

final class _ClientAccessValue extends StatelessWidget {
  const _ClientAccessValue({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF0D151F),
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SelectableText(value),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            tooltip: 'Копировать',
            icon: const Icon(Icons.copy_outlined, size: 19),
          ),
        ],
      ),
    ),
  );
}

final class _MetadataPanel extends StatelessWidget {
  const _MetadataPanel({required this.controller, required this.board});
  final QuoteController controller;
  final KanbanBoard board;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 780;
          final fields = <Widget>[
            _TextField(
              initialValue: draft.title,
              label: 'Название КП',
              onChanged: (value) =>
                  controller.updateDocument((draft) => draft.title = value),
            ),
            AppSelectField<String>(
              value: draft.clientId.isEmpty ? null : draft.clientId,
              label: 'Заказчик',
              options: controller.clients
                  .map(
                    (item) => AppSelectOption(value: item.id, label: item.name),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  controller.updateDocument((draft) => draft.clientId = value);
                }
              },
            ),
            AppSelectField<String>(
              value: draft.executorCompanyId.isEmpty
                  ? null
                  : draft.executorCompanyId,
              label: 'Исполнитель',
              options: controller.executors
                  .map(
                    (item) => AppSelectOption(value: item.id, label: item.name),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  controller.selectExecutor(value);
                }
              },
            ),
            AppSelectField<String>(
              value: draft.managerUserId,
              label: 'Менеджер',
              options: [
                const AppSelectOption<String>(value: null, label: 'Не указан'),
                ...controller.employees
                    .where((item) => item.isActive)
                    .map(
                      (item) => AppSelectOption(
                        value: item.userId,
                        label: item.displayName,
                      ),
                    ),
              ],
              onChanged: (value) => controller.updateDocument(
                (draft) => draft.managerUserId = value,
              ),
            ),
            AppSelectField<String>(
              value: draft.salesHeadUserId,
              label: 'РОП',
              options: [
                const AppSelectOption<String>(value: null, label: 'Не указан'),
                ...controller.employees
                    .where((item) => item.isActive)
                    .map(
                      (item) => AppSelectOption(
                        value: item.userId,
                        label: item.displayName,
                      ),
                    ),
              ],
              onChanged: (value) => controller.updateDocument(
                (draft) => draft.salesHeadUserId = value,
              ),
            ),
          ];
          final selectionMode = AppSelectField<String>(
            value: draft.selectionMode,
            label: 'Выбор клиента',
            options: const [
              AppSelectOption(value: 'variant', label: 'Один вариант'),
              AppSelectOption(
                value: 'proposal_type',
                label: 'Тип со всеми вариантами',
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.updateDocument(
                  (draft) => draft.selectionMode = value,
                );
              }
            },
          );
          return Column(
            children: [
              if (narrow) ...[
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: field,
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: selectionMode,
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(flex: 2, child: fields[0]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[3]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[4]),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: fields[1]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[2]),
                    const SizedBox(width: 10),
                    Expanded(child: selectionMode),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _TextField(
                initialValue: draft.additionalInformation,
                label: 'Дополнительная информация',
                maxLines: 2,
                onChanged: (value) => controller.updateDocument(
                  (draft) => draft.additionalInformation = value,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _TypeTabs extends StatelessWidget {
  const _TypeTabs({required this.controller});
  final QuoteController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final type in controller.draft!.proposalTypes)
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: _TabButton(
              label: type.name,
              selected: type.id == controller.activeType?.id,
              icon: Icons.folder_copy_outlined,
              badge: type.id == controller.draft!.clientSelectedProposalTypeId
                  ? 'Выбран клиентом'
                  : null,
              onPressed: () => controller.selectType(type.id),
              deleteTooltip: controller.draft!.proposalTypes.length <= 1
                  ? 'Нельзя удалить последний тип'
                  : 'Удалить тип',
              onDelete:
                  controller.saving ||
                      controller.draft!.proposalTypes.length <= 1
                  ? null
                  : () => _confirmTabRemoval(
                      context,
                      title: 'Удалить тип «${type.name}»?',
                      content:
                          'Все варианты и позиции этого типа будут удалены из предложения.',
                      onConfirmed: () => controller.removeType(type.id),
                    ),
              onRename: () => _rename(context, type.name, (value) {
                type.name = value;
                controller.positionChanged();
              }),
            ),
          ),
        OutlinedButton.icon(
          onPressed: controller.addType,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Добавить тип'),
        ),
      ],
    ),
  );
}

final class _VariantTabs extends StatelessWidget {
  const _VariantTabs({required this.controller});
  final QuoteController controller;

  @override
  Widget build(BuildContext context) {
    final type = controller.activeType;
    if (type == null) return const SizedBox.shrink();
    final vatRates = controller.availableVatRates;
    final numericVatRates = vatRates.whereType<double>().toSet().toList()
      ..sort();
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final variant in type.variants)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _TabButton(
                      label: variant.name,
                      selected: variant.id == controller.activeVariant?.id,
                      badge:
                          type.selectedByClient &&
                              variant.id == type.selectedVariantId
                          ? 'Выбран клиентом'
                          : null,
                      onPressed: () => controller.selectVariant(variant.id),
                      deleteTooltip: type.variants.length <= 1
                          ? 'Нельзя удалить последний вариант'
                          : 'Удалить вариант',
                      onDelete: controller.saving || type.variants.length <= 1
                          ? null
                          : () => _confirmTabRemoval(
                              context,
                              title: 'Удалить вариант «${variant.name}»?',
                              content:
                                  'Все категории, разделы и позиции этого варианта будут удалены из предложения.',
                              onConfirmed: () =>
                                  controller.removeVariant(type.id, variant.id),
                            ),
                      onRename: () => _rename(context, variant.name, (value) {
                        variant.name = value;
                        controller.positionChanged();
                      }),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: controller.addVariant,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить вариант'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 145,
          child: AppSelectField<double>(
            value: controller.activeVariant?.vatRate,
            label: 'НДС',
            isDense: true,
            options: [
              if (vatRates.contains(null))
                const AppSelectOption<double>(value: null, label: 'Без НДС'),
              for (final rate in numericVatRates)
                AppSelectOption(value: rate, label: '${_formatVatRate(rate)}%'),
            ],
            onChanged: (value) {
              final variant = controller.activeVariant;
              if (variant != null) {
                variant.vatRate = value;
                controller.positionChanged();
              }
            },
          ),
        ),
      ],
    );
  }

  static String _formatVatRate(double rate) => rate == rate.roundToDouble()
      ? rate.toInt().toString()
      : rate
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
}

final class _VariantContent extends StatelessWidget {
  const _VariantContent({
    required this.controller,
    required this.board,
    required this.variant,
    required this.expandedCategories,
    required this.expandedSections,
    required this.onToggleCategory,
    required this.onToggleSection,
    required this.onAddCategory,
    required this.onAddSection,
    required this.onAddPosition,
    required this.columnWidthStore,
  });

  final QuoteController controller;
  final KanbanBoard board;
  final QuoteVariantDraft variant;
  final Set<String> expandedCategories;
  final Set<String> expandedSections;
  final ValueChanged<String> onToggleCategory;
  final ValueChanged<String> onToggleSection;
  final VoidCallback onAddCategory;
  final ValueChanged<QuoteCategoryDraft> onAddSection;
  final void Function(QuoteCategoryDraft, QuoteSectionDraft) onAddPosition;
  final _ColumnWidthStore columnWidthStore;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (variant.categories.isEmpty)
        _EmptyVariant(onAddCategory: onAddCategory)
      else
        for (final category in variant.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CategoryBlock(
              controller: controller,
              board: board,
              category: category,
              expanded: expandedCategories.contains(category.id),
              expandedSections: expandedSections,
              onToggle: () => onToggleCategory(category.id),
              onToggleSection: onToggleSection,
              onAddSection: () => onAddSection(category),
              onAddPosition: (section) => onAddPosition(category, section),
              columnWidthStore: columnWidthStore,
            ),
          ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onAddCategory,
          icon: const Icon(Icons.add),
          label: const Text('Добавить категорию'),
        ),
      ),
    ],
  );
}

final class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.controller,
    required this.board,
    required this.category,
    required this.expanded,
    required this.expandedSections,
    required this.onToggle,
    required this.onToggleSection,
    required this.onAddSection,
    required this.onAddPosition,
    required this.columnWidthStore,
  });

  final QuoteController controller;
  final KanbanBoard board;
  final QuoteCategoryDraft category;
  final bool expanded;
  final Set<String> expandedSections;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleSection;
  final VoidCallback onAddSection;
  final ValueChanged<QuoteSectionDraft> onAddPosition;
  final _ColumnWidthStore columnWidthStore;

  @override
  Widget build(BuildContext context) {
    final fields = _positionFields(board, controller, category);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                  const Icon(Icons.folder_outlined, size: 18, color: _accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Добавить раздел',
                          onPressed: onAddSection,
                          icon: const Icon(Icons.create_new_folder_outlined),
                        ),
                        const SizedBox(width: 8),
                        _MoneyLabel('Закупка', category.purchaseTotal),
                        const SizedBox(width: 16),
                        _MoneyLabel('Розница', category.clientTotal),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Удалить категорию',
                          color: const Color(0xFFFF7676),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: controller.saving
                              ? null
                              : () => _confirmTabRemoval(
                                  context,
                                  title:
                                      'Удалить категорию «${category.name}»?',
                                  content:
                                      'Категория и все её разделы с позициями будут удалены из этого варианта. Связанные автоматические позиции будут пересчитаны. Каталог товаров не изменится.',
                                  onConfirmed: () =>
                                      controller.removeCategory(category),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            if (category.sections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: onAddSection,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить раздел'),
                ),
              )
            else
              for (final section in category.sections)
                _SectionBlock(
                  controller: controller,
                  section: section,
                  fields: fields,
                  expanded: expandedSections.contains(section.id),
                  onToggle: () => onToggleSection(section.id),
                  onAddPosition: () => onAddPosition(section),
                  widthScope: category.catalogCategoryId ?? category.id,
                  columnWidthStore: columnWidthStore,
                ),
          ],
        ],
      ),
    );
  }
}

final class _SectionBlock extends StatefulWidget {
  const _SectionBlock({
    required this.controller,
    required this.section,
    required this.fields,
    required this.expanded,
    required this.onToggle,
    required this.onAddPosition,
    required this.widthScope,
    required this.columnWidthStore,
  });

  final QuoteController controller;
  final QuoteSectionDraft section;
  final List<KanbanField> fields;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAddPosition;
  final String widthScope;
  final _ColumnWidthStore columnWidthStore;

  @override
  State<_SectionBlock> createState() => _SectionBlockState();
}

final class _SectionBlockState extends State<_SectionBlock> {
  final ScrollController horizontalScrollController = ScrollController();

  @override
  void dispose() {
    horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const fixedColumnsWidth = 38.0 + 34.0 + 36.0;
    final controller = widget.controller;
    final section = widget.section;
    final fields = widget.fields;
    final expanded = widget.expanded;
    final onToggle = widget.onToggle;
    final onAddPosition = widget.onAddPosition;
    final widthScope = widget.widthScope;
    final columnWidthStore = widget.columnWidthStore;
    return Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFF132334)),
          child: _SectionHeader(
            controller: controller,
            fields: fields,
            section: section,
            expanded: expanded,
            onToggle: onToggle,
            onAddPosition: onAddPosition,
          ),
        ),
        if (expanded)
          Listener(
            onPointerMove: (event) {
              if (event.down) columnWidthStore.updateResize(event.delta.dx);
            },
            onPointerUp: (_) => columnWidthStore.endResize(),
            onPointerCancel: (_) => columnWidthStore.endResize(),
            child: AnimatedBuilder(
              animation: columnWidthStore,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final preferredFieldWidths = [
                    for (final field in fields)
                      columnWidthStore.widthFor(
                        widthScope,
                        field.code,
                        _fieldWidth(field),
                      ),
                  ];
                  final preferredFieldsWidth = preferredFieldWidths
                      .fold<double>(0, (total, width) => total + width);
                  final preferredTableWidth =
                      fixedColumnsWidth + preferredFieldsWidth;
                  final tableWidth = preferredTableWidth > constraints.maxWidth
                      ? preferredTableWidth
                      : constraints.maxWidth;
                  final stretchedFieldsWidth = tableWidth - fixedColumnsWidth;
                  final availableFieldsWidth =
                      preferredFieldsWidth > stretchedFieldsWidth
                      ? preferredFieldsWidth
                      : stretchedFieldsWidth;
                  final widthScale =
                      preferredFieldsWidth > 0 &&
                          !columnWidthStore.hasCustomWidths(widthScope)
                      ? availableFieldsWidth / preferredFieldsWidth
                      : 1.0;
                  final fieldWidths = [
                    for (final width in preferredFieldWidths)
                      width * widthScale,
                  ];

                  final overflows = tableWidth > constraints.maxWidth + 0.5;
                  return Scrollbar(
                    key: ValueKey('quote-section-scrollbar-${section.id}'),
                    controller: horizontalScrollController,
                    thumbVisibility: overflows,
                    trackVisibility: overflows,
                    interactive: true,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    thickness: 7,
                    radius: const Radius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: overflows ? 12 : 0),
                      child: SingleChildScrollView(
                        controller: horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Column(
                            children: [
                              _SectionColumnHeader(
                                fields: fields,
                                fieldWidths: fieldWidths,
                                selectedCount: section.positions
                                    .where((position) => position.selected)
                                    .length,
                                positionCount: section.positions.length,
                                onSelectionChanged: (selected) => controller
                                    .setSectionSelection(section, selected),
                                onResizeStart: (fieldIndex) =>
                                    columnWidthStore.beginResize(
                                      scope: widthScope,
                                      fields: fields,
                                      currentWidths: fieldWidths,
                                      fieldIndex: fieldIndex,
                                    ),
                              ),
                              if (section.positions.isEmpty)
                                InkWell(
                                  onTap: onAddPosition,
                                  child: const SizedBox(
                                    height: 56,
                                    child: Center(
                                      child: Text(
                                        'В разделе нет позиций. Добавить из каталога',
                                        style: TextStyle(color: _muted),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: section.positions.length,
                                  onReorder: (oldIndex, newIndex) =>
                                      controller.reorderPosition(
                                        section,
                                        oldIndex,
                                        newIndex,
                                      ),
                                  itemBuilder: (context, index) => _PositionRow(
                                    key: ValueKey(section.positions[index].id),
                                    controller: controller,
                                    section: section,
                                    position: section.positions[index],
                                    fields: fields,
                                    fieldWidths: fieldWidths,
                                    index: index,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Адаптивная шапка раздела. Заголовки колонок намеренно находятся ниже,
/// внутри раскрытого раздела, а не над всей категорией.
final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.controller,
    required this.fields,
    required this.section,
    required this.expanded,
    required this.onToggle,
    required this.onAddPosition,
  });

  final QuoteController controller;
  final List<KanbanField> fields;
  final QuoteSectionDraft section;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAddPosition;

  KanbanField? _percentField(bool markup) {
    final code = markup ? 'markup_value' : 'discount_value';
    final label = markup ? 'наценка' : 'скидка';
    return fields.where((field) => field.code == code).firstOrNull ??
        fields
            .where(
              (field) =>
                  const {'percent', 'number'}.contains(field.fieldType) &&
                  field.label.trim().toLowerCase() == label,
            )
            .firstOrNull;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final markupField = _percentField(true);
      final discountField = _percentField(false);
      final title = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onToggle,
            icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
          ),
          const Icon(Icons.folder_open_outlined, size: 17),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              section.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Добавить позицию',
            onPressed: onAddPosition,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (section.positions.any((position) => position.selected)) ...[
            OutlinedButton.icon(
              onPressed: () => controller.removeSelectedPositions(section),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(
                'Удалить выбранные (${section.positions.where((position) => position.selected).length})',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF7676),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (markupField != null) ...[
            _PercentAction(
              label: 'Наценка',
              initialValue: section.markupPercent,
              onApply: (value) => controller.applyPercent(
                section,
                value: value,
                markup: true,
                fieldCode: markupField.code,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (discountField != null) ...[
            _PercentAction(
              label: 'Скидка',
              initialValue: section.discountPercent,
              onApply: (value) => controller.applyPercent(
                section,
                value: value,
                markup: false,
                fieldCode: discountField.code,
              ),
            ),
            const SizedBox(width: 10),
          ],
          _MoneyLabel('Итого', section.clientTotal),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Удалить раздел',
            color: const Color(0xFFFF7676),
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: controller.saving
                ? null
                : () => _confirmTabRemoval(
                    context,
                    title: 'Удалить раздел «${section.name}»?',
                    content:
                        'Раздел и все его позиции будут удалены из этого варианта. Связанные автоматические позиции будут пересчитаны. Каталог товаров не изменится.',
                    onConfirmed: () => controller.removeSection(section),
                  ),
          ),
        ],
      );
      if (constraints.maxWidth >= 760) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              Flexible(child: title),
              const SizedBox(width: 8),
              actions,
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: actions,
            ),
          ],
        ),
      );
    },
  );
}

final class _SectionColumnHeader extends StatelessWidget {
  const _SectionColumnHeader({
    required this.fields,
    required this.fieldWidths,
    required this.selectedCount,
    required this.positionCount,
    required this.onSelectionChanged,
    required this.onResizeStart,
  });

  final List<KanbanField> fields;
  final List<double> fieldWidths;
  final int selectedCount;
  final int positionCount;
  final ValueChanged<bool> onSelectionChanged;
  final ValueChanged<int> onResizeStart;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    decoration: const BoxDecoration(
      color: Color(0xFF1A2B3E),
      border: Border(
        top: BorderSide(color: Color(0xFF3B5D80)),
        bottom: BorderSide(color: Color(0xFF3B5D80)),
      ),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 38,
          child: Checkbox(
            tristate: true,
            value: selectedCount == 0
                ? false
                : selectedCount == positionCount
                ? true
                : null,
            onChanged: positionCount == 0
                ? null
                : (value) => onSelectionChanged(value == true),
          ),
        ),
        const SizedBox(width: 34),
        for (final (index, field) in fields.indexed)
          _HeaderCell(
            field.label.toUpperCase(),
            fieldWidths[index],
            fieldCode: field.code,
            onResizeStart: () => onResizeStart(index),
          ),
        const SizedBox(width: 36),
      ],
    ),
  );
}

final class _HeaderCell extends StatelessWidget {
  const _HeaderCell(
    this.label,
    this.width, {
    required this.fieldCode,
    required this.onResizeStart,
  });
  final String label;
  final double width;
  final String fieldCode;
  final VoidCallback onResizeStart;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('quote-column-$fieldCode'),
    width: width,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA9BEDA),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .25,
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: 10,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: Listener(
              key: ValueKey('quote-column-resize-$fieldCode'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => onResizeStart(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (_) {},
                child: const Center(
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0xFF45617F),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Сохраняет пользовательские ширины колонок между открытиями редактора.
/// КП и ПКП используют один экземпляр механизма, а значения синхронизируются
/// между всеми разделами одной категории без перестроения остальной страницы.
final class _ColumnWidthStore extends ChangeNotifier {
  _ColumnWidthStore({required this.storageKey}) {
    unawaited(_restore());
  }

  static const double _minimumWidth = 64;
  static const double _maximumWidth = 480;

  final String storageKey;
  final Map<String, Map<String, double>> _widths = {};
  _ColumnResizeSession? _activeResize;
  bool _changedLocally = false;
  bool _disposed = false;

  double widthFor(String scope, String fieldCode, double fallback) =>
      _widths[scope]?[fieldCode] ?? fallback;

  bool hasCustomWidths(String scope) => _widths[scope]?.isNotEmpty == true;

  void beginResize({
    required String scope,
    required List<KanbanField> fields,
    required List<double> currentWidths,
    required int fieldIndex,
  }) {
    if (fieldIndex < 0 || fieldIndex >= fields.length) return;
    _activeResize = _ColumnResizeSession(
      scope: scope,
      fields: fields,
      widths: currentWidths.toList(growable: false),
      fieldIndex: fieldIndex,
    );
  }

  void updateResize(double delta) {
    final session = _activeResize;
    if (session == null || delta == 0) return;

    final next = session.widths.toList(growable: false);
    final resizedWidth = (next[session.fieldIndex] + delta).clamp(
      _minimumWidth,
      _maximumWidth,
    );
    final appliedDelta = resizedWidth - next[session.fieldIndex];
    if (appliedDelta == 0) return;
    next[session.fieldIndex] = resizedWidth;

    session.widths = next;
    _widths[session.scope] = {
      for (final (index, field) in session.fields.indexed)
        field.code: next[index],
    };
    _changedLocally = true;
    notifyListeners();
  }

  void endResize() {
    if (_activeResize == null) return;
    _activeResize = null;
    unawaited(_ColumnWidthPersistence.write(storageKey, _widths));
  }

  Future<void> _restore() async {
    final restored = await _ColumnWidthPersistence.read(storageKey);
    if (_disposed || _changedLocally || restored.isEmpty) return;
    _widths
      ..clear()
      ..addAll(restored);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _ColumnWidthPersistence {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final Map<String, Map<String, Map<String, double>>> _memory = {};

  static Future<Map<String, Map<String, double>>> read(String key) async {
    final cached = _memory[key];
    if (cached != null) return _copy(cached);
    try {
      final encoded = await _storage.read(key: key);
      if (encoded == null || encoded.isEmpty) return {};
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return {};
      final result = <String, Map<String, double>>{};
      for (final entry in decoded.entries) {
        final fields = entry.value;
        if (fields is! Map<String, dynamic>) continue;
        result[entry.key] = {
          for (final field in fields.entries)
            if (field.value is num) field.key: (field.value as num).toDouble(),
        };
      }
      _memory[key] = _copy(result);
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> write(
    String key,
    Map<String, Map<String, double>> widths,
  ) async {
    final snapshot = _copy(widths);
    _memory[key] = snapshot;
    try {
      await _storage.write(key: key, value: jsonEncode(snapshot));
    } catch (_) {
      // In-memory persistence still preserves widths during this app session.
    }
  }

  static Map<String, Map<String, double>> _copy(
    Map<String, Map<String, double>> source,
  ) => {
    for (final entry in source.entries)
      entry.key: Map<String, double>.from(entry.value),
  };
}

String _columnWidthStorageKey(String? accessToken, String boardId) {
  var subject = 'anonymous';
  try {
    final parts = accessToken?.split('.') ?? const <String>[];
    if (parts.length == 3) {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map<String, dynamic> && payload['sub'] is String) {
        subject = payload['sub'] as String;
      }
    }
  } catch (_) {
    // A malformed token must not prevent the editor from opening.
  }
  return 'quote.column_widths.v1.$subject.$boardId';
}

final class _ColumnResizeSession {
  _ColumnResizeSession({
    required this.scope,
    required this.fields,
    required this.widths,
    required this.fieldIndex,
  });

  final String scope;
  final List<KanbanField> fields;
  List<double> widths;
  final int fieldIndex;
}

List<KanbanField> _positionFields(
  KanbanBoard board,
  QuoteController controller,
  QuoteCategoryDraft category,
) {
  final configuredCategory = board.categories
      .where((item) => item.categoryId == category.catalogCategoryId)
      .firstOrNull;
  final fields =
      configuredCategory?.fields.toList() ??
      _legacyPositionFields(controller, category);
  fields.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  return fields;
}

/// Старые предложения могут содержать категорию, которую позднее исключили из
/// текущего канбана. Для таких сохранённых данных оставляем редактируемое
/// представление, но новые категории редактор разрешает брать только из канбана.
List<KanbanField> _legacyPositionFields(
  QuoteController controller,
  QuoteCategoryDraft category,
) {
  final catalogCategory = controller.catalog?.categories
      .where((item) => item.id == category.catalogCategoryId)
      .firstOrNull;
  if (catalogCategory == null) return <KanbanField>[];
  return [
    for (final field in catalogCategory.fields)
      if (field.isVisible)
        KanbanField(
          code: field.code,
          label: field.label,
          fieldType: field.fieldType,
          isRequired: field.isRequired,
          sortOrder: field.sortOrder,
          dictionaryCode: field.dictionaryCode,
          options: _legacyDictionaryOptions(controller, field.dictionaryCode),
        ),
  ];
}

List<KanbanDictionaryOption> _legacyDictionaryOptions(
  QuoteController controller,
  String? dictionaryCode,
) {
  if (dictionaryCode == null) return const [];
  final dictionary = controller.catalog?.dictionaries
      .where((item) => item.code == dictionaryCode)
      .firstOrNull;
  if (dictionary == null) return const [];
  return [
    for (final item in dictionary.items)
      KanbanDictionaryOption(
        id: item.id,
        value: item.value,
        sortOrder: item.sortOrder,
      ),
  ];
}

double _fieldWidth(KanbanField field) => switch (field.code) {
  'name' => 170,
  'marking' => 155,
  'group' || 'supplier' => 135,
  'quantity' => 82,
  'unit' => 105,
  'note' || 'technical_note' => 170,
  'excluded_from_calc' => 92,
  'line_total' => 110,
  _ when field.fieldType == 'boolean' => 92,
  _ when field.fieldType == 'relation' => 180,
  _
      when const {
        'number',
        'money',
        'percent',
        'calculated_money',
      }.contains(field.fieldType) =>
    110,
  _ => 145,
};

final class _PositionFieldCell extends StatelessWidget {
  const _PositionFieldCell({
    required this.controller,
    required this.section,
    required this.position,
    required this.field,
    required this.width,
  });

  final QuoteController controller;
  final QuoteSectionDraft section;
  final QuotePositionDraft position;
  final KanbanField field;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (position.hiddenFieldCodes.contains(field.code)) {
      return SizedBox(width: width);
    }
    switch (field.code) {
      case 'name':
        return _RowInput(
          initialValue: position.name,
          width: width,
          onChanged: (value) {
            position.name = value;
            controller.positionChanged(
              position: position,
              fieldCode: field.code,
            );
          },
        );
      case 'marking':
        return _RowInput(
          initialValue: position.marking,
          width: width,
          onChanged: (value) {
            position.marking = value;
            controller.positionChanged(
              position: position,
              fieldCode: field.code,
            );
          },
        );
      case 'quantity':
        return _RowNumber(
          value: position.quantity,
          width: width,
          minimum: 0,
          minimumExclusive: true,
          onChanged: (value) {
            if (value > 0) position.quantity = value;
            controller.positionChanged(
              position: position,
              fieldCode: field.code,
            );
          },
        );
      case 'unit':
        return _dictionaryCell(
          width: width,
          value: position.unit,
          onChanged: (value) {
            position.unit = value ?? '';
            position.values[field.code] = value;
            controller.positionChanged(
              position: position,
              fieldCode: field.code,
            );
          },
        );
      case 'purchase_price':
        return _numberCell(
          width,
          position.purchasePrice,
          (value) => position.purchasePrice = value,
          field.code,
        );
      case 'markup_value':
        return _numberCell(
          width,
          position.markupPercent,
          (value) => position.markupPercent = value,
          field.code,
        );
      case 'base_price':
        return _RowText(
          _money(position.manualPrice ?? position.basePrice),
          width,
          alignEnd: true,
        );
      case 'discount_value':
        return _numberCell(
          width,
          position.discountPercent,
          (value) => position.discountPercent = value,
          field.code,
        );
      case 'line_total':
        return _RowText(_money(position.lineTotal), width, alignEnd: true);
      case 'excluded_from_calc':
        return SizedBox(
          width: width,
          child: Center(
            child: Checkbox(
              value: position.excludeFromTotals,
              onChanged: (value) {
                position.excludeFromTotals = value == true;
                position.values['_manual_excluded_from_calc'] = value == true;
                controller.positionChanged(
                  position: position,
                  fieldCode: field.code,
                );
              },
            ),
          ),
        );
      case 'group':
        return _dictionaryCell(
          width: width,
          value: _text(position.values[field.code]),
          options: _groupValues(),
          onChanged: (value) {
            position.values[field.code] = value;
            controller.positionChanged(
              position: position,
              fieldCode: field.code,
            );
          },
        );
    }

    if (field.fieldType == 'dictionary') {
      return _dictionaryCell(
        width: width,
        value: _text(position.values[field.code]),
        onChanged: (value) {
          position.values[field.code] = value;
          controller.positionChanged(position: position, fieldCode: field.code);
        },
      );
    }
    if (field.fieldType == 'boolean') {
      return SizedBox(
        width: width,
        child: Center(
          child: Checkbox(
            value: position.values[field.code] == true,
            onChanged: (value) {
              position.values[field.code] = value == true;
              controller.positionChanged(
                position: position,
                fieldCode: field.code,
              );
            },
          ),
        ),
      );
    }
    if (field.fieldType == 'relation') {
      final value = position.values[field.code];
      final label = value is List ? value.join(', ') : _text(value);
      return _RowText(label, width);
    }
    if (field.fieldType == 'calculated_money') {
      return _RowText(
        _money(_asDouble(position.values[field.code]) ?? 0),
        width,
        alignEnd: true,
      );
    }
    if (const {'number', 'money', 'percent'}.contains(field.fieldType)) {
      return _numberCell(
        width,
        _asDouble(position.values[field.code]),
        (value) => position.values[field.code] = value,
        field.code,
      );
    }
    return _RowInput(
      initialValue: _text(position.values[field.code]),
      width: width,
      onChanged: (value) {
        position.values[field.code] = value;
        controller.positionChanged(position: position, fieldCode: field.code);
      },
    );
  }

  Widget _numberCell(
    double width,
    double? value,
    ValueChanged<double> assign,
    String fieldCode,
  ) => _RowNumber(
    value: value ?? 0,
    width: width,
    minimum: field.fieldType == 'money' ? 0 : null,
    onChanged: (next) {
      assign(next);
      controller.positionChanged(position: position, fieldCode: fieldCode);
    },
  );

  Widget _dictionaryCell({
    required double width,
    required String value,
    required ValueChanged<String?> onChanged,
    Iterable<Object?>? options,
  }) {
    final values = (options ?? _dictionaryValues())
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return _RowSelect(
      value: values.contains(value) ? value : null,
      values: values,
      width: width,
      onChanged: onChanged,
    );
  }

  Iterable<Object?> _dictionaryValues() {
    return field.options.map((item) => item.value).toList(growable: false);
  }

  Iterable<Object?> _groupValues() {
    for (final category in controller.catalog?.categories ?? const []) {
      for (final sourceSection in category.sections) {
        if (sourceSection.id == section.catalogSectionId) {
          return sourceSection.groups
              .map((group) => group.name)
              .toList(growable: false);
        }
      }
    }
    return const [];
  }
}

String _text(dynamic value) => value == null ? '' : value.toString();

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value).replaceAll(',', '.'));
}

final class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.controller,
    required this.section,
    required this.position,
    required this.fields,
    required this.fieldWidths,
    required this.index,
    super.key,
  });

  final QuoteController controller;
  final QuoteSectionDraft section;
  final QuotePositionDraft position;
  final List<KanbanField> fields;
  final List<double> fieldWidths;
  final int index;

  @override
  Widget build(BuildContext context) {
    final changedExternally = position.values['changed_externally'] == true;
    final isNew = position.catalogItemId == null;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isNew
            ? const Color(0x1AF5B942)
            : changedExternally
            ? const Color(0x18EF5350)
            : index.isEven
            ? const Color(0xFF101A27)
            : const Color(0xFF0E1722),
        border: Border(
          bottom: const BorderSide(color: Color(0xFF233248)),
          left: changedExternally
              ? const BorderSide(color: Color(0xFFEF5350), width: 2)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Checkbox(
              value: position.selected,
              onChanged: (value) {
                position.selected = value ?? false;
                controller.positionChanged();
              },
            ),
          ),
          SizedBox(
            width: 34,
            child: ReorderableDragStartListener(
              index: index,
              child: const MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Icon(Icons.drag_indicator, size: 18, color: _muted),
              ),
            ),
          ),
          for (final (fieldIndex, field) in fields.indexed)
            _PositionFieldCell(
              controller: controller,
              section: section,
              position: position,
              field: field,
              width: fieldWidths[fieldIndex],
            ),
          SizedBox(
            width: 36,
            child: IconButton(
              tooltip: 'Удалить позицию',
              onPressed: () => controller.removePosition(section, position),
              icon: const Icon(
                Icons.delete_outline,
                size: 17,
                color: Color(0xFFFF6B6B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({
    required this.controller,
    required this.variant,
    this.horizontal = false,
  });
  final QuoteController controller;
  final QuoteVariantDraft variant;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _SummaryCard(
        title: 'Сводка варианта',
        rows: [
          ('Сумма без НДС', variant.systemSummary.subtotal),
          ('Итого закупка', variant.purchaseTotal),
          ('Валовая прибыль', variant.systemSummary.margin),
          ('НДС', variant.systemSummary.vat),
          ('Итого для клиента', variant.systemSummary.total),
        ],
        footer: (
          'Маржинальность',
          '${variant.systemSummary.marginPercent.toStringAsFixed(1)}%',
        ),
      ),
      if (controller.activeType case final type?)
        _SummaryCard(
          title: 'Сводка типа',
          rows: [
            ('Сумма без НДС', type.systemSummary.subtotal),
            ('Итого закупка', type.purchaseTotal),
            ('Валовая прибыль', type.systemSummary.margin),
            ('НДС', type.systemSummary.vat),
            ('Итого для клиента', type.systemSummary.total),
          ],
          footer: (
            'Маржинальность',
            '${type.systemSummary.marginPercent.toStringAsFixed(1)}%',
          ),
        ),
    ];
    if (horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < cards.length; index++) ...[
            if (index > 0) const SizedBox(width: 12),
            Expanded(child: cards[index]),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var index = 0; index < cards.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          cards[index],
        ],
      ],
    );
  }
}

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.rows, this.footer});
  final String title;
  final List<(String, double)> rows;
  final (String, String)? footer;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.$1,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                Text(
                  _money(row.$2),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        if (footer case final value?) ...[
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(value.$1, style: const TextStyle(color: _muted)),
              ),
              Text(
                value.$2,
                style: const TextStyle(
                  color: Color(0xFF55D889),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

final class _PercentAction extends StatefulWidget {
  const _PercentAction({
    required this.label,
    required this.initialValue,
    required this.onApply,
  });
  final String label;
  final double? initialValue;
  final ValueChanged<double> onApply;

  @override
  State<_PercentAction> createState() => _PercentActionState();
}

final class _PercentActionState extends State<_PercentAction> {
  late final TextEditingController input;

  @override
  void initState() {
    super.initState();
    input = TextEditingController();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(widget.label, style: const TextStyle(fontSize: 11, color: _muted)),
      const SizedBox(width: 5),
      SizedBox(
        width: 62,
        child: TextField(
          controller: input,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            isDense: true,
            suffixText: '%',
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
      ),
      const SizedBox(width: 4),
      SizedBox(
        height: 32,
        child: OutlinedButton(
          onPressed: () {
            final value = double.tryParse(input.text.replaceAll(',', '.'));
            if (value == null) return;
            widget.onApply(value);
            input.clear();
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('Применить', style: TextStyle(fontSize: 10)),
        ),
      ),
    ],
  );
}

final class _CatalogPickerDialog extends StatefulWidget {
  const _CatalogPickerDialog({
    required this.controller,
    required this.categoryId,
    required this.sectionId,
  });
  final QuoteController controller;
  final String categoryId;
  final String? sectionId;

  @override
  State<_CatalogPickerDialog> createState() => _CatalogPickerDialogState();
}

final class _CatalogPickerDialogState extends State<_CatalogPickerDialog> {
  final search = TextEditingController();
  Timer? debounce;
  String? groupId;
  bool pending = false;
  List<CatalogGroup> get groups =>
      widget.controller.catalog?.categories
          .where((category) => category.id == widget.categoryId)
          .expand((category) => category.sections)
          .where(
            (section) =>
                widget.sectionId == null || section.id == widget.sectionId,
          )
          .expand((section) => section.groups)
          .toList() ??
      [];

  @override
  void initState() {
    super.initState();
    if (groups.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Добавить позицию из каталога'),
    content: SizedBox(
      width: 640,
      height: 520,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Column(
          children: [
            if (groups.isNotEmpty) ...[
              AppSelectField<String>(
                value: groupId,
                label: 'Группа товаров',
                options: [
                  const AppSelectOption(value: '', label: 'Все группы'),
                  for (final group in groups)
                    AppSelectOption(value: group.id, label: group.name),
                ],
                onChanged: (value) {
                  setState(() => groupId = value);
                  _search();
                },
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: search,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Поиск по наименованию и маркировке',
                suffixIcon: IconButton(
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _search(),
              onChanged: (_) {
                debounce?.cancel();
                setState(() => pending = true);
                debounce = Timer(const Duration(milliseconds: 300), _search);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: groups.isNotEmpty && groupId == null
                  ? const Center(
                      child: Text('Сначала выберите группу товаров.'),
                    )
                  : pending || widget.controller.catalogSearching
                  ? const Center(child: CircularProgressIndicator())
                  : widget.controller.catalogSearchResults.isEmpty
                  ? const Center(child: Text('Подходящие позиции не найдены.'))
                  : ListView.separated(
                      itemCount: widget.controller.catalogSearchResults.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item =
                            widget.controller.catalogSearchResults[index];
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(item.name),
                          subtitle: Text(item.marking),
                          trailing: Text(_money(_catalogPrice(item))),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  );

  void _search() {
    debounce?.cancel();
    if (!mounted) return;
    setState(() => pending = false);
    if (groups.isNotEmpty && groupId == null) return;
    widget.controller.searchCatalog(
      categoryId: widget.categoryId,
      sectionId: widget.sectionId,
      groupId: groupId == '' ? null : groupId,
      search: search.text,
    );
  }
}

final class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Padding(padding: padding, child: child),
  );
}

final class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.onRename,
    required this.onDelete,
    required this.deleteTooltip,
    this.icon,
    this.badge,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onRename;
  final VoidCallback? onDelete;
  final String deleteTooltip;
  final IconData? icon;
  final String? badge;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFF1D4E89) : _surfaceRaised,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onPressed,
      onLongPress: onRename,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: selected ? Colors.white : _muted),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (badge case final value?) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF174D38),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF71E6AD),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 5),
            InkWell(
              onTap: onRename,
              child: const Icon(Icons.edit_outlined, size: 14, color: _muted),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: deleteTooltip,
              icon: const Icon(Icons.delete_outline, size: 16),
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              color: _muted,
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _confirmTabRemoval(
  BuildContext context, {
  required String title,
  required String content,
  required VoidCallback onConfirmed,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        '$content\nИзменения вступят в силу после сохранения предложения.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) onConfirmed();
}

final class _TextField extends StatelessWidget {
  const _TextField({
    required this.initialValue,
    required this.label,
    required this.onChanged,
    this.maxLines = 1,
  });
  final String initialValue;
  final String label;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: initialValue,
    maxLines: maxLines,
    decoration: InputDecoration(labelText: label),
    onChanged: onChanged,
  );
}

final class _RowText extends StatelessWidget {
  const _RowText(this.text, this.width, {this.alignEnd = false});
  final String text;
  final double width;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: const TextStyle(fontSize: 11),
      ),
    ),
  );
}

final class _RowSelect extends StatelessWidget {
  const _RowSelect({
    required this.value,
    required this.values,
    required this.width,
    required this.onChanged,
  });

  final String? value;
  final List<String> values;
  final double width;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: MenuAnchor(
        crossAxisUnconstrained: false,
        alignmentOffset: const Offset(0, 4),
        menuChildren: [
          const SizedBox(height: 2),
          MenuItemButton(
            closeOnActivate: true,
            onPressed: () => onChanged(null),
            child: const Text('Не выбрано'),
          ),
          for (final item in values)
            MenuItemButton(
              closeOnActivate: true,
              onPressed: () => onChanged(item),
              child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        builder: (context, menuController, _) => InkWell(
          onTap: () => menuController.isOpen
              ? menuController.close()
              : menuController.open(),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            height: 34,
            padding: const EdgeInsets.only(left: 7, right: 3),
            decoration: BoxDecoration(
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(7),
              color: const Color(0xFF0D1622),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 17, color: _muted),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _RowInput extends StatefulWidget {
  const _RowInput({
    required this.initialValue,
    required this.width,
    required this.onChanged,
  });
  final String initialValue;
  final double width;
  final ValueChanged<String> onChanged;

  @override
  State<_RowInput> createState() => _RowInputState();
}

final class _RowInputState extends State<_RowInput> {
  late final TextEditingController input = TextEditingController(
    text: widget.initialValue,
  );
  String? lastEnteredValue;

  @override
  void didUpdateWidget(covariant _RowInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue == widget.initialValue) return;
    final enteredNumber = double.tryParse(
      (lastEnteredValue ?? '').replaceAll(',', '.'),
    );
    final nextNumber = double.tryParse(widget.initialValue);
    // Preserve in-progress numeric input (for example "1,") on its own echo.
    if (input.text == lastEnteredValue &&
        (widget.initialValue == lastEnteredValue ||
            (enteredNumber != null && enteredNumber == nextNumber))) {
      return;
    }
    input.value = TextEditingValue(
      text: widget.initialValue,
      selection: TextSelection.collapsed(offset: widget.initialValue.length),
    );
    lastEnteredValue = null;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextFormField(
        controller: input,
        style: const TextStyle(fontSize: 11),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        ),
        onChanged: (value) {
          lastEnteredValue = value;
          widget.onChanged(value);
        },
      ),
    ),
  );
}

final class _RowNumber extends StatelessWidget {
  const _RowNumber({
    required this.value,
    required this.width,
    required this.onChanged,
    this.minimum,
    this.minimumExclusive = false,
  });
  final double value;
  final double width;
  final ValueChanged<double> onChanged;
  final double? minimum;
  final bool minimumExclusive;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: AppNumberField(
        minimum: minimum,
        minimumExclusive: minimumExclusive,
        style: const TextStyle(fontSize: 11),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        ),
        value: value == value.roundToDouble()
            ? value.toInt().toString()
            : value.toString(),
        onChanged: (text) {
          final parsed = double.tryParse(text.replaceAll(',', '.'));
          if (parsed != null &&
              parsed.isFinite &&
              (minimum == null || parsed >= minimum!)) {
            onChanged(parsed);
          }
        },
      ),
    ),
  );
}

final class _MoneyLabel extends StatelessWidget {
  const _MoneyLabel(this.label, this.value);
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 9)),
      Text(
        _money(value),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

final class _EmptyVariant extends StatelessWidget {
  const _EmptyVariant({required this.onAddCategory});
  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 42, color: _muted),
          const SizedBox(height: 12),
          const Text(
            'Вариант пока пуст',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Добавьте первую категорию из настроек организации.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddCategory,
            icon: const Icon(Icons.add),
            label: const Text('Добавить категорию'),
          ),
        ],
      ),
    ),
  );
}

final class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) =>
      AutoDismissNotice(message: message, child: _content(context));

  Widget _content(BuildContext context) => Container(
    width: double.infinity,
    color: error ? const Color(0xFF4A1D29) : const Color(0xFF123B2A),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    child: Row(
      children: [
        Icon(
          error ? Icons.error_outline : Icons.check_circle_outline,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

final class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _background,
    child: Center(
      child: _Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Color(0xFFFF6B81)),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onBack,
              child: const Text('Вернуться в канбан'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _rename(
  BuildContext context,
  String initialValue,
  ValueChanged<String> onSave,
) async {
  final input = TextEditingController(text: initialValue);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Изменить название'),
      content: TextField(controller: input, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, input.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  input.dispose();
  if (value != null && value.isNotEmpty) onSave(value);
}

double _catalogPrice(CatalogItem item) {
  final value = item.values['base_price'];
  if (value is num) return value.toDouble();
  return double.tryParse('$value'.replaceAll(',', '.')) ?? 0;
}

final _moneyFormat = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 2,
);

String _money(double value) => _moneyFormat.format(value);
