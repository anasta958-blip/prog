SET search_path TO __TENANT_SCHEMA__, public;

-- Ставка НДС относится к конкретному юридическому лицу-исполнителю.
ALTER TABLE companies
    ADD COLUMN default_vat_rate numeric(5, 2) NULL;

-- Сохраняем ранее настроенное общее значение при переходе на новую модель.
UPDATE companies AS company
SET default_vat_rate = profile.default_vat_rate
FROM organization_profile AS profile
WHERE profile.singleton;

ALTER TABLE companies
    ALTER COLUMN default_vat_rate SET DEFAULT 20.00,
    ADD CONSTRAINT companies_default_vat_rate_check
        CHECK (default_vat_rate IS NULL OR default_vat_rate BETWEEN 0 AND 100);
