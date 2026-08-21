# Flutter-клиент авторизации

## Платформы

Один Dart-код используется на Web, Windows, macOS, Android и iOS. Отличается
только adapter хранения refresh-токена и нативная упаковка.

## Слои

- `auth_api.dart` реализует REST и единый API-конверт. Интерфейс `AuthGateway`
  позволяет тестировать контроллер без сети.
- `auth_controller.dart` содержит state machine и не создаёт виджеты.
- `auth_flow_page.dart` отображает этапы входа, QR, recovery-коды и активные
  устройства, а onboarding передаёт отдельному экрану.
- `onboarding_models.dart` описывает полный изменяемый черновик организации.
- `organization_onboarding_page.dart` реализует выбранный семишаговый вариант
  с desktop/mobile-компоновкой и живым предварительным просмотром.
- `token_store.dart` отделяет `TokenRepository` от production secure storage.
- `http_client_factory_web.dart` включает `withCredentials` только для Web,
  чтобы браузер отправлял закрытую refresh-cookie.

## Состояния интерфейса

`loading → login → changePassword → setupTotp/verifyTotp → recoveryCodes →
organization → ready`.

Широкий экран использует двухпанельную композицию. На мобильной ширине
информационная панель убирается, форма остаётся в одной колонке без
горизонтальной прокрутки. Ошибки API показываются внутри текущего шага.

Экран ролей не добавлен намеренно: по правилу проекта для него сначала будут
созданы три структурно разных изображения и выбран один вариант.
