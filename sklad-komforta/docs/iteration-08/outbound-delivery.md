# Итерация 08. Внешняя отправка документов

PDF КП, ПКП и комплектации отправляется в Telegram-группу (при необходимости —
в её топик) или письмом. Файл — тот же, что при печати; формирует и отправляет
его сервер, поэтому токен бота и пароль почты не покидают сервер.

## Права

| Право | Что даёт |
|---|---|
| `outbound.settings.manage` | Раздел «Внешняя отправка»: чтение, сохранение, проверка |
| `documents.send` | Кнопка «Отправить» в редакторах и пункты меню карточки |

Отправка дополнительно требует права просмотра документа (`quotes.view` или
`orders.view`) и видимости карточки. У директора (`system.full_access`) оба
права есть сразу; остальным ролям назначаются в «Права доступа».

## Данные (`migrations/tenant/0038_outbound_delivery.sql`)

- `outbound_settings` — одна строка (`id = 1`):
  - Telegram: `telegram_bot_token` (bytea, зашифрован), `telegram_chat_id`
    (`-100…` или `@имя`), `telegram_uses_topics`, `telegram_default_topic_id`,
    `telegram_caption_template`;
  - почта: `email_address`, `email_password` (bytea, зашифрован),
    `email_sender_name`, `email_smtp_host`, `email_smtp_port`,
    `email_subject_template`, `email_body_template`, `email_default_recipient`.
- `outbound_telegram_topics` — справочник топиков: `topic_id`, `name`,
  `sort_order`.
- Ограничение шага первичной настройки расширено до 10.

Секреты шифруются AES-GCM ключом, выведенным HKDF из
`Security:TotpEncryptionKey` с назначением `outbound-delivery`
(`OutboundSecretProtector`). Клиенту возвращаются только признаки
`hasBotToken` / `hasPassword`; в аудит попадают они же (замена секрета без
других правок записывается как `secretsReplaced`). При смене адреса почты
без нового пароля сохранённый пароль удаляется.

## Шаблоны и имя файла

`OutboundTemplate` (Application) подставляет в тему письма, подпись в Telegram
и текст письма:

| Подстановка | Значение |
|---|---|
| `{документ}` | «КП», «ПКП» или «Комплектация» |
| `{номер}` | номер карточки |
| `{название}` | название карточки (адрес объекта) |
| `{заказчик}` | заказчик документа |
| `{дата}` | дата отправки `дд.мм.гггг` |

Неизвестные слова в фигурных скобках остаются как есть. По умолчанию тема и
подпись — `{документ} №{номер} — {название}`. Пустая подпись — в Telegram
уходит только файл; пустая тема заменяется шаблоном по умолчанию. Подпись
обрезается до 1024 символов (предел Telegram).

Имя файла — `название карточки — дд.мм.гггг.pdf` без недопустимых символов.
Дату присылает клиент (`clientDate`, календарь пользователя); без неё берётся
дата сервера (UTC).

## Правила отправки

- **Telegram.** Группа без топиков — в общий чат. С топиками: если задан топик
  по умолчанию, отправка всегда идёт в него (присланный `topicId`
  игнорируется); иначе топик обязателен и должен быть в справочнике.
- **Почта.** Если задан получатель по умолчанию, письмо всегда уходит ему;
  иначе адрес обязателен.
- **КП/ПКП** из редактора — с выбором, как при печати (вариант, тип или весь
  документ); из меню карточки — весь документ. Комплектация — её PDF.
- Отправляется сохранённая версия: при несохранённых правках редактор
  спрашивает «Сохранить и отправить?».
- Каждая отправка пишется в аудит: `kanban_card`, действие `sent_telegram` /
  `sent_email`, документ, способ, куда и имя файла.

## Почтовый сервер

`SmtpServerPresets`: Gmail (`gmail.com`, `googlemail.com`), Яндекс
(`yandex.ru`, `ya.ru`, `yandex.com`, `yandex.by`, `yandex.kz`, `narod.ru`) и
Mail.ru (`mail.ru`, `inbox.ru`, `list.ru`, `bk.ru`, `internet.ru`) — порт 465.
Для других доменов сервер и порт обязательны; порты — 465, 587, 25, 2525.

`SmtpEmailTransport` (MailKit): 465 — TLS сразу, остальные — обязательный
STARTTLS. Адрес сервера задаёт организация, поэтому сервер подключается
только к публичным IP: имя разрешается заранее, частные, локальные и
служебные адреса отклоняются, сокет открывается к проверенному адресу (подмена
DNS после проверки не действует). Для тестового SMTP в локальной сети:
`Outbound:AllowPrivateSmtpHosts=true`, по умолчанию выключено. В Docker
задаётся в `.env` / `.env.production` переменной
`OUTBOUND_ALLOW_PRIVATE_SMTP_HOSTS=true` (`compose.yaml` и
`compose.production.yaml` передают её API как
`Outbound__AllowPrivateSmtpHosts`), затем `docker compose up -d api`. Остальные
требования остаются: имя сервера с точкой, порт 465/587/25/2525 и TLS, поэтому
Mailpit (`mailpit:1025` без TLS) для этой отправки не подходит.

## Telegram

