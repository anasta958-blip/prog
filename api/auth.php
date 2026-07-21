<?php
require_once __DIR__ . '/../includes/auth.php';

header('Content-Type: application/json; charset=utf-8');
$input  = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) $input = [];
$action = $_GET['action'] ?? ($input['action'] ?? '');

$db = getDB();

switch ($action) {
    case 'login':
        $username = trim($input['username'] ?? '');
        $password = $input['password'] ?? '';
        if (!$username || !$password) jsonResponse(['error' => 'Заполните все поля'], 400);
        $st = $db->prepare("SELECT id, username, password, role, full_name, created_at, phone, telegram, email FROM users WHERE username = ?");
        $st->execute([$username]);
        $user = $st->fetch();
        if (!$user || !password_verify($password, $user['password'])) {
            jsonResponse(['error' => 'Неверный логин или пароль'], 401);
        }
        session_regenerate_id(true);
        $_SESSION['user_id'] = $user['id'];
        $csrfToken = csrfToken();
        $nextOrder = getNextOrderNumber();
        // Attach ROP name if manager
        $ropName = '';
        if ($user['role'] === 'manager') {
            $ropId = getManagerRop($user['id']);
            if ($ropId) {
                $rSt = $db->prepare("SELECT full_name FROM users WHERE id=?");
                $rSt->execute([$ropId]);
                $rRow = $rSt->fetch();
                $ropName = $rRow ? $rRow['full_name'] : '';
            }
        }
        jsonResponse(['ok' => true, 'csrf_token' => $csrfToken, 'user' => [
            'id' => $user['id'], 'username' => $user['username'],
            'role' => $user['role'], 'full_name' => $user['full_name'],
            'phone' => $user['phone'], 'telegram' => $user['telegram'],
            'email' => $user['email'] ?? '',
            'rop_name' => $ropName,
        ], 'next_order' => $nextOrder]);
        break;

    case 'me':
        $u = getCurrentUser();
        if (!$u) jsonResponse(['error' => 'Unauthorized'], 401);
        $nextOrder = getNextOrderNumber();
        // Attach ROP name if manager
        $ropName = '';
        if ($u['role'] === 'manager') {
            $ropId = getManagerRop($u['id']);
            if ($ropId) {
                $rSt = $db->prepare("SELECT full_name FROM users WHERE id=?");
                $rSt->execute([$ropId]);
                $rRow = $rSt->fetch();
                $ropName = $rRow ? $rRow['full_name'] : '';
            }
        }
        jsonResponse(['user' => array_merge($u, ['rop_name' => $ropName]), 'next_order' => $nextOrder, 'csrf_token' => csrfToken()]);
        break;

    case 'logout':
        csrfAssertRequest();
        if (session_status() !== PHP_SESSION_ACTIVE) {
            session_start();
        }
        $_SESSION = [];
        session_destroy();
        jsonResponse(['ok' => true]);
        break;

    default:
        jsonResponse(['error' => 'Unknown action'], 400);
}
