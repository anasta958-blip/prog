SET search_path TO __TENANT_SCHEMA__, public;

-- Дополняет ранее созданные категории четырьмя системными полями. Настроенные
-- пользователем поля и их порядок не меняются; отсутствующие поля добавляются
-- в конец текущего списка.
WITH fixed_fields(field_code, is_required, field_order) AS (
    VALUES
        ('name', true, 1),
        ('marking', false, 2),
        ('unit', false, 3),
        ('base_price', false, 4)
),
missing_fields AS (
    SELECT
        category.id AS category_id,
        fixed.field_code,
        fixed.is_required,
        fixed.field_order,
        COALESCE((
            SELECT MAX(existing.sort_order)
            FROM catalog_category_fields AS existing
            WHERE existing.category_id = category.id
        ), -1) AS current_max_order
    FROM catalog_categories AS category
    CROSS JOIN fixed_fields AS fixed
    WHERE NOT EXISTS (
        SELECT 1
        FROM catalog_category_fields AS existing
        WHERE existing.category_id = category.id
          AND existing.field_code = fixed.field_code
    )
),
positioned_fields AS (
    SELECT
        category_id,
        field_code,
        is_required,
        (current_max_order + ROW_NUMBER() OVER (
            PARTITION BY category_id
            ORDER BY field_order
        ))::integer AS sort_order
    FROM missing_fields
)
INSERT INTO catalog_category_fields
    (category_id, field_code, is_visible, is_required, sort_order)
SELECT category_id, field_code, true, is_required, sort_order
FROM positioned_fields;