`TelegramBotTransport`: Bot API `sendDocument` (файл) и `sendMessage`
(проверка). Токен входит в адрес запроса, поэтому именованный `HttpClient`
`telegram-bot` зарегистрирован с `RemoveAllLoggers()` — токен не попадает в
логи. Имя файла передаётся в UTF-8. Ошибки Bot API переводятся в понятные
тексты (неверный токен, группа или топик не найдены, у бота нет прав, лимит
частоты, слишком большой файл) — 502 `outbound_telegram_failed`.

## API

| Метод | Путь | Право |
|---|---|---|
| GET | `/api/v1/company/outbound` | `outbound.settings.manage` |
| PUT | `/api/v1/company/outbound` (`SaveOutboundSettingsRequest`) | `outbound.settings.manage` |
| POST | `/api/v1/company/outbound/test/{telegram\|email}` | `outbound.settings.manage` |
| GET | `/api/v1/outbound/channels` | `documents.send` |
| POST | `/api/v1/outbound/kanbans/{boardId}/cards/{cardId}/send` (`SendDocumentRequest`) | `documents.send` |

- `SaveOutboundSettingsRequest`: `telegram {botToken, clearBotToken, chatId,
  usesTopics, defaultTopicId, topics[{topicId, name}], captionTemplate}`,
  `email {address, password, clearPassword, senderName, smtpHost, smtpPort,
  subjectTemplate, bodyTemplate, defaultRecipient}`. Пустой `botToken` /
  `password` — оставить сохранённый.
- `OutboundChannels`: `telegramReady`, `telegramTopicRequired`, `topics`,
  `emailReady`, `emailRecipientRequired`.
- `SendDocumentRequest`: `channel`, `topicId?`, `recipient?`,
  `proposalTypeId?`, `variantId?`, `clientDate?` → `SendDocumentResult`
  (`channel`, `destination`, `fileName`).
- Проверка: Telegram — в топик по умолчанию, иначе в первый топик справочника
  или общий чат; почта — получателю по умолчанию, иначе на адрес отправителя.
- Ошибки: 400 `outbound_settings_invalid`, `outbound_channel_invalid`,
  `outbound_topic_required`, `outbound_topic_invalid`,
  `outbound_recipient_required`, `outbound_recipient_invalid`; 409
  `outbound_not_configured`, `outbound_document_unsupported`; 502
  `outbound_telegram_failed`, `outbound_email_failed`.
- Отправка вынесена из `/api/v1/kanbans`, чтобы не рассылать сигнал обновления
  канбанов; сохранение настроек рассылает сигнал компании с разделом
  `outbound` (проверка — нет).

## Flutter

- `lib/features/outbound/`:
  - `outbound_models.dart` — `OutboundChannel`, `OutboundSettingsModel`
    (новые `botToken`/`password` уходят только при вводе), `OutboundChannels`,
    `OutboundSendResult`, подстановки и пример шаблона;
  - `outbound_api.dart` — `OutboundGateway` / `OutboundApi`;
  - `outbound_settings_controller.dart` — загрузка, правки (`dirty`),
    сохранение, проверка, перечитывание по сигналу реального времени без
    затирания несохранённых правок;
  - `outbound_settings_editor.dart` — раздел: Telegram (токен, ID группы,
    «Группа с топиками», справочник топиков, топик по умолчанию, подпись) и
    почта (адрес с подсказкой определённого сервера, пароль приложения,
    сервер и порт для других доменов, «От кого», получатель по умолчанию, тема
    и текст), кнопки «Проверить», пример подстановки под шаблонами;
  - `outbound_send.dart` — `loadOutboundChannels`, `sendCardDocument` (выбор
    топика и ввод адреса — только без значений по умолчанию; результат и
    ошибки — сообщением), `OutboundSendButton` (меню «В Telegram» / «На
    почту»).
- Шаг «Внешняя отправка» (индекс 8) — в первичной настройке перед «Проверкой»
  и во вкладках «Настройки организации». Его данные не входят в черновик
  конфигурации: кнопка страницы сохраняет раздел на сервер («Сохранить и
  продолжить» в мастере сначала сохраняет раздел). Уход с несохранёнными
  правками раздела предупреждает так же, как остальные вкладки.
- Кнопка «Отправить» — в командных панелях редакторов КП/ПКП и комплектации;
  пункты «В Telegram» / «На почту» — в меню карточек канбанов КП, ПКП и
  комплектации. Доступность способов перечитывается при открытии канбана и
  после закрытия редактора.
- Аудит: раздел `outbound_settings` («Внешняя отправка»), действия
  `sent_telegram` / `sent_email` и подписи их полей.

## Тесты

- `tests/api-integration/.../OutboundTests.cs` — шаблоны, имя файла,
  определение сервера, проверка настроек, тексты ошибок Telegram, фильтр
  публичных адресов SMTP.
- `DatabaseRegressionTests.OutboundDeliveryAgainstRealDatabase` — на живой
  базе с подменёнными транспортами: секреты не в ответах и аудите, выбор топика
  и получателя, шаблоны, файл, проверка, значения по умолчанию, сброс пароля
  при смене адреса, удаление токена. `RegressionFactory` принимает подмену
  сервисов.
- Flutter: `test/outbound_test.dart` (модель, раздел настроек, сценарий
  отправки), «Сохранить и отправить» в `order_controller_test.dart`, меню
  карточки в `kanban_controller_test.dart`, вкладка в
  `workflow_transfer_settings_test.dart`.

## Не входит

Отправка нескольких документов одним сообщением, история отправок отдельным
списком (есть в аудите), вложение счетов комплектации.
