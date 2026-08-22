SET search_path TO __TENANT_SCHEMA__, public;

-- Явная связь заменяет клиентское угадывание справочника по имени поля.
ALTER TABLE catalog_category_fields
    ADD COLUMN dictionary_code varchar(80) NULL;

ALTER TABLE entity_field_definitions
    ADD COLUMN dictionary_code varchar(80) NULL;

ALTER TABLE catalog_category_fields
    ADD CONSTRAINT catalog_category_fields_dictionary_fk
    FOREIGN KEY (dictionary_code) REFERENCES dictionary_types(code)
    ON UPDATE CASCADE ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE entity_field_definitions
    ADD CONSTRAINT entity_field_definitions_dictionary_fk
    FOREIGN KEY (dictionary_code) REFERENCES dictionary_types(code)
    ON UPDATE CASCADE ON DELETE SET NULL
    DEFERRABLE INITIALLY DEFERRED;
