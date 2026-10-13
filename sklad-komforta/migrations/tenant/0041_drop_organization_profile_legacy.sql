-- Реквизиты используются только из companies. Архив профиля больше не нужен.
-- Без CASCADE: при неожиданных зависимостях миграция остановится, не удаляя их.
DROP TABLE IF EXISTS organization_profile_legacy;
