# Одна Ubuntu-ВМ и Cloudflare Tunnel

Техническое описание профиля, подготовленного 11.10.2026. Он не заменяет
`compose.yaml` разработки или `compose.production.yaml` с внешними хранилищами.
Полный актуальный маршрут и подтверждённые владельцем результаты см. в
[едином гайде](../virtualbox-server-from-zero.md). Секреты в документации не публикуются.

## 1. Подготовка ВМ и кода

Полная установка VirtualBox/Ubuntu/Docker описана в
[руководстве с нуля](../virtualbox-server-from-zero.md). SSH не требуется:
все команды ниже выполняются прямо в консоли Ubuntu, из папки `sklad-komforta`.
Сеть VirtualBox — NAT, входящие порты на роутере не открываются.

Нужны Python >= 3.11, Git, GnuPG, Docker Engine и актуальный Compose v2/v5:

```bash
sudo apt update
sudo apt install -y python3 gnupg git
python3 --version
sudo docker compose version
```

Перед переносом на ВМ нужно по отдельной команде зафиксировать и отправить
проверенную версию проекта в GitHub. Пока изменения локальные, `git clone`
их не получит. Рабочие дампы, `.env`, volumes и тестовые карточки НЕ переносить.
Нужен собственный домен с активной DNS-зоной Cloudflare и два поддомена.
Ниже `app.example.com` и `files.example.com` — примеры, их заменить своими.

## 2. Создать настройки и запустить внутренние сервисы

```bash
sudo python3 scripts/server.py init --app-domain app.example.com --files-domain files.example.com
sudo python3 scripts/server.py config
sudo python3 scripts/server.py up
sudo python3 scripts/server.py status
```

`init` создаёт `.env.server` (0600), `.env.server.secrets/` (0700) и пустой
файл Tunnel-токена (0600). Повторный `init` ничего не перезаписывает.
Не выполнять `source .env.server`: утилита сама читает строгий формат настроек.
`config` проверяет файл и Compose, не выводя секреты.

`up` собирает Production API, worker и Flutter Web. На чистом volume PostgreSQL
создаёт несуперпользователя `sklad` и применяет `migrations/public/*.sql`.
MinIO создаёт закрытый bucket `sklad-komforta` и пользователя `sklad-app`
с доступом только к этому bucket. Redis защищён отдельным паролем.
Mailpit отсутствует. Ни один Docker-порт не опубликован на ВМ.

Успех: PostgreSQL, Redis, MinIO и web healthy; API/worker running;
`minio-init` exited (0). Состояние exited (0) для этой одноразовой задачи нормально.
По умолчанию Tunnel НЕ запускается, сайт ещё недоступен из интернета.

Проверка внутренней готовности:

```bash
sudo docker compose --env-file .env.server -f compose.server.yaml exec -T web nginx -t
sudo docker compose --env-file .env.server -f compose.server.yaml exec -T web sh -c 'wget -qO- --header="Host: $APP_DOMAIN" http://127.0.0.1/health/ready'
```

Если сборка/healthcheck не прошли, не публиковать сайт. Посмотреть журналы:

```bash
sudo docker compose --env-file .env.server -f compose.server.yaml logs --tail 80 postgres minio-init api web
```

Не присылать журналы без проверки на чувствительные данные. Полный вывод
`docker compose config`/`docker inspect` содержит пароли и не подходит для отчёта.

## 3. Создать первого директора

```bash
sudo python3 scripts/server.py bootstrap
```

Указать логин, русское имя, лимит сотрудников (по умолчанию 5) и временный
пароль не короче 12 символов с заглавной и строчной буквами, цифрой и спецсимволом;
ввод пароля скрыт. API дополнительно проверяет
свои правила пароля. Команда не создаёт организацию автоматически.
Повторный запуск с занятым логином завершится ошибкой, а не заменой аккаунта.

Утилита обращается к внутреннему API через одноразовый curl-контейнер.
Bootstrap-токен и пароль идут через stdin, не аргументами процесса.
На публичном Nginx `/api/v1/auth/bootstrap...` всегда возвращает 404.

## 4. Подключить Cloudflare

В Cloudflare One открыть Networks / Connectors / Cloudflare Tunnels,
создать tunnel типа cloudflared, например `sklad-production`.
Из предложенной команды установки взять только токен, не запускать вторую
копию connector как службу Ubuntu. В консоли ВМ:

```bash
sudo python3 scripts/server.py set-tunnel
```

Вставить токен в скрытый ввод. Он сохраняется только в закрытый файл.
Для tunnel настроить **два published application routes**:

| Публичный hostname | Service type | URL |
|---|---|---|
| app.example.com | HTTP | web:80 |
| files.example.com | HTTP | web:80 |

