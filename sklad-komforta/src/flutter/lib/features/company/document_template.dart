import 'document_layout_models.dart';

const documentPartyFields = <DocumentLayoutField>[
  DocumentLayoutField('name', 'Название'),
  DocumentLayoutField('legal_name', 'Юридическое название'),
  DocumentLayoutField('inn', 'ИНН'),
  DocumentLayoutField('kpp', 'КПП'),
  DocumentLayoutField('ogrn', 'ОГРН'),
  DocumentLayoutField('address', 'Адрес'),
  DocumentLayoutField('phone', 'Телефон'),
  DocumentLayoutField('email', 'Электронная почта'),
  DocumentLayoutField('bank_name', 'Банк'),
  DocumentLayoutField('bank_bik', 'БИК'),
  DocumentLayoutField('bank_account', 'Расчётный счёт'),
  DocumentLayoutField('corr_account', 'Корреспондентский счёт'),
  DocumentLayoutField('company_type', 'Тип компании'),
  DocumentLayoutField('company_name', 'Компания заказчика'),
  DocumentLayoutField('contact_name', 'Контактное лицо'),
  DocumentLayoutField('object_type', 'Тип объекта'),
  DocumentLayoutField('object_address', 'Адрес объекта'),
  DocumentLayoutField('recipient_name', 'Получатель'),
  DocumentLayoutField('website', 'Сайт'),
  DocumentLayoutField('director_name', 'Руководитель'),
  DocumentLayoutField('signatory_name', 'Подписант'),
  DocumentLayoutField('signatory_title', 'Должность подписанта'),
];

List<DocumentLayoutField> documentPartyFieldsFor(String kind) =>
    documentPartyFields
        .where(
          (field) => kind == 'client'
              ? !{
                  'website',
                  'director_name',
                  'signatory_name',
                  'signatory_title',
                }.contains(field.code)
              : !{
                  'company_name',
                  'contact_name',
                  'object_type',
                  'object_address',
                  'recipient_name',
                }.contains(field.code),
        )
        .toList();

const documentBlockNames = {
  'executor': 'Исполнитель',
  'client': 'Заказчик',
  'table': 'Таблица',
  'totals': 'Итоги',
};

class DocumentTemplate {
  DocumentTemplate({
    this.landscape = false,
    this.margin = 30,
    this.fontSize = 12,
    this.lineHeight = 1.35,
    this.fontFamily = 'sans',
    List<DocumentBlock>? blocks,
  }) : blocks = blocks ?? [];
  bool landscape;
  double margin;
  double fontSize;
  double lineHeight;
  String fontFamily;
  final List<DocumentBlock> blocks;
  double get width => landscape ? 1123 : 794;
  double get height => landscape ? 794 : 1123;
  factory DocumentTemplate.fromJson(Map<String, dynamic> json) =>
      DocumentTemplate(
        landscape: json['landscape'] == true,
        margin: (json['margin'] as num?)?.toDouble() ?? 30,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 12,
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.35,
        fontFamily: json['fontFamily'] as String? ?? 'sans',
        blocks: (json['blocks'] as List? ?? [])
            .map((item) => DocumentBlock.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
  Map<String, dynamic> toJson() => {
    'landscape': landscape,
    'margin': margin,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'fontFamily': fontFamily,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };
}

class DocumentBlock {
  DocumentBlock({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    this.width = 320,
    this.height = 150,
    this.fontSize = 12,
    this.padding = 10,
    this.align = 'left',
    this.flowFields = false,
    List<String>? categoryOrder,
    List<String>? fields,
    Map<String, double>? columnWidths,
  }) : categoryOrder = categoryOrder ?? [],
       fields = fields ?? ['name', 'inn', 'address'],
       columnWidths = columnWidths ?? {};
  final String id;
  final String kind;
  double x, y, width, height, fontSize, padding;
  String align;
  bool flowFields;
  List<String> categoryOrder;
  int categoryRank(String? id) {
    final index = categoryOrder.indexOf(id ?? '');
    return index < 0 ? categoryOrder.length : index;
  }

  List<String> fields;
  final Map<String, double> columnWidths;
  factory DocumentBlock.fromJson(Map<String, dynamic> json) => DocumentBlock(
    id: json['id'] as String,
    kind: json['kind'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 12,
    padding: (json['padding'] as num?)?.toDouble() ?? 10,
    align: json['align'] as String? ?? 'left',
    flowFields: json['flowFields'] == true,
    categoryOrder: (json['categoryOrder'] as List? ?? [])
        .cast<String>()
        .toList(),
    fields: (json['fields'] as List? ?? []).cast<String>().toList(),
    columnWidths: (json['columnWidths'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    ),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'fontSize': fontSize,
    'padding': padding,
    'align': align,
    'flowFields': flowFields,
    'categoryOrder': categoryOrder,
    'fields': fields,
    'columnWidths': columnWidths,
  };
}
