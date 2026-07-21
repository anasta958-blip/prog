<?php
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

function releaseSessionLock() {
    if (session_status() === PHP_SESSION_ACTIVE) {
        session_write_close();
    }
}

function appLog(string $message, array $context = []): void {
    if ($context) {
        $encoded = json_encode($context, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($encoded !== false) {
            $message .= ' ' . $encoded;
        }
    }
    error_log($message);
}

function appSafeUnlink(?string $path): void {
    if (!$path || !file_exists($path)) return;
    if (!unlink($path)) {
        appLog('Не удалось удалить временный файл', ['path' => $path]);
    }
}

function appFileGetContents(string $path, bool $useIncludePath = false, $context = null, int $offset = 0, ?int $length = null, string $label = 'file_get_contents') {
    $warning = null;
    set_error_handler(function ($severity, $message) use (&$warning) {
        $warning = $message;
        return true;
    });
    try {
        $result = $length === null
            ? file_get_contents($path, $useIncludePath, $context, $offset)
            : file_get_contents($path, $useIncludePath, $context, $offset, $length);
    } finally {
        restore_error_handler();
    }
    if ($result === false) {
        appLog('Ошибка чтения данных', ['label' => $label, 'path' => $path, 'warning' => $warning]);
    }
    return $result;
}

function csrfToken(): string {
    if (session_status() !== PHP_SESSION_ACTIVE) {
        session_start();
    }
    if (empty($_SESSION['csrf_token']) || !is_string($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

function csrfRequestToken(): string {
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    foreach ($headers as $name => $value) {
        if (strcasecmp((string)$name, 'X-CSRF-Token') === 0) {
            return trim((string)$value);
        }
    }
    if (!empty($_SERVER['HTTP_X_CSRF_TOKEN'])) {
        return trim((string)$_SERVER['HTTP_X_CSRF_TOKEN']);
    }
    if (!empty($_POST['csrf_token'])) {
        return trim((string)$_POST['csrf_token']);
    }
    return '';
}

function csrfAssertRequest(): void {
    $method = strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET'));
    if (in_array($method, ['GET', 'HEAD', 'OPTIONS'], true)) return;
    $sessionToken = $_SESSION['csrf_token'] ?? '';
    $requestToken = csrfRequestToken();
    if (!$sessionToken || !$requestToken || !hash_equals((string)$sessionToken, $requestToken)) {
        jsonResponse(['error' => 'CSRF token invalid'], 403);
    }
}

function getDB() {
    static $db = null;
    if ($db) return $db;
    $host = getenv('DB_HOST') ?: 'localhost';
    $name = getenv('DB_NAME') ?: 'kompl';
    $user = getenv('DB_USER') ?: 'root';
    $pass = getenv('DB_PASS') ?: '';
    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ];
    try {
        $db = new PDO("mysql:host=$host;dbname=$name;charset=utf8mb4", $user, $pass, $options);
    } catch (PDOException $e) {
        // Local XAMPP fallback when stale env credentials point to a non-working account.
        if ($host === 'localhost' && !($user === 'root' && $pass === '' && $name === 'kompl')) {
            $db = new PDO("mysql:host=localhost;dbname=kompl;charset=utf8mb4", 'root', '', $options);
        } else {
            throw $e;
        }
    }
    return $db;
}

function getMeasurementUnits() {
    static $units = null;
    if ($units !== null) return $units;
    $units = getDB()->query("SELECT id, name, sort_order, is_default FROM measurement_units ORDER BY is_default DESC, sort_order, name")->fetchAll();
    return $units;
}

function catalogReferenceCategoryCodes(): array {
    return ['equipment', 'materials', 'consumables', 'work', 'construction_works', 'incidental_expenses', 'maintenance', 'kits'];
}

function catalogReferenceCodePlaceholders(): string {
    return implode(',', array_fill(0, count(catalogReferenceCategoryCodes()), '?'));
}

function getCatalogReferenceCategories(): array {
    static $categories = null;
    if ($categories !== null) return $categories;
    $sql = "SELECT id, code, name, sort_order
              FROM categories
             WHERE code IN (" . catalogReferenceCodePlaceholders() . ")
             ORDER BY sort_order";
    $st = getDB()->prepare($sql);
    $st->execute(catalogReferenceCategoryCodes());
    $categories = $st->fetchAll();
    return $categories;
}

function getCatalogReferenceSections(int $categoryId = 0): array {
    static $sections = null;
    if ($sections === null) {
        $sql = "SELECT s.id, s.category_id, s.code, s.name, s.sort_order, c.code as category_code, c.name as category_name
                  FROM sections s
                  JOIN categories c ON c.id = s.category_id
                 WHERE c.code IN (" . catalogReferenceCodePlaceholders() . ")
                 ORDER BY c.sort_order, s.sort_order";
        $st = getDB()->prepare($sql);
        $st->execute(catalogReferenceCategoryCodes());
        $sections = $st->fetchAll();
    }
    if ($categoryId <= 0) return $sections;
    return array_values(array_filter($sections, function ($row) use ($categoryId) {
        return intval($row['category_id'] ?? 0) === $categoryId;
    }));
}

function getCatalogReferenceGroups(int $sectionId = 0): array {
    static $groups = null;
    if ($groups === null) {
        $groups = getDB()->query("SELECT g.id, g.section_id, g.name, g.sort_order, g.created_at, s.name AS section_name, c.name AS category_name, c.code AS category_code
                                    FROM catalog_groups g
                                    JOIN sections s ON s.id = g.section_id
                                    JOIN categories c ON c.id = s.category_id
                                   ORDER BY c.sort_order, s.sort_order, g.sort_order, g.name")->fetchAll();
    }
    if ($sectionId <= 0) return $groups;
    return array_values(array_filter($groups, function ($row) use ($sectionId) {
        return intval($row['section_id'] ?? 0) === $sectionId;
    }));
}

function getCatalogReferenceSuppliersWithSections(): array {
    static $suppliers = null;
    if ($suppliers !== null) return $suppliers;
    $suppliers = getDB()->query("SELECT sup.id, sup.name, sup.sort_order,
                                        GROUP_CONCAT(ss.section_id ORDER BY ss.section_id) as section_ids
                                   FROM suppliers sup
                                   LEFT JOIN section_suppliers ss ON ss.supplier_id = sup.id
                                  GROUP BY sup.id
                                  ORDER BY sup.sort_order, sup.name")->fetchAll();
    return $suppliers;
}

function getCatalogReferenceSuppliers(int $sectionId = 0, bool $includeEmpty = false): array {
    $rows = getCatalogReferenceSuppliersWithSections();
    if ($sectionId > 0) {
        $rows = array_values(array_filter($rows, function ($row) use ($sectionId) {
            $ids = array_filter(array_map('intval', explode(',', (string)($row['section_ids'] ?? ''))));
            return in_array($sectionId, $ids, true);
        }));
    }
    $rows = array_map(function ($row) {
        return [
            'id' => intval($row['id'] ?? 0),
            'name' => (string)($row['name'] ?? ''),
            'sort_order' => intval($row['sort_order'] ?? 0),
        ];
    }, $rows);
    if ($includeEmpty) {
        array_unshift($rows, ['id' => 0, 'name' => '', 'sort_order' => 0]);
    }
    return $rows;
}

function getCatalogReferenceMeta(): array {
    static $meta = null;
    if ($meta !== null) return $meta;
    $meta = [
        'categories' => getCatalogReferenceCategories(),
        'sections' => getCatalogReferenceSections(),
        'groups' => getCatalogReferenceGroups(),
        'suppliers' => getCatalogReferenceSuppliersWithSections(),
        'units' => getMeasurementUnits(),
    ];
    return $meta;
}

function getDefaultMeasurementUnitName() {
    $units = getMeasurementUnits();
    if (!$units) return '';
    foreach ($units as $unit) {
        if (!empty($unit['is_default'])) return (string)$unit['name'];
    }
    return (string)($units[0]['name'] ?? '');
}

function apiResponseEnvelope($data, $code = 200) {
    if (is_array($data) && array_key_exists('ok', $data) && array_key_exists('data', $data) && array_key_exists('error', $data)) {
        return $data;
    }
    $isError = $code >= 400 || (is_array($data) && array_key_exists('error', $data));
    if ($isError) {
        $message = is_array($data) && array_key_exists('error', $data) ? (string)$data['error'] : 'Ошибка запроса';
        return [
            'ok' => false,
            'data' => null,
            'error' => $message,
        ];
    }
    return [
        'ok' => true,
        'data' => $data,
        'error' => null,
    ];
}

function jsonResponse($data, $code = 200) {
    if (!headers_sent()) {
        header('Content-Type: application/json; charset=utf-8');
    }
    http_response_code($code);
    echo json_encode(apiResponseEnvelope($data, $code), JSON_UNESCAPED_UNICODE);
    releaseSessionLock();
    exit;
}

function getCurrentUser() {
    static $loaded = false;
    static $currentUser = null;
    if ($loaded) return $currentUser;

    $userId = $_SESSION['user_id'] ?? null;
    if (!$userId) {
        $loaded = true;
        releaseSessionLock();
        return null;
    }

    $db = getDB();
    $st = $db->prepare("SELECT id, username, role, full_name, phone, telegram, email FROM users WHERE id = ?");
    $st->execute([$userId]);
    $currentUser = $st->fetch() ?: null;
    $loaded = true;
    releaseSessionLock();
    return $currentUser;
}

function requireAuth() {
    $u = getCurrentUser();
    if (!$u) jsonResponse(['error' => 'Unauthorized'], 401);
    csrfAssertRequest();
    return $u;
}

function requireAdmin() {
    $u = requireAuth();
    if ($u['role'] !== 'admin') jsonResponse(['error' => 'Forbidden'], 403);
    return $u;
}

function isAdmin($user = null) {
    if ($user) return $user['role'] === 'admin';
    $u = getCurrentUser();
    return $u && $u['role'] === 'admin';
}

function isRole($role) {
    $u = getCurrentUser();
    return $u && $u['role'] === $role;
}

function hasRole(array $roles) {
    $u = getCurrentUser();
    return $u && in_array($u['role'], $roles);
}

function getRopManagers($ropId) {
    $db = getDB();
    $st = $db->prepare("SELECT manager_id FROM rop_managers WHERE rop_id = ?");
    $st->execute([$ropId]);
    return array_column($st->fetchAll(), 'manager_id');
}

function getManagerRop($managerId) {
    $db = getDB();
    $st = $db->prepare("SELECT rop_id FROM rop_managers WHERE manager_id = ?");
    $st->execute([$managerId]);
    $r = $st->fetch();
    return $r ? $r['rop_id'] : null;
}

function accessRolesList() {
    return ['admin','manager','rop','logist','prorab'];
}

function accessDefaultPolicy($role) {
    $allTabs = [
        'catalog' => true,
        'orders' => true,
        'doc' => true,
        'employees' => true,
        'users' => false,
        'kp_company' => true,
        'kp_clients' => true,
        'kp_contractors' => true,
        'kp_list' => true,
        'documents_builder' => true,
        'settings_units' => false,
        'settings_suppliers' => false,
        'settings_groups' => false,
        'settings_access' => false,
    ];
    $spaces = [
        'catalog' => ['create' => true, 'edit' => true, 'delete' => false, 'export' => true],
        'orders' => ['create' => true, 'edit' => true, 'delete' => false, 'export' => false],
        'kp' => ['create' => true, 'edit' => true, 'delete' => false, 'export' => false],
        'company' => ['create' => true, 'edit' => true, 'delete' => false, 'export' => false],
        'documents' => ['create' => true, 'edit' => true, 'delete' => false, 'export' => false],
        'settings' => ['create' => false, 'edit' => false, 'delete' => false, 'export' => false],
        'users' => ['create' => false, 'edit' => false, 'delete' => false, 'export' => false],
    ];
    $kanban = [
        'orders' => ['scope' => 'all', 'user_ids' => []],
        'kp' => ['scope' => 'all', 'user_ids' => []],
    ];

    if ($role === 'admin') {
        foreach ($allTabs as $key => $val) $allTabs[$key] = true;
        foreach ($spaces as $key => $cfg) $spaces[$key] = ['create' => true, 'edit' => true, 'delete' => true, 'export' => true];
        $kanban = [
            'orders' => ['scope' => 'all', 'user_ids' => []],
            'kp' => ['scope' => 'all', 'user_ids' => []],
        ];
    } elseif ($role === 'manager') {
        $allTabs['settings_units'] = false;
        $allTabs['settings_suppliers'] = false;
        $allTabs['settings_groups'] = false;
        $kanban = [
            'orders' => ['scope' => 'own', 'user_ids' => []],
            'kp' => ['scope' => 'own', 'user_ids' => []],
        ];
    } elseif ($role === 'rop') {
        $spaces['catalog']['delete'] = true;
        $spaces['orders']['delete'] = true;
        $spaces['kp']['delete'] = true;
        $spaces['company']['delete'] = true;
        $kanban = [
            'orders' => ['scope' => 'managed', 'user_ids' => []],
            'kp' => ['scope' => 'managed', 'user_ids' => []],
        ];
    } elseif ($role === 'logist' || $role === 'prorab') {
        $spaces['catalog']['delete'] = false;
        $spaces['kp']['create'] = false;
        $spaces['kp']['edit'] = false;
        $spaces['company']['create'] = false;
        $spaces['company']['edit'] = false;
        $spaces['company']['delete'] = false;
        $kanban = [
            'orders' => ['scope' => 'all', 'user_ids' => []],
            'kp' => ['scope' => 'all', 'user_ids' => []],
        ];
    }

    if ($role !== 'admin') {
        $allTabs['settings_access'] = false;
        $allTabs['users'] = false;
    }

    return [
        'tabs' => $allTabs,
        'spaces' => $spaces,
        'kanban' => $kanban,
    ];
}

function accessMergePolicy(array $base, array $saved) {
    foreach ($saved as $key => $value) {
        if (is_array($value) && isset($base[$key]) && is_array($base[$key])) {
            $base[$key] = accessMergePolicy($base[$key], $value);
        } else {
            $base[$key] = $value;
        }
    }
    return $base;
}

function getRoleAccessPolicies() {
    static $cache = null;
    if ($cache !== null) return $cache;
    $cache = [];
    foreach (accessRolesList() as $role) {
        $cache[$role] = accessDefaultPolicy($role);
    }
    try {
        $rows = getDB()->query("SELECT role, config_json FROM role_access_policies")->fetchAll();
        foreach ($rows as $row) {
            $role = trim((string)($row['role'] ?? ''));
            if ($role === '' || !isset($cache[$role])) continue;
            $decoded = json_decode((string)($row['config_json'] ?? ''), true);
            if (is_array($decoded)) {
                $cache[$role] = accessMergePolicy($cache[$role], $decoded);
            }
        }
    } catch (Throwable $e) {
    }
    return $cache;
}

function getRoleAccessPolicy($role) {
    $policies = getRoleAccessPolicies();
    return $policies[$role] ?? accessDefaultPolicy($role);
}

function getCurrentAccessPolicy($user = null) {
    $user = $user ?: getCurrentUser();
    if (!$user) return accessDefaultPolicy('manager');
    return getRoleAccessPolicy((string)($user['role'] ?? 'manager'));
}

function accessCan($user, $space, $action) {
    if (!$user) return false;
    $role = (string)($user['role'] ?? '');
    if ($role === 'admin') return true;
    $policy = getCurrentAccessPolicy($user);
    return !empty($policy['spaces'][$space][$action]);
}

function accessTabVisible($user, $tabKey) {
    if (!$user) return false;
    if ((string)($user['role'] ?? '') === 'admin') return true;
    $policy = getCurrentAccessPolicy($user);
    return !empty($policy['tabs'][$tabKey]);
}

function accessResolveScopeUserIds($user, $workspaceKey) {
    if (!$user) return [];
    if ((string)($user['role'] ?? '') === 'admin') return [];
    $policy = getCurrentAccessPolicy($user);
    $scopeCfg = $policy['kanban'][$workspaceKey] ?? ['scope' => 'own', 'user_ids' => []];
    $scope = trim((string)($scopeCfg['scope'] ?? 'own'));
    $uid = intval($user['id'] ?? 0);
    if ($scope === 'all') return [];
    if ($scope === 'own') return [$uid];
    if ($scope === 'managed') {
        $ids = [$uid];
        foreach (getRopManagers($uid) as $mid) $ids[] = intval($mid);
        return array_values(array_unique(array_filter($ids)));
    }
    if ($scope === 'specific') {
        $ids = array_map('intval', is_array($scopeCfg['user_ids'] ?? null) ? $scopeCfg['user_ids'] : []);
        return array_values(array_unique(array_filter($ids)));
    }
    return [$uid];
}

function accessAssert($user, $space, $action) {
    if (!accessCan($user, $space, $action)) jsonResponse(['error' => 'Forbidden'], 403);
}

function getNextOrderNumber($orderType = null) {
    $db = getDB();
    if ($orderType) {
        // Get max sequence number for this type (supports both "ДК-5" and legacy "5" formats)
        $row = $db->prepare("SELECT MAX(CAST(REGEXP_REPLACE(order_number, '^[^0-9]*', '') AS UNSIGNED)) as mx FROM orders WHERE order_type = ?");
        $row->execute([$orderType]);
        $row = $row->fetch();
        return (string)(($row['mx'] ?? 0) + 1);
    }
    // fallback: global max
    $row = $db->query("SELECT MAX(CAST(REGEXP_REPLACE(order_number, '^[^0-9]*', '') AS UNSIGNED)) as mx FROM orders")->fetch();
    return (string)(($row['mx'] ?? 0) + 1);
}
