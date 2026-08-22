SET search_path TO __TENANT_SCHEMA__, public;

-- Составные ограничения позволяют базе проверить принадлежность раздела
-- категории и группы разделу без доверия идентификаторам из HTTP-запроса.
ALTER TABLE catalog_sections
    ADD CONSTRAINT catalog_sections_id_category_unique UNIQUE (id, category_id);

ALTER TABLE catalog_groups
    ADD CONSTRAINT catalog_groups_id_section_unique UNIQUE (id, section_id);

CREATE TABLE catalog_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id uuid NOT NULL REFERENCES catalog_categories(id),
    section_id uuid NULL,
    group_id uuid NULL,
    name text NOT NULL CHECK (btrim(name) <> ''),
    marking text NOT NULL DEFAULT '',
    normalized_name text GENERATED ALWAYS AS
        (lower(regexp_replace(btrim(name), '\s+', ' ', 'g'))) STORED,
    normalized_marking text GENERATED ALWAYS AS
        (lower(regexp_replace(btrim(marking), '\s+', ' ', 'g'))) STORED,
    status varchar(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved')),
    values jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(values) = 'object'),
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    deleted_at timestamptz NULL,
    delete_reason text NULL,
    CHECK (group_id IS NULL OR section_id IS NOT NULL),
    FOREIGN KEY (section_id, category_id)
        REFERENCES catalog_sections(id, category_id),
    FOREIGN KEY (group_id, section_id)
        REFERENCES catalog_groups(id, section_id)
);

-- Уникальность следует бизнес-правилу: группа + название + маркировка.
-- Пустая группа образует один общий диапазон уникальности tenant-каталога.
CREATE UNIQUE INDEX ux_catalog_items_identity
    ON catalog_items (
        COALESCE(group_id::text, ''),
        normalized_name,
        normalized_marking
    )
    WHERE deleted_at IS NULL;

CREATE INDEX ix_catalog_items_category_updated
    ON catalog_items (category_id, updated_at DESC, id)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_catalog_items_section_updated
    ON catalog_items (section_id, updated_at DESC, id)
    WHERE deleted_at IS NULL;

CREATE INDEX ix_catalog_items_status_updated
    ON catalog_items (status, updated_at DESC, id)
    WHERE deleted_at IS NULL;

INSERT INTO permissions (code, name, group_name)
VALUES
    ('catalog.view', 'Просмотр каталога', 'Каталог'),
    ('catalog.manage', 'Управление каталогом', 'Каталог')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;
