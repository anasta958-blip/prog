SET search_path TO __TENANT_SCHEMA__, public;

ALTER TABLE catalog_category_fields
    DROP CONSTRAINT catalog_category_fields_total_mode_check;

ALTER TABLE catalog_category_fields
    ADD CONSTRAINT catalog_category_fields_total_mode_check
    CHECK (total_mode IS NULL OR total_mode IN ('none', 'total', 'separate', 'separate_only'));
