BEGIN;

-- Количество входов клиента по ссылке: показывается на карточке КП/ПКП.
-- Для уже открывавшихся ссылок точное число неизвестно, считаем один вход.
ALTER TABLE public.quote_client_access_links
    ADD COLUMN IF NOT EXISTS access_count integer NOT NULL DEFAULT 0
        CHECK (access_count >= 0);

UPDATE public.quote_client_access_links
SET access_count = 1
WHERE last_accessed_at IS NOT NULL
  AND access_count = 0;

INSERT INTO public.schema_migrations (version)
VALUES ('0007_quote_client_access_views')
ON CONFLICT (version) DO NOTHING;

COMMIT;
