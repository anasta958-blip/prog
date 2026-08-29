SET search_path TO __TENANT_SCHEMA__, public;

-- Действия с рабочими карточками настраиваются правами роли, а не полями
-- категории. Обновление также исправляет подписи старых разрешений, если они
-- были импортированы в базу с неверной кодировкой.
INSERT INTO permissions (code, name, group_name)
VALUES
    ('kanban.view', 'Просмотр канбанов', 'Канбаны'),
    ('kanban.cards.create', 'Создание карточек', 'Канбаны'),
    ('kanban.cards.edit', 'Редактирование карточек', 'Канбаны'),
    ('kanban.cards.delete', 'Удаление карточек', 'Канбаны'),
    ('kanban.cards.move', 'Перемещение карточек', 'Канбаны')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    group_name = EXCLUDED.group_name;

-- Роли со старым общим правом управления сохраняют прежние возможности.
INSERT INTO role_permissions (role_id, permission_id)
SELECT existing.role_id, replacement.id
FROM role_permissions AS existing
JOIN permissions AS previous ON previous.id = existing.permission_id
CROSS JOIN permissions AS replacement
WHERE previous.code = 'kanban.manage'
  AND replacement.code IN (
      'kanban.cards.create',
      'kanban.cards.edit',
      'kanban.cards.delete',
      'kanban.cards.move')
ON CONFLICT DO NOTHING;

DELETE FROM permissions WHERE code = 'kanban.manage';

ALTER TABLE kanban_cards
    ADD COLUMN section_id uuid NULL,
    ADD CONSTRAINT kanban_cards_section_category_fk
        FOREIGN KEY (section_id, category_id)
        REFERENCES catalog_sections(id, category_id) ON DELETE RESTRICT;

CREATE INDEX ix_kanban_cards_section
    ON kanban_cards (section_id, updated_at DESC)
    WHERE deleted_at IS NULL AND section_id IS NOT NULL;
