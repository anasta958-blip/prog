<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/access_middleware.php';

header('Content-Type: application/json; charset=utf-8');

$user = requireAuth();
$method = $_SERVER['REQUEST_METHOD'];
$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) $input = [];
$action = $_GET['action'] ?? ($input['action'] ?? 'my');
accessMiddlewareAssertAction($user, (string)$action, [
    'policies' => ['admin' => true],
    'save_policy' => ['admin' => true],
    'users' => ['admin' => true],
]);
$db = getDB();

function permissionsNormalizePolicy($role, $raw) {
    $base = accessDefaultPolicy($role);
    if (!is_array($raw)) return $base;
    $policy = accessMergePolicy($base, $raw);
    if ($role !== 'admin') {
        $policy['tabs']['settings_access'] = false;
        $policy['tabs']['users'] = !empty($policy['tabs']['users']);
    } else {
        foreach ($policy['tabs'] as $k => $v) $policy['tabs'][$k] = true;
        foreach ($policy['spaces'] as $k => $cfg) $policy['spaces'][$k] = ['create' => true, 'edit' => true, 'delete' => true, 'export' => true];
        $policy['kanban']['orders'] = ['scope' => 'all', 'user_ids' => []];
        $policy['kanban']['kp'] = ['scope' => 'all', 'user_ids' => []];
    }
    unset($policy['spaces']['pkp'], $policy['kanban']['pkp'], $policy['tabs']['pkp_company'], $policy['tabs']['pkp_clients'], $policy['tabs']['pkp_list']);
    foreach (['orders','kp'] as $workspaceKey) {
        $scope = trim((string)($policy['kanban'][$workspaceKey]['scope'] ?? 'own'));
        if (!in_array($scope, ['own','all','managed','specific'], true)) $scope = 'own';
        $policy['kanban'][$workspaceKey]['scope'] = $scope;
        $policy['kanban'][$workspaceKey]['user_ids'] = array_values(array_unique(array_filter(array_map('intval', is_array($policy['kanban'][$workspaceKey]['user_ids'] ?? null) ? $policy['kanban'][$workspaceKey]['user_ids'] : []))));
        $columns = is_array($policy['kanban'][$workspaceKey]['columns'] ?? null) ? $policy['kanban'][$workspaceKey]['columns'] : [];
        $policy['kanban'][$workspaceKey]['columns'] = array_values(array_unique(array_filter(array_map('strval', $columns))));
    }
    return $policy;
}

switch ($action) {
    case 'my':
        jsonResponse([
            'role' => $user['role'],
            'policy' => getCurrentAccessPolicy($user),
            'roles' => accessRolesList(),
        ]);
        break;

    case 'policies':
        requireAdmin();
        jsonResponse([
            'roles' => accessRolesList(),
            'policies' => getRoleAccessPolicies(),
        ]);
        break;

    case 'save_policy':
        requireAdmin();
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        $role = trim((string)($input['role'] ?? ''));
        if (!in_array($role, accessRolesList(), true)) jsonResponse(['error' => 'Invalid role'], 400);
        $policy = permissionsNormalizePolicy($role, $input['policy'] ?? []);
        $payload = json_encode($policy, JSON_UNESCAPED_UNICODE);
        $st = $db->prepare("INSERT INTO role_access_policies (role, config_json) VALUES (?, ?)
                            ON DUPLICATE KEY UPDATE config_json = VALUES(config_json)");
        $st->execute([$role, $payload]);
        jsonResponse(['ok' => true]);
        break;

    case 'users':
        requireAdmin();
        $rows = $db->query("SELECT id, full_name, username, role FROM users ORDER BY full_name, username")->fetchAll();
        jsonResponse($rows);
        break;
}

jsonResponse(['error' => 'Unknown action'], 400);
