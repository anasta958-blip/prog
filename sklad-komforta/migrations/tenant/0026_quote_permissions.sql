SET search_path TO __TENANT_SCHEMA__, public;

-- Содержимое КП/ПКП управляется отдельно от универсальной карточки канбана.
-- Директор сохраняет полный доступ, остальные роли получают эти права явно.
INSERT INTO permissions (code, name, group_name)
VALUES
    ('quotes.view', 'Просмотр КП и ПКП', 'Коммерческие предложения'),
    ('quotes.manage', 'Редактирование КП и ПКП', 'Коммерческие предложения')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;
