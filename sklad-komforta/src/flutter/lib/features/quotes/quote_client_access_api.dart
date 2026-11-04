import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sklad_komforta_app/core/config/app_config.dart';
import 'package:sklad_komforta_app/core/network/api_response_decoder.dart';
import 'package:sklad_komforta_app/core/network/http_client_factory.dart'
    if (dart.library.js_interop) 'package:sklad_komforta_app/core/network/http_client_factory_web.dart';

/// REST-клиент отдельного парольного доступа внешнего клиента.
final class QuoteClientAccessApi {
  QuoteClientAccessApi(this._config, {http.Client? client})
    : _client = client ?? createPlatformHttpClient();

  final AppConfig _config;
  final http.Client _client;

  String _managerPath(String boardId, String cardId) =>
      '${_config.apiBaseUrl}/kanbans/${Uri.encodeComponent(boardId)}/cards/'
      '${Uri.encodeComponent(cardId)}/quote/client-access';

  Future<QuoteClientAccessStatus> getLinkStatus(
    String employeeToken,
    String boardId,
    String cardId,
  ) async {
    final response = await _client.get(
      Uri.parse(_managerPath(boardId, cardId)),
      headers: {
        'Authorization': 'Bearer $employeeToken',
        'Accept': 'application/json',
      },
    );
    return QuoteClientAccessStatus.fromJson(
      decodeApiResponse(response) as Map<String, dynamic>,
    );
  }

