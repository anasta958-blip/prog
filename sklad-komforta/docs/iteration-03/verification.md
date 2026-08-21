# Проверка итерации 3

## Автоматические проверки

- `dotnet build SkladKomforta.sln --no-restore` — успешно, 0 предупреждений;
- 22 domain unit-теста — успешно;
- 6 API integration-тестов — успешно;
- `flutter analyze` — замечаний нет;
- 2 Flutter widget-теста — успешно;
- Docker API/Worker — успешно пересобраны, readiness отвечает;
- Flutter Web release — успешно собран.

После разделения Identity был дополнительно проверен startup Worker: API-only
регистрации вынесены в `AddIdentityInfrastructure`, контейнер остаётся в состоянии
`Up`, а `RestartCount` после контрольного ожидания равен нулю.

## Docker smoke

В пустой тестовой базе последовательно проверены:

- bootstrap первого директора;
- смена временного пароля;
- настройка и проверка TOTP;
- выдача recovery-кодов и отдельный вход одним из них;
- создание организации и tenant-схемы;
- чтение ролей, прав и сотрудников;
- создание пользовательской роли;
- отзыв текущей сессии через logout.

После обеих проверок созданные пользователи, организации и tenant-схемы
удалены. `schema_migrations` и рабочая структура базы не изменялись.

## Ограничения локальной среды

- Windows widget-тесты требуют временного пути Flutter SDK без пробелов из-за
  native-assets hook пакета `objective_c`; код приложения здесь ни при чём.
- Windows native build упирается в тот же локальный путь SDK
  `D:\Program Files\...` внутри MSBuild subprocess.
- Android build обнаружил требование `flutter_secure_storage` к compile SDK 37,
  тогда как текущий проект использует Flutter compile SDK 36. Локальный SDK
  установил платформу в каталог `android-37.0`, который текущий Gradle plugin не
  распознаёт как `android-37`. Зависимость или Android toolchain нужно выровнять
  перед release-сборкой.
- macOS и iOS нативно собираются только на macOS с Xcode и signing profiles.
