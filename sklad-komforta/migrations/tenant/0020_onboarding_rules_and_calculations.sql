SET search_path TO __TENANT_SCHEMA__, public;

-- Девятый шаг onboarding хранится в существующем JSONB-черновике. Отдельные
-- таблицы не нужны, но ограничение номера шага должно разрешать новый экран.
ALTER TABLE onboarding_draft
    DROP CONSTRAINT onboarding_draft_current_step_check;

ALTER TABLE onboarding_draft
    ADD CONSTRAINT onboarding_draft_current_step_check
    CHECK (current_step BETWEEN 1 AND 9);
