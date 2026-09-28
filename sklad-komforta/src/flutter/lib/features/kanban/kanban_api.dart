import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';
import 'package:sklad_komforta_app/features/kanban/kanban_models.dart';

/// Заменяемый транспорт рабочего канбана для тестов контроллера.
abstract interface class KanbanGateway {
  Future<List<KanbanBoardSummary>> getBoards(String accessToken);
  Future<List<KanbanCardAuthor>> getCardAuthors(String accessToken);
  Future<KanbanBoard> getBoard(String accessToken, String boardId);
  Future<KanbanCardPage> getCards(
    String accessToken,
    String boardId,
    String columnId, {
    required int page,
    required int pageSize,
    String? authorUserId,
    bool includeOwn = true,
    bool archived = false,
  });
  Future<KanbanCard> createCard(
    String accessToken,
    String boardId,
    KanbanCardDraft draft,
  );
  Future<KanbanCard> updateCard(
    String accessToken,
    String boardId,
    String cardId,
    KanbanCardDraft draft,
  );
  Future<KanbanCard> moveCard(
    String accessToken,
    String boardId,
    String cardId,
    String targetColumnId,
    int targetIndex,
  );
  Future<void> deleteCard(String accessToken, String boardId, String cardId);
  Future<void> setArchived(
    String accessToken,
    String boardId,
    String cardId,
    bool archived,
  );
  void close();
}

/// REST-клиент read-only части пространства канбанов.
final class KanbanApi implements KanbanGateway {
  KanbanApi(this._config) : _client = createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  @override
  Future<List<KanbanBoardSummary>> getBoards(String accessToken) async {
    final data = await _send('GET', '/kanbans/', accessToken) as List<dynamic>;
    return data
        .map(
          (item) => KanbanBoardSummary.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<List<KanbanCardAuthor>> getCardAuthors(String accessToken) async {
    final data =
        await _send('GET', '/kanbans/card-authors', accessToken)
            as List<dynamic>;
    return data
        .map((item) => KanbanCardAuthor.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<KanbanBoard> getBoard(String accessToken, String boardId) async =>
      KanbanBoard.fromJson(
        await _send(
              'GET',
              '/kanbans/${Uri.encodeComponent(boardId)}',
              accessToken,
            )
            as Map<String, dynamic>,
      );

  @override
  Future<KanbanCardPage> getCards(
    String accessToken,
    String boardId,
    String columnId, {
    required int page,
    required int pageSize,
    String? authorUserId,
    bool includeOwn = true,
    bool archived = false,
  }) async => KanbanCardPage.fromJson(
    await _send(
          'GET',
          '/kanbans/${Uri.encodeComponent(boardId)}/cards',
          accessToken,
          query: {
            'columnId': columnId,
            'archived': '$archived',
            'page': '$page',
            'pageSize': '$pageSize',
            'authorUserId': ?authorUserId,
            if (authorUserId != null) 'includeOwn': '$includeOwn',
          },
        )
        as Map<String, dynamic>,
  );

  @override
  Future<KanbanCard> createCard(
    String accessToken,
    String boardId,
    KanbanCardDraft draft,
  ) async => KanbanCard.fromJson(
    await _send(
          'POST',
          '/kanbans/${Uri.encodeComponent(boardId)}/cards',
          accessToken,
          body: draft.toJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<KanbanCard> updateCard(
    String accessToken,
    String boardId,
    String cardId,
    KanbanCardDraft draft,
  ) async => KanbanCard.fromJson(
    await _send(
          'PUT',
          '/kanbans/${Uri.encodeComponent(boardId)}/cards/${Uri.encodeComponent(cardId)}',
          accessToken,
          body: draft.toJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<KanbanCard> moveCard(
    String accessToken,
    String boardId,
    String cardId,
    String targetColumnId,
    int targetIndex,
  ) async => KanbanCard.fromJson(
    await _send(
          'POST',
          '/kanbans/${Uri.encodeComponent(boardId)}/cards/${Uri.encodeComponent(cardId)}/move',
          accessToken,
          body: {'targetColumnId': targetColumnId, 'targetIndex': targetIndex},
        )
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteCard(
    String accessToken,
    String boardId,
    String cardId,
  ) async {
    await _send(
      'DELETE',
      '/kanbans/${Uri.encodeComponent(boardId)}/cards/${Uri.encodeComponent(cardId)}',
      accessToken,
    );
  }

  @override
  Future<void> setArchived(
    String accessToken,
    String boardId,
    String cardId,
    bool archived,
  ) async {
    await _send(
      'POST',
      '/kanbans/${Uri.encodeComponent(boardId)}/cards/${Uri.encodeComponent(cardId)}/archive',
      accessToken,
      body: {'archived': archived},
    );
  }

  Future<dynamic> _send(
    String method,
    String path,
    String accessToken, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(
      '${_config.apiBaseUrl}$path',
    ).replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    return decodeApiResponse(response);
  }

  @override
  void close() => _client.close();
}
