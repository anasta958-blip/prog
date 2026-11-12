SET search_path TO __TENANT_SCHEMA__, public;

-- Catalog item updates and deletes must find referencing document positions.
-- PostgreSQL does not automatically index the referencing side of a foreign key.
CREATE INDEX IF NOT EXISTS ix_quote_positions_catalog_item
    ON quote_positions (catalog_item_id)
    WHERE catalog_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_order_positions_catalog_item
    ON order_positions (catalog_item_id)
    WHERE catalog_item_id IS NOT NULL;
