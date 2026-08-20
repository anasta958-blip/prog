# Склад Комфорта

Новая версия системы на ASP.NET Core, Flutter, PostgreSQL и Redis.

Проект создаётся отдельно от действующего PHP-приложения. Исходное приложение и рабочая база не изменяются.

## Текущее состояние

- Итерация 1: аудит действующей системы, базы и бизнес-правил.
- Итерация 2: технический каркас ASP.NET Core 10, Flutter для Windows, macOS, Web, Android и iOS, PostgreSQL, Redis, MinIO и Mailpit.
- Бизнес-модули ещё не переносятся. Их экраны будут реализованы только после подготовки и согласования трёх вариантов дизайна для каждого экрана.

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
- [Правила документирования](docs/documentation-rules.md)

## Инструменты аудита

```powershell
php scripts\audit_legacy_dump.php path\to\dump.sql
php scripts\compare_legacy_schema.php path\to\schema.sql path\to\dump.sql
```

Скрипты читают SQL-файлы и выводят агрегированный JSON. Они не подключаются к базе и не выполняют SQL.
