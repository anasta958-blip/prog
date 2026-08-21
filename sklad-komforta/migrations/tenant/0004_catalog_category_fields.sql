SET search_path TO __TENANT_SCHEMA__, public;

-- Категория хранит только выбранные из системного реестра поля и их порядок.
-- Метаданные поля (название, тип и расчётная логика) остаются частью приложения,
-- поэтому tenant не может создать поле без поддерживающей его бизнес-логики.
CREATE TABLE catalog_category_fields (
    category_id uuid NOT NULL REFERENCES catalog_categories(id) ON DELETE CASCADE,
    field_code varchar(80) NOT NULL,
    is_visible boolean NOT NULL DEFAULT true,
    is_required boolean NOT NULL DEFAULT false,
    sort_order integer NOT NULL,
    PRIMARY KEY (category_id, field_code),
    UNIQUE (category_id, sort_order),
    CHECK (NOT is_required OR is_visible)
);
