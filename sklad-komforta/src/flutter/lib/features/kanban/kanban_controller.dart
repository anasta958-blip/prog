import 'package:flutter/foundation.dart';
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_exception.dart';
import 'package:sklad_komforta_app/features/auth/auth_controller.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_api.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';

/// Состояние выбора и загрузки рабочего канбана без бизнес-данных карточек.
final class KanbanController extends ChangeNotifier {
  KanbanController(
    AppConfig config,
    this._auth, {
    KanbanGateway? gateway,
    this.pageSize = 20,
  }) : _gateway = gateway ?? KanbanApi(config),
       _ownsGateway = gateway == null;

  final AuthController _auth;
  final KanbanGateway _gateway;
  final bool _ownsGateway;
  final int pageSize;

  List<KanbanBoardSummary> boards = const [];
  List<KanbanCardAuthor> cardAuthors = const [];
  KanbanBoard? board;
  String? selectedAuthorUserId;
  bool includeOwnCards = true;

  /// Поиск по названию или номеру карточки; применяется на сервере ко всем
  /// столбцам и архиву, поэтому работает и при большом числе карточек.
  String cardSearch = '';
  int _searchGeneration = 0;
  final Map<String, KanbanCardPage> _columnPages = {};
  final Set<String> _loadingColumns = {};
  final Map<String, KanbanCardPage> _archivePages = {};
  final Set<String> expandedArchives = {};
  bool archiveLoading = false;
  KanbanCardPage? archiveFor(String columnId) => _archivePages[columnId];

  void toggleArchive(String columnId) {
    if (!expandedArchives.remove(columnId)) expandedArchives.add(columnId);
    notifyListeners();
  }

  Future<void> _readArchive(String columnId, {int page = 1}) async {
    final selectedBoard = board;
    if (selectedBoard == null) return;
    var result = await _authorized(
      (token) => _gateway.getCards(
        token,
        selectedBoard.id,
        columnId,
        page: page,
        pageSize: pageSize,
        authorUserId: selectedAuthorUserId,
        includeOwn: includeOwnCards,
        search: cardSearch.isEmpty ? null : cardSearch,
        archived: true,
      ),
    );
    if (result.items.isEmpty && page > 1) {
      result = await _authorized(
        (token) => _gateway.getCards(
          token,
          selectedBoard.id,
          columnId,
          page: 1,
          pageSize: pageSize,
          authorUserId: selectedAuthorUserId,
          includeOwn: includeOwnCards,
          search: cardSearch.isEmpty ? null : cardSearch,
          archived: true,
        ),
      );
    }
    if (board?.id == selectedBoard.id) _archivePages[columnId] = result;
  }

  Future<void> loadArchive(String columnId, {int page = 1}) async {
    if (archiveLoading) return;
    archiveLoading = true;
    notifyListeners();
    try {
      await _readArchive(columnId, page: page);
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось загрузить архив.';
    } finally {
      archiveLoading = false;
      notifyListeners();
    }
  }

