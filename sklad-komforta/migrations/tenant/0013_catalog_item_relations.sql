SET search_path TO __TENANT_SCHEMA__, public;

-- Экземпляры межкатегорийных зависимостей. Конфигурация определяет, какие
-- категории совместимы, а эта таблица хранит выбранные карточки по UUID.
CREATE TABLE catalog_item_relations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    dependency_id uuid NOT NULL
        REFERENCES catalog_category_dependencies(id) ON DELETE CASCADE,
    target_item_id uuid NOT NULL
        REFERENCES catalog_items(id) ON DELETE CASCADE,
    source_item_id uuid NOT NULL
        REFERENCES catalog_items(id) ON DELETE CASCADE,
    sort_order integer NOT NULL CHECK (sort_order >= 0),
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (target_item_id <> source_item_id),
    UNIQUE (dependency_id, target_item_id, source_item_id),
    UNIQUE (target_item_id, sort_order)
);

CREATE INDEX ix_catalog_item_relations_target
    ON catalog_item_relations (target_item_id, sort_order);

CREATE INDEX ix_catalog_item_relations_source
    ON catalog_item_relations (source_item_id);
