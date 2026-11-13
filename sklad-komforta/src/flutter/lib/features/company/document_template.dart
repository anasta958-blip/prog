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
  DocumentLayoutField('passport_series', 'Серия паспорта'),
  DocumentLayoutField('passport_number', 'Номер паспорта'),
  DocumentLayoutField('passport_issued_by', 'Кем выдан'),
];

List<DocumentLayoutField> documentPartyFieldsFor(String kind, String type) {
  final codes = kind == 'client'
      ? type == 'person'
            ? [
                'name',
                'phone',
                'email',
                'passport_series',
                'passport_number',
                'passport_issued_by',
                'address',
              ]
            : [
                'name',
                'inn',
                if (type == 'ooo') 'kpp',
                'ogrn',
                'phone',
                'email',
                'bank_name',
                'bank_bik',
                'address',
                'bank_account',
                'corr_account',
              ]
      : [
          'name',
          'legal_name',
          'inn',
          if (type == 'ooo') 'kpp',
          'ogrn',
          'address',
          'phone',
          'email',
          'website',
          'director_name',
          'signatory_name',
          'signatory_title',
          'bank_name',
          'bank_bik',
          'bank_account',
          'corr_account',
        ];
  return [
    for (final code in codes)
      DocumentLayoutField(code, documentPartyFieldLabel(kind, type, code)),
  ];
}

String documentPartyFieldLabel(String kind, String? type, String code) =>
    switch ((kind, type, code)) {
      ('client', 'person', 'name') => 'ФИО',
      ('client', 'person', 'address') => 'Адрес регистрации',
      ('client', 'ip', 'name') => 'Название ИП',
      ('client', 'ooo', 'name') => 'Название компании',
      ('client', 'ip' || 'ooo', 'address') => 'Юридический адрес',
      ('executor', 'ip' || 'ooo', 'name') => 'Короткое название',
      ('executor', 'ip', 'legal_name') => 'ФИО индивидуального предпринимателя',
      (_, 'ip', 'ogrn') => 'ОГРНИП',
      _ =>
        documentPartyFields
                .where((field) => field.code == code)
                .firstOrNull
                ?.label ??
            code,
    };

List<String> documentPartyTypes(String kind) =>
    kind == 'client' ? ['person', 'ip', 'ooo'] : ['ip', 'ooo'];
const documentPartyTypeNames = {
  'person': 'Физическое лицо',
  'ip': 'ИП',
  'ooo': 'ООО',
};

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
    this.fieldColumns,
    Map<String, List<String>>? partyFieldsByType,
    List<String>? categoryOrder,
    List<String>? fields,
    Map<String, double>? columnWidths,
  }) : partyFieldsByType = partyFieldsByType ?? {},
       categoryOrder = categoryOrder ?? [],
       fields = fields ?? ['name', 'inn', 'address'],
       columnWidths = columnWidths ?? {};
  final String id;
  final String kind;
  double x, y, width, height, fontSize, padding;
  String align;
  bool flowFields;
  int? fieldColumns;
  final Map<String, List<String>> partyFieldsByType;
  List<String> fieldsForParty(String? type) =>
      partyFieldsByType[type] ?? fields;
  List<String> editablePartyFields(String type) {
    final allowed = documentPartyFieldsFor(
      kind,
      type,
    ).map((field) => field.code).toSet();
    return fieldsForParty(type).where(allowed.contains).toList();
  }

  void setPartyFields(String type, List<String> selected) {
    if (partyFieldsByType.isEmpty) {
      for (final other in documentPartyTypes(kind)) {
        partyFieldsByType[other] = editablePartyFields(other);
      }
    }
    partyFieldsByType[type] = [...selected];
  }

  int get effectiveFieldColumns => fieldColumns ?? (flowFields ? 2 : 1);
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
    partyFieldsByType:
        (json['partyFieldsByType'] as Map<String, dynamic>? ?? {}).map(
          (key, value) =>
              MapEntry(key, (value as List).cast<String>().toList()),
        ),
    fieldColumns: (json['fieldColumns'] as num?)?.toInt().clamp(
      1,
      documentPartyFields.length,
    ),
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
    'fieldColumns': effectiveFieldColumns,
    'categoryOrder': categoryOrder,
    'fields': fields,
    if (partyFieldsByType.isNotEmpty) 'partyFieldsByType': partyFieldsByType,
    'columnWidths': columnWidths,
  };
}
