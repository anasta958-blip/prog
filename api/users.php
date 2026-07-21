<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/access_middleware.php';
require_once __DIR__ . '/../includes/pagination.php';

header('Content-Type: application/json; charset=utf-8');
$user = requireAuth();
$role = $user['role'];
$method = $_SERVER['REQUEST_METHOD'];
$input  = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) $input = [];
$action = $_GET['action'] ?? ($input['action'] ?? '');
accessMiddlewareAssertAction($user, (string)$action, [
    'list' => ['tabs_any' => ['users', 'employees']],
    'create' => ['space' => 'users', 'action' => 'create'],
    'update' => ['space' => 'users', 'action' => 'edit'],
    'set_director' => ['space' => 'users', 'action' => 'edit'],
    'delete' => ['space' => 'users', 'action' => 'delete'],
]);

$db = getDB();
$VALID_ROLES = ['admin','manager','rop','logist','prorab'];

function usersAccessSummary($role) {
    $policy = getRoleAccessPolicy((string)$role);
    $tabs = is_array($policy['tabs'] ?? null) ? $policy['tabs'] : [];
    $spaces = is_array($policy['spaces'] ?? null) ? $policy['spaces'] : [];
    $kanban = is_array($policy['kanban'] ?? null) ? $policy['kanban'] : [];
    $visibleTabs = [];
    foreach ($tabs as $key => $visible) {
        if ($visible) $visibleTabs[] = (string)$key;
    }
    $allowedSpaces = [];
    foreach ($spaces as $space => $actions) {
        if (!is_array($actions)) continue;
        $active = [];
        foreach (['create','edit','delete','export'] as $action) {
            if (!empty($actions[$action])) $active[] = $action;
        }
        if ($active) $allowedSpaces[(string)$space] = $active;
    }
    return [
        'tabs' => $visibleTabs,
        'spaces' => $allowedSpaces,
        'kanban' => $kanban,
    ];
}

function usersTransferOwnedData($db, $fromUserId, $toUserId) {
    $fromUserId = intval($fromUserId);
    $toUserId = intval($toUserId);
    if (!$fromUserId || !$toUserId || $fromUserId === $toUserId) {
        throw new RuntimeException('Некорректные пользователи для переноса данных');
    }

    $db->prepare("UPDATE company_profiles SET user_id = ?, is_default = 0 WHERE user_id = ?")->execute([$toUserId, $fromUserId]);
    $defaultCheck = $db->prepare("SELECT id FROM company_profiles WHERE user_id = ? AND is_default = 1 LIMIT 1");
    $defaultCheck->execute([$toUserId]);
    if (!$defaultCheck->fetch()) {
        $firstProfile = $db->prepare("SELECT id FROM company_profiles WHERE user_id = ? ORDER BY id LIMIT 1");
        $firstProfile->execute([$toUserId]);
        $firstId = intval($firstProfile->fetch()['id'] ?? 0);
        if ($firstId) $db->prepare("UPDATE company_profiles SET is_default = 1 WHERE id = ?")->execute([$firstId]);
    }

    foreach (['kp_clients', 'kp_contractors', 'kp_quotes', 'pkp_quotes', 'documents_templates'] as $table) {
        $db->prepare("UPDATE {$table} SET user_id = ? WHERE user_id = ?")->execute([$toUserId, $fromUserId]);
    }

    $db->prepare("UPDATE documents_template_versions SET created_by = ? WHERE created_by = ?")
       ->execute([$toUserId, $fromUserId]);
    $db->prepare("UPDATE orders SET manager_id = ? WHERE manager_id = ?")
       ->execute([$toUserId, $fromUserId]);
    $db->prepare("UPDATE orders SET rop_id = NULL WHERE rop_id = ?")
       ->execute([$fromUserId]);
    $db->prepare("UPDATE orders SET status_changed_by = NULL WHERE status_changed_by = ?")
       ->execute([$fromUserId]);
    $db->prepare("UPDATE products SET created_by = ? WHERE created_by = ?")
       ->execute([$toUserId, $fromUserId]);
}

