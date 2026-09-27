import 'dart:math';

/// Вид специализированного документа внутри канбан-карточки.
enum QuoteKind {
  quote('quote', 'КП'),
  prequote('prequote', 'ПКП');

  const QuoteKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static QuoteKind fromApi(String value) =>
      value == prequote.apiValue ? prequote : quote;
}

/// Полное изменяемое состояние КП/ПКП.
///
/// UUID создаются на клиенте до сохранения. Благодаря этому выбранный вариант
/// может ссылаться на новый вариант в том же атомарном PUT-запросе.
final class QuoteDraft {
  QuoteDraft({
    required this.kind,
    required this.title,
    required this.clientId,
    required this.executorCompanyId,
    required this.selectionMode,
    required this.proposalTypes,
    this.id,
    this.cardId,
    this.managerUserId,
    this.salesHeadUserId,
    this.additionalInformation = '',
    this.clientSelectedProposalTypeId,
    this.clientSelectionSubmittedAt,
  });

  String? id;
  String? cardId;
  QuoteKind kind;
  String title;
  String clientId;
  String executorCompanyId;
  String? managerUserId;
  String? salesHeadUserId;
  String selectionMode;
  String additionalInformation;
  String? clientSelectedProposalTypeId;
  DateTime? clientSelectionSubmittedAt;
  final List<QuoteProposalTypeDraft> proposalTypes;

  factory QuoteDraft.fromJson(Map<String, dynamic> json) => QuoteDraft(
    id: json['id'] as String?,
    cardId: json['cardId'] as String?,
    kind: QuoteKind.fromApi(json['quoteKind'] as String? ?? 'quote'),
    title: json['title'] as String? ?? '',
    clientId: json['clientId'] as String? ?? '',
    executorCompanyId: json['executorCompanyId'] as String? ?? '',
    managerUserId: json['managerUserId'] as String?,
    salesHeadUserId: json['salesHeadUserId'] as String?,
    selectionMode: json['selectionMode'] as String? ?? 'variant',
    additionalInformation: json['additionalInformation'] as String? ?? '',
    clientSelectedProposalTypeId:
        json['clientSelectedProposalTypeId'] as String?,
    clientSelectionSubmittedAt: json['clientSelectionSubmittedAt'] == null
        ? null
        : DateTime.parse(json['clientSelectionSubmittedAt'] as String),
    proposalTypes: ((json['proposalTypes'] as List<dynamic>?) ?? const [])
        .map(
          (item) =>
              QuoteProposalTypeDraft.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'quoteKind': kind.apiValue,
    'title': title.trim(),
    'clientId': clientId,
    'executorCompanyId': executorCompanyId,
    'managerUserId': managerUserId,
    'salesHeadUserId': salesHeadUserId,
    'selectionMode': selectionMode,
    'additionalInformation': _nullableText(additionalInformation),
    'proposalTypes': proposalTypes.map((item) => item.toJson()).toList(),
  };
}

/// Тип предложения, например «Кондиционеры» или «Бойлеры».
final class QuoteProposalTypeDraft {
  QuoteProposalTypeDraft({
    required this.id,
    required this.name,
    required this.variants,
    this.selectedVariantId,
    this.selectedByClient = false,
  });

  final String id;
  String name;
  String? selectedVariantId;
  bool selectedByClient;
  final List<QuoteVariantDraft> variants;

  factory QuoteProposalTypeDraft.create({
    String name = 'Основное предложение',
    double? initialVatRate,
  }) {
    final variant = QuoteVariantDraft.create(vatRate: initialVatRate);
    return QuoteProposalTypeDraft(
      id: newQuoteId(),
      name: name,
      variants: [variant],
      selectedVariantId: variant.id,
    );
  }

  factory QuoteProposalTypeDraft.fromJson(Map<String, dynamic> json) =>
      QuoteProposalTypeDraft(
        id: json['id'] as String? ?? newQuoteId(),
        name: json['name'] as String? ?? '',
        selectedVariantId: json['selectedVariantId'] as String?,
        selectedByClient: json['selectedByClient'] as bool? ?? false,
        variants: ((json['variants'] as List<dynamic>?) ?? const [])
            .map(
              (item) =>
                  QuoteVariantDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name.trim(),
    'selectedVariantId': selectedVariantId,
    'variants': variants.map((item) => item.toJson()).toList(),
  };

  double get clientTotal => variants
      .fold(0.0, (total, variant) => total + variant.clientTotal)
      .roundMoney();

  QuoteSystemSummary get systemSummary => QuoteSystemSummary(
    subtotal: clientTotal,
    purchase: purchaseTotal,
    vat: vatAmount,
  );

  double get purchaseTotal => variants
      .fold(0.0, (total, variant) => total + variant.purchaseTotal)
      .roundMoney();

  double get margin => (clientTotal - purchaseTotal).roundMoney();

  double get marginPercent =>
      purchaseTotal <= 0 ? 0 : margin / purchaseTotal * 100;

  double get vatAmount => variants
      .fold(0.0, (total, variant) => total + variant.vatAmount)
      .roundMoney();

  double get totalWithVat => (clientTotal + vatAmount).roundMoney();
}

/// Вариант предложения с собственной ставкой НДС и наполнением.
final class QuoteVariantDraft {
  QuoteVariantDraft({
    required this.id,
    required this.name,
    required this.categories,
    this.subtitle = '',
    this.vatRate,
  });

