SET search_path TO __TENANT_SCHEMA__, public;

-- Универсальный канбан становится специализированным только после явного выбора.
-- NULL сохраняет прежнее поведение стандартного канбана.
ALTER TABLE workflows
    ADD COLUMN specialization varchar(30) NULL
        CHECK (specialization IN ('quote', 'quote_and_prequote', 'order'));

ALTER TABLE kanban_cards
    ADD CONSTRAINT kanban_cards_id_workflow_unique UNIQUE (id, workflow_id);

-- КП и ПКП используют одну сущность и различаются видом предложения. Карточка
-- остаётся источником статуса и положения в канбане, а эта таблица хранит только
-- специализированные данные предложения.
CREATE TABLE quotes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id uuid NOT NULL REFERENCES workflows(id) ON DELETE RESTRICT,
    card_id uuid NOT NULL,
    quote_kind varchar(20) NOT NULL CHECK (quote_kind IN ('quote', 'prequote')),
    title text NOT NULL CHECK (btrim(title) <> ''),
    client_id uuid NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
    executor_company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    manager_user_id uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    sales_head_user_id uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    selection_mode varchar(20) NOT NULL DEFAULT 'variant'
        CHECK (selection_mode IN ('variant', 'proposal_type')),
    additional_information text NULL,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    deleted_at timestamptz NULL,
    CONSTRAINT quotes_card_workflow_fk
        FOREIGN KEY (card_id, workflow_id)
        REFERENCES kanban_cards(id, workflow_id) ON DELETE CASCADE,
    UNIQUE (card_id)
);

CREATE TABLE quote_proposal_types (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_id uuid NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
    name text NOT NULL CHECK (btrim(name) <> ''),
    sort_order integer NOT NULL,
    UNIQUE (quote_id, sort_order)
);

CREATE TABLE quote_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_type_id uuid NOT NULL REFERENCES quote_proposal_types(id) ON DELETE CASCADE,
    name text NOT NULL CHECK (btrim(name) <> ''),
    subtitle text NULL,
    vat_rate numeric(5,2) NULL CHECK (vat_rate IS NULL OR vat_rate BETWEEN 0 AND 100),
    sort_order integer NOT NULL,
    UNIQUE (proposal_type_id, sort_order),
    UNIQUE (id, proposal_type_id)
);

-- Для каждого типа предложения может быть выбран максимум один его вариант.
CREATE TABLE quote_proposal_type_selections (
    proposal_type_id uuid PRIMARY KEY REFERENCES quote_proposal_types(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL,
    selected_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    selected_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT quote_selection_variant_type_fk
        FOREIGN KEY (variant_id, proposal_type_id)
        REFERENCES quote_variants(id, proposal_type_id) ON DELETE CASCADE
);

CREATE TABLE quote_variant_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id uuid NOT NULL REFERENCES quote_variants(id) ON DELETE CASCADE,
    catalog_category_id uuid NULL REFERENCES catalog_categories(id) ON DELETE SET NULL,
    name_snapshot text NOT NULL CHECK (btrim(name_snapshot) <> ''),
    sort_order integer NOT NULL,
    UNIQUE (variant_id, sort_order)
);

CREATE TABLE quote_variant_sections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_category_id uuid NOT NULL REFERENCES quote_variant_categories(id) ON DELETE CASCADE,
    catalog_section_id uuid NULL REFERENCES catalog_sections(id) ON DELETE SET NULL,
    name_snapshot text NOT NULL CHECK (btrim(name_snapshot) <> ''),
    markup_percent numeric(9,4) NULL,
    discount_percent numeric(9,4) NULL,
    sort_order integer NOT NULL,
    UNIQUE (variant_category_id, sort_order)
);

-- Основные вычисляемые значения вынесены в типизированные столбцы. Остальные
-- настраиваемые поля организации сохраняются в values без потери расширяемости.
CREATE TABLE quote_positions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_section_id uuid NOT NULL REFERENCES quote_variant_sections(id) ON DELETE CASCADE,
    catalog_item_id uuid NULL REFERENCES catalog_items(id) ON DELETE SET NULL,
    name_snapshot text NOT NULL CHECK (btrim(name_snapshot) <> ''),
    marking_snapshot text NOT NULL DEFAULT '',
    unit_snapshot text NOT NULL DEFAULT '',
    quantity numeric(18,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    purchase_price numeric(18,2) NULL CHECK (purchase_price IS NULL OR purchase_price >= 0),
    base_price numeric(18,2) NOT NULL CHECK (base_price >= 0),
    manual_price numeric(18,2) NULL CHECK (manual_price IS NULL OR manual_price >= 0),
    markup_percent numeric(9,4) NULL,
    discount_percent numeric(9,4) NULL,
    line_total numeric(18,2) NOT NULL DEFAULT 0,
    exclude_from_totals boolean NOT NULL DEFAULT false,
    values jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(values) = 'object'),
    sort_order integer NOT NULL,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (variant_section_id, sort_order)
);

-- Предложение нельзя случайно записать в стандартный канбан или в комплектацию.
-- Проверка находится в базе, поэтому действует для любого будущего API-клиента.
CREATE FUNCTION ensure_quote_workflow_specialization()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    workflow_specialization varchar(30);
BEGIN
    SELECT specialization
      INTO workflow_specialization
      FROM workflows
     WHERE id = NEW.workflow_id;

    IF NEW.quote_kind = 'quote'
       AND workflow_specialization IS DISTINCT FROM 'quote'
       AND workflow_specialization IS DISTINCT FROM 'quote_and_prequote' THEN
        RAISE EXCEPTION 'КП можно создать только в канбане типа КП или КП+ПКП.'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.quote_kind = 'prequote'
       AND workflow_specialization IS DISTINCT FROM 'quote_and_prequote' THEN
        RAISE EXCEPTION 'ПКП можно создать только в канбане типа КП+ПКП.'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_quotes_workflow_specialization
BEFORE INSERT OR UPDATE OF workflow_id, quote_kind ON quotes
FOR EACH ROW
EXECUTE FUNCTION ensure_quote_workflow_specialization();

-- Специализацию используемого канбана можно менять только тогда, когда все
-- уже созданные предложения остаются допустимыми для нового типа.
CREATE FUNCTION ensure_workflow_specialization_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.specialization IS NOT DISTINCT FROM OLD.specialization THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM quotes
         WHERE workflow_id = NEW.id
           AND deleted_at IS NULL
           AND (
               (quote_kind = 'quote'
                    AND NEW.specialization IS DISTINCT FROM 'quote'
                    AND NEW.specialization IS DISTINCT FROM 'quote_and_prequote')
               OR
               (quote_kind = 'prequote'
                    AND NEW.specialization IS DISTINCT FROM 'quote_and_prequote')
           )
    ) THEN
        RAISE EXCEPTION 'Тип канбана несовместим с созданными в нём КП или ПКП.'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_workflows_specialization_change
BEFORE UPDATE OF specialization ON workflows
FOR EACH ROW
EXECUTE FUNCTION ensure_workflow_specialization_change();

CREATE INDEX ix_workflows_specialization
    ON workflows (specialization)
    WHERE specialization IS NOT NULL;

CREATE INDEX ix_quotes_workflow_updated
    ON quotes (workflow_id, updated_at DESC, id)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_quotes_client_updated
    ON quotes (client_id, updated_at DESC, id)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_quote_types_quote
    ON quote_proposal_types (quote_id, sort_order);

CREATE INDEX ix_quote_variants_type
    ON quote_variants (proposal_type_id, sort_order);

CREATE INDEX ix_quote_positions_section
    ON quote_positions (variant_section_id, sort_order);
