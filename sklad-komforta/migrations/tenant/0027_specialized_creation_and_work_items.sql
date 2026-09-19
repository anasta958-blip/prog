SET search_path TO __TENANT_SCHEMA__, public;

-- Универсальным карточкам категория по-прежнему требуется на уровне API.
-- Специализированная карточка КП/ПКП является контейнером документа, категории
-- которого хранятся отдельно в quote_variant_categories, поэтому здесь NULL.
ALTER TABLE kanban_cards
    ALTER COLUMN category_id DROP NOT NULL;

-- Общая рабочая сущность объединяет проекции одного объекта в разных канбанах.
-- Данные КП и комплектации остаются в собственных таблицах: перенос создаёт новую
-- проекцию с тем же work_item_id, поэтому неподдерживаемые поля не теряются.
CREATE TABLE work_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    archived_at timestamptz NULL
);

ALTER TABLE kanban_cards
    ADD COLUMN work_item_id uuid NULL REFERENCES work_items(id) ON DELETE RESTRICT;

INSERT INTO work_items (id, created_by, created_at)
SELECT card.id, card.created_by, card.created_at
FROM kanban_cards AS card
ON CONFLICT (id) DO NOTHING;

UPDATE kanban_cards
SET work_item_id = id
WHERE work_item_id IS NULL;

ALTER TABLE kanban_cards
    ALTER COLUMN work_item_id SET NOT NULL;

CREATE INDEX ix_kanban_cards_work_item
    ON kanban_cards (work_item_id, workflow_id)
    WHERE deleted_at IS NULL;

-- Действие создания назначается конкретному столбцу. Ограничение workflow_id +
-- action_kind гарантирует, что кнопка каждого типа находится только в одном столбце.
CREATE TABLE workflow_column_creation_actions (
    workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    column_id uuid NOT NULL,
    action_kind varchar(20) NOT NULL CHECK (action_kind IN ('quote', 'prequote', 'order')),
    PRIMARY KEY (column_id, action_kind),
    UNIQUE (workflow_id, action_kind),
    CONSTRAINT workflow_column_creation_actions_column_fk
        FOREIGN KEY (column_id, workflow_id)
        REFERENCES workflow_columns(id, workflow_id) ON DELETE CASCADE
);

-- Сохраняем работоспособность специализированных канбанов, созданных до появления
-- настройки кнопок. Для каждого действия выбирается первый столбец канбана.
-- Новые и изменённые настройки записываются приложением явно и этим блоком не
-- перетираются, поскольку миграция выполняется один раз.
WITH first_columns AS (
    SELECT DISTINCT ON (column_item.workflow_id)
        column_item.workflow_id,
        column_item.id AS column_id
    FROM workflow_columns AS column_item
    ORDER BY column_item.workflow_id, column_item.sort_order, column_item.id
), default_actions AS (
    SELECT workflow.id AS workflow_id, first_columns.column_id, 'quote'::varchar(20) AS action_kind
    FROM workflows AS workflow
    JOIN first_columns ON first_columns.workflow_id = workflow.id
    WHERE workflow.specialization IN ('quote', 'quote_and_prequote')

    UNION ALL

    SELECT workflow.id, first_columns.column_id, 'prequote'::varchar(20)
    FROM workflows AS workflow
    JOIN first_columns ON first_columns.workflow_id = workflow.id
    WHERE workflow.specialization = 'quote_and_prequote'

    UNION ALL

    SELECT workflow.id, first_columns.column_id, 'order'::varchar(20)
    FROM workflows AS workflow
    JOIN first_columns ON first_columns.workflow_id = workflow.id
    WHERE workflow.specialization = 'order'
)
INSERT INTO workflow_column_creation_actions (workflow_id, column_id, action_kind)
SELECT workflow_id, column_id, action_kind
FROM default_actions
ON CONFLICT DO NOTHING;
