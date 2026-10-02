part of 'quote_controller.dart';

/// Значение фильтра для строк без поставщика или статуса отгрузки.
const orderFilterEmptyValue = '';

/// Редактор комплектации.
///
/// Наследует от [QuoteController] всю работу с таблицей позиций: категории,
/// разделы, строку ввода с автопоиском по каталогу, Enter-навигацию и
/// ширины колонок. Документ комплектации показан редактору как предложение
/// из одного типа и одного варианта. Отличия: нет цен и связанных позиций,
/// есть фильтры строк, подсветка дозаказа и PDF-счета.
final class OrderController extends QuoteController {
  OrderController(
    super.config,
    super.auth, {
    OrderGateway? orderGateway,
    super.catalogGateway,
    super.companyGateway,
  }) : _orderGateway = orderGateway ?? OrderApi(config),
       _ownsOrderGateway = orderGateway == null,
       super(quoteGateway: _NoQuoteGateway.instance);

  static const _typeId = 'order-type';
  static const _variantId = 'order-variant';

  final OrderGateway _orderGateway;
  final bool _ownsOrderGateway;

  /// Загруженная или создаваемая комплектация.
  OrderDocument? order;
  KanbanBoard? _board;
  KanbanCard? _card;

  /// Карточка стоит в столбце дозаказа или правее: новые строки будут дозаказом.
  bool reorderActive = false;
  final Set<String> _knownPositionIds = <String>{};

  /// Выбранные значения фильтров; пустое множество — фильтр выключен.
  final Set<String> supplierFilter = <String>{};
  final Set<String> shipmentFilter = <String>{};

  List<OrderInvoice> invoices = const [];
  bool invoicesLoading = false;
  bool invoiceBusy = false;

  @override
  bool get attachesCatalogRelations => false;

  @override
  bool get showsMoney => false;

  @override
  bool get positionFiltersActive =>
      supplierFilter.isNotEmpty || shipmentFilter.isNotEmpty;

  @override
  bool isPositionVisible(QuotePositionDraft position) =>
      _matches(supplierFilter, position.values['supplier']) &&
      _matches(shipmentFilter, position.values['shipment_status']);

  static bool _matches(Set<String> filter, dynamic value) =>
      filter.isEmpty || filter.contains(_filterValue(value));

  static String _filterValue(dynamic value) =>
      value == null ? orderFilterEmptyValue : '$value'.trim();

  @override
  bool isPositionHighlighted(QuotePositionDraft position) =>
      (order?.reorderPositionIds.contains(position.id) ?? false) ||
      (reorderActive &&
          !_knownPositionIds.contains(position.id) &&
          (position.name.trim().isNotEmpty ||
              position.marking.trim().isNotEmpty));

  /// Значения фильтра «Поставщик»: справочник поля и значения в строках.
  List<String> get supplierOptions => _filterOptions('supplier');

  /// Значения фильтра «Статус отгрузки»: справочник канбана и значения в строках.
  List<String> get shipmentOptions => _filterOptions('shipment_status');

  bool get hasSupplierField => _boardHasField('supplier');
  bool get hasShipmentField => _boardHasField('shipment_status');

  bool _boardHasField(String code) =>
      _board?.categories.any(
        (category) => category.fields.any((field) => field.code == code),
      ) ??
      false;

  List<String> _filterOptions(String code) {
    final result = <String>[];
    void add(String value) {
      if (!result.contains(value)) result.add(value);
    }

    for (final category in _board?.categories ?? const <KanbanCategory>[]) {
      for (final field in category.fields.where((item) => item.code == code)) {
        for (final option in field.options) {
          add(option.value);
        }
      }
    }
    var hasEmpty = false;
    for (final category in order?.categories ?? const <QuoteCategoryDraft>[]) {
      for (final section in category.sections) {
        for (final position in section.positions) {
          final value = _filterValue(position.values[code]);
          if (value.isEmpty) {
            hasEmpty = true;
          } else {
            add(value);
          }
        }
      }
    }
    if (hasEmpty) add(orderFilterEmptyValue);
    return result;
  }

  void toggleSupplierFilter(String value) => _toggle(supplierFilter, value);

  void toggleShipmentFilter(String value) => _toggle(shipmentFilter, value);

  void clearFilters() {
    supplierFilter.clear();
    shipmentFilter.clear();
    notifyListeners();
  }

