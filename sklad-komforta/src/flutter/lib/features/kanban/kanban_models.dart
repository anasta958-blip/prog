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
  });

  final String id;
  final String name;
  final String color;
  final int sortOrder;

  factory KanbanColumn.fromJson(Map<String, dynamic> json) => KanbanColumn(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
    sortOrder: json['sortOrder'] as int,
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
  });

  final String categoryId;
  final String name;
  final int sortOrder;
  final List<KanbanField> fields;
  final List<KanbanSection> sections;

  factory KanbanCategory.fromJson(Map<String, dynamic> json) => KanbanCategory(
    categoryId: json['categoryId'] as String,
    name: json['name'] as String,
    sortOrder: json['sortOrder'] as int,
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
    required this.categoryId,
    this.sectionId,
    required this.title,
    required this.values,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.createdByName,
    this.updatedBy,
    this.updatedByName,
  });

  final String id;
  final int number;
  final String workflowId;
  final String columnId;
  final String categoryId;
  final String? sectionId;
  final String title;
  final Map<String, dynamic> values;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final String? updatedBy;
  final String? updatedByName;
  final DateTime updatedAt;

  factory KanbanCard.fromJson(Map<String, dynamic> json) => KanbanCard(
    id: json['id'] as String,
    number: json['number'] as int,
    workflowId: json['workflowId'] as String,
    columnId: json['columnId'] as String,
    categoryId: json['categoryId'] as String,
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
  );
}

/// Одна серверная страница карточек отдельного столбца.
final class KanbanCardPage {
  const KanbanCardPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<KanbanCard> items;
  final int page;
  final int pageSize;
  final int total;

  int get pageCount => total == 0 ? 1 : (total / pageSize).ceil();

  factory KanbanCardPage.fromJson(Map<String, dynamic> json) => KanbanCardPage(
    items: (json['items'] as List<dynamic>)
        .map((item) => KanbanCard.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    page: json['page'] as int,
    pageSize: json['pageSize'] as int,
    total: json['total'] as int,
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
    categoryId: card.categoryId,
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
  });

  final String id;
  final String code;
  final String name;
  final WorkflowSpecialization specialization;
  final List<KanbanColumn> columns;
  final List<KanbanTransition> transitions;
  final List<KanbanCategory> categories;

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
  );
}
