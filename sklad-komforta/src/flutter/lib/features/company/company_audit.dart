import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'company_models.dart';

final class AuditFieldChange {
  const AuditFieldChange(this.field, this.before, this.after);
  final String field;
  final String before;
  final String after;
}

Map<String, String> auditReferenceNames(Object? data) {
  final result = <String, String>{};
  void visit(Object? value) {
    if (value is Map) {
      final name = value['name'] ?? value['label'] ?? value['title'];
      if (name is String && name.isNotEmpty) {
        for (final key in ['id', 'clientId', 'code']) {
          if (value[key] is String) result[value[key] as String] = name;
        }
      }
      value.values.forEach(visit);
    } else if (value is List) {
      value.forEach(visit);
    }
  }

  visit(data);
  return result;
}

const _technical = {
  'id',
  'clientId',
  'createdAt',
  'updatedAt',
  'createdBy',
  'updatedBy',
  'currentStep',
  'password',
  'temporaryPassword',
  'passwordHash',
  'createdByName',
  'updatedByName',
  'thumbnailUrl',
};

/// Compares nested structures rather than displaying their JSON representation.
List<AuditFieldChange> auditChanges(
  CompanyAuditEntryModel entry, {
  Map<String, String> names = const {},
}) {
  final changes = <AuditFieldChange>[];
  final labels = {...names};
  void collect(Object? value) {
    if (value is Map) {
      final name = value['name'] ?? value['title'] ?? value['displayName'];
      if (name is String && name.isNotEmpty) {
        for (final key in ['id', 'clientId', 'code']) {
          if (value[key] is String) labels[value[key] as String] = name;
        }
      }
      value.values.forEach(collect);
    } else if (value is List) {
      value.forEach(collect);
    }
  }

  collect(entry.diff['before']);
  collect(entry.diff['after']);

  String format(Object? value) {
    if (value == null || value == '') return 'Не задано';
    if (value is bool) return value ? 'Да' : 'Нет';
    if (value is Map) {
      return (value['name'] ??
              value['title'] ??
              value['sourceName'] ??
              value['displayName'] ??
              'Элемент')
          .toString();
    }
    if (value is List) {
      return value.isEmpty ? 'Нет' : value.map(format).join(', ');
    }
    final text = value.toString();
    if (labels.containsKey(text)) return labels[text]!;
    return switch (text) {
      'own' => 'Только свои',
      'all' => 'Все',
      'subordinates' => 'Свои и подчинённых',
      'specific' => 'Выбранные сотрудники',
      'quote' => 'КП',
      'prequote' => 'ПКП',
      'approved' => 'Согласовано',
      'draft' => 'Черновик',
      _ => text,
    };
  }

  String identity(Map value) =>
      (value['id'] ??
              value['clientId'] ??
              value['code'] ??
              (value['sourceItemId'] == null
                  ? null
                  : '${value['dependencyId']}:${value['sourceItemId']}') ??
              '')
          .toString();

  void compare(
    Object? before,
    Object? after,
    String path, {
    bool dynamicValue = false,
  }) {
    if (before is Map || after is Map) {
      final old = before is Map ? before : const {};
      final next = after is Map ? after : const {};
      for (final key in {...old.keys, ...next.keys}) {
        if (!dynamicValue &&
            _technical.contains(key) &&
            !(key == 'clientId' &&
                entry.entityType == 'quote' &&
                path.isEmpty)) {
          continue;
        }
        // Historical request snapshots omitted these read-only properties.
        if (path.isEmpty &&
            before != null &&
            after != null &&
            !next.containsKey(key) &&
            const {
              'roleName',
              'isSystem',
              'membershipId',
              'userId',
              'isDirector',
            }.contains(key)) {
          continue;
        }
        final label = labels[key] ?? auditFieldLabel(key.toString());
        compare(
          old[key],
          next[key],
          path.isEmpty ? label : '$path / $label',
          dynamicValue: dynamicValue || key == 'values',
        );
      }
      return;
    }
    if (before is List || after is List) {
      final old = before is List ? before : const [];
      final next = after is List ? after : const [];
      if ([...old, ...next].every((e) => e is Map && identity(e).isNotEmpty) &&
          old.map((e) => identity(e as Map)).toSet().length == old.length &&
          next.map((e) => identity(e as Map)).toSet().length == next.length) {
        final oldMap = {for (final e in old) identity(e as Map): e};
        final newMap = {for (final e in next) identity(e as Map): e};
        for (final id in {...oldMap.keys, ...newMap.keys}) {
          final a = oldMap[id];
          final b = newMap[id];
          final title = format(b ?? a);
          if (a == null || b == null) {
            changes.add(
              AuditFieldChange(
                path,
                a == null ? 'Отсутствует' : title,
                b == null ? 'Удалено' : '$title (добавлено)',
              ),
            );
          } else {
            compare(a, b, '$path / $title', dynamicValue: dynamicValue);
          }
        }
        if (oldMap.length == newMap.length &&
            oldMap.keys.toSet().containsAll(newMap.keys) &&
            oldMap.keys.join('|') != newMap.keys.join('|')) {
          changes.add(
            AuditFieldChange('$path / Порядок', format(old), format(next)),
          );
        }
        return;
      }
      if ([...old, ...next].any((e) => e is Map || e is List)) {
        for (
          var index = 0;
          index < (old.length > next.length ? old.length : next.length);
          index++
        ) {
          compare(
            index < old.length ? old[index] : null,
            index < next.length ? next[index] : null,
            '$path / ${index + 1}',
            dynamicValue: dynamicValue,
          );
        }
        return;
      }
    }
    final a = format(before);
    final b = format(after);
    if (a != b) {
      changes.add(AuditFieldChange(path.isEmpty ? 'Значение' : path, a, b));
    }
  }

  if (entry.diff.containsKey('before') || entry.diff.containsKey('after')) {
    compare(entry.diff['before'], entry.diff['after'], '');
  } else {
    compare(null, entry.diff, '');
  }
  return changes;
}

