import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_api.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/company/company_api.dart';
import 'package:sklad_komforta_app/features/company/company_models.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_api.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Состояние редактора КП/ПКП и все операции над его изменяемым деревом.
///
/// Контроллер не содержит Flutter-виджетов, поэтому расчёты, массовые операции
/// и сериализация проверяются unit-тестами без запуска UI.
final class QuoteController extends ChangeNotifier {
  QuoteController(
    AppConfig config,
    this._auth, {
    QuoteGateway? quoteGateway,
    CatalogGateway? catalogGateway,
    CompanyWorkspaceGateway? companyGateway,
  }) : _quoteGateway = quoteGateway ?? QuoteApi(config),
       _catalogGateway = catalogGateway ?? CatalogApi(config),
       _companyGateway = companyGateway ?? CompanyApi(config),
       _ownsQuoteGateway = quoteGateway == null,
       _ownsCatalogGateway = catalogGateway == null,
       _ownsCompanyGateway = companyGateway == null;

  final AuthController _auth;
  final QuoteGateway _quoteGateway;
  final CatalogGateway _catalogGateway;
  final CompanyWorkspaceGateway _companyGateway;
  final bool _ownsQuoteGateway;
  final bool _ownsCatalogGateway;
  final bool _ownsCompanyGateway;

  QuoteDraft? draft;
  CatalogConfiguration? catalog;
  List<CompanyClientModel> clients = const [];
  List<LegalEntityModel> executors = const [];
  List<EmployeeModel> employees = const [];
  List<CatalogItem> catalogSearchResults = const [];
  String? activeTypeId;
  String? activeVariantId;
  bool loading = false;
  bool saving = false;
  bool catalogSearching = false;
  bool dirty = false;
  String? error;
  String? successMessage;

  QuoteProposalTypeDraft? get activeType {
    final document = draft;
    if (document == null || document.proposalTypes.isEmpty) return null;
    return document.proposalTypes.firstWhere(
      (item) => item.id == activeTypeId,
      orElse: () => document.proposalTypes.first,
    );
  }

  QuoteVariantDraft? get activeVariant {
    final type = activeType;
    if (type == null || type.variants.isEmpty) return null;
    return type.variants.firstWhere(
      (item) => item.id == activeVariantId,
      orElse: () => type.variants.first,
    );
  }

