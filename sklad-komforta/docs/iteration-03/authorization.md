# Multi-tenant и разрешения

## Граница tenant

Общие учётные записи, организации, членства, refresh-сессии и security audit
расположены в `public`. Данные каждой организации находятся в схеме вида
`tenant_<uuid без дефисов>`. Имя схемы вычисляется только через
`TenantSchemaName`; клиент не может передать имя схемы строкой.

Перед вызовом tenant endpoint выполняется следующий порядок:

1. JWT middleware проверяет подпись, issuer, audience и срок.
2. `TenantResolutionMiddleware` получает UUID пользователя, сессии и
   организации только из подписанных claims.
3. `PostgresTenantAccessValidator` подтверждает активность всех четырёх
   сущностей и соответствие сессии организации.
4. Только после успеха `TenantContext` вычисляет имя схемы.
5. `PostgresConnectionFactory` задаёт проверенный `search_path`.
6. `TenantPermissionMiddleware` применяет permission metadata endpoint-а.

## Модель ролей

- роли создаются отдельно в каждой организации;
- разрешения представлены стабильными кодами;
- связь роли и разрешений хранится в `role_permissions`;
- связь сотрудника и ролей хранится в `member_roles`;
- `system.full_access` обходит частные проверки только для системных ролей;
- системные роли нельзя переименовать или удалить;
- единственная системная роль организации — «Директор»;
- роль «Администратор» не создаётся автоматически и при необходимости может
  быть заведена директором как обычная настраиваемая роль;
- у директора нельзя отозвать обязательную системную роль директора;
- неизвестные роли и permission codes отклоняются до фиксации транзакции.

## API настроек доступа

| Метод | Маршрут | Требуемое разрешение |
|---|---|---|
| GET | `/api/v1/settings/access/permissions` | `settings.roles.view` |
| GET | `/api/v1/settings/access/roles` | `settings.roles.view` |
| POST | `/api/v1/settings/access/roles` | `settings.roles.manage` |
| PUT | `/api/v1/settings/access/roles/{id}` | `settings.roles.manage` |
| DELETE | `/api/v1/settings/access/roles/{id}` | `settings.roles.manage` |
| GET | `/api/v1/settings/access/members` | `settings.members.view` |
| PUT | `/api/v1/settings/access/members/{id}/roles` | `settings.members.manage` |

## Миграции

- `migrations/public/0002_identity_security.sql` добавляет recovery-коды,
  разрешает pre-onboarding refresh-сессию и добавляет индексы.
- `migrations/tenant/0002_identity_authorization.sql` добавляет разрешения,
  системную роль директора и выдаёт ей полный доступ.
- `migrations/tenant/0016_remove_unused_default_administrator.sql` удаляет
  старую дефолтную роль администратора, только если она никому не назначена.
- Tenant SQL встроен в Infrastructure assembly. Новая организация получает
  миграции в числовом порядке внутри транзакции onboarding.
