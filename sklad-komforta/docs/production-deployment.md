# Развёртывание в production

Для **одной ВМ с локальными PostgreSQL, Redis, MinIO и Cloudflare Tunnel**
используется другой профиль: [серверный комплект](iteration-08/server-deployment.md).
Ниже описан вариант с внешними хранилищами и собственным TLS на Nginx.

Production использует отдельный файл `compose.production.yaml` и не изменяет
среду разработки из `compose.yaml`. Единственной публичной точкой входа является
Nginx: он отдаёт Flutter Web и перенаправляет `/api/*` во внутренний контейнер
API, порт которого не публикуется на сервере.

## Необходимая инфраструктура

- сервер Ubuntu с Docker Engine и Docker Compose;
- DNS-запись A/AAAA для `APP_DOMAIN`;
- доверенный TLS-сертификат и закрытый ключ на сервере;
- управляемые PostgreSQL и Redis;
- S3-совместимое хранилище и отдельные учётные данные с минимальными правами.

## Настройка

1. Скопировать `.env.production.example` в `.env.production`, не добавляя новый
   файл в Git.
2. Заменить все значения `replace-me`, указать домен и пути к сертификатам.
3. Разрешить подключения к PostgreSQL, Redis и S3 только с сервера приложения.
4. Не публиковать в интернет API-порт 8080, PostgreSQL, Redis и хранилище.

Адреса PostgreSQL, Redis и S3 задаются переменными окружения. При смене
провайдера меняется конфигурация, а не код приложения. Значение
`S3_FORCE_PATH_STYLE=true` используется для MinIO и подобных хранилищ; для
большинства облачных S3-провайдеров применяется `false`.

## Проверка и запуск

Перед первым запуском проверить итоговую конфигурацию:

```bash
docker compose --env-file .env.production -f compose.production.yaml config
```

Собрать и запустить контейнеры:

```bash
docker compose --env-file .env.production -f compose.production.yaml up -d --build
```

Flutter Web собирается с относительным адресом API `/api/v1`. Браузер и API
работают через один HTTPS-домен, поэтому обычные production-запросы не зависят
от CORS. Нативные приложения получают полный адрес вида
`https://app.example.com/api/v1` через `API_BASE_URL` во время сборки.

## Обновление TLS-сертификата

Сертификаты подключаются в контейнер только для чтения. Их выдачей и продлением
управляет серверный Certbot или другой менеджер сертификатов. После продления
следует перечитать конфигурацию Nginx:

```bash
docker compose --env-file .env.production -f compose.production.yaml exec web nginx -s reload
```

## Граница доверия reverse proxy

Параметр `ReverseProxy__TrustForwardedHeaders=true` включён только в production
Compose. API принимает `X-Forwarded-For` и `X-Forwarded-Proto` ровно от одного
промежуточного узла, поскольку доступен только во внутренних Docker-сетях.
Нельзя публиковать API-порт 8080 при включённом режиме доверия заголовкам.

## Сборки для платформ

Web собирается файлом `src/flutter/Dockerfile.web`. Нативные приложения используют
тот же Dart-код, но получают production-адрес API во время своей сборки:

```powershell
flutter build windows --release --dart-define=API_BASE_URL=https://app.example.com/api/v1 --dart-define=PUBLIC_APP_BASE_URL=https://app.example.com --dart-define=APP_ENVIRONMENT=production
flutter build apk --release --dart-define=API_BASE_URL=https://app.example.com/api/v1 --dart-define=PUBLIC_APP_BASE_URL=https://app.example.com --dart-define=APP_ENVIRONMENT=production
```

Перед распространением необходимо отдельно настроить подпись Android/iOS и
Windows/macOS. Текущая Android release-сборка подписывается отладочным ключом и
не предназначена для публикации в магазине.

## Почему dev-среда не изменилась

Команда `docker compose up` по-прежнему читает только `compose.yaml` и запускает
локальные PostgreSQL, Redis, MinIO и Mailpit. Production-файл применяется только
при явном указании `-f compose.production.yaml`, поэтому подготовленная
конфигурация не влияет на текущую разработку.
