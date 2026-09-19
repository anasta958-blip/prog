SET search_path TO __TENANT_SCHEMA__, public;

-- После переноса ставки к юридическим лицам общий источник больше не используется.
ALTER TABLE organization_profile
    DROP CONSTRAINT IF EXISTS organization_profile_default_vat_rate_check,
    DROP COLUMN IF EXISTS default_vat_rate;
