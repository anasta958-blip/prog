/// Настроенное поле карточки товара одной категории.
final class CatalogField {
  const CatalogField({
    required this.code,
    required this.label,
    required this.fieldType,
    required this.isVisible,
    required this.isRequired,
    required this.sortOrder,
    this.dictionaryCode,
  });
  final String code;
  final String label;
  final String fieldType;
  final bool isVisible;
  final bool isRequired;
  final int sortOrder;
  final String? dictionaryCode;
  factory CatalogField.fromJson(Map<String, dynamic> json) => CatalogField(
    code: json['code'] as String,
    label: json['label'] as String,
    fieldType: json['fieldType'] as String,
    isVisible: json['isVisible'] as bool,
    isRequired: json['isRequired'] as bool,
    sortOrder: json['sortOrder'] as int,
    dictionaryCode: json['dictionaryCode'] as String?,
  );
}

/// Группа товаров внутри раздела каталога.
final class CatalogGroup {
  const CatalogGroup({
    required this.id,
    required this.name,
    required this.sortOrder,
  });
  final String id;
  final String name;
  final int sortOrder;
  factory CatalogGroup.fromJson(Map<String, dynamic> json) => CatalogGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    sortOrder: json['sortOrder'] as int,
  );
}

/// Раздел каталога с доступными в нём группами.
final class CatalogSection {
  const CatalogSection({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.groups,
  });
  final String id;
  final String name;
  final int sortOrder;
  final List<CatalogGroup> groups;
  factory CatalogSection.fromJson(Map<String, dynamic> json) => CatalogSection(
    id: json['id'] as String,
    name: json['name'] as String,
    sortOrder: json['sortOrder'] as int,
    groups: (json['groups'] as List<dynamic>)
        .map((item) => CatalogGroup.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}

/// Категория каталога с её динамической структурой карточки.
final class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.fields,
    required this.sections,
  });
  final String id;
  final String name;
  final int sortOrder;
  final List<CatalogField> fields;
  final List<CatalogSection> sections;
  factory CatalogCategory.fromJson(Map<String, dynamic> json) =>
      CatalogCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        sortOrder: json['sortOrder'] as int,
        fields: (json['fields'] as List<dynamic>)
            .map((item) => CatalogField.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        sections: (json['sections'] as List<dynamic>)
            .map(
              (item) => CatalogSection.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );
}

/// Значение пользовательского справочника организации.
final class CatalogDictionaryItem {
  const CatalogDictionaryItem({
    required this.id,
    required this.value,
    required this.sortOrder,
  });
  final String id;
  final String value;
  final int sortOrder;
  factory CatalogDictionaryItem.fromJson(Map<String, dynamic> json) =>
      CatalogDictionaryItem(
        id: json['id'] as String,
        value: json['value'] as String,
        sortOrder: json['sortOrder'] as int,
      );
}

/// Справочник, который может использовать динамическое поле карточки.
final class CatalogDictionary {
  const CatalogDictionary({
    required this.id,
    required this.code,
    required this.name,
    required this.sortOrder,
    required this.items,
  });
  final String id;
  final String code;
  final String name;
  final int sortOrder;
  final List<CatalogDictionaryItem> items;
  factory CatalogDictionary.fromJson(Map<String, dynamic> json) =>
      CatalogDictionary(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        sortOrder: json['sortOrder'] as int,
        items: (json['items'] as List<dynamic>)
            .map(
              (item) =>
                  CatalogDictionaryItem.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );
}

/// Разрешённое направление привязки карточек между двумя категориями.
final class CatalogDependency {
  const CatalogDependency({
    required this.id,
    required this.sourceCategoryId,
    required this.targetCategoryId,
    required this.targetFieldCode,
    required this.sortOrder,
  });

  final String id;
  final String sourceCategoryId;
  final String targetCategoryId;
  final String targetFieldCode;
  final int sortOrder;

