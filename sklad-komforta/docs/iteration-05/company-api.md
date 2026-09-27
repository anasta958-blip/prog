# REST API пространства «Компания»

## Настройки

- `GET/PUT /api/v1/company/profile` — основной профиль;
- `GET/PUT /api/v1/company/configuration` — канбаны, каталог, поля, зависимости
  и справочники. Роли этим endpoint-ом больше не синхронизируются;
- `GET /api/v1/company/configuration/categories/{clientId}/deletion-impact` —
  предварительно считает карточки, изображения и связи удаляемой категории;
- `GET /api/v1/company/lifecycle` — единый срок и признак заморозки.
- `GET /api/v1/company/audit` — последние действия текущей организации;
  требует право `company.audit.view`. Ответ содержит `diff` с состояниями
  `before/after`, из которых клиент строит читаемый список изменённых полей.

`PUT /configuration` принимает объект `draft` и список
`deleteCategoryData`. Категория с рабочими данными не удаляется без её
`clientId` в этом списке. При явном подтверждении карточки, метаданные
изображений и межкарточные связи удаляются одной транзакцией; объекты
изображений удаляются из S3/MinIO после коммита, а операция фиксируется в
`audit_log` как `catalog_category/deleted_with_data`.

## Юридические лица

- `GET/POST /api/v1/company/legal-entities`;
- `PUT/DELETE /api/v1/company/legal-entities/{id}`.

Права: `company.legal_entities.view/manage`. После удаления исполнителя по
умолчанию сервер назначает первым оставшееся юридическое лицо.
Адрес, email, сайт, вводный и дополнительный тексты необязательны; остальные
реквизиты формы проверяются как обязательные на API, включая телефон и
банковские данные.

## Клиенты

- `GET/POST /api/v1/company/clients`;
- `PUT/DELETE /api/v1/company/clients/{id}`.

Права: `company.clients.view/manage`.
Для физического лица обязательны ФИО, телефон и паспортные данные. Для ИП/ООО
обязательны название, телефон, регистрационные и банковские реквизиты. Email и
адрес остаются необязательными.

## Поиск реквизитов по ИНН

- `GET /api/v1/company/legal-entities/registry-lookup?inn=...` — право
  `company.legal_entities.manage`;
- `GET /api/v1/company/clients/registry-lookup?inn=...` — право
  `company.clients.manage`.

Оба адреса вызывают один обработчик; два маршрута нужны, чтобы поиск был
доступен тем, кто может редактировать соответствующий раздел. Ответ —
`CompanyRegistryRecord` (`Application/Company/CompanyRegistryContracts.cs`):
`companyType` (`ooo`/`ip`), `name` (сокращённое наименование), `legalName`,
`inn`, `kpp`, `ogrn`, `address`, `email`, `directorName`, `directorTitle`. Ничего не
сохраняется: форма только предзаполняется.

Источник — публичный сервис ФНС `egrul.nalog.ru`, как в прежней PHP-версии
(`EgrulCompanyRegistryLookup`):

1. `POST /` с ИНН → токен поиска; `GET /search-result/{t}` → JSON с
   наименованиями, ИНН, ОГРН, КПП и руководителем (`EgrulResponseParser.ParseSearchResult`);
2. `vyp-request` → опрос `vyp-status` (до 8 с) → `vyp-download`; с первых двух
   страниц PDF через PdfPig читаются адрес юрлица (`ParseAddress`) и e-mail
   (`ParseEmail`, длинный адрес склеивается из перенесённых строк и приводится
   к нижнему регистру). Сбой этого шага не ломает ответ — поля остаются `null`.

ИНН сначала проверяется по контрольной сумме (`Domain/Company/TaxpayerNumber`).
Успешный ответ кэшируется в Redis на 24 часа (`registry:egrul:v2:{inn}`).
Банковские реквизиты в реестре не публикуются. Место жительства ИП в публичной
выписке ЕГРИП отсутствует; «адрес регистрирующего органа» — это адрес инспекции
ФНС, поэтому у ИП `address` всегда `null`.

| Код | HTTP | Когда |
|---|---|---|
| `inn_invalid` | 400 | неверная длина или контрольное число |
| `registry_not_found` | 404 | в ЕГРЮЛ/ЕГРИП нет записи |
| `registry_unavailable` | 503 | сеть, таймаут 30 с или ФНС запросила капчу |

Формат ответов ФНС неофициальный и может измениться; разбор покрыт тестами
`EgrulResponseParserTests`, в том числе на раскладке текста PdfPig.

## Сотрудники

- `GET/POST /api/v1/company/employees`;
- `PUT/DELETE /api/v1/company/employees/{membershipId}`.

Создание атомарно добавляет `public.users`, членство, одну роль, руководителя и
профиль. Пароль проверяется общей `PasswordPolicy` и является одноразовым.
Удаление мягкое, отзывает refresh-сессии и не удаляет аудит. Директор защищён от
отключения и удаления.

## Роли

`/api/v1/settings/access` использует `RoleSummary` с `subordinateRoleIds` и
назначает сотруднику один `roleId` вместе с `supervisorMembershipId`. Сервер
проверяет существование ролей, допустимость связи и отсутствие циклов. Доступ к
этому подпространству проверяется кодами `company.access.view/manage`; изменения
ролей, прав и подчинённости записываются в `audit_log`. Роль, назначенную хотя бы
одному сотруднику, удалить нельзя.

Системную роль «Директор» нельзя назначить подчинённой другой
роли. Это ограничение действует и в интерфейсе, и в серверной проверке.

## Заморозка

`PostgresTenantAccessValidator` проверяет срок на каждом tenant-запросе.
`RefreshAsync` не ротирует токен просроченной организации, а вход возвращает
ошибку `organization_expired`, а не отправляет сотрудника в onboarding.
