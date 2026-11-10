part of 'quote_editor_page.dart';

final class _OrderCalculationBanner extends StatelessWidget {
  const _OrderCalculationBanner({
    required this.busy,
    required this.hasLocalChanges,
    required this.onPreview,
    required this.onDiscard,
  });

  final bool busy;
  final bool hasLocalChanges;
  final VoidCallback onPreview;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFF3CD),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Расчётные правила изменились. Сохранённые значения комплектации показаны без изменений.',
          ),
          FilledButton.icon(
            onPressed: busy || hasLocalChanges ? null : onPreview,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Посмотреть новый расчёт'),
          ),
          if (hasLocalChanges)
            TextButton(
              onPressed: busy ? null : onDiscard,
              child: const Text('Отменить локальные изменения'),
            ),
        ],
      ),
    ),
  );
}

/// Полноэкранный редактор комплектации карточки канбана.
///
/// Таблица позиций общая с редактором КП ([_VariantContent]): категории,
/// разделы, строка ввода с автопоиском по каталогу и ширины колонок. Сверху —
/// шапка (адрес, тип объекта, стороны, менеджер и РОП), фильтры по поставщику
/// и статусу отгрузки и PDF-счета.
final class OrderEditorPage extends StatefulWidget {
  const OrderEditorPage({
    required this.config,
    required this.authController,
    required this.board,
    this.card,
    this.creationColumnId,
    required this.onBack,
    this.onOpenDocumentSettings,
    this.controller,
    this.pdfViewerBuilder,
    this.outboundGatewayFactory,
    this.backRequest = 0,
    super.key,
  });

  /// Транспорт внешней отправки; в тестах — память.
  final OutboundGatewayFactory? outboundGatewayFactory;

  final AppConfig config;
  final AuthController authController;
  final KanbanBoard board;
  final KanbanCard? card;
  final String? creationColumnId;
  final VoidCallback onBack;
  final Future<void> Function()? onOpenDocumentSettings;

  /// Изменение счётчика вызывает тот же выход, что и кнопка «Назад».
  final int backRequest;
  final OrderController? controller;

  /// Область просмотра PDF-счёта; тесты подменяют её, чтобы обойтись без
  /// PDFium. По умолчанию — [defaultPdfViewerBuilder].
  final PdfViewerBuilder? pdfViewerBuilder;

  @override
  State<OrderEditorPage> createState() => _OrderEditorPageState();
}

