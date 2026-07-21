<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/access_middleware.php';
require_once __DIR__ . '/../includes/pagination.php';

header('Content-Type: application/json; charset=utf-8');

$user = requireAuth();
$method = $_SERVER['REQUEST_METHOD'];
$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) $input = [];
$postAction = is_array($_POST ?? null) ? ($_POST['action'] ?? null) : null;
$action = $_GET['action'] ?? ($input['action'] ?? $postAction ?? 'list');
accessMiddlewareAssertAction($user, (string)$action, [
    'upload_image' => ['space_any' => [['documents', 'create'], ['documents', 'edit']]],
    'save' => ['space_any' => [['documents', 'create'], ['documents', 'edit']]],
    'delete' => ['space' => 'documents', 'action' => 'delete'],
]);
$db = getDB();

function documentsScopeUserIds(array $user): array {
    if (($user['role'] ?? '') === 'admin') return [];
    return accessResolveScopeUserIds($user, 'kp');
}

function documentsAssertTemplateAccess(array $user, array $row): void {
    if (($user['role'] ?? '') === 'admin') return;
    $uid = intval($user['id'] ?? 0);
    if (intval($row['user_id'] ?? 0) === $uid) return;
    $scope = documentsScopeUserIds($user);
    if ($scope && in_array(intval($row['user_id'] ?? 0), $scope, true)) return;
    jsonResponse(['error' => 'Forbidden'], 403);
}

function documentsDecodePayload(?string $json): array {
    if (!$json) return [];
    $payload = json_decode($json, true);
    return is_array($payload) ? $payload : [];
}

function documentsNormalizeType(string $type): string {
    return $type === 'pkp' ? 'pkp' : 'kp';
}