  Future<bool> setArchived(KanbanCard card, bool archived) async {
    final selectedBoard = board;
    if (selectedBoard == null || saving || loading) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _authorized(
        (token) =>
            _gateway.setArchived(token, selectedBoard.id, card.id, archived),
      );
      await _reloadColumnSilently(card.columnId);
      await _readArchive(
        card.columnId,
        page: _archivePages[card.columnId]?.page ?? 1,
      );
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось изменить состояние архива. Обновите канбан.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  bool loading = false;
  bool saving = false;
  String? error;

  KanbanCardPage? pageFor(String columnId) => _columnPages[columnId];
  bool isColumnLoading(String columnId) => _loadingColumns.contains(columnId);

  String get authorFilterKey => selectedAuthorUserId == null
      ? 'own'
      : includeOwnCards
      ? 'own:${selectedAuthorUserId!}'
      : 'user:${selectedAuthorUserId!}';

  /// Переупорядочивание внутри столбца разрешено всегда. Между столбцами
  /// клиент использует ту же направленную матрицу переходов, что и backend.
  bool canMoveCard(KanbanCard card, String targetColumnId) {
    final selectedBoard = board;
    if (selectedBoard == null || card.isArchived) return false;
    if (card.columnId == targetColumnId) return true;
    return selectedBoard.transitions.any(
      (transition) =>
          transition.fromColumnId == card.columnId &&
          transition.toColumnId == targetColumnId,
    );
  }

  Future<void> initialize() async {
    if (loading || boards.isNotEmpty) return;
    await reload();
  }

  Future<void> reload() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final initialData = await Future.wait([
        _authorized(_gateway.getBoards),
        _authorized(_gateway.getCardAuthors),
      ]);
      boards = initialData[0] as List<KanbanBoardSummary>;
      cardAuthors = initialData[1] as List<KanbanCardAuthor>;
      if (selectedAuthorUserId != null &&
          !cardAuthors.any((item) => item.userId == selectedAuthorUserId)) {
        selectedAuthorUserId = null;
        includeOwnCards = true;
      }
      if (boards.isEmpty) {
        board = null;
      } else {
        final selectedId = boards.any((item) => item.id == board?.id)
            ? board!.id
            : boards.first.id;
        board = await _authorized(
          (token) => _gateway.getBoard(token, selectedId),
        );
        await _loadAllColumns();
      }
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось загрузить канбаны. Проверьте подключение.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Применяет поиск и заново загружает первые страницы столбцов. Если за время
  /// загрузки запрос поменялся, результат устаревшего поиска не показывается.
  Future<void> setCardSearch(String value) async {
    final normalized = value.trim();
    if (normalized == cardSearch) return;
    cardSearch = normalized;
    final generation = ++_searchGeneration;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadAllColumns();
    } on ApiException catch (exception) {
      if (generation == _searchGeneration) error = exception.message;
    } on Object {
      if (generation == _searchGeneration) {
        error = 'Не удалось выполнить поиск карточек.';
      }
    } finally {
      if (generation == _searchGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Меняет только фильтр авторов и заново загружает первые страницы столбцов.
  Future<void> selectAuthorFilter(String value) async {
    if (loading || value == authorFilterKey) return;
    if (value == 'own') {
      selectedAuthorUserId = null;
      includeOwnCards = true;
    } else {
      final separator = value.indexOf(':');
      if (separator < 0) return;
      final mode = value.substring(0, separator);
      final userId = value.substring(separator + 1);
      if (!cardAuthors.any(
        (item) => !item.isCurrentUser && item.userId == userId,
      )) {
        return;
      }
      selectedAuthorUserId = userId;
      includeOwnCards = mode == 'own';
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadAllColumns();
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось применить фильтр карточек.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectBoard(String boardId) async {
    if (loading || board?.id == boardId) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      board = await _authorized((token) => _gateway.getBoard(token, boardId));
      _columnPages.clear();
      await _loadAllColumns();
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось открыть выбранный канбан.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Загружает конкретную страницу одного столбца, не затрагивая соседние.
  Future<void> loadColumn(String columnId, {int page = 1}) async {
    final selectedBoard = board;
    if (selectedBoard == null || _loadingColumns.contains(columnId)) return;
    _loadingColumns.add(columnId);
    error = null;
    notifyListeners();
    try {
      _columnPages[columnId] = await _authorized(
        (token) => _gateway.getCards(
          token,
          selectedBoard.id,
          columnId,
          page: page,
          pageSize: pageSize,
          authorUserId: selectedAuthorUserId,
          includeOwn: includeOwnCards,
          search: cardSearch.isEmpty ? null : cardSearch,
        ),
      );
    } on ApiException catch (exception) {
      error = exception.message;
    } on Object {
      error = 'Не удалось загрузить карточки столбца.';
    } finally {
      _loadingColumns.remove(columnId);
      notifyListeners();
    }
  }

  /// Создаёт или обновляет карточку, затем перечитывает только её столбец.
  Future<bool> saveCard(KanbanCardDraft draft, {KanbanCard? card}) async {
    final selectedBoard = board;
    if (selectedBoard == null || saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      if (card == null) {
        await _authorized(
          (token) => _gateway.createCard(token, selectedBoard.id, draft),
        );
      } else {
        await _authorized(
          (token) =>
              _gateway.updateCard(token, selectedBoard.id, card.id, draft),
        );
      }
      await _reloadColumnSilently(draft.columnId);
      if (card?.isArchived == true) await _readArchive(draft.columnId);
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось сохранить карточку. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  /// Мягко удаляет карточку и сохраняет текущую страницу, если она ещё существует.
  Future<bool> deleteCard(KanbanCard card) async {
    final selectedBoard = board;
    if (selectedBoard == null || saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _authorized(
        (token) => _gateway.deleteCard(token, selectedBoard.id, card.id),
      );
      final current = _columnPages[card.columnId]?.page ?? 1;
      await _reloadColumnSilently(card.columnId, requestedPage: current);
      if (card.isArchived) {
        await _readArchive(
          card.columnId,
          page: _archivePages[card.columnId]?.page ?? 1,
        );
      }
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось удалить карточку. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  /// Перемещает карточку и перечитывает только исходный и целевой столбцы.
  /// Локальный индекс переводится в индекс полного серверного списка с учётом
  /// открытой страницы целевого столбца.
  Future<bool> moveCard(
    KanbanCard card,
    String targetColumnId,
    int localTargetIndex,
  ) async {
    final selectedBoard = board;
    if (selectedBoard == null || saving || !canMoveCard(card, targetColumnId)) {
      if (selectedBoard != null && !canMoveCard(card, targetColumnId)) {
        error = 'Этот переход запрещён настройками канбана.';
        notifyListeners();
      }
      return false;
    }
    final targetPage = _columnPages[targetColumnId];
    var globalTargetIndex =
        ((targetPage?.page ?? 1) - 1) * pageSize + localTargetIndex;
    if (card.columnId == targetColumnId && targetPage != null) {
      final localSourceIndex = targetPage.items.indexWhere(
        (item) => item.id == card.id,
      );
      if (localSourceIndex >= 0) {
        final globalSourceIndex =
            (targetPage.page - 1) * pageSize + localSourceIndex;
        if (globalTargetIndex > globalSourceIndex) globalTargetIndex--;
      }
    }
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _authorized(
        (token) => _gateway.moveCard(
          token,
          selectedBoard.id,
          card.id,
          targetColumnId,
          globalTargetIndex,
        ),
      );
      final sourcePage = _columnPages[card.columnId]?.page ?? 1;
      final destinationPage = _columnPages[targetColumnId]?.page ?? 1;
      await _reloadColumnSilently(card.columnId, requestedPage: sourcePage);
      if (targetColumnId != card.columnId) {
        await _reloadColumnSilently(
          targetColumnId,
          requestedPage: destinationPage,
        );
      }
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
      return false;
    } on Object {
      error = 'Не удалось переместить карточку. Проверьте подключение.';
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> _loadAllColumns() async {
    final selectedBoard = board;
    if (selectedBoard == null) return;
    _columnPages.clear();
    _archivePages.clear();
    final pages = await Future.wait([
      for (final column in selectedBoard.columns)
        _authorized(
          (token) => _gateway.getCards(
            token,
            selectedBoard.id,
            column.id,
            page: 1,
            pageSize: pageSize,
            authorUserId: selectedAuthorUserId,
            includeOwn: includeOwnCards,
            search: cardSearch.isEmpty ? null : cardSearch,
          ),
        ),
    ]);
    for (var index = 0; index < selectedBoard.columns.length; index++) {
      _columnPages[selectedBoard.columns[index].id] = pages[index];
      await _readArchive(selectedBoard.columns[index].id);
    }
  }

  Future<void> _reloadColumnSilently(
    String columnId, {
    int? requestedPage,
  }) async {
    final selectedBoard = board;
    if (selectedBoard == null) return;
    var targetPage = requestedPage ?? _columnPages[columnId]?.page ?? 1;
    var result = await _authorized(
      (token) => _gateway.getCards(
        token,
        selectedBoard.id,
        columnId,
        page: targetPage,
        pageSize: pageSize,
        authorUserId: selectedAuthorUserId,
        includeOwn: includeOwnCards,
        search: cardSearch.isEmpty ? null : cardSearch,
      ),
    );
    if (result.items.isEmpty && targetPage > 1) {
      targetPage = result.total > 0 ? result.pageCount : 1;
      result = await _authorized(
        (token) => _gateway.getCards(
          token,
          selectedBoard.id,
          columnId,
          page: targetPage,
          pageSize: pageSize,
          authorUserId: selectedAuthorUserId,
          includeOwn: includeOwnCards,
          search: cardSearch.isEmpty ? null : cardSearch,
        ),
      );
    }
    _columnPages[columnId] = result;
  }

  Future<T> _authorized<T>(Future<T> Function(String token) request) =>
      _auth.executeAuthorized(request);

  @override
  void dispose() {
    if (_ownsGateway) _gateway.close();
    super.dispose();
  }
}
