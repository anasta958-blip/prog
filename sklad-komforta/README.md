# Склад Комфорта

Новая версия системы на ASP.NET Core, Flutter, PostgreSQL и Redis.

Проект создаётся отдельно от действующего PHP-приложения. Исходное приложение и рабочая база не изменяются.

## Текущее состояние

- Итерация 1: аудит действующей системы, базы и бизнес-правил.
- Итерация 2: технический каркас ASP.NET Core 10, Flutter для Windows, macOS, Web, Android и iOS, PostgreSQL, Redis, MinIO и Mailpit.
- Итерация 3: JWT/TOTP, refresh-сессии устройств, onboarding директора,
  schema-per-tenant и настраиваемые роли организации.
- Итерация 4: реализованы tenant-схема карточек, защищённый REST API и выбранный
  карточный Flutter-каталог с динамическим редактором.
- Итерация 5: пространство «Компания» разделено на настройки организации,
  клиентов, сотрудников со структурой и права доступа; добавлен единый срок
  активности tenant-а.

## Документы первой итерации

- [Обзор аудита](docs/iteration-01/README.md)
- [Архитектура текущей системы](docs/iteration-01/current-system.md)
- [Аудит базы данных](docs/iteration-01/database-audit.md)
- [Бизнес-правила](docs/iteration-01/business-rules.md)
- [Целевая архитектура](docs/iteration-01/target-architecture.md)
- [План миграции](docs/iteration-01/migration-plan.md)
- [Требует подтверждения](docs/iteration-01/requires-confirmation.md)
- [Инвентаризация файлов](docs/iteration-01/file-inventory.md)
- [Действующие API-операции](docs/iteration-01/api-actions.md)

## Документы второй итерации

- [Обзор итерации](docs/iteration-02/README.md)
- [Структура и границы](docs/iteration-02/architecture.md)
- [Запуск разработки](docs/iteration-02/development.md)
- [Проверки](docs/iteration-02/verification.md)
- [Состав компонентов](docs/iteration-02/components.md)

## Документы третьей итерации

- [Авторизация и multi-tenant](docs/iteration-03/README.md)
- [Сценарий авторизации и API](docs/iteration-03/authentication.md)
- [Tenant-роли и разрешения](docs/iteration-03/authorization.md)
- [Flutter-клиент](docs/iteration-03/flutter-client.md)
- [Первичная настройка организации](docs/iteration-03/organization-onboarding.md)
- [Проверки итерации](docs/iteration-03/verification.md)
- [Согласованные варианты авторизации](docs/iteration-03/authentication-design-options.png)
- [Правила документирования](docs/documentation-rules.md)

## Документы четвёртой итерации

- [Обзор каталога](docs/iteration-04/README.md)
- [Модель и хранение](docs/iteration-04/catalog-model.md)
- [REST API](docs/iteration-04/catalog-api.md)
- [Flutter-клиент](docs/iteration-04/flutter-client.md)
- [Утверждённый вариант 2](docs/iteration-04/catalog-ui-variant-2.png)
- [Проверки этапа](docs/iteration-04/verification.md)

## Документы пятой итерации

- [Обзор пространства «Компания»](docs/iteration-05/README.md)
- [Модель и миграции](docs/iteration-05/company-model.md)
- [REST API и безопасность](docs/iteration-05/company-api.md)
- [Flutter-клиент](docs/iteration-05/flutter-client.md)
- [Проверки](docs/iteration-05/verification.md)

## Инструменты аудита

```powershell
php scripts\audit_legacy_dump.php path\to\dump.sql
php scripts\compare_legacy_schema.php path\to\schema.sql path\to\dump.sql
```

Скрипты читают SQL-файлы и выводят агрегированный JSON. Они не подключаются к базе и не выполняют SQL.
