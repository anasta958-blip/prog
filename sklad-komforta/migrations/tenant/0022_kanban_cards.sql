SET search_path TO __TENANT_SCHEMA__, public;

-- Универсальная карточка канбана хранит только общие данные рабочего процесса.
-- Содержимое КП, ПКП и комплектаций будет добавлено отдельными модулями и не
-- смешивается с базовой моделью канбана.
ALTER TABLE workflow_columns
    ADD CONSTRAINT workflow_columns_id_workflow_unique UNIQUE (id, workflow_id);

CREATE TABLE kanban_cards (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    card_number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
    workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE RESTRICT,
    column_id uuid NOT NULL,
    category_id uuid NOT NULL,
    title varchar(200) NOT NULL CHECK (btrim(title) <> ''),
    values jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(values) = 'object'),
    sort_order bigint NOT NULL DEFAULT 0,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    deleted_at timestamptz NULL,
    CONSTRAINT kanban_cards_column_workflow_fk
        FOREIGN KEY (column_id, workflow_id)
        REFERENCES workflow_columns(id, workflow_id) ON DELETE RESTRICT,
    CONSTRAINT kanban_cards_workflow_category_fk
        FOREIGN KEY (workflow_id, category_id)
        REFERENCES workflow_categories(workflow_id, category_id) ON DELETE RESTRICT
);

CREATE INDEX ix_kanban_cards_column_page
    ON kanban_cards (workflow_id, column_id, updated_at DESC, id)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_kanban_cards_category
    ON kanban_cards (category_id, updated_at DESC)
    WHERE deleted_at IS NULL;
