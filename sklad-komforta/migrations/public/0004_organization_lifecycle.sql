BEGIN;

ALTER TABLE public.organizations
    ADD COLUMN IF NOT EXISTS active_until timestamptz;

UPDATE public.organizations
SET active_until = created_at + interval '1 year'
WHERE active_until IS NULL;

ALTER TABLE public.organizations
    ALTER COLUMN active_until SET NOT NULL,
    ALTER COLUMN active_until SET DEFAULT (now() + interval '1 year');

ALTER TABLE public.organization_members
    ADD COLUMN IF NOT EXISTS created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_organizations_active_until
    ON public.organizations (active_until)
    WHERE is_active AND deleted_at IS NULL;

INSERT INTO public.schema_migrations (version)
VALUES ('0004_organization_lifecycle')
ON CONFLICT (version) DO NOTHING;

COMMIT;
