# Авторизация

## Сценарий первого входа

1. Директор создаётся закрытым bootstrap endpoint-ом. Endpoint отвечает как
   отсутствующий, если заголовок `X-Bootstrap-Token` неверен.
2. Логин и одноразовый пароль проверяются с rate limit в Redis.
3. Одноразовый пароль заменяется паролем, соответствующим `PasswordPolicy`.
4. API создаёт TOTP-секрет, но до подтверждения хранит его только внутри
   ограниченного challenge в Redis.
5. После верного TOTP секрет сохраняется в PostgreSQL в зашифрованном виде,
   пользователю один раз показываются десять recovery-кодов.
6. После входа директор начинает восьмишаговый onboarding. Первое сохранение
   создаёт tenant-схему и назначает системную роль директора.
7. Черновик сохраняется после каждого шага, а рабочие таблицы заполняются
   атомарно только после финальной проверки и активации.

## Токены и устройства

- Access token — JWT на 15 минут. Он содержит `sub`, `session_id`, имя и после
  onboarding `organization_id`.
- Refresh token — случайное 64-байтовое значение. В базе хранится только его
  SHA-256 хеш.
- При обновлении refresh token атомарно отзывается и заменяется новым.
- Web получает refresh token через `HttpOnly`, `SameSite=Strict` cookie и не
  видит его из Dart/JavaScript.
- Windows, macOS, Android и iOS сохраняют refresh token через
  `flutter_secure_storage`.
- При ответе `401` на защищённый запрос Flutter-клиент один раз ротирует
  refresh token и повторяет исходный запрос. Если refresh-сессия уже отозвана,
  локальные токены очищаются, а пользователь возвращается на экран входа.
- В Development CORS принимает Flutter Web с любого HTTP/HTTPS-порта только на
  loopback-адресе. В production действуют исключительно явно заданные origins.
- Отзыв refresh-сессии сразу закрывает tenant-доступ даже при ещё не истёкшем
  access token, поскольку middleware повторно проверяет сессию.

## REST API

| Метод | Маршрут | Назначение |
|---|---|---|
| POST | `/api/v1/auth/bootstrap/director` | Закрытое создание первого директора |
| POST | `/api/v1/auth/login` | Пароль и выдача challenge следующего шага |
| POST | `/api/v1/auth/initial-password` | Обязательная смена временного пароля |
| POST | `/api/v1/auth/totp/setup` | QR URI и Base32-секрет первичной настройки |
| POST | `/api/v1/auth/totp/confirm` | Подтверждение нового TOTP и recovery-коды |
| POST | `/api/v1/auth/totp/verify` | Обычный вход по TOTP |
| POST | `/api/v1/auth/recovery/verify` | Одноразовый вход recovery-кодом |
| POST | `/api/v1/auth/refresh` | Ротация refresh-сессии |
| POST | `/api/v1/identity/organization` | Создание первой организации директора |
| GET | `/api/v1/onboarding/` | Загрузка прогресса настройки |
| POST | `/api/v1/onboarding/draft` | Сохранение полного черновика |
| POST | `/api/v1/onboarding/activate` | Финальная проверка и активация |
| GET | `/api/v1/identity/sessions` | Список активных устройств |
| DELETE | `/api/v1/identity/sessions/{id}` | Отзыв выбранного устройства |
| DELETE | `/api/v1/identity/sessions` | Отзыв остальных устройств |
| POST | `/api/v1/identity/logout` | Отзыв текущего устройства и удаление cookie |

Все ответы используют конверт `{ok, data, error}`. Прикладные ошибки содержат
стабильный машинный код и безопасный русский текст без SQL/stack trace.

## Управление с клавиатуры

- Поля авторизации используют стандартное адаптивное меню Flutter для
  выделения, удаления и вставки текста мышью или системными сочетаниями клавиш.
- `Enter` в логине переводит фокус на пароль, а `Enter` в пароле отправляет
  форму входа.
- `Enter` в повторе нового пароля, TOTP/recovery-коде и названии организации
  выполняет то же действие, что и основная кнопка текущего этапа.
- Во время выполняющегося запроса повторная отправка формы блокируется.

## Основные файлы

- `Application/Identity/IdentityContracts.cs` — DTO и этапы state machine.
- `Application/Identity/IIdentityService.cs` — независимый от транспорта
  контракт use cases.
- `Infrastructure/Identity/PostgresIdentityService*.cs` — PostgreSQL, Redis,
  TOTP, refresh-сессии и onboarding.
- `Api/Identity/IdentityEndpoints.cs` — тонкое REST-сопоставление.
- `Api/Identity/JwtAccessTokenIssuer.cs` — единственное место выпуска JWT.
