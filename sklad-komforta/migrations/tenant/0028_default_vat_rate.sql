SET search_path TO __TENANT_SCHEMA__, public;

-- Актуальная стандартная ставка организации используется только как значение
-- по умолчанию для новых вариантов КП/ПКП. NULL означает «Без НДС».
ALTER TABLE organization_profile
    ADD COLUMN default_vat_rate numeric(5, 2) NULL DEFAULT 20.00,
    ADD CONSTRAINT organization_profile_default_vat_rate_check
        CHECK (default_vat_rate IS NULL OR default_vat_rate BETWEEN 0 AND 100);

