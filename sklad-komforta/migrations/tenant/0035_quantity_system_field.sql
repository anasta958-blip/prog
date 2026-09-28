SET search_path TO __TENANT_SCHEMA__, public;

-- «Количество» становится системным полем категории, как наименование,
-- маркировка, единица и цена. Оно добавляется во все категории каталога и в
-- колонки КП/ПКП-канбанов, где его ещё нет. Поле необязательное, чтобы
-- карточки каталога не требовали количества. Конфигурация хранится дважды:
-- в таблицах и в JSON-черновике, из которого таблицы пересобираются при
-- сохранении настроек, поэтому обновляются оба представления.

-- 1. Поля категорий каталога: отсутствующее поле добавляется в конец.
-- Подпись уникальна в категории: если пользователь уже завёл своё поле
-- «Количество», системное получает отличающуюся подпись.
INSERT INTO catalog_category_fields
    (category_id, field_code, is_visible, is_required, sort_order, label, field_type)
SELECT category.id, 'quantity', true, false,
       COALESCE((
           SELECT MAX(existing.sort_order) + 1
           FROM catalog_category_fields AS existing
           WHERE existing.category_id = category.id
       ), 0),
       CASE
           WHEN EXISTS (
               SELECT 1
               FROM catalog_category_fields AS existing
               WHERE existing.category_id = category.id
                 AND existing.label = 'Количество')
           THEN 'Количество (системное)'
           ELSE 'Количество'
       END,
       'number'
FROM catalog_categories AS category
WHERE NOT EXISTS (
    SELECT 1
    FROM catalog_category_fields AS existing
    WHERE existing.category_id = category.id
      AND existing.field_code = 'quantity'
);

-- 2. Колонки КП/ПКП: поле вставляется сразу после маркировки (или наименования).
CREATE TEMP TABLE quantity_workflow_targets ON COMMIT DROP AS
SELECT link.workflow_id,
       link.category_id,
       COALESCE(
           (SELECT field.sort_order FROM workflow_category_fields AS field
             WHERE field.workflow_id = link.workflow_id
               AND field.category_id = link.category_id
               AND field.field_code = 'marking'),
           (SELECT field.sort_order FROM workflow_category_fields AS field
             WHERE field.workflow_id = link.workflow_id
               AND field.category_id = link.category_id
               AND field.field_code = 'name'),
           (SELECT MAX(field.sort_order) FROM workflow_category_fields AS field
             WHERE field.workflow_id = link.workflow_id
               AND field.category_id = link.category_id),
           -1) AS anchor
FROM workflow_categories AS link
JOIN workflows AS workflow ON workflow.id = link.workflow_id
WHERE workflow.specialization IN ('quote', 'quote_and_prequote')
  AND NOT EXISTS (
      SELECT 1
      FROM workflow_category_fields AS field
      WHERE field.workflow_id = link.workflow_id
        AND field.category_id = link.category_id
        AND field.field_code = 'quantity'
  );

-- Сдвиг в два шага не нарушает UNIQUE (workflow_id, category_id, sort_order).
UPDATE workflow_category_fields AS field
SET sort_order = field.sort_order + 100000
FROM quantity_workflow_targets AS target
WHERE field.workflow_id = target.workflow_id
  AND field.category_id = target.category_id
  AND field.sort_order > target.anchor;

UPDATE workflow_category_fields AS field
SET sort_order = field.sort_order - 99999
FROM quantity_workflow_targets AS target
WHERE field.workflow_id = target.workflow_id
  AND field.category_id = target.category_id
  AND field.sort_order >= 100000;

INSERT INTO workflow_category_fields (workflow_id, category_id, field_code, sort_order)
SELECT workflow_id, category_id, 'quantity', anchor + 1
FROM quantity_workflow_targets;

DROP TABLE quantity_workflow_targets;

-- 3. Тот же результат в JSON-черновике конфигурации.
UPDATE onboarding_draft
SET payload = jsonb_set(
    jsonb_set(
        payload,
        '{categories}',
        COALESCE((
            SELECT jsonb_agg(
                CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM jsonb_array_elements(COALESCE(category -> 'fields', '[]'::jsonb)) AS field
                        WHERE field ->> 'fieldCode' = 'quantity')
                    THEN category
                    ELSE jsonb_set(
                        category,
                        '{fields}',
                        COALESCE(category -> 'fields', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                            'fieldCode', 'quantity',
                            'isVisible', true,
                            'isRequired', false,
                            'label', NULL,
                            'fieldType', NULL,
                            'dictionaryCode', NULL)))
                END
                ORDER BY category_order)
            FROM jsonb_array_elements(payload -> 'categories')
                 WITH ORDINALITY AS categories(category, category_order)
        ), '[]'::jsonb)),
    '{workflows}',
    COALESCE((
        SELECT jsonb_agg(
            CASE
                WHEN workflow ->> 'specialization' IN ('quote', 'quote_and_prequote')
                THEN jsonb_set(
                    workflow,
                    '{categories}',
                    COALESCE((
                        SELECT jsonb_agg(
                            CASE
                                WHEN COALESCE(link -> 'fieldCodes', '[]'::jsonb) ? 'quantity' THEN link
                                ELSE jsonb_set(link, '{fieldCodes}', (
                                    SELECT jsonb_agg(code ORDER BY position)
                                    FROM (
                                        SELECT code, code_order::numeric AS position
                                        FROM jsonb_array_elements_text(COALESCE(link -> 'fieldCodes', '[]'::jsonb))
                                             WITH ORDINALITY AS codes(code, code_order)
                                        UNION ALL
                                        SELECT 'quantity', COALESCE(
                                            (SELECT code_order FROM jsonb_array_elements_text(COALESCE(link -> 'fieldCodes', '[]'::jsonb))
                                                  WITH ORDINALITY AS codes(code, code_order) WHERE code = 'marking'),
                                            (SELECT code_order FROM jsonb_array_elements_text(COALESCE(link -> 'fieldCodes', '[]'::jsonb))
                                                  WITH ORDINALITY AS codes(code, code_order) WHERE code = 'name'),
                                            jsonb_array_length(COALESCE(link -> 'fieldCodes', '[]'::jsonb)))::numeric + 0.5
                                    ) AS ordered))
                            END
                            ORDER BY link_order)
                        FROM jsonb_array_elements(COALESCE(workflow -> 'categories', '[]'::jsonb))
                             WITH ORDINALITY AS links(link, link_order)
                    ), '[]'::jsonb))
                ELSE workflow
            END
            ORDER BY workflow_order)
        FROM jsonb_array_elements(payload -> 'workflows')
             WITH ORDINALITY AS workflows(workflow, workflow_order)
    ), '[]'::jsonb))
WHERE jsonb_typeof(payload -> 'categories') = 'array'
  AND jsonb_typeof(payload -> 'workflows') = 'array';
