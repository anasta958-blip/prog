SET search_path TO __TENANT_SCHEMA__, public;

-- Исправляет подписи, повреждённые в уже созданных организациях старым
-- способом выполнения миграции. Коды прав остаются стабильными.
INSERT INTO permissions (code, name, group_name)
VALUES
    ('catalog.view', 'Просмотр каталога', 'Каталог'),
    ('catalog.manage', 'Управление каталогом', 'Каталог'),
    ('company.audit.view', 'Просмотр аудита изменений', 'Компания')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;

-- Директор является верхнеуровневой системной ролью и не может быть назначен
-- подчинённым другой роли.
DELETE FROM role_subordination AS relation
USING roles AS subordinate
WHERE subordinate.id = relation.subordinate_role_id
  AND subordinate.is_system;

INSERT INTO role_permissions (role_id, permission_id)
SELECT role.id, permission.id
FROM roles AS role
JOIN permissions AS permission ON permission.code = 'company.audit.view'
WHERE role.is_system
  AND role.name = 'Директор'
ON CONFLICT DO NOTHING;
