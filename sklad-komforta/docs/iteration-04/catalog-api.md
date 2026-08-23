# REST API каталога

Все endpoint-ы требуют JWT, активную tenant-сессию и разрешение роли.

## Конфигурация

`GET /api/v1/catalog/configuration`

Возвращает категории, разделы, группы, поля и справочники текущей организации.
Требуемое право: `catalog.view`.

## Список

`GET /api/v1/catalog/items`

Параметры:

- `categoryId`, `sectionId`, `status`, `search` — необязательные фильтры;
- `page` — номер от 1, по умолчанию 1;
- `pageSize` — от 1 до 100, по умолчанию 50.

Сортировка: сначала последние изменённые карточки. Ответ содержит `items`,
`page`, `pageSize`, `total`. У каждого элемента `thumbnailUrl` содержит
короткоживущую ссылку на первое готовое изображение либо `null`. Обложка
выбирается в том же SQL-запросе, поэтому список не создаёт отдельный запрос к
базе для каждой карточки. Требуемое право: `catalog.view`.

## Карточка

- `GET /api/v1/catalog/items/{itemId}` — чтение, `catalog.view`;
- `POST /api/v1/catalog/items` — создание, `catalog.manage`;
- `PUT /api/v1/catalog/items/{itemId}` — полная замена редактируемых данных,
  `catalog.manage`;
- `DELETE /api/v1/catalog/items/{itemId}` — мягкое удаление,
  `catalog.manage`.

Тело создания и изменения:

```json
{
  "categoryId": "uuid",
  "sectionId": "uuid или null",
  "groupId": "uuid или null",
  "name": "Наименование",
  "marking": "Маркировка",
  "status": "pending",
  "values": {
    "unit": "шт",
    "base_price": 100
  }
}
```

Все ответы используют единый контракт `{ "ok": true, "data": ..., "error": null }`.
Ошибки имеют стабильные коды, включая `catalog_item_exists`,
`catalog_price_invalid`, `catalog_structure_invalid` и `catalog_field_type_invalid`.
# Изображения карточки

- `GET /api/v1/catalog/items/{itemId}/images` возвращает готовые изображения с
  временными download URL;
- `POST /api/v1/catalog/items/{itemId}/images/uploads` проверяет имя, MIME и
  размер и выдаёт upload ticket на пять минут;
- клиент загружает байты напрямую в S3/MinIO методом `PUT` с тем же
  `Content-Type`;
- `POST /api/v1/catalog/items/{itemId}/images/{imageId}/confirm` сверяет
  метаданные реального объекта и только затем делает изображение видимым;
- `DELETE /api/v1/catalog/items/{itemId}/images/{imageId}` удаляет изображение.

Чтение требует `catalog.view`, остальные операции — `catalog.manage`. Допустимы
JPEG, PNG и WebP размером до 10 МБ, не более восьми изображений на карточку.

# Связи карточек

- `GET /api/v1/catalog/items/{itemId}/relations` — сохранённые связи карточки;
- `GET /api/v1/catalog/dependencies/{dependencyId}/candidates` — серверный поиск
  карточек исходной категории, параметры `search` и `limit`;
- `PUT /api/v1/catalog/items/{itemId}/relations` — полная атомарная замена
  набора связей.

Тело замены является массивом объектов `dependencyId` и `sourceItemId`.
Количество не передаётся и не хранится. Чтение и поиск требуют `catalog.view`,
изменение — `catalog.manage`.

# XLSX и массовые операции

- `GET /api/v1/catalog/template.xlsx` — актуальный шаблон всего каталога;
- `GET /api/v1/catalog/template.xlsx?categoryId={uuid}` — шаблон категории;
- `GET /api/v1/catalog/export.xlsx` — полный экспорт с необязательными
  `categoryId`, `sectionId`, `status` и `search`;
- `POST /api/v1/catalog/import.xlsx` — импорт `.xlsx` до 10 МБ из multipart-поля
  `file`;
- `POST /api/v1/catalog/items/bulk` — массовая операция над 1–500 UUID.

Шаблон и экспорт требуют `catalog.view`, импорт и массовые изменения —
`catalog.manage`. Массовое тело содержит `itemIds`, действие `set_status` или
`delete`, а для статуса также `status`. Экспорт не использует пагинацию списка.
