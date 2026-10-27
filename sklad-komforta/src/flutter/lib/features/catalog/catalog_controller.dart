import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/realtime_client.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_api.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

/// Состояние фильтров, пагинации и CRUD каталога без зависимости от UI.
final class CatalogController extends ChangeNotifier {
  /// Без [api] контроллер работает с сервером и сам подписывается на
  /// уведомления об изменениях каталога; в тестах источник передаётся явно
  /// через [realtime].
  CatalogController(
    AppConfig config,
    this._auth, {
    CatalogGateway? api,
    RealtimeSource? realtime,
    this.pageSize = 12,
    this.realtimeDebounce = const Duration(milliseconds: 300),
  }) : _api = api ?? CatalogApi(config),
       _ownsApi = api == null,
       _realtime =
           realtime ??
           (api == null
               ? RealtimeClient(
                   config: config,
                   topic: 'catalog',
                   ticketPath: '/catalog/realtime-ticket',
                   authorized: _auth.executeAuthorized,
                 )
               : null),
       _ownsRealtime = realtime == null && api == null;

  final AuthController _auth;
  final CatalogGateway _api;
  final bool _ownsApi;
  final int pageSize;

  /// Пауза, за которую серия сигналов (импорт, массовая операция) сливается
  /// в одно перечитывание страницы.
  final Duration realtimeDebounce;
  final RealtimeSource? _realtime;
  final bool _ownsRealtime;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  Timer? _realtimeTimer;
  bool _realtimeConfigurationChanged = false;
  Timer? _searchTimer;
  int _imageLoadGeneration = 0;
  int _relationLoadGeneration = 0;
  final Map<String, Future<CatalogBulkResult>> _relationWrites = {};
  bool _disposed = false;

  CatalogConfiguration? configuration;
  CatalogItemPage? result;
  CatalogItem? selectedItem;
  String? categoryId;
  String? sectionId;
  String? status;
  String search = '';
  String sort = 'import';
  int page = 1;
  bool loading = false;
  bool saving = false;
  bool imagesLoading = false;
  bool relationsLoading = false;
  bool transferBusy = false;
  String? error;
  String? transferMessage;
  String? imagesError;
  String? relationsError;
  List<CatalogItemImage> images = const [];
  List<CatalogItemRelation> relations = const [];
  final Set<String> selectedIds = <String>{};
  int _selectionGeneration = 0;
  final Map<String, CatalogItem> _selectedItems = {};
  List<CatalogItem> get bulkItems => selectedIds
      .map((id) => _selectedItems[id])
      .whereType<CatalogItem>()
      .toList(growable: false);

  Future<Map<String, List<CatalogItemRelation>>> loadBulkRelations(
    List<CatalogItem> targets,
  ) async {
    final api = _api as CatalogRelationGateway;
    final result = <String, List<CatalogItemRelation>>{};
    // Limit concurrent requests when the selection spans several pages.
    for (var offset = 0; offset < targets.length; offset += 8) {
      final batch = targets.skip(offset).take(8);
      final entries = await Future.wait(
        batch.map((item) async {
          await _relationWrites[item.id];
          return MapEntry(
            item.id,
            await _authorized((token) => api.getRelations(token, item.id)),
          );
        }),
      );
      result.addEntries(entries);
    }
    return result;
  }

  Future<void> editBulkRelation(
    List<CatalogItem> targets,
    String dependencyId,
    String sourceItemId, {
    bool remove = false,
  }) async {
    final api = _api as CatalogBulkRelationGateway;
    for (final target in targets) {
      await _relationWrites[target.id];
    }
    final operation = _authorized(
      (token) => api.editBulkRelation(
        accessToken: token,
        itemIds: targets.map((item) => item.id).toList(),
        dependencyId: dependencyId,
        sourceItemId: sourceItemId,
        remove: remove,
      ),
    );
    for (final target in targets) {
      _relationWrites[target.id] = operation;
    }
    try {
      await operation;
      final activeId = selectedItem?.id;
      if (!_disposed &&
          activeId != null &&
          targets.any((item) => item.id == activeId)) {
        await loadRelations(activeId);
      }
    } finally {
      for (final target in targets) {
        if (identical(_relationWrites[target.id], operation)) {
          _relationWrites.remove(target.id);
        }
      }
    }
  }

  List<CatalogItem> get items => result?.items ?? const [];
  int get total => result?.total ?? 0;
  int get pageCount => result?.pageCount ?? 1;
  bool get hasSelection => selectedIds.isNotEmpty;
  bool get currentPageSelected =>
      items.isNotEmpty && items.every((item) => selectedIds.contains(item.id));

