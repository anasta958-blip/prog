BEGIN;

CREATE TABLE public.quote_client_access_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    quote_id uuid NOT NULL,
    token_hash bytea NOT NULL UNIQUE,
    password_hash text NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz NULL,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NULL,
    CHECK (expires_at > created_at)
);

CREATE INDEX ix_quote_client_access_links_quote
    ON public.quote_client_access_links (organization_id, quote_id, created_at DESC)
    WHERE revoked_at IS NULL;

INSERT INTO public.schema_migrations (version)
VALUES ('0005_quote_client_access')
ON CONFLICT (version) DO NOTHING;

COMMIT;
