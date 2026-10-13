-- Старый мастер сохранял реквизиты после миграции 0014, поэтому юрлицо не создавалось.
-- Не трогаем существующие/удалённые вручную юрлица и не создаём дубликаты.
INSERT INTO companies (
    name, company_type, legal_name, inn, kpp, ogrn,
    address, phone, email, is_default, created_by
)
SELECT organization_name,
       CASE WHEN lower(company_type) IN ('ip', 'ип') THEN 'ip' ELSE 'ooo' END,
       legal_name, inn, kpp, ogrn, address, phone, email, true, updated_by
FROM organization_profile
WHERE singleton AND NOT EXISTS (SELECT 1 FROM companies);
