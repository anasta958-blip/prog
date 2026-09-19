# Запуск разработки

## Требования

- .NET SDK 10.0.400 или совместимый patch;
- Flutter 3.38.9 / Dart 3.10.8 или совместимая стабильная версия;
- Docker Desktop с Compose;
- Android Studio/SDK для Android;
- Visual Studio с Desktop development with C++ для Windows;
- macOS с Xcode потребуется для сборки, тестирования и подписи macOS и iOS.

## Конфигурация

1. Скопировать `.env.example` в `.env`.
2. Заменить все development-пароли и `JWT_SIGNING_KEY`.
3. Запустить инфраструктуру:

```powershell
docker compose up --build
```

API будет доступен по `http://localhost:8080`, Mailpit по `http://localhost:8025`, консоль MinIO по `http://localhost:9001`.

## Backend без Docker

```powershell
$env:DOTNET_CLI_HOME = Join-Path (Get-Location) '.dotnet-home'
dotnet restore SkladKomforta.sln
dotnet run --project src/backend/SkladKomforta.Api
```

Подключения можно заменить переменными `Database__ConnectionString`, `Redis__ConnectionString`, `ObjectStorage__*` и `Jwt__*`. В production для внешней управляемой базы меняется строка подключения, а не код.

## Flutter

```powershell
cd src/flutter
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8080/api/v1 --dart-define=PUBLIC_APP_BASE_URL=http://localhost:3000
flutter run -d chrome --web-port=3000 --dart-define=API_BASE_URL=http://localhost:8080/api/v1 --dart-define=PUBLIC_APP_BASE_URL=http://localhost:3000
flutter run -d macos --dart-define=API_BASE_URL=http://localhost:8080/api/v1 --dart-define=PUBLIC_APP_BASE_URL=http://localhost:3000
flutter run -d 24095PCADG
```

Обычный `docker compose up -d` также запускает готовую Flutter Web-сборку на
`http://localhost:3000`. Она обслуживает клиентские ссылки КП/ПКП и проксирует
`/api/v1` в контейнер API, поэтому отдельный `flutter run -d chrome` для открытия
ссылки не требуется.

Для ссылки, открываемой с телефона или другого компьютера, `API_BASE_URL` и
`PUBLIC_APP_BASE_URL` настольной/мобильной сборки должны использовать LAN-IP
компьютера, например `http://192.168.0.105:8080/api/v1` и
`http://192.168.0.105:3000`. Адрес `localhost` работает только на том компьютере,
где запущен Docker Compose.

Для Android URL локального API обычно указывается как `http://10.0.2.2:8080/api/v1`. macOS и iOS собираются только на компьютере Apple с Xcode, хотя общий Dart-код и платформенный каркас хранятся и разрабатываются в этом репозитории на Windows.

## Миграции

`migrations/public/0001_bootstrap.sql` автоматически применяется PostgreSQL только при создании пустого Docker volume. Tenant-шаблон не запускается вручную: будущий provisioner создаст безопасное имя схемы, применит шаблон транзакционно и запишет версию в `public.tenant_migrations`.
