# SSH-доступ к Ubuntu VM с Windows

Памятка для локальной VM VirtualBox: Windows подключается к Ubuntu по NAT
`127.0.0.1:2222`, пользователь Ubuntu — `sayu`, имя подключения — `codex-vm`.
Команды PowerShell выполняются **в Windows**; команды Bash — **в PuTTY/Ubuntu**.

## Быстрое подключение после настройки

В обычном PowerShell:

```powershell
ssh-add -l
```

Если агент отвечает `The agent has no identities`, добавьте ключ. Фраза ключа
понадобится один раз:

```powershell
ssh-add "$env:USERPROFILE\.ssh\codex_vm_ed25519"
```

Проверка без запроса пароля Ubuntu или фразы ключа:

```powershell
ssh -o BatchMode=yes codex-vm "whoami; docker ps"
```

Ожидаемый результат: `sayu` и список контейнеров. Для обычной консоли VM:

```powershell
ssh codex-vm
```

Если VM выключена или проброс порта 2222 недоступен, SSH не подключится.

## Разовая настройка на новом Windows-компьютере или новой VM

1. Создайте отдельный ключ в PowerShell **только если файла ещё нет**:

   ```powershell
   ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\codex_vm_ed25519" -C "codex-vm"
   ```

   Задайте фразу ключа. Не перезаписывайте существующий приватный ключ.

2. Создайте файл `$env:USERPROFILE\.ssh\config` без расширения `.txt`:

   ```powershell
   notepad "$env:USERPROFILE\.ssh\config"
   ```

   Содержимое для этой VM:

   ```text
   Host codex-vm
       HostName 127.0.0.1
       Port 2222
       User sayu
       IdentityFile ~/.ssh/codex_vm_ed25519
       IdentitiesOnly yes
   ```

3. Один раз добавьте **публичный** ключ в Ubuntu. Команда попросит пароль
   пользователя `sayu`, если вход по ключу ещё не настроен:

   ```powershell
   Get-Content "$env:USERPROFILE\.ssh\codex_vm_ed25519.pub" |
       ssh codex-vm "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
   ```

   `authorized_keys` находится в `/home/sayu/.ssh/` **в Ubuntu**. Приватный
   ключ остаётся на Windows и не передаётся в чат или на VM.

4. Проверьте вход по ключу в PowerShell:

   ```powershell
   ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no codex-vm whoami
   ```

   Команда может запросить фразу ключа, но должна вывести `sayu`, не спрашивая
   пароль Ubuntu.

5. Если `docker ps` сообщает о запрете доступа, один раз выполните **в Ubuntu**:

   ```bash
   sudo usermod -aG docker sayu
   ```

   Выйдите из SSH/PuTTY и подключитесь заново, затем проверьте `docker ps`.
   Группа `docker` даёт пользователю широкие права на VM.

6. Чтобы SSH не спрашивал фразу при каждом подключении, в PowerShell
   **от имени администратора** запустите службу в таком порядке:

   ```powershell
   Set-Service ssh-agent -StartupType Automatic
   Start-Service ssh-agent
   ```

   В обычном PowerShell добавьте ключ:

   ```powershell
   ssh-add "$env:USERPROFILE\.ssh\codex_vm_ed25519"
   ```

После настройки запускайте проверку из раздела «Быстрое подключение».
Для прямого SSH из Codex выберите **Permissions → Ask for approval** в чате
и подтвердите запрос на SSH-команду. Песочница Windows работает от отдельного
пользователя и без такого подтверждения не видит `~/.ssh` и SSH-агент.
Проверенный ответ команды `ssh -o BatchMode=yes codex-vm whoami` — `sayu`.
В запросе к Codex укажите `codex-vm` и путь к проекту внутри Ubuntu.
Перед тестами с записью используйте отдельную тестовую БД, а не рабочую базу
сайта.