final class _OrderEditorPageState extends State<OrderEditorPage> {
  @override
  void didUpdateWidget(covariant OrderEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backRequest != widget.backRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_requestBack());
      });
    }
  }

  late final OrderController controller;
  late final bool ownsController;
  final Set<String> expandedCategories = <String>{};
  final Set<String> expandedSections = <String>{};
  bool expansionInitialized = false;
  bool invoicesExpanded = true;

  /// Счета, отмеченные для совместного просмотра.
  final Set<String> selectedInvoices = <String>{};
  late final _ColumnWidthStore columnWidthStore;
  OrderLocalDraft? localDraft;
  bool draftReady = false;
  bool hadLocalChanges = false;
  Timer? _draftWriteTimer;

  String get _storagePrefix => _columnWidthStorageKey(
    widget.authController.accessToken,
    widget.board.id,
  );

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller =
        widget.controller ??
        OrderController(widget.config, widget.authController);
    columnWidthStore = _ColumnWidthStore(storageKey: _storagePrefix);
    if (ownsController) {
      localDraft = OrderLocalDraft(
        '$_storagePrefix.order-draft.'
        '${widget.card?.id ?? 'new.${widget.creationColumnId}'}',
      );
    }
    _initializeEditor();
    _loadOutbound();
  }

  /// Способы внешней отправки для кнопки «Отправить».
  OutboundChannels outboundChannels = OutboundChannels.none;
  bool sending = false;

  Future<void> _loadOutbound() async {
    final channels = await loadOutboundChannels(
      widget.authController,
      gatewayFactory: widget.outboundGatewayFactory,
    );
    if (mounted) setState(() => outboundChannels = channels);
  }

  /// Отправляет PDF комплектации — тот же, что при печати.
  Future<void> _sendDocument(OutboundChannel channel) async {
    if (!await _requireDocumentLayout()) return;
    if (!mounted) return;
    if (sending || controller.saving) return;
    if (controller.dirty || controller.persistedCardId == null) {
      if (!await _confirmSaveAndSend(context)) return;
      final saved = await controller.saveOrder(
        creationColumnId: widget.creationColumnId,
      );
      if (!saved || !mounted) return;
    }
    final cardId = controller.persistedCardId;
    if (cardId == null) return;
    setState(() => sending = true);
    try {
      await sendCardDocument(
        context,
        auth: widget.authController,
        boardId: widget.board.id,
        cardId: cardId,
        channel: channel,
        gatewayFactory: widget.outboundGatewayFactory,
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _initializeEditor() async {
    await controller.initializeOrder(board: widget.board, card: widget.card);
    if (!mounted) return;
    try {
      final restored = await localDraft?.read();
      if (!mounted) return;
      if (restored != null && controller.order != null) {
        final saved = controller.order!;
        restored
          ..calculationVersion = saved.calculationVersion
          ..currentCalculationVersion = saved.currentCalculationVersion
          ..updatedAt = saved.updatedAt;
        controller.restoreDraft(restored);
        controller.showDraftRestoredMessage();
        hadLocalChanges = true;
      }
    } on Object {
      controller.error = 'Не удалось прочитать локальный черновик.';
    }
    if (!mounted) return;
    controller.addListener(_persistLocalDraft);
    controller.draftChanges.addListener(_persistLocalDraft);
    setState(() => draftReady = true);
  }

  void _persistLocalDraft() {
    final store = localDraft;
    if (store == null || controller.order == null) return;
    if (controller.dirty) {
      hadLocalChanges = true;
      _draftWriteTimer?.cancel();
      _draftWriteTimer = Timer(const Duration(milliseconds: 500), () {
        _draftWriteTimer = null;
        if (controller.dirty) unawaited(_writeLocalDraft());
      });
    } else if (hadLocalChanges) {
      hadLocalChanges = false;
      _draftWriteTimer?.cancel();
      _draftWriteTimer = null;
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
        final key = '$_storagePrefix.order-draft.$cardId';
        if (store.key != key) localDraft = OrderLocalDraft(key);
      }
    }
  }

  Future<bool> _writeLocalDraft() async {
    _draftWriteTimer?.cancel();
    _draftWriteTimer = null;
    try {
      final order = controller.snapshot;
      if (order != null) await localDraft?.write(order);
      return true;
    } on Object {
      if (mounted && controller.dirty) {
        setState(
          () => controller.error =
              'Не удалось сохранить локальный черновик. Не закрывайте редактор.',
        );
      }
      return false;
    }
  }

  Future<void> _showOrderCalculationPreview() async {
    final preview = await controller.previewOrderCalculation();
    if (preview == null || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Пересчёт комплектации'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Пересчёт учитывает текущий черновик. После применения результата нажмите «Сохранить», чтобы записать изменения на сервер.',
                ),
                const SizedBox(height: 12),
                Text('Изменится позиций: ${preview.changedPositions}'),
                const SizedBox(height: 12),
                if (preview.changes.isEmpty)
                  const Text(
                    'Значения полей не изменятся. Новая версия правил будет применена к черновику.',
                  ),
                for (final change in preview.changes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${change.positionName} · ${change.fieldCode}: '
                      '${change.savedValue ?? '—'} → ${change.newValue ?? '—'}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Применить к черновику'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) {
      await controller.applyOrderCalculation(preview);
    }
  }

  Future<void> _discardOrderLocalChanges() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отменить локальные изменения?'),
        content: const Text('Несохранённые изменения будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Отменить изменения'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) await controller.discardOrderChanges();
  }

  @override
  void dispose() {
    _draftWriteTimer?.cancel();
    controller.removeListener(_persistLocalDraft);
    controller.draftChanges.removeListener(_persistLocalDraft);
    columnWidthStore.dispose();
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
      final variant = controller.activeVariant;
      if (controller.draft == null || variant == null) {
        return _LoadFailure(
          message: controller.error ?? 'Комплектация не загружена.',
          onBack: widget.onBack,
        );
      }
      if (!expansionInitialized) {
        expansionInitialized = true;
        expandedCategories.addAll(variant.categories.map((item) => item.id));
        expandedSections.addAll(
          variant.categories.expand(
            (category) => category.sections.map((section) => section.id),
          ),
        );
      }
      return ColoredBox(
        color: _background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            return Column(
              children: [
                _OrderCommandBar(
                  controller: controller,
                  card: widget.card,
                  compact: compact,
                  onBack: _requestBack,
                  onPreview: _openPreview,
                  onPrint: _printPdf,
                  sendButton: OutboundSendButton(
                    channels: outboundChannels,
                    compact: constraints.maxWidth < 1100,
                    menuItem: constraints.maxWidth < 600,
                    busy: sending,
                    onSend: _sendDocument,
                  ),
                  onSave: () => controller.saveOrder(
                    creationColumnId: widget.creationColumnId,
                  ),
                ),
                if (controller.error case final message?)
                  _MessageBanner(message: message, error: true),
                if (controller.successMessage case final message?)
                  _MessageBanner(message: message),
                if (controller.needsRecalculation)
                  _OrderCalculationBanner(
                    busy: controller.calculationBusy,
                    hasLocalChanges: controller.dirty,
                    onPreview: _showOrderCalculationPreview,
                    onDiscard: _discardOrderLocalChanges,
                  ),
                Expanded(
                  child: AbsorbPointer(
                    absorbing: controller.needsRecalculation,
                    child: _usesLazyStructure(variant)
                        ? _lazyBody(compact: compact, variant: variant)
                        : ListView(
                            key: const Key('order-page-scroll'),
                            padding: EdgeInsets.fromLTRB(
                              compact ? 12 : 18,
                              12,
                              compact ? 12 : 14,
                              24,
                            ),
                            children: [
                              _OrderMetadataPanel(
                                controller: controller,
                                board: widget.board,
                              ),
                              const SizedBox(height: 12),
                              ...[
                                _OrderInvoicesPanel(
                                  controller: controller,
                                  expanded: invoicesExpanded,
                                  onToggle: () => setState(
                                    () => invoicesExpanded = !invoicesExpanded,
                                  ),
                                  onUpload: _uploadInvoice,
                                  selected: selectedInvoices,
                                  onToggleSelected: (invoice) => setState(
                                    () => selectedInvoices.remove(invoice.id)
                                        ? null
                                        : selectedInvoices.add(invoice.id),
                                  ),
                                  onView: _viewInvoices,
                                  onDownload: _downloadInvoice,
                                  onDelete: _deleteInvoice,
                                ),
                                const SizedBox(height: 12),
                              ],
                              ...[
                                _OrderFiltersBar(controller: controller),
                                const SizedBox(height: 10),
                              ],
                              _VariantContent(
                                controller: controller,
                                board: widget.board,
                                variant: variant,
                                expandedCategories: expandedCategories,
                                expandedSections: expandedSections,
                                onToggleCategory: (id) => setState(
                                  () => expandedCategories.contains(id)
                                      ? expandedCategories.remove(id)
                                      : expandedCategories.add(id),
                                ),
                                onToggleSection: (id) => setState(
                                  () => expandedSections.contains(id)
                                      ? expandedSections.remove(id)
                                      : expandedSections.add(id),
                                ),
                                onAddCategory: _addCategory,
                                onAddSection: _addSection,
                                onAddPosition: _addPosition,
                                columnWidthStore: columnWidthStore,
                                emptyTitle: 'В комплектации пока нет позиций',
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  Widget _lazyBody({
    required bool compact,
    required QuoteVariantDraft variant,
  }) => CustomScrollView(
    key: const Key('order-page-scroll'),
    slivers: [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 18,
          12,
          compact ? 12 : 14,
          24,
        ),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: _OrderMetadataPanel(
                controller: controller,
                board: widget.board,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: _OrderInvoicesPanel(
                controller: controller,
                expanded: invoicesExpanded,
                onToggle: () =>
                    setState(() => invoicesExpanded = !invoicesExpanded),
                onUpload: _uploadInvoice,
                selected: selectedInvoices,
                onToggleSelected: (invoice) => setState(
                  () => selectedInvoices.remove(invoice.id)
                      ? null
                      : selectedInvoices.add(invoice.id),
                ),
                onView: _viewInvoices,
                onDownload: _downloadInvoice,
                onDelete: _deleteInvoice,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(child: _OrderFiltersBar(controller: controller)),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            ..._variantStructureSlivers(
              controller: controller,
              board: widget.board,
              variant: variant,
              expandedCategories: expandedCategories,
              expandedSections: expandedSections,
              onToggleCategory: (id) => setState(
                () => expandedCategories.contains(id)
                    ? expandedCategories.remove(id)
                    : expandedCategories.add(id),
              ),
              onToggleSection: (id) => setState(
                () => expandedSections.contains(id)
                    ? expandedSections.remove(id)
                    : expandedSections.add(id),
              ),
              onAddCategory: _addCategory,
              onAddSection: _addSection,
              onAddPosition: _addPosition,
              columnWidthStore: columnWidthStore,
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _openPreview() async {
    if (!await _requireDocumentLayout()) return;
    if (!mounted) return;
    final order = controller.snapshot;
    if (order == null) return;
    String? employee(String? id) => controller.employees
        .where((item) => item.userId == id)
        .firstOrNull
        ?.displayName;
    final executor = controller.executors
        .where((item) => item.id == order.executorCompanyId)
        .firstOrNull;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderPreviewPage(
          order: order,
          board: widget.board,
          clientData: controller.clients
              .where((c) => c.id == order.clientId)
              .firstOrNull
              ?.toJson(),
          executorData: executor?.toJson(),
          clientName: controller.clients
              .where((item) => item.id == order.clientId)
              .firstOrNull
              ?.name,
          executorName: executor?.legalName ?? executor?.name,
          managerName: employee(order.managerUserId),
          salesHeadName: employee(order.salesHeadUserId),
          cardNumber: widget.card?.number,
        ),
      ),
    );
  }

  Future<void> _printPdf() async {
    if (!await _requireDocumentLayout()) return;
    if (!mounted) return;
    final file = await controller.downloadOrderPdf();
    if (file == null || !mounted) return;
    await _saveFile(file.fileName, file.bytes);
  }

  Future<bool> _requireDocumentLayout() async {
    if (widget.board.documentTemplate != null) return true;
    await showDocumentLayoutRequiredDialog(
      context,
      documentName: 'PDF комплектации',
      onOpenSettings: widget.onOpenDocumentSettings == null
          ? null
          : () async {
              if (controller.dirty && !await _writeLocalDraft()) return;
              if (!mounted) return;
              await widget.onOpenDocumentSettings!();
            },
    );
    return false;
  }

  Future<void> _saveFile(String fileName, Uint8List bytes) async {
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Сохранить PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(content: Text('Не удалось сохранить файл.')),
      );
    }
  }

  Future<void> _uploadInvoice() async {
    if (controller.persistedCardId == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сохранить комплектацию?'),
          content: const Text(
            'Для загрузки счёта сначала нужно сохранить комплектацию. Заполните адрес объекта, заказчика и исполнителя.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить и продолжить'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (!await controller.saveOrder(
            creationColumnId: widget.creationColumnId,
          ) ||
          !mounted) {
        return;
      }
    }
    if (!(controller.order?.canManageInvoices ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(
          content: Text('Нет права загружать счета комплектации.'),
        ),
      );
      return;
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (!mounted || file == null) return;
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(
          content: Text('Не удалось прочитать выбранный файл.'),
        ),
      );
      return;
    }
    await controller.uploadInvoice(file.name, bytes);
  }

  /// Открывает счета в плавающем окне просмотра без сохранения: несколько —
  /// вкладками; работа с комплектацией при этом не блокируется.
  void _viewInvoices(List<OrderInvoice> invoices, int index) => openPdfViewer(
    context,
    initialIndex: index,
    viewerBuilder: widget.pdfViewerBuilder ?? defaultPdfViewerBuilder,
    documents: [
      for (final invoice in invoices)
        PdfViewerSource(
          id: 'order-invoice-${invoice.id}',
          title: invoice.fileName,
          load: () => controller.invoiceBytes(invoice),
        ),
    ],
  );

  Future<void> _downloadInvoice(OrderInvoice invoice) async {
    try {
      await _saveFile(invoice.fileName, await controller.invoiceBytes(invoice));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const AppSnackBar(
          content: Text('Не удалось скачать счёт. Попробуйте ещё раз.'),
        ),
      );
    }
  }

  Future<void> _deleteInvoice(OrderInvoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить счёт?'),
        content: Text('Файл «${invoice.fileName}» будет удалён.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteInvoice(invoice);
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
      _draftWriteTimer?.cancel();
      _draftWriteTimer = null;
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
    final allowed = widget.board.categories
        .map((item) => item.categoryId)
        .toSet();
    final available = configuration.categories
        .where(
          (candidate) =>
              allowed.contains(candidate.id) &&
              !variant.categories.any(
                (existing) => existing.catalogCategoryId == candidate.id,
              ),
        )
        .toList();
    final selected = await _pick<CatalogCategory>(
      title: 'Добавить категорию',
      values: available,
      label: (item) => item.name,
    );
    if (selected == null) return;
    controller.addCategory(selected);
    setState(
      () => expandedCategories.add(
        variant.categories
            .firstWhere((item) => item.catalogCategoryId == selected.id)
            .id,
      ),
    );
  }

  Future<void> _addSection(QuoteCategoryDraft category) async {
    final source = controller.catalog?.categories
        .where((item) => item.id == category.catalogCategoryId)
        .firstOrNull;
    if (source == null) return;
    final selected = await _pick<CatalogSection>(
      title: 'Добавить раздел',
      values: source.sections
          .where(
            (candidate) => !category.sections.any(
              (existing) => existing.catalogSectionId == candidate.id,
            ),
          )
          .toList(),
      label: (item) => item.name,
    );
    if (selected == null) return;
    controller.addSection(category, selected);
    setState(
      () => expandedSections.add(
        category.sections
            .firstWhere((item) => item.catalogSectionId == selected.id)
            .id,
      ),
    );
  }

  void _addPosition(QuoteCategoryDraft category, QuoteSectionDraft section) {
    setState(() {
      expandedCategories.add(category.id);
      expandedSections.add(section.id);
    });
    controller.addEntryPosition(section);
  }

  Future<T?> _pick<T>({
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
}

final class _OrderCommandBar extends StatelessWidget {
  const _OrderCommandBar({
    required this.controller,
    required this.card,
    required this.compact,
    required this.onBack,
    required this.onPreview,
    required this.onPrint,
    required this.onSave,
    this.sendButton,
  });
  final OrderController controller;
  final KanbanCard? card;
  final bool compact;
  final VoidCallback onBack, onPreview, onPrint, onSave;
  final Widget? sendButton;
  @override
  Widget build(BuildContext context) => DocumentCommandBar(
    title: card == null
        ? 'Новая комплектация'
        : 'Комплектация №${card!.number}',
    shortTitle: card == null ? 'Новая' : '№${card!.number}',
    saving: controller.saving,
    onBack: onBack,
    onSave: onSave,
    commands: [
      DocumentCommand(
        'Создать клиента',
        Icons.person_add_alt_1_outlined,
        controller.saving
            ? null
            : () => _createDocumentClient(context, controller),
      ),
      DocumentCommand('Предпросмотр', Icons.visibility_outlined, onPreview),
      DocumentCommand(
        'Печать',
        Icons.print_outlined,
        controller.printing ? null : onPrint,
      ),
    ],
    extra: sendButton,
  );
}

/// Шапка комплектации: адрес, тип объекта, стороны, менеджер и РОП.
final class _OrderMetadataPanel extends StatelessWidget {
  const _OrderMetadataPanel({required this.controller, required this.board});

  final OrderController controller;
  final KanbanBoard board;

  /// Тип объекта, которого уже нет в справочнике канбана, остаётся в списке,
  /// чтобы значение не терялось при открытии документа.
  String? _legacyObjectType(String? current) =>
      current != null &&
          current.isNotEmpty &&
          !board.objectTypes.contains(current)
      ? current
      : null;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    final order = controller.order!;
    final objectTypes = [
      ...board.objectTypes,
      ?_legacyObjectType(order.objectType),
    ];
    final fields = <Widget>[
      _TextField(
        key: const Key('order-title'),
        initialValue: draft.title,
        label: 'Адрес объекта',
        onChanged: (value) =>
            controller.updateDocument((draft) => draft.title = value),
      ),
      AppSelectField<String>(
        key: const Key('order-object-type'),
        value: order.objectType?.isEmpty ?? true ? null : order.objectType,
        label: 'Тип объекта',
        options: [
          const AppSelectOption<String>(value: null, label: 'Не указан'),
          for (final value in objectTypes)
            AppSelectOption(value: value, label: value),
        ],
        onChanged: controller.setObjectType,
      ),
      _CustomerField(controller: controller),
      PartySearchField(
        value: draft.executorCompanyId.isEmpty ? null : draft.executorCompanyId,
        label: 'Исполнитель',
        options: [
          for (final executor in controller.executors)
            PartySearchOption.executor(executor),
        ],
        onChanged: (value) {
          controller.updateDocument(
            (draft) => draft.executorCompanyId = value ?? '',
          );
        },
      ),
      _EmployeeField(
        key: const Key('order-manager'),
        controller: controller,
        value: draft.managerUserId,
        label: 'Менеджер',
        enabled: draft.canChangeManager,
        onChanged: (value) =>
            controller.updateDocument((draft) => draft.managerUserId = value),
      ),
      _EmployeeField(
        key: const Key('order-sales-head'),
        controller: controller,
        value: draft.salesHeadUserId,
        label: 'РОП',
        enabled: draft.canChangeManager,
        onChanged: (value) =>
            controller.updateDocument((draft) => draft.salesHeadUserId = value),
      ),
    ];
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100
              ? 3
              : constraints.maxWidth >= 640
              ? 2
              : 1;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (order.sourceQuote case final source?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Chip(
                    key: const Key('order-source-quote'),
                    avatar: const Icon(Icons.description_outlined, size: 16),
                    label: Text(
                      'Из КП №${source.cardNumber} · ${source.title}',
                    ),
                  ),
                ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final field in fields)
                    SizedBox(width: width, child: field),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Фильтры строк: несколько значений в каждом, между фильтрами — «и».
final class _OrderFiltersBar extends StatelessWidget {
  const _OrderFiltersBar({required this.controller});

  final OrderController controller;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Icon(Icons.filter_list, size: 18, color: _muted),
      _MultiSelectFilter(
        key: const Key('order-filter-supplier'),
        label: 'Поставщик',
        emptyMessage: controller.hasSupplierField
            ? 'Значений пока нет'
            : 'Не настроено поле фильтрации. Выберите источник в настройках канбана.',
        options: controller.supplierOptions,
        selected: controller.supplierFilter,
        onToggle: controller.toggleSupplierFilter,
      ),
      _MultiSelectFilter(
        key: const Key('order-filter-shipment'),
        label: 'Статус отгрузки',
        options: controller.shipmentOptions,
        selected: controller.shipmentFilter,
        onToggle: controller.toggleShipmentFilter,
      ),
      if (controller.positionFiltersActive)
        TextButton.icon(
          key: const Key('order-filter-reset'),
          onPressed: controller.clearFilters,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Сбросить фильтры'),
        ),
    ],
  );
}

/// Кнопка-выпадашка с галочками. Меню не закрывается после выбора, на кнопке —
/// число выбранных значений.
final class _MultiSelectFilter extends StatelessWidget {
  const _MultiSelectFilter({
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.emptyMessage = 'Значений пока нет',
    super.key,
  });

  final String label;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String emptyMessage;

  static String _title(String value) =>
      value == orderFilterEmptyValue ? 'Не указан' : value;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: [
      if (options.isEmpty) MenuItemButton(child: Text(emptyMessage)),
      for (final option in options)
        CheckboxMenuButton(
          key: ValueKey('$label-$option'),
          value: selected.contains(option),
          closeOnActivate: false,
          onChanged: (_) => onToggle(option),
          child: Text(_title(option)),
        ),
    ],
    builder: (context, menu, _) => OutlinedButton.icon(
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      style: selected.isEmpty
          ? null
          : OutlinedButton.styleFrom(
              side: const BorderSide(color: _accent),
              foregroundColor: _accent,
            ),
      icon: const Icon(Icons.arrow_drop_down, size: 18),
      label: Text(selected.isEmpty ? label : '$label · ${selected.length}'),
    ),
  );
}

/// Счета комплектации: список PDF, загрузка и удаление (по праву).
final class _OrderInvoicesPanel extends StatelessWidget {
  const _OrderInvoicesPanel({
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.onUpload,
    required this.selected,
    required this.onToggleSelected,
    required this.onView,
    required this.onDownload,
    required this.onDelete,
  });

  final OrderController controller;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onUpload;
  final Set<String> selected;
  final ValueChanged<OrderInvoice> onToggleSelected;

  /// Просмотр списка счетов, начиная с указанного индекса.
  final void Function(List<OrderInvoice> invoices, int index) onView;
  final ValueChanged<OrderInvoice> onDownload;
  final ValueChanged<OrderInvoice> onDelete;

  @override
  Widget build(BuildContext context) {
    final canManage =
        controller.persistedCardId == null ||
        (controller.order?.canManageInvoices ?? false);
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm', 'ru');
    final invoices = controller.invoices;
    final chosen = invoices
        .where((invoice) => selected.contains(invoice.id))
        .toList(growable: false);
    final multiple = invoices.length > 1;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CollapseToggle(
                expanded: expanded,
                expandTooltip: 'Развернуть счета',
                collapseTooltip: 'Свернуть счета',
                onPressed: onToggle,
              ),
              const Icon(Icons.receipt_long_outlined, size: 18, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Счета (${controller.invoices.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (controller.invoicesLoading || controller.invoiceBusy)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (multiple) ...[
                OutlinedButton.icon(
                  key: const Key('order-invoice-view-selected'),
                  onPressed: () =>
                      chosen.isEmpty ? onView(invoices, 0) : onView(chosen, 0),
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: Text(
                    chosen.isEmpty
                        ? 'Открыть все'
                        : 'Открыть выбранные (${chosen.length})',
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (canManage)
                OutlinedButton.icon(
                  key: const Key('order-invoice-upload'),
                  onPressed: controller.invoiceBusy || controller.saving
                      ? null
                      : onUpload,
                  icon: const Icon(Icons.upload_file_outlined, size: 17),
                  label: const Text('Загрузить PDF'),
                ),
            ],
          ),
          if (expanded) ...[
            if (controller.invoices.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 4, 8, 12),
                child: Text(
                  'Счетов пока нет.',
                  style: TextStyle(color: _muted),
                ),
              ),
            for (final (index, invoice) in invoices.indexed)
              ListTile(
                key: ValueKey('order-invoice-${invoice.id}'),
                dense: true,
                // Нажатие на строку открывает счёт в окне просмотра.
                onTap: () => onView(invoices, index),
                leading: multiple
                    ? Checkbox(
                        key: ValueKey('order-invoice-select-${invoice.id}'),
                        value: selected.contains(invoice.id),
                        onChanged: (_) => onToggleSelected(invoice),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                title: Text(invoice.fileName),
                subtitle: Text(
                  [
                    '${(invoice.byteSize / 1024).ceil()} КБ',
                    dateFormat.format(invoice.uploadedAt.toLocal()),
                    ?invoice.uploadedByName,
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Открыть',
                      onPressed: () => onView(invoices, index),
                      icon: const Icon(Icons.visibility_outlined),
                    ),
                    IconButton(
                      tooltip: 'Скачать',
                      onPressed: () => onDownload(invoice),
                      icon: const Icon(Icons.download_outlined),
                    ),
                    if (canManage)
                      IconButton(
                        tooltip: 'Удалить счёт',
                        color: const Color(0xFFFF7676),
                        onPressed: controller.invoiceBusy
                            ? null
                            : () => onDelete(invoice),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
