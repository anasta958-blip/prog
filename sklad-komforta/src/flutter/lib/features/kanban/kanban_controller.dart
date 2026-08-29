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
  KanbanBoard? board;
  final Map<String, KanbanCardPage> _columnPages = {};
  final Set<String> _loadingColumns = {};
  bool loading = false;
  bool saving = false;
  String? error;

  KanbanCardPage? pageFor(String columnId) => _columnPages[columnId];
  bool isColumnLoading(String columnId) => _loadingColumns.contains(columnId);

  /// Переупорядочивание внутри столбца разрешено всегда. Между столбцами
  /// клиент использует ту же направленную матрицу переходов, что и backend.
  bool canMoveCard(KanbanCard card, String targetColumnId) {
    final selectedBoard = board;
    if (selectedBoard == null) return false;
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
      boards = await _authorized(_gateway.getBoards);
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
    final pages = await Future.wait([
      for (final column in selectedBoard.columns)
        _authorized(
          (token) => _gateway.getCards(
            token,
            selectedBoard.id,
            column.id,
            page: 1,
            pageSize: pageSize,
          ),
        ),
    ]);
    for (var index = 0; index < selectedBoard.columns.length; index++) {
      _columnPages[selectedBoard.columns[index].id] = pages[index];
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
      ),
    );
    if (result.items.isEmpty && result.total > 0 && targetPage > 1) {
      targetPage = result.pageCount;
      result = await _authorized(
        (token) => _gateway.getCards(
          token,
          selectedBoard.id,
          columnId,
          page: targetPage,
          pageSize: pageSize,
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
