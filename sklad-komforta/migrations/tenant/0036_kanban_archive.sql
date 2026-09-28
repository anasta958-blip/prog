SET search_path TO __TENANT_SCHEMA__, public;

ALTER TABLE kanban_cards ADD COLUMN IF NOT EXISTS is_archived boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS ix_kanban_cards_archive
    ON kanban_cards (workflow_id, column_id, is_archived, sort_order, id)
    WHERE deleted_at IS NULL;