function documentsVersionRows(PDO $db, int $templateId): array {
    $st = $db->prepare("SELECT id, template_id, version_no, version_name, source_quote_id, document_type, page_format, theme_name, created_by, created_at
                          FROM documents_template_versions
                         WHERE template_id = ?
                      ORDER BY version_no DESC, id DESC");
    $st->execute([$templateId]);
    return $st->fetchAll();
}

function documentsUploadDir(): string {
    $dir = realpath(__DIR__ . '/..');
    if ($dir === false) $dir = dirname(__DIR__);
    $target = $dir . DIRECTORY_SEPARATOR . 'uploads' . DIRECTORY_SEPARATOR . 'documents';
    if (!is_dir($target) && !mkdir($target, 0775, true)) {
        jsonResponse(['error' => 'Не удалось создать папку для файлов'], 500);
    }
    return $target;
}

function documentsHandleImageUpload(array $user): array {
    accessAssert($user, 'documents', accessCan($user, 'documents', 'edit') ? 'edit' : 'create');
    if (empty($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'])) {
        jsonResponse(['error' => 'Файл не загружен'], 400);
    }
    $file = $_FILES['file'];
    if (($file['error'] ?? UPLOAD_ERR_OK) !== UPLOAD_ERR_OK) {
        jsonResponse(['error' => 'Ошибка загрузки файла'], 400);
    }
    if (intval($file['size'] ?? 0) <= 0 || intval($file['size'] ?? 0) > 10 * 1024 * 1024) {
        jsonResponse(['error' => 'Размер изображения должен быть до 10 МБ'], 400);
    }
    $tmp = (string)$file['tmp_name'];
    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $mime = (string)$finfo->file($tmp);
    $map = [
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif'
    ];
    if (!isset($map[$mime])) {
        jsonResponse(['error' => 'Поддерживаются только JPG, PNG, WEBP и GIF'], 400);
    }
    $baseDir = documentsUploadDir();
    $subDir = date('Y') . DIRECTORY_SEPARATOR . date('m');
    $targetDir = $baseDir . DIRECTORY_SEPARATOR . $subDir;
    if (!is_dir($targetDir) && !mkdir($targetDir, 0775, true)) {
        jsonResponse(['error' => 'Не удалось создать папку для изображения'], 500);
    }
    $realBase = realpath($baseDir);
    $realTargetDir = realpath($targetDir);
    if (!$realBase || !$realTargetDir || strpos($realTargetDir, $realBase) !== 0) {
        jsonResponse(['error' => 'Некорректный путь загрузки'], 500);
    }
    $fileName = 'docimg_' . date('Ymd_His') . '_' . bin2hex(random_bytes(5)) . '.' . $map[$mime];
    $targetPath = $targetDir . DIRECTORY_SEPARATOR . $fileName;
    if (!move_uploaded_file($tmp, $targetPath)) {
        jsonResponse(['error' => 'Не удалось сохранить файл'], 500);
    }
    $rel = 'uploads/documents/' . str_replace(DIRECTORY_SEPARATOR, '/', $subDir) . '/' . $fileName;
    return ['ok' => true, 'path' => $rel, 'url' => $rel, 'mime' => $mime];
}

function documentsBuildTemplateResponse(PDO $db, array $templateRow, ?int $versionId = null): array {
    $templateId = intval($templateRow['id'] ?? 0);
    $versions = documentsVersionRows($db, $templateId);
    $selectedVersion = null;
    if ($versionId > 0) {
        foreach ($versions as $version) {
            if (intval($version['id']) === $versionId) {
                $selectedVersion = $version;
                break;
            }
        }
    }
    if (!$selectedVersion && !empty($templateRow['current_version_id'])) {
        foreach ($versions as $version) {
            if (intval($version['id']) === intval($templateRow['current_version_id'])) {
                $selectedVersion = $version;
                break;
            }
        }
    }
    if (!$selectedVersion && !empty($versions)) $selectedVersion = $versions[0];

    $payload = [];
    if ($selectedVersion) {
        $st = $db->prepare("SELECT payload_json FROM documents_template_versions WHERE id = ? LIMIT 1");
        $st->execute([intval($selectedVersion['id'])]);
        $payload = documentsDecodePayload((string)($st->fetch()['payload_json'] ?? ''));
    } else {
        $payload = documentsDecodePayload((string)($templateRow['payload_json'] ?? ''));
    }

    return [
        'id' => intval($templateRow['id'] ?? 0),
        'user_id' => intval($templateRow['user_id'] ?? 0),
        'source_quote_id' => intval($templateRow['source_quote_id'] ?? 0) ?: null,
        'document_type' => documentsNormalizeType((string)($selectedVersion['document_type'] ?? $templateRow['document_type'] ?? 'kp')),
        'title' => (string)($templateRow['title'] ?? ''),
        'page_format' => (string)($templateRow['page_format'] ?? 'a4'),
        'theme_name' => (string)($templateRow['theme_name'] ?? 'clean'),
        'created_at' => $templateRow['created_at'] ?? null,
        'updated_at' => $templateRow['updated_at'] ?? null,
        'current_version_id' => intval($templateRow['current_version_id'] ?? 0) ?: null,
        'selected_version_id' => $selectedVersion ? intval($selectedVersion['id']) : null,
        'selected_version_name' => $selectedVersion['version_name'] ?? null,
        'payload' => $payload,
        'versions' => $versions
    ];
}

switch ($action) {
    case 'upload_image':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        jsonResponse(documentsHandleImageUpload($user));
        break;

    case 'list':
        $pagination = paginationFromRequest(30, 150);
        $scopeIds = documentsScopeUserIds($user);
        $whereParts = [];
        $params = [];
        if ($scopeIds) {
            $whereParts[] = "t.user_id IN (" . implode(',', array_fill(0, count($scopeIds), '?')) . ")";
            foreach ($scopeIds as $sid) $params[] = intval($sid);
        }
        $filterType = trim((string)($_GET['document_type'] ?? ''));
        if ($filterType !== '') {
            $whereParts[] = "t.document_type = ?";
            $params[] = documentsNormalizeType($filterType);
        }
        $where = $whereParts ? ("WHERE " . implode(" AND ", $whereParts)) : '';
        $sql = "SELECT t.id, t.user_id, t.source_quote_id, t.document_type, t.title, t.page_format, t.theme_name, t.current_version_id, t.created_at, t.updated_at,
                       cv.version_name AS current_version_name, cv.version_no AS current_version_no,
                       (SELECT COUNT(*) FROM documents_template_versions v WHERE v.template_id = t.id) AS versions_count
                  FROM documents_templates t
             LEFT JOIN documents_template_versions cv ON cv.id = t.current_version_id
                  $where
              ORDER BY t.updated_at DESC, t.id DESC" . paginationLimitSql($pagination);
        $st = $db->prepare($sql);
        $st->execute($params);
        $items = $st->fetchAll();
        if ($pagination) {
            $countFrom = "FROM documents_templates t $where";
            jsonResponse(paginationPayload($items, paginationCount($db, $countFrom, $params), $pagination));
        }
        jsonResponse($items);
        break;

    case 'detail':
        $id = intval($_GET['id'] ?? 0);
        $versionId = intval($_GET['version_id'] ?? 0);
        if ($id <= 0) jsonResponse(['error' => 'Invalid id'], 400);
        $st = $db->prepare("SELECT id, user_id, source_quote_id, document_type, title, page_format, theme_name, payload_json, current_version_id, created_at, updated_at FROM documents_templates WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $row = $st->fetch();
        if (!$row) jsonResponse(['error' => 'Not found'], 404);
        documentsAssertTemplateAccess($user, $row);
        jsonResponse(documentsBuildTemplateResponse($db, $row, $versionId ?: null));
        break;

    case 'save':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        $isEdit = $id > 0;
        accessAssert($user, 'documents', $isEdit ? 'edit' : 'create');

        $title = trim((string)($input['title'] ?? ''));
        if ($title === '') jsonResponse(['error' => 'Название обязательно'], 400);

        $sourceQuoteId = intval($input['source_quote_id'] ?? 0) ?: null;
        $documentType = documentsNormalizeType((string)($input['document_type'] ?? ($input['payload']['document_type'] ?? 'kp')));
        $pageFormat = trim((string)($input['page_format'] ?? 'a4'));
        $themeName = trim((string)($input['theme'] ?? 'clean'));
        $versionName = trim((string)($input['version_name'] ?? ''));
        $payload = is_array($input['payload'] ?? null) ? $input['payload'] : [];
        $payload['id'] = $id;
        $payload['title'] = $title;
        $payload['document_type'] = $documentType;
        $payload['source_quote_id'] = $sourceQuoteId ? strval($sourceQuoteId) : '';
        $payload['page_format'] = $pageFormat;
        $payload['theme'] = $themeName;
        $payloadJson = json_encode($payload, JSON_UNESCAPED_UNICODE);
        $uid = intval($user['id'] ?? 0);

        if ($isEdit) {
            $st = $db->prepare("SELECT id, user_id, source_quote_id, document_type, title, page_format, theme_name, payload_json, current_version_id, created_at, updated_at FROM documents_templates WHERE id = ? LIMIT 1");
            $st->execute([$id]);
            $row = $st->fetch();
            if (!$row) jsonResponse(['error' => 'Not found'], 404);
            documentsAssertTemplateAccess($user, $row);

            $verSt = $db->prepare("SELECT COALESCE(MAX(version_no), 0) FROM documents_template_versions WHERE template_id = ?");
            $verSt->execute([$id]);
            $nextVersionNo = intval($verSt->fetchColumn() ?: 0) + 1;
            if ($versionName === '') $versionName = 'Версия ' . $nextVersionNo;

            $insVer = $db->prepare("INSERT INTO documents_template_versions
                (template_id, version_no, version_name, source_quote_id, document_type, page_format, theme_name, payload_json, created_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
            $insVer->execute([$id, $nextVersionNo, $versionName, $sourceQuoteId, $documentType, $pageFormat, $themeName, $payloadJson, $uid]);
            $currentVersionId = intval($db->lastInsertId());

            $upd = $db->prepare("UPDATE documents_templates
                                    SET source_quote_id = ?, document_type = ?, title = ?, page_format = ?, theme_name = ?, payload_json = ?, current_version_id = ?
                                  WHERE id = ?");
            $upd->execute([$sourceQuoteId, $documentType, $title, $pageFormat, $themeName, $payloadJson, $currentVersionId, $id]);
            jsonResponse(['ok' => true, 'id' => $id, 'version_id' => $currentVersionId, 'version_name' => $versionName]);
        }

        $ins = $db->prepare("INSERT INTO documents_templates
            (user_id, source_quote_id, document_type, title, page_format, theme_name, payload_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)");
        $ins->execute([$uid, $sourceQuoteId, $documentType, $title, $pageFormat, $themeName, $payloadJson]);
        $templateId = intval($db->lastInsertId());
        $versionNo = 1;
        if ($versionName === '') $versionName = 'Версия 1';
        $insVer = $db->prepare("INSERT INTO documents_template_versions
            (template_id, version_no, version_name, source_quote_id, document_type, page_format, theme_name, payload_json, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $insVer->execute([$templateId, $versionNo, $versionName, $sourceQuoteId, $documentType, $pageFormat, $themeName, $payloadJson, $uid]);
        $currentVersionId = intval($db->lastInsertId());
        $db->prepare("UPDATE documents_templates SET current_version_id = ? WHERE id = ?")->execute([$currentVersionId, $templateId]);
        jsonResponse(['ok' => true, 'id' => $templateId, 'version_id' => $currentVersionId, 'version_name' => $versionName]);
        break;

    case 'delete':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        accessAssert($user, 'documents', 'delete');
        $id = intval($input['id'] ?? 0);
        if ($id <= 0) jsonResponse(['error' => 'Invalid id'], 400);
        $st = $db->prepare("SELECT id, user_id, source_quote_id, document_type, title, page_format, theme_name, payload_json, current_version_id, created_at, updated_at FROM documents_templates WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $row = $st->fetch();
        if (!$row) jsonResponse(['error' => 'Not found'], 404);
        documentsAssertTemplateAccess($user, $row);
        $db->prepare("DELETE FROM documents_templates WHERE id = ?")->execute([$id]);
        jsonResponse(['ok' => true]);
        break;
}

jsonResponse(['error' => 'Unknown action'], 400);
