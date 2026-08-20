# Проверки итерации 2

## Автоматические

```powershell
dotnet build SkladKomforta.sln --no-restore
dotnet test SkladKomforta.sln --no-build --no-restore

cd src/flutter
flutter analyze
flutter test
```

Проверяется:

- безопасная и стабильная генерация tenant-схемы;
- отклонение произвольных SQL-идентификаторов;
- access token 15 минут;
- refresh token 7 дней для Web и 30 дней для остальных устройств;
- доступность API bootstrap и liveness endpoint;
- русская локализация технического Flutter bootstrap.

Платформенный каталог macOS создан и проверяется общими `flutter analyze` и widget-тестами. Нативная сборка `.app` на Windows невозможна; её smoke-тест выполняется на macOS с Xcode перед выпуском.

## Compose

Структура проверяется командой:

```powershell
docker compose --env-file .env.example config --quiet
```

## Выполненный контейнерный smoke-test

Development-стек фактически собран и запущен в Docker Desktop:

- API и Worker успешно опубликованы внутри multi-stage Docker build;
- PostgreSQL 18 прошёл health-check и применил `public/0001_bootstrap.sql`;
- в `public.schema_migrations` записана версия `0001_bootstrap`;
- Redis прошёл health-check и ответил `PONG` с включённой аутентификацией;
- MinIO прошёл health-check, а `minio-init` создал приватный bucket `sklad-komforta` и завершился с кодом 0;
- Mailpit прошёл health-check;
- `/health/live`, `/health/ready` и `/api/v1` вернули HTTP 200;
- API, Worker, PostgreSQL, Redis, MinIO и Mailpit сохранили `restart_count=0` после контрольного ожидания.

Во время первого прогона были обнаружены и исправлены две ошибки Compose: mount PostgreSQL 18 перенесён на `/var/lib/postgresql`, а credentials `minio-init` теперь корректно раскрываются shell. Worker переведён на ASP.NET Core runtime, поскольку Infrastructure использует shared framework `Microsoft.AspNetCore.App`.