  void _toggle(Set<String> filter, String value) {
    if (!filter.remove(value)) filter.add(value);
    notifyListeners();
  }

  /// Загружает справочники и комплектацию карточки либо готовит новую.
  Future<void> initializeOrder({
    required KanbanBoard board,
    KanbanCard? card,
  }) async {
    if (loading || draft != null) return;
    _board = board;
    _card = card;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final references = await Future.wait([
        _authorized(_catalogGateway.getConfiguration),
        _authorized(_companyGateway.getClients),
        _authorized(_companyGateway.getLegalEntities),
        _authorized(_companyGateway.getEmployees),
      ]);
      catalog = references[0] as CatalogConfiguration;
      clients = references[1] as List<CompanyClientModel>;
      executors = references[2] as List<LegalEntityModel>;
      employees = references[3] as List<EmployeeModel>;
      if (card == null) {
        final defaults = executors.where((item) => item.isDefault);
        order = OrderDocument(
          title: '',
          clientId: clients.firstOrNull?.id ?? '',
          executorCompanyId:
              (defaults.isNotEmpty ? defaults.first : executors.firstOrNull)
                  ?.id ??
              '',
          categories: [],
          canChangeManager: false,
        );
      } else {
        persistedCardId = card.id;
        order = await _authorized(
          (token) => _orderGateway.getOrder(token, board.id, card.id),
        );
        unawaited(loadInvoices());
      }
      reorderActive = _isReorderColumn(board, card?.columnId);
      _applyOrder(order!);
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось открыть комплектацию. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  static bool _isReorderColumn(KanbanBoard board, String? columnId) {
    final start = board.columns.where((column) => column.reorderFrom);
    if (start.isEmpty || columnId == null) return false;
    final current = board.columns.where((column) => column.id == columnId);
    return current.isNotEmpty &&
        current.first.sortOrder >= start.first.sortOrder;
  }

  /// Показывает комплектацию редактору как один тип с одним вариантом.
  void _applyOrder(OrderDocument value) {
    order = value;
    _knownPositionIds
      ..clear()
      ..addAll(
        value.categories.expand(
          (category) => category.sections.expand(
            (section) => section.positions.map((position) => position.id),
          ),
        ),
      );
    draft = QuoteDraft(
      id: value.id,
      cardId: value.cardId,
      kind: QuoteKind.quote,
      title: value.title,
      clientId: value.clientId,
      executorCompanyId: value.executorCompanyId,
      managerUserId: value.managerUserId,
      salesHeadUserId: value.salesHeadUserId,
      selectionMode: 'variant',
      canChangeManager: value.canChangeManager,
      proposalTypes: [
        QuoteProposalTypeDraft(
          id: _typeId,
          name: 'Комплектация',
          variants: [
            QuoteVariantDraft(
              id: _variantId,
              name: 'Комплектация',
              categories: value.categories,
            ),
          ],
        ),
      ],
    );
    activeTypeId = _typeId;
    activeVariantId = _variantId;
  }

  /// Восстанавливает локальный черновик поверх загруженной комплектации.
  void restoreDraft(OrderDocument value) {
    _applyOrder(value);
    dirty = true;
    notifyListeners();
  }

  /// Меняет тип объекта.
  void setObjectType(String? value) {
    order?.objectType = value;
    _changed();
  }

  /// Текущее состояние редактора в виде команды сохранения.
  OrderDocument? get snapshot {
    final value = order;
    final document = draft;
    if (value == null || document == null) return null;
    return value
      ..title = document.title
      ..clientId = document.clientId
      ..executorCompanyId = document.executorCompanyId
      ..managerUserId = document.managerUserId
      ..salesHeadUserId = document.salesHeadUserId;
  }

  /// Сохраняет комплектацию; новая создаётся в столбце [creationColumnId].
  Future<bool> saveOrder({String? creationColumnId}) async {
    final board = _board;
    final value = snapshot;
    final document = draft;
    if (board == null || value == null || document == null || saving) {
      return false;
    }
    _removeBlankEntryRows(document);
    for (final position
        in document.proposalTypes.first.variants.first.positions) {
      if (position.quantity <= 0) position.quantity = 1;
    }
    if (value.title.trim().isEmpty) {
      error = 'Укажите адрес объекта.';
      notifyListeners();
      return false;
    }
    if (value.clientId.isEmpty || value.executorCompanyId.isEmpty) {
      error = 'Выберите заказчика и исполнителя.';
      notifyListeners();
      return false;
    }
    saving = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      final cardId = persistedCardId ?? _card?.id;
      final OrderDocument saved;
      if (cardId == null) {
        if (creationColumnId == null) {
          error = 'Не выбран столбец создания комплектации.';
          return false;
        }
        saved = await _authorized(
          (token) => _orderGateway.createOrder(
            token,
            board.id,
            creationColumnId,
            value,
          ),
        );
        persistedCardId = saved.cardId;
      } else {
        saved = await _authorized(
          (token) => _orderGateway.saveOrder(token, board.id, cardId, value),
        );
      }
      _applyOrder(saved);
      dirty = false;
      successMessage = 'Изменения сохранены';
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось сохранить комплектацию. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  /// PDF сохранённой комплектации; `null` — есть несохранённые изменения или ошибка.
  Future<QuotePdfDownload?> downloadOrderPdf() async {
    final board = _board;
    final cardId = persistedCardId ?? _card?.id;
    if (board == null || cardId == null) {
      error = 'Сначала сохраните комплектацию.';
      notifyListeners();
      return null;
    }
    if (dirty) {
      error = 'Сохраните изменения перед печатью.';
      notifyListeners();
      return null;
    }
    printing = true;
    error = null;
    notifyListeners();
    try {
      return await _authorized(
        (token) => _orderGateway.downloadPdf(token, board.id, cardId),
      );
    } on ApiException catch (exception) {
      error = exception.message;
      return null;
    } on Object {
      error = 'Не удалось получить PDF комплектации.';
      return null;
    } finally {
      printing = false;
      notifyListeners();
    }
  }

  Future<void> loadInvoices() async {
    final board = _board;
    final cardId = persistedCardId ?? _card?.id;
    if (board == null || cardId == null) return;
    invoicesLoading = true;
    notifyListeners();
    try {
      invoices = await _authorized(
        (token) => _orderGateway.getInvoices(token, board.id, cardId),
      );
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось загрузить счета.';
    } finally {
      invoicesLoading = false;
      notifyListeners();
    }
  }

  /// Содержимое счёта. Ссылка хранилища живёт несколько минут, поэтому при
  /// ошибке список счетов перечитывается и загрузка повторяется по новой ссылке.
  Future<Uint8List> invoiceBytes(OrderInvoice invoice) async {
    try {
      return await _orderGateway.fetchInvoice(invoice);
    } on Object {
      await loadInvoices();
      final fresh = invoices.where((item) => item.id == invoice.id).firstOrNull;
      if (fresh == null) rethrow;
      return _orderGateway.fetchInvoice(fresh);
    }
  }

  /// Загружает PDF-счёт; только для сохранённой комплектации.
  Future<bool> uploadInvoice(String fileName, Uint8List bytes) async {
    final board = _board;
    final cardId = persistedCardId ?? _card?.id;
    if (board == null || cardId == null || invoiceBusy) return false;
    invoiceBusy = true;
    error = null;
    notifyListeners();
    try {
      final invoice = await _authorized(
        (token) => _orderGateway.uploadInvoice(
          token,
          board.id,
          cardId,
          fileName: fileName,
          bytes: bytes,
        ),
      );
      invoices = [...invoices, invoice];
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось загрузить счёт.';
      return false;
    } finally {
      invoiceBusy = false;
      notifyListeners();
    }
  }

  Future<bool> deleteInvoice(OrderInvoice invoice) async {
    final board = _board;
    final cardId = persistedCardId ?? _card?.id;
    if (board == null || cardId == null || invoiceBusy) return false;
    invoiceBusy = true;
    error = null;
    notifyListeners();
    try {
      await _authorized(
        (token) =>
            _orderGateway.deleteInvoice(token, board.id, cardId, invoice.id),
      );
      invoices = invoices.where((item) => item.id != invoice.id).toList();
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось удалить счёт.';
      return false;
    } finally {
      invoiceBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_ownsOrderGateway) _orderGateway.close();
    super.dispose();
  }
}

/// Комплектации шлюз КП не нужен: базовый контроллер получает заглушку и не
/// создаёт лишний HTTP-клиент.
final class _NoQuoteGateway implements QuoteGateway {
  const _NoQuoteGateway();

  static const instance = _NoQuoteGateway();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Комплектация не использует API КП: ${invocation.memberName}.',
  );

  @override
  void close() {}
}
