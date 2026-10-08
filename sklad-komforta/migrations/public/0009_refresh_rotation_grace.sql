BEGIN;
-- Связь «сессия → её замена» при ротации refresh-токена. Позволяет короткое
-- время принять только что заменённый токен, если ответ с новой cookie не
-- дошёл до браузера (перезагрузка страницы во время запроса, два окна).
ALTER TABLE public.refresh_sessions
    ADD COLUMN IF NOT EXISTS replaced_by uuid NULL REFERENCES public.refresh_sessions(id) ON DELETE SET NULL;
INSERT INTO public.schema_migrations (version) VALUES ('0009_refresh_rotation_grace') ON CONFLICT (version) DO NOTHING;
COMMIT;
