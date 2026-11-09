SET search_path TO __TENANT_SCHEMA__, public;

-- Существующие комплектации остаются с сохранёнными значениями до подтверждения.
ALTER TABLE orders ADD COLUMN calculation_version varchar(64) NULL;