  factory CatalogDependency.fromJson(Map<String, dynamic> json) =>
      CatalogDependency(
        id: json['id'] as String,
        sourceCategoryId: json['sourceCategoryId'] as String,
        targetCategoryId: json['targetCategoryId'] as String,
        targetFieldCode: json['targetFieldCode'] as String,
        sortOrder: json['sortOrder'] as int,
      );
}

/// Полная tenant-конфигурация, необходимая для динамического каталога.
final class CatalogConfiguration {
  const CatalogConfiguration({
    required this.categories,
    required this.dictionaries,
    this.dependencies = const [],
  });
  final List<CatalogCategory> categories;
  final List<CatalogDictionary> dictionaries;
  final List<CatalogDependency> dependencies;
  factory CatalogConfiguration.fromJson(
    Map<String, dynamic> json,
  ) => CatalogConfiguration(
    categories: (json['categories'] as List<dynamic>)
        .map((item) => CatalogCategory.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    dictionaries: (json['dictionaries'] as List<dynamic>)
        .map((item) => CatalogDictionary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    dependencies: ((json['dependencies'] as List<dynamic>?) ?? const [])
        .map((item) => CatalogDependency.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}

/// Одна сохранённая карточка каталога.
final class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.categoryId,
    required this.sectionId,
    required this.groupId,
    required this.name,
    required this.marking,
    required this.status,
    required this.values,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnailUrl,
  });
  final String id;
  final String categoryId;
  final String? sectionId;
  final String? groupId;
  final String name;
  final String marking;
  final String status;
  final Map<String, dynamic> values;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? thumbnailUrl;
  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
    id: json['id'] as String,
    categoryId: json['categoryId'] as String,
    sectionId: json['sectionId'] as String?,
    groupId: json['groupId'] as String?,
    name: json['name'] as String,
    marking: json['marking'] as String,
    status: json['status'] as String,
    values: Map<String, dynamic>.from(
      (json['values'] as Map<String, dynamic>?) ?? const {},
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    thumbnailUrl: json['thumbnailUrl'] as String?,
  );

  CatalogItem withThumbnail(String? value) => CatalogItem(
    id: id,
    categoryId: categoryId,
    sectionId: sectionId,
    groupId: groupId,
    name: name,
    marking: marking,
    status: status,
    values: values,
    createdAt: createdAt,
    updatedAt: updatedAt,
    thumbnailUrl: value,
  );
}

/// Серверная страница карточек каталога.
final class CatalogItemPage {
  const CatalogItemPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });
  final List<CatalogItem> items;
  final int page;
  final int pageSize;
  final int total;
  int get pageCount => total == 0 ? 1 : (total / pageSize).ceil();
  factory CatalogItemPage.fromJson(Map<String, dynamic> json) =>
      CatalogItemPage(
        items: (json['items'] as List<dynamic>)
            .map((item) => CatalogItem.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
        total: json['total'] as int,
      );
}

/// Изображение карточки с короткоживущей защищённой ссылкой просмотра.
final class CatalogItemImage {
  const CatalogItemImage({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.byteSize,
    required this.sortOrder,
    required this.downloadUrl,
  });
  final String id;
  final String fileName;
  final String contentType;
  final int byteSize;
  final int sortOrder;
  final String downloadUrl;
  factory CatalogItemImage.fromJson(Map<String, dynamic> json) =>
      CatalogItemImage(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        contentType: json['contentType'] as String,
        byteSize: json['byteSize'] as int,
        sortOrder: json['sortOrder'] as int,
        downloadUrl: json['downloadUrl'] as String,
      );
}

/// Параметры прямой загрузки в закрытое S3-совместимое хранилище.
final class CatalogImageUploadTicket {
  const CatalogImageUploadTicket({
    required this.imageId,
    required this.uploadUrl,
    required this.expiresAt,
  });
  final String imageId;
  final String uploadUrl;
  final DateTime expiresAt;
  factory CatalogImageUploadTicket.fromJson(Map<String, dynamic> json) =>
      CatalogImageUploadTicket(
        imageId: json['imageId'] as String,
        uploadUrl: json['uploadUrl'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}

/// Карточка исходной категории, доступная для новой привязки.
final class CatalogRelationCandidate {
  const CatalogRelationCandidate({
    required this.id,
    required this.name,
    required this.marking,
    required this.status,
  });

  final String id;
  final String name;
  final String marking;
  final String status;

  factory CatalogRelationCandidate.fromJson(Map<String, dynamic> json) =>
      CatalogRelationCandidate(
        id: json['id'] as String,
        name: json['name'] as String,
        marking: json['marking'] as String,
        status: json['status'] as String,
      );
}

/// Одна карточка, прикреплённая к редактируемому товару по UUID.
final class CatalogItemRelation {
  const CatalogItemRelation({
    required this.dependencyId,
    required this.sourceItemId,
    required this.sourceName,
    required this.sourceMarking,
    required this.sortOrder,
  });

  final String dependencyId;
  final String sourceItemId;
  final String sourceName;
  final String sourceMarking;
  final int sortOrder;

  factory CatalogItemRelation.fromJson(Map<String, dynamic> json) =>
      CatalogItemRelation(
        dependencyId: json['dependencyId'] as String,
        sourceItemId: json['sourceItemId'] as String,
        sourceName: json['sourceName'] as String,
        sourceMarking: json['sourceMarking'] as String,
        sortOrder: json['sortOrder'] as int,
      );

  Map<String, dynamic> toSaveJson() => {
    'dependencyId': dependencyId,
    'sourceItemId': sourceItemId,
  };
}

/// Полное редактируемое состояние карточки для POST и PUT.
final class CatalogItemDraft {
  CatalogItemDraft({
    required this.categoryId,
    required this.name,
    this.sectionId,
    this.groupId,
    this.marking = '',
    this.status = 'pending',
    Map<String, dynamic>? values,
  }) : values = values ?? <String, dynamic>{};
  String categoryId;
  String? sectionId;
  String? groupId;
  String name;
  String marking;
  String status;
  Map<String, dynamic> values;
  factory CatalogItemDraft.fromItem(CatalogItem item) => CatalogItemDraft(
    categoryId: item.categoryId,
    sectionId: item.sectionId,
    groupId: item.groupId,
    name: item.name,
    marking: item.marking,
    status: item.status,
    values: Map<String, dynamic>.from(item.values),
  );
  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'sectionId': sectionId,
    'groupId': groupId,
    'name': name.trim(),
    'marking': marking.trim(),
    'status': status,
    'values': values,
  };
}