  Future<CreatedQuoteClientAccess> createLink(
    String employeeToken,
    String boardId,
    String cardId, {
    int lifetimeDays = 7,
  }) async {
    final response = await _client.post(
      Uri.parse(_managerPath(boardId, cardId)),
      headers: {
        'Authorization': 'Bearer $employeeToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({'lifetimeDays': lifetimeDays}),
    );
    return CreatedQuoteClientAccess.fromJson(
      decodeApiResponse(response) as Map<String, dynamic>,
    );
  }

  Future<QuoteClientAccessStatus> extendLink(
    String employeeToken,
    String boardId,
    String cardId,
    int days,
  ) async {
    final response = await _client.post(
      Uri.parse('${_managerPath(boardId, cardId)}/extend'),
      headers: {
        'Authorization': 'Bearer $employeeToken',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({'additionalDays': days}),
    );
    return QuoteClientAccessStatus.fromJson(
      decodeApiResponse(response) as Map<String, dynamic>,
    );
  }

  Future<void> revokeLink(
    String employeeToken,
    String boardId,
    String cardId,
  ) async {
    final response = await _client.delete(
      Uri.parse(_managerPath(boardId, cardId)),
      headers: {
        'Authorization': 'Bearer $employeeToken',
        'Accept': 'application/json',
      },
    );
    decodeApiResponse(response);
  }

  Future<QuoteClientLoginResult> login(
    String accessToken,
    String password,
  ) async {
    final response = await _client.post(
      Uri.parse('${_config.apiBaseUrl}/client/quotes/login'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({'accessToken': accessToken, 'password': password}),
    );
    return QuoteClientLoginResult.fromJson(
      decodeApiResponse(response) as Map<String, dynamic>,
    );
  }

  Future<QuoteClientView> submitSelection(
    String sessionToken, {
    String? proposalTypeId,
    required Map<String, String> variants,
  }) async {
    final response = await _client.put(
      Uri.parse('${_config.apiBaseUrl}/client/quotes/current/selection'),
      headers: {
        'X-Quote-Client-Session': sessionToken,
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({
        'proposalTypeId': proposalTypeId,
        'variants': variants.entries
            .map(
              (entry) => {
                'proposalTypeId': entry.key,
                'variantId': entry.value,
              },
            )
            .toList(),
      }),
    );
    return QuoteClientView.fromJson(
      decodeApiResponse(response) as Map<String, dynamic>,
    );
  }

  void close() => _client.close();
}

final class QuoteClientAccessStatus {
  const QuoteClientAccessStatus({
    required this.isActive,
    required this.createdAt,
    required this.expiresAt,
    required this.lastAccessedAt,
    this.accessToken,
    this.password,
  });

  final bool isActive;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? lastAccessedAt;

  /// Токен и пароль действующей ссылки для повторного копирования. Пустые,
  /// если ссылки нет или она создана до появления зашифрованного хранения.
  final String? accessToken;
  final String? password;

  /// Секреты действующей ссылки в том же виде, что и сразу после создания.
  CreatedQuoteClientAccess? get secrets =>
      isActive && accessToken != null && password != null && expiresAt != null
      ? CreatedQuoteClientAccess(
          accessToken: accessToken!,
          password: password!,
          expiresAt: expiresAt!,
        )
      : null;

  factory QuoteClientAccessStatus.fromJson(Map<String, dynamic> json) =>
      QuoteClientAccessStatus(
        isActive: json['isActive'] as bool? ?? false,
        createdAt: _date(json['createdAt']),
        expiresAt: _date(json['expiresAt']),
        lastAccessedAt: _date(json['lastAccessedAt']),
        accessToken: json['accessToken'] as String?,
        password: json['password'] as String?,
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.parse(value) : null;
}

final class CreatedQuoteClientAccess {
  const CreatedQuoteClientAccess({
    required this.accessToken,
    required this.password,
    required this.expiresAt,
  });

  final String accessToken;
  final String password;
  final DateTime expiresAt;

  factory CreatedQuoteClientAccess.fromJson(Map<String, dynamic> json) =>
      CreatedQuoteClientAccess(
        accessToken: json['accessToken'] as String,
        password: json['password'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}

final class QuoteClientLoginResult {
  const QuoteClientLoginResult({
    required this.sessionToken,
    required this.expiresAt,
    required this.quote,
  });

  final String sessionToken;
  final DateTime expiresAt;
  final QuoteClientView quote;

  factory QuoteClientLoginResult.fromJson(Map<String, dynamic> json) =>
      QuoteClientLoginResult(
        sessionToken: json['sessionToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        quote: QuoteClientView.fromJson(json['quote'] as Map<String, dynamic>),
      );
}

final class QuoteClientView {
  const QuoteClientView({
    required this.id,
    required this.kind,
    required this.title,
    required this.executorName,
    required this.selectionMode,
    required this.additionalInformation,
    required this.selectedProposalTypeId,
    required this.proposalTypes,
    required this.selectionSubmittedAt,
    required this.updatedAt,
    this.clientName,
  });

  final String id;
  final String kind;
  final String title;
  final String executorName;

  /// Заказчик для шапки документа; отсутствует у старых версий API.
  final String? clientName;
  final String selectionMode;
  final String? additionalInformation;
  final String? selectedProposalTypeId;
  final List<QuoteClientProposalType> proposalTypes;
  final DateTime? selectionSubmittedAt;
  final DateTime updatedAt;

  factory QuoteClientView.fromJson(Map<String, dynamic> json) =>
      QuoteClientView(
        id: json['id'] as String,
        kind: json['quoteKind'] as String,
        title: json['title'] as String,
        executorName: json['executorName'] as String,
        clientName: json['clientName'] as String?,
        selectionMode: json['selectionMode'] as String? ?? 'variant',
        additionalInformation: json['additionalInformation'] as String?,
        selectedProposalTypeId: json['selectedProposalTypeId'] as String?,
        proposalTypes: (json['proposalTypes'] as List<dynamic>? ?? const [])
            .map(
              (item) => QuoteClientProposalType.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        selectionSubmittedAt: json['selectionSubmittedAt'] == null
            ? null
            : DateTime.parse(json['selectionSubmittedAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

final class QuoteClientProposalType {
  const QuoteClientProposalType({
    required this.id,
    required this.name,
    required this.selectedVariantId,
    required this.variants,
  });

  final String id;
  final String name;
  final String? selectedVariantId;
  final List<QuoteClientVariant> variants;

  factory QuoteClientProposalType.fromJson(Map<String, dynamic> json) =>
      QuoteClientProposalType(
        id: json['id'] as String,
        name: json['name'] as String,
        selectedVariantId: json['selectedVariantId'] as String?,
        variants: (json['variants'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  QuoteClientVariant.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}

final class QuoteClientVariant {
  const QuoteClientVariant({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.vatRate,
    required this.subtotal,
    required this.vatAmount,
    required this.total,
    required this.categories,
  });

  final String id;
  final String name;
  final String? subtitle;
  final double? vatRate;
  final double subtotal;
  final double vatAmount;
  final double total;
  final List<QuoteClientCategory> categories;

  factory QuoteClientVariant.fromJson(Map<String, dynamic> json) =>
      QuoteClientVariant(
        id: json['id'] as String,
        name: json['name'] as String,
        subtitle: json['subtitle'] as String?,
        vatRate: (json['vatRate'] as num?)?.toDouble(),
        subtotal: (json['subtotal'] as num).toDouble(),
        vatAmount: (json['vatAmount'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
        categories: (json['categories'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  QuoteClientCategory.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}

final class QuoteClientCategory {
  const QuoteClientCategory({required this.name, required this.sections});
  final String name;
  final List<QuoteClientSection> sections;

  factory QuoteClientCategory.fromJson(Map<String, dynamic> json) =>
      QuoteClientCategory(
        name: json['name'] as String,
        sections: (json['sections'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  QuoteClientSection.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}

final class QuoteClientSection {
  const QuoteClientSection({
    required this.name,
    required this.positions,
    this.columns,
    this.total,
  });
  final String name;
  final List<QuoteClientPosition> positions;
  final List<String>? columns;
  final double? total;

  factory QuoteClientSection.fromJson(Map<String, dynamic> json) =>
      QuoteClientSection(
        columns: (json['columns'] as List?)
            ?.map((item) => (item as Map<String, dynamic>)['label'] as String)
            .toList(),
        total: (json['total'] as num?)?.toDouble(),
        name: json['name'] as String,
        positions: (json['positions'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  QuoteClientPosition.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}

final class QuoteClientPosition {
  const QuoteClientPosition({
    required this.name,
    required this.marking,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.cells,
  });
  final String name;
  final String marking;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final List<String>? cells;

  factory QuoteClientPosition.fromJson(Map<String, dynamic> json) =>
      QuoteClientPosition(
        cells: (json['cells'] as List?)?.cast<String>(),
        name: json['name'] as String,
        marking: json['marking'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        quantity: (json['quantity'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
        lineTotal: (json['lineTotal'] as num).toDouble(),
      );
}
