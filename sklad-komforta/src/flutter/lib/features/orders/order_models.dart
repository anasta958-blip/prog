import 'package:sklad_komforta_app/features/quotes/quote_models.dart';

/// Комплектация карточки канбана.
///
/// Дерево позиций хранится в моделях редактора КП ([QuoteCategoryDraft] и
/// ниже), поэтому таблица позиций, автопоиск по каталогу и Enter-навигация
/// общие с КП. Настроенные денежные поля сохраняются в values вместе с
/// остальными полями канбана, без отдельных ценовых колонок в контракте API.
final class OrderDocument {
  OrderDocument({
    required this.title,
    required this.clientId,
    required this.executorCompanyId,
    required this.categories,
    this.id,
    this.cardId,
    this.objectType,
    this.managerUserId,
    this.salesHeadUserId,
    this.sourceQuote,
    this.canChangeManager = false,
    this.canManageInvoices = false,
    Set<String>? reorderPositionIds,
    Set<String>? fromQuotePositionIds,
  }) : reorderPositionIds = reorderPositionIds ?? <String>{},
       fromQuotePositionIds = fromQuotePositionIds ?? <String>{};

  String? id;
  String? cardId;

  /// Адрес объекта; совпадает с названием карточки.
  String title;
  String? objectType;
  String clientId;
  String executorCompanyId;

  /// Менеджер — создатель карточки (или менеджер исходного КП).
  String? managerUserId;

  /// РОП — руководитель менеджера по структуре сотрудников.
  String? salesHeadUserId;
  OrderSourceQuote? sourceQuote;

  /// Право менять менеджера и РОП (`orders.manager.change`).
  bool canChangeManager;

  /// Право загружать и удалять счета (`orders.invoices.manage`).
  bool canManageInvoices;
  final List<QuoteCategoryDraft> categories;

  /// Позиции-дозаказ (назначает сервер).
  final Set<String> reorderPositionIds;

  /// Позиции, перенесённые из КП и синхронизируемые повторным переносом.
  final Set<String> fromQuotePositionIds;

  factory OrderDocument.fromJson(Map<String, dynamic> json) {
    final reorder = <String>{};
    final fromQuote = <String>{};
    final categories = ((json['categories'] as List<dynamic>?) ?? const []).map(
      (item) {
        final category = item as Map<String, dynamic>;
        return QuoteCategoryDraft(
          id: category['id'] as String? ?? newQuoteId(),
          catalogCategoryId: category['catalogCategoryId'] as String?,
          name: category['name'] as String? ?? '',
          sections: ((category['sections'] as List<dynamic>?) ?? const []).map((
            sectionItem,
          ) {
            final section = sectionItem as Map<String, dynamic>;
            return QuoteSectionDraft(
              id: section['id'] as String? ?? newQuoteId(),
              catalogSectionId: section['catalogSectionId'] as String?,
              name: section['name'] as String? ?? '',
              positions: ((section['positions'] as List<dynamic>?) ?? const [])
                  .map((positionItem) {
                    final position = positionItem as Map<String, dynamic>;
                    final id = position['id'] as String? ?? newQuoteId();
                    if (position['isReorder'] == true) reorder.add(id);
                    if (position['fromQuote'] == true) {
                      fromQuote.add(id);
                    }
                    final values = Map<String, dynamic>.from(
                      (position['values'] as Map<String, dynamic>?) ?? const {},
                    );
                    return QuotePositionDraft(
                        id: id,
                        catalogItemId: position['catalogItemId'] as String?,
                        name: position['name'] as String? ?? '',
                        marking: position['marking'] as String? ?? '',
                        unit: position['unit'] as String? ?? '',
                        quantity:
                            (position['quantity'] as num?)?.toDouble() ?? 1,
                        basePrice:
                            (values['base_price'] as num?)?.toDouble() ?? 0,
                        purchasePrice: (values['purchase_price'] as num?)
                            ?.toDouble(),
                        markupPercent: (values['markup_value'] as num?)
                            ?.toDouble(),
                        discountPercent: (values['discount_value'] as num?)
                            ?.toDouble(),
                        excludeFromTotals: values['excluded_from_calc'] == true,
                        values: values,
                      )
                      ..configuredLineTotal = (values['line_total'] as num?)
                          ?.toDouble();
                  })
                  .toList(),
            );
          }).toList(),
        );
      },
    ).toList();
    return OrderDocument(
      id: json['id'] as String?,
      cardId: json['cardId'] as String?,
      title: json['title'] as String? ?? '',
      objectType: json['objectType'] as String?,
      clientId: json['clientId'] as String? ?? '',
      executorCompanyId: json['executorCompanyId'] as String? ?? '',
      managerUserId: json['managerUserId'] as String?,
      salesHeadUserId: json['salesHeadUserId'] as String?,
      sourceQuote: json['sourceQuote'] == null
          ? null
          : OrderSourceQuote.fromJson(
              json['sourceQuote'] as Map<String, dynamic>,
            ),
      canChangeManager: json['canChangeManager'] as bool? ?? false,
      canManageInvoices: json['canManageInvoices'] as bool? ?? false,
      categories: categories,
      reorderPositionIds: reorder,
      fromQuotePositionIds: fromQuote,
    );
  }

