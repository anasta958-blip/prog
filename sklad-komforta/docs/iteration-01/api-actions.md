# Действующие API-операции

Это функциональная карта старого REST-подобного API. В новой версии каждая операция получает отдельный HTTP route и DTO; параметр `action` и большие `switch` не переносятся.

## Авторизация

`api/auth.php`:

- `login`: проверка логина/пароля, создание PHP-сессии, выдача CSRF;
- `me`: текущий пользователь, РОП и следующий номер заявки;
- `logout`: завершение сессии.

## Права

`api/permissions.php`:

- `my`: эффективная политика текущего пользователя;
- `policies`: политики всех фиксированных ролей;
- `save_policy`: сохранение JSON-политики роли;
- `users`: пользователи для настройки области видимости.

## Пользователи

`api/users.php`:

- `list`, `create`, `update`, `delete`;
- `set_director`: назначение директора.

При удалении текущий API переносит принадлежащие пользователю компании, клиентов, подрядчиков, КП/ПКП, документы и комплектации выбранному пользователю. В новой системе это должно быть явной domain-командой с аудитом, а не частью обычного удаления.

## Каталог

`api/catalog.php`:

- справочники: `categories`, `sections`, `groups`, `suppliers`, `all_suppliers`, `units`;
- группы: `save_group`, `delete_group`;
- единицы: `save_unit`, `delete_unit`;
- поставщики: `save_supplier`, `delete_supplier`;
- карточки: `names`, `names_by_name`, `names_search`, `all_names`, `create_name`, `update_name`, `delete_name`;
- работы: `services`, `create_service`, `update_service`, `delete_service`;
- связи: `linkable_catalog_items`;
- импорт: `import_catalog_excel`.

Экспорт каталога частично формируется на frontend; в новой системе импорт и экспорт реализуются backend job/API с единым XLSX-контрактом.

## КП

`api/kp.php`:

- builder-каталог: `catalog_products`, `catalog_services`, `catalog_sections`;
- сохранение новых карточек из КП: `save_catalog_product`, `save_catalog_service`;
- удаление каталога из контекста КП: `delete_catalog_product`, `delete_catalog_service`;
- компании: `company_get`, `company_save`, `company_set_default`, `company_delete`, `company_lookup_inn`;
- клиенты/подрядчики: `clients`, `contractors`, `save_client`, `save_contractor`, `delete_client`, `delete_contractor`;
- предложения: `quotes`, `quote_meta`, `quote_detail`, `save_quote`, `delete_quote`;
- канбан: `set_quote_kanban_orders`, `set_quote_status`, `set_quote_workflow`, `set_quote_archive`.

`quote_detail` разделён на мету и полный payload для ускорения открытия. Нормализованные позиции синхронизируются при сохранении.

## ПКП

`api/pkp.php`:

- повторяет builder-каталог, компании, клиентов и операции предложений КП;
- `transfer_to_kp`: создаёт КП из ПКП;
- имеет собственные статусы и канбан.

В новой системе КП и ПКП используют один Quotes-модуль и одну таблицу `quotes`, различаясь полем `kind`, workflow и доступными категориями.

## Комплектация

`api/orders.php`:

- `next_order_num`, `save_order`;
- `orders`, `order_detail`, `update_order`, `delete_order`;
- `set_archive_state`;
- `upload_order_invoice`, `order_invoice_pdf`, `delete_order_invoice`.

## Документы

`api/documents.php`:

- `upload_image`;
- `list`, `detail`, `save`, `delete`.

Версии создаются внутри `save`. В новой системе рекомендуются явные routes шаблона и версии, чтобы сохранение текущего draft и публикация версии не смешивались.

## Уведомления и версия

- `api/email.php`: отправка сформированного файла по email.
- `api/telegram.php`: отправка PDF/HTML в Telegram.
- `api/version.php`: проверка хеша версии приложения.
- `api/meta.php`: агрегированная загрузка справочников.

## Целевой стиль routes

Пример замены:

```text
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
POST   /api/v1/auth/totp/verify
GET    /api/v1/catalog/items
POST   /api/v1/catalog/items
PATCH  /api/v1/catalog/items/{id}
GET    /api/v1/quotes/{id}
PUT    /api/v1/quotes/{id}
POST   /api/v1/quotes/{id}/workflow-transitions
POST   /api/v1/pkp/{id}/convert-to-kp
GET    /api/v1/orders/{id}
POST   /api/v1/orders/{id}/invoices
POST   /api/v1/document-templates/{id}/render
```

Все ответы используют единый контракт ошибки с `code`, `message`, `traceId` и списком validation errors. Успешные ответы не обязаны оборачиваться в поле `data`, если HTTP-код и DTO однозначны.
