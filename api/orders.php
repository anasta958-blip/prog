<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/access_middleware.php';
require_once __DIR__ . '/../includes/pagination.php';
require_once __DIR__ . '/email.php';

header('Content-Type: application/json; charset=utf-8');
$user   = requireAuth();
$method = $_SERVER['REQUEST_METHOD'];
$input  = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) $input = [];
$action = $_GET['action'] ?? ($input['action'] ?? '');
$role   = $user['role'];
$uid    = $user['id'];

accessMiddlewareAssertAction($user, (string)$action, [
    'next_order_num' => ['space' => 'orders', 'action' => 'create'],
    'save_order' => ['space' => 'orders', 'action' => 'create'],
    'upload_order_invoice' => ['space' => 'orders', 'action' => 'edit'],
    'delete_order_invoice' => ['space' => 'orders', 'action' => 'edit'],
    'update_order' => ['space' => 'orders', 'action' => 'edit'],
    'set_archive_state' => ['space' => 'orders', 'action' => 'delete'],
    'delete_order' => ['space' => 'orders', 'action' => 'delete'],
]);

$db = getDB();

function ordersInvoiceUploadRoot() {
    $root = realpath(__DIR__ . '/..');
    return $root ? $root . DIRECTORY_SEPARATOR . 'uploads' . DIRECTORY_SEPARATOR . 'order-invoices' : null;
}

function ordersInvoiceRelativePath($orderId, $fileName) {
    return 'uploads/order-invoices/' . intval($orderId) . '/' . $fileName;
}

function ordersSafeInvoiceFileName($originalName) {
    $base = pathinfo((string)$originalName, PATHINFO_FILENAME);
    $base = preg_replace('/[^\p{L}\p{N}_\-. ]+/u', '_', $base);
    $base = trim((string)$base, " .\t\n\r\0\x0B");
    if ($base === '') $base = 'invoice';
    return $base . '_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.pdf';
}

function ordersAbsoluteInvoicePath($relativePath) {
    $relativePath = str_replace(['/', '\\'], DIRECTORY_SEPARATOR, (string)$relativePath);
    $relativePath = ltrim($relativePath, DIRECTORY_SEPARATOR);
    $root = realpath(__DIR__ . '/..');
    if (!$root) return null;
    $path = $root . DIRECTORY_SEPARATOR . $relativePath;
    $uploadRoot = ordersInvoiceUploadRoot();
    $dir = realpath(dirname($path));
    if (!$dir || !$uploadRoot || strpos($dir, $uploadRoot) !== 0) return null;
    return $path;
}

function ordersInvoiceTableReady($db) {
    return true;
}

