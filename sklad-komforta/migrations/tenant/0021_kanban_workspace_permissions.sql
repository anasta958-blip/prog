SET search_path TO __TENANT_SCHEMA__, public;

INSERT INTO permissions (code, name, group_name)
VALUES
    ('kanban.view', 'Просмотр канбанов', 'Канбаны'),
    ('kanban.manage', 'Управление канбанами', 'Канбаны')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;
