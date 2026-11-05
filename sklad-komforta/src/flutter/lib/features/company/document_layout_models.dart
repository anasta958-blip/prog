import 'document_template.dart';

final class DocumentLayoutField {
  const DocumentLayoutField(this.code, this.label);
  final String code;
  final String label;
  factory DocumentLayoutField.fromJson(Map<String, dynamic> json) =>
      DocumentLayoutField(json['code'] as String, json['label'] as String);
}

final class DocumentLayoutCategory {
  DocumentLayoutCategory(this.id, this.name, this.fields, this.codes);
  final String id;
  final String name;
  final List<DocumentLayoutField> fields;
  List<String>? codes;
  factory DocumentLayoutCategory.fromJson(Map<String, dynamic> json) =>
      DocumentLayoutCategory(
        json['categoryId'] as String,
        json['name'] as String,
        (json['fields'] as List)
            .map(
              (item) =>
                  DocumentLayoutField.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        (json['fieldCodes'] as List?)?.cast<String>().toList(),
      );
  Map<String, dynamic> toJson() => {'categoryId': id, 'fieldCodes': codes};
}

final class DocumentLayoutBoard {
  DocumentLayoutBoard(
    this.id,
    this.name,
    this.specialization,
    this.categories, {
    this.template,
  });
  DocumentTemplate? template;
  final String id;
  final String name;
  final String specialization;
  final List<DocumentLayoutCategory> categories;
  factory DocumentLayoutBoard.fromJson(Map<String, dynamic> json) =>
      DocumentLayoutBoard(
        json['workflowId'] as String,
        json['name'] as String,
        json['specialization'] as String,
        (json['categories'] as List)
            .map(
              (item) =>
                  DocumentLayoutCategory.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        template: json['template'] is Map<String, dynamic>
            ? DocumentTemplate.fromJson(
                json['template'] as Map<String, dynamic>,
              )
            : null,
      );
  Map<String, dynamic> toJson() => {
    'categories': categories.map((item) => item.toJson()).toList(),
    'template': template?.toJson(),
  };
}

abstract interface class DocumentLayoutGateway {
  Future<List<DocumentLayoutBoard>> getDocumentLayouts(String token);
  Future<void> saveDocumentLayout(String token, DocumentLayoutBoard board);
}
