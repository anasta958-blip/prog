<?php
require_once __DIR__ . '/../includes/auth.php';

header('Content-Type: application/json; charset=utf-8');

$user = requireAuth();

try {
    $meta = getCatalogReferenceMeta();
    jsonResponse([
        'categories' => $meta['categories'],
        'sections' => $meta['sections'],
        'groups' => $meta['groups'],
        'suppliers' => $meta['suppliers'],
        'units' => $meta['units'],
        'permissions' => [
            'role' => $user['role'],
            'policy' => getCurrentAccessPolicy($user),
            'roles' => accessRolesList(),
        ],
    ]);
} catch (Throwable $e) {
    jsonResponse(['error' => 'Не удалось загрузить справочники'], 500);
}