  final String id;
  String name;
  String subtitle;
  double? vatRate;
  final List<QuoteCategoryDraft> categories;

  factory QuoteVariantDraft.create({
    String name = 'Бюджетный',
    double? vatRate,
  }) => QuoteVariantDraft(
    id: newQuoteId(),
    name: name,
    categories: [],
    vatRate: vatRate,
  );

  factory QuoteVariantDraft.fromJson(Map<String, dynamic> json) =>
      QuoteVariantDraft(
        id: json['id'] as String? ?? newQuoteId(),
        name: json['name'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        vatRate: _number(json['vatRate']),
        categories: ((json['categories'] as List<dynamic>?) ?? const [])
            .map(
              (item) =>
                  QuoteCategoryDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name.trim(),
    'subtitle': _nullableText(subtitle),
    'vatRate': vatRate,
    'categories': categories.map((item) => item.toJson()).toList(),
  };

  Iterable<QuotePositionDraft> get positions sync* {
    for (final category in categories) {
      for (final section in category.sections) {
        yield* section.positions;
      }
    }
  }

  double get clientTotal => positions
      .where((position) => !position.excludeFromTotals)
      .fold(0.0, (total, position) => total + position.lineTotal)
      .roundMoney();

  QuoteSystemSummary get systemSummary => QuoteSystemSummary(
    subtotal: clientTotal,
    purchase: purchaseTotal,
    vat: vatAmount,
  );

  double get purchaseTotal => positions
      .where((position) => !position.excludeFromTotals)
      .fold(
        0.0,
        (total, position) =>
            total + (position.purchasePrice ?? 0) * position.quantity,
      )
      .roundMoney();

  double get margin => (clientTotal - purchaseTotal).roundMoney();

  double get marginPercent =>
      purchaseTotal <= 0 ? 0 : margin / purchaseTotal * 100;

  double get vatAmount =>
      vatRate == null ? 0 : (clientTotal * vatRate! / 100).roundMoney();

  double get totalWithVat => (clientTotal + vatAmount).roundMoney();
}

/// Категория каталога, добавленная в конкретный вариант.
final class QuoteCategoryDraft {
  QuoteCategoryDraft({
    required this.id,
    required this.name,
    required this.sections,
    this.catalogCategoryId,
  });

  final String id;
  String? catalogCategoryId;
  String name;
  final List<QuoteSectionDraft> sections;

  factory QuoteCategoryDraft.fromJson(Map<String, dynamic> json) =>
      QuoteCategoryDraft(
        id: json['id'] as String? ?? newQuoteId(),
        catalogCategoryId: json['catalogCategoryId'] as String?,
        name: json['name'] as String? ?? '',
        sections: ((json['sections'] as List<dynamic>?) ?? const [])
            .map(
              (item) =>
                  QuoteSectionDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'catalogCategoryId': catalogCategoryId,
    'name': name.trim(),
    'sections': sections.map((item) => item.toJson()).toList(),
  };

  double get clientTotal => sections
      .fold(0.0, (total, section) => total + section.clientTotal)
      .roundMoney();

  double get purchaseTotal => sections
      .fold(0.0, (total, section) => total + section.purchaseTotal)
      .roundMoney();
}

/// Раздел с локальными массовыми настройками и строками позиций.
final class QuoteSectionDraft {
  QuoteSectionDraft({
    required this.id,
    required this.name,
    required this.positions,
    this.catalogSectionId,
    this.markupPercent,
    this.discountPercent,
  });

  final String id;
  String? catalogSectionId;
  String name;
  double? markupPercent;
  double? discountPercent;
  final List<QuotePositionDraft> positions;

  factory QuoteSectionDraft.fromJson(Map<String, dynamic> json) =>
      QuoteSectionDraft(
        id: json['id'] as String? ?? newQuoteId(),
        catalogSectionId: json['catalogSectionId'] as String?,
        name: json['name'] as String? ?? '',
        markupPercent: _number(json['markupPercent']),
        discountPercent: _number(json['discountPercent']),
        positions: ((json['positions'] as List<dynamic>?) ?? const [])
            .map(
              (item) =>
                  QuotePositionDraft.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'catalogSectionId': catalogSectionId,
    'name': name.trim(),
    'markupPercent': markupPercent,
    'discountPercent': discountPercent,
    'positions': positions.map((item) => item.toJson()).toList(),
  };

  double get clientTotal => positions
      .where((position) => !position.excludeFromTotals)
      .fold(0.0, (total, position) => total + position.lineTotal)
      .roundMoney();

  double get purchaseTotal => positions
      .where((position) => !position.excludeFromTotals)
      .fold(
        0.0,
        (total, position) =>
            total + (position.purchasePrice ?? 0) * position.quantity,
      )
      .roundMoney();
}

/// Редактируемая строка варианта. Сумма вычисляется локально для мгновенного UI,
/// но сервер при сохранении обязательно пересчитывает её повторно.
final class QuotePositionDraft {
  QuotePositionDraft({
    required this.id,
    required this.name,
    required this.marking,
    required this.unit,
    required this.quantity,
    required this.basePrice,
    required this.values,
    this.catalogItemId,
    this.purchasePrice,
    this.manualPrice,
    this.markupPercent,
    this.discountPercent,
    this.excludeFromTotals = false,
  });

  final String id;
  String? catalogItemId;
  String name;
  String marking;
  String unit;
  double quantity;
  double? purchasePrice;
  double basePrice;
  double? manualPrice;
  double? markupPercent;
  double? discountPercent;
  bool excludeFromTotals;
  final Map<String, dynamic> values;
  bool selected = false;
  double? configuredLineTotal;
  final Set<String> hiddenFieldCodes = <String>{};

  factory QuotePositionDraft.fromJson(Map<String, dynamic> json) =>
      QuotePositionDraft(
        id: json['id'] as String? ?? newQuoteId(),
        catalogItemId: json['catalogItemId'] as String?,
        name: json['name'] as String? ?? '',
        marking: json['marking'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        quantity: _number(json['quantity']) ?? 1,
        purchasePrice: _number(json['purchasePrice']),
        basePrice: _number(json['basePrice']) ?? 0,
        manualPrice: _number(json['manualPrice']),
        markupPercent: _number(json['markupPercent']),
        discountPercent: _number(json['discountPercent']),
        excludeFromTotals: json['excludeFromTotals'] as bool? ?? false,
        values: Map<String, dynamic>.from(
          (json['values'] as Map<String, dynamic>?) ?? const {},
        ),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'catalogItemId': catalogItemId,
    'name': name.trim(),
    'marking': marking.trim(),
    'unit': unit.trim(),
    'quantity': quantity,
    'purchasePrice': purchasePrice,
    'basePrice': basePrice,
    'manualPrice': manualPrice,
    'markupPercent': markupPercent,
    'discountPercent': discountPercent,
    'excludeFromTotals': excludeFromTotals,
    'values': values,
  };

  double get _calculatedUnitPrice {
    final source = manualPrice ?? basePrice;
    final withMarkup = source * (1 + (markupPercent ?? 0) / 100);
    return withMarkup * (1 - (discountPercent ?? 0) / 100);
  }

  double get unitPrice => _calculatedUnitPrice.roundMoney();

  bool get hasValidCalculatedPrice => configuredLineTotal != null
      ? configuredLineTotal! >= 0
      : _calculatedUnitPrice >= 0;

  // The backend rounds the final line independently from the displayed unit
  // price. Multiplying an already rounded unit price causes cent differences.
  double get legacyLineTotal => (_calculatedUnitPrice * quantity).roundMoney();

  double get lineTotal => configuredLineTotal ?? legacyLineTotal;
}

/// Editor summary using the same included line totals as sections and categories.
final class QuoteSystemSummary {
  const QuoteSystemSummary({
    required this.subtotal,
    required this.purchase,
    required this.vat,
  });
  final double subtotal;
  final double purchase;
  final double vat;
  double get margin => (subtotal - purchase).roundMoney();
  double get marginPercent => purchase <= 0 ? 0 : margin / purchase * 100;
  double get total => (subtotal + vat).roundMoney();
}

double? _number(dynamic value) => value is num ? value.toDouble() : null;

String? _nullableText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

extension on double {
  double roundMoney() => (this * 100).round() / 100;
}

/// Генерирует RFC 4122 UUID v4 без новой зависимости пакета.
String newQuoteId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
