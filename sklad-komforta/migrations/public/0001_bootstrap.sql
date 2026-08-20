BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version varchar(100) PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    login citext NOT NULL UNIQUE,
    password_hash text NOT NULL,
    display_name text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    must_change_password boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz NULL
);

CREATE TABLE public.user_totp_credentials (
    user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    encrypted_secret bytea NOT NULL,
    enabled_at timestamptz NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    schema_name varchar(39) NOT NULL UNIQUE
        CHECK (schema_name ~ '^tenant_[a-f0-9]{32}$'),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz NULL
);

CREATE TABLE public.organization_members (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    is_director boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz NULL,
    UNIQUE (organization_id, user_id)
);

CREATE UNIQUE INDEX ux_organization_single_director
    ON public.organization_members (organization_id)
    WHERE is_director AND deleted_at IS NULL;

CREATE INDEX ix_organization_members_user
    ON public.organization_members (user_id)
    WHERE deleted_at IS NULL;

CREATE TABLE public.refresh_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    token_hash bytea NOT NULL UNIQUE,
    device_type smallint NOT NULL CHECK (device_type BETWEEN 1 AND 5),
    device_name text NULL,
    ip_address inet NULL,
    user_agent text NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_refresh_sessions_active_user
    ON public.refresh_sessions (user_id, expires_at DESC)
    WHERE revoked_at IS NULL;

CREATE TABLE public.tenant_migrations (
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    version varchar(100) NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, version)
);

CREATE TABLE public.security_audit_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    organization_id uuid NULL REFERENCES public.organizations(id) ON DELETE SET NULL,
    event_type varchar(100) NOT NULL,
    ip_address inet NULL,
    user_agent text NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_security_audit_log_created
    ON public.security_audit_log (created_at DESC);

INSERT INTO public.schema_migrations (version)
VALUES ('0001_bootstrap')
ON CONFLICT (version) DO NOTHING;

COMMIT;
