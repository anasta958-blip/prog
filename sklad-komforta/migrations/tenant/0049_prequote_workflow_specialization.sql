SET search_path TO __TENANT_SCHEMA__, public;

ALTER TABLE workflows DROP CONSTRAINT workflows_specialization_check;
ALTER TABLE workflows ADD CONSTRAINT workflows_specialization_check
    CHECK (specialization IN ('quote', 'prequote', 'quote_and_prequote', 'order'));

CREATE OR REPLACE FUNCTION ensure_quote_workflow_specialization()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    workflow_specialization varchar(30);
BEGIN
    SELECT specialization INTO workflow_specialization
    FROM workflows WHERE id = NEW.workflow_id;

    IF NEW.quote_kind = 'quote'
       AND workflow_specialization IS DISTINCT FROM 'quote'
       AND workflow_specialization IS DISTINCT FROM 'quote_and_prequote' THEN
        RAISE EXCEPTION 'КП можно создать только в канбане типа КП или КП+ПКП.'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.quote_kind = 'prequote'
       AND workflow_specialization IS DISTINCT FROM 'prequote'
       AND workflow_specialization IS DISTINCT FROM 'quote_and_prequote' THEN
        RAISE EXCEPTION 'ПКП можно создать только в канбане типа ПКП или КП+ПКП.'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ensure_workflow_specialization_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.specialization IS NOT DISTINCT FROM OLD.specialization THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1 FROM quotes
        WHERE workflow_id = NEW.id
          AND deleted_at IS NULL
          AND (
              (quote_kind = 'quote'
                  AND NEW.specialization IS DISTINCT FROM 'quote'
                  AND NEW.specialization IS DISTINCT FROM 'quote_and_prequote')
              OR
              (quote_kind = 'prequote'
                  AND NEW.specialization IS DISTINCT FROM 'prequote'
                  AND NEW.specialization IS DISTINCT FROM 'quote_and_prequote')
          )
    ) THEN
        RAISE EXCEPTION 'Тип канбана несовместим с созданными в нём КП или ПКП.'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;
