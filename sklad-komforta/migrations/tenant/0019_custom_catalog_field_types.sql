SET search_path TO __TENANT_SCHEMA__, public;

-- Тип хранится вместе с полем категории: это позволяет организации создавать
-- собственные поля с произвольным названием, не подменяя системные коды.
ALTER TABLE catalog_category_fields
    ADD COLUMN field_type varchar(32) NULL;

UPDATE catalog_category_fields
SET field_type = CASE field_code
    WHEN 'group' THEN 'dictionary'
    WHEN 'name' THEN 'text'
    WHEN 'marking' THEN 'text'
    WHEN 'note' THEN 'text'
    WHEN 'completion' THEN 'text'
    WHEN 'quantity' THEN 'number'
    WHEN 'unit' THEN 'dictionary'
    WHEN 'supplier' THEN 'dictionary'
    WHEN 'purchase_price' THEN 'money'
    WHEN 'minimal_price' THEN 'money'
    WHEN 'price_type' THEN 'enum'
    WHEN 'markup_value' THEN 'percent'
    WHEN 'base_price' THEN 'money'
    WHEN 'discount_value' THEN 'percent'
    WHEN 'line_total' THEN 'calculated_money'
    WHEN 'excluded_from_calc' THEN 'boolean'
    WHEN 'technical_note' THEN 'text'
    WHEN 'linked_services' THEN 'relation'
    WHEN 'invoice_check' THEN 'enum'
    WHEN 'shipment_status' THEN 'enum'
    ELSE 'text'
END;

ALTER TABLE catalog_category_fields
    ALTER COLUMN field_type SET NOT NULL,
    ADD CONSTRAINT catalog_category_fields_type_supported
        CHECK (field_type IN (
            'text', 'number', 'money', 'percent', 'dictionary',
            'boolean', 'relation', 'enum', 'calculated_money'
        ));
