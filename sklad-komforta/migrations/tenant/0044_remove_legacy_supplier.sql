SET search_path TO __TENANT_SCHEMA__, public;

-- Remove only the retired system code. Custom supplier fields and dictionaries
-- are independent user data and must remain intact. Audit history is immutable.
CREATE OR REPLACE FUNCTION pg_temp.references_legacy_supplier(node jsonb, removed_dependencies jsonb)
RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE entry record; child jsonb;
BEGIN
    IF jsonb_typeof(node) = 'object' THEN
        FOR entry IN SELECT * FROM jsonb_each(node) LOOP
            IF entry.key IN ('fieldCode', 'eventFieldCode', 'targetFieldCode',
                'sourceFieldCode', 'basePriceFieldCode', 'manualPriceFieldCode',
                'markupFieldCode', 'discountFieldCode', 'quantityFieldCode', 'resultFieldCode')
                AND entry.value = '"supplier"'::jsonb THEN RETURN true; END IF;
            IF entry.key = 'dependencyClientId' AND removed_dependencies ? (entry.value #>> '{}')
                THEN RETURN true; END IF;
            IF pg_temp.references_legacy_supplier(entry.value, removed_dependencies)
                THEN RETURN true; END IF;
        END LOOP;
    ELSIF jsonb_typeof(node) = 'array' THEN
        FOR child IN SELECT value FROM jsonb_array_elements(node) LOOP
            IF pg_temp.references_legacy_supplier(child, removed_dependencies)
                THEN RETURN true; END IF;
        END LOOP;
    END IF;
    RETURN false;
END $fn$;

CREATE OR REPLACE FUNCTION pg_temp.remove_legacy_supplier_settings(node jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE result jsonb; entry record; child jsonb; cleaned jsonb;
BEGIN
    IF jsonb_typeof(node) = 'object' THEN
        IF node ->> 'fieldCode' = 'supplier' THEN RETURN NULL; END IF;
        result := '{}'::jsonb;
        FOR entry IN SELECT * FROM jsonb_each(node) LOOP
            IF entry.key = 'supplierFilterFieldCode' AND entry.value = '"supplier"'::jsonb
                THEN CONTINUE; END IF;
            IF entry.key = 'fieldCodes' AND jsonb_typeof(entry.value) = 'array' THEN
                SELECT COALESCE(jsonb_agg(value ORDER BY ord), '[]'::jsonb) INTO cleaned
                FROM jsonb_array_elements(entry.value) WITH ORDINALITY AS codes(value, ord)
                WHERE value <> '"supplier"'::jsonb;
            ELSE
                cleaned := pg_temp.remove_legacy_supplier_settings(entry.value);
            END IF;
            IF cleaned IS NOT NULL THEN result := result || jsonb_build_object(entry.key, cleaned); END IF;
        END LOOP;
        RETURN result;
    ELSIF jsonb_typeof(node) = 'array' THEN
        result := '[]'::jsonb;
        FOR child IN SELECT value FROM jsonb_array_elements(node) LOOP
            cleaned := pg_temp.remove_legacy_supplier_settings(child);
            IF cleaned IS NOT NULL THEN result := result || jsonb_build_array(cleaned); END IF;
        END LOOP;
        RETURN result;
    END IF;
    RETURN node;
END $fn$;

DO $remove_legacy_supplier$
DECLARE draft record; v_payload jsonb; removed_dependencies jsonb; array_key text; cleaned jsonb;
BEGIN
    FOR draft IN SELECT singleton, onboarding_draft.payload FROM onboarding_draft LOOP
        v_payload := draft.payload;
        SELECT COALESCE(jsonb_agg(value ->> 'clientId'), '[]'::jsonb) INTO removed_dependencies
        FROM jsonb_array_elements(COALESCE(NULLIF(v_payload -> 'dependencies', 'null'::jsonb), '[]'::jsonb))
        WHERE value ->> 'targetFieldCode' = 'supplier';
        -- Remove the whole affected rule/pipeline, never weaken a rule by dropping
        -- only its supplier condition and leaving its actions unconditional.
        FOREACH array_key IN ARRAY ARRAY['dependencies', 'rules', 'moneyPipelines'] LOOP
            IF jsonb_typeof(v_payload -> array_key) = 'array' THEN
                SELECT COALESCE(jsonb_agg(value ORDER BY ord), '[]'::jsonb) INTO cleaned
                FROM jsonb_array_elements(v_payload -> array_key) WITH ORDINALITY AS items(value, ord)
                WHERE NOT pg_temp.references_legacy_supplier(value, removed_dependencies);
                v_payload := jsonb_set(v_payload, ARRAY[array_key], cleaned);
            END IF;
        END LOOP;
        UPDATE onboarding_draft SET payload = pg_temp.remove_legacy_supplier_settings(v_payload)
        WHERE singleton = draft.singleton;
    END LOOP;
END $remove_legacy_supplier$;

UPDATE workflow_categories SET supplier_filter_field_code = NULL
WHERE supplier_filter_field_code = 'supplier';
DELETE FROM workflow_category_fields WHERE field_code = 'supplier';
DELETE FROM catalog_category_dependencies WHERE target_field_code = 'supplier';
DELETE FROM catalog_category_fields WHERE field_code = 'supplier';
DELETE FROM entity_field_definitions WHERE field_code = 'supplier';

UPDATE catalog_items SET values = values - 'supplier' WHERE values ? 'supplier';
UPDATE kanban_cards SET values = values - 'supplier' WHERE values ? 'supplier';
UPDATE quote_positions SET values = values - 'supplier' WHERE values ? 'supplier';
UPDATE order_positions SET values = values - 'supplier' WHERE values ? 'supplier';

DROP FUNCTION pg_temp.remove_legacy_supplier_settings(jsonb);
DROP FUNCTION pg_temp.references_legacy_supplier(jsonb, jsonb);
