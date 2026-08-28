SET search_path TO __TENANT_SCHEMA__, public;

-- Отображаемое название настраивается организацией, а технический тип и
-- бизнес-логика по-прежнему определяются доверенным системным кодом поля.
ALTER TABLE catalog_category_fields
    ADD COLUMN label varchar(120) NULL;

UPDATE catalog_category_fields
SET label = CASE field_code
    WHEN 'group' THEN 'Группа'
    WHEN 'name' THEN 'Наименование'
    WHEN 'marking' THEN 'Маркировка / размер'
    WHEN 'note' THEN 'Примечание'
    WHEN 'completion' THEN 'Комплектация'
    WHEN 'quantity' THEN 'Количество'
    WHEN 'unit' THEN 'Единица измерения'
    WHEN 'supplier' THEN 'Поставщик'
    WHEN 'purchase_price' THEN 'Закупочная цена'
    WHEN 'minimal_price' THEN 'Минимальная цена'
    WHEN 'price_type' THEN 'Тип цены'
    WHEN 'markup_value' THEN 'Наценка'
    WHEN 'base_price' THEN 'Цена'
    WHEN 'discount_value' THEN 'Скидка'
    WHEN 'line_total' THEN 'Сумма'
    WHEN 'excluded_from_calc' THEN 'Не считать'
    WHEN 'technical_note' THEN 'Техническая информация'
    WHEN 'linked_services' THEN 'Связанные позиции'
    WHEN 'invoice_check' THEN 'Проверка счёта'
    WHEN 'shipment_status' THEN 'Статус отгрузки'
    ELSE field_code
END;

ALTER TABLE catalog_category_fields
    ALTER COLUMN label SET NOT NULL,
    ADD CONSTRAINT catalog_category_fields_label_not_blank
        CHECK (btrim(label) <> ''),
    ADD CONSTRAINT catalog_category_fields_category_label_unique
        UNIQUE (category_id, label);