function ordersInvoiceRows($db, $order) {
    $orderId = intval($order['id'] ?? 0);
    $rows = [];
    if (!$orderId || !ordersInvoiceTableReady($db)) return $rows;
    $st = $db->prepare("SELECT " . ordersInvoiceSelectFields() . "
                          FROM order_invoices
                         WHERE order_id=?
                         ORDER BY uploaded_at DESC, id DESC");
    $st->execute([$orderId]);
    return $st->fetchAll();
}

function ordersSelectFields(): string {
    return "id, order_number, address, manager_id, status, created_at, status_order, doc_snapshot, order_type, rop_id, status_changed_by, status_changed_at, client_type, is_archived, archived_at";
}

function ordersSelectFieldsWithAlias(string $alias): string {
    $fields = explode(', ', ordersSelectFields());
    return implode(', ', array_map(static fn($field) => $alias . '.' . $field, $fields));
}

function ordersProductSelectFieldsWithAlias(string $alias): string {
    $fields = [
        'id', 'category_id', 'section_id', 'product_name_id', 'order_id', 'marking', 'size_value',
        'quantity', 'dozakaz', 'unit', 'note', 'komplektaciya', 'supplier', 'address', 'status',
        'created_by', 'created_at', 'updated_at', 'custom_name', 'group_name', 'invoice_check',
        'shipment_status',
    ];
    return implode(', ', array_map(static fn($field) => $alias . '.' . $field, $fields));
}

function ordersInvoiceSelectFields(): string {
    return "id, order_id, file_path, original_name, uploaded_by, uploaded_at";
}

$ROLE_SET_STATUSES = [
    'admin'   => ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
    'manager' => ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
    'rop'     => ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
    'logist'  => ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
    'prorab'  => ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
];

function normalizeCatalogValue($value) {
    return mb_strtolower(trim((string)$value));
}

function canDeleteOrders($user) {
    return accessCan($user, 'orders', 'delete');
}

function ordersIntValue($value, $default = 0) {
    if ($value === null) return intval($default);
    if (is_string($value)) {
        $value = trim($value);
        if ($value === '') return intval($default);
        $value = str_replace(["\xC2\xA0", ' '], '', $value);
        $value = str_replace(',', '.', $value);
    }
    return is_numeric($value) ? intval(round(floatval($value))) : intval($default);
}

function ordersProductsGroupNameSchemaReady($db) {
    return true;
}

function loadItemNameFromCatalog($db, $nameId) {
    static $cache = [];
    $nameId = intval($nameId);
    if (!$nameId) return '';
    if (isset($cache[$nameId])) return $cache[$nameId];
    $st = $db->prepare("SELECT name FROM product_names WHERE id=?");
    $st->execute([$nameId]);
    $cache[$nameId] = trim((string)($st->fetch()['name'] ?? ''));
    return $cache[$nameId];
}

function resolveProductNameCard($db, $item, $isConsumables, $creatorId = 0) {
    $sectionId = intval($item['section_id'] ?? 0);
    $nameId = intval($item['product_name_id'] ?? 0);
    $name = trim((string)($item['custom_name'] ?? $item['name_txt'] ?? ''));
    if (!$name && $nameId) {
        $name = loadItemNameFromCatalog($db, $nameId);
    }
    if (!$sectionId || !$name) {
        return [null, $name, 'Не согласовано'];
    }

    $markingSize = trim((string)($item['marking_size'] ?? $item['size_value'] ?? ''));
    $komplektaciya = $isConsumables ? trim((string)($item['komplektaciya'] ?? '')) : '';
    $unit = trim((string)($item['unit'] ?? getDefaultMeasurementUnitName()));
    $supplier = trim((string)($item['supplier'] ?? ''));
    $groupName = trim((string)($item['group_name'] ?? ''));

    $find = $db->prepare(
        "SELECT id, status
           FROM product_names
          WHERE section_id = ?
            AND LOWER(TRIM(COALESCE(group_name, ''))) = ?
            AND LOWER(TRIM(name)) = ?
            AND LOWER(TRIM(COALESCE(marking_size, ''))) = ?
            AND LOWER(TRIM(COALESCE(unit, ''))) = ?
            AND LOWER(TRIM(COALESCE(supplier, ''))) = ?
          ORDER BY id
          LIMIT 1"
    );
    $find->execute([
        $sectionId,
        normalizeCatalogValue($groupName),
        normalizeCatalogValue($name),
        normalizeCatalogValue($markingSize),
        normalizeCatalogValue($unit),
        normalizeCatalogValue($supplier),
    ]);
    $row = $find->fetch();
    if ($row) {
        return [intval($row['id']), $name, $row['status'] ?: 'Не согласовано'];
    }

    $db->prepare(
        "INSERT INTO product_names (section_id, group_name, name, is_custom, status, supplier, marking_size, komplektaciya, unit, created_by)
         VALUES (?,?,?,?,?,?,?,?,?,?)"
    )->execute([
        $sectionId,
        $groupName !== '' ? $groupName : null,
        $name,
        $nameId ? 0 : 1,
        'Не согласовано',
        $supplier,
        $markingSize,
        $komplektaciya ?: null,
        $unit,
        intval($creatorId) ?: null,
    ]);

    return [intval($db->lastInsertId()), $name, 'Не согласовано'];
}

function insertOrderProducts($db, $items, $orderId, $address, $managerId) {
    $hasProductGroupName = ordersProductsGroupNameSchemaReady($db);
    $insertProduct = $hasProductGroupName
        ? $db->prepare("
            INSERT INTO products
                (category_id, section_id, product_name_id, custom_name, group_name, order_id,
                 marking, size_value, quantity, dozakaz, unit, note,
                 komplektaciya, supplier, address, status, invoice_check, shipment_status, created_by)
            VALUES
                (:category_id, :section_id, :product_name_id, :custom_name, :group_name, :order_id,
                 :marking, :size_value, :quantity, :dozakaz, :unit, :note,
                 :komplektaciya, :supplier, :address, :status, :invoice_check, :shipment_status, :created_by)
        ")
        : $db->prepare("
            INSERT INTO products
                (category_id, section_id, product_name_id, custom_name, order_id,
                 marking, size_value, quantity, dozakaz, unit, note,
                 komplektaciya, supplier, address, status, invoice_check, shipment_status, created_by)
            VALUES
                (:category_id, :section_id, :product_name_id, :custom_name, :order_id,
                 :marking, :size_value, :quantity, :dozakaz, :unit, :note,
                 :komplektaciya, :supplier, :address, :status, :invoice_check, :shipment_status, :created_by)
        ");

    foreach ($items as $item) {
        $catStmt = $db->prepare("SELECT code FROM categories WHERE id = ?");
        $catStmt->execute([intval($item['category_id'] ?? 0)]);
        $cat = $catStmt->fetch();
        if (!$cat) continue;
        $isConsumables = $cat['code'] === 'consumables';

        [$resolvedNameId, $resolvedName, $catalogStatus] = resolveProductNameCard($db, $item, $isConsumables, $managerId);
        $customName = $resolvedNameId ? null : ($resolvedName ?: trim((string)($item['custom_name'] ?? '')));

        $params = [
            'category_id'     => intval($item['category_id'] ?? 0),
            'section_id'      => intval($item['section_id'] ?? 0),
            'product_name_id' => $resolvedNameId,
            'custom_name'     => $customName ?: null,
            'order_id'        => $orderId,
            'marking'         => trim((string)($item['marking'] ?? $item['marking_size'] ?? '')),
            'size_value'      => trim((string)($item['size_value'] ?? $item['marking_size'] ?? '')),
            'quantity'        => ordersIntValue($item['quantity'] ?? 0),
            'dozakaz'         => intval($item['dozakaz'] ?? 0),
            'unit'            => trim((string)($item['unit'] ?? getDefaultMeasurementUnitName())),
            'note'            => trim((string)($item['note'] ?? '')),
            'komplektaciya'   => $isConsumables ? trim((string)($item['komplektaciya'] ?? '')) : null,
            'supplier'        => trim((string)($item['supplier'] ?? '')),
            'address'         => $address,
            'status'          => $catalogStatus === 'Согласовано' ? 'Согласовано' : 'Не согласовано',
            'invoice_check'   => $item['invoice_check'] ?? '',
            'shipment_status' => $item['shipment_status'] ?? '',
            'created_by'      => $managerId,
        ];
        if ($hasProductGroupName) {
            $groupName = trim((string)($item['group_name'] ?? ''));
            $params['group_name'] = $groupName !== '' ? $groupName : null;
        }
        $insertProduct->execute($params);
    }
}

function applyOrderAccessScope(&$where, &$params, $user) {
    $ids = accessResolveScopeUserIds($user, 'orders');
    if (!$ids) return;
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $where[] = "(o.manager_id IN ($placeholders) OR o.rop_id IN ($placeholders))";
    foreach ($ids as $id) $params[] = intval($id);
    foreach ($ids as $id) $params[] = intval($id);
}

function assertOrderAccess($user, $order) {
    if (($user['role'] ?? '') === 'admin') return;
    $ids = accessResolveScopeUserIds($user, 'orders');
    if (!$ids) return;
    $managerId = intval($order['manager_id'] ?? 0);
    $ropId = intval($order['rop_id'] ?? 0);
    if (in_array($managerId, $ids, true) || in_array($ropId, $ids, true)) return;
    jsonResponse(['error' => 'Forbidden'], 403);
}

function ordersDecodeJsonField($value) {
    if (!$value) return [];
    $data = json_decode((string)$value, true);
    return is_array($data) ? $data : [];
}

function ordersEncodeJsonField($value) {
    return json_encode(is_array($value) ? $value : [], JSON_UNESCAPED_UNICODE);
}

function ordersBuildWorkflowChangedMeta($user, $workflowStatus) {
    return [
        'workflow_status' => (string)$workflowStatus,
        'changed_at' => date('Y-m-d H:i:s'),
        'user_id' => intval($user['id'] ?? 0),
        'login' => (string)($user['username'] ?? $user['login'] ?? ''),
        'role' => (string)($user['role'] ?? ''),
        'full_name' => (string)($user['full_name'] ?? ''),
    ];
}

function ordersCompanyTypeLabel($type) {
    $map = [
        'person' => 'Физ лицо',
        'ip' => 'ИП',
        'ooo' => 'ООО',
    ];
    $type = trim((string)$type);
    return $map[$type] ?? ($type !== '' ? $type : '—');
}

function ordersExtractQuoteMeta($quote, $payload = null) {
    $payload = is_array($payload) ? $payload : ordersDecodeJsonField($quote['payload_json'] ?? null);
    $client = ordersDecodeJsonField($quote['client_snapshot_json'] ?? null);
    $meta = is_array($payload['quote_meta'] ?? null) ? $payload['quote_meta'] : [];
    return [
        'object_address' => trim((string)($meta['object_address'] ?? ($client['object_address'] ?? ''))),
    ];
}

function ordersSendFinalPaymentWorkflowEmail($quote, $payload) {
    $to = 't2bjzxzyeu8vmbg3w0cc@task.yougile.com';
    $meta = ordersExtractQuoteMeta($quote, $payload);
    $client = ordersDecodeJsonField($quote['client_snapshot_json'] ?? null);

    $address = trim((string)($meta['object_address'] ?? ''));
    $quoteNumber = intval($quote['id'] ?? 0);
    $clientType = ordersCompanyTypeLabel($client['company_type'] ?? '');
    $clientName = trim((string)($client['company_name'] ?? ''));

    $subject = implode(' | ', [
        'Получить финальную оплату',
        'Адрес: ' . ($address !== '' ? $address : '—'),
        'КП #' . $quoteNumber,
        'Тип клиента: ' . $clientType,
        'Клиент: ' . ($clientName !== '' ? $clientName : '—'),
    ]);

    $messageBody = '<h2>Карточка КП переведена в статус "Получить финальную оплату"</h2>'
        . '<table style="border-collapse:collapse;font-family:Arial,sans-serif">'
        . '<tr><td style="padding:6px 12px 6px 0"><strong>Адрес</strong></td><td style="padding:6px 0">' . htmlspecialchars($address !== '' ? $address : '—', ENT_QUOTES, 'UTF-8') . '</td></tr>'
        . '<tr><td style="padding:6px 12px 6px 0"><strong>Номер КП</strong></td><td style="padding:6px 0">#' . $quoteNumber . '</td></tr>'
        . '<tr><td style="padding:6px 12px 6px 0"><strong>Тип клиента</strong></td><td style="padding:6px 0">' . htmlspecialchars($clientType, ENT_QUOTES, 'UTF-8') . '</td></tr>'
        . '<tr><td style="padding:6px 12px 6px 0"><strong>Клиент</strong></td><td style="padding:6px 0">' . htmlspecialchars($clientName !== '' ? $clientName : '—', ENT_QUOTES, 'UTF-8') . '</td></tr>'
        . '</table>';

    if (!sendSimpleEmail($to, $subject, $messageBody)) {
        throw new RuntimeException('Не удалось отправить письмо для финальной оплаты КП');
    }
}

function ordersMoveQuoteToFinalPayment($db, $orderId, $user) {
    $orderId = intval($orderId);
    if (!$orderId) return;

    $quote = ordersFindLinkedQuoteByOrderId($db, $orderId);
    if (!$quote) return;

    $payload = ordersDecodeJsonField($quote['payload_json'] ?? null);
    $payload['last_workflow_change'] = ordersBuildWorkflowChangedMeta($user, 'Получить финальную оплату');
    ordersSendFinalPaymentWorkflowEmail($quote, $payload);

    $db->prepare("UPDATE kp_quotes SET workflow_status = ?, payload_json = ? WHERE id = ? AND user_id = ?")
       ->execute(['Получить финальную оплату', ordersEncodeJsonField($payload), intval($quote['id']), intval($quote['user_id'])]);
}

function ordersFindLinkedQuoteByOrderId($db, $orderId) {
    $orderId = intval($orderId);
    if (!$orderId) return null;
    $st = $db->prepare("SELECT id, user_id, workflow_status, payload_json, created_order_id
                          FROM kp_quotes
                         WHERE created_order_id = ?
                         ORDER BY id DESC
                         LIMIT 1");
    $st->execute([$orderId]);
    return $st->fetch() ?: null;
}

function ordersFindLinkedQuotesByOrderIds($db, array $orderIds): array {
    $orderIds = array_values(array_unique(array_filter(array_map('intval', $orderIds))));
    if (!$orderIds) return [];
    $found = [];
    $placeholders = implode(',', array_fill(0, count($orderIds), '?'));

    $st = $db->prepare("SELECT id, user_id, workflow_status, payload_json, created_order_id
                        FROM kp_quotes
                       WHERE created_order_id IN ($placeholders)
                       ORDER BY id DESC");
    $st->execute($orderIds);
    foreach ($st->fetchAll() as $quote) {
        $orderId = intval($quote['created_order_id'] ?? 0);
        if (!$orderId || isset($found[$orderId])) continue;
        $found[$orderId] = $quote;
    }
    return $found;
}

function ordersHideFromOrdersList($db, $order, ?array $linkedQuotes = null) {
    if (!is_array($order)) return false;
    $orderId = intval($order['id'] ?? 0);
    $quote = $linkedQuotes !== null
        ? ($linkedQuotes[$orderId] ?? null)
        : ordersFindLinkedQuoteByOrderId($db, $orderId);
    if (!$quote) return false;

    $orderStatus = trim((string)($order['status_order'] ?? ''));
    if (in_array($orderStatus, ['Монтаж завершён', 'Выполнено'], true)) return true;

    $quoteStatus = trim((string)($quote['workflow_status'] ?? ''));
    return in_array($quoteStatus, ['Получить финальную оплату', 'Оплата получена', 'Выполненные монтажи', 'Вторые этапы'], true);
}

function ordersMoveQuoteToCompletedMontage($db, $orderId, $user) {
    $quote = ordersFindLinkedQuoteByOrderId($db, $orderId);
    if (!$quote) return false;

    $payload = ordersDecodeJsonField($quote['payload_json'] ?? null);
    $payload['last_workflow_change'] = ordersBuildWorkflowChangedMeta($user, 'Получить финальную оплату');
    ordersSendFinalPaymentWorkflowEmail($quote, $payload);

    $db->prepare("UPDATE kp_quotes SET workflow_status = ?, payload_json = ? WHERE id = ? AND user_id = ?")
       ->execute(['Получить финальную оплату', ordersEncodeJsonField($payload), intval($quote['id']), intval($quote['user_id'])]);

    return true;
}

switch ($action) {

    case 'next_order_num':
        accessAssert($user, 'orders', 'create');
        $orderType = $_GET['order_type'] ?? '';
        $TYPE_PREFIXES = ['bytovoy' => 'Б-', 'dom_komforta' => 'ДК-', 'turkov' => 'Т-', 'sergey' => 'С-'];
        $prefix = $TYPE_PREFIXES[$orderType] ?? '';
        $seqNum = getNextOrderNumber($orderType ?: null);
        jsonResponse(['order_number' => $prefix . $seqNum]);
        break;

    case 'save_order':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        accessAssert($user, 'orders', 'create');

        $address    = trim((string)($input['address'] ?? ''));
        $orderType  = $input['order_type'] ?? null;
        $clientType = trim((string)($input['client_type'] ?? ''));
        $snapshot   = isset($input['snapshot']) ? json_encode($input['snapshot'], JSON_UNESCAPED_UNICODE) : null;
        $items      = $input['items'] ?? [];

        if (!$address) jsonResponse(['error' => 'Адрес обязателен'], 400);
        if (empty($items)) jsonResponse(['error' => 'Нет товаров'], 400);

        $ropId = getManagerRop($uid);

        $TYPE_PREFIXES = ['bytovoy' => 'Б-', 'dom_komforta' => 'ДК-', 'turkov' => 'Т-', 'sergey' => 'С-'];
        $prefix = $TYPE_PREFIXES[$orderType] ?? '';
        $seqNum = getNextOrderNumber($orderType);
        $orderNum = $prefix . $seqNum;

        $db->beginTransaction();
        try {
            $db->prepare("INSERT INTO orders (order_number, address, manager_id, rop_id, order_type, client_type, status_order, doc_snapshot)
                          VALUES (?,?,?,?,?,?,'Составление комплектации',?)")
               ->execute([$orderNum, $address, $uid, $ropId, $orderType, $clientType, $snapshot]);
            $orderId = $db->lastInsertId();
            insertOrderProducts($db, $items, $orderId, $address, $uid);
            $db->commit();
            jsonResponse(['ok' => true, 'order_number' => $orderNum, 'order_id' => $orderId]);
        } catch (Exception $e) {
            $db->rollBack();
            jsonResponse(['error' => 'Ошибка: ' . $e->getMessage()], 500);
        }
        break;

    case 'orders':
        $pagination = paginationFromRequest(50, 200);
        $where  = ['1=1'];
        $params = [];
        applyOrderAccessScope($where, $params, $user);

        $filterSt = $_GET['status'] ?? '';
        if ($filterSt) {
            $where[] = 'o.status_order = ?';
            $params[] = $filterSt;
        }

        $search = trim((string)($_GET['search'] ?? ''));
        if ($search) {
            $where[] = '(o.address LIKE ? OR o.order_number LIKE ?)';
            $params[] = '%' . $search . '%';
            $params[] = '%' . $search . '%';
        }

        $sql = "SELECT " . ordersSelectFieldsWithAlias('o') . ", u.full_name as manager_name,
                    ur.full_name as rop_name,
                    us.username as status_changed_by_login,
                    us.role as status_changed_by_role,
                    us.full_name as status_changed_by_name,
                    COUNT(p.id) as product_count
                FROM orders o
                JOIN users u ON u.id = o.manager_id
                LEFT JOIN users ur ON ur.id = o.rop_id
                LEFT JOIN users us ON us.id = o.status_changed_by
                LEFT JOIN products p ON p.order_id = o.id
                WHERE " . implode(' AND ', $where) . "
                GROUP BY o.id
                ORDER BY o.created_at DESC";
        $st = $db->prepare($sql);
        $st->execute($params);
        $rows = $st->fetchAll();
        $linkedQuotes = ordersFindLinkedQuotesByOrderIds($db, array_column($rows, 'id'));
        $rows = array_values(array_filter($rows, function ($row) use ($db, $linkedQuotes) {
            return !ordersHideFromOrdersList($db, $row, $linkedQuotes);
        }));
        if ($pagination) {
            $total = count($rows);
            $rows = array_slice($rows, intval($pagination['offset']), intval($pagination['per_page']));
            jsonResponse(paginationPayload($rows, $total, $pagination));
        }
        jsonResponse($rows);
        break;

    case 'upload_order_invoice':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        accessAssert($user, 'orders', 'edit');
        $id = intval($_POST['id'] ?? ($_GET['id'] ?? 0));
        if (!$id) jsonResponse(['error' => 'id required'], 400);

        $st = $db->prepare("SELECT " . ordersSelectFields() . " FROM orders WHERE id=?");
        $st->execute([$id]);
        $order = $st->fetch();
        if (!$order) jsonResponse(['error' => 'Not found'], 404);
        assertOrderAccess($user, $order);
        if (!ordersInvoiceTableReady($db)) jsonResponse(['error' => 'Таблица счетов не создана'], 500);

        if (empty($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'])) {
            jsonResponse(['error' => 'Файл не выбран'], 400);
        }
        $file = $_FILES['file'];
        if (($file['error'] ?? UPLOAD_ERR_OK) !== UPLOAD_ERR_OK) {
            jsonResponse(['error' => 'Ошибка загрузки файла'], 400);
        }
        if (intval($file['size'] ?? 0) <= 0 || intval($file['size'] ?? 0) > 25 * 1024 * 1024) {
            jsonResponse(['error' => 'Размер PDF должен быть до 25 МБ'], 400);
        }
        $originalName = (string)($file['name'] ?? 'invoice.pdf');
        if (mb_strtolower(pathinfo($originalName, PATHINFO_EXTENSION)) !== 'pdf') {
            jsonResponse(['error' => 'Можно загрузить только PDF'], 400);
        }
        $mime = '';
        if (function_exists('finfo_open')) {
            $finfo = finfo_open(FILEINFO_MIME_TYPE);
            if ($finfo) {
                $mime = (string)finfo_file($finfo, $file['tmp_name']);
                finfo_close($finfo);
            }
        }
        $head = file_get_contents($file['tmp_name'], false, null, 0, 4);
        if ($mime && $mime !== 'application/pdf' && $head !== '%PDF') {
            jsonResponse(['error' => 'Файл не похож на PDF'], 400);
        }
        if ($head !== '%PDF') {
            jsonResponse(['error' => 'Файл не похож на PDF'], 400);
        }

        $root = ordersInvoiceUploadRoot();
        if (!$root) jsonResponse(['error' => 'Некорректная папка загрузки'], 500);
        if (!is_dir($root) && !mkdir($root, 0775, true)) {
            jsonResponse(['error' => 'Не удалось создать папку для счетов'], 500);
        }
        $dir = $root . DIRECTORY_SEPARATOR . $id;
        if (!is_dir($dir) && !mkdir($dir, 0775, true)) {
            jsonResponse(['error' => 'Не удалось создать папку для счёта'], 500);
        }
        $realRoot = realpath($root);
        $realDir = realpath($dir);
        if (!$realRoot || !$realDir || strpos($realDir, $realRoot) !== 0) {
            jsonResponse(['error' => 'Некорректный путь загрузки'], 500);
        }
        $fileName = ordersSafeInvoiceFileName($originalName);
        $target = $dir . DIRECTORY_SEPARATOR . $fileName;
        if (!move_uploaded_file($file['tmp_name'], $target)) {
            jsonResponse(['error' => 'Не удалось сохранить файл'], 500);
        }

        $relativePath = ordersInvoiceRelativePath($id, $fileName);
        $uploadedAt = date('Y-m-d H:i:s');
        $db->prepare("INSERT INTO order_invoices (order_id, file_path, original_name, uploaded_by, uploaded_at)
                      VALUES (?, ?, ?, ?, ?)")
           ->execute([$id, $relativePath, $originalName, $uid, $uploadedAt]);
        jsonResponse([
            'ok' => true,
            'invoices' => ordersInvoiceRows($db, $order),
        ]);
        break;

    case 'order_invoice_pdf':
        $id = intval($_GET['id'] ?? 0);
        $invoiceId = intval($_GET['invoice_id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);

        $st = $db->prepare("SELECT " . ordersSelectFields() . " FROM orders WHERE id=?");
        $st->execute([$id]);
        $order = $st->fetch();
        if (!$order) jsonResponse(['error' => 'Not found'], 404);
        assertOrderAccess($user, $order);

        $invoice = null;
        if ($invoiceId && ordersInvoiceTableReady($db)) {
            $iSt = $db->prepare("SELECT " . ordersInvoiceSelectFields() . " FROM order_invoices WHERE id=? AND order_id=?");
            $iSt->execute([$invoiceId, $id]);
            $invoice = $iSt->fetch();
        } else {
            $rows = ordersInvoiceRows($db, $order);
            $invoice = $rows[0] ?? null;
        }
        if (!$invoice) jsonResponse(['error' => 'Счёт не загружен'], 404);

        $path = ordersAbsoluteInvoicePath($invoice['file_path']);
        if (!$path || !is_file($path)) jsonResponse(['error' => 'Файл счёта не найден'], 404);

        header_remove('Content-Type');
        header('Content-Type: application/pdf');
        $downloadName = $invoice['original_name'] ?: 'invoice.pdf';
        header('Content-Disposition: inline; filename="invoice.pdf"; filename*=UTF-8\'\'' . rawurlencode($downloadName));
        header('Content-Length: ' . filesize($path));
        readfile($path);
        exit;

    case 'delete_order_invoice':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        accessAssert($user, 'orders', 'edit');
        $id = intval($input['id'] ?? 0);
        $invoiceId = intval($input['invoice_id'] ?? 0);
        if (!$id || !$invoiceId) jsonResponse(['error' => 'id required'], 400);
        if (!ordersInvoiceTableReady($db)) jsonResponse(['error' => 'Таблица счетов не создана'], 500);

        $st = $db->prepare("SELECT " . ordersSelectFields() . " FROM orders WHERE id=?");
        $st->execute([$id]);
        $order = $st->fetch();
        if (!$order) jsonResponse(['error' => 'Not found'], 404);
        assertOrderAccess($user, $order);

        $iSt = $db->prepare("SELECT " . ordersInvoiceSelectFields() . " FROM order_invoices WHERE id=? AND order_id=?");
        $iSt->execute([$invoiceId, $id]);
        $invoice = $iSt->fetch();
        if (!$invoice) jsonResponse(['error' => 'Счёт не найден'], 404);

        $path = ordersAbsoluteInvoicePath($invoice['file_path']);
        if ($path && is_file($path) && !unlink($path)) {
            error_log('Не удалось удалить файл счёта: ' . $path);
        }
        $db->prepare("DELETE FROM order_invoices WHERE id=? AND order_id=?")->execute([$invoiceId, $id]);

        $rows = ordersInvoiceRows($db, $order);
        jsonResponse(['ok' => true, 'invoices' => $rows]);
        break;

    case 'order_detail':
        $id = intval($_GET['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);

        $st = $db->prepare("SELECT " . ordersSelectFieldsWithAlias('o') . ", u.full_name as manager_name, ur.full_name as rop_name,
                                    us.username as status_changed_by_login, us.role as status_changed_by_role,
                                    us.full_name as status_changed_by_name
                               FROM orders o
                               JOIN users u ON u.id=o.manager_id
                               LEFT JOIN users ur ON ur.id=o.rop_id
                               LEFT JOIN users us ON us.id=o.status_changed_by
                              WHERE o.id=?");
        $st->execute([$id]);
        $order = $st->fetch();
        if (!$order) jsonResponse(['error' => 'Not found'], 404);
        assertOrderAccess($user, $order);

        $order['doc_snapshot'] = $order['doc_snapshot'] ? json_decode($order['doc_snapshot'], true) : null;

        $pSt = $db->prepare("SELECT " . ordersProductSelectFieldsWithAlias('p') . ", COALESCE(pn.name, p.custom_name) as product_name
                               FROM products p
                               LEFT JOIN product_names pn ON pn.id = p.product_name_id
                              WHERE p.order_id = ?
                              ORDER BY p.id");
        $pSt->execute([$id]);
        $order['products'] = $pSt->fetchAll();
        $order['invoices'] = ordersInvoiceRows($db, $order);

        jsonResponse($order);
        break;

    case 'update_order':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);

        $st = $db->prepare("SELECT " . ordersSelectFields() . " FROM orders WHERE id=?");
        $st->execute([$id]);
        $order = $st->fetch();
        if (!$order) jsonResponse(['error' => 'Not found'], 404);
        assertOrderAccess($user, $order);
        accessAssert($user, 'orders', 'edit');

        $address     = trim((string)($input['address'] ?? $order['address']));
        $statusOrder = $input['status_order'] ?? $order['status_order'];
        $snapshot    = isset($input['snapshot']) ? json_encode($input['snapshot'], JSON_UNESCAPED_UNICODE) : null;
        $items       = $input['items'] ?? null;
        $orderNumber = trim((string)($input['order_number'] ?? $order['order_number']));
        $orderType   = $input['order_type'] ?? $order['order_type'];
        $clientType  = isset($input['client_type']) ? trim((string)$input['client_type']) : ($order['client_type'] ?? '');

        $allowedSet = $ROLE_SET_STATUSES[$role] ?? [];
        if (!empty($allowedSet) && !in_array($statusOrder, $allowedSet, true)) {
            jsonResponse(['error' => 'Статус недоступен для вашей роли: ' . $statusOrder], 403);
        }

        $db->beginTransaction();
        try {
            $statusChangedBy = null;
            $statusChangedAt = null;
            $hiddenInOrders = false;
            if ($statusOrder !== $order['status_order']) {
                $statusChangedBy = $uid;
                $statusChangedAt = date('Y-m-d H:i:s');
            }

            if ($snapshot !== null) {
                if ($statusChangedBy !== null) {
                    $db->prepare("UPDATE orders
                                     SET address=?, status_order=?, order_number=?, order_type=?, client_type=?, doc_snapshot=?, status_changed_by=?, status_changed_at=?
                                   WHERE id=?")
                       ->execute([$address, $statusOrder, $orderNumber, $orderType, $clientType, $snapshot, $statusChangedBy, $statusChangedAt, $id]);
                } else {
                    $db->prepare("UPDATE orders
                                     SET address=?, status_order=?, order_number=?, order_type=?, client_type=?, doc_snapshot=?
                                   WHERE id=?")
                       ->execute([$address, $statusOrder, $orderNumber, $orderType, $clientType, $snapshot, $id]);
                }
            } else {
                if ($statusChangedBy !== null) {
                    $db->prepare("UPDATE orders
                                     SET address=?, status_order=?, order_number=?, order_type=?, client_type=?, status_changed_by=?, status_changed_at=?
                                   WHERE id=?")
                       ->execute([$address, $statusOrder, $orderNumber, $orderType, $clientType, $statusChangedBy, $statusChangedAt, $id]);
                } else {
                    $db->prepare("UPDATE orders
                                     SET address=?, status_order=?, order_number=?, order_type=?, client_type=?
                                   WHERE id=?")
                       ->execute([$address, $statusOrder, $orderNumber, $orderType, $clientType, $id]);
                }
            }

            if ($items !== null) {
                $db->prepare("DELETE FROM products WHERE order_id=?")->execute([$id]);
                insertOrderProducts($db, $items, $id, $address, $order['manager_id']);
            }

            if (!empty($input['product_updates']) && is_array($input['product_updates'])) {
                $upd = $db->prepare("UPDATE products SET invoice_check=?, shipment_status=? WHERE id=? AND order_id=?");
                foreach ($input['product_updates'] as $pu) {
                    $upd->execute([
                        $pu['invoice_check'] ?? '',
                        $pu['shipment_status'] ?? '',
                        intval($pu['id']),
                        $id,
                    ]);
                }
            }

            if ($statusOrder !== $order['status_order'] && $statusOrder === 'Монтаж завершён') {
                $hiddenInOrders = ordersMoveQuoteToCompletedMontage($db, $id, $user);
            }

            $db->commit();
            jsonResponse(['ok' => true, 'hidden_in_orders' => $hiddenInOrders]);
        } catch (Exception $e) {
            $db->rollBack();
            jsonResponse(['error' => 'Ошибка: ' . $e->getMessage()], 500);
        }
        break;

    case 'set_archive_state':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);
        $archived = !empty($input['archived']) ? 1 : 0;

        $st = $db->prepare("SELECT " . ordersSelectFields() . " FROM orders WHERE id=?");
        $st->execute([$id]);
        $order = $st->fetch();
        if (!$order) jsonResponse(['error' => 'Not found'], 404);
        assertOrderAccess($user, $order);
        accessAssert($user, 'orders', 'edit');

        $db->prepare("UPDATE orders SET is_archived = ?, archived_at = ? WHERE id = ?")
           ->execute([$archived, $archived ? date('Y-m-d H:i:s') : null, $id]);
        jsonResponse(['ok' => true]);
        break;

    case 'delete_order':
        if ($method !== 'POST') jsonResponse(['error' => 'POST required'], 405);
        accessAssert($user, 'orders', 'delete');
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);

        $st = $db->prepare("SELECT " . ordersSelectFields() . " FROM orders WHERE id=?");
        $st->execute([$id]);
        $order = $st->fetch();
        if (!$order) jsonResponse(['error' => 'Not found'], 404);
        assertOrderAccess($user, $order);

        $db->beginTransaction();
        try {
            $db->prepare("DELETE FROM products WHERE order_id=?")->execute([$id]);
            $db->prepare("DELETE FROM orders WHERE id=?")->execute([$id]);
            $db->commit();
            jsonResponse(['ok' => true]);
        } catch (Exception $e) {
            $db->rollBack();
            jsonResponse(['error' => 'Ошибка: ' . $e->getMessage()], 500);
        }
        break;

    default:
        jsonResponse(['error' => 'Unknown action'], 400);
}