Путь оставить пустым. HTTP Host Header не переопределять: Nginx различает
виртуальные хосты, а подпись S3 включает домен файлов. Не указывать `localhost`,
`api:8080` или `minio:9000`. Connector находится в отдельном контейнере.
Внешний HTTPS завершает Cloudflare; участок `cloudflared -> web` — HTTP
в приватной Docker-сети. Прямого публичного HTTP-порта нет.

Не включать Cache Everything для API/файлов и интерактивную Cloudflare Access
перед ними без отдельной интеграции: это мешает Windows-клиенту и S3-запросам.
Для этих двух hostname создать Cache Rule с Bypass cache, чтобы приватные
ответы не кэшировались даже при уже настроенных правилах зоны.

```bash
sudo python3 scripts/server.py publish
sudo python3 scripts/server.py status
```

`publish` попросит ввести домен приложения для подтверждения. После запуска
ожидается Healthy/Connected в Cloudflare. При изменении токена у уже созданного
connector остановить его командой `unpublish`, затем `set-tunnel` и `publish`.
Не показывать токен в скриншотах. Он даёт возможность подключить connector.

Остановить публикацию, не удаляя данные:

```bash
sudo python3 scripts/server.py unpublish
```

После первого `publish` container имеет `restart: unless-stopped` и поднимется
после перезапуска Docker. `unpublish` явно его останавливает.

Проверить с телефона через мобильный интернет:

1. HTTPS-сайт открывается, вход требует смены временного пароля и настройки TOTP.
2. После TOTP сохранить recovery-коды отдельно от ВМ, создать чистую организацию.
3. Загрузка и открытие изображения/PDF работают через домен файлов.
4. Ссылка клиента КП работает, realtime-изменения приходят во второй браузер.
5. Публичный bootstrap и адрес корня домена файлов возвращают 404.
6. После перезапуска ВМ данные сохранены; Docker запускается автоматически.

Корень `https://files.example.com/` НЕ является страницей с файлами: 404 там
ожидаем. Приватные объекты доступны только по подписанным ссылкам.

[Официальная инструкция Cloudflare](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/),
[token-file connector](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/).

## 5. Резервная копия

Один раз создать отдельный ключ, НЕ внутри папки репозитория:

```bash
sudo install -d -m 700 /root/sklad-backup-keys
sudo python3 scripts/server.py backup-key /root/sklad-backup-keys/main.key
```

Сохранить дубликат ключа отдельно от ВМ и архивов. Без него восстановление
невозможно. Сам ключ не включается в резервную копию.

```bash
sudo python3 scripts/server.py backup "backups/sklad-$(date +%Y%m%d-%H%M%S).tar.gpg" --key /root/sklad-backup-keys/main.key
```

На время снимка команда останавливает ранее запущенные Tunnel, web, API, worker,
MinIO и Redis. Делает PostgreSQL custom dump и архив остановленных MinIO/Redis
volumes. Это плановый краткий простой. Затем запускает только ранее работавшие
сервисы, даже если копирование завершилось ошибкой. При аварийном выключении ВМ
или SIGKILL восстановление запуска вручную; такую прерванную копию не использовать.

Внутри AES256/GnuPG-архива: `database.dump`, `volumes.tar.gz`, `server.env`,
`tunnel-token`, `manifest.json` с SHA-256 и коммитом кода. Секреты TOTP/JWT
нужны для восстановления; передавать можно только зашифрованный `.tar.gpg`.
Рабочие временные файлы хранятся в каталоге 0700 и удаляются при штатном завершении.
Нужно свободное место под дамп, сжатые volumes, tar и итоговый зашифрованный архив.

Копию перенести с этого ПК на другой носитель/устройство, а ключ — отдельно.
Хранить несколько поколений. Сейчас команда ручная; расписание и уведомления
об ошибках ещё не настроены. Snapshot VirtualBox не заменяет такую копию.

## 6. Проверить восстановление в пустую среду

Рекомендуется отдельная новая ВМ и тот же коммит приложения. НЕ выполнять
поверх рабочего проекта и НЕ удалять рабочие volumes ради проверки.

В новой рабочей копии без `.env.server`:

```bash
sudo python3 scripts/server.py restore /путь/к/копии.tar.gpg --key /путь/к/main.key
sudo python3 scripts/server.py config
sudo python3 scripts/server.py up
```

`restore` отказывает, если уже существуют .env, каталог секретов или любые
контейнеры/volumes/сети с именем целевого Compose-проекта. Сверяет SHA-256,
формат архива и коммит. Не принимает абсолютные пути, `..`, symlink, устройства
в архиве volumes. Восстанавливает данные, но запускает только PostgreSQL.
После неудачного restore окружение может быть частично создано: автоматического
удаления нет. Разобрать причину, использовать другую пустую тестовую среду.

На той же тестовой ВМ можно указать другое имя и отдельный .env вне репозитория:

```bash
sudo install -d -m 700 /root/sklad-restore-test
sudo python3 scripts/server.py --project sklad-restore-check --env /root/sklad-restore-test/server.env restore /путь/к/копии.tar.gpg --key /путь/к/main.key
sudo python3 scripts/server.py --project sklad-restore-check --env /root/sklad-restore-test/server.env up
```

