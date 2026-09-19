SET search_path TO __TENANT_SCHEMA__, public;

ALTER TABLE catalog_categories
    ADD COLUMN client_id varchar(100);

WITH configured_categories AS (
    SELECT category.value ->> 'clientId' AS client_id,
           category.ordinality - 1 AS sort_order
    FROM onboarding_draft AS draft
    CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(draft.payload -> 'categories', '[]'::jsonb)
    ) WITH ORDINALITY AS category(value, ordinality)
    WHERE draft.singleton
)
UPDATE catalog_categories AS materialized
SET client_id = configured.client_id
FROM configured_categories AS configured
WHERE materialized.sort_order = configured.sort_order
  AND configured.client_id IS NOT NULL;

UPDATE catalog_categories
SET client_id = id::text
WHERE client_id IS NULL;

ALTER TABLE catalog_categories
    ALTER COLUMN client_id SET NOT NULL,
    ADD CONSTRAINT catalog_categories_client_id_key UNIQUE (client_id);
