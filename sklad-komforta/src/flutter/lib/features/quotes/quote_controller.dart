import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_api.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';
import 'package:sklad_komforta_app/features/company/company_api.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';
import 'package:sklad_komforta_app/features/onboarding/onboarding_models.dart';
import 'package:sklad_komforta_app/features/orders/order_api.dart';
import 'package:sklad_komforta_app/features/orders/order_models.dart';
import 'package:sklad_komforta_app/features/quotes/quote_api.dart';
import 'package:sklad_komforta_app/features/quotes/quote_configured_calculation.dart';
import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

part 'order_controller.dart';

const _autoRelationSourcesKey = '_auto_relation_sources';

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
  String? activeTypeId;
  String? activeVariantId;
  bool loading = false;
  bool saving = false;
  bool printing = false;
  bool dirty = false;

  /// Строка, в первое поле которой редактор должен перевести фокус. Редактор
  /// сбрасывает значение, как только выполнит запрос.
  String? focusRequestPositionId;

  String? error;
  String? _successMessage;
  Timer? _successMessageTimer;
  String? get successMessage => _successMessage;
  set successMessage(String? value) {
    _successMessageTimer?.cancel();
    _successMessage = value;
    if (value == null) return;
    _successMessageTimer = Timer(const Duration(seconds: 5), () {
      _successMessage = null;
      notifyListeners();
    });
  }

  String? persistedCardId;
  List<double?> availableVatRates = [20];
  String? _calculationError;
  final Map<String, Future<List<CatalogItemRelation>>> _relationRequests = {};
  final Map<String, Future<void>> _behaviorQueues = {};

  double? get initialVatRate => availableVatRates.firstOrNull;

  /// Добавлять ли связанные позиции каталога при выборе карточки. В
  /// комплектации связи не материализуются: её состав задают КП и пользователь.
  bool get attachesCatalogRelations => true;

  /// Показывать ли денежные итоги категорий и разделов (в комплектации цен нет).
  bool get showsMoney => true;

  /// Видна ли строка при текущих фильтрах таблицы (фильтры есть у комплектации).
  bool isPositionVisible(QuotePositionDraft position) => true;

  /// Включены ли фильтры строк: при фильтрации перетаскивание строк отключается.
  bool get positionFiltersActive => false;

  /// Подсвечивать ли строку (в комплектации — дозаказ).
  bool isPositionHighlighted(QuotePositionDraft position) => false;

  void showDraftRestoredMessage() {
    successMessage = 'Восстановлен локальный черновик';
    notifyListeners();
  }

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
    KanbanCard? card,
    QuoteKind? createKind,
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
      final defaultExecutor = executors.where((item) => item.isDefault);
      availableVatRates = _vatRatesOf(
        defaultExecutor.isNotEmpty
            ? defaultExecutor.first
            : executors.firstOrNull,
      );
      if (card == null) {
        draft = _newDraft(board, null, createKind: createKind);
      } else {
        persistedCardId = card.id;
        try {
          draft = await _authorized(
            (token) => _quoteGateway.getQuote(token, board.id, card.id),
          );
        } on ApiException catch (exception) {
          if (exception.code != 'quote_not_found') rethrow;
          draft = _newDraft(board, card, createKind: createKind);
        }
      }
      _synchronizeExecutorVatRates(repairVariants: true);
      _repairActiveSelection();
      _recalculateConfiguredRules();
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось открыть КП или ПКП. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  QuoteDraft _newDraft(
    KanbanBoard board,
    KanbanCard? card, {
    QuoteKind? createKind,
  }) {
    final defaultExecutor = executors.where((item) => item.isDefault);
    final executor = defaultExecutor.isNotEmpty
        ? defaultExecutor.first
        : executors.firstOrNull;
    return QuoteDraft(
      kind:
          createKind ??
          (board.specialization == WorkflowSpecialization.quoteAndPrequote
              ? QuoteKind.prequote
              : QuoteKind.quote),
      title: card?.title ?? '',
      clientId: clients.firstOrNull?.id ?? '',
      executorCompanyId: executor?.id ?? '',
      managerUserId: card?.createdBy,
      selectionMode: 'variant',
      proposalTypes: [
        QuoteProposalTypeDraft.create(initialVatRate: initialVatRate),
      ],
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

  void selectExecutor(String id) {
    final document = draft;
    if (document == null) return;
    document.executorCompanyId = id;
    _synchronizeExecutorVatRates(repairVariants: true);
    _changed();
  }

  void _synchronizeExecutorVatRates({required bool repairVariants}) {
    final document = draft;
    if (document == null) return;
    final executor = executors
        .where((item) => item.id == document.executorCompanyId)
        .firstOrNull;
    availableVatRates = _vatRatesOf(executor);
    if (!repairVariants) return;
    for (final type in document.proposalTypes) {
      for (final variant in type.variants) {
        if (!availableVatRates.contains(variant.vatRate)) {
          variant.vatRate = initialVatRate;
        }
      }
    }
  }

  static List<double?> _vatRatesOf(LegalEntityModel? executor) {
    final rates = executor?.vatRates ?? const <double?>[];
    return rates.isEmpty ? <double?>[20] : List<double?>.from(rates);
  }

  QuoteProposalTypeDraft addType() {
    final type = QuoteProposalTypeDraft.create(
      name: 'Тип предложения ${(draft?.proposalTypes.length ?? 0) + 1}',
      initialVatRate: initialVatRate,
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
      vatRate: initialVatRate,
    );
    type.variants.add(variant);
    activeVariantId = variant.id;
    _changed();
    return variant;
  }

  void removeType(String id) {
    final document = draft;
    if (saving ||
        document == null ||
        document.proposalTypes.length <= 1 ||
        !document.proposalTypes.any((type) => type.id == id)) {
      return;
    }
    document.proposalTypes.removeWhere((type) => type.id == id);
    if (document.clientSelectedProposalTypeId == id) {
      document.clientSelectedProposalTypeId = null;
      document.clientSelectionSubmittedAt = null;
    }
    _repairActiveSelection();
    _changed();
  }

  void removeVariant(String typeId, String variantId) {
    final type = draft?.proposalTypes
        .where((type) => type.id == typeId)
        .firstOrNull;
    if (saving ||
        type == null ||
        type.variants.length <= 1 ||
        !type.variants.any((variant) => variant.id == variantId)) {
      return;
    }
    type.variants.removeWhere((variant) => variant.id == variantId);
    if (type.selectedVariantId == variantId) {
      type.selectedVariantId = null;
      type.selectedByClient = false;
    }
    _repairActiveSelection();
    _changed();
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

  /// Разделы категории каталога, на основе которой создана [category].
  List<CatalogSection> catalogSections(QuoteCategoryDraft category) =>
      catalog?.categories
          .where((item) => item.id == category.catalogCategoryId)
          .firstOrNull
          ?.sections ??
      const [];

  /// Позиции можно добавлять прямо в категорию, пока в ней нет разделов
  /// каталога: либо у категории каталога нет разделов, либо в предложение
  /// ещё не добавлен ни один раздел.
  bool canAddDirectPosition(QuoteCategoryDraft category) =>
      category.sections.every((section) => section.catalogSectionId == null);

  /// Раздел для позиций «прямо в категории»: без ссылки на раздел каталога и
  /// с именем категории, поэтому в печати и по ссылке выводится только
  /// название категории. Создаётся при первой позиции.
  QuoteSectionDraft ensureDirectSection(QuoteCategoryDraft category) {
    final existing = category.sections
        .where((section) => section.catalogSectionId == null)
        .firstOrNull;
    if (existing != null) return existing;
    final section = QuoteSectionDraft(
      id: newQuoteId(),
      name: category.name,
      positions: [],
    );
    category.sections.insert(0, section);
    _changed();
    return section;
  }

  /// Добавляет в раздел пустую строку ввода и просит редактор перевести
  /// фокус в её первое поле.
  QuotePositionDraft addEntryPosition(QuoteSectionDraft section) {
    final position = QuotePositionDraft(
      id: newQuoteId(),
      name: '',
      marking: '',
      unit: '',
      quantity: 1,
      basePrice: 0,
      values: <String, dynamic>{},
    );
    section.positions.add(position);
    focusRequestPositionId = position.id;
    _changed();
    return position;
  }

  /// Группы раздела каталога, соответствующего разделу предложения.
  List<CatalogGroup> catalogGroups(
    QuoteCategoryDraft category,
    QuoteSectionDraft section,
  ) {
    final catalogCategory = catalog?.categories
        .where((item) => item.id == category.catalogCategoryId)
        .firstOrNull;
    final catalogSection = catalogCategory?.sections
        .where((item) => item.id == section.catalogSectionId)
        .firstOrNull;
    return catalogSection?.groups ?? const [];
  }

  /// Карточки каталога для автопоиска строки ввода: утверждённые позиции раздела,
  /// при указанной группе — только этой группы. Сервер ищет [search] в
  /// наименовании и маркировке. Ошибка сети не прерывает ввод: возвращается
  /// пустой список, и строку можно заполнить вручную.
  Future<List<CatalogItem>> lookupCatalogItems({
    required QuoteCategoryDraft category,
    required QuoteSectionDraft section,
    String? groupName,
    String search = '',
  }) async {
    final categoryId = category.catalogCategoryId;
    if (categoryId == null) return const [];
    final normalizedGroup = groupName?.trim().toLowerCase() ?? '';
    final groupId = normalizedGroup.isEmpty
        ? null
        : catalogGroups(category, section)
              .where(
                (group) => group.name.trim().toLowerCase() == normalizedGroup,
              )
              .firstOrNull
              ?.id;
    try {
      final page = await _authorized(
        (token) => _catalogGateway.getItems(
          accessToken: token,
          categoryId: categoryId,
          sectionId: section.catalogSectionId,
          groupId: groupId,
          status: 'approved',
          search: search.trim(),
          page: 1,
          pageSize: 100,
        ),
      );
      return page.items;
    } on Object {
      return const [];
    }
  }

  /// Находит единственную карточку каталога по введённым в строку группе,
  /// наименованию и маркировке (без учёта регистра и крайних пробелов).
  /// Возвращает `null`, если совпадений нет или их несколько.
  Future<CatalogItem?> resolveEntryItem({
    required QuoteCategoryDraft category,
    required QuoteSectionDraft section,
    required QuotePositionDraft position,
  }) async {
    final name = position.name.trim().toLowerCase();
    final marking = position.marking.trim().toLowerCase();
    if (name.isEmpty && marking.isEmpty) return null;
    final items = await lookupCatalogItems(
      category: category,
      section: section,
      groupName: _textValue(position.values['group']),
      search: name.isNotEmpty ? position.name : position.marking,
    );
    final matches = items
        .where(
          (item) =>
              (name.isEmpty || item.name.trim().toLowerCase() == name) &&
              (marking.isEmpty || item.marking.trim().toLowerCase() == marking),
        )
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  /// Заполняет строку данными карточки каталога: наименованием, маркировкой,
  /// единицей, ценами и значениями полей. Введённое количество сохраняется.
  /// Затем, как при выборе карточки в каталоге, добавляются связанные позиции.
  Future<void> applyCatalogItem(
    QuoteCategoryDraft category,
    QuoteSectionDraft section,
    QuotePositionDraft target,
    CatalogItem item,
  ) async {
    final variant = activeVariant;
    if (variant == null || target.catalogItemId == item.id) return;
    if (target.catalogItemId != null) {
      _removeAutomaticContributions(variant, target.id);
    }
    final source = _positionFromCatalogItem(
      item,
      groupName: _groupName(
        category.catalogCategoryId,
        section.catalogSectionId,
        item.groupId,
      ),
    );
    final typedGroup = target.values['group'];
    target
      ..catalogItemId = item.id
      ..name = source.name
      ..marking = source.marking
      ..unit = source.unit
      ..purchasePrice = source.purchasePrice
      ..basePrice = source.basePrice
      ..manualPrice = null;
    target.values
      ..clear()
      ..addAll(source.values);
    if (!target.values.containsKey('group') && typedGroup != null) {
      target.values['group'] = typedGroup;
    }
    _changed();
    await _attachCatalogRelations(variant, target, item);
  }

  /// Отвязывает строку от карточки каталога, когда введённые наименование или
  /// маркировка ей больше не соответствуют. Данные строки остаются как есть.
  void detachCatalogItem(QuotePositionDraft position) {
    if (position.catalogItemId == null) return;
    final variant = _variantContaining(position);
    if (variant != null) _removeAutomaticContributions(variant, position.id);
    position.catalogItemId = null;
    _changed(position: position);
  }

  /// Пустые строки ввода не сохраняются: сервер требует наименование позиции,
  /// а после Enter в количестве всегда появляется следующая пустая строка.
  void _removeBlankEntryRows(QuoteDraft document) {
    for (final type in document.proposalTypes) {
      for (final variant in type.variants) {
        for (final category in variant.categories) {
          for (final section in category.sections) {
            section.positions.removeWhere(
              (position) =>
                  position.catalogItemId == null &&
                  position.name.trim().isEmpty &&
                  position.marking.trim().isEmpty,
            );
          }
        }
      }
    }
  }

  /// Добавляет выбранную карточку и затем точечно материализует её сохранённые
  /// зависимости в том же варианте. Уже присутствующая связанная карточка не
  /// пересоздаётся: увеличивается только количество, поэтому ручные цены и
  /// остальные изменения строки сохраняются.
  Future<void> addCatalogPosition(
    QuoteCategoryDraft category,
    QuoteSectionDraft section,
    CatalogItem item,
  ) async {
    final variant = activeVariant;
    if (variant == null) return;
    final existing = variant.positions
        .where((position) => position.catalogItemId == item.id)
        .firstOrNull;
    if (existing != null) {
      existing.quantity += 1;
    }
    final primaryPosition =
        existing ??
        _positionFromCatalogItem(
          item,
          groupName: _groupName(
            category.catalogCategoryId,
            section.catalogSectionId,
            item.groupId,
          ),
        );
    if (existing == null) section.positions.add(primaryPosition);
    _changed();
    await _attachCatalogRelations(
      variant,
      primaryPosition,
      item,
      additionalContribution: existing != null,
    );
  }

  /// Материализует сохранённые связи карточки в варианте и пересчитывает строку.
  Future<void> _attachCatalogRelations(
    QuoteVariantDraft variant,
    QuotePositionDraft primaryPosition,
    CatalogItem item, {
    bool additionalContribution = false,
  }) async {
    if (!attachesCatalogRelations) {
      await positionChanged(position: primaryPosition, fieldCode: 'quantity');
      return;
    }
    final relationGateway = _catalogGateway is CatalogRelationGateway
        ? _catalogGateway as CatalogRelationGateway
        : null;
    if (relationGateway == null) {
      await positionChanged(position: primaryPosition, fieldCode: 'quantity');
      return;
    }
    try {
      final relations = await _relationsFor(item.id, relationGateway);
      var changed = false;
      for (final relation in relations) {
        changed = _appendRelationLabel(primaryPosition, relation) || changed;
        final dependency = _dependencyByDatabaseId(relation.dependencyId);
        if (dependency != null && !_isRuleControlled(dependency.clientId)) {
          changed =
              _appendRelatedPosition(
                variant,
                relation,
                parentPositionId: primaryPosition.id,
                dependencyClientId: dependency.clientId,
                additionalContribution: additionalContribution,
              ) ||
              changed;
        }
      }
      if (changed) _changed();
      await positionChanged(position: primaryPosition, fieldCode: 'quantity');
    } on ApiException catch (exception) {
      error = exception.message;
      notifyListeners();
    } on Object {
      error = 'Позиция добавлена, но связанные карточки загрузить не удалось.';
      notifyListeners();
    }
  }

  bool _appendRelationLabel(
    QuotePositionDraft target,
    CatalogItemRelation relation,
  ) {
    final dependency = catalog?.dependencies
        .where((item) => item.id == relation.dependencyId)
        .firstOrNull;
    final fieldCode = dependency?.targetFieldCode;
    if (fieldCode == null) return false;
    final storedValue = target.values[fieldCode];
    final labels = storedValue is Iterable
        ? storedValue
              .map((item) => item?.toString().trim() ?? '')
              .where((item) => item.isNotEmpty)
              .toList()
        : <String>[
            if (storedValue != null && storedValue.toString().trim().isNotEmpty)
              storedValue.toString().trim(),
          ];
    final label = relation.sourceMarking.isEmpty
        ? relation.sourceName
        : '${relation.sourceName} / ${relation.sourceMarking}';
    if (labels.contains(label)) return false;
    labels.add(label);
    target.values[fieldCode] = labels;
    return true;
  }

  QuotePositionDraft _positionFromCatalogItem(
    CatalogItem item, {
    required String groupName,
  }) {
    final values = Map<String, dynamic>.from(item.values);
    if (groupName.isNotEmpty) values['group'] = groupName;
    return QuotePositionDraft(
      id: newQuoteId(),
      catalogItemId: item.id,
      name: item.name,
      marking: item.marking,
      unit: _textValue(item.values['unit']),
      quantity: 1,
      purchasePrice: _numericValue(item.values['purchase_price']),
      basePrice: _numericValue(item.values['base_price']) ?? 0,
      values: values,
    );
  }

  bool _appendRelatedPosition(
    QuoteVariantDraft variant,
    CatalogItemRelation relation, {
    required String parentPositionId,
    required String dependencyClientId,
    bool additionalContribution = false,
  }) {
    final baseMarker = _relationMarker(parentPositionId, dependencyClientId);
    final marker = additionalContribution
        ? '$baseMarker|${newQuoteId()}'
        : baseMarker;
    for (final position in variant.positions) {
      if (position.catalogItemId == relation.sourceItemId) {
        final sources = _autoRelationSources(position);
        if (sources.contains(marker)) return false;
        position.quantity += 1;
        _writeAutoRelationSources(position, {...sources, marker});
        return true;
      }
    }

    final categoryId = relation.sourceCategoryId;
    if (categoryId == null) return false;
    final sourceCategory = catalog?.categories
        .where((item) => item.id == categoryId)
        .firstOrNull;
    if (sourceCategory == null) return false;
    final sourceSection = sourceCategory.sections
        .where((item) => item.id == relation.sourceSectionId)
        .firstOrNull;

    var quoteCategory = variant.categories
        .where((item) => item.catalogCategoryId == sourceCategory.id)
        .firstOrNull;
    if (quoteCategory == null) {
      quoteCategory = QuoteCategoryDraft(
        id: newQuoteId(),
        catalogCategoryId: sourceCategory.id,
        name: sourceCategory.name,
        sections: [],
      );
      variant.categories.add(quoteCategory);
    }

    var quoteSection = quoteCategory.sections
        .where((item) => item.catalogSectionId == relation.sourceSectionId)
        .firstOrNull;
    if (quoteSection == null) {
      quoteSection = QuoteSectionDraft(
        id: newQuoteId(),
        catalogSectionId: sourceSection?.id,
        name: sourceSection?.name ?? sourceCategory.name,
        positions: [],
      );
      quoteCategory.sections.add(quoteSection);
    }

    final values = Map<String, dynamic>.from(relation.sourceValues);
    final groupName = _groupName(
      sourceCategory.id,
      sourceSection?.id,
      relation.sourceGroupId,
    );
    if (groupName.isNotEmpty) values['group'] = groupName;
    values['auto_added'] = true;
    values[_autoRelationSourcesKey] = [marker];
    quoteSection.positions.add(
      QuotePositionDraft(
        id: newQuoteId(),
        catalogItemId: relation.sourceItemId,
        name: relation.sourceName,
        marking: relation.sourceMarking,
        unit: _textValue(values['unit']),
        quantity: 1,
        purchasePrice: _numericValue(values['purchase_price']),
        basePrice: _numericValue(values['base_price']) ?? 0,
        values: values,
      ),
    );
    return true;
  }

  String _groupName(String? categoryId, String? sectionId, String? groupId) {
    if (categoryId == null || sectionId == null || groupId == null) return '';
    final category = catalog?.categories
        .where((item) => item.id == categoryId)
        .firstOrNull;
    final section = category?.sections
        .where((item) => item.id == sectionId)
        .firstOrNull;
    return section?.groups
            .where((item) => item.id == groupId)
            .firstOrNull
            ?.name ??
        '';
  }

  void removePosition(QuoteSectionDraft section, QuotePositionDraft position) {
    final variant = _variantContaining(position);
    if (variant != null) {
      _removeAutomaticContributions(variant, position.id);
    }
    section.positions.remove(position);
    _changed();
  }

  void removeCategory(QuoteCategoryDraft category) {
    if (saving) return;
    for (final type in draft?.proposalTypes ?? <QuoteProposalTypeDraft>[]) {
      for (final variant in type.variants) {
        if (!variant.categories.contains(category)) continue;
        final ids = category.sections
            .expand((section) => section.positions)
            .map((position) => position.id)
            .toList();
        for (final id in ids) {
          _removeAutomaticContributions(variant, id);
        }
        variant.categories.remove(category);
        _changed();
        return;
      }
    }
  }

  void removeSection(QuoteSectionDraft section) {
    if (saving) return;
    for (final type in draft?.proposalTypes ?? <QuoteProposalTypeDraft>[]) {
      for (final variant in type.variants) {
        for (final category in variant.categories) {
          if (!category.sections.contains(section)) continue;
          final ids = section.positions.map((position) => position.id).toList();
          for (final id in ids) {
            _removeAutomaticContributions(variant, id);
          }
          category.sections.remove(section);
          _changed();
          return;
        }
      }
    }
  }

  void setSectionSelection(QuoteSectionDraft section, bool selected) {
    for (final position in section.positions) {
      position.selected = selected;
    }
    _changed();
  }

  void removeSelectedPositions(QuoteSectionDraft section) {
    final selectedIds = section.positions
        .where((position) => position.selected)
        .map((position) => position.id)
        .toSet();
    if (selectedIds.isEmpty) return;
    final variant = section.positions
        .where((position) => selectedIds.contains(position.id))
        .map(_variantContaining)
        .whereType<QuoteVariantDraft>()
        .firstOrNull;
    if (variant != null) {
      for (final positionId in selectedIds) {
        _removeAutomaticContributions(variant, positionId);
      }
    }
    section.positions.removeWhere(
      (position) => selectedIds.contains(position.id),
    );
    _changed();
  }

  void reorderPosition(QuoteSectionDraft section, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = section.positions.removeAt(oldIndex);
    section.positions.insert(newIndex, item);
    _changed();
  }

  void reorderCategory(QuoteVariantDraft variant, int oldIndex, int newIndex) =>
      _reorderStructure(variant.categories, oldIndex, newIndex);

  void reorderSection(
    QuoteCategoryDraft category,
    int oldIndex,
    int newIndex,
  ) => _reorderStructure(category.sections, oldIndex, newIndex);

  void _reorderStructure<T>(List<T> items, int oldIndex, int newIndex) {
    if (saving ||
        oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex > items.length) {
      return;
    }
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    items.insert(newIndex, items.removeAt(oldIndex));
    dirty = true;
    successMessage = null;
    notifyListeners();
  }

  /// Применяет значение к выбранным строкам, а при отсутствии выбора — ко
  /// всему разделу. Это соответствует согласованной логике массовых действий.
  void applyPercent(
    QuoteSectionDraft section, {
    required double value,
    required bool markup,
    String? fieldCode,
  }) {
    final targetCode =
        fieldCode ?? (markup ? 'markup_value' : 'discount_value');
    final selected = section.positions.where((position) => position.selected);
    final targets = selected.isEmpty ? section.positions : selected.toList();
    for (final position in targets) {
      if (targetCode == 'markup_value') {
        position.markupPercent = value;
      } else if (targetCode == 'discount_value') {
        position.discountPercent = value;
      } else {
        position.values[targetCode] = value;
      }
    }
    if (markup) {
      section.markupPercent = value;
    } else {
      section.discountPercent = value;
    }
    _changed();
  }

  Future<void> positionChanged({
    QuotePositionDraft? position,
    String? fieldCode,
  }) async {
    _changed(position: position, fieldCode: fieldCode);
    if (position == null) return;
    final previous = _behaviorQueues[position.id] ?? Future<void>.value();
    final queued = previous.then(
      (_) => _applyBehaviorRules(position, changedFieldCode: fieldCode),
    );
    _behaviorQueues[position.id] = queued;
    try {
      await queued;
    } on ApiException catch (exception) {
      error = exception.message;
      notifyListeners();
    } on Object {
      error =
          'Не удалось применить настроенное действие для связанных карточек.';
      notifyListeners();
    } finally {
      if (identical(_behaviorQueues[position.id], queued)) {
        _behaviorQueues.remove(position.id);
      }
    }
  }

  Future<void> _applyBehaviorRules(
    QuotePositionDraft position, {
    String? changedFieldCode,
    String? eventType,
  }) async {
    final configuration = catalog;
    final location = _locationOf(position);
    if (configuration == null || location == null) return;
    final categoryClientId = configuration.categories
        .where((item) => item.id == location.category.catalogCategoryId)
        .firstOrNull
        ?.clientId;
    if (categoryClientId == null || position.catalogItemId == null) return;

    final evaluator = QuoteConfiguredCalculationEngine(configuration);
    var changed = false;
    for (final rule in configuration.rules.where(
      (item) =>
          item.isEnabled &&
          item.categoryClientId == categoryClientId &&
          _ruleRunsFor(item, changedFieldCode, eventType),
    )) {
      if (!evaluator.matchesRule(position, rule)) continue;
      for (final action in rule.actions.where(
        (item) => const {
          'add_related_cards',
          'remove_related_cards',
        }.contains(item.actionType),
      )) {
        final dependency = configuration.dependencies
            .where((item) => item.clientId == action.dependencyClientId)
            .firstOrNull;
        if (dependency == null) continue;
        if (action.actionType == 'remove_related_cards') {
          changed =
              _removeDependencyContributions(
                location.variant,
                position.id,
                dependency.clientId,
              ) ||
              changed;
          continue;
        }
        final gateway = _catalogGateway is CatalogRelationGateway
            ? _catalogGateway as CatalogRelationGateway
            : null;
        if (gateway == null) continue;
        final relations = await _relationsFor(position.catalogItemId!, gateway);
        for (final relation in relations.where(
          (item) => item.dependencyId == dependency.id,
        )) {
          changed =
              _appendRelatedPosition(
                location.variant,
                relation,
                parentPositionId: position.id,
                dependencyClientId: dependency.clientId,
              ) ||
              changed;
        }
      }
    }
    if (changed) _changed();
  }

  Future<void> _applyDocumentBehaviorRules(String eventType) async {
    final document = draft;
    if (document == null) return;
    final positions = document.proposalTypes
        .expand((type) => type.variants)
        .expand((variant) => variant.positions)
        .toList(growable: false);
    for (final position in positions) {
      await _applyBehaviorRules(position, eventType: eventType);
    }
  }

  bool _ruleRunsFor(
    CalculationRuleDraft rule,
    String? changedFieldCode,
    String? eventType,
  ) {
    if (eventType != null) return rule.eventType == eventType;
    if (rule.eventType == 'field_changed') {
      return changedFieldCode != null &&
          (rule.eventFieldCode == null ||
              rule.eventFieldCode == changedFieldCode);
    }
    return rule.eventType == 'row_calculation' ||
        rule.eventType == 'variant_calculation';
  }

  Future<List<CatalogItemRelation>> _relationsFor(
    String itemId,
    CatalogRelationGateway gateway,
  ) async {
    final cached = _relationRequests[itemId];
    if (cached != null) return await cached;
    final request = _authorized((token) => gateway.getRelations(token, itemId));
    _relationRequests[itemId] = request;
    try {
      return await request;
    } on Object {
      if (identical(_relationRequests[itemId], request)) {
        _relationRequests.remove(itemId);
      }
      rethrow;
    }
  }

  CatalogDependency? _dependencyByDatabaseId(String id) =>
      catalog?.dependencies.where((item) => item.id == id).firstOrNull;

  bool _isRuleControlled(String dependencyClientId) =>
      catalog?.rules.any(
        (rule) =>
            rule.isEnabled &&
            rule.actions.any(
              (action) =>
                  action.dependencyClientId == dependencyClientId &&
                  const {
                    'add_related_cards',
                    'remove_related_cards',
                  }.contains(action.actionType),
            ),
      ) ??
      false;

  ({QuoteVariantDraft variant, QuoteCategoryDraft category})? _locationOf(
    QuotePositionDraft position,
  ) {
    final document = draft;
    if (document == null) return null;
    for (final type in document.proposalTypes) {
      for (final variant in type.variants) {
        for (final category in variant.categories) {
          if (category.sections.any(
            (section) => section.positions.contains(position),
          )) {
            return (variant: variant, category: category);
          }
        }
      }
    }
    return null;
  }

  QuoteVariantDraft? _variantContaining(QuotePositionDraft position) =>
      _locationOf(position)?.variant;

  bool _removeDependencyContributions(
    QuoteVariantDraft variant,
    String parentPositionId,
    String dependencyClientId,
  ) {
    final marker = _relationMarker(parentPositionId, dependencyClientId);
    var changed = false;
    for (final category in variant.categories) {
      for (final section in category.sections) {
        for (final position in section.positions.toList(growable: false)) {
          final sources = _autoRelationSources(position);
          final removed = sources
              .where(
                (source) => source == marker || source.startsWith('$marker|'),
              )
              .length;
          if (removed == 0) continue;
          sources.removeWhere(
            (source) => source == marker || source.startsWith('$marker|'),
          );
          position.quantity -= removed;
          changed = true;
          if (position.quantity <= 0) {
            section.positions.remove(position);
          } else {
            _writeAutoRelationSources(position, sources);
          }
        }
      }
    }
    return changed;
  }

  void _removeAutomaticContributions(
    QuoteVariantDraft variant,
    String parentPositionId,
  ) {
    final prefix = '$parentPositionId|';
    for (final category in variant.categories) {
      for (final section in category.sections) {
        for (final position in section.positions.toList(growable: false)) {
          final sources = _autoRelationSources(position);
          final removed = sources
              .where((item) => item.startsWith(prefix))
              .length;
          if (removed == 0) continue;
          sources.removeWhere((item) => item.startsWith(prefix));
          position.quantity -= removed;
          if (position.quantity <= 0) {
            section.positions.remove(position);
          } else {
            _writeAutoRelationSources(position, sources);
          }
        }
      }
    }
  }

  Set<String> _autoRelationSources(QuotePositionDraft position) {
    final stored = position.values[_autoRelationSourcesKey];
    return stored is Iterable
        ? stored.map((item) => item.toString()).toSet()
        : <String>{};
  }

  void _writeAutoRelationSources(
    QuotePositionDraft position,
    Set<String> sources,
  ) {
    if (sources.isEmpty) {
      position.values.remove(_autoRelationSourcesKey);
    } else {
      position.values[_autoRelationSourcesKey] = sources.toList(
        growable: false,
      );
    }
  }

  String _relationMarker(String parentPositionId, String dependencyClientId) =>
      '$parentPositionId|$dependencyClientId';

  void _changed({QuotePositionDraft? position, String? fieldCode}) {
    _recalculateConfiguredRules(position: position, fieldCode: fieldCode);
    dirty = true;
    successMessage = null;
    notifyListeners();
  }

  void _recalculateConfiguredRules({
    QuotePositionDraft? position,
    String? fieldCode,
    bool saving = false,
  }) {
    final configuration = catalog;
    final document = draft;
    if (configuration == null || document == null) return;
    final previousCalculationError = _calculationError;
    _calculationError = null;
    if (error == previousCalculationError) error = null;
    try {
      QuoteConfiguredCalculationEngine(configuration).calculateDocument(
        document,
        changedPosition: position,
        changedFieldCode: fieldCode,
        saving: saving,
      );
    } on FormatException catch (exception) {
      _calculationError = exception.message;
      error = _calculationError;
    }
  }

  Future<bool> save({
    required KanbanBoard board,
    KanbanCard? card,
    String? creationColumnId,
  }) async {
    final document = draft;
    if (document == null || saving) return false;
    _removeBlankEntryRows(document);
    try {
      await Future.wait(_behaviorQueues.values.toList(growable: false));
      await _applyDocumentBehaviorRules('card_saving');
    } on ApiException catch (exception) {
      error = exception.message;
      notifyListeners();
      return false;
    } on Object {
      error = 'Не удалось применить настроенные связи перед сохранением.';
      notifyListeners();
      return false;
    }
    _recalculateConfiguredRules(saving: true);
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
      final cardId = persistedCardId ?? card?.id;
      if (cardId == null) {
        if (creationColumnId == null) {
          error = 'Не выбран столбец создания предложения.';
          return false;
        }
        draft = await _authorized(
          (token) => _quoteGateway.createQuote(
            token,
            board.id,
            creationColumnId,
            document,
          ),
        );
        persistedCardId = draft?.cardId;
      } else {
        draft = await _authorized(
          (token) => _quoteGateway.saveQuote(token, board.id, cardId, document),
        );
        persistedCardId = cardId;
      }
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

  /// Идентификаторы для запроса PDF: [QuotePrintScope.variant] — открытые
  /// сейчас тип и вариант, [QuotePrintScope.type] — только открытый тип,
  /// [QuotePrintScope.all] — без ограничений.
  ({String? typeId, String? variantId}) printSelection(QuotePrintScope scope) =>
      switch (scope) {
        QuotePrintScope.variant => (
          typeId: activeType?.id,
          variantId: activeVariant?.id,
        ),
        QuotePrintScope.type => (typeId: activeType?.id, variantId: null),
        QuotePrintScope.all => (typeId: null, variantId: null),
      };

  /// Проверяет, что предложение можно печатать: оно сохранено и без
  /// несохранённых изменений. Иначе записывает причину в [error].
  bool ensurePrintable({KanbanCard? card}) {
    if ((persistedCardId ?? card?.id) == null) {
      error = 'Сначала сохраните предложение.';
      notifyListeners();
      return false;
    }
    if (dirty) {
      error = 'Сохраните изменения перед печатью.';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Загружает PDF только для сохранённой и не изменённой версии предложения.
  /// Это исключает ситуацию, когда экран показывает одно, а сервер печатает
  /// предыдущую версию документа. Содержимое PDF задаёт [scope].
  Future<QuotePdfDownload?> downloadPdf({
    required KanbanBoard board,
    required QuotePrintScope scope,
    KanbanCard? card,
  }) async {
    if (printing) return null;
    if (!ensurePrintable(card: card)) return null;
    final cardId = (persistedCardId ?? card?.id)!;
    final selection = printSelection(scope);
    printing = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      return await _authorized(
        (token) => _quoteGateway.downloadPdf(
          token,
          board.id,
          cardId,
          proposalTypeId: selection.typeId,
          variantId: selection.variantId,
        ),
      );
    } on ApiException catch (exception) {
      error = exception.message;
      return null;
    } on Object {
      error = 'Не удалось сформировать PDF. Проверьте подключение.';
      return null;
    } finally {
      printing = false;
      notifyListeners();
    }
  }

  String? _validate(QuoteDraft document) {
    if (_calculationError != null) return _calculationError;
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
        if (variant.positions.any(
          (position) => !position.hasValidCalculatedPrice,
        )) {
          return 'Расчётная цена позиции не может быть отрицательной.';
        }
      }
    }
    final configuredValidation = catalog == null
        ? null
        : QuoteConfiguredCalculationEngine(catalog!).validateForSave(document);
    if (configuredValidation != null) return configuredValidation;
    return null;
  }

  Future<T> _authorized<T>(Future<T> Function(String token) request) =>
      _auth.executeAuthorized(request);

  @override
  void dispose() {
    _successMessageTimer?.cancel();
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
