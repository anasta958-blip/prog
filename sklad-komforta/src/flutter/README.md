# Flutter-клиент «Склад Комфорта»

Один Flutter-проект используется для Windows, macOS, Web, Android и iOS.
Платформы отличаются упаковкой, подписью и системными интеграциями, но используют
общий Dart-код из `lib/`.

## Локальный SDK

На рабочем компьютере Flutter расположен в `D:\develop\flutter`. Android SDK
указан в `android/local.properties` и расположен в `E:\Android\Sdk`.

Проверка окружения:

```powershell
& "D:\develop\flutter\bin\flutter.bat" doctor -v
& "E:\Android\Sdk\platform-tools\adb.exe" devices -l
```

## Android API 37

Плагин `flutter_secure_storage` версии 11 требует `compileSdk = 37`. Это значение
зафиксировано в `android/app/build.gradle.kts`. Оно влияет только на компиляцию:
`minSdk` не повышен, поэтому поддержка совместимых старых устройств сохраняется.

В `E:\Android\Sdk\platforms\android-37.0` уже установлена необходимая платформа.
Отладочная сборка:

```powershell
& "D:\develop\flutter\bin\flutter.bat" build apk --debug
```

Готовый APK находится в `build/app/outputs/flutter-apk/app-debug.apk`.

## Запуск на физическом Android-устройстве

1. Включить на телефоне режим разработчика и отладку по USB.
2. Подключить устройство и подтвердить его RSA-ключ на экране телефона.
3. Проверить идентификатор командой `adb devices -l`.
4. Запустить Flutter с адресом API, доступным телефону.

При подключении по USB рекомендуется перенаправить порт телефона на компьютер:

```powershell
& "E:\Android\Sdk\platform-tools\adb.exe" reverse tcp:8080 tcp:8080
& "D:\develop\flutter\bin\flutter.bat" run -d 24095PCADG --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

Перенаправление действует, пока подключено устройство или пока не перезапущен
ADB. Проверить его можно командой `adb reverse --list`.

Если телефон и компьютер находятся в одной локальной сети:

```powershell
& "D:\develop\flutter\bin\flutter.bat" run -d 24095PCADG --dart-define=API_BASE_URL=http://IP_КОМПЬЮТЕРА:8080/api/v1
```

`localhost` на телефоне означает сам телефон, а не компьютер. Поэтому локальный
API через `http://localhost:8080` с физического устройства недоступен. Для
production используется HTTPS-адрес вида `https://app.example.com/api/v1`.

Остановка `flutter run` выполняется клавишей `q`. Сочетание `Ctrl+C` принудительно
прерывает команду; вопрос PowerShell «Завершить выполнение пакетного файла?» не
является ошибкой Gradle.

## Запуск остальных платформ

```powershell
& "D:\develop\flutter\bin\flutter.bat" run -d windows --dart-define=API_BASE_URL=http://localhost:8080/api/v1
& "D:\develop\flutter\bin\flutter.bat" run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api/v1
```

macOS и iOS собираются только на macOS с Xcode. Исходный код и платформенные
заготовки уже находятся в этом проекте.

## Проверки

```powershell
& "D:\develop\flutter\bin\flutter.bat" analyze
& "D:\develop\flutter\bin\flutter.bat" test
```

Перед распространением release-сборок необходимо настроить отдельные ключи
подписи для каждой платформы. Текущий Android release-конфиг использует
отладочный ключ и подходит только для разработки.
