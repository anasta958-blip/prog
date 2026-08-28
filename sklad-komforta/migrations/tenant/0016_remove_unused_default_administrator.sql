SET search_path TO __TENANT_SCHEMA__, public;

-- Старую дефолтную роль удаляем только тогда, когда она никому не назначена.
-- Назначенную роль нельзя удалять автоматически: это могло бы оставить
-- сотрудника без доступа и уничтожить настроенные пользователем связи.
DELETE FROM roles AS role
WHERE role.name = 'Администратор'
  AND role.is_system
  AND NOT EXISTS (
      SELECT 1
      FROM member_roles AS member_role
      WHERE member_role.role_id = role.id
  );
