import 'package:sklad_komforta_app/core/models/workflow_specialization.dart';

/// Краткая запись в переключателе настроенных канбанов.
final class KanbanBoardSummary {
  const KanbanBoardSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.sortOrder,
    required this.columnCount,
    this.specialization = WorkflowSpecialization.standard,
  });

  final String id;
  final String code;
  final String name;
  final int sortOrder;
  final int columnCount;
  final WorkflowSpecialization specialization;

  factory KanbanBoardSummary.fromJson(Map<String, dynamic> json) =>
      KanbanBoardSummary(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        sortOrder: json['sortOrder'] as int,
        columnCount: json['columnCount'] as int,
        specialization: WorkflowSpecialization.fromApi(
          json['specialization'] as String?,
        ),
      );
}

/// Пользователь, карточки которого разрешено включать в текущую выборку.
final class KanbanCardAuthor {
  const KanbanCardAuthor({
    required this.userId,
    required this.displayName,
    required this.isCurrentUser,
  });

  final String userId;
  final String displayName;
  final bool isCurrentUser;

  factory KanbanCardAuthor.fromJson(Map<String, dynamic> json) =>
      KanbanCardAuthor(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        isCurrentUser: json['isCurrentUser'] as bool? ?? false,
      );
}

/// Один столбец рабочего канбана.
final class KanbanColumn {
  const KanbanColumn({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
    this.creationActions = const [],
    this.transferTo,
    this.reorderFrom = false,
  });

  final String id;
  final String name;
  final String color;
  final int sortOrder;
  final List<WorkflowCreationAction> creationActions;

  /// Столбец-триггер: попавшая сюда карточка переносится в другой канбан
  /// (КП → комплектация или обратно).
  final KanbanColumnTransfer? transferTo;

  /// Канбан комплектации: с этого столбца (и правее) новые позиции — дозаказ.
  final bool reorderFrom;

  factory KanbanColumn.fromJson(Map<String, dynamic> json) => KanbanColumn(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
    sortOrder: json['sortOrder'] as int,
    creationActions: ((json['creationActions'] as List<dynamic>?) ?? const [])
        .map((item) => WorkflowCreationAction.tryFromApi('$item'))
        .whereType<WorkflowCreationAction>()
        .toList(growable: false),
    transferTo: json['transferTo'] == null
        ? null
        : KanbanColumnTransfer.fromJson(
            json['transferTo'] as Map<String, dynamic>,
          ),
    reorderFrom: json['reorderFrom'] as bool? ?? false,
  );
}

/// Цель переноса из столбца-триггера.
final class KanbanColumnTransfer {
  const KanbanColumnTransfer({
    required this.boardId,
    required this.boardName,
    required this.columnId,
    required this.columnName,
  });

  final String boardId;
  final String boardName;
  final String columnId;
  final String columnName;

  factory KanbanColumnTransfer.fromJson(Map<String, dynamic> json) =>
      KanbanColumnTransfer(
        boardId: json['boardId'] as String,
        boardName: json['boardName'] as String,
        columnId: json['columnId'] as String,
        columnName: json['columnName'] as String,
      );
}

/// Разрешённый переход, который будет использован модулем карточек.
final class KanbanTransition {
  const KanbanTransition({
    required this.fromColumnId,
    required this.toColumnId,
  });

  final String fromColumnId;
  final String toColumnId;

  factory KanbanTransition.fromJson(Map<String, dynamic> json) =>
      KanbanTransition(
        fromColumnId: json['fromColumnId'] as String,
        toColumnId: json['toColumnId'] as String,
      );
}

/// Одно значение справочника динамического поля карточки.
final class KanbanDictionaryOption {
  const KanbanDictionaryOption({
    required this.id,
    required this.value,
    required this.sortOrder,
  });

  final String id;
  final String value;
  final int sortOrder;

  factory KanbanDictionaryOption.fromJson(Map<String, dynamic> json) =>
      KanbanDictionaryOption(
        id: json['id'] as String,
        value: json['value'] as String,
        sortOrder: json['sortOrder'] as int,
      );
}

/// Настроенное поле карточки внутри конкретной категории канбана.
final class KanbanField {
  const KanbanField({
    required this.code,
    required this.label,
    required this.fieldType,
    required this.isRequired,
    required this.sortOrder,
    required this.options,
    this.dictionaryCode,
  });