  CatalogCategory? get selectedCategory {
    for (final category in configuration?.categories ?? const []) {
      if (category.id == categoryId) return category;
    }
    return null;
  }

  /// Загружает структуру и первую страницу параллельно после входа.
  Future<void> initialize() async {
    _listenRealtime();
    if (loading || configuration != null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final responses = await Future.wait([
        _authorized((token) => _api.getConfiguration(token)),
        _loadPage(),
      ]);
      configuration = responses.first as CatalogConfiguration;
    } on AuthApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось загрузить каталог. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Выбирает категорию и сбрасывает несовместимый раздел.
  Future<void> selectCategory(String? value) async {
    if (categoryId == value) return;
    categoryId = value;
    sectionId = null;
    page = 1;
    clearSelection(notify: false);
    await refresh();
  }

  Future<void> selectSection(String? value) async {
    if (sectionId == value) return;
    sectionId = value;
    page = 1;
    clearSelection(notify: false);
    await refresh();
  }

  Future<void> selectStatus(String? value) async {
    final normalized = value?.isEmpty == true ? null : value;
    if (status == normalized) return;
    status = normalized;
    page = 1;
    clearSelection(notify: false);
    await refresh();
  }

  /// Откладывает сетевой поиск, чтобы ввод не создавал запрос на каждый символ.
  void updateSearch(String value) {
    if (search != value) clearSelection(notify: false);
    search = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      page = 1;
      refresh();
    });
  }

  Future<void> goToPage(int value) async {
    final target = value.clamp(1, pageCount);
    if (target == page) return;
    page = target;
    await refresh();
  }

  Future<void> selectSort(String value) async {
    if (sort == value || loading || transferBusy) return;
    sort = value;
    page = 1;
    await refresh();
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadPage();
    } on AuthApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось обновить каталог. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Повторно загружает структуру каталога после изменения настроек организации.
  /// Обычные фильтры и пагинация используют [refresh], чтобы не запрашивать
  /// неизменную конфигурацию при каждом пользовательском действии.
  Future<void> reloadConfiguration() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      configuration = await _authorized(
        (token) => _api.getConfiguration(token),
      );
      _normalizeStructuralFilters();
      await _loadPage();
    } on AuthApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось обновить структуру каталога. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Подписывается на изменения каталога, сделанные другими пользователями
  /// или в другой вкладке.
  void _listenRealtime() {
    final source = _realtime;
    if (source == null || _realtimeSubscription != null) return;
    _realtimeSubscription = source.events.listen((event) {
      if (event.kind == RealtimeEvent.configuration) {
        _realtimeConfigurationChanged = true;
      }
      _realtimeTimer?.cancel();
      _realtimeTimer = Timer(realtimeDebounce, _applyRealtimeChanges);
    });
    source.start();
  }

  /// Тихо перечитывает текущую страницу с теми же фильтрами. Открытый
  /// редактор товара не трогается: он работает со своей копией данных.
  Future<void> _applyRealtimeChanges() async {
    if (_disposed) return;
    if (loading || saving || transferBusy) {
      _realtimeTimer = Timer(realtimeDebounce, _applyRealtimeChanges);
      return;
    }
    try {
      if (_realtimeConfigurationChanged) {
        _realtimeConfigurationChanged = false;
        configuration = await _authorized(
          (token) => _api.getConfiguration(token),
        );
        _normalizeStructuralFilters();
      }
      await _loadPage();
    } on Object {
      // Сеть недоступна: страница обновится после переподключения (resync).
      return;
    }
    if (!_disposed) notifyListeners();
  }

  void _normalizeStructuralFilters() {
    final category = selectedCategory;
    if (category == null) {
      categoryId = null;
      sectionId = null;
      page = 1;
      return;
    }
    if (!category.sections.any((section) => section.id == sectionId)) {
      sectionId = null;
      page = 1;
    }
  }

  /// Выбирает карточку для постоянной панели редактирования.
  void selectItem(CatalogItem? item) {
    if (selectedItem?.id != item?.id) {
      ++_relationLoadGeneration;
      relationsLoading = false;
      images = const [];
      imagesError = null;
      relations = const [];
      relationsError = null;
    }
    selectedItem = item;
    notifyListeners();
  }

  Future<void> loadRelations(String itemId) async {
    final relationApi = _api is CatalogRelationGateway
        ? _api as CatalogRelationGateway
        : null;
    if (relationApi == null) return;
    final generation = ++_relationLoadGeneration;
    relationsLoading = true;
    relationsError = null;
    notifyListeners();
    try {
      await _relationWrites[itemId];
      final loaded = await _authorized(
        (token) => relationApi.getRelations(token, itemId),
      );
      if (generation == _relationLoadGeneration && selectedItem?.id == itemId) {
        relations = loaded;
      }
    } on AuthApiException catch (exception) {
      if (generation == _relationLoadGeneration) {
        relationsError = exception.message;
      }
    } on Object {
      if (generation == _relationLoadGeneration) {
        relationsError = 'Не удалось загрузить связанные карточки.';
      }
    } finally {
      if (generation == _relationLoadGeneration) {
        relationsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<List<CatalogRelationCandidate>> searchRelationCandidates(
    String dependencyId,
    String search,
  ) async {
    final relationApi = _api is CatalogRelationGateway
        ? _api as CatalogRelationGateway
        : null;
    if (relationApi == null) return const [];
    return _authorized(
      (token) => relationApi.searchRelationCandidates(
        accessToken: token,
        dependencyId: dependencyId,
        search: search,
      ),
    );
  }

  Future<bool> addRelation(
    String itemId,
    CatalogDependency dependency,
    CatalogRelationCandidate candidate,
  ) => _editRelation(itemId, dependency.id, candidate.id, false);

  Future<bool> removeRelation(
    String itemId,
    String dependencyId,
    String sourceItemId,
  ) => _editRelation(itemId, dependencyId, sourceItemId, true);

  Future<bool> _editRelation(
    String itemId,
    String dependencyId,
    String sourceItemId,
    bool remove,
  ) async {
    final relationApi = _api is CatalogRelationGateway
        ? _api as CatalogRelationGateway
        : null;
    if (relationApi == null ||
        _api is! CatalogBulkRelationGateway ||
        relationsLoading ||
        selectedItem?.id != itemId ||
        _relationWrites.containsKey(itemId)) {
      return false;
    }
    final generation = ++_relationLoadGeneration;
    relationsLoading = true;
    relationsError = null;
    Future<CatalogBulkResult>? operation;
    try {
      operation = _authorized(
        (token) => (_api as CatalogBulkRelationGateway).editBulkRelation(
          accessToken: token,
          itemIds: [itemId],
          dependencyId: dependencyId,
          sourceItemId: sourceItemId,
          remove: remove,
        ),
      );
      _relationWrites[itemId] = operation;
      notifyListeners();
      await operation;
      final loaded = await _authorized(
        (token) => relationApi.getRelations(token, itemId),
      );
      if (generation == _relationLoadGeneration && selectedItem?.id == itemId) {
        relations = loaded;
      }
      return true;
    } on AuthApiException catch (exception) {
      if (generation == _relationLoadGeneration) {
        relationsError = exception.message;
      }
      return false;
    } on Object {
      if (generation == _relationLoadGeneration) {
        relationsError =
            'Не удалось сохранить или обновить связанные карточки. Повторите загрузку.';
      }
      return false;
    } finally {
      if (identical(_relationWrites[itemId], operation)) {
        _relationWrites.remove(itemId);
      }
      if (generation == _relationLoadGeneration) {
        relationsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadImages(String itemId) async {
    final imageApi = _api is CatalogImageGateway
        ? _api as CatalogImageGateway
        : null;
    if (imageApi == null) return;
    final generation = ++_imageLoadGeneration;
    imagesLoading = true;
    imagesError = null;
    notifyListeners();
    try {
      final loaded = await _authorized(
        (token) => imageApi.getImages(token, itemId),
      );
      if (generation == _imageLoadGeneration && selectedItem?.id == itemId) {
        images = loaded;
      }
    } on AuthApiException catch (exception) {
      if (generation == _imageLoadGeneration) {
        imagesError = exception.message;
      }
    } on Object {
      if (generation == _imageLoadGeneration) {
        imagesError = 'Не удалось загрузить изображения.';
      }
    } finally {
      if (generation == _imageLoadGeneration) {
        imagesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> uploadImage({
    required String itemId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final imageApi = _api is CatalogImageGateway
        ? _api as CatalogImageGateway
        : null;
    if (imageApi == null || imagesLoading) return false;
    imagesLoading = true;
    imagesError = null;
    notifyListeners();
    try {
      final uploaded = await _authorized(
        (token) => imageApi.uploadImage(
          accessToken: token,
          itemId: itemId,
          fileName: fileName,
          contentType: contentType,
          bytes: bytes,
        ),
      );
      images = [...images, uploaded]
        ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
      _replaceItemThumbnail(itemId, images.first.downloadUrl);
      return true;
    } on AuthApiException catch (exception) {
      imagesError = exception.message;
      return false;
    } on Object {
      imagesError = 'Не удалось загрузить изображение.';
      return false;
    } finally {
      imagesLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteImage(String itemId, String imageId) async {
    final imageApi = _api is CatalogImageGateway
        ? _api as CatalogImageGateway
        : null;
    if (imageApi == null || imagesLoading) return false;
    imagesLoading = true;
    imagesError = null;
    notifyListeners();
    try {
      await _authorized(
        (token) => imageApi.deleteImage(token, itemId, imageId),
      );
      images = images.where((image) => image.id != imageId).toList();
      _replaceItemThumbnail(
        itemId,
        images.isEmpty ? null : images.first.downloadUrl,
      );
      return true;
    } on AuthApiException catch (exception) {
      imagesError = exception.message;
      return false;
    } on Object {
      imagesError = 'Не удалось удалить изображение.';
      return false;
    } finally {
      imagesLoading = false;
      notifyListeners();
    }
  }

  CatalogItemDraft createDraft() {
    final categories = configuration?.categories ?? const [];
    final initialCategory =
        categoryId ?? (categories.isEmpty ? '' : categories.first.id);
    return CatalogItemDraft(categoryId: initialCategory, name: '');
  }

  Future<bool> save(CatalogItemDraft draft, {String? itemId}) async {
    if (saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final saved = itemId == null
          ? await _authorized((token) => _api.createItem(token, draft))
          : await _authorized((token) => _api.updateItem(token, itemId, draft));
      selectedItem = saved;
      await _loadPage();
      return true;
    } on AuthApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось сохранить товар. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> deleteSelected() async {
    final item = selectedItem;
    if (item == null || saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _authorized((token) => _api.deleteItem(token, item.id));
      selectedItem = null;
      if (items.length == 1 && page > 1) page--;
      await _loadPage();
      return true;
    } on AuthApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось удалить товар. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void toggleSelection(String itemId) {
    ++_selectionGeneration;
    if (!selectedIds.add(itemId)) selectedIds.remove(itemId);
    for (final item in items) {
      if (selectedIds.contains(item.id)) _selectedItems[item.id] = item;
    }
    _selectedItems.removeWhere((id, _) => !selectedIds.contains(id));
    notifyListeners();
  }

  void toggleCurrentPage() {
    ++_selectionGeneration;
    if (currentPageSelected) {
      selectedIds.removeAll(items.map((item) => item.id));
    } else {
      selectedIds.addAll(items.map((item) => item.id));
    }
    for (final item in items) {
      if (selectedIds.contains(item.id)) _selectedItems[item.id] = item;
    }
    _selectedItems.removeWhere((id, _) => !selectedIds.contains(id));
    notifyListeners();
  }

  void clearSelection({bool notify = true}) {
    ++_selectionGeneration;
    if (selectedIds.isEmpty) return;
    selectedIds.clear();
    _selectedItems.clear();
    if (notify) notifyListeners();
  }

  /// Выбирает все страницы текущей выборки, не меняя открытую страницу.
  Future<void> selectAllFiltered() async {
    if (transferBusy || saving || loading || _disposed) return;
    final generation = ++_selectionGeneration;
    final filters = (categoryId, sectionId, status, search);
    final selectedSort = sort;
    bool active() =>
        !_disposed &&
        generation == _selectionGeneration &&
        filters == (categoryId, sectionId, status, search);
    transferBusy = true;
    error = null;
    notifyListeners();
    try {
      final selected = <String, CatalogItem>{};
      var nextPage = 1;
      while (active()) {
        final loaded = await _authorized(
          (token) => _api.getItems(
            accessToken: token,
            categoryId: filters.$1,
            sectionId: filters.$2,
            status: filters.$3,
            search: filters.$4,
            page: nextPage,
            pageSize: 100,
            sort: selectedSort,
          ),
        );
        if (!active()) return;
        for (final item in loaded.items) {
          selected[item.id] = item;
        }
        if (nextPage >= loaded.pageCount) break;
        nextPage++;
      }
      if (!active()) return;
      selectedIds
        ..clear()
        ..addAll(selected.keys);
      _selectedItems
        ..clear()
        ..addAll(selected);
    } on AuthApiException catch (exception) {
      if (active()) error = exception.message;
    } on Object {
      if (active()) {
        error =
            'Не удалось выбрать все позиции. Проверьте подключение и повторите попытку.';
      }
    } finally {
      transferBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<CatalogSpreadsheetDownload?> downloadTemplate() =>
      _downloadSpreadsheet(
        (api, token) =>
            api.downloadTemplate(accessToken: token, categoryId: categoryId),
      );

  Future<CatalogSpreadsheetDownload?> exportCatalog() => _downloadSpreadsheet(
    (api, token) => api.exportCatalog(
      accessToken: token,
      categoryId: categoryId,
      sectionId: sectionId,
      status: status,
      search: search,
    ),
  );

  Future<CatalogSpreadsheetDownload?> _downloadSpreadsheet(
    Future<CatalogSpreadsheetDownload> Function(
      CatalogTransferGateway api,
      String token,
    )
    request,
  ) async {
    final transferApi = _api is CatalogTransferGateway
        ? _api as CatalogTransferGateway
        : null;
    if (transferApi == null || transferBusy) return null;
    transferBusy = true;
    transferMessage = null;
    error = null;
    notifyListeners();
    try {
      return await _authorized((token) => request(transferApi, token));
    } on AuthApiException catch (exception) {
      error = exception.message;
      return null;
    } on Object {
      error = 'Не удалось получить XLSX-файл.';
      return null;
    } finally {
      transferBusy = false;
      notifyListeners();
    }
  }

  Future<bool> importCatalog({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final transferApi = _api is CatalogTransferGateway
        ? _api as CatalogTransferGateway
        : null;
    if (transferApi == null || transferBusy) return false;
    transferBusy = true;
    transferMessage = null;
    error = null;
    notifyListeners();
    try {
      final imported = await _authorized(
        (token) => transferApi.importCatalog(
          accessToken: token,
          fileName: fileName,
          bytes: bytes,
        ),
      );
      page = 1;
      clearSelection(notify: false);
      await _loadPage();
      transferMessage =
          'Импортировано строк: ${imported.totalRows}. '
          'Создано: ${imported.created}, обновлено: ${imported.updated}.';
      return true;
    } on AuthApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось импортировать XLSX-файл.';
      return false;
    } finally {
      transferBusy = false;
      notifyListeners();
    }
  }

  Future<bool> applyBulk({required String action, String? status}) async {
    final transferApi = _api is CatalogTransferGateway
        ? _api as CatalogTransferGateway
        : null;
    if (transferApi == null || transferBusy || selectedIds.isEmpty) {
      return false;
    }
    transferBusy = true;
    transferMessage = null;
    error = null;
    notifyListeners();
    try {
      final result = await _authorized(
        (token) => transferApi.applyBulk(
          accessToken: token,
          itemIds: selectedIds.toList(growable: false),
          action: action,
          status: status,
        ),
      );
      clearSelection(notify: false);
      await _loadPage();
      if (items.isEmpty && page > 1) {
        page--;
        await _loadPage();
      }
      transferMessage = 'Изменено карточек: ${result.affected}.';
      return true;
    } on AuthApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось выполнить массовую операцию.';
      return false;
    } finally {
      transferBusy = false;
      notifyListeners();
    }
  }

  Future<CatalogItemPage> _loadPage() async {
    final loaded = await _authorized(
      (token) => _api.getItems(
        accessToken: token,
        categoryId: categoryId,
        sectionId: sectionId,
        status: status,
        search: search,
        page: page,
        pageSize: pageSize,
        sort: sort,
      ),
    );
    result = loaded;
    page = loaded.page;
    return loaded;
  }

  /// Обновляет только обложку изменённой карточки, не перезагружая страницу каталога.
  void _replaceItemThumbnail(String itemId, String? thumbnailUrl) {
    final current = result;
    if (current == null) return;
    result = CatalogItemPage(
      items: current.items
          .map(
            (item) =>
                item.id == itemId ? item.withThumbnail(thumbnailUrl) : item,
          )
          .toList(growable: false),
      page: current.page,
      pageSize: current.pageSize,
      total: current.total,
    );
    if (selectedItem?.id == itemId) {
      selectedItem = selectedItem!.withThumbnail(thumbnailUrl);
    }
  }

  Future<T> _authorized<T>(Future<T> Function(String token) request) =>
      _auth.executeAuthorized(request);

  @override
  void dispose() {
    _disposed = true;
    _realtimeTimer?.cancel();
    unawaited(_realtimeSubscription?.cancel());
    if (_ownsRealtime) unawaited(_realtime?.close());
    ++_relationLoadGeneration;
    _searchTimer?.cancel();
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
