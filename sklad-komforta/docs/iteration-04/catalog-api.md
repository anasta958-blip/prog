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
