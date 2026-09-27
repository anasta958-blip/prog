# CLAUDE.md

Новая версия системы «Склад Комфорта»: ASP.NET Core 10 + Flutter + PostgreSQL + Redis + MinIO.
Действующее PHP-приложение и его рабочая база **не изменяются** — этот репозиторий развивается отдельно.
Язык документации, комментариев и сообщений интерфейса — русский (UTF-8).

## Структура

- `src/backend/` — решение `SkladKomforta.sln`. Зависимости только внутрь:
  `Api`/`Worker` → `Infrastructure` → `Application` → `Domain`.
  - `Domain` — правила без HTTP/БД (пароли, TOTP, сроки токенов, имя tenant-схемы).
  - `Application` — контракты сервисов (`*Contracts.cs`), интерфейсы инфраструктуры, расчётные движки (`RuleCalculationEngine`, `Quote*CalculationEngine`, `QuoteVatCalculator`).
  - `Infrastructure` — реализации `Postgres*Service` на чистом Npgsql (без EF/ORM), Redis, S3, PDF (PDFsharp-MigraDoc), XLSX (ClosedXML).
  - `Api` — Minimal API: модуль = `<Module>/<Module>Endpoints.cs`, группа `/api/v1/...`, ответ всегда `ApiResponse.Success(...)`, права через `.RequireTenantPermission("<module>.<action>")`.
- `src/flutter/` — единый клиент для Windows/macOS/Web/Android/iOS. `lib/core` (config, network, security, widgets), `lib/features/<module>/` = `*_api.dart`, `*_models.dart`, `*_controller.dart`, `*_page.dart`. Строки — через `lib/l10n`.
- `migrations/public/` — общие таблицы (пользователи, организации, сессии).
- `migrations/tenant/` — шаблоны схемы каждой организации; встраиваются в `Infrastructure` как EmbeddedResource.
- `tests/backend-unit/` — xUnit, `Domain.Tests`. `tests/api-integration/` — xUnit + `Mvc.Testing`, включая `DatabaseRegressionTests` на живой PostgreSQL.
- `docs/iteration-NN/` — документация по итерациям. `docs/documentation-rules.md` — обязательные правила.

## Multi-tenant — критично для безопасности

- Каждая организация — схема `tenant_<uuid без дефисов>`, имя создаётся только через `TenantSchemaName.Create`. В tenant-таблицах нет `organization_id`.
- Значения из HTTP-запроса **никогда** не подставляются в SQL как идентификаторы; данные — только параметрами Npgsql.
- Каждый новый endpoint обязан иметь `RequireAuthorization()` и `RequireTenantPermission(...)`; новое право добавляется миграцией и в `TenantPermissionMetadata`.
- Файлы в MinIO выдаются только через короткоживущие pre-signed URL после серверной проверки прав.

## Миграции

- Новое изменение — новый файл со следующим номером (`tenant/0035_...sql`). Уже применённые миграции **не редактируются**.
- В tenant-шаблонах схема пишется как `__TENANT_SCHEMA__`; подстановку делает только сервер.
- Tenant-миграции применяются транзакционно при создании организации и фиксируются в `public.tenant_migrations`. Для уже существующих схем применение новых миграций нужно предусмотреть отдельно — проверить, прежде чем полагаться на новую колонку/таблицу.
- `migrations/public/*` применяется Docker-образом PostgreSQL только к пустому volume.
- Каждая миграция кратко описывается в `migrations/README.md`.

## Команды (PowerShell, из корня)

```powershell
docker compose up -d --build                     # postgres, redis, minio, mailpit, api :8080, web :3000
dotnet build SkladKomforta.sln                   # предупреждения = ошибки (Directory.Build.props)
dotnet test SkladKomforta.sln
.\scripts\test-database-regression.ps1           # регрессия БД, нужен .env и поднятый postgres
```

Flutter (SDK: `D:\develop\flutter\bin\flutter.bat`), из `src/flutter`:

```powershell
flutter analyze
flutter test
flutter gen-l10n
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8080/api/v1 --dart-define=PUBLIC_APP_BASE_URL=http://localhost:3000
```

Для Dart/Flutter предпочтительно использовать инструменты MCP-сервера dart-flutter (analyze, format, run_tests, hot reload).

## Правила работы

- Документация обновляется в той же задаче, что и код (`docs/documentation-rules.md`): публичные контракты — XMLDoc/DartDoc, реализации — `<inheritdoc/>`, изменения API/модели — в `docs/iteration-NN/`. Изменение публичного контракта без документации = незавершённая задача.
- Следующая итерация не начинается без явной команды пользователя.
- Сгенерированные Flutter/Gradle/Swift/Xcode-файлы вручную не правятся и не комментируются.
- `TreatWarningsAsErrors` и `AnalysisLevel=latest-recommended` включены — сборка должна проходить без предупреждений.
- Новая бизнес-логика расчётов покрывается unit-тестами; изменения SQL — регрессионными тестами БД; изменения UI-контроллеров — Flutter-тестами.
- Секреты — только в `.env` / `.env.production` (не коммитятся); шаблоны — `.env.example`, `.env.production.example`.
