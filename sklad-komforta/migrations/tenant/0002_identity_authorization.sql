SET search_path TO __TENANT_SCHEMA__, public;

INSERT INTO permissions (code, name, group_name)
VALUES
    ('system.full_access', 'Полный доступ', 'Система'),
    ('settings.roles.view', 'Просмотр ролей', 'Настройки'),
    ('settings.roles.manage', 'Управление ролями', 'Настройки'),
    ('settings.members.view', 'Просмотр сотрудников', 'Настройки'),
    ('settings.members.manage', 'Управление сотрудниками', 'Настройки')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;

INSERT INTO roles (name, is_system)
VALUES ('Директор', true), ('Администратор', true)
ON CONFLICT (name) DO UPDATE SET is_system = true;

INSERT INTO role_permissions (role_id, permission_id)
SELECT role.id, permission.id
FROM roles AS role
CROSS JOIN permissions AS permission
WHERE role.name IN ('Директор', 'Администратор')
  AND permission.code = 'system.full_access'
ON CONFLICT DO NOTHING;