Во всех последующих командах для этого теста повторять оба флага.
**Не запускать `publish` на тестовой копии с восстановленным production-токеном**:
Cloudflare может направить рабочий трафик на тестовые данные. Для публичного
staging нужны отдельные домены, новый Tunnel и соответствующие настройки.

## 7. Границы и обновления

- Все хранилища находятся на одной ВМ. Её потеря без внешней копии означает потерю данных.
- ПК/ВМ не должны уходить в сон; автозапуск VirtualBox на Windows проверяется отдельно.
- Обновление кода не обновляет существующие public/tenant-схемы автоматически.
  Перед обновлением нужны backup и план миграций; `down -v` не является обновлением.
- Не менять пароли хранилищ простой правкой .env у уже заполненных volumes:
  требуется согласованная ротация в БД/MinIO и приложении.
- Не подключать локальные development volumes к серверному проекту.
- Nginx ограничивает тело запроса 50 MiB; ограничения API/Cloudflare могут быть ниже.
- Доступ root/Docker означает доступ к секретам. Не выдавать его обычным пользователям.
- Логи access Nginx не включают query string с токенами; диагностические error-логи
  всё равно считать чувствительными. API request diagnostics ограничены Warning.
- Образы PostgreSQL/Redis и базовые .NET/Flutter берутся из используемых проектом
  версий; перед очередным выпуском проверять обновления и фиксировать release/digests.

## 8. Модуль и проверки

`scripts/server.py`: строгий разбор env, генератор секретов, Compose-обёртка,
bootstrap через stdin, эксклюзивная блокировка операций, backup/restore.
Зависимости: стандартная библиотека Python, Docker Compose, Git, GnuPG.
CLI предназначен для Linux. Ошибки возвращают ненулевой код; существующие данные
не удаляются и не заменяются. Документированные имена переменных —
`.env.server.example`; ключ TOTP — Base64 32 байта, остальные секреты — hex 32 байта.
`APP_DOMAIN`/`FILES_DOMAIN` — разные ASCII DNS-имена без схемы/порта.

Проверки без Docker:

```bash
python3 -m unittest discover -s tests/server -v
```

Интеграционный тест — ТОЛЬКО на тестовом Docker daemon, не на рабочем сервере:

```bash
sudo python3 tests/server/smoke.py --allow-disposable-projects
```

Он создаёт два случайно именованных проекта, проверяет чистую БД, отсутствие
публичных портов, bootstrap, S3 PUT/GET/CORS, backup/restore, затем удаляет
только свои проекты и их volumes. Требует Docker, Git и GnuPG; место под сборки.
`tests/server/Dockerfile` предоставляет Linux-инструментарий для Docker Desktop,
не используется production-сервисами. Docker socket этому тестовому контейнеру
даёт административный доступ к daemon; не запускать недоверенный тестовый код.

### Результаты проверки 11.10.2026

- 14 unit-тестов прошли на Windows Python 3.12 и в Linux-контейнере Python 3.12.
- `docker compose config --quiet`, сборки API/worker/Flutter Web и запуск
  серверного профиля прошли. Nginx проверен; опубликованных host ports нет.
- Сквозной Linux/Docker-тест прошёл: изначально 0 пользователей, app-роль
  PostgreSQL не superuser, bootstrap закрыт через Nginx независимо от регистра URL,
  внутреннее создание директора, смена пароля, TOTP, Secure/HttpOnly-cookie,
  создание организации и tenant-миграции под ограниченной ролью.
- Подписанные PUT/GET и CORS проверены через Nginx с публичным Host файлов.
- Зашифрованная копия восстановлена в другой пустой Compose-проект;
  организация и объект сохранились, вход с тем же TOTP после восстановления прошёл.
  Tunnel тестом не запускался; после restore до явного up работал только PostgreSQL.
- Проверочный образ cloudflared 2026.10.0 доступен и загружен, но подключение
  к Cloudflare не выполнялось: реальный токен и домены ещё не настроены.
- Временные тестовые контейнеры, сети, volumes и тестовые секреты удалены.
  Рабочий development-проект и оба существующих Compose-файла не изменены.
- Сборка Flutter успешна, но сохраняет предупреждение о шрифте CupertinoIcons
  и запуске Flutter от root внутри существующего build-образа. UI и зависимости
  этой подготовкой не изменялись; полный набор Flutter-тестов не перезапускался.

После этих автоматических проверок владелец подтвердил работу Ubuntu VirtualBox,
внешнего HTTPS/Tunnel, входа, файлов через мобильный интернет и перезапуска ВМ.
Это не подтверждает отдельно WebSocket, аварийное восстановление рабочей ВМ
или автоматический запуск ВМ после перезагрузки физического ПК.
Последующие сборки Windows/Android описаны в едином гайде.