String auditFieldLabel(String key) =>
    const {
      'name': 'Название',
      'displayName': 'Имя',
      'title': 'Название',
      'organizationName': 'Организация',
      'companyType': 'Тип компании',
      'companyName': 'Компания',
      'legalName': 'Юридическое название',
      'inn': 'ИНН',
      'kpp': 'КПП',
      'ogrn': 'ОГРН / ОГРНИП',
      'phone': 'Телефон',
      'email': 'Почта',
      'address': 'Адрес',
      'website': 'Сайт',
      'directorName': 'Директор',
      'signatoryName': 'Подписант',
      'signatoryTitle': 'Должность подписанта',
      'bankName': 'Банк',
      'bankBik': 'БИК',
      'bankAccount': 'Расчётный счёт',
      'corrAccount': 'Корреспондентский счёт',
      'passportSeries': 'Серия паспорта',
      'passportNumber': 'Номер паспорта',
      'passportIssuedBy': 'Кем выдан паспорт',
      'roleId': 'Роль',
      'supervisorMembershipId': 'Руководитель',
      'isActive': 'Активность',
      'isDefault': 'Исполнитель по умолчанию',
      'introDefault': 'Вводный текст',
      'footerDefault': 'Дополнительный текст',
      'vatRates': 'Ставки НДС',
      'vatRate': 'НДС',
      'login': 'Логин',
      'note': 'Примечание',
      'permissionCodes': 'Разрешения',
      'subordinateRoleIds': 'Подчинённые роли',
      'cardVisibilityMode': 'Видимость карточек',
      'cardVisibilityMembershipIds': 'Выбранные сотрудники',
      'workflows': 'Канбаны',
      'columns': 'Столбцы',
      'categories': 'Категории',
      'sections': 'Разделы',
      'groups': 'Группы',
      'fields': 'Поля',
      'dictionaries': 'Справочники',
      'items': 'Элементы',
      'dependencies': 'Связи',
      'rules': 'Правила',
      'moneyPipelines': 'Денежные расчёты',
      'company': 'Компания',
      'proposalTypes': 'Типы предложения',
      'variants': 'Варианты',
      'positions': 'Позиции',
      'quantity': 'Количество',
      'basePrice': 'Базовая цена',
      'base_price': 'Цена',
      'purchasePrice': 'Закупочная цена',
      'manualPrice': 'Ручная цена',
      'markupPercent': 'Наценка, %',
      'discountPercent': 'Скидка, %',
      'lineTotal': 'Сумма строки',
      'excludeFromTotals': 'Не учитывать в итогах',
      'values': 'Поля',
      'marking': 'Маркировка',
      'unit': 'Единица',
      'status': 'Статус',
      'sortOrder': 'Позиция',
      'columnId': 'Столбец',
      'isArchived': 'В архиве',
      'categoryId': 'Категория',
      'sectionId': 'Раздел',
      'groupId': 'Группа',
      'clientId': 'Заказчик',
      'executorCompanyId': 'Исполнитель',
      'managerUserId': 'Менеджер',
      'salesHeadUserId': 'РОП',
      'additionalInformation': 'Дополнительная информация',
      'quoteKind': 'Вид предложения',
      'selectionMode': 'Режим выбора',
      'selectedVariantId': 'Выбранный вариант',
      'selectedByClient': 'Выбрано клиентом',
      'isRequired': 'Обязательное',
      'isVisible': 'Показывать',
      'fieldType': 'Тип поля',
      'sourceName': 'Связанная позиция',
      'sourceMarking': 'Маркировка связанной позиции',
      'categoryName': 'Категория',
      'itemCount': 'Товаров',
      'imageCount': 'Изображений',
      'relationCount': 'Связей',
      'contactName': 'Контактное лицо',
      'objectType': 'Тип объекта',
      'objectAddress': 'Адрес объекта',
      'recipientName': 'Получатель',
      'salutation': 'Обращение',
      'proposalTitle': 'Название предложения',
      'introText': 'Вводный текст',
      'subtitle': 'Подзаголовок',
      'telegram': 'Telegram',
      'number': 'Номер',
      'workflowId': 'Канбан',
      'catalogItemId': 'Товар каталога',
      'sourceItemId': 'Связанная позиция',
      'dependencyId': 'Правило связи',
      'isEnabled': 'Включено',
      'enabled': 'Включено',
      'required': 'Обязательное',
      'visible': 'Показывать',
      'type': 'Тип',
      'code': 'Код',
      'dictionaryCode': 'Источник справочника',
      'specialization': 'Тип канбана',
      'creationActions': 'Кнопки создания',
      'categoryIds': 'Категории',
      'event': 'Событие',
      'conditions': 'Условия',
      'actions': 'Действия',
      'formula': 'Формула',
      'roles': 'Роли',
      'fieldCode': 'Поле',
      'targetFieldCode': 'Поле результата',
      'sourceFieldCode': 'Исходное поле',
      'submitted': 'Выбор подтверждён',
      'proposalTypeId': 'Тип предложения',
      'variantId': 'Вариант',
    }[key] ??
    key;

