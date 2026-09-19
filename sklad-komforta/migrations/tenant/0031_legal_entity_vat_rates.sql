SET search_path TO __TENANT_SCHEMA__, public;

-- Юридическое лицо хранит единый список ставок, доступных в его КП и ПКП.
ALTER TABLE companies
    ADD COLUMN vat_rates jsonb NOT NULL DEFAULT '[20]'::jsonb;

UPDATE companies
SET vat_rates = CASE
    WHEN default_vat_rate IS NULL THEN '[null]'::jsonb
    ELSE jsonb_build_array(default_vat_rate)
END;

ALTER TABLE companies
    ADD CONSTRAINT companies_vat_rates_check
        CHECK (jsonb_typeof(vat_rates) = 'array' AND jsonb_array_length(vat_rates) BETWEEN 1 AND 20),
    DROP CONSTRAINT IF EXISTS companies_default_vat_rate_check,
    DROP COLUMN default_vat_rate;