  /// Команда сохранения (`SaveOrderRequest`).
  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'objectType': (objectType?.trim().isEmpty ?? true)
        ? null
        : objectType!.trim(),
    'clientId': clientId,
    'executorCompanyId': executorCompanyId,
    'managerUserId': managerUserId,
    'salesHeadUserId': salesHeadUserId,
    'categories': [
      for (final category in categories)
        {
          'id': category.id,
          'catalogCategoryId': category.catalogCategoryId,
          'name': category.name.trim(),
          'sections': [
            for (final section in category.sections)
              {
                'id': section.id,
                'catalogSectionId': section.catalogSectionId,
                'name': section.name.trim(),
                'positions': [
                  for (final position in section.positions)
                    {
                      'id': position.id,
                      'catalogItemId': position.catalogItemId,
                      'name': position.name.trim(),
                      'marking': position.marking.trim(),
                      'unit': position.unit.trim(),
                      'quantity': position.quantity,
                      'values': {
                        ...position.values,
                        'base_price':
                            position.manualPrice ?? position.basePrice,
                        'purchase_price': position.purchasePrice,
                        'markup_value': position.markupPercent,
                        'discount_value': position.discountPercent,
                        'excluded_from_calc': position.excludeFromTotals,
                        'line_total': position.lineTotal,
                      },
                    },
                ],
              },
          ],
        },
    ],
  };

  /// Снимок для локального черновика: вместе со служебными полями документа.
  Map<String, dynamic> toSnapshot() => {
    ...toJson(),
    'id': id,
    'cardId': cardId,
    'sourceQuote': sourceQuote?.toJson(),
    'canChangeManager': canChangeManager,
    'canManageInvoices': canManageInvoices,
    'categories': [
      for (final category in (toJson()['categories'] as List<dynamic>))
        {
          ...(category as Map<String, dynamic>),
          'sections': [
            for (final section in (category['sections'] as List<dynamic>))
              {
                ...(section as Map<String, dynamic>),
                'positions': [
                  for (final position
                      in (section['positions'] as List<dynamic>))
                    {
                      ...(position as Map<String, dynamic>),
                      'isReorder': reorderPositionIds.contains(position['id']),
                      'fromQuote': fromQuotePositionIds.contains(
                        position['id'],
                      ),
                    },
                ],
              },
          ],
        },
    ],
  };
}

/// Исходное КП комплектации, созданной переносом.
final class OrderSourceQuote {
  const OrderSourceQuote({
    required this.quoteId,
    required this.boardId,
    required this.cardId,
    required this.cardNumber,
    required this.title,
  });

  final String quoteId;
  final String boardId;
  final String cardId;
  final int cardNumber;
  final String title;

  factory OrderSourceQuote.fromJson(Map<String, dynamic> json) =>
      OrderSourceQuote(
        quoteId: json['quoteId'] as String,
        boardId: json['boardId'] as String,
        cardId: json['cardId'] as String,
        cardNumber: json['cardNumber'] as int,
        title: json['title'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'quoteId': quoteId,
    'boardId': boardId,
    'cardId': cardId,
    'cardNumber': cardNumber,
    'title': title,
  };
}

/// Загруженный PDF-счёт комплектации.
final class OrderInvoice {
  const OrderInvoice({
    required this.id,
    required this.fileName,
    required this.byteSize,
    required this.uploadedAt,
    required this.downloadUrl,
    this.uploadedByName,
  });

  final String id;
  final String fileName;
  final int byteSize;
  final DateTime uploadedAt;
  final String? uploadedByName;

  /// Короткоживущая ссылка на скачивание (около 5 минут).
  final String downloadUrl;

  factory OrderInvoice.fromJson(Map<String, dynamic> json) => OrderInvoice(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    byteSize: json['byteSize'] as int,
    uploadedAt: DateTime.parse(json['uploadedAt'] as String),
    uploadedByName: json['uploadedByName'] as String?,
    downloadUrl: json['downloadUrl'] as String,
  );
}
