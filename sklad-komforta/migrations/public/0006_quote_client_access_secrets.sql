BEGIN;

-- Зашифрованные AES-GCM копии открытого токена ссылки и пароля клиента.
-- Нужны, чтобы сотрудник с правом quotes.manage мог повторно скопировать
-- действующую ссылку. Поиск и проверка по-прежнему идут только по token_hash
-- и password_hash; у ссылок, созданных до этой миграции, копий нет (NULL).
ALTER TABLE public.quote_client_access_links
    ADD COLUMN IF NOT EXISTS token_ciphertext bytea NULL,
    ADD COLUMN IF NOT EXISTS password_ciphertext bytea NULL;

INSERT INTO public.schema_migrations (version)
VALUES ('0006_quote_client_access_secrets')
ON CONFLICT (version) DO NOTHING;

COMMIT;