final class CompanyAuditList extends StatelessWidget {
  const CompanyAuditList({
    required this.entries,
    this.names = const {},
    super.key,
  });
  final List<CompanyAuditEntryModel> entries;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = switch (constraints.maxWidth) {
        >= 1440 => 3,
        >= 1000 => 2,
        _ => 1,
      };
      return ListView.separated(
        padding: const EdgeInsets.all(22),
        itemCount: (entries.length / columns).ceil(),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, row) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: 12),
              Expanded(
                child: row * columns + column < entries.length
                    ? CompanyAuditCard(
                        key: ValueKey(entries[row * columns + column].id),
                        entry: entries[row * columns + column],
                        names: names,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    },
  );
}

final class CompanyAuditCard extends StatefulWidget {
  const CompanyAuditCard({
    required this.entry,
    this.names = const {},
    super.key,
  });
  final CompanyAuditEntryModel entry;
  final Map<String, String> names;
  @override
  State<CompanyAuditCard> createState() => _CompanyAuditCardState();
}

class _CompanyAuditCardState extends State<CompanyAuditCard> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final changes = auditChanges(entry, names: widget.names);
    final snapshot = entry.diff['after'] ?? entry.diff['before'];
    final name = snapshot is Map
        ? snapshot['name'] ??
              snapshot['title'] ??
              snapshot['displayName'] ??
              snapshot['organizationName']
        : null;
    final objectName = name ?? widget.names[entry.entityId];
    final entity = switch (entry.entityType) {
      'legal_entity' => 'Юридическое лицо',
      'client' => 'Клиент',
      'employee' || 'employee_access' => 'Сотрудник',
      'role' => 'Роль',
      'catalog_item' => 'Товар',
      'catalog_category' => 'Категория каталога',
      'kanban_card' => 'Карточка канбана',
      'quote' => 'КП / ПКП',
      'organization_configuration' ||
      'company_configuration' => 'Настройки организации',
      'organization_profile' ||
      'company_profile' ||
      'organization' => 'Организация',
      _ => 'Объект',
    };
    final action = switch (entry.action) {
      'created' || 'import_created' => 'Создание',
      'deleted' || 'deleted_with_data' => 'Удаление',
      'moved' => 'Перемещение',
      'archived' => 'Перемещение в архив',
      'restored' => 'Возврат из архива',
      'password_changed' => 'Смена пароля',
      'relations_replaced' => 'Изменение связей',
      'image_added' => 'Добавление изображения',
      'image_deleted' => 'Удаление изображения',
      'client_selection_submitted' => 'Выбор клиента',
      'client_link_secret_viewed' => 'Просмотр ссылки и пароля клиента',
      'onboarding_completed' => 'Завершение настройки',
      _ => 'Изменение',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final valueWidth = constraints.maxWidth < 500
                ? constraints.maxWidth
                : (constraints.maxWidth - 40) / 2;
            bool overflows(String text, {double? width, int maxLines = 1}) {
              final painter = TextPainter(
                text: TextSpan(
                  text: text,
                  style: DefaultTextStyle.of(context).style,
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: maxLines,
                ellipsis: '…',
              )..layout(maxWidth: width ?? valueWidth);
              final result = painter.didExceedMaxLines;
              painter.dispose();
              return result;
            }

            final canExpand =
                overflows(
                  '$action · $entity${objectName == null ? '' : ' «$objectName»'}',
                  width: constraints.maxWidth,
                ) ||
                overflows(
                  'Кто: ${entry.actorName ?? 'Система'}',
                  width: constraints.maxWidth,
                  maxLines: 1,
                ) ||
                changes.length > 1 ||
                changes
                    .take(1)
                    .any(
                      (change) =>
                          overflows(change.before) ||
                          overflows(change.after) ||
                          overflows(
                            change.field,
                            width: constraints.maxWidth,
                            maxLines: 1,
                          ),
                    );
            double lineHeight({double? fontSize}) {
              final painter = TextPainter(
                text: TextSpan(
                  text: 'Текст',
                  style: DefaultTextStyle.of(
                    context,
                  ).style.copyWith(fontSize: fontSize),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final height = painter.height;
              painter.dispose();
              return height;
            }

            final bodyLine = lineHeight();
            final labelLine = lineHeight(fontSize: 11);
            // Reserve only the visible text lines, spacing and the action row.
            final compactHeight =
                bodyLine * 5 +
                labelLine +
                52 +
                (bodyLine + 16).clamp(48, double.infinity) +
                (constraints.maxWidth < 500 ? bodyLine + labelLine + 4 : 0);
            return SizedBox(
              height: expanded ? null : compactHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$action · $entity${objectName == null ? '' : ' «$objectName»'}',
                    maxLines: expanded ? null : 1,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Кто: ${entry.actorName ?? (entry.action == 'client_selection_submitted' ? 'Клиент по ссылке' : 'Система')}',
                        maxLines: expanded ? null : 1,
                        overflow: expanded ? null : TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF9FB2CD)),
                      ),
                      Text(
                        'Когда: ${DateFormat('dd.MM.yyyy HH:mm').format(entry.createdAt.toLocal())}',
                        maxLines: expanded ? null : 1,
                        overflow: expanded ? null : TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF9FB2CD)),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (changes.isEmpty)
                    const Text(
                      'Подробности изменения в этой записи не сохранены.',
                    )
                  else
                    for (final change in expanded ? changes : changes.take(1))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              change.field,
                              maxLines: expanded ? null : 1,
                              overflow: expanded ? null : TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                Widget value(
                                  String label,
                                  String text,
                                  Color color,
                                ) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9FB2CD),
                                      ),
                                    ),
                                    Tooltip(
                                      message: text,
                                      child: Text(
                                        text,
                                        maxLines: expanded ? null : 1,
                                        overflow: expanded
                                            ? null
                                            : TextOverflow.ellipsis,
                                        style: TextStyle(color: color),
                                      ),
                                    ),
                                  ],
                                );
                                final before = value(
                                  'Было',
                                  change.before,
                                  const Color(0xFF9FB2CD),
                                );
                                final after = value(
                                  'Стало',
                                  change.after,
                                  const Color(0xFFD2E4FF),
                                );
                                if (constraints.maxWidth < 500) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      before,
                                      const SizedBox(height: 4),
                                      after,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: before),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Icon(
                                        Icons.arrow_forward,
                                        size: 16,
                                      ),
                                    ),
                                    Expanded(child: after),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                  if (!expanded) const Spacer(),
                  if (canExpand)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => expanded = !expanded),
                        child: Text(
                          expanded
                              ? 'Свернуть'
                              : 'Все подробности (${changes.length})',
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
