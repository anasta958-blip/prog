SET search_path TO __TENANT_SCHEMA__, public;

DROP TABLE IF EXISTS contractors;

ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS address text NULL,
    ADD COLUMN IF NOT EXISTS phone text NULL,
    ADD COLUMN IF NOT EXISTS email text NULL;

INSERT INTO companies (
    company_type, name, legal_name, inn, kpp, ogrn,
    address, phone, email, is_default
)
SELECT COALESCE(company_type, 'ООО'), organization_name, legal_name, inn, kpp, ogrn,
       address, phone, email, true
FROM organization_profile
WHERE singleton
  AND NOT EXISTS (SELECT 1 FROM companies WHERE deleted_at IS NULL);

ALTER TABLE clients
    ADD COLUMN IF NOT EXISTS company_name text NULL,
    ADD COLUMN IF NOT EXISTS contact_name text NULL,
    ADD COLUMN IF NOT EXISTS phone text NULL,
    ADD COLUMN IF NOT EXISTS email text NULL,
    ADD COLUMN IF NOT EXISTS address text NULL;

CREATE TABLE IF NOT EXISTS employee_profiles (
    membership_id uuid PRIMARY KEY REFERENCES public.organization_members(id) ON DELETE CASCADE,
    email text NULL,
    phone text NULL,
    telegram text NULL,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS role_subordination (
    supervisor_role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    subordinate_role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (supervisor_role_id, subordinate_role_id),
    CHECK (supervisor_role_id <> subordinate_role_id)
);

CREATE TABLE IF NOT EXISTS member_reporting (
    membership_id uuid PRIMARY KEY REFERENCES public.organization_members(id) ON DELETE CASCADE,
    supervisor_membership_id uuid NOT NULL REFERENCES public.organization_members(id) ON DELETE CASCADE,
    CHECK (membership_id <> supervisor_membership_id)
);

-- Новая модель допускает ровно одну роль. Для старых данных сохраняется
-- системная роль директора, иначе первая роль по стабильному UUID-порядку.
WITH ranked AS (
    SELECT member_role.membership_id,
           member_role.role_id,
           row_number() OVER (
               PARTITION BY member_role.membership_id
               ORDER BY CASE WHEN role.name = 'Директор' THEN 0 ELSE 1 END,
                        member_role.role_id
           ) AS position
    FROM member_roles AS member_role
    JOIN roles AS role ON role.id = member_role.role_id
)
DELETE FROM member_roles AS member_role
USING ranked
WHERE member_role.membership_id = ranked.membership_id
  AND member_role.role_id = ranked.role_id
  AND ranked.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_member_roles_single_role
    ON member_roles (membership_id);

CREATE INDEX IF NOT EXISTS ix_member_reporting_supervisor
    ON member_reporting (supervisor_membership_id);

INSERT INTO permissions (code, name, group_name)
VALUES
    ('company.legal_entities.view', 'Просмотр юридических лиц', 'Компания'),
    ('company.legal_entities.manage', 'Управление юридическими лицами', 'Компания'),
    ('company.clients.view', 'Просмотр клиентов', 'Компания'),
    ('company.clients.manage', 'Управление клиентами', 'Компания'),
    ('company.employees.view', 'Просмотр сотрудников', 'Компания'),
    ('company.employees.manage', 'Управление сотрудниками', 'Компания'),
    ('company.access.view', 'Просмотр прав доступа', 'Компания'),
    ('company.access.manage', 'Управление правами доступа', 'Компания')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;

INSERT INTO role_permissions (role_id, permission_id)
SELECT role.id, permission.id
FROM roles AS role
CROSS JOIN permissions AS permission
WHERE role.name = 'Директор'
  AND role.is_system
  AND permission.code LIKE 'company.%'
ON CONFLICT DO NOTHING;
