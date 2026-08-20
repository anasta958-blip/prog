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
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8080/api/v1
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api/v1
flutter run -d macos --dart-define=API_BASE_URL=http://localhost:8080/api/v1
flutter run -d 24095PCADG
```

Для Android URL локального API обычно указывается как `http://10.0.2.2:8080/api/v1`. macOS и iOS собираются только на компьютере Apple с Xcode, хотя общий Dart-код и платформенный каркас хранятся и разрабатываются в этом репозитории на Windows.

## Миграции

`migrations/public/0001_bootstrap.sql` автоматически применяется PostgreSQL только при создании пустого Docker volume. Tenant-шаблон не запускается вручную: будущий provisioner создаст безопасное имя схемы, применит шаблон транзакционно и запишет версию в `public.tenant_migrations`.
