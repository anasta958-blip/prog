-- Старые реквизиты уже перенесены миграцией 0039. Архив не используется приложением:
-- он сохраняет исходные значения на случай расхождений с вручную созданными юрлицами.
ALTER TABLE organization_profile RENAME TO organization_profile_legacy;

-- После завершения мастера конфигурация больше не хранит вторую копию юрлица.
UPDATE onboarding_draft
SET payload = jsonb_set(payload, '{company}',
    jsonb_build_object('organizationName', payload #>> '{company,organizationName}'))
WHERE EXISTS (
    SELECT 1 FROM public.organizations
    WHERE schema_name = current_schema() AND onboarding_completed_at IS NOT NULL
);
