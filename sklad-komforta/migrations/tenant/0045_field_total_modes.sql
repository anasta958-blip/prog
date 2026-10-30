SET search_path TO __TENANT_SCHEMA__, public;

-- NULL preserves old calculation settings until the category is configured.
-- Explicit 'none' differs from NULL: a category with all fields set to 'none'
-- has zero total, not the old implicit price calculation.
ALTER TABLE catalog_category_fields ADD COLUMN total_mode text
    CHECK (total_mode IS NULL OR total_mode IN ('none', 'total', 'separate'));
