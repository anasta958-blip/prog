BEGIN;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS employee_limit integer NOT NULL DEFAULT 5 CHECK (employee_limit >= 0);
ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS employee_limit integer NOT NULL DEFAULT 5 CHECK (employee_limit >= 0);
INSERT INTO public.schema_migrations (version) VALUES ('0008_employee_limits') ON CONFLICT (version) DO NOTHING;
COMMIT;
