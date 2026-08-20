# Состав компонентов итерации 2

## Корень проекта

- `SkladKomforta.sln` объединяет backend и два тестовых проекта.
- `global.json` фиксирует .NET SDK 10.0.400 и разрешает только совместимый patch.
- `Directory.Build.props` включает актуальные анализаторы, проверку code style и преобразует предупреждения ручного C#-кода в ошибки сборки.
- `.editorconfig` фиксирует UTF-8, окончания строк и отступы.
- `.gitignore` исключает секреты, build/cache и локальные IDE-файлы.
- `.dockerignore` сокращает build context API/Worker и не отправляет в Docker Flutter, тесты, документацию и локальные секреты.
- `compose.yaml` описывает PostgreSQL, Redis, MinIO, Mailpit, API и Worker. PostgreSQL 18 монтирует volume на `/var/lib/postgresql`, чтобы кластер хранился в version-specific подкаталоге; `minio-init` создаёт закрытый bucket после health-check основного MinIO.
- `.env.example` перечисляет обязательные development-переменные без production-секретов.

## Domain

### `TenantSchemaName`

Доменное значение безопасного PostgreSQL-идентификатора. `Create` детерминированно формирует имя из UUID организации. `Parse` разрешает восстановление только строки формата `tenant_` плюс 32 hex-символа. `ToString` возвращает уже проверенное значение. Ни один HTTP-параметр не используется как имя схемы напрямую.

### `DeviceType`

Стабильное числовое перечисление типов сессий: Web, Windows, Android, iOS и macOS. Значения синхронизированы с ограничением `refresh_sessions.device_type` в public-миграции.

### `TokenLifetimePolicy`

`AccessTokenLifetime` задаёт 15 минут для access-токена. `GetRefreshTokenLifetime` возвращает 7 дней для Web и 30 дней для нативных Windows, macOS, Android и iOS приложений.

## Application

- `ITenantContext` описывает scoped-контекст организации: UUID, безопасную схему, состояние resolution, установку и очистку.
- `IDatabaseConnectionFactory` разделяет public и tenant-соединения.
- `IApplicationCache` задаёт чтение, TTL-запись и удаление строковых значений без зависимости от Redis.
- `IObjectStorage` задаёт pre-signed upload/download и удаление закрытого S3-объекта.
- `ApiResponse<T>`, `ApiResponse` и `ApiError` формируют единый контракт `{ok, data, error}`.

## Infrastructure

### Конфигурация

`DatabaseOptions`, `RedisOptions`, `ObjectStorageOptions` и `JwtOptions` связывают environment/JSON с типизированными параметрами. `ObjectStorageOptions` разделяет внутренний `ServiceUrl` и подписываемый `PublicUrl`, потому что host входит в S3 SigV4.

### Реализации

- `TenantContext` вычисляет схему из UUID и очищается после запроса.
- `PostgresConnectionFactory` использует общий Npgsql pool и задаёт `search_path` для tenant-соединения.
- `RedisApplicationCache` использует потокобезопасный singleton multiplexer.
- `S3ObjectStorage` выполняет операции внутренним S3 client, а ссылки подписывает отдельным client с публичным endpoint. `NormalizeObjectKey` запрещает пустой ключ и `..`.
- `DependencyInjection.AddInfrastructure` проверяет конфигурацию при старте и регистрирует корректные lifetimes adapter-ов.

### Health

`PostgresHealthCheck` выполняет `SELECT 1`, `RedisHealthCheck` выполняет PING, `ObjectStorageHealthCheck` проверяет bucket. Они включены только в readiness; liveness подтверждает работоспособность процесса и не зависит от внешней сети.

## API

- `Program.cs` собирает pipeline: Problem Details, infrastructure, JWT validation, exception mapping, correlation ID, authentication, tenant resolution, authorization, versioned API и health endpoints.
- `CorrelationIdMiddleware.InvokeAsync` принимает или создаёт `X-Correlation-ID`, записывает его в trace и response.
- `TenantResolutionMiddleware.InvokeAsync` читает `organization_id` только из проверенного JWT, заполняет scoped-контекст и очищает его в `finally`.

## Worker

`Worker.ExecuteAsync` поддерживает корректный lifetime фонового процесса до добавления отдельных обработчиков. Логи старта и остановки созданы через source-generated `LoggerMessage`, чтобы не выделять массив параметров при каждом сообщении. Финальный Docker-образ использует ASP.NET Core runtime, поскольку общий Infrastructure-слой содержит health/options типы из `Microsoft.AspNetCore.App`.

## PostgreSQL

- `migrations/public/0001_bootstrap.sql` создаёт глобальных пользователей, TOTP, организации, членство, device refresh-сессии, журнал tenant-миграций и security audit.
- `migrations/tenant/0001_bootstrap.sql` является шаблоном схемы организации: роли, права, назначения, настройки, компании, клиенты, подрядчики и audit. Placeholder заменяется только provisioner-ом на проверенный `TenantSchemaName`.

## Flutter

### Ручной Dart-код

- `main` инициализирует binding, читает compile-time конфигурацию и запускает приложение.
- `AppConfig.fromEnvironment` читает `API_BASE_URL` и `APP_ENVIRONMENT` из `--dart-define`.
- `SkladKomfortaApp.build` подключает русскую локализацию, общую тему и техническую стартовую страницу.
- `_buildTheme` централизует только базовые цвета и типографику; стили бизнес-модулей появятся после согласования дизайна.
- `_BootstrapPage.build` показывает среду и API для диагностики ошибочной сборки.
- `_TechnicalValue.build` выводит техническое значение с возможностью копирования.
- `app_ru.arb` является текущим русским источником строк; `app_en.arb` сохраняет архитектурную возможность будущего языка.

### Платформенные оболочки

- `windows/` содержит runner и CMake-конфигурацию Windows.
- `macos/` содержит Swift runner, Xcode project/workspace, entitlements, plist, menu и app icons.
- `web/` содержит HTML manifest, bootstrap и web icons.
- `android/` содержит Gradle-проект и Android manifest.
- `ios/` содержит Swift/Xcode runner и настройки подписи iOS.

Платформенные оболочки генерируются Flutter. Бизнес-логика в них не размещается; ручные изменения допустимы только для разрешений, подписи, deep links, secure storage и других нативных интеграций.

## Тесты

- `TenantSchemaNameTests` проверяет стабильное имя и отклонение небезопасных идентификаторов.
- `TokenLifetimePolicyTests` проверяет access/refresh сроки для пяти платформ.
- `ApiBootstrapTests` проверяет liveness и единый API response через in-memory host.
- `widget_test.dart` проверяет запуск общей Flutter-оболочки и русскую локализацию.
