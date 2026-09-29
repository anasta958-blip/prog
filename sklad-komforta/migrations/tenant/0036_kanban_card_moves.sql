SET search_path TO __TENANT_SCHEMA__, public;

-- Кто и когда последним перенёс карточку в другую колонку («Статус изменил»).
-- Раньше перенос перезаписывал updated_by/updated_at, и отличить его от
-- правки содержимого было нельзя; теперь перенос пишется отдельно.
ALTER TABLE kanban_cards
    ADD COLUMN IF NOT EXISTS moved_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS moved_at timestamptz NULL;

-- Для существующих карточек берётся последний перенос между колонками из аудита.
UPDATE kanban_cards AS card
SET moved_by = last_move.actor_user_id,
    moved_at = last_move.created_at
FROM (
    SELECT DISTINCT ON (entity_id) entity_id, actor_user_id, created_at
    FROM audit_log
    WHERE entity_type = 'kanban_card'
      AND action = 'moved'
      AND diff -> 'before' ->> 'columnId' IS DISTINCT FROM diff -> 'after' ->> 'columnId'
    ORDER BY entity_id, created_at DESC, id DESC
) AS last_move
WHERE card.id = last_move.entity_id
  AND card.moved_at IS NULL;
