SET search_path TO __TENANT_SCHEMA__, public;

-- Метаданные изображений хранятся в tenant-схеме, а сами файлы остаются
-- закрытыми объектами S3/MinIO и доступны только по короткоживущим ссылкам.
CREATE TABLE catalog_item_images (
    id uuid PRIMARY KEY,
    catalog_item_id uuid NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
    object_key text NOT NULL UNIQUE CHECK (btrim(object_key) <> ''),
    file_name text NOT NULL CHECK (btrim(file_name) <> ''),
    content_type varchar(40) NOT NULL,
    byte_size bigint NOT NULL CHECK (byte_size > 0),
    sort_order integer NOT NULL DEFAULT 0,
    created_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    ready_at timestamptz NULL,
    deleted_at timestamptz NULL
);

CREATE INDEX ix_catalog_item_images_item_order
    ON catalog_item_images (catalog_item_id, sort_order, created_at)
    WHERE ready_at IS NOT NULL AND deleted_at IS NULL;
