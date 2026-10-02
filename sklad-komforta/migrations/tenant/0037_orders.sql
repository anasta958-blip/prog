SET search_path TO __TENANT_SCHEMA__, public;

-- Комплектация объекта: шапка, дерево категорий, разделов и позиций, PDF-счета,
-- а также настройки канбанов для переноса между КП и комплектацией.

INSERT INTO permissions (code, name, group_name)
VALUES
    ('orders.invoices.manage', 'Счета комплектаций', 'Комплектация'),
    ('orders.manager.change', 'Смена менеджера и РОП комплектации', 'Комплектация'),
    ('quotes.manager.change', 'Смена менеджера и РОП КП и ПКП', 'Коммерческие предложения')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;

-- Справочники канбана комплектации: типы объекта и статусы отгрузки.
CREATE TABLE workflow_order_options (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    option_kind varchar(30) NOT NULL CHECK (option_kind IN ('object_type', 'shipment_status')),
    value text NOT NULL CHECK (btrim(value) <> ''),
    sort_order integer NOT NULL,
    UNIQUE (workflow_id, option_kind, value)
);

-- Столбец, начиная с которого (он и все правее) новые позиции комплектации
-- считаются дозаказом. В канбане не более одного такого столбца.
ALTER TABLE workflow_columns
    ADD COLUMN reorder_from boolean NOT NULL DEFAULT false;

CREATE UNIQUE INDEX ux_workflow_columns_reorder_from
    ON workflow_columns (workflow_id)
    WHERE reorder_from;

-- Столбец-триггер: карточка, попавшая в него, переносится в другой канбан.
-- КП/ПКП → комплектация создаёт или обновляет комплектацию; комплектация → КП
-- только перемещает связанную карточку КП.
CREATE TABLE workflow_column_transfers (
    column_id uuid PRIMARY KEY REFERENCES workflow_columns(id) ON DELETE CASCADE,
    target_workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    target_column_id uuid NOT NULL,
    CONSTRAINT workflow_column_transfers_target_fk
        FOREIGN KEY (target_column_id, target_workflow_id)
        REFERENCES workflow_columns(id, workflow_id) ON DELETE CASCADE
);

-- Шапка комплектации. Название — адрес объекта (совпадает с названием карточки).
CREATE TABLE orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE RESTRICT,
    card_id uuid NOT NULL,
    title text NOT NULL CHECK (btrim(title) <> ''),
    object_type text NULL,
    client_id uuid NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
    executor_company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    manager_user_id uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    sales_head_user_id uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    source_quote_id uuid NULL REFERENCES quotes(id) ON DELETE SET NULL,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    deleted_at timestamptz NULL,
    CONSTRAINT orders_card_workflow_fk
        FOREIGN KEY (card_id, workflow_id)
        REFERENCES kanban_cards(id, workflow_id) ON DELETE CASCADE,
    UNIQUE (card_id)
);

CREATE INDEX ix_orders_source_quote ON orders (source_quote_id) WHERE source_quote_id IS NOT NULL;

CREATE TABLE order_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    catalog_category_id uuid NULL REFERENCES catalog_categories(id) ON DELETE SET NULL,
    name_snapshot text NOT NULL CHECK (btrim(name_snapshot) <> ''),
    sort_order integer NOT NULL,
    UNIQUE (order_id, sort_order)
);

CREATE UNIQUE INDEX ux_order_categories_catalog
    ON order_categories (order_id, catalog_category_id)
    WHERE catalog_category_id IS NOT NULL;

CREATE TABLE order_sections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_category_id uuid NOT NULL REFERENCES order_categories(id) ON DELETE CASCADE,
    catalog_section_id uuid NULL REFERENCES catalog_sections(id) ON DELETE SET NULL,
    name_snapshot text NOT NULL CHECK (btrim(name_snapshot) <> ''),
    sort_order integer NOT NULL,
    UNIQUE (order_category_id, sort_order)
);

-- В одной категории несколько разных разделов допустимы, дубликат — нет.
CREATE UNIQUE INDEX ux_order_sections_catalog
    ON order_sections (order_category_id, catalog_section_id)
    WHERE catalog_section_id IS NOT NULL;

-- Позиция комплектации. source_key — отпечаток строки, перенесённой из КП:
-- по нему повторный перенос обновляет количество, добавляет новые и удаляет
-- исчезнувшие строки, не трогая строки, добавленные в комплектации вручную.
CREATE TABLE order_positions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_section_id uuid NOT NULL REFERENCES order_sections(id) ON DELETE CASCADE,
    catalog_item_id uuid NULL REFERENCES catalog_items(id) ON DELETE SET NULL,
    name_snapshot text NOT NULL CHECK (btrim(name_snapshot) <> ''),
    marking_snapshot text NOT NULL DEFAULT '',
    unit_snapshot text NOT NULL DEFAULT '',
    quantity numeric(18,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    is_reorder boolean NOT NULL DEFAULT false,
    source_key text NULL,
    -- Количество в КП при последнем переносе: повторный перенос меняет
    -- количество в комплектации, только если оно изменилось в самом КП.
    source_quantity numeric(18,4) NULL,
    values jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(values) = 'object'),
    sort_order integer NOT NULL,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (order_section_id, sort_order)
);

CREATE INDEX ix_order_positions_section ON order_positions (order_section_id, sort_order);

-- PDF-счета: файл в закрытом хранилище, выдача только по короткой ссылке.
CREATE TABLE order_invoices (
    id uuid PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    object_key text NOT NULL UNIQUE CHECK (btrim(object_key) <> ''),
    file_name text NOT NULL CHECK (btrim(file_name) <> ''),
    content_type varchar(40) NOT NULL,
    byte_size bigint NOT NULL CHECK (byte_size > 0),
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    ready_at timestamptz NULL,
    deleted_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    deleted_at timestamptz NULL
);

CREATE INDEX ix_order_invoices_order
    ON order_invoices (order_id, created_at)
    WHERE ready_at IS NOT NULL AND deleted_at IS NULL;
