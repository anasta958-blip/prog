# Обновления в реальном времени

Канбаны (включая КП/ПКП), каталог и пространство «Компания» обновляются у всех
пользователей организации без ручного обновления страницы: изменение карточки,
перенос, архив, сохранение предложения, просмотр клиентской ссылки и выбор
клиента; изменения товаров, изображений, связей, импорт и массовые операции;
настройки организации и профиль, юридические лица, клиенты, сотрудники, роли и
назначение прав.

## Принцип

Сервер рассылает только **сигнал** «данные изменились» с идентификаторами — без
самих данных. Получив сигнал, клиент перечитывает нужные страницы обычными
запросами API. Поэтому права, фильтры, поиск и расчёты применяются как при
обычной загрузке, а через поток уведомлений ничего не утекает.

```
изменение (REST) ──► RealtimeChangeMiddleware / PostgresQuoteClientAccessService
                         │ IRealtimeNotifier.PublishAsync
                         ▼
                 Redis pub/sub, канал realtime:org:<organizationId:N>
                         │ (все экземпляры API)
                         ▼
                 RealtimeHub ──► WebSocket /api/v1/realtime ──► RealtimeClient (Flutter)
                                                                     │
                                          KanbanController / CatalogController
                                          тихо перечитывают открытые страницы
```

## Сервер

- `Application/Abstractions/Realtime/RealtimeContracts.cs` — `RealtimeTopics`
  (`kanban`, `catalog`, `company`), `RealtimeChange` (для `company` — с
  разделом `Section`), `IRealtimeNotifier`, `IRealtimeTicketStore`.
- `Infrastructure/Realtime/RedisRealtimeNotifier.cs` — публикация в Redis
  pub/sub (ошибка шины только пишется в журнал и не отменяет сохранённое
  изменение) и хранилище одноразовых билетов (в Redis лежит SHA-256 билета,
  погашение атомарное — `GETDEL`).
- `Api/Realtime/RealtimeChangeMiddleware.cs` — после успешного (2xx) изменяющего
  запроса (не GET/HEAD/OPTIONS) с определённой организацией публикует сигнал:
  - `/api/v1/kanbans/...` → `kanban`/`changed`, `boardId` и `entityId`
    (карточка) из маршрута;
  - `/api/v1/catalog/...` → `catalog`/`changed`, `entityId` = товар;
  - `/api/v1/company/configuration...` → `configuration` для `kanban` и
    `catalog` и `company` с разделом `configuration`;
  - `/api/v1/company/profile` → `company`/`profile`;
  - `/api/v1/company/legal-entities...` → `company`/`legal_entities`;
  - `/api/v1/company/clients...` → `company`/`clients`;
  - `/api/v1/company/employees...` → `company`/`employees` (в том числе смена
    пароля сотрудника);
  - `/api/v1/settings/access...` → `company`/`access` (роли и назначения).
  Новый изменяющий endpoint этих модулей получает уведомления автоматически.
- `PostgresQuoteClientAccessService` сам публикует `kanban`/`changed` после
  входа клиента по ссылке (счётчик просмотров) и после отправки выбора: эти
  запросы идут без JWT сотрудника.
- `Api/Realtime/RealtimeHub.cs` — одна подписка Redis на шаблон
  `realtime:org:*` на экземпляр API; сообщения раздаются подключениям своей
  организации и темы. Очередь подключения ограничена 64 сообщениями
  (старые отбрасываются — безопасно, клиент всё равно перечитывает данные).

## API

| Метод | Путь | Право | Ответ |
|---|---|---|---|
| POST | `/api/v1/kanbans/realtime-ticket` | `kanban.view` | `{ ticket, topic: "kanban" }` |
| POST | `/api/v1/catalog/realtime-ticket` | `catalog.view` | `{ ticket, topic: "catalog" }` |
| POST | `/api/v1/company/realtime-ticket` | `company.view` | `{ ticket, topic: "company" }` |
| GET (WebSocket) | `/api/v1/realtime?ticket=…` | одноразовый билет | поток JSON |

Билет живёт 60 секунд и погашается при подключении. WebSocket-endpoint —
осознанное исключение из правила `RequireAuthorization`: браузер не может
передать заголовок `Authorization` при открытии WebSocket, а токен доступа в
адресе попал бы в журналы nginx. Права проверяются при выдаче билета; во время
подключения раз в 60 секунд перепроверяется, что сессия и членство в
организации активны (иначе соединение закрывается с `access_revoked`).

Сообщения сервера (camelCase):

```json
{ "topic": "kanban", "kind": "changed", "boardId": "…", "entityId": "…" }
{ "topic": "company", "kind": "changed", "section": "clients", "entityId": "…" }
```

`kind`: `ready` (подключение установлено), `ping` (раз в 25 секунд, держит
соединение через прокси), `changed`, `configuration`.

nginx (`src/flutter/docker/nginx/*.conf.template`) проксирует
`location = /api/v1/realtime` с заголовками `Upgrade`/`Connection` и таймаутом
чтения 120 секунд.

## Flutter

- `lib/core/network/realtime_client.dart` — `RealtimeClient` (пакет
  `web_socket_channel`): получает билет, подключается, при обрыве
  переподключается с паузой 1, 2, 4, 8, 16, 30 секунд и после восстановления
  выдаёт событие `resync` (сигналы за время обрыва могли быть пропущены).
  Адрес WebSocket выводится из `API_BASE_URL`; относительный адрес Web-сборки
  разрешается от адреса страницы, `http/https` меняются на `ws/wss`.
- `KanbanController` подписывается в `initialize()`. Сигнал текущего канбана
  (или без канбана, или `resync`) через 300 мс тихо перечитывает открытые
  страницы всех столбцов и загруженные страницы архивов с текущими фильтрами и
  поиском; сигнал другого канбана игнорируется; `configuration` перезагружает
  список и структуру канбанов. Пока идёт собственная загрузка или сохранение,
  перечитывание откладывается.
- `CatalogController` так же перечитывает текущую страницу каталога, а на
  `configuration` — и структуру каталога. Открытый редактор товара не
  затрагивается: он работает со своей копией данных.
- `CompanyController` подписывается при первом открытии пространства
  «Компания». Любой сигнал тихо перечитывает списки (юрлица, клиенты,
  сотрудники, роли и права, аудит, срок действия); разделы `configuration` и
  `profile` (и `resync`) — ещё и конфигурацию с профилем.
- Экран настроек (`OrganizationOnboardingPage`, режим настроек) принимает новую
  серверную версию, только если в форме нет несохранённых правок. Иначе правки
  остаются, а пользователь видит предупреждение: сохранение заменит чужие
  изменения, «Выйти без сохранения» покажет актуальную версию. Эхо собственного
  сохранения (та же версия) форму не трогает.
- В тестах источник передаётся через параметр `realtime:` (`RealtimeSource`);
  с подменённым шлюзом и без `realtime:` контроллер не подключается к серверу.

Открытый редактор КП/ПКП не перезаписывается чужими изменениями этого же
предложения: одновременная правка одного КП разными пользователями по-прежнему
решается последним сохранением.
