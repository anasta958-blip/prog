SET search_path TO __TENANT_SCHEMA__, public;

ALTER TABLE catalog_category_dependencies
    ADD COLUMN client_id varchar(100);

WITH configured_dependencies AS (
    SELECT dependency.value ->> 'clientId' AS client_id,
           dependency.ordinality - 1 AS sort_order
    FROM onboarding_draft AS draft
    CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(draft.payload -> 'dependencies', '[]'::jsonb)
    ) WITH ORDINALITY AS dependency(value, ordinality)
    WHERE draft.singleton
)
UPDATE catalog_category_dependencies AS materialized
SET client_id = configured.client_id
FROM configured_dependencies AS configured
WHERE materialized.sort_order = configured.sort_order
  AND configured.client_id IS NOT NULL;

UPDATE catalog_category_dependencies
SET client_id = id::text
WHERE client_id IS NULL;

ALTER TABLE catalog_category_dependencies
    ALTER COLUMN client_id SET NOT NULL,
    ADD CONSTRAINT catalog_category_dependencies_client_id_key UNIQUE (client_id);
