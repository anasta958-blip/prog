-- The provisioner replaces __TENANT_SCHEMA__ only with a generated,
-- validated TenantSchemaName. User input must never be substituted here.
CREATE SCHEMA IF NOT EXISTS __TENANT_SCHEMA__;
SET search_path TO __TENANT_SCHEMA__, public;

CREATE TABLE roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL UNIQUE,
    is_system boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz NULL
);

CREATE TABLE permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(160) NOT NULL UNIQUE,
    name text NOT NULL,
    group_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE role_permissions (
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE member_roles (
    membership_id uuid NOT NULL REFERENCES public.organization_members(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (membership_id, role_id)
);

CREATE TABLE organization_settings (
    key varchar(160) PRIMARY KEY,
    value jsonb NOT NULL,
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_type varchar(20) NOT NULL,
    name text NOT NULL,
    legal_name text NULL,
    inn varchar(12) NULL,
    kpp varchar(9) NULL,
    ogrn varchar(15) NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_default boolean NOT NULL DEFAULT false,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz NULL
);

CREATE UNIQUE INDEX ux_companies_default
    ON companies (is_default)
    WHERE is_default AND deleted_at IS NULL;

CREATE TABLE clients (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz NULL
);

CREATE TABLE contractors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz NULL
);

CREATE TABLE audit_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_user_id uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    entity_type varchar(100) NOT NULL,
    entity_id uuid NULL,
    action varchar(100) NOT NULL,
    diff jsonb NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_audit_log_entity
    ON audit_log (entity_type, entity_id, created_at DESC);

