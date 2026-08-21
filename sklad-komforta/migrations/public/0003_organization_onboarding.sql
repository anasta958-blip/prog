BEGIN;

ALTER TABLE public.organizations
    ADD COLUMN onboarding_completed_at timestamptz NULL;

INSERT INTO public.schema_migrations (version)
VALUES ('0003_organization_onboarding');

COMMIT;
