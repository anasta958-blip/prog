BEGIN;

-- A director can authenticate before the first organization is provisioned.
-- The session receives an organization after onboarding or organization switch.
ALTER TABLE public.refresh_sessions
    ALTER COLUMN organization_id DROP NOT NULL;

CREATE TABLE public.user_recovery_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    code_hash bytea NOT NULL,
    used_at timestamptz NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, code_hash)
);

CREATE INDEX ix_user_recovery_codes_available
    ON public.user_recovery_codes (user_id)
    WHERE used_at IS NULL;

CREATE INDEX ix_refresh_sessions_active_organization
    ON public.refresh_sessions (organization_id, expires_at DESC)
    WHERE revoked_at IS NULL AND organization_id IS NOT NULL;

INSERT INTO public.schema_migrations (version)
VALUES ('0002_identity_security');

COMMIT;