switch ($action) {

    case 'list':
        if (!accessTabVisible($user, 'users') && !accessTabVisible($user, 'employees')) jsonResponse(['error' => 'Forbidden'], 403);
        $pagination = paginationFromRequest(50, 200);
        if ($role !== 'admin') {
            $sql = "SELECT u.id, u.full_name, u.role, u.phone, u.telegram, u.email,
                        (d.user_id IS NOT NULL) AS is_director
                 FROM users u
                 LEFT JOIN company_director d ON d.user_id = u.id
                 ORDER BY u.full_name" . paginationLimitSql($pagination);
            $rows = $db->query($sql)->fetchAll();
        } else {
            $sql = "SELECT u.id, u.username, u.role, u.full_name, u.phone, u.telegram, u.email, u.created_at,
                        (d.user_id IS NOT NULL) AS is_director,
                        GROUP_CONCAT(rm.manager_id) as manager_ids
                 FROM users u
                 LEFT JOIN rop_managers rm ON rm.rop_id = u.id
                 LEFT JOIN company_director d ON d.user_id = u.id
                 GROUP BY u.id
                 ORDER BY u.created_at DESC" . paginationLimitSql($pagination);
            $rows = $db->query($sql)->fetchAll();
            foreach ($rows as &$r) {
                $r['manager_ids'] = $r['manager_ids'] ? array_map('intval', explode(',', $r['manager_ids'])) : [];
            }
            unset($r);
        }
        foreach ($rows as &$r) {
            $r['access_summary'] = usersAccessSummary($r['role'] ?? 'manager');
        }
        unset($r);
        if ($pagination) {
            jsonResponse(paginationPayload($rows, paginationCount($db, "FROM users"), $pagination));
        }
        jsonResponse($rows);
        break;

    case 'create':
        accessAssert($user, 'users', 'create');
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        $username  = trim($input['username']  ?? '');
        $password  = $input['password']       ?? '';
        $role      = in_array($input['role'] ?? '', $VALID_ROLES) ? $input['role'] : 'manager';
        $full_name = trim($input['full_name'] ?? '');
        $phone     = trim($input['phone']     ?? '');
        $telegram  = trim($input['telegram']  ?? '');
        $email     = trim($input['email']     ?? '');
        if (!$email || !filter_var($email, FILTER_VALIDATE_EMAIL)) jsonResponse(['error' => 'Некорректный email'], 400);

        if (!$username || !$password || !$full_name) jsonResponse(['error' => 'Заполните все поля'], 400);
        if (mb_strlen($password) < 4) jsonResponse(['error' => 'Пароль минимум 4 символа'], 400);

        $check = $db->prepare("SELECT id FROM users WHERE username=?");
        $check->execute([$username]);
        if ($check->fetch()) jsonResponse(['error' => 'Логин уже занят'], 409);

        $hash = password_hash($password, PASSWORD_DEFAULT);
        $stmt = $db->prepare("INSERT INTO users (username, password, role, full_name, phone, telegram, email) VALUES (?,?,?,?,?,?,?)");
        $stmt->execute([$username, $hash, $role, $full_name, $phone, $telegram, $email]);
        $newId = $db->lastInsertId();

        // Bind managers if ROP
        if ($role === 'rop' && !empty($input['manager_ids']) && is_array($input['manager_ids'])) {
            $ins = $db->prepare("INSERT IGNORE INTO rop_managers (rop_id, manager_id) VALUES (?,?)");
            foreach ($input['manager_ids'] as $mid) {
                $ins->execute([$newId, intval($mid)]);
            }
        }
        jsonResponse(['ok' => true, 'id' => $newId]);
        break;

    case 'update':
        accessAssert($user, 'users', 'edit');
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        $id        = intval($input['id'] ?? 0);
        $full_name = trim($input['full_name'] ?? '');
        $role      = in_array($input['role'] ?? '', $VALID_ROLES) ? $input['role'] : 'manager';
        $password  = trim($input['password'] ?? '');
        $phone     = trim($input['phone']    ?? '');
        $telegram  = trim($input['telegram'] ?? '');
        $email     = trim($input['email']    ?? '');
        if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) jsonResponse(['error' => 'Некорректный email'], 400);

        if (!$id || !$full_name) jsonResponse(['error' => 'Данные неполные'], 400);

        if ($password) {
            if (mb_strlen($password) < 4) jsonResponse(['error' => 'Пароль минимум 4 символа'], 400);
            $hash = password_hash($password, PASSWORD_DEFAULT);
            $db->prepare("UPDATE users SET full_name=?, role=?, password=?, phone=?, telegram=?, email=? WHERE id=?")
               ->execute([$full_name, $role, $hash, $phone, $telegram, $email, $id]);
        } else {
            $db->prepare("UPDATE users SET full_name=?, role=?, phone=?, telegram=?, email=? WHERE id=?")
               ->execute([$full_name, $role, $phone, $telegram, $email, $id]);
        }

        // Update ROP managers binding
        $db->prepare("DELETE FROM rop_managers WHERE rop_id=?")->execute([$id]);
        if ($role === 'rop' && !empty($input['manager_ids']) && is_array($input['manager_ids'])) {
            $ins = $db->prepare("INSERT IGNORE INTO rop_managers (rop_id, manager_id) VALUES (?,?)");
            foreach ($input['manager_ids'] as $mid) {
                $ins->execute([$id, intval($mid)]);
            }
        }
        jsonResponse(['ok' => true]);
        break;

    case 'set_director':
        accessAssert($user, 'users', 'edit');
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'Пользователь не указан'], 400);

        $check = $db->prepare("SELECT id FROM users WHERE id=?");
        $check->execute([$id]);
        if (!$check->fetch()) jsonResponse(['error' => 'Пользователь не найден'], 404);

        $db->prepare(
            "INSERT INTO company_director (singleton_id, user_id, updated_by)
             VALUES (1, ?, ?)
             ON DUPLICATE KEY UPDATE user_id=VALUES(user_id), updated_by=VALUES(updated_by)"
        )->execute([$id, intval($user['id'] ?? 0) ?: null]);
        jsonResponse(['ok' => true, 'director_id' => $id]);
        break;

    case 'delete':
        accessAssert($user, 'users', 'delete');
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        $currentUser = getCurrentUser();
        if (!$id) jsonResponse(['error' => 'Пользователь не указан'], 400);
        if ($id == $currentUser['id']) jsonResponse(['error' => 'Нельзя удалить себя'], 400);

        $check = $db->prepare("SELECT id FROM users WHERE id = ? LIMIT 1");
        $check->execute([$id]);
        if (!$check->fetch()) jsonResponse(['error' => 'Пользователь не найден'], 404);

        $db->beginTransaction();
        try {
            usersTransferOwnedData($db, $id, intval($currentUser['id']));
            $delete = $db->prepare("DELETE FROM users WHERE id = ?");
            $delete->execute([$id]);
            if ($delete->rowCount() !== 1) {
                throw new RuntimeException('Пользователь не был удалён');
            }
            $db->commit();
            jsonResponse(['ok' => true, 'deleted_id' => $id]);
        } catch (Throwable $e) {
            if ($db->inTransaction()) $db->rollBack();
            jsonResponse(['error' => 'Не удалось удалить пользователя: ' . $e->getMessage()], 500);
        }
        break;

    default:
        jsonResponse(['error' => 'Unknown action'], 400);
}