  final String code;
  final String label;
  final String fieldType;
  final bool isRequired;
  final int sortOrder;
  final String? dictionaryCode;
  final List<KanbanDictionaryOption> options;

  factory KanbanField.fromJson(Map<String, dynamic> json) => KanbanField(
    code: json['code'] as String,
    label: json['label'] as String,
    fieldType: json['fieldType'] as String,
    isRequired: json['isRequired'] as bool,
    sortOrder: json['sortOrder'] as int,
    dictionaryCode: json['dictionaryCode'] as String?,
    options: ((json['options'] as List<dynamic>?) ?? const [])
        .map(
          (item) =>
              KanbanDictionaryOption.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false),
  );
}

/// Раздел каталога, доступный выбранной категории карточки.
final class KanbanSection {
  const KanbanSection({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int sortOrder;

  factory KanbanSection.fromJson(Map<String, dynamic> json) => KanbanSection(
    id: json['id'] as String,
    name: json['name'] as String,
    sortOrder: json['sortOrder'] as int,
  );
}

/// Категория и порядок полей карточки внутри канбана.
final class KanbanCategory {
  const KanbanCategory({
    required this.categoryId,
    required this.name,
    required this.sortOrder,
    required this.fields,
    this.sections = const [],
    this.supplierFilterFieldCode,
    this.documentFields,
  });

  final String categoryId;
  final String name;
  final int sortOrder;
  final List<KanbanField> fields;
  final List<KanbanSection> sections;
  final String? supplierFilterFieldCode;
  final List<KanbanField>? documentFields;

  factory KanbanCategory.fromJson(Map<String, dynamic> json) => KanbanCategory(
    categoryId: json['categoryId'] as String,
    name: json['name'] as String,
    sortOrder: json['sortOrder'] as int,
    supplierFilterFieldCode: json['supplierFilterFieldCode'] as String?,
    documentFields: (json['documentFields'] as List?)
        ?.map((item) => KanbanField.fromJson(item as Map<String, dynamic>))
        .toList(),
    sections: ((json['sections'] as List<dynamic>?) ?? const [])
        .map((item) => KanbanSection.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    fields: (json['fields'] as List<dynamic>)
        .map((item) => KanbanField.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}

/// Одна сохранённая универсальная карточка канбана.
final class KanbanCard {
  const KanbanCard({
    required this.id,
    required this.number,
    required this.workflowId,
    required this.columnId,
    this.categoryId,
    this.sectionId,
    required this.title,
    required this.values,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.createdByName,
    this.updatedBy,
    this.updatedByName,
    this.isArchived = false,
    this.movedBy,
    this.movedByName,
    this.movedAt,
    this.createdByRole,
    this.updatedByRole,
    this.movedByRole,
    this.quote,
    this.order,
    this.linkedCards = const [],
  });

  final String id;
  final int number;
  final String workflowId;
  final String columnId;
  final String? categoryId;
  final String? sectionId;
  final String title;
  final Map<String, dynamic> values;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final String? updatedBy;
  final String? updatedByName;
  final DateTime updatedAt;
  final bool isArchived;

  /// Кто и когда последним перенёс карточку в другую колонку.
  final String? movedBy;
  final String? movedByName;
  final DateTime? movedAt;

  /// Роли пользователей в организации — для подписи «Имя · Роль».
  final String? createdByRole;
  final String? updatedByRole;
  final String? movedByRole;

  /// Сводка предложения; есть только у карточек КП/ПКП.
  final KanbanQuoteSummary? quote;

  /// Сводка комплектации; есть только у карточек канбана комплектации.
  final KanbanOrderSummary? order;

  /// Карточки того же объекта в других канбанах (КП ↔ комплектация). Сервер
  /// заполняет их, только пока карточка стоит в столбце-триггере переноса.
  final List<KanbanLinkedCard> linkedCards;

  factory KanbanCard.fromJson(Map<String, dynamic> json) => KanbanCard(
    id: json['id'] as String,
    number: json['number'] as int,
    workflowId: json['workflowId'] as String,
    columnId: json['columnId'] as String,
    categoryId: json['categoryId'] as String?,
    sectionId: json['sectionId'] as String?,
    title: json['title'] as String,
    values: Map<String, dynamic>.from(
      (json['values'] as Map<String, dynamic>?) ?? const {},
    ),
    createdBy: json['createdBy'] as String?,
    createdByName: json['createdByName'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedBy: json['updatedBy'] as String?,
    updatedByName: json['updatedByName'] as String?,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isArchived: json['isArchived'] as bool? ?? false,
    movedBy: json['movedBy'] as String?,
    movedByName: json['movedByName'] as String?,
    movedAt: json['movedAt'] == null
        ? null
        : DateTime.parse(json['movedAt'] as String),
    createdByRole: json['createdByRole'] as String?,
    updatedByRole: json['updatedByRole'] as String?,
    movedByRole: json['movedByRole'] as String?,
    quote: json['quote'] == null
        ? null
        : KanbanQuoteSummary.fromJson(json['quote'] as Map<String, dynamic>),
    order: json['order'] == null
        ? null
        : KanbanOrderSummary.fromJson(json['order'] as Map<String, dynamic>),
    linkedCards: ((json['linkedCards'] as List<dynamic>?) ?? const [])
        .map((item) => KanbanLinkedCard.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}

/// Сводка комплектации на карточке канбана.
final class KanbanOrderSummary {
  const KanbanOrderSummary({
    this.clientName,
    this.executorName,
    this.managerName,
    this.objectType,
    required this.positionCount,
    required this.reorderCount,
    required this.invoiceCount,
    this.sourceQuoteNumber,
  });

  final String? clientName;
  final String? executorName;
  final String? managerName;
  final String? objectType;
  final int positionCount;

  /// Из позиций — дозаказ.
  final int reorderCount;
  final int invoiceCount;

  /// Номер карточки исходного КП, если комплектация создана переносом.
  final int? sourceQuoteNumber;

  factory KanbanOrderSummary.fromJson(Map<String, dynamic> json) =>
      KanbanOrderSummary(
        clientName: json['clientName'] as String?,
        executorName: json['executorName'] as String?,
        managerName: json['managerName'] as String?,
        objectType: json['objectType'] as String?,
        positionCount: json['positionCount'] as int? ?? 0,
        reorderCount: json['reorderCount'] as int? ?? 0,
        invoiceCount: json['invoiceCount'] as int? ?? 0,
        sourceQuoteNumber: json['sourceQuoteNumber'] as int?,
      );
}

/// Карточка того же рабочего объекта в другом канбане.
final class KanbanLinkedCard {
  const KanbanLinkedCard({
    required this.boardId,
    required this.boardName,
    required this.specialization,
    required this.cardId,
    required this.cardNumber,
    required this.columnName,
  });

  final String boardId;
  final String boardName;
  final WorkflowSpecialization specialization;
  final String cardId;
  final int cardNumber;
  final String columnName;

  factory KanbanLinkedCard.fromJson(Map<String, dynamic> json) =>
      KanbanLinkedCard(
        boardId: json['boardId'] as String,
        boardName: json['boardName'] as String,
        specialization: WorkflowSpecialization.fromApi(
          json['specialization'] as String?,
        ),
        cardId: json['cardId'] as String,
        cardNumber: json['cardNumber'] as int,
        columnName: json['columnName'] as String,
      );
}

/// Сводка КП/ПКП на карточке канбана.
final class KanbanQuoteSummary {
  const KanbanQuoteSummary({
    required this.quoteKind,
    required this.selectionMode,
    required this.selections,
    required this.linkViews,
    this.clientName,
    this.executorName,
    this.lastViewedAt,
  });

  /// `quote` или `prequote`.
  final String quoteKind;
  final String? clientName;
  final String? executorName;

  /// `variant` или `proposal_type`.
  final String selectionMode;

  /// Выбранные варианты или выбранный тип целиком; пусто — ничего не выбрано.
  final List<KanbanQuoteSelection> selections;

  /// Сколько раз клиент входил по ссылке.
  final int linkViews;
  final DateTime? lastViewedAt;

  String get kindLabel => quoteKind == 'prequote' ? 'ПКП' : 'КП';

  factory KanbanQuoteSummary.fromJson(Map<String, dynamic> json) =>
      KanbanQuoteSummary(
        quoteKind: json['quoteKind'] as String? ?? 'quote',
        clientName: json['clientName'] as String?,
        executorName: json['executorName'] as String?,
        selectionMode: json['selectionMode'] as String? ?? 'variant',
        selections: [
          for (final item in json['selections'] as List<dynamic>? ?? const [])
            KanbanQuoteSelection.fromJson(item as Map<String, dynamic>),
        ],
        linkViews: json['linkViews'] as int? ?? 0,
        lastViewedAt: json['lastViewedAt'] == null
            ? null
            : DateTime.parse(json['lastViewedAt'] as String),
      );
}

/// Выбранный вариант типа или тип целиком (без [variantName]) с итогом.
final class KanbanQuoteSelection {
  const KanbanQuoteSelection({
    required this.proposalTypeName,
    required this.total,
    this.variantName,
  });

  final String proposalTypeName;
  final String? variantName;

  /// Итог для клиента с НДС.
  final double total;

  factory KanbanQuoteSelection.fromJson(Map<String, dynamic> json) =>
      KanbanQuoteSelection(
        proposalTypeName: json['proposalTypeName'] as String,
        variantName: json['variantName'] as String?,
        total: (json['total'] as num).toDouble(),
      );
}

/// Одна серверная страница карточек отдельного столбца.
final class KanbanCardPage {
  const KanbanCardPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    this.selectedTotal,
  });

  final List<KanbanCard> items;
  final int page;
  final int pageSize;
  final int total;

  /// Сумма выбранных вариантов и типов (с НДС) по всем карточкам столбца с
  /// учётом фильтров; `null`, если в столбце нет КП/ПКП.
  final double? selectedTotal;

  int get pageCount => total == 0 ? 1 : (total / pageSize).ceil();

  factory KanbanCardPage.fromJson(Map<String, dynamic> json) => KanbanCardPage(
    items: (json['items'] as List<dynamic>)
        .map((item) => KanbanCard.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    page: json['page'] as int,
    pageSize: json['pageSize'] as int,
    total: json['total'] as int,
    selectedTotal: (json['selectedTotal'] as num?)?.toDouble(),
  );
}

/// Изменяемая копия данных карточки для формы создания и редактирования.
final class KanbanCardDraft {
  KanbanCardDraft({
    required this.columnId,
    required this.categoryId,
    this.sectionId,
    required this.title,
    Map<String, dynamic>? values,
  }) : values = Map<String, dynamic>.from(values ?? const {});

  String columnId;
  String categoryId;
  String? sectionId;
  String title;
  final Map<String, dynamic> values;

  factory KanbanCardDraft.create(KanbanBoard board, String columnId) =>
      KanbanCardDraft(
        columnId: columnId,
        categoryId: board.categories.isEmpty
            ? ''
            : board.categories.first.categoryId,
        sectionId:
            board.categories.isEmpty ||
                board.categories.first.sections.length != 1
            ? null
            : board.categories.first.sections.single.id,
        title: '',
      );

  factory KanbanCardDraft.fromCard(KanbanCard card) => KanbanCardDraft(
    columnId: card.columnId,
    categoryId: card.categoryId ?? '',
    sectionId: card.sectionId,
    title: card.title,
    values: card.values,
  );

  Map<String, dynamic> toJson() => {
    'columnId': columnId,
    'categoryId': categoryId,
    'sectionId': sectionId,
    'title': title.trim(),
    'values': values,
  };
}

/// Полная конфигурация выбранного рабочего канбана без содержимого карточек.
final class KanbanBoard {
  const KanbanBoard({
    required this.id,
    required this.code,
    required this.name,
    this.specialization = WorkflowSpecialization.standard,
    required this.columns,
    required this.transitions,
    required this.categories,
    this.objectTypes = const [],
  });

  final String id;
  final String code;
  final String name;
  final WorkflowSpecialization specialization;
  final List<KanbanColumn> columns;
  final List<KanbanTransition> transitions;
  final List<KanbanCategory> categories;

  /// Канбан комплектации: справочник «Тип объекта».
  final List<String> objectTypes;

  factory KanbanBoard.fromJson(Map<String, dynamic> json) => KanbanBoard(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    specialization: WorkflowSpecialization.fromApi(
      json['specialization'] as String?,
    ),
    columns: (json['columns'] as List<dynamic>)
        .map((item) => KanbanColumn.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    transitions: (json['transitions'] as List<dynamic>)
        .map((item) => KanbanTransition.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    categories: (json['categories'] as List<dynamic>)
        .map((item) => KanbanCategory.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    objectTypes: ((json['objectTypes'] as List<dynamic>?) ?? const [])
        .map((item) => '$item')
        .toList(growable: false),
  );
}
