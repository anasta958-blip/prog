SET search_path TO __TENANT_SCHEMA__, public;

DELETE FROM workflow_category_fields
WHERE field_code = 'retail_price';

DELETE FROM entity_field_definitions
WHERE field_code = 'retail_price';

DELETE FROM catalog_category_fields
WHERE field_code = 'retail_price';
