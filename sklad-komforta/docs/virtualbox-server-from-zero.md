# Склад Комфорта: от настройки сервера до Windows EXE и Android APK

Единый практический гайд по пройденному пути. Актуализирован 13.10.2026
по файлам проекта и результатам, подтверждённым владельцем.
Заменяет прежнюю версию этой инструкции, а не создаёт дубликат.

**Если сервер уже работает, не повторяйте создание ВМ, init и bootstrap.**
Для повторной сборки клиентов переходите к разделам 10–13.
Для обслуживания сервера используйте разделы 8–9 и 15.

## Содержание

- [1. Схема и обозначения](#part-1)
- [2. VirtualBox, Ubuntu и SSH](#part-2)
- [3. Диск и время](#part-3)
- [4. Docker и исходники](#part-4)
- [5. Домен и Cloudflare](#part-5)
- [6. Первый запуск сервера](#part-6)
- [7. Публикация через Tunnel](#part-7)
- [8. Проверка и перезапуск](#part-8)
- [9. Резервное копирование](#part-9)
- [10. Компьютер для сборки](#part-10)
- [11. Windows-установщик](#part-11)
- [12. Android APK](#part-12)
- [13. Название, версия, иконки и настройки](#part-13)
- [14. Назначение файлов](#part-14)
- [15. Обновления и диагностика](#part-15)
- [Все команды server.py](#server-commands)
- [Мониторинг ВМ и контейнеров](#monitoring)

<a id="part-1"></a>
## 1. Схема и обозначения

~~~text
Браузер / Windows-клиент / Android-клиент
                     |
                   HTTPS
                     |
                 Cloudflare
                     |
           зашифрованный Tunnel
                     |
Windows-ПК -> VirtualBox -> Ubuntu Server
                              |
                         cloudflared
                              |
                         Nginx (web)
                           /     \
                         API    MinIO (файлы)
                          |
                  PostgreSQL / Redis / worker
~~~

EXE и APK являются клиентами. Они не содержат сервер, базу организации и
загруженные пользователями файлы. Сотрудникам не нужен Docker, но нужны
работающий сервер и интернет.

| Что | Наше значение |
|---|---|
| Пользователь Ubuntu | `sayu` |
| SSH с этого Windows-ПК | `127.0.0.1`, порт `2222` |
| Репозиторий в Ubuntu | `/home/sayu/apps/prog` |
| Проект в Ubuntu | `/home/sayu/apps/prog/sklad-komforta` |
| Проект в Windows | `E:\Program Files\XAMPP\htdocs\sklad-komforta` |
| Домен | `skladkomforta.dpdns.org` |
| Приложение | `https://app.skladkomforta.dpdns.org` |
| Файлы | `https://files.skladkomforta.dpdns.org` |
| Tunnel | `skladkomforta` |
| Flutter SDK | `D:\develop\flutter` |
| Android SDK | `E:\Android\Sdk` |

На другом ПК замените пути, пользователя и домены своими.
`127.0.0.1` означает компьютер, **на котором выполняется команда**.
Это не публичный адрес сервера.

**Ubuntu / Bash** ниже означает консоль ВМ или PuTTY.
**Windows / PowerShell** означает терминал Windows, не PuTTY.
Копируйте команды без приглашений `PS ...>` и `sayu@...$`.

Пути исходников ниже указаны относительно папки `sklad-komforta`,
чтобы инструкция оставалась пригодной при переносе проекта.

<a id="part-2"></a>
## 2. VirtualBox, Ubuntu и SSH

### 2.1. Создать ВМ

1. Установите VirtualBox с [официального сайта](https://www.virtualbox.org/).
2. Скачайте Ubuntu Server amd64 с [сайта Ubuntu](https://ubuntu.com/download/server).
   В нашем развёртывании использована Ubuntu Server 26.04.1.
3. Создайте ВМ: Ubuntu 64-bit, 4 процессора, 8 ГБ RAM, VDI 50 ГБ.
   Это наша начальная конфигурация, а не гарантия достаточности для любого объёма данных.
4. Подключите ISO и установите Ubuntu на **виртуальный диск этой ВМ**.
   Не выбирайте физические диски Windows.
5. Создайте пользователя `sayu` с надёжным паролем.
   Если предлагается OpenSSH Server, включите его.
6. После установки извлеките ISO из виртуального привода и загрузитесь с VDI.

У физического ПК было 32 ГБ RAM. Не отдавайте ВМ всю память.
Следите за свободным местом и внутри Ubuntu, и на диске Windows:
динамический VDI тоже способен заполнить диск хоста.

### 2.2. Настроить SSH

При выключенной ВМ: VirtualBox → Настройки → Сеть → NAT →
Дополнительно → Проброс портов:

| Имя | Протокол | IP хоста | Порт хоста | IP гостя | Порт гостя |
|---|---|---|---|---|---|
| SSH | TCP | 127.0.0.1 | 2222 | пусто | 22 |

IP хоста `127.0.0.1` ограничивает доступ этим ПК.
Для сайта входящие порты на роутере открывать не нужно.

**Ubuntu**, если SSH не установлен:

~~~bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo systemctl status ssh --no-pager
~~~

В PuTTY: Host Name `127.0.0.1`, Port `2222`, SSH.
Перед принятием нового ключа хоста сверьте отпечаток с консолью ВМ:

~~~bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
~~~

Войдите как `sayu`. При вводе пароля Linux символы не отображаются.
Вместо PuTTY можно использовать **PowerShell**:

~~~powershell
ssh -p 2222 sayu@127.0.0.1
~~~

Если включаете UFW, сначала разрешите SSH, затем включайте firewall.
Оставьте консоль VirtualBox доступной на случай ошибки:

~~~bash
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status
~~~

Docker-порты нашего серверного профиля наружу не публикуются.
Добавление `ports:` меняет модель безопасности: одного UFW тогда недостаточно.

Для цветного приглашения откройте `nano ~/.bashrc`, найдите существующее
`#force_color_prompt=yes`, уберите `#` и выполните `source ~/.bashrc`.
`PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ ' `
Не добавляйте дубликат настройки.

<a id="part-3"></a>
## 3. Диск и время

### 3.1. Размер корневого раздела

**Ubuntu:**

~~~bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
df -h /
sudo pvs
sudo vgs
sudo lvs
~~~

У нас VDI был 50 ГБ, а корневому LVM-тому сначала выделилось около 24 ГБ.
В группе томов оставалось свободное место. После проверки имени тома применили:

~~~bash
sudo lvextend --resizefs -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
df -h /
~~~

**Не запускайте вслепую:** команда подходит только для этого LVM-пути
и при наличии свободных экстентов в группе. Она не увеличивает сам VDI.
Для рабочего сервера сначала нужна резервная копия.

### 3.2. Синхронизация времени и TOTP

~~~bash
date
timedatectl status
chronyc tracking
chronyc sources -v
~~~

У нас работает **chrony**. Отсутствие `systemd-timesyncd.service` при работающем
chrony нормально: не нужно одновременно включать два NTP-клиента.
На новой ВМ сначала выясните, какой NTP-клиент уже используется.

В нашем случае `System time` показывало отставание примерно **1678 секунд**.
Из-за этого TOTP-коды считались неверными. После выбора доступного достоверного
источника времени (`^*` в sources) применили поправку сразу:

~~~bash
sudo chronyc makestep
chronyc tracking
timedatectl status
~~~

Ожидаем небольшое отклонение, `Leap status: Normal` и, после синхронизации,
`System clock synchronized: yes`. Одного `NTP service: active` недостаточно.
После скачка времени войдите заново со свежим TOTP-кодом. На телефоне также
включите автоматические дату и время. Не отключайте 2FA ради неверных часов.

**UTC можно оставить.** Часовой пояс меняет отображение, не абсолютное время.
Например, 11 октября 2026 года 14:21 UTC соответствует 17:21 в Кишинёве.
Местное отображение, если удобнее:

~~~bash
sudo timedatectl set-timezone Europe/Chisinau
~~~

Для исправного TOTP это не требуется.

<a id="part-4"></a>
## 4. Docker и исходники

### 4.1. Docker на чистой Ubuntu

Если Docker установлен и hello-world работает, повторная установка не нужна.
Не смешивайте пакеты `docker.io` и Docker CE без проверки существующей установки.

**Ubuntu, официальный репозиторий:**

~~~bash
sudo apt update
sudo apt install -y ca-certificates curl git python3 gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo docker compose version
python3 --version
~~~

Успех: `Hello from Docker!` и версия Compose. Для server.py нужен Python 3.11+.
Порядок установки сверяется с [документацией Docker](https://docs.docker.com/engine/install/ubuntu/).

**Ключ репозитория Docker** в docker.asc является публичным ключом проверки
пакетов APT, не паролем Docker, не SSH-ключом и не ключом вашей БД.
Docker-команды здесь выполняются через sudo; доступ к Docker практически
равнозначен административному доступу, сотрудникам его выдавать не нужно.

### 4.2. Получить код

Нужные изменения сначала проверяют, коммитят и отправляют в репозиторий
с компьютера разработчика. Коммит локален до push. Сервер не получает
незакоммиченные изменения автоматически.

На **новой ВМ**, если `~/apps/prog` ещё нет:

~~~bash
mkdir -p ~/apps
cd ~/apps
git clone https://github.com/anasta958-blip/prog.git
cd ~/apps/prog/sklad-komforta
git log -1 --oneline
ls -l compose.server.yaml .env.server.example scripts/server.py
~~~

Для закрытого репозитория настройте доступ GitHub отдельно, не вставляйте
токен в URL команды. Не переносите development-базу, дампы старого PHP
и локальные Docker volumes.

На существующем сервере используйте раздел 15, не клонируйте поверх проекта.
Серверная подготовка уже отправлялась в GitHub; новые локальные файлы сборки
Windows/Android на дату гайда ещё нужно включить в проверенный коммит.
Иначе новый clone их не получит.

<a id="part-5"></a>
## 5. Домен и Cloudflare

1. Зарегистрируйте домен. В нашем пути использован DigitalPlat,
   итоговое имя `skladkomforta.dpdns.org`.
2. В Cloudflare: Domains → Add domain → **Connect a domain**.
   Это подключение DNS, не Transfer a domain.
3. Введите зарегистрированное имя, выберите бесплатный план.
   Пустой список DNS нормален для нового неиспользовавшегося домена.
4. Замените NS у регистратора на два nameserver, выданные Cloudflare.
   У нас это `leah.ns.cloudflare.com` и `tate.ns.cloudflare.com`;
   для другой зоны используйте её собственную пару.
5. Если раньше был DNSSEC, следуйте инструкции перехода Cloudflare:
   нельзя оставлять старую DS-запись для новых NS.
   Существующие почтовые и другие нужные DNS-записи сохраните.
6. Дождитесь статуса зоны **Active**.

Первоначальный `skladkomforta.qd.je` Cloudflare не принял как корневой домен,
поэтому мы перешли на `skladkomforta.dpdns.org`.
Не пытайтесь подключать чужой `qd.je` вместо собственного имени.

Для Tunnel не нужна A-запись на внешний IP домашнего ПК.
Имена app и files будут связаны с Tunnel через маршруты.

### Зачем нужны app и files

Это **поддомены**, а не папки и не имена установщиков:

| Адрес | Что обслуживает |
|---|---|
| `skladkomforta.dpdns.org` | Базовое зарегистрированное имя; в нашей схеме сайт на самом корне не настроен |
| `app.skladkomforta.dpdns.org` | Интерфейс браузера и API для всех клиентов: вход, каталог, организации и т. д. |
| `files.skladkomforta.dpdns.org` | Обмен объектами MinIO по временным подписанным ссылкам |

`app` сокращено от application, `files` означает файлы.
Покупать два новых домена или поднимать две ВМ для этого не требуется:
оба имени идут через один Tunnel в один Nginx `web:80`.
Nginx смотрит на имя хоста запроса и выбирает обработчик:
для app отдаёт интерфейс или передаёт запрос API, для files передаёт
разрешённые обращения к bucket в MinIO.

Так у приложения и файлов отдельные адреса и правила доступа; пути S3
не смешиваются с маршрутами интерфейса/API. Само разделение имён не является
защитой файлов: защиту обеспечивают закрытый bucket, проверка прав в API
и ограниченные по времени подписи.

Слова app и files не магические: можно выбрать другие имена, согласованно
настроив сервер и Cloudflare. Но **текущий server.py требует два разных имени**.
Просто удалить files или направить оба имени на API нельзя.
Параметр сборки `--app-url` принимает именно адрес приложения, не адрес файлов.

<a id="part-6"></a>
## 6. Первый запуск сервера

Команды: **Ubuntu**, из `~/apps/prog/sklad-komforta`.

### 6.1. Создать настройки и запустить

~~~bash
cd ~/apps/prog/sklad-komforta
sudo python3 scripts/server.py init --app-domain app.skladkomforta.dpdns.org --files-domain files.skladkomforta.dpdns.org
sudo python3 scripts/server.py config
sudo python3 scripts/server.py up
sudo python3 scripts/server.py status
~~~

init создаёт случайные секреты в `.env.server` и закрытый каталог
`.env.server.secrets`. Домены здесь **без https://**.
Существующие настройки не перезаписываются. Не выполняйте `source .env.server`.
config при успехе может ничего не вывести.

up собирает API, worker, Web и запускает хранилища.
Первая сборка долгая из-за скачивания образов и зависимостей.

| Сервис | Нормальное состояние |
|---|---|
| postgres, redis, minio, web | Up / healthy |
| api, worker | Up / running |
| minio-init | Exited (0), одноразовая настройка завершена |
| cloudflared | Пока не запущен |

Профиль compose.server.yaml не публикует порты БД, Redis, MinIO или API.
Данные остаются в volumes при пересоздании контейнеров.
**Не выполняйте docker compose down -v: это удаление volumes, не обновление.**

### 6.2. Наш обход ошибки загрузки MinIO

Docker Hub отказал в скачивании minio/mc. Проверенные образы уже были
в Docker Desktop на Windows: мы перенесли **образы**, не базу.
Этот способ возможен только при наличии точных образов на доверенном ПК.

**Windows / PowerShell**, Docker Desktop запущен:

~~~powershell
Set-Location "E:\Program Files\XAMPP\htdocs\sklad-komforta"
New-Item -ItemType Directory -Force backups | Out-Null
docker image inspect minio/minio:RELEASE.2025-09-07T16-13-09Z minio/mc:RELEASE.2025-08-13T08-35-41Z
docker image save --output "backups\minio-server-images.tar" minio/minio:RELEASE.2025-09-07T16-13-09Z minio/mc:RELEASE.2025-08-13T08-35-41Z
Get-FileHash "backups\minio-server-images.tar" -Algorithm SHA256
scp -P 2222 "backups\minio-server-images.tar" sayu@127.0.0.1:/home/sayu/
~~~

**Ubuntu:**

~~~bash
sha256sum /home/sayu/minio-server-images.tar
~~~

Сверьте обе суммы. Только после совпадения:

~~~bash
sudo docker image load -i /home/sayu/minio-server-images.tar
cd ~/apps/prog/sklad-komforta
sudo python3 scripts/server.py up
sudo python3 scripts/server.py status
~~~

Не заменяйте теги случайным latest и не используйте неизвестные зеркала.
Нужна пара image save / image load, не export / import.
Хеш нового экспорта может отличаться от старого: сравниваются отправленный
и полученный файлы одной операции.

### 6.3. Создать первого директора

~~~bash
sudo python3 scripts/server.py bootstrap
~~~

Введите логин, имя, лимит сотрудников и временный пароль по запросам.
Пароль: минимум 12 символов, заглавная и строчная буквы, цифра, спецсимвол;
ввод скрыт. Сохраните безопасно, не отправляйте в чат.

Создаётся аккаунт директора, не заполненная организация.
Повторный запуск для того же логина не сбрасывает пароль.
Публичный bootstrap закрыт Nginx, вызывать его через интернет не нужно.

<a id="server-commands"></a>
### 6.4. Справочник всех команд server.py

Все административные операции выполняются в **Ubuntu**, не в PowerShell:

~~~bash
cd ~/apps/prog/sklad-komforta
sudo python3 scripts/server.py --help
sudo python3 scripts/server.py backup --help
~~~

`--help` / `-h` показывает справку без выполнения операции.
Можно запросить помощь после любой команды, например `init --help`.
Ниже перечислены **все 11 подкоманд текущей версии**. Это справочник,
а не список для последовательного запуска.

| Команда | Что делает и когда нужна | Что учитывать |
|---|---|---|
| `init --app-domain ИМЯ --files-domain ИМЯ` | Создаёт .env.server со случайными секретами и каталог секретов; один раз на новой установке | Домены разные, в нижнем регистре, без схемы/порта. Существующий env не перезаписывает; контейнеры не запускает |
| `config` | Проверяет переменные, права env и Compose через config --quiet | Не выводит настройки и секреты; не проверяет доступность сайта или работоспособность БД |
| `up` | Собирает образы и запускает внутренние сервисы: up -d --build --wait --wait-timeout 300 | Может пересоздать контейнеры и вызвать простой; volumes сохраняются. Не включает public-профиль для первого запуска Tunnel; не является командой миграции БД |
| `status` | Показывает все контейнеры проекта, включая остановленные и public-профиль | Не запускает контейнеры. Up/Exited/healthy описывают состояние, не CPU/RAM |
| `set-tunnel` | Скрыто запрашивает и сохраняет/заменяет токен Cloudflare | Сам connector не запускает и не перезапускает. Для смены рабочего токена: unpublish → set-tunnel → publish |
| `publish` | После проверки непустого токена и подтверждения домена запускает cloudflared с public-профилем | Compose может запустить зависимости; маршруты в панели Cloudflare команда не создаёт. Не применять к тестовой копии с production-токеном |
| `unpublish` | Останавливает только cloudflared, прекращая внешний доступ через этот connector | Внутренние сервисы и данные остаются. Возврат публикации через publish |
| `bootstrap` | Интерактивно создаёт аккаунт директора через внутренний API | Нужен работающий API. Спрашивает логин, имя, лимит и пароль с повтором. Не создаёт организацию и не сбрасывает пароль существующего аккаунта |
| `backup-key ПУТЬ` | Создаёт новый закрытый файл ключа резервирования | Родительский каталог должен существовать. Существующий файл не заменяет; ключ сохранить вне ВМ |
| `backup АРХИВ --key КЛЮЧ` | Создаёт зашифрованную копию БД, файлов, Redis и настроек | PostgreSQL должен работать. Другие ранее работавшие сервисы временно останавливаются и возобновляются; существующий архив не перезаписывается |
| `restore АРХИВ --key КЛЮЧ` | Восстанавливает архив в пустой проект, проверяя состав, хеши и коммит | Целевые env/секреты/ресурсы должны отсутствовать. Запускает только PostgreSQL, затем отдельно config/up и проверка |

Как поменять адреса сервера
`cd ~/apps/prog/sklad-komforta`
`sudo nano .env.server`
Измените существующие APP_DOMAIN и FILES_DOMAIN, не трогая пароли и ключи. Затем:
`sudo python3 scripts/server.py config`
`sudo python3 scripts/server.py up`
`sudo python3 scripts/server.py status`

Примеры init/bootstrap/Tunnel уже приведены в разделах 6–7,
backup-key/backup/restore с безопасными путями — в разделе 9.

**Общие параметры ставятся до подкоманды:**

~~~text
sudo python3 scripts/server.py [--project ИМЯ] [--env ПУТЬ] КОМАНДА [параметры команды]
~~~

| Параметр | По умолчанию / действие |
|---|---|
| `--project` | `sklad-komforta-server`; имя Compose-проекта, разделяющее контейнеры, сети и volumes |
| `--env` | `.env.server` в корне проекта; иной путь выбирает другой набор настроек |
| `--app-domain`, `--files-domain` | Обязательны только у init |
| `--key` | Обязателен у backup и restore; путь к файлу, не сам секрет |

Для нестандартного имени проекта допускаются префиксы `sklad-server` или
`sklad-restore`, затем строчные латинские буквы, цифры и дефисы.
Каталог секретов создаётся рядом с выбранным env, с суффиксом `.secrets`.
Относительный `--env` разрешается от текущего каталога терминала.
Для отдельной среды выбирайте **и другое имя проекта, и другой env**.

Пример просмотра уже созданной тестовой среды, не рабочего сервера:

~~~bash
sudo python3 scripts/server.py --project sklad-restore-check --env /root/sklad-restore-test/server.env status
~~~

Перед большинством операций выполняется проверка config; исключения:
init, backup-key, restore. Есть блокировка параллельных операций
`.server-operation.lock`: пока идёт backup/up, второй вызов, включая status,
может сообщить «Другая серверная операция ещё выполняется».
Не удаляйте lock-файл для обхода: используйте read-only команды Docker
из [раздела мониторинга](#monitoring).

У server.py **нет** подкоманд logs, stats, restart, stop, down, update,
migrate и delete. Их не следует дописывать по аналогии с Docker:
логи и нагрузка смотрятся отдельными командами ниже.

<a id="part-7"></a>
## 7. Публикация через Tunnel

1. В Cloudflare One найдите Cloudflare Tunnels / Connectors.
   Создайте tunnel типа cloudflared; наше имя `skladkomforta`.
2. Выберите **Docker**, а не Windows. Из команды возьмите только токен после --token.
3. Не ставьте вторую службу cloudflared на Windows: connector предусмотрен Compose.

**Ubuntu:**

~~~bash
sudo python3 scripts/server.py set-tunnel
sudo python3 scripts/server.py publish
~~~

В set-tunnel вставьте токен в скрытый ввод.
publish попросит подтвердить `app.skladkomforta.dpdns.org`.
Ожидается **Tunnel connected successfully**.

Добавьте две Published application routes:

| Subdomain | Domain | Path | Service URL |
|---|---|---|---|
| app | skladkomforta.dpdns.org | пусто | http://web:80 |
| files | skladkomforta.dpdns.org | пусто | http://web:80 |

Если поля раздельные: Type **HTTP**, URL **web:80**.
HTTP Host Header не переопределяйте: домен нужен Nginx и подписи S3.
Не указывайте localhost, api:8080 или minio:9000.

**Почему HTTP?** Пользователь подключается по HTTPS к Cloudflare, дальше идёт
зашифрованный Tunnel. Только участок cloudflared → web внутри приватной
Docker-сети использует HTTP. Открытого публичного HTTP-порта нет.

web является именем Nginx-сервиса, не ограничением «только браузер».
Через него работают API Windows/Android и файлы.

Для обоих hostname рекомендуется Cache Rule **Bypass cache**.
Не включайте Cache Everything и интерактивный вход Cloudflare Access перед
API/файлами без отдельной интеграции: это мешает клиентам и подписанным ссылкам.
Наличие Bypass-правила у владельца отдельно не проверялось.

Остановить внешний доступ без удаления данных:

~~~bash
sudo python3 scripts/server.py unpublish
~~~

При замене токена существующего connector: unpublish → set-tunnel → publish.
Не помещайте токен в Git, скриншоты и открытые аргументы команд.
Справка: [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/).

<a id="part-8"></a>
## 8. Проверка и перезапуск

1. Откройте [приложение](https://app.skladkomforta.dpdns.org).
2. Войдите директором, смените временный пароль.
3. Настройте TOTP, сохраните recovery-коды отдельно от ВМ.
4. Создайте организацию в интерфейсе. Тестовую базу из разработки не импортируйте.
5. Проверьте каталог, загрузку и открытие изображения/PDF.
6. Отключите Wi-Fi телефона и повторите через мобильный интернет.
7. Дополнительно проверьте ссылку КП и обновления данных во втором клиенте.

Корень `https://files.skladkomforta.dpdns.org/` не файловый менеджер:
404 допустим. Приватные объекты выдаются по подписанным ссылкам.

В запланированное окно проверьте перезапуск Ubuntu:

~~~bash
sudo reboot
~~~

После загрузки снова подключитесь по SSH:

~~~bash
cd ~/apps/prog/sklad-komforta
sudo python3 scripts/server.py status
timedatectl status
~~~

У нас сервисы поднялись, часы синхронизировались, сайт открылся.
Это проверка **ВМ**, не автозапуска ВМ после включения Windows.
Автозапуск VirtualBox пока отложен. Сон или выключение физического ПК
останавливает сервер независимо от работоспособности Cloudflare.

<a id="part-9"></a>
## 9. Резервное копирование

### 9.1. Ключ создать один раз

**Ubuntu:**

~~~bash
sudo install -d -m 700 /root/sklad-backup-keys
sudo python3 scripts/server.py backup-key /root/sklad-backup-keys/main.key
~~~

Если ключ уже есть, используйте его. Новый ключ не расшифрует старые архивы.

### 9.2. Создать архив

Из папки проекта:

~~~bash
sudo python3 scripts/server.py backup "backups/sklad-$(date +%Y%m%d-%H%M%S).tar.gpg" --key /root/sklad-backup-keys/main.key
sudo python3 scripts/server.py status
sudo ls -lah backups
~~~

Команда временно останавливает ранее работавшие Tunnel, web, API, worker,
MinIO и Redis. Предупредите сотрудников о коротком простое.
Сохраняются дамп PostgreSQL, volumes файлов/Redis, настройки и секреты
в GnuPG-архив; затем запускаются ранее работавшие сервисы.
При аварийном выключении ВМ запуск может потребоваться восстановить вручную.

Ключ расшифровки **не включён** в архив. Без ключа восстановление невозможно.
Внутри архива есть серверные секреты: расшифрованное содержимое не публиковать.

Почему `sudo ls backups/*.tar.gpg` не находило файл:
звёздочку раскрывает оболочка до sudo, а каталог доступен root.
Используйте `sudo ls -lah backups`, не меняйте права всего каталога.

### 9.3. Перенести и проверить архив

Историческое имя первой копии: `sklad-20261011-143400.tar.gpg`.
**Замените его именем свежего архива из ls.**

**Ubuntu:**

~~~bash
ARCHIVE=sklad-20261011-143400.tar.gpg
sudo install -o sayu -g sayu -m 600 "/home/sayu/apps/prog/sklad-komforta/backups/$ARCHIVE" "/home/sayu/$ARCHIVE"
sha256sum "/home/sayu/$ARCHIVE"
~~~

**PowerShell:**

~~~powershell
$archive = "sklad-20261011-143400.tar.gpg"
scp -P 2222 "sayu@127.0.0.1:/home/sayu/$archive" "$env:USERPROFILE\Downloads\"
Get-FileHash "$env:USERPROFILE\Downloads\$archive" -Algorithm SHA256
~~~

Суммы должны совпасть независимо от регистра букв.
Это проверка переноса, **не полноценная проверка восстановления**.

Скопируйте архив **за пределы физического ПК**, на другой носитель/устройство.
Downloads не защитит от поломки диска, на котором лежит и ВМ.
Храните несколько поколений.

### 9.4. Отдельно сохранить ключ

**Ubuntu**, временный файл для SSH-пользователя:

~~~bash
sudo install -o sayu -g sayu -m 600 /root/sklad-backup-keys/main.key /home/sayu/sklad-backup-main.key
sudo sha256sum /root/sklad-backup-keys/main.key
~~~

**PowerShell:** замените F: реальной буквой защищённого внешнего носителя:

~~~powershell
scp -P 2222 sayu@127.0.0.1:/home/sayu/sklad-backup-main.key "F:\sklad-backup-main.key"
Get-FileHash "F:\sklad-backup-main.key" -Algorithm SHA256
~~~

После проверки внешней копии удалите **только временный файл** Ubuntu:

~~~bash
rm -- /home/sayu/sklad-backup-main.key
~~~

Оригинал /root/sklad-backup-keys/main.key оставить.
Ключ храните отдельно от архивов. Его содержимое не присылайте.
В нашем пути владелец подтвердил совпадение сумм архива и ключа.

### 9.5. Восстановление: только отдельная пустая среда

Предпочтительна новая тестовая ВМ с тем же коммитом кода, Docker и GnuPG.
Не восстанавливайте поверх рабочей организации и не удаляйте её volumes.

Вариант отдельного Compose-проекта и env на тестовой среде
(замените пути к архиву/ключу существующими):

~~~bash
sudo install -d -m 700 /root/sklad-restore-test
sudo python3 scripts/server.py --project sklad-restore-check --env /root/sklad-restore-test/server.env restore /путь/к/копии.tar.gpg --key /путь/к/main.key
sudo python3 scripts/server.py --project sklad-restore-check --env /root/sklad-restore-test/server.env config
sudo python3 scripts/server.py --project sklad-restore-check --env /root/sklad-restore-test/server.env up
sudo python3 scripts/server.py --project sklad-restore-check --env /root/sklad-restore-test/server.env status
~~~

Для всех команд теста повторяйте --project и --env.
Restore отказывает при существующих настройках/ресурсах, проверяет архив,
хеши и коммит; после восстановления запускает только PostgreSQL.
Полный запуск выполняется отдельно через up.

**Не выполняйте publish с восстановленным production-токеном!**
Cloudflare может направить пользователей на тестовую копию.
Для проверки интерфейса нужны отдельные тестовые домены/Tunnel и настройки.

Интеграционный backup/restore-тест проекта ранее прошёл.
Аварийное восстановление вашей рабочей ВМ остаётся отдельной проверкой.
Подробности: [серверное руководство](iteration-08/server-deployment.md).

<a id="part-10"></a>
## 10. Компьютер для сборки

Windows и Android собираются **на Windows**, не на серверной Ubuntu.
Инструменты разработчика могут требовать администратора при установке;
готовый Windows-клиент устанавливается обычным пользователем.

| Инструмент | Назначение |
|---|---|
| Git | Исходники и коммит в release.json |
| Python 3.11+ | Наши сценарии; сторонние pip-пакеты не нужны |
| Flutter SDK | Общий клиент; проверено с Flutter 3.38.9 / Dart 3.10.8 |
| Visual Studio 2022 + Desktop development with C++ + Windows SDK | Windows-компилятор, CMake и x64 CRT; VS Code её не заменяет |
| NSIS 3 | Windows-мастер установки; использован 3.12 |
| Android Studio / JDK / Android SDK | Android-компиляция, Gradle и подпись |

Официальные источники:
[Python](https://www.python.org/downloads/windows/),
[Flutter](https://docs.flutter.dev/install),
[Visual Studio](https://visualstudio.microsoft.com/downloads/),
[NSIS](https://nsis.sourceforge.io/Download),
[Android Studio](https://developer.android.com/studio).
Условия лицензий и права распространения зависимостей проверяет владелец выпуска.
Не обновляйте все инструменты и зависимости одновременно без тестов.

**PowerShell:**

~~~powershell
Set-Location "E:\Program Files\XAMPP\htdocs\sklad-komforta"
python --version
Get-Command python
git --version
& "D:\develop\flutter\bin\flutter.bat" --version
& "D:\develop\flutter\bin\flutter.bat" doctor -v
~~~

Для Windows исправьте ошибки Visual Studio, для Android ошибки Android toolchain.
В Android SDK Manager нужны платформа текущего Gradle (`compileSdk = 37`),
Build-Tools, Platform-Tools и Command-line Tools.
В нашем выпуске потребовался NDK **27.0.12077973**, использован JDK 21 из
`C:\Program Files\Android\Android Studio\jbr`.
SDK/NDK требуют свободного места. Лицензии прочитайте и примите, если согласны:

~~~powershell
& "D:\develop\flutter\bin\flutter.bat" doctor --android-licenses
~~~

Восстановите зависимости:

~~~powershell
Push-Location src/flutter
& "D:\develop\flutter\bin\flutter.bat" pub get
Pop-Location
~~~

### Почему python и $python не одно и то же

`python` — имя команды из PATH. `$python` — переменная PowerShell,
которую сначала нужно заполнить. Из корня проекта достаточно:

~~~powershell
python scripts/build_windows_installer.py --app-url https://app.skladkomforta.dpdns.org --flutter "D:\develop\flutter\bin\flutter.bat"
~~~

Если используете переменные, задайте их в **текущем окне**:

~~~powershell
$python = (Get-Command python -CommandType Application).Source
$flutter = "D:\develop\flutter\bin\flutter.bat"
& $python scripts/build_windows_installer.py --app-url https://app.skladkomforta.dpdns.org --flutter $flutter
~~~

`&` запускает команду по пути/значению переменной. Пустая переменная вызывает
«недопустимый объект». `puthon` — опечатка, нужно `python`.
URL вставляйте обычным текстом, не конструкцией `[адрес](адрес)`.
Если терминал уже в scripts, путь будет `.\build_windows_installer.py`.
В этом гайде сборки всегда запускаются из **корня проекта**.

<a id="part-11"></a>
## 11. Windows-установщик

### 11.1. NSIS и сборка

Используется **NSIS, не Inno Setup**. Промежуточные пакеты Inno не распространять.
Установите NSIS или распакуйте официальный ZIP так, чтобы существовал
`build/tools/nsis-3.12/makensis.exe`: этот путь находится автоматически.
Для другого пути есть параметр `--makensis "полный путь к makensis.exe"`.

**PowerShell, корень проекта:**

~~~powershell
python scripts/build_windows_installer.py --app-url https://app.skladkomforta.dpdns.org --flutter "D:\develop\flutter\bin\flutter.bat"
~~~

Что делает сценарий:

1. Проверяет Windows x64, HTTPS-домен, версию pubspec, NSIS и x64 CRT.
2. Вызывает Flutter build windows --release с production-настройками.
3. Копирует весь bundle: EXE, Flutter DLL, плагины, data.
4. Добавляет распространяемые x64 CRT DLL из Visual Studio рядом с программой,
   чтобы не устанавливать системный Redistributable с правами администратора.
5. Проверяет комплектность и отсутствие запрещённых файлов секретов.
6. Создаёт точные списки установки/удаления и вызывает NSIS.
7. Записывает SHA-256 и паспорт выпуска.

Результат в новой папке, точный путь выводится после «Готово»:

~~~text
build/windows-installer/1.0.0.1-<суффикс>/
  SkladKomforta-1.0.0.1-windows-x64-setup.exe
  SkladKomforta-1.0.0.1-windows-x64-setup.exe.sha256
  release.json
  bundle/
  install-files.nsh
  uninstall-files.nsh
~~~

| Файл | Назначение |
|---|---|
| setup.exe | Самодостаточный установщик для сотрудника |
| .sha256 | Контроль целостности переданного EXE |
| release.json | Версия, домен, коммит, dirty, время, CRT, хеш; не настройки запуска |
| bundle | Полный набор клиентских файлов до упаковки |
| install-files.nsh / uninstall-files.nsh | Сгенерированные списки NSIS; вручную не редактировать |

Каждая сборка создаёт новую папку. Это результаты разных запусков,
не четыре разных приложения. Старые папки сами не удаляются.

`--prepare-only` создаёт bundle без установщика.
`--crt-dir` задаёт redistributable x64 Microsoft.VC*.CRT.
Не копируйте случайные DLL из System32.
Локальный CRT обновляется новым выпуском клиента, не Windows Update.

### 11.2. Установка и выбор папки

1. Закройте клиент, запустите свежий setup.exe обычным пользователем.
2. Выберите доступный каталог; по умолчанию
   `%LOCALAPPDATA%\Programs\SkladKomforta`.
3. При необходимости включите ярлык рабочего стола.
4. Проверьте вход/TOTP, изображение/PDF, ссылки, перезапуск.

Установщик использует `RequestExecutionLevel user`, HKCU и пользовательские
ярлыки. Выбор C:\Program Files не даёт прав администратора: запись туда может
быть запрещена. Рекомендуется папка внутри профиля.

Выбор папки включает строка `!insertmacro MUI_PAGE_DIRECTORY` в
`deploy/windows/installer.nsi`. Она уже есть в текущем файле.
Изменение NSIS требует пересборки: старый EXE не меняется.

При обновлении **проверьте прежний каталог**: смена пути не переносит старую
установку. В текущем сценарии есть InstallDirRegKey, однако SetRegView 64
не распространяется на эту директиву; автоматическое восстановление
нестандартного пути нельзя считать гарантированным без проверки.
Для доработки нужен согласованный ReadRegStr после выбора 64-битного
представления в .onInit; этот гайд код установщика не меняет.
См. [ограничение NSIS SetRegView](https://nsis.sourceforge.io/Reference/SetRegView).

Удаление программы не удаляет серверную БД и не очищает secure storage.
На общем ПК перед удалением выйдите из аккаунта; потерянному устройству
отзовите сессию.

EXE пока **не подписан Authenticode**: возможен SmartScreen.
Не отключайте защиту. Доверенный канал распространения важен;
SHA-256 не заменяет доверенную подпись издателя.

<a id="part-12"></a>
## 12. Android APK

### 12.1. Подпись и ключ

APK уже установочный пакет Android, отдельный setup.exe не нужен.
Для обновления установленного APK нужны прежние applicationId и ключ подписи,
а также повышенный номер сборки. Release-ключ отличается от debug-ключа.
Это не HTTPS-сертификат, не подпись Windows и не публикация в Google Play.

**На нашем ПК ключ уже создан. Для обновления его не пересоздают.**
Только для первого выпуска нового приложения:

~~~powershell
python scripts/build_android_apk.py init-signing
~~~

По умолчанию:

~~~text
C:\Users\Sau0rin\.sklad-komforta\android-signing/
  release.p12
  password.txt
~~~

На другом пользователе Windows меняется начало пути.
release.p12 содержит закрытый ключ/сертификат, password.txt — пароль.
Сценарий ограничивает права, не перезаписывает папку и не допускает ключ в Git.

**Сохраните всю папку на защищённом внешнем носителе.**
APK не заменяет копию ключа. Без старого ключа обычное обновление прямого APK
невозможно; утечка ключа с паролем позволяет подписывать чужие пакеты вашим ключом.
Содержимое не присылайте. Публичный отпечаток сертификата не является секретом.

На новом ПК восстановите прежнюю папку, не делайте новый init-signing.
Для другого места используйте `--signing-dir "путь вне репозитория"`.
Подтверждения внешней копии Android-ключа в нашем пути пока нет.

### 12.2. Сборка

**PowerShell, корень проекта:**

~~~powershell
python scripts/build_android_apk.py build --app-url https://app.skladkomforta.dpdns.org --flutter "D:\develop\flutter\bin\flutter.bat" --android-sdk "E:\Android\Sdk"
~~~

При необходимости добавьте
`--java-home "C:\Program Files\Android\Android Studio\jbr"`.

Сценарий:

1. Проверяет домен, версию, ключ, SDK и инструменты.
2. Передаёт каталог подписи процессу сборки через SKLAD_ANDROID_SIGNING_DIR.
3. Вызывает Flutter build apk --release с production API и публичным URL.
4. Gradle подписывает APK release-ключом, без подмены debug-подписью.
5. apksigner проверяет подпись, сертификат сверяется с нашим ключом.
6. aapt проверяет package ID, INTERNET и отсутствие debuggable.
7. Сохраняет APK, хеш и сведения о выпуске.

~~~text
build/android-apk/1.0.0+1-<суффикс>/
  SkladKomforta-1.0.0+1-android.apk
  SkladKomforta-1.0.0+1-android.apk.sha256
  release.json
  apk-verification.txt
~~~

Ключ/пароль туда не копируются. apk-verification.txt содержит публичные
сведения о подписи, SDK и разрешениях.
Сценарий импортирует проверку URL/версии из Windows-сценария,
но NSIS и Visual Studio для Android не нужны.

Первая сборка может долго скачивать Gradle/NDK.
У нас кэш Kotlin конфликтовал из-за дисков C: и E:; сценарий уже отключает
incremental Kotlin только для release-процесса.
Не запускайте две сборки одновременно в одном рабочем дереве.

### 12.3. Размер и установка

Первый пакет около 72 МБ: универсальный release для arm64-v8a, armeabi-v7a,
x86_64. В нём Flutter, ресурсы и нативные библиотеки, включая PDF.
Это не размер серверной базы и не debug-сборка.

Уменьшение возможно отдельными APK по архитектурам или только ARM64.
Текущий Python-сценарий **не принимает --split-per-abi**:
для перехода нужны изменения упаковки/путей результатов и проверки устройств.
См. [Flutter Android release](https://docs.flutter.dev/deployment/android).

Проверенный manifest: minSdk 24 (Android 7.0+), targetSdk 36.
Это требования пакета, не проверка всех моделей телефонов.

Передайте сотруднику APK через доверенный канал.
Если Android попросит, разрешите установку из конкретного браузера/файлового
менеджера, затем разрешение можно отозвать. Play Protect не отключайте.
Проверьте вход/TOTP, каталог, изображение/PDF, ссылки, перезапуск,
отдельно обновление поверх предыдущего APK.

Debug-приложение с тем же package ID имеет другую подпись и release поверх
не обновится. Не удаляйте его без учёта потери локального состояния.
Данные на сервере от удаления клиента не исчезают.
Автообновление и Google Play здесь не настроены.

<a id="part-13"></a>
## 13. Название, версия, иконки и настройки

### 13.1. Версия

Основное место: [pubspec.yaml](../src/flutter/pubspec.yaml).

~~~yaml
version: 1.0.0+1
~~~

Например, следующий выпуск:

~~~yaml
version: 1.0.1+2
~~~

| Часть | Значение |
|---|---|
| 1.0.1 | Пользовательская версия |
| +2 | Номер сборки; повышать для каждого распространяемого Android-обновления |
| Windows | Преобразуется в 1.0.1.2 |
| Android | versionName 1.0.1, versionCode 2 |

Текущие сценарии принимают части 0..65535. Не сбрасывайте build number после
смены основной версии. Сгенерированные FLUTTER_VERSION вручную не редактируют.

### 13.2. Название

| Где видно | Где менять |
|---|---|
| Локализованный заголовок Flutter | `src/flutter/lib/l10n/app_ru.arb` и `app_en.arb`, appTitle |
| Экран входа | `src/flutter/lib/features/auth/auth_flow_page.dart` |
| Рабочее пространство | `src/flutter/lib/features/workspace/workspace_page.dart`, надпись и Tooltip |
| Нативное окно Windows | `src/flutter/windows/runner/main.cpp`, window.Create |
| Свойства Windows EXE | `src/flutter/windows/runner/Runner.rc`: ProductName, FileDescription, CompanyName |
| Установщик, ярлыки, список программ Windows | `deploy/windows/installer.nsi`: Name, VIAddVersionKey, CreateShortcut, DisplayName, Publisher |
| Имя Android под иконкой | `src/flutter/android/app/src/main/res/values/strings.xml`: app_name |
| Привязка имени Android | `src/flutter/android/app/src/main/AndroidManifest.xml`: android:label="@string/app_name" |
| Вкладка/метаданные Web | `src/flutter/web/index.html`: title и meta |
| Web/PWA | `src/flutter/web/manifest.json`: name, short_name, description |

Одной замены в pubspec недостаточно. Часть нативных названий пока техническая,
например sklad_komforta_app. Название организации меняется в интерфейсе
организации и не переименовывает программу.

После изменения ARB из src/flutter выполните `flutter gen-l10n`, анализ,
тесты и сборку. Не редактируйте сгенерированные app_localizations*.dart.
При ребрендинге ищите оставшиеся надписи по исходникам, не заменяйте строку
глобально во всех файлах и сборочных каталогах.

### 13.3. Иконки

| Где | Исходники |
|---|---|
| Windows EXE / ярлык | `src/flutter/windows/runner/resources/app_icon.ico` |
| Windows setup.exe | `deploy/windows/installer.nsi`: MUI_ICON / MUI_UNICON перед вставкой страниц; специальная иконка мастера сейчас не задана |
| Android | `src/flutter/android/app/src/main/res/mipmap-*/ic_launcher.png` |
| Web favicon | `src/flutter/web/favicon.png` |
| Web/PWA | `src/flutter/web/icons/` и ссылки в manifest.json |

Windows нужен настоящий ICO нескольких размеров, не переименованный PNG.
Текущие Android-размеры: mdpi 48×48, hdpi 72×72, xhdpi 96×96,
xxhdpi 144×144, xxxhdpi 192×192.
Image Asset Android Studio может подготовить ресурсы; adaptive/round-иконки
требуют согласования XML/ресурсов с manifest, не только замены PNG.

Для Web обновляйте обычные и maskable-иконки согласно manifest.
После изменения нужна новая сборка и обновление установки.
Лаунчер/браузер может показывать старую картинку из кэша; не удаляйте
пользовательские данные ради иконки.

### 13.4. Идентификаторы — не обычные надписи

| Идентификатор | Ограничение |
|---|---|
| Android applicationId | `com.skladkomforta.sklad_komforta_app`; смена создаёт другое приложение, не обновление |
| Android namespace / MainActivity package | Связаны с Kotlin-кодом; для смены видимого названия не нужны |
| Windows BINARY_NAME | `src/flutter/windows/CMakeLists.txt`; имя EXE ожидают также Python и NSIS |
| NSIS UninstallKey / каталог | Участвуют в обнаружении установленного продукта |
| Имя setup.exe | Задано в NSIS OutFile и Python; менять согласованно |
| Android PACKAGE в Python | Проверка package ID, не подпись под иконкой |

Для существующих Android-установок сохраняйте ID и ключ.
При смене бренда обычно меняют надписи/ресурсы, а не эти идентификаторы.

### 13.5. Адрес сервера

**Адрес приложения вы явно указываете в команде сборки. Адрес файлов
при сборке указывать не нужно: клиент получает готовые ссылки от API.**

#### Откуда берётся адрес приложения в EXE/APK

Например, вы запускаете на Windows:

~~~powershell
python scripts/build_windows_installer.py --app-url https://app.skladkomforta.dpdns.org --flutter "D:\develop\flutter\bin\flutter.bat"
~~~

Цепочка следующая:

1. Python читает текст после `--app-url`. Это единственный источник основного
   адреса в этих сценариях; они не подключаются к ВМ и не читают её .env.server.
2. Функция build_arguments в сценарии добавляет к адресу путь /api/v1
   и передаёт значения Flutter через параметры `--dart-define`.
3. Flutter при release-компиляции встраивает значения в клиентский код.
   AppConfig.fromEnvironment в `src/flutter/lib/core/config/app_config.dart`
   получает их через String.fromEnvironment.
4. NSIS упаковывает уже собранный Windows-клиент. Установщик не выбирает сервер
   заново, не спрашивает адрес и не берёт его из папки установки.
5. При запуске установленный клиент обращается к встроенному API_BASE_URL.
   Android-сценарий делает ту же передачу параметров при сборке APK.

Для указанной команды во Flutter передаются:

~~~text
--dart-define=API_BASE_URL=https://app.skladkomforta.dpdns.org/api/v1
--dart-define=PUBLIC_APP_BASE_URL=https://app.skladkomforta.dpdns.org
--dart-define=APP_ENVIRONMENT=production
~~~

API_BASE_URL нужен для входа и запросов данных.
PUBLIC_APP_BASE_URL нужен для публичных ссылок на Web-приложение,
например ссылки клиенту на предложение; **это не адрес файлового хранилища**.

Сценарии требуют --app-url явно и принимают HTTPS-домен без пути и порта.
Если не передать его, они не должны молча выбрать localhost:
Windows завершится ошибкой отсутствующего аргумента, Android build тоже потребует адрес.
Development-значения в AppConfig нужны запуску без production-параметров;
не заменяйте их ради обычного выпуска.

Проверить адрес успешно завершившейся сборки можно по `appUrl` в её
`release.json`. Это паспорт, а не файл runtime-настроек:
правка release.json, .env.server или переменных Windows уже готовый EXE/APK
**не перенастраивает**. Для смены адреса API нужна новая сборка с новым --app-url.

#### Откуда клиент узнаёт адрес files

Адрес файлов формирует **сервер во время работы**, не Python-упаковщик:

1. В Ubuntu .env.server содержит `FILES_DOMAIN=files.skladkomforta.dpdns.org`.
2. compose.server.yaml передаёт API параметр
   `ObjectStorage__PublicUrl=https://files.skladkomforta.dpdns.org`.
3. S3ObjectStorage создаёт временную подписанную ссылку на конкретный объект
   для загрузки или скачивания. Внутренний `http://minio:9000` используется
   сервером внутри Docker, а публичные ссылки создаются с files-доменом.
4. API возвращает клиенту полный `uploadUrl` или `downloadUrl`.
5. Клиент использует этот URL как получен. Он не заменяет app на files
   и не знает пароля MinIO или серверного ключа подписи.

Пример для изображения каталога:

~~~text
Windows/Android -> app.../api/v1/catalog/items/<id>/images/uploads
API             -> возвращает uploadUrl с https://files... и подписью
Windows/Android -> PUT по полученному uploadUrl с содержимым файла
Windows/Android -> подтверждает загрузку через API на app...
API             -> возвращает сведения об изображении и downloadUrl
~~~

Подписанный URL даёт ограниченный по времени доступ к объекту.
Не меняйте в нём вручную домен/параметры и не публикуйте его в логах или чате.
По истечении срока клиенту требуется свежая ссылка от API.

Этот путь виден в [CatalogApi.uploadImage](../src/flutter/lib/features/catalog/catalog_api.dart)
и [S3ObjectStorage](../src/backend/SkladKomforta.Infrastructure/Files/S3ObjectStorage.cs).
Не все ответы с файлами идут через MinIO: например, генерируемый PDF предложения
и экспорт XLSX могут возвращаться самим API через app.

#### Что менять при переносе

| Изменение | Нужна новая сборка Windows/Android? |
|---|---|
| Изменился адрес приложения/API | Да: передать новый --app-url и установить новый выпуск |
| Изменился только files-домен, API остался прежним | Обычно нет: перенастроить сервер и маршрут files; клиент получит новые URL от API |
| Изменились имя/иконка/код клиента | Да, независимо от адреса сервера |

При смене files уже выданные ссылки продолжают содержать старое имя;
учтите их срок жизни и обновите данные в открытых клиентах.
На сервере APP_DOMAIN и FILES_DOMAIN задаются без схемы и согласуются
с маршрутами Cloudflare, Nginx, CORS и публичным адресом S3.

#### Как изменить адрес на существующем сервере без init

init нужен только для первой установки: его отказ перезаписывать файл защищает
действующие пароли и ключи. **Рабочие настройки можно редактировать вручную.**
Меняется .env.server, не .env.server.example и не файл внутри контейнера.

Сначала запланируйте окно обслуживания, сделайте backup по разделу 9,
подготовьте новые домены/TLS и маршруты Cloudflare на тот же http://web:80.
Новый Tunnel не обязателен, если используете прежний connector.

**Ubuntu, наш рабочий проект:**

~~~bash
cd ~/apps/prog/sklad-komforta
sudo nano .env.server
~~~

Измените **только существующие строки** APP_DOMAIN и FILES_DOMAIN.
Например, если вы владеете соответствующим новым доменом:

~~~dotenv
APP_DOMAIN=app.new-domain.example
FILES_DOMAIN=files.new-domain.example
~~~

Это шаблон, .example не рабочий домен. Укажите собственные имена без https://,
порта и завершающего слеша. Не добавляйте повторные строки.
Пароли, JWT_SIGNING_KEY, TOTP_ENCRYPTION_KEY и BOOTSTRAP_TOKEN оставьте прежними.
В nano: Ctrl+O, Enter для сохранения; Ctrl+X для выхода.
Не показывайте содержимое env в скриншотах.

Проверить и применить:

~~~bash
sudo python3 scripts/server.py config
sudo python3 scripts/server.py up
sudo python3 scripts/server.py status
~~~

Если config сообщает ошибку, исправьте файл до up.
Up перечитает Compose и пересоздаст сервисы с изменёнными настройками,
не удаляя volumes. Простого редактирования env или docker restart недостаточно:
окружение уже созданного контейнера от этого не меняется.
Для нестандартного проекта во всех командах передавайте прежние --project/--env
и редактируйте именно выбранный env, не создавайте новое имя проекта случайно.

Если публикация ранее была остановлена через unpublish, выполните publish.
При неизменном работающем Tunnel повторно вводить токен не нужно.
Проверьте новый сайт, вход/TOTP, загрузку и открытие файлов через мобильный интернет.
Изменение APP_DOMAIN меняет также JWT issuer: может понадобиться повторный вход.
Веб-клиент серверного профиля использует относительный /api/v1, то есть API
на домене открытой страницы; в отличие от нативных клиентов отдельный
--app-url ему не передают.

При смене app-домена пересоберите Windows/Android с новым --app-url и раздайте
обновления. При смене только files новые ссылки приходят от API без пересборки.
Старые EXE/APK не узнают новый адрес API автоматически.

**Плавный переезд требует отдельной подготовки:** текущий Nginx-профиль принимает
одно имя приложения и одно имя файлов. Сохранение старой DNS-записи само по себе
не сохраняет доступ по старому имени после смены env; редирект также не является
универсальным решением для API и подписанных S3-ссылок.
Если нельзя одновременно обновить всех клиентов, сначала нужен план поддержки
старого и нового адреса, а не мгновенное отключение старого.
Для отката без изменений БД верните прежние домены в env, проверьте config,
примените up и восстановите прежние маршруты Cloudflare.

### 13.6. Ключи и секреты

| Что | Где / для чего |
|---|---|
| Docker APT key | /etc/apt/keyrings/docker.asc, публичная проверка пакетов |
| SSH host key | /etc/ssh/, подлинность сервера; публичный отпечаток сверяют в PuTTY |
| Пароли, JWT, TOTP, bootstrap | .env.server, доступ к хранилищам/сеансам/2FA |
| Tunnel token | .env.server.secrets/, подключение connector |
| Backup key | /root/sklad-backup-keys/main.key, расшифровка серверных архивов |
| Android key / пароль | %USERPROFILE%\.sklad-komforta\android-signing, подпись обновлений APK |
| Recovery-коды | У владельца аккаунта, восстановление его доступа к 2FA |

Ключ backup не заменяет Android-ключ.
Смена TOTP_ENCRYPTION_KEY может сделать старые TOTP-секреты нечитаемыми.
Правка пароля БД/MinIO только в env может остановить приложение.
Ротация требует отдельного согласованного плана.

<a id="part-14"></a>
## 14. Назначение файлов

### Сервер

| Файл | Роль |
|---|---|
| [compose.server.yaml](../compose.server.yaml) | Одна ВМ: сервисы, сети, volumes, версии образов, restart, healthchecks |
| [.env.server.example](../.env.server.example) | Образец переменных без рабочих секретов |
| .env.server / .env.server.secrets | Реальные настройки и закрытые файлы connector; не коммитить |
| [scripts/server.py](../scripts/server.py) | Init, config, запуск, bootstrap, Tunnel, backup/restore |
| [init-postgres.sh](../deploy/server/init-postgres.sh) | Начальная настройка PostgreSQL/public на чистом volume |
| [init-minio.sh](../deploy/server/init-minio.sh) | Закрытый bucket и ограниченный пользователь |
| [storage-policy.json](../deploy/server/storage-policy.json) | Права пользователя MinIO |
| [server.conf.template](../src/flutter/docker/nginx/server.conf.template) | Nginx: Web/API/файлы, домены, ограничения, закрытый bootstrap |
| migrations/public и migrations/tenant | SQL общей части и организаций; обновления по отдельному плану |
| [compose.yaml](../compose.yaml) | Локальная разработка, не наш публичный профиль |
| [compose.production.yaml](../compose.production.yaml) | Другой production-профиль с внешними хранилищами |
| tests/server | Тесты; интеграционный smoke не запускать на рабочем Docker |

### Клиенты и упаковка

| Файл | Роль |
|---|---|
| [build_windows_installer.py](../scripts/build_windows_installer.py) | Flutter Windows, CRT, NSIS, хеш/паспорт |
| [installer.nsi](../deploy/windows/installer.nsi) | Мастер, каталог, ярлыки, HKCU, обновление/удаление |
| [build_android_apk.py](../scripts/build_android_apk.py) | Ключ вне Git, Flutter APK, проверка подписи/package, хеш |
| [build.gradle.kts](../src/flutter/android/app/build.gradle.kts) | ID/SDK Android, версия Flutter, release-подпись |
| [AndroidManifest.xml](../src/flutter/android/app/src/main/AndroidManifest.xml) | INTERNET, activity, имя/иконка, запрет Android backup |
| [strings.xml](../src/flutter/android/app/src/main/res/values/strings.xml) | Видимое имя Android |
| [pubspec.yaml](../src/flutter/pubspec.yaml) | Версия, зависимости и Flutter-настройки |
| pubspec.lock | Зафиксированные версии Dart-пакетов |
| android/local.properties | Локальные пути SDK/Flutter, не адрес сервера |
| tests/windows-installer и tests/android-apk | Тесты сценариев и ограничений упаковки |
| build/windows-installer и build/android-apk | Результаты выпусков, не исходники |
| build/tools | Локальные инструменты вроде portable NSIS, не часть клиента |
| .gitignore / .dockerignore | Исключения секретов/артефактов из Git и Docker-контекста |

Android backup отключён для предотвращения переноса зашифрованных токенов
без подходящих ключей secure storage. Серверный backup от этого не отключается.

Не редактируйте вместо исходников build, .dart_tool, .gradle,
Windows ephemeral и сгенерированные списки упаковки.

<a id="part-15"></a>
## 15. Обновления и диагностика

### 15.1. Выпуск клиентов

**Как обновления доходят до пользователей сейчас**

Автоматической проверки версии, загрузчика обновлений и магазина приложений
в текущем решении нет. Новые файлы в GitHub или на сервере сами по себе
не обновляют установленный Windows EXE или Android APK.

| Клиент | Как получает новую версию |
|---|---|
| Браузер | После обновления Web на сервере пользователь перезагружает страницу; уже открытая вкладка может продолжать выполнять старый код |
| Windows | Вы передаёте новый setup.exe; пользователь закрывает клиент и запускает установщик под той же учётной записью в прежнюю папку |
| Android | Вы передаёте новый APK; пользователь устанавливает его поверх старого с тем же applicationId и ключом подписи, с повышенным versionCode |

Удалять прежний клиент перед штатным обновлением не нужно.
Для Windows проверьте прежний путь установки, для Android не создавайте новый
ключ. Серверные данные остаются на сервере, но совместимость новой версии API
со старыми клиентами и сохранение входа нужно проверять при выпуске.
Изменения только на backend могут начать работать без новой сборки клиента,
если не изменили совместимый контракт API.

Распространять пакеты пока нужно вручную через доверенный канал
вместе с контрольной суммой. Страница скачивания тоже сама по себе
не является автоматическим обновлением.
Автообновление можно реализовать отдельно: проверка версии, доверенные метаданные
и пакеты, установка с учётом правил ОС, обработка ошибок и совместимость.
Оно не появляется от изменения pubspec.yaml или запуска сборщика.

1. Измените исходники и при необходимости название/иконки.
2. Увеличьте версию pubspec.yaml.
3. Выполните тесты. Для выпуска проверьте и зафиксируйте изменения в Git:
   dirty: true в release.json означает незакоммиченные изменения.
4. Соберите Windows и Android последовательно.
5. Проверьте обновление поверх предыдущего клиента и основные операции.
   Не создавайте новый Android-ключ.
6. Передайте setup.exe/APK, сохраните хеши и release.json.
   Сценарии не публикуют файлы, не делают commit/push и не обновляют сотрудников.

**PowerShell, корень проекта:**

~~~powershell
python -m unittest discover -s tests/windows-installer -v
python -m unittest discover -s tests/android-apk -v
Push-Location src/flutter
& "D:\develop\flutter\bin\flutter.bat" analyze
& "D:\develop\flutter\bin\flutter.bat" test
Pop-Location
~~~

### 15.2. Обновление сервера

Сначала проверенный выпуск, успешный backup и план миграций, если менялась БД.
После подтверждения публикации нужного кода, **Ubuntu**:

~~~bash
cd ~/apps/prog/sklad-komforta
git status --short
git pull --ff-only
git log -1 --oneline
sudo python3 scripts/server.py config
sudo python3 scripts/server.py up
sudo python3 scripts/server.py status
~~~

При неизвестных локальных изменениях/конфликте Git остановитесь,
не выполняйте reset --hard.
Не удаляйте env/volumes ради «чистого обновления».

Начальный PostgreSQL-скрипт работает на **новом volume**.
Git pull и пересборка не являются автоматической миграцией всех существующих
public/tenant-схем. Миграции требуют отдельной проверки совместимости.

Проверьте внешний HTTPS, TOTP, файлы и Tunnel.
После ручного unpublish connector нужно явно вернуть через publish.
Откат кода сам по себе не откатывает изменённую БД.

### 15.3. Диагностика

<a id="monitoring"></a>
#### Мониторинг всей Ubuntu-ВМ

Эти команды выполняются **в PuTTY/Ubuntu**, не в PowerShell Windows.
Они показывают ресурсы, выделенные ВМ (у нас 4 CPU / 8 ГБ RAM),
а не все ресурсы физического ПК. Для самого Windows-хоста отдельно откройте
Диспетчер задач и проверьте CPU, память, диск и процесс VirtualBox.

Быстрый обзор:

~~~bash
uptime
nproc
free -h
df -h /
df -i /
~~~

| Команда / поле | Как понимать |
|---|---|
| uptime, load average | Очередь выполняемых/ожидающих задач за 1/5/15 минут, не процент CPU; зависит и от ожидания диска |
| nproc | Число доступных процессоров ВМ; длительный load заметно выше этого числа требует изучения CPU и I/O |
| free -h, available | Оценка памяти, доступной приложениям; низкое free при большом файловом кэше само по себе не проблема |
| free -h, Swap | Занятое место подкачки; постоянная активная подкачка вместе с задержками может означать нехватку RAM |
| df -h / | Заполненность корневой файловой системы |
| df -i / | Остаток inode: множество мелких файлов может исчерпать их раньше места в байтах |

Живой список процессов:

~~~bash
top
~~~

В top: `P` — сортировка по CPU, `M` — по памяти, `1` — отдельные CPU,
`q` — выход. Альтернатива: `htop`, если установлен.
Не применяйте команды завершения процессов при обычном наблюдении.

CPU/подкачка/ожидание диска каждые 2 секунды:

~~~bash
vmstat 2
~~~

Смотрите r (готовые задачи), si/so (подкачка), us/sy (CPU), id (простой),
wa (ожидание I/O). Первая строка обычно отражает среднее с загрузки,
последующие — текущие интервалы. Выход: Ctrl+C.

#### Мониторинг контейнеров

Для начала узнайте имена:

~~~bash
sudo docker ps --filter label=com.docker.compose.project=sklad-komforta-server --format 'table {{.Names}}\t{{.Status}}'
~~~

Все работающие контейнеры этого Docker daemon в реальном времени:

~~~bash
sudo docker stats
~~~

Один снимок без постоянного обновления:

~~~bash
sudo docker stats --no-stream
~~~

Только API или несколько конкретных контейнеров нашего проекта:

~~~bash
sudo docker stats sklad-komforta-server-api-1
sudo docker stats sklad-komforta-server-api-1 sklad-komforta-server-worker-1 sklad-komforta-server-postgres-1
~~~

Каждую живую команду запускайте отдельно; Ctrl+C закрывает наблюдение,
**не останавливает контейнеры**. Для другого --project возьмите имена
из docker ps, не копируйте production-имена в тестовую среду.

| Поле docker stats | Значение |
|---|---|
| CPU % | На Linux 100% приблизительно соответствует одному полностью занятому CPU; сумма может превышать 100% |
| MEM USAGE / LIMIT | Память контейнера и доступный лимит; без индивидуального ограничения лимит может отражать память ВМ |
| MEM % | Доля от показанного лимита; память не резервируется каждому контейнеру в этом размере |
| NET I/O | Накопленные принятые/отправленные байты, не скорость в секунду |
| BLOCK I/O | Накопленный обмен с блочными устройствами, не размер файлов контейнера |
| PIDS | Процессы и потоки, не число пользователей |

В Linux Docker CLI вычитает часть файлового кэша из показателя памяти:
сумма stats не обязана совпадать с free.
Официальная справка: [docker stats](https://docs.docker.com/reference/cli/docker/container/stats/).

Занятость диска ресурсами Docker, отдельно от RAM:

~~~bash
sudo docker system df
sudo docker system df -v
~~~

Вторая команда показывает подробности образов, контейнеров и volumes;
на большой системе может выполняться дольше. Это не полный учёт всего диска:
проверяйте также df, архивы backup и журналы.
`RECLAIMABLE` не означает «можно безопасно удалить всё»:
**не запускайте prune --volumes и не удаляйте volumes ради освобождения места**.
Справка: [docker system df](https://docs.docker.com/reference/cli/docker/system/df/).

Проверка перезапусков и OOM одного контейнера без вывода его секретных env:

~~~bash
sudo docker inspect --format 'status={{.State.Status}} restarts={{.RestartCount}} oomKilled={{.State.OOMKilled}} exitCode={{.State.ExitCode}}' sklad-komforta-server-api-1
sudo journalctl -k --since "1 hour ago" --no-pager | grep -Ei 'out of memory|oom|killed process'
~~~

Если grep ничего не вывел, совпадений в этом журнале за час нет.
OOMKilled=false тоже не доказывает отсутствие любых проблем с памятью:
сопоставляйте журнал, динамику RAM и перезапуски.
Для постоянной истории/оповещений нужна отдельная система мониторинга;
эти команды показывают текущее состояние, а не настраивают автоматические уведомления.

#### Состояние и логи

**Ubuntu, корень проекта:**

~~~bash
sudo python3 scripts/server.py status
df -h /
timedatectl status
sudo docker compose --env-file .env.server -f compose.server.yaml logs --tail 80 api web minio-init cloudflared
~~~

Логи сначала смотрите локально, не отправляйте пароли, cookie и подписанные URL.
Полные docker inspect и docker compose config могут раскрывать секреты.
Для безопасной проверки конфигурации используйте server.py config.

| Симптом | Проверка |
|---|---|
| totp_invalid / «сессия истекла» | Время Ubuntu/телефона, свежий код и верный аккаунт аутентификатора |
| ERR_BLOCKED_BY_CLIENT у analytics | Блокировщик браузера, не доказательство поломки API |
| minio-init Exited (0) | Норма для завершённой одноразовой задачи |
| pull access denied MinIO | Точный тег/источник; доверенный save/load из раздела 6 |
| 502 после Tunnel | Запущены ли сервисы, маршрут http://web:80, hostname и сеть |
| files возвращает 404 | Корень не файловый менеджер; проверяйте через приложение |
| Сайт пропал после сна ПК | ВМ и Windows должны оставаться включёнными |
| sudo ls backups/*.tar.gpg не находит архив | sudo ls -lah backups; glob раскрывается до sudo |
| & $python: недопустимый объект | Переменная не задана; используйте python из PATH |
| Release требует SKLAD_ANDROID_SIGNING_DIR | Запускать Python-сценарий с существующим ключом |
| APK не обновляется | Package ID, ключ подписи и versionCode |
| Старое имя/иконка | Нужный платформенный исходник, свежая сборка/установка и кэш |
| Несколько папок build | Отдельные результаты запусков; брать последний успешный |

### 15.4. Подтверждено и отложено

Владелец подтвердил: внешний сайт и файлы работают через мобильный интернет,
Ubuntu перезапущена успешно, Windows-клиент и Android APK работают.
Это пользовательская проверка имеющихся устройств, не всех версий ОС,
и не повторный запуск тестов в рамках написания документа.

Ранее выполнены серверный интеграционный backup/restore, тесты сценариев
упаковки, Flutter analyze и Flutter-тесты. Подробности в документах ниже.

**Не считать уже выполненными:**

- Внешняя резервная копия всей папки Android-подписи.
- Регулярные серверные архивы вне физического ПК и проверка аварийного восстановления.
- Расписание backup, контроль ошибок и срок хранения.
- Автозапуск ВМ после старта Windows.
- Проверка чистой Windows без инструментов разработчика и обновления обоих клиентов.
- Подпись издателя Windows, автообновление и страница скачивания.
- Отдельная тестовая среда и согласованный процесс миграций/выпуска.

### Дополнительные технические детали

- [Сервер: команды, ограничения, backup/restore, тесты](iteration-08/server-deployment.md).
- [Windows: контракт упаковки и результаты проверок](iteration-08/windows-installer.md).
- [Android: подпись, ограничения и результаты проверок](iteration-08/android-apk.md).

Это справочные детали единого маршрута, не три разных установки.
