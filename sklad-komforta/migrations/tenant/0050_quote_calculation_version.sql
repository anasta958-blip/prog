SET search_path TO __TENANT_SCHEMA__, public;

-- NULL у существующих КП/ПКП означает, что версия расчётных правил неизвестна.
-- Их сохранённые суммы остаются без изменений до явного пересчёта пользователем.
ALTER TABLE quotes ADD COLUMN calculation_version varchar(64) NULL;