  /// Загружает справочники параллельно с документом. Отсутствие документа для
  /// новой карточки является штатным состоянием, а не ошибкой редактора.
  Future<void> initialize({
    required KanbanBoard board,
    required KanbanCard card,
  }) async {
    if (loading || draft != null) return;
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
      try {
        draft = await _authorized(
          (token) => _quoteGateway.getQuote(token, board.id, card.id),
        );
      } on ApiException catch (exception) {
        if (exception.code != 'quote_not_found') rethrow;
        draft = _newDraft(board, card);
      }
      _repairActiveSelection();
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось открыть КП или ПКП. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  QuoteDraft _newDraft(KanbanBoard board, KanbanCard card) {
    final defaultExecutor = executors.where((item) => item.isDefault);
    final executor = defaultExecutor.isNotEmpty
        ? defaultExecutor.first
        : executors.firstOrNull;
    return QuoteDraft(
      kind: board.specialization == WorkflowSpecialization.quoteAndPrequote
          ? QuoteKind.prequote
          : QuoteKind.quote,
      title: card.title,
      clientId: clients.firstOrNull?.id ?? '',
      executorCompanyId: executor?.id ?? '',
      managerUserId: card.createdBy,
      selectionMode: 'variant',
      proposalTypes: [QuoteProposalTypeDraft.create()],
    );
  }

  void _repairActiveSelection() {
    final document = draft;
    if (document == null || document.proposalTypes.isEmpty) return;
    final type = document.proposalTypes.firstWhere(
      (item) => item.id == activeTypeId,
      orElse: () => document.proposalTypes.first,
    );
    activeTypeId = type.id;
    if (type.variants.isNotEmpty) {
      activeVariantId = type.variants.any((item) => item.id == activeVariantId)
          ? activeVariantId
          : type.variants.first.id;
    }
  }

  void selectType(String id) {
    if (activeTypeId == id) return;
    activeTypeId = id;
    activeVariantId = activeType?.variants.firstOrNull?.id;
    notifyListeners();
  }

  void selectVariant(String id) {
    if (activeVariantId == id) return;
    activeVariantId = id;
    notifyListeners();
  }

  void updateDocument(void Function(QuoteDraft draft) update) {
    final document = draft;
    if (document == null) return;
    update(document);
    _changed();
  }

  QuoteProposalTypeDraft addType() {
    final type = QuoteProposalTypeDraft.create(
      name: 'Тип предложения ${(draft?.proposalTypes.length ?? 0) + 1}',
    );
    draft?.proposalTypes.add(type);
    activeTypeId = type.id;
    activeVariantId = type.variants.first.id;
    _changed();
    return type;
  }

  QuoteVariantDraft addVariant() {
    final type = activeType;
    if (type == null) return QuoteVariantDraft.create();
    final variant = QuoteVariantDraft.create(
      name: 'Вариант ${type.variants.length + 1}',
    );
    type.variants.add(variant);
    activeVariantId = variant.id;
    _changed();
    return variant;
  }

  void addCategory(CatalogCategory source) {
    final variant = activeVariant;
    if (variant == null ||
        variant.categories.any(
          (category) => category.catalogCategoryId == source.id,
        )) {
      return;
    }
    variant.categories.add(
      QuoteCategoryDraft(
        id: newQuoteId(),
        catalogCategoryId: source.id,
        name: source.name,
        sections: [],
      ),
    );
    _changed();
  }

  void addSection(QuoteCategoryDraft category, CatalogSection source) {
    if (category.sections.any(
      (section) => section.catalogSectionId == source.id,
    )) {
      return;
    }
    category.sections.add(
      QuoteSectionDraft(
        id: newQuoteId(),
        catalogSectionId: source.id,
        name: source.name,
        positions: [],
      ),
    );
    _changed();
  }

  /// Загружает каталог только для окна выбора позиции. Основной документ при
  /// этом не перерисовывается и не перечитывается с сервера.
  Future<void> searchCatalog({
    required String categoryId,
    String? sectionId,
    String search = '',
  }) async {
    catalogSearching = true;
    error = null;
    notifyListeners();
    try {
      final page = await _authorized(
        (token) => _catalogGateway.getItems(
          accessToken: token,
          categoryId: categoryId,
          sectionId: sectionId,
          status: 'approved',
          search: search,
          page: 1,
          pageSize: 50,
        ),
      );
      catalogSearchResults = page.items;
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось загрузить позиции каталога.';
    } finally {
      catalogSearching = false;
      notifyListeners();
    }
  }

  void addCatalogPosition(QuoteSectionDraft section, CatalogItem item) {
    section.positions.add(
      QuotePositionDraft(
        id: newQuoteId(),
        catalogItemId: item.id,
        name: item.name,
        marking: item.marking,
        unit: _textValue(item.values['unit']),
        quantity: 1,
        purchasePrice: _numericValue(item.values['purchase_price']),
        basePrice: _numericValue(item.values['base_price']) ?? 0,
        values: Map<String, dynamic>.from(item.values),
      ),
    );
    _changed();
  }

  void removePosition(QuoteSectionDraft section, QuotePositionDraft position) {
    section.positions.remove(position);
    _changed();
  }

  void reorderPosition(QuoteSectionDraft section, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = section.positions.removeAt(oldIndex);
    section.positions.insert(newIndex, item);
    _changed();
  }

  /// Применяет значение к выбранным строкам, а при отсутствии выбора — ко
  /// всему разделу. Это соответствует согласованной логике массовых действий.
  void applyPercent(
    QuoteSectionDraft section, {
    required double value,
    required bool markup,
  }) {
    final selected = section.positions.where((position) => position.selected);
    final targets = selected.isEmpty ? section.positions : selected.toList();
    for (final position in targets) {
      if (markup) {
        position.markupPercent = value;
      } else {
        position.discountPercent = value;
      }
    }
    if (markup) {
      section.markupPercent = value;
    } else {
      section.discountPercent = value;
    }
    _changed();
  }

  void positionChanged() => _changed();

  void _changed() {
    dirty = true;
    successMessage = null;
    notifyListeners();
  }

  Future<bool> save({
    required KanbanBoard board,
    required KanbanCard card,
  }) async {
    final document = draft;
    if (document == null || saving) return false;
    final validation = _validate(document);
    if (validation != null) {
      error = validation;
      notifyListeners();
      return false;
    }
    saving = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      draft = await _authorized(
        (token) => _quoteGateway.saveQuote(token, board.id, card.id, document),
      );
      dirty = false;
      successMessage = 'Изменения сохранены';
      _repairActiveSelection();
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось сохранить КП или ПКП. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  String? _validate(QuoteDraft document) {
    if (document.title.trim().isEmpty) return 'Введите название предложения.';
    if (document.clientId.isEmpty) return 'Выберите заказчика.';
    if (document.executorCompanyId.isEmpty) return 'Выберите исполнителя.';
    if (document.proposalTypes.isEmpty) {
      return 'Добавьте хотя бы один тип предложения.';
    }
    for (final type in document.proposalTypes) {
      if (type.name.trim().isEmpty) return 'Введите название типа предложения.';
      if (type.variants.isEmpty) return 'Добавьте вариант в каждый тип.';
      for (final variant in type.variants) {
        if (variant.name.trim().isEmpty) return 'Введите название варианта.';
      }
    }
    return null;
  }

  Future<T> _authorized<T>(Future<T> Function(String token) request) =>
      _auth.executeAuthorized(request);

  @override
  void dispose() {
    if (_ownsQuoteGateway) _quoteGateway.close();
    if (_ownsCatalogGateway) _catalogGateway.close();
    if (_ownsCompanyGateway && _companyGateway is CompanyApi) {
      _companyGateway.close();
    }
    super.dispose();
  }
}

double? _numericValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value'.replaceAll(',', '.'));
}

String _textValue(dynamic value) => value == null ? '' : '$value';
