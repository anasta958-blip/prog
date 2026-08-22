import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/features/auth/auth_api.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_api.dart';
import 'package:sklad_komforta_app/features/catalog/catalog_models.dart';

/// Состояние фильтров, пагинации и CRUD каталога без зависимости от UI.
final class CatalogController extends ChangeNotifier {
  CatalogController(
    AppConfig config,
    this._auth, {
    CatalogGateway? api,
    this.pageSize = 12,
  }) : _api = api ?? CatalogApi(config),
       _ownsApi = api == null;

  final AuthController _auth;
  final CatalogGateway _api;
  final bool _ownsApi;
  final int pageSize;
  Timer? _searchTimer;
  int _imageLoadGeneration = 0;

  CatalogConfiguration? configuration;
  CatalogItemPage? result;
  CatalogItem? selectedItem;
  String? categoryId;
  String? sectionId;
  String? status;
  String search = '';
  int page = 1;
  bool loading = false;
  bool saving = false;
  bool imagesLoading = false;
  String? error;
  String? imagesError;
  List<CatalogItemImage> images = const [];

  List<CatalogItem> get items => result?.items ?? const [];
  int get total => result?.total ?? 0;
  int get pageCount => result?.pageCount ?? 1;

  CatalogCategory? get selectedCategory {
    for (final category in configuration?.categories ?? const []) {
      if (category.id == categoryId) return category;
    }
    return null;
  }

  /// Загружает структуру и первую страницу параллельно после входа.
  Future<void> initialize() async {
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
    await refresh();
  }

  Future<void> selectSection(String? value) async {
    if (sectionId == value) return;
    sectionId = value;
    page = 1;
    await refresh();
  }

  Future<void> selectStatus(String? value) async {
    final normalized = value?.isEmpty == true ? null : value;
    if (status == normalized) return;
    status = normalized;
    page = 1;
    await refresh();
  }

  /// Откладывает сетевой поиск, чтобы ввод не создавал запрос на каждый символ.
  void updateSearch(String value) {
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
      images = const [];
      imagesError = null;
    }
    selectedItem = item;
    notifyListeners();
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
    _searchTimer?.cancel();
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
