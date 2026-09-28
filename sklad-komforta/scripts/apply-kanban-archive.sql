-- Apply tenant migration 0036 to existing organizations before deploying API.
BEGIN;
DO $migration$
DECLARE organization record;
BEGIN
    FOR organization IN SELECT id, schema_name FROM public.organizations LOOP
        IF organization.schema_name !~ '^tenant_[a-f0-9]{32}$' THEN
            RAISE EXCEPTION 'Invalid tenant schema';
        END IF;
        IF to_regclass(format('%I.kanban_cards', organization.schema_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('ALTER TABLE %I.kanban_cards ADD COLUMN IF NOT EXISTS is_archived boolean NOT NULL DEFAULT false', organization.schema_name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS ix_kanban_cards_archive ON %I.kanban_cards (workflow_id, column_id, is_archived, sort_order, id) WHERE deleted_at IS NULL', organization.schema_name);
        INSERT INTO public.tenant_migrations (organization_id, version)
        VALUES (organization.id, '0036_kanban_archive') ON CONFLICT DO NOTHING;
    END LOOP;
END
$migration$;
COMMIT;
