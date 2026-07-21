<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/access_middleware.php';
require_once __DIR__ . '/../includes/pagination.php';

header('Content-Type: application/json; charset=utf-8');
$user   = requireAuth();
$method = $_SERVER['REQUEST_METHOD'];
$input  = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) $input = [];
$action = $_GET['action'] ?? ($input['action'] ?? '');
$role   = $user['role'];
$uid    = intval($user['id'] ?? 0);

accessMiddlewareAssertAction($user, (string)$action, [
    'save_group' => ['space_any' => [['settings', 'create'], ['settings', 'edit']]],
    'delete_group' => ['space' => 'settings', 'action' => 'delete'],
    'save_unit' => ['space_any' => [['settings', 'create'], ['settings', 'edit']]],
    'delete_unit' => ['space' => 'settings', 'action' => 'delete'],
    'save_supplier' => ['space_any' => [['settings', 'create'], ['settings', 'edit']]],
    'delete_supplier' => ['space' => 'settings', 'action' => 'delete'],
    'import_catalog_excel' => ['space' => 'catalog', 'action' => 'create'],
    'create_name' => ['space' => 'catalog', 'action' => 'create'],
    'update_name' => ['space' => 'catalog', 'action' => 'edit'],
    'delete_name' => ['space' => 'catalog', 'action' => 'delete'],
    'delete_product' => ['space' => 'catalog', 'action' => 'delete'],
    'create_service' => ['space' => 'catalog', 'action' => 'create'],
    'update_service' => ['space' => 'catalog', 'action' => 'edit'],
    'delete_service' => ['space' => 'catalog', 'action' => 'delete'],
]);

$db = getDB();

const CATALOG_DEFAULT_PER_PAGE = 25;
const CATALOG_MAX_PER_PAGE = 300;

function catalogSectionSelectFieldsWithAlias(string $alias): string {
    $fields = ['id', 'category_id', 'code', 'name', 'sort_order'];
    return implode(', ', array_map(static fn($field) => $alias . '.' . $field, $fields));
}

function catalogGroupSelectFieldsWithAlias(string $alias): string {
    $fields = ['id', 'section_id', 'name', 'sort_order', 'created_at'];
    return implode(', ', array_map(static fn($field) => $alias . '.' . $field, $fields));
}

function catalogProductNameSelectFieldsWithAlias(string $alias): string {
    $fields = [
        'id', 'section_id', 'group_name', 'name', 'sort_order', 'created_by', 'created_at',
        'is_custom', 'status', 'supplier', 'marking_size', 'komplektaciya', 'note', 'unit', 'purchase_price',
        'retail_price', 'price_type', 'discount_value', 'labor_price', 'minimal_price', 'linked_service_id',
        'technical_note',
    ];
    return implode(', ', array_map(static fn($field) => $alias . '.' . $field, $fields));
}

function catalogProductSelectFieldsWithAlias(string $alias): string {
    $fields = [
        'id', 'category_id', 'section_id', 'product_name_id', 'order_id', 'marking', 'size_value',
        'quantity', 'dozakaz', 'unit', 'note', 'komplektaciya', 'supplier', 'address', 'status',
        'created_by', 'created_at', 'updated_at', 'custom_name', 'group_name', 'invoice_check',
        'shipment_status',
    ];
    return implode(', ', array_map(static fn($field) => $alias . '.' . $field, $fields));
}

function canManageCatalog($user) {
    if (!$user) return false;
    if (($user['role'] ?? '') === 'admin') return true;
    return accessCan($user, 'catalog', 'create') || accessCan($user, 'catalog', 'edit') || accessCan($user, 'catalog', 'delete');
}

function canDeleteCatalog($user) {
    return accessCan($user, 'catalog', 'delete');
}

function canManageSettingsCatalog($user) {
    if (!$user) return false;
    if (($user['role'] ?? '') === 'admin') return true;
    return accessCan($user, 'settings', 'create') || accessCan($user, 'settings', 'edit') || accessCan($user, 'settings', 'delete');
}

function catalogNullableInt($value) {
    $value = trim((string)$value);
    if ($value === '') return null;
    $value = str_replace(["\xC2\xA0", ' '], '', $value);
    $value = str_replace(',', '.', $value);
    return is_numeric($value) ? intval(round(floatval($value))) : null;
}

function catalogIntValue($value, $default = 0) {
    $normalized = catalogNullableInt($value);
    return $normalized === null ? intval($default) : $normalized;
}

function catalogProductPriceType($value, $categoryCode) {
    if ((string)$categoryCode !== 'incidental_expenses') return 'fixed';
    return trim((string)$value) === 'percent' ? 'percent' : 'fixed';
}

function catalogServicePricingSchemaReady($db) {
    return true;
}

function catalogServiceRetailExpr($db, $alias = 'catalog_services') {
    $prefix = $alias !== '' ? ($alias . '.') : '';
    return "COALESCE({$prefix}retail_price, {$prefix}cost)";
}

function catalogServiceSortOrderSchemaReady($db) {
    return true;
}

function catalogServiceWorkSectionSchemaReady($db) {
    return true;
}

function catalogServiceWorkSectionExpr($db, $alias = 'catalog_services') {
    $prefix = $alias !== '' ? ($alias . '.') : '';
    return "COALESCE(NULLIF({$prefix}work_section_code,''), 'installation')";
}

function normalizeCatalogApprovalStatus($value) {
    return trim((string)$value) === 'Согласовано' ? 'Согласовано' : 'Не согласовано';
}

function syncProductServiceLink($db, $productNameId, $serviceId) {
    $productNameId = intval($productNameId);
    $serviceId = intval($serviceId);
    if (!$productNameId) return;

    if (!$serviceId) {
        $db->prepare("UPDATE product_names SET linked_service_id = NULL, labor_price = NULL WHERE id = ?")
           ->execute([$productNameId]);
        return;
    }

    $st = $db->prepare("SELECT ".catalogServiceRetailExpr($db, '')." AS retail_price FROM catalog_services WHERE id = ?");
    $st->execute([$serviceId]);
    $row = $st->fetch();
    if (!$row) return;
    $serviceCost = $row['retail_price'] !== null ? intval(round(floatval($row['retail_price']))) : null;
    $db->prepare("UPDATE product_names SET linked_service_id = ?, labor_price = ? WHERE id = ?")
       ->execute([$serviceId, $serviceCost, $productNameId]);
}

function catalogProductServiceLinksSchemaReady($db) {
    return true;
}

function catalogNormalizeLinkedServiceIds($input) {
    $raw = [];
    if (array_key_exists('linked_service_ids', $input)) {
        $raw = is_array($input['linked_service_ids'])
            ? $input['linked_service_ids']
            : preg_split('/\s*,\s*/', (string)$input['linked_service_ids'], -1, PREG_SPLIT_NO_EMPTY);
    } elseif (array_key_exists('linked_service_id', $input)) {
        $raw = [intval($input['linked_service_id'])];
    }
    $out = [];
    foreach ($raw as $id) {
        $id = intval($id);
        if ($id > 0 && !in_array($id, $out, true)) $out[] = $id;
    }
    return $out;
}

function validateLinkedServicesForSection($db, $sectionId, $serviceIds) {
    foreach ($serviceIds as $serviceId) {
        $err = validateLinkedServiceForSection($db, $sectionId, $serviceId);
        if ($err) return $err;
    }
    return null;
}

function syncProductServiceLinks($db, $productNameId, $serviceIds) {
    $productNameId = intval($productNameId);
    $serviceIds = catalogNormalizeLinkedServiceIds(['linked_service_ids' => $serviceIds]);
    $primaryServiceId = $serviceIds[0] ?? 0;
    syncProductServiceLink($db, $productNameId, $primaryServiceId);
    if (!catalogProductServiceLinksSchemaReady($db) || !$productNameId) return;

    $db->prepare("DELETE FROM product_service_links WHERE product_name_id = ?")->execute([$productNameId]);
    if (!$serviceIds) return;
    $ins = $db->prepare("INSERT INTO product_service_links (product_name_id, service_id, sort_order) VALUES (?, ?, ?)");
    foreach ($serviceIds as $idx => $serviceId) {
        $ins->execute([$productNameId, $serviceId, $idx]);
    }
}

function enrichProductsWithLinkedServices($db, $rows) {
    if (!$rows) return $rows;
    $map = [];
    foreach ($rows as $idx => $row) {
        $rows[$idx]['linked_services'] = [];
        $id = intval($row['id'] ?? 0);
        if ($id) $map[$id] = $idx;
    }
    if (!$map) return $rows;

    if (catalogProductServiceLinksSchemaReady($db)) {
        $ids = array_keys($map);
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $sql = "SELECT psl.product_name_id, cs.id, cs.name, cs.marking_size, ".catalogServiceRetailExpr($db, 'cs')." AS retail_price,
                       cs.purchase_price, cs.unit, ".catalogServiceWorkSectionExpr($db, 'cs')." AS work_section_code
                  FROM product_service_links psl
                  JOIN catalog_services cs ON cs.id = psl.service_id
                 WHERE psl.product_name_id IN ($placeholders)
                 ORDER BY psl.sort_order, cs.name";
        $st = $db->prepare($sql);
        $st->execute($ids);
        foreach ($st->fetchAll() as $svc) {
            $pid = intval($svc['product_name_id']);
            if (!isset($map[$pid])) continue;
            $rows[$map[$pid]]['linked_services'][] = [
                'id' => intval($svc['id']),
                'name' => $svc['name'] ?? '',
                'marking_size' => $svc['marking_size'] ?? '',
                'retail_price' => $svc['retail_price'] !== null ? intval(round(floatval($svc['retail_price']))) : null,
                'purchase_price' => $svc['purchase_price'] !== null ? intval(round(floatval($svc['purchase_price']))) : null,
                'unit' => $svc['unit'] ?? '',
                'work_section_code' => $svc['work_section_code'] ?? '',
            ];
        }
    }

    foreach ($rows as $idx => $row) {
        if (!$rows[$idx]['linked_services'] && intval($row['linked_service_id'] ?? 0)) {
            $rows[$idx]['linked_services'][] = [
                'id' => intval($row['linked_service_id']),
                'name' => $row['linked_service_name'] ?? '',
                'marking_size' => $row['linked_service_marking_size'] ?? '',
                'retail_price' => $row['linked_service_cost'] !== null ? intval(round(floatval($row['linked_service_cost']))) : null,
                'purchase_price' => $row['linked_service_purchase_price'] !== null ? intval(round(floatval($row['linked_service_purchase_price']))) : null,
                'unit' => $row['linked_service_unit'] ?? '',
                'work_section_code' => $row['work_section_code'] ?? '',
            ];
        }
    }
    return $rows;
}

function findServiceLinkedToOtherProduct($db, $serviceId, $productNameId = 0) {
    $serviceId = intval($serviceId);
    if (!$serviceId) return null;
    $st = $db->prepare("SELECT pn.id AS linked_product_name_id, pn.name AS product_name
                          FROM product_names pn
                         WHERE pn.linked_service_id = ?
                           AND pn.id <> ?
                         ORDER BY pn.id
                         LIMIT 1");
    $st->execute([$serviceId, intval($productNameId)]);
    $row = $st->fetch();
    return $row ?: null;
}

function findOtherServiceForProduct($db, $productNameId, $serviceId = 0) {
    $productNameId = intval($productNameId);
    if (!$productNameId) return null;
    $st = $db->prepare("SELECT cs.id, cs.name
                          FROM product_names pn
                          JOIN catalog_services cs ON cs.id = pn.linked_service_id
                         WHERE pn.id = ?
                           AND (? = 0 OR cs.id <> ?)
                         LIMIT 1");
    $st->execute([$productNameId, intval($serviceId), intval($serviceId)]);
    return $st->fetch() ?: null;
}

function deleteProductNameReferences($db, $id) {
    $nameSt = $db->prepare("SELECT name FROM product_names WHERE id = ?");
    $nameSt->execute([$id]);
    $row = $nameSt->fetch();
    $fallbackName = $row ? $row['name'] : '';

    try {
        $db->prepare("UPDATE products
                         SET custom_name = COALESCE(NULLIF(custom_name, ''), ?),
                             product_name_id = NULL
                       WHERE product_name_id = ?")
           ->execute([$fallbackName, $id]);
    } catch (Exception $e) {
        $db->prepare("DELETE FROM products WHERE product_name_id = ?")->execute([$id]);
    }
}

function getSectionCategoryCode($db, $sectionId) {
    $sectionId = intval($sectionId);
    if (!$sectionId) return '';
    $st = $db->prepare("SELECT c.code
                          FROM sections s
                          JOIN categories c ON c.id = s.category_id
                         WHERE s.id = ?
                         LIMIT 1");
    $st->execute([$sectionId]);
    return trim((string)($st->fetch()['code'] ?? ''));
}

function validateLinkedServiceForSection($db, $sectionId, $serviceId) {
    $serviceId = intval($serviceId);
    if (!$serviceId) return null;
    return null;
    if ($categoryCode === '') {
        return 'Не удалось определить категорию товара или раздел монтажа';
    }
    if (false) {
        return $categoryCode === 'materials'
            ? 'Для материалов можно выбрать только монтаж материалов'
            : 'Для оборудования можно выбрать только монтаж оборудования';
    }
    return null;
}

function catalogReadSpreadsheetRows() {
    if (empty($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'])) {
        throw new RuntimeException('Файл не загружен');
    }
    $file = $_FILES['file'];
    if (($file['error'] ?? UPLOAD_ERR_OK) !== UPLOAD_ERR_OK) {
        throw new RuntimeException('Ошибка загрузки файла');
    }
    $size = intval($file['size'] ?? 0);
    if ($size <= 0 || $size > 20 * 1024 * 1024) {
        throw new RuntimeException('Размер файла должен быть до 20 МБ');
    }
    $name = mb_strtolower((string)($file['name'] ?? ''));
    $tmp = $file['tmp_name'];
    $ext = pathinfo($name, PATHINFO_EXTENSION);
    if (!in_array($ext, ['csv', 'xlsx'], true)) {
        throw new RuntimeException('Поддерживаются только .xlsx и .csv');
    }
    if (class_exists('finfo')) {
        $mime = (string)(new finfo(FILEINFO_MIME_TYPE))->file($tmp);
        $allowedMime = [
            'csv' => ['text/plain', 'text/csv', 'application/csv', 'application/vnd.ms-excel', 'application/octet-stream'],
            'xlsx' => ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/zip', 'application/octet-stream'],
        ];
        if ($mime && !in_array($mime, $allowedMime[$ext], true)) {
            throw new RuntimeException('Некорректный тип файла');
        }
    }
    if (substr($name, -4) === '.csv') {
        return catalogReadCsvRows($tmp);
    }
    if (substr($name, -5) === '.xlsx') {
        return catalogReadXlsxRows($tmp);
    }
    throw new RuntimeException('Поддерживаются только .xlsx и .csv');
}

function catalogReadCsvRows($path) {
    $rows = [];
    $fh = fopen($path, 'rb');
    if (!$fh) throw new RuntimeException('Не удалось прочитать CSV');
    while (($row = fgetcsv($fh, 0, ';')) !== false) {
        if (count($row) <= 1) {
            $row = str_getcsv(implode(',', $row), ',');
        }
        $rows[] = array_map(function ($v) {
            return trim((string)$v);
        }, $row);
    }
    fclose($fh);
    return $rows;
}

function catalogReadXlsxRows($path) {
    if (!class_exists('ZipArchive')) {
        throw new RuntimeException('Импорт .xlsx недоступен на этом сервере: не установлено расширение PHP zip. Используйте .csv или включите zip.');
    }
    $zip = new ZipArchive();
    if ($zip->open($path) !== true) {
        throw new RuntimeException('Не удалось открыть XLSX');
    }

    $sharedStrings = [];
    $sharedXml = $zip->getFromName('xl/sharedStrings.xml');
    if ($sharedXml !== false) {
        $sx = @simplexml_load_string($sharedXml);
        if ($sx && isset($sx->si)) {
            foreach ($sx->si as $si) {
                if (isset($si->t)) {
                    $sharedStrings[] = (string)$si->t;
                    continue;
                }
                $parts = [];
                if (isset($si->r)) {
                    foreach ($si->r as $run) {
                        $parts[] = (string)$run->t;
                    }
                }
                $sharedStrings[] = implode('', $parts);
            }
        }
    }

    $sheetXml = $zip->getFromName('xl/worksheets/sheet1.xml');
    if ($sheetXml === false) {
        $zip->close();
        throw new RuntimeException('В XLSX не найден первый лист');
    }

    $sx = @simplexml_load_string($sheetXml);
    if (!$sx || !isset($sx->sheetData)) {
        $zip->close();
        throw new RuntimeException('Не удалось прочитать данные XLSX');
    }

    $rows = [];
    foreach ($sx->sheetData->row as $row) {
        $current = [];
        foreach ($row->c as $cell) {
            $ref = (string)$cell['r'];
            $colLetters = preg_replace('/\d+/', '', $ref);
            $colIndex = catalogColumnIndex($colLetters);
            $type = (string)$cell['t'];
            $value = '';
            if ($type === 'inlineStr' && isset($cell->is->t)) {
                $value = (string)$cell->is->t;
            } elseif ($type === 's') {
                $idx = intval((string)$cell->v);
                $value = $sharedStrings[$idx] ?? '';
            } elseif (isset($cell->v)) {
                $value = (string)$cell->v;
            }
            $current[$colIndex] = trim((string)$value);
        }
        if (!$current) continue;
        ksort($current);
        $maxIndex = max(array_keys($current));
        $normalized = [];
        for ($i = 1; $i <= $maxIndex; $i++) {
            $normalized[] = $current[$i] ?? '';
        }
        $rows[] = $normalized;
    }
    $zip->close();
    return $rows;
}

function catalogColumnIndex($letters) {
    $letters = strtoupper(trim((string)$letters));
    $value = 0;
    $len = strlen($letters);
    for ($i = 0; $i < $len; $i++) {
        $value = ($value * 26) + (ord($letters[$i]) - 64);
    }
    return max(1, $value);
}

function catalogNormalizeHeader($value) {
    $value = preg_replace('/^\xEF\xBB\xBF/u', '', trim((string)$value));
    $value = mb_strtolower($value, 'UTF-8');
    $value = str_replace('ё', 'е', $value);
    return preg_replace('/[^\p{L}\p{N}]+/u', '', $value);
}

function catalogMapRows(array $rows) {
    if (!$rows) return [];
    $headers = array_map('catalogNormalizeHeader', array_shift($rows));
    $mapped = [];
    foreach ($rows as $row) {
        $item = [];
        $hasData = false;
        foreach ($headers as $idx => $header) {
            if ($header === '') continue;
            $value = trim((string)($row[$idx] ?? ''));
            if ($value !== '') $hasData = true;
            $item[$header] = $value;
        }
        if ($hasData) $mapped[] = $item;
    }
    return $mapped;
}

function catalogRowValue(array $row, array $keys, $default = '') {
    foreach ($keys as $key) {
        $normalized = catalogNormalizeHeader($key);
        if ($normalized !== '' && array_key_exists($normalized, $row)) {
            return trim((string)$row[$normalized]);
        }
    }
    return $default;
}

function catalogNullableFloat($value) {
    return catalogNullableInt($value);
}

function catalogResolveCategoryCode($value) {
    $normalized = catalogNormalizeHeader($value);
    $map = [
        'equipment' => 'equipment',
        'оборудование' => 'equipment',
        'materials' => 'materials',
        'материал' => 'materials',
        'материалы' => 'materials',
        'consumables' => 'consumables',
        'расходныйматериал' => 'consumables',
        'расходныематериалы' => 'consumables',
        'расходник' => 'consumables',
        'расходники' => 'consumables',
        'work' => 'work',
        'работа' => 'work',
        'услуга' => 'work',
        'монтаж' => 'work',
        'constructionworks' => 'construction_works',
        'строительныеработы' => 'construction_works',
        'стройработы' => 'construction_works',
        'incidentalexpenses' => 'incidental_expenses',
        'maintenance' => 'maintenance',
        'kits' => 'kits',
        'комплекты' => 'kits',
        'комплект' => 'kits',
        'сопутствующиерасходы' => 'incidental_expenses',
        'накладныерасходы' => 'incidental_expenses',
    ];
    return $map[$normalized] ?? '';
}

function catalogResolveWorkSectionCode($value) {
    $normalized = catalogNormalizeHeader($value);
    $map = [
        'installation' => 'installation',
        'монтаж' => 'installation',
        'монтажныеработы' => 'installation',
        'construction' => 'construction',
        'constructionworks' => 'construction',
        'строительныеработы' => 'construction',
        'стройработы' => 'construction',
        'dismantling' => 'dismantling',
        'демонтаж' => 'dismantling',
        'демонтажныеработы' => 'dismantling',
    ];
    return $map[$normalized] ?? 'installation';
}

function catalogCategoryCodeBySectionId($db, $sectionId) {
    $sectionId = intval($sectionId);
    if (!$sectionId) return '';
    $st = $db->prepare("SELECT c.code FROM sections s JOIN categories c ON c.id = s.category_id WHERE s.id = ? LIMIT 1");
    $st->execute([$sectionId]);
    return trim((string)($st->fetch()['code'] ?? ''));
}

function catalogIsAutoApprovedCategoryCode($code) {
    return in_array((string)$code, ['incidental_expenses', 'maintenance', 'kits'], true);
}

function catalogKitGroupName() {
    return 'комплекты';
}

function catalogFindSectionId($db, $categoryRaw, $sectionRaw) {
    $sectionRaw = trim((string)$sectionRaw);
    if ($sectionRaw === '') return 0;
    $categoryCode = catalogResolveCategoryCode($categoryRaw);
    $categoryName = trim((string)$categoryRaw);
    $sectionCode = catalogNormalizeHeader($sectionRaw);
    $st = $db->prepare(
        "SELECT s.id
           FROM sections s
           JOIN categories c ON c.id = s.category_id
          WHERE (
                    LOWER(TRIM(c.code)) = LOWER(TRIM(?))
                 OR LOWER(TRIM(c.name)) = LOWER(TRIM(?))
                )
            AND (
                    LOWER(TRIM(s.code)) = LOWER(TRIM(?))
                 OR LOWER(TRIM(s.name)) = LOWER(TRIM(?))
                )
          LIMIT 1"
    );
    $st->execute([$categoryCode ?: $categoryName, $categoryName, $sectionCode, $sectionRaw]);
    return intval($st->fetch()['id'] ?? 0);
}

function catalogFindServiceId($db, $serviceRaw, $scopeCode = '', $serviceMarking = '') {
    $serviceRaw = trim((string)$serviceRaw);
    $serviceMarking = trim((string)$serviceMarking);
    if ($serviceRaw === '') return 0;
    if (ctype_digit($serviceRaw)) {
        return intval($serviceRaw);
    }
    if ($serviceMarking !== '') {
        $st = $db->prepare("SELECT id FROM catalog_services WHERE name = ? AND COALESCE(marking_size,'') = ? ORDER BY id DESC LIMIT 1");
        $params = [$serviceRaw, $serviceMarking];
        $st->execute($params);
        $found = intval($st->fetch()['id'] ?? 0);
        if ($found > 0) return $found;
    }
    $st = $db->prepare("SELECT id FROM catalog_services WHERE name = ? ORDER BY id DESC LIMIT 1");
    $params = [$serviceRaw];
    $st->execute($params);
    return intval($st->fetch()['id'] ?? 0);
}

function catalogParseLinkedServices($db, array $row, $scopeCode) {
    $ids = [];
    $missing = [];
    $indexes = [];
    foreach (array_keys($row) as $header) {
        if (preg_match('/^(?:работа|названиеработы)(\d+)$/u', $header, $matches)) {
            $indexes[] = intval($matches[1]);
        }
    }
    $indexes = array_values(array_unique($indexes));
    sort($indexes, SORT_NUMERIC);

    foreach ($indexes as $index) {
        $serviceName = catalogRowValue($row, ['Работа ' . $index, 'Название работы ' . $index]);
        $serviceMarking = catalogRowValue($row, ['Маркировка работы ' . $index]);
        if ($serviceName === '') continue;
        $serviceId = catalogFindServiceId($db, $serviceName, '', $serviceMarking);
        if ($serviceId > 0) {
            if (!in_array($serviceId, $ids, true)) $ids[] = $serviceId;
        } else {
            $missing[] = $serviceName . ($serviceMarking !== '' ? ' / ' . $serviceMarking : '');
        }
    }
    return ['ids' => $ids, 'missing' => $missing];
}

function catalogImportRows($db, array $rows, int $creatorId = 0) {
    $result = ['products' => 0, 'services' => 0, 'errors' => []];
    $serviceSortReady = catalogServiceSortOrderSchemaReady($db);
    foreach ($rows as $line => $row) {
        $type = catalogNormalizeHeader(catalogRowValue($row, ['Тип', 'ItemType'], 'Товар'));
        $isService = in_array($type, ['работа', 'монтаж', 'услуга', 'service', 'work'], true);
        $importId = intval(catalogRowValue($row, ['ID', 'id'], '0'));
        $sortOrder = catalogIntValue(catalogRowValue($row, ['sort_order', 'SortOrder', 'Сортировка'], '0'));

        if ($isService) {
            $name = catalogRowValue($row, ['Наименование', 'Название']);
            if ($name === '') {
                $result['errors'][] = 'Строка ' . ($line + 2) . ': не указано наименование работы';
                continue;
            }
            $scopeCode = '';
            $workSectionCode = catalogResolveWorkSectionCode(catalogRowValue($row, ['Раздел', 'Раздел работ', 'Work section']));
            $marking = catalogRowValue($row, ['Маркировка', 'Маркировка/Размер', 'Маркировка / Размер']);
            $purchase = catalogNullableFloat(catalogRowValue($row, ['Закупочная цена']));
            $minimal = catalogNullableFloat(catalogRowValue($row, ['Минимальная цена']));
            $retail = catalogNullableFloat(catalogRowValue($row, ['Стоимость', 'Цена', 'Розничная цена']));
            $unit = catalogRowValue($row, ['Единица', 'Единица измерения', 'Едизм'], getDefaultMeasurementUnitName());

            $existingServiceId = 0;
            if ($importId > 0) {
                $st = $db->prepare("SELECT id FROM catalog_services WHERE id = ? LIMIT 1");
                $st->execute([$importId]);
                $existingServiceId = intval($st->fetch()['id'] ?? 0);
            }
            if (catalogServicePricingSchemaReady($db)) {
                if ($existingServiceId) {
                    if ($serviceSortReady) {
                        $db->prepare("UPDATE catalog_services
                                         SET name = ?, cost = ?, marking_size = ?, purchase_price = ?, minimal_price = ?, retail_price = ?, unit = ?, sort_order = ?
                                       WHERE id = ?")
                           ->execute([$name, $retail ?: 0, $marking ?: null, $purchase, $minimal, $retail, $unit ?: null, $sortOrder, $existingServiceId]);
                    } else {
                        $db->prepare("UPDATE catalog_services
                                         SET name = ?, cost = ?, marking_size = ?, purchase_price = ?, minimal_price = ?, retail_price = ?, unit = ?
                                       WHERE id = ?")
                           ->execute([$name, $retail ?: 0, $marking ?: null, $purchase, $minimal, $retail, $unit ?: null, $existingServiceId]);
                    }
                } else {
                    if ($serviceSortReady) {
                        $db->prepare("INSERT INTO catalog_services (name, cost, marking_size, purchase_price, minimal_price, retail_price, unit, linked_product_name_id, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)")
                           ->execute([$name, $retail ?: 0, $marking ?: null, $purchase, $minimal, $retail, $unit ?: null, $sortOrder]);
                    } else {
                        $db->prepare("INSERT INTO catalog_services (name, cost, marking_size, purchase_price, minimal_price, retail_price, unit, linked_product_name_id) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)")
                           ->execute([$name, $retail ?: 0, $marking ?: null, $purchase, $minimal, $retail, $unit ?: null]);
                    }
                }
            } else {
                if ($existingServiceId) {
                    if ($serviceSortReady) {
                        $db->prepare("UPDATE catalog_services
                                         SET name = ?, cost = ?, unit = ?, sort_order = ?
                                       WHERE id = ?")
                           ->execute([$name, $retail ?: 0, $unit ?: null, $sortOrder, $existingServiceId]);
                    } else {
                        $db->prepare("UPDATE catalog_services
                                         SET name = ?, cost = ?, unit = ?
                                       WHERE id = ?")
                           ->execute([$name, $retail ?: 0, $unit ?: null, $existingServiceId]);
                    }
                } else {
                    if ($serviceSortReady) {
                        $db->prepare("INSERT INTO catalog_services (name, cost, unit, linked_product_name_id, sort_order) VALUES (?, ?, ?, NULL, ?)")
                           ->execute([$name, $retail ?: 0, $unit ?: null, $sortOrder]);
                    } else {
                        $db->prepare("INSERT INTO catalog_services (name, cost, unit, linked_product_name_id) VALUES (?, ?, ?, NULL)")
                           ->execute([$name, $retail ?: 0, $unit ?: null]);
                    }
                }
            }
            $savedServiceId = $existingServiceId ?: intval($db->lastInsertId());
            if ($savedServiceId && catalogServiceWorkSectionSchemaReady($db)) {
                $db->prepare("UPDATE catalog_services SET work_section_code = ? WHERE id = ?")
                   ->execute([$workSectionCode, $savedServiceId]);
            }
            $result['services']++;
            continue;
        }

        $categoryName = catalogRowValue($row, ['Категория']);
        $sectionName = catalogRowValue($row, ['Раздел']);
        $groupName = catalogRowValue($row, ['Группа', 'group_name', 'Group']);
        $name = catalogRowValue($row, ['Наименование', 'Название']);
        if ($categoryName === '' || $sectionName === '' || $name === '') {
            $result['errors'][] = 'Строка ' . ($line + 2) . ': нужны Категория, Раздел, Наименование';
            continue;
        }

        $sectionId = catalogFindSectionId($db, $categoryName, $sectionName);
        if (!$sectionId) {
            $result['errors'][] = 'Строка ' . ($line + 2) . ': раздел не найден';
            continue;
        }

        $status = normalizeCatalogApprovalStatus(catalogRowValue($row, ['Статус'], 'Согласовано'));
        $supplier = catalogRowValue($row, ['Поставщик']);
        $note = catalogRowValue($row, ['Примечание', 'Note']);
        $technicalNote = catalogRowValue($row, ['Техничка', 'Technical note', 'Technical_note']);
        $marking = catalogRowValue($row, ['Маркировка', 'Маркировка/Размер', 'Маркировка / Размер']);
        $unit = catalogRowValue($row, ['Единица', 'Единица измерения', 'Едизм'], getDefaultMeasurementUnitName());
        $purchase = catalogNullableFloat(catalogRowValue($row, ['Закупочная цена']));
        $minimal = catalogNullableFloat(catalogRowValue($row, ['Минимальная цена']));
        $retail = catalogNullableFloat(catalogRowValue($row, ['Розничная цена']));
        $labor = catalogNullableFloat(catalogRowValue($row, ['Цена работ', 'Монтаж']));
        $scopeCode = getSectionCategoryCode($db, $sectionId);
        if ($scopeCode === 'kits') {
            $status = 'Согласовано';
            if ($groupName === '') $groupName = catalogKitGroupName();
            $supplier = '';
            $note = '';
            $technicalNote = '';
            $purchase = null;
            $minimal = null;
            $labor = null;
        }
        $linkedServices = ($scopeCode === 'kits')
            ? ['ids' => [], 'missing' => []]
            : catalogParseLinkedServices($db, $row, $scopeCode);
        if ($linkedServices['missing']) {
            $result['errors'][] = 'Строка ' . ($line + 2) . ': не найдены работы: ' . implode('; ', $linkedServices['missing']);
            continue;
        }
        $scopeError = validateLinkedServicesForSection($db, $sectionId, $linkedServices['ids']);
        if ($scopeError) {
            $result['errors'][] = 'Строка ' . ($line + 2) . ': ' . $scopeError;
            continue;
        }

        $existingProductId = 0;
        if ($importId > 0) {
            $st = $db->prepare("SELECT id FROM product_names WHERE id = ? LIMIT 1");
            $st->execute([$importId]);
            $existingProductId = intval($st->fetch()['id'] ?? 0);
        }
        if (!$existingProductId && ($retail === null || floatval($retail) <= 0)) {
            $result['errors'][] = 'Строка ' . ($line + 2) . ': розничная цена должна быть больше 0';
            continue;
        }
        if ($existingProductId) {
            $db->prepare(
                "UPDATE product_names
                    SET section_id = ?, group_name = ?, name = ?, status = ?, supplier = ?, note = ?, technical_note = ?, marking_size = ?, unit = ?, purchase_price = ?, minimal_price = ?, retail_price = ?, labor_price = ?, sort_order = ?
                  WHERE id = ?"
            )->execute([
                $sectionId,
                $groupName !== '' ? $groupName : null,
                $name,
                $status,
                $supplier ?: null,
                $note !== '' ? $note : null,
                $technicalNote ?: null,
                $marking ?: null,
                $unit ?: null,
                $purchase,
                $minimal,
                $retail,
                $labor,
                $sortOrder,
                $existingProductId,
            ]);
            $productId = $existingProductId;
        } else {
            $db->prepare(
                "INSERT INTO product_names
                    (section_id, group_name, name, is_custom, status, supplier, note, technical_note, marking_size, unit, purchase_price, minimal_price, retail_price, labor_price, sort_order, created_by)
                 VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            )->execute([
                $sectionId,
                $groupName !== '' ? $groupName : null,
                $name,
                $status,
                $supplier ?: null,
                $note !== '' ? $note : null,
                $technicalNote ?: null,
                $marking ?: null,
                $unit ?: null,
                $purchase,
                $minimal,
                $retail,
                $labor,
                $sortOrder,
                $creatorId ?: null,
            ]);
            $productId = intval($db->lastInsertId());
        }

        syncProductServiceLinks($db, $productId, $linkedServices['ids']);
        $result['products']++;
    }
    return $result;
}

switch ($action) {

    case 'categories':
        jsonResponse(getCatalogReferenceCategories());
        break;

    case 'sections':
        $catId = intval($_GET['category_id'] ?? 0);
        jsonResponse(getCatalogReferenceSections($catId));
        break;

    case 'groups':
        $secId = intval($_GET['section_id'] ?? 0);
        jsonResponse(getCatalogReferenceGroups($secId));
        break;

    case 'suppliers':
        $secId = intval($_GET['section_id'] ?? 0);
        jsonResponse(getCatalogReferenceSuppliers($secId, true));
        break;

    case 'all_suppliers':
        try {
            jsonResponse(getCatalogReferenceSuppliersWithSections());
        } catch (Exception $e) {
            jsonResponse([]);
        }
        break;

    case 'units':
        jsonResponse(getMeasurementUnits());
        break;

    case 'save_group':
        accessAssert($user, 'settings', intval($input['id'] ?? 0) > 0 ? 'edit' : 'create');
        $id = intval($input['id'] ?? 0);
        $sectionId = intval($input['section_id'] ?? 0);
        $name = trim((string)($input['name'] ?? ''));
        $sortOrder = intval($input['sort_order'] ?? 0);
        if ($sectionId <= 0) jsonResponse(['error' => 'Раздел обязателен'], 400);
        if ($name === '') jsonResponse(['error' => 'Название обязательно'], 400);
        if ($id > 0) {
            $cur = $db->prepare("SELECT section_id, name FROM catalog_groups WHERE id = ? LIMIT 1");
            $cur->execute([$id]);
            $oldGroup = $cur->fetch();
            if (!$oldGroup) jsonResponse(['error' => 'Group not found'], 404);
            $db->beginTransaction();
            try {
                $st = $db->prepare("UPDATE catalog_groups SET section_id = ?, name = ?, sort_order = ? WHERE id = ?");
                $st->execute([$sectionId, $name, $sortOrder, $id]);
                if (trim((string)$oldGroup['name']) !== $name || intval($oldGroup['section_id']) !== $sectionId) {
                    $sync = $db->prepare("UPDATE product_names SET group_name = ? WHERE section_id = ? AND TRIM(COALESCE(group_name,'')) = ?");
                    $sync->execute([$name, intval($oldGroup['section_id']), trim((string)$oldGroup['name'])]);
                }
                $db->commit();
            } catch (Throwable $e) {
                if ($db->inTransaction()) $db->rollBack();
                throw $e;
            }
            jsonResponse(['ok' => true, 'id' => $id]);
        }
        $st = $db->prepare("INSERT INTO catalog_groups (section_id, name, sort_order) VALUES (?, ?, ?)");
        $st->execute([$sectionId, $name, $sortOrder]);
        jsonResponse(['ok' => true, 'id' => intval($db->lastInsertId())]);
        break;

    case 'delete_group':
        accessAssert($user, 'settings', 'delete');
        $id = intval($input['id'] ?? 0);
        if ($id <= 0) jsonResponse(['error' => 'Invalid id'], 400);
        $st = $db->prepare("DELETE FROM catalog_groups WHERE id = ?");
        $st->execute([$id]);
        jsonResponse(['ok' => true]);
        break;

    case 'save_unit':
        $name = trim($input['name'] ?? '');
        if ($name === '') jsonResponse(['error' => 'Название обязательно'], 400);
        $sortOrder = intval($input['sort_order'] ?? 0);
        $isDefault = !empty($input['is_default']) ? 1 : 0;
        $existing = $db->prepare("SELECT id FROM measurement_units WHERE name = ? LIMIT 1");
        $existing->execute([$name]);
        $row = $existing->fetch();
        accessAssert($user, 'settings', $row ? 'edit' : 'create');
        if ($isDefault) {
            $db->exec("UPDATE measurement_units SET is_default = 0");
        }
        if ($row) {
            $db->prepare("UPDATE measurement_units SET sort_order = ?, is_default = ? WHERE id = ?")
               ->execute([$sortOrder, $isDefault, $row['id']]);
            jsonResponse(['ok' => true, 'id' => intval($row['id'])]);
        }
        $db->prepare("INSERT INTO measurement_units (name, sort_order, is_default) VALUES (?, ?, ?)")
           ->execute([$name, $sortOrder, $isDefault]);
        jsonResponse(['ok' => true, 'id' => intval($db->lastInsertId())]);
        break;

    case 'delete_unit':
        accessAssert($user, 'settings', 'delete');
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);
        $db->prepare("DELETE FROM measurement_units WHERE id = ?")->execute([$id]);
        jsonResponse(['ok' => true]);
        break;

    case 'save_supplier':
        $supId = intval($input['id'] ?? 0);
        accessAssert($user, 'settings', $supId > 0 ? 'edit' : 'create');
        $name = trim($input['name'] ?? '');
        if (!$name) jsonResponse(['error' => 'Название обязательно'], 400);
        $sectionIds = array_map('intval', $input['section_ids'] ?? []);
        $existing = $db->prepare("SELECT id FROM suppliers WHERE name = ?" . ($supId ? " AND id <> ?" : ""));
        $existing->execute($supId ? [$name, $supId] : [$name]);
        $row = $existing->fetch();
        if ($row) {
            if ($supId) {
                jsonResponse(['error' => 'Поставщик с таким названием уже существует'], 409);
            }
            $supId = intval($row['id']);
        } elseif ($supId) {
            $db->prepare("UPDATE suppliers SET name = ?, sort_order = ? WHERE id = ?")
               ->execute([$name, intval($input['sort_order'] ?? 0), $supId]);
        } else {
            $db->prepare("INSERT INTO suppliers (name, sort_order) VALUES (?, ?)")
               ->execute([$name, intval($input['sort_order'] ?? 0)]);
            $supId = $db->lastInsertId();
        }
        $db->prepare("DELETE FROM section_suppliers WHERE supplier_id = ?")->execute([$supId]);
        foreach ($sectionIds as $sid) {
            if ($sid) {
                $db->prepare("INSERT IGNORE INTO section_suppliers (section_id, supplier_id) VALUES (?,?)")
                   ->execute([$sid, $supId]);
            }
        }
        jsonResponse(['ok' => true, 'id' => $supId]);
        break;

    case 'delete_supplier':
        accessAssert($user, 'settings', 'delete');
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);
        $db->prepare("DELETE FROM suppliers WHERE id = ?")->execute([$id]);
        jsonResponse(['ok' => true]);
        break;

    case 'names':
        $secId = intval($_GET['section_id'] ?? 0);
        if (!$secId) jsonResponse(['error' => 'section_id required'], 400);
        $hasGroupFilter = array_key_exists('group_name', $_GET);
        $groupName = trim((string)($_GET['group_name'] ?? ''));
        if ($groupName === '__EMPTY__') $groupName = '';
        $where = " AND status = 'Согласовано'";
        if ($hasGroupFilter) $where .= " AND LOWER(TRIM(COALESCE(group_name,''))) = LOWER(TRIM(?))";
        $st = $db->prepare(
            "SELECT id, name, group_name, marking_size, komplektaciya, supplier, unit, note, status
               FROM product_names
              WHERE section_id = ? $where
              ORDER BY COALESCE(group_name,''), sort_order, name, marking_size, unit, supplier"
        );
        $params = [$secId];
        if ($hasGroupFilter) $params[] = $groupName;
        $st->execute($params);
        jsonResponse($st->fetchAll());
        break;

    case 'names_by_name':
        $nameId = intval($_GET['name_id'] ?? 0);
        if (!$nameId) jsonResponse([]);
        $st = $db->prepare("SELECT DISTINCT marking_size
                              FROM product_names
                             WHERE id = ?
                                OR (section_id = (SELECT section_id FROM product_names WHERE id=?)
                                    AND name = (SELECT name FROM product_names WHERE id=?)
                                    AND status = 'Согласовано')
                             ORDER BY marking_size");
        $st->execute([$nameId, $nameId, $nameId]);
        jsonResponse(array_filter(array_column($st->fetchAll(), 'marking_size')));
        break;

    case 'names_search':
        $q = trim($_GET['q'] ?? '');
        $statusFilter = "AND pn.status='Согласовано'";
        $secFilter = '';
        $secId = intval($_GET['section_id'] ?? 0);
        $catId = intval($_GET['category_id'] ?? ($_GET['cat_id'] ?? 0));
        $hasGroupFilter = array_key_exists('group_name', $_GET);
        $groupName = trim((string)($_GET['group_name'] ?? ''));
        if ($groupName === '__EMPTY__') $groupName = '';
        if ($secId) $secFilter = "AND pn.section_id = $secId";
        if ($catId) $secFilter .= " AND s.category_id = $catId";
        if ($hasGroupFilter) $secFilter .= " AND LOWER(TRIM(COALESCE(pn.group_name,''))) = LOWER(TRIM(?))";
        if ($q) {
            $st = $db->prepare("SELECT pn.id, pn.name, pn.group_name, pn.marking_size, pn.komplektaciya, pn.unit, pn.supplier, pn.note, pn.section_id, s.category_id
                                 FROM product_names pn
                                 JOIN sections s ON s.id=pn.section_id
                                WHERE pn.name LIKE ? $statusFilter $secFilter
                                ORDER BY CASE
                                           WHEN pn.name LIKE ? THEN 0
                                           WHEN pn.name LIKE ? THEN 1
                                           ELSE 2
                                         END,
                                         COALESCE(pn.group_name,''), pn.name, pn.marking_size, pn.unit, pn.supplier
                                LIMIT 300");
            $params = ['%' . $q . '%'];
            if ($hasGroupFilter) $params[] = $groupName;
            $params[] = $q . '%';
            $params[] = '%' . $q . '%';
            $st->execute($params);
        } else {
            $st = $db->prepare("SELECT pn.id, pn.name, pn.group_name, pn.marking_size, pn.komplektaciya, pn.unit, pn.supplier, pn.note, pn.section_id, s.category_id
                                 FROM product_names pn
                                 JOIN sections s ON s.id=pn.section_id
                                WHERE 1=1 $statusFilter $secFilter
                                ORDER BY COALESCE(pn.group_name,''), pn.name, pn.marking_size, pn.unit, pn.supplier
                                LIMIT 500");
            $params = [];
            if ($hasGroupFilter) $params[] = $groupName;
            $st->execute($params);
        }
        jsonResponse($st->fetchAll());
        break;

    case 'all_names':
        $pagination = paginationFromRequest(CATALOG_DEFAULT_PER_PAGE, CATALOG_MAX_PER_PAGE);
        $whereParts = ['1=1'];
        $params = [];
        if (!canManageCatalog($user)) $whereParts[] = "pn.status='Согласовано'";
        $categoryCode = trim((string)($_GET['category_code'] ?? ''));
        $categoryId = intval($_GET['category_id'] ?? ($_GET['cat_id'] ?? 0));
        $sectionId = intval($_GET['section_id'] ?? 0);
        $status = trim((string)($_GET['status'] ?? ''));
        $search = trim((string)($_GET['search'] ?? ($_GET['q'] ?? '')));
        if ($categoryCode !== '') {
            $whereParts[] = 'c.code = ?';
            $params[] = $categoryCode;
        }
        if ($categoryId > 0) {
            $whereParts[] = 'c.id = ?';
            $params[] = $categoryId;
        }
        if ($sectionId > 0) {
            $whereParts[] = 's.id = ?';
            $params[] = $sectionId;
        }
        if ($status !== '') {
            $whereParts[] = 'pn.status = ?';
            $params[] = $status;
        }
        if ($search !== '') {
            $whereParts[] = "(pn.name LIKE ? OR COALESCE(pn.marking_size, '') LIKE ? OR s.name LIKE ? OR c.name LIKE ?)";
            $like = '%' . $search . '%';
            array_push($params, $like, $like, $like, $like);
        }
        $fromWhere = "FROM product_names pn
                JOIN sections s ON s.id = pn.section_id
                JOIN categories c ON c.id = s.category_id
                LEFT JOIN catalog_services cs ON cs.id = pn.linked_service_id
                WHERE " . implode(' AND ', $whereParts);
        $sql = "SELECT " . catalogProductNameSelectFieldsWithAlias('pn') . ", s.name as section_name, s.id as section_id, s.code as section_code, c.name as category_name, c.id as category_id, c.code as category_code,
                       pn.minimal_price,
                       pn.linked_service_id, cs.name as linked_service_name, cs.marking_size as linked_service_marking_size, ".catalogServiceRetailExpr($db, 'cs')." as linked_service_cost, cs.purchase_price as linked_service_purchase_price, cs.unit as linked_service_unit
                 {$fromWhere}
                ORDER BY c.sort_order, s.sort_order, pn.sort_order, pn.name, pn.marking_size, pn.unit, pn.supplier" . paginationLimitSql($pagination);
        $st = $db->prepare($sql);
        $st->execute($params);
        $items = enrichProductsWithLinkedServices($db, $st->fetchAll());
        $total = $pagination ? paginationCount($db, $fromWhere, $params) : count($items);
        jsonPaginatedResponse($items, $pagination, $total);
        break;

    case 'import_catalog_excel':
        accessAssert($user, 'catalog', 'create');
        try {
            @set_time_limit(0);
            @ini_set('memory_limit', '512M');
            $rows = catalogMapRows(catalogReadSpreadsheetRows());
            $db->beginTransaction();
            $result = catalogImportRows($db, $rows, $uid);
            $db->commit();
            jsonResponse($result);
        } catch (Throwable $e) {
            if ($db->inTransaction()) $db->rollBack();
            jsonResponse(['error' => $e->getMessage()], 400);
        }
        break;

    case 'update_name':
        accessAssert($user, 'catalog', 'edit');
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);

        $cur = $db->prepare("SELECT id, section_id, group_name, name, sort_order, created_by, created_at, is_custom, status, supplier, marking_size, komplektaciya, note, unit, purchase_price, retail_price, price_type, discount_value, labor_price, minimal_price, linked_service_id, technical_note FROM product_names WHERE id=?");
        $cur->execute([$id]);
        $curRow = $cur->fetch();
        if (!$curRow) jsonResponse(['error' => 'Not found'], 404);

        $name          = trim($input['name'] ?? $curRow['name']);
        $status        = normalizeCatalogApprovalStatus($input['status'] ?? $curRow['status']);
        $sectionId     = intval($input['section_id'] ?? $curRow['section_id']);
        $sectionCategoryCode = catalogCategoryCodeBySectionId($db, $sectionId);
        if (catalogIsAutoApprovedCategoryCode($sectionCategoryCode)) $status = 'Согласовано';
        $groupName     = trim($input['group_name'] ?? ($curRow['group_name'] ?? ''));
        $supplier      = trim($input['supplier'] ?? $curRow['supplier']);
        $note          = trim($input['note'] ?? $curRow['note']);
        $markingSize   = trim($input['marking_size'] ?? $curRow['marking_size']);
        $komplektaciya = trim($input['komplektaciya'] ?? $curRow['komplektaciya']);
        $technicalNote = trim($input['technical_note'] ?? $curRow['technical_note']);
        $unit          = trim($input['unit'] ?? $curRow['unit']);
        $purchasePrice = ($input['purchase_price'] ?? $curRow['purchase_price']) !== '' ? catalogIntValue($input['purchase_price'] ?? $curRow['purchase_price']) : null;
        $minimalPrice  = ($input['minimal_price'] ?? $curRow['minimal_price']) !== '' ? catalogIntValue($input['minimal_price'] ?? $curRow['minimal_price']) : null;
        $retailPrice   = ($input['retail_price'] ?? $curRow['retail_price']) !== '' ? catalogIntValue($input['retail_price'] ?? $curRow['retail_price']) : null;
        $priceType     = catalogProductPriceType($input['price_type'] ?? ($curRow['price_type'] ?? 'fixed'), $sectionCategoryCode);
        $laborPrice    = ($input['labor_price'] ?? $curRow['labor_price']) !== '' ? catalogIntValue($input['labor_price'] ?? $curRow['labor_price']) : null;
        $linkedServiceIds = catalogNormalizeLinkedServiceIds($input);
        $linkedServiceId = $linkedServiceIds[0] ?? 0;
        if (!$name) jsonResponse(['error' => 'Название обязательно'], 400);
        if ($sectionCategoryCode === 'kits') {
            $status = 'Согласовано';
            if ($groupName === '') $groupName = catalogKitGroupName();
            $supplier = '';
            $note = '';
            $technicalNote = '';
            $purchasePrice = null;
            $minimalPrice = null;
            $laborPrice = null;
            $linkedServiceIds = [];
        }
        if ($sectionCategoryCode === 'consumables') {
            $note = '';
            $technicalNote = '';
            $purchasePrice = null;
            $minimalPrice = null;
            $retailPrice = null;
            $laborPrice = null;
            $linkedServiceIds = [];
        }
        $scopeError = validateLinkedServicesForSection($db, $sectionId, $linkedServiceIds);
        if ($scopeError) jsonResponse(['error' => $scopeError], 409);
        $db->prepare("UPDATE product_names
                         SET name=?, status=?, section_id=?, group_name=?, supplier=?, note=?, technical_note=?, marking_size=?, komplektaciya=?, unit=?, purchase_price=?, minimal_price=?, retail_price=?, price_type=?, labor_price=?
                       WHERE id=?")
           ->execute([$name, $status, $sectionId, $groupName !== '' ? $groupName : null, $supplier, $note ?: null, $technicalNote ?: null, $markingSize, $komplektaciya ?: null, $unit, $purchasePrice, $minimalPrice, $retailPrice, $priceType, $laborPrice, $id]);
        if ($sectionCategoryCode === 'kits' || array_key_exists('linked_service_ids', $input) || array_key_exists('linked_service_id', $input)) {
            syncProductServiceLinks($db, $id, $linkedServiceIds);
        }
        jsonResponse(['ok' => true]);
        break;

    case 'create_name':
        accessAssert($user, 'catalog', 'create');
        $name          = trim($input['name'] ?? '');
        $status        = normalizeCatalogApprovalStatus($input['status'] ?? '');
        $sectionId     = intval($input['section_id'] ?? 0);
        $sectionCategoryCode = catalogCategoryCodeBySectionId($db, $sectionId);
        if (catalogIsAutoApprovedCategoryCode($sectionCategoryCode)) $status = 'Согласовано';
        $groupName     = trim($input['group_name'] ?? '');
        $supplier      = trim($input['supplier'] ?? '');
        $note          = trim($input['note'] ?? '');
        $markingSize   = trim($input['marking_size'] ?? '');
        $komplektaciya = trim($input['komplektaciya'] ?? '');
        $technicalNote = trim($input['technical_note'] ?? '');
        $unit          = trim($input['unit'] ?? '');
        $purchasePrice = ($input['purchase_price'] ?? '') !== '' ? catalogIntValue($input['purchase_price']) : null;
        $minimalPrice  = ($input['minimal_price'] ?? '') !== '' ? catalogIntValue($input['minimal_price']) : null;
        $retailPrice   = ($input['retail_price'] ?? '') !== '' ? catalogIntValue($input['retail_price']) : null;
        $priceType     = catalogProductPriceType($input['price_type'] ?? 'fixed', $sectionCategoryCode);
        $laborPrice    = ($input['labor_price'] ?? '') !== '' ? catalogIntValue($input['labor_price']) : null;
        $linkedServiceIds = catalogNormalizeLinkedServiceIds($input);
        $linkedServiceId = $linkedServiceIds[0] ?? 0;
        if (!$name) jsonResponse(['error' => 'Название обязательно'], 400);
        if (!$sectionId) jsonResponse(['error' => 'section_id required'], 400);
        if ($sectionCategoryCode === 'kits') {
            $status = 'Согласовано';
            if ($groupName === '') $groupName = catalogKitGroupName();
            $supplier = '';
            $note = '';
            $technicalNote = '';
            $purchasePrice = null;
            $minimalPrice = null;
            $laborPrice = null;
            $linkedServiceIds = [];
        }
        if ($sectionCategoryCode === 'consumables') {
            $note = '';
            $technicalNote = '';
            $purchasePrice = null;
            $minimalPrice = null;
            $retailPrice = null;
            $laborPrice = null;
            $linkedServiceIds = [];
        }
        if ($sectionCategoryCode !== 'consumables' && ($retailPrice === null || intval($retailPrice) <= 0)) jsonResponse(['error' => 'Розничная цена должна быть больше 0'], 400);
        $scopeError = validateLinkedServicesForSection($db, $sectionId, $linkedServiceIds);
        if ($scopeError) jsonResponse(['error' => $scopeError], 409);
        $db->prepare("INSERT INTO product_names (section_id, group_name, name, is_custom, status, supplier, note, technical_note, marking_size, komplektaciya, unit, purchase_price, minimal_price, retail_price, price_type, labor_price, created_by)
                      VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
           ->execute([$sectionId, $groupName !== '' ? $groupName : null, $name, $status, $supplier, $note ?: null, $technicalNote ?: null, $markingSize, $komplektaciya ?: null, $unit ?: null, $purchasePrice, $minimalPrice, $retailPrice, $priceType, $laborPrice, $uid ?: null]);
        $newId = intval($db->lastInsertId());
        if ($sectionCategoryCode === 'kits' || array_key_exists('linked_service_ids', $input) || array_key_exists('linked_service_id', $input)) {
            syncProductServiceLinks($db, $newId, $linkedServiceIds);
        }
        jsonResponse(['ok' => true, 'id' => $newId]);
        break;

    case 'linkable_catalog_items':
        $q = trim($_GET['q'] ?? '');
        $sql = "SELECT pn.id, pn.name, pn.marking_size, c.code as category_code, c.name as category_name, s.name as section_name,
                       cs.id as linked_service_id, cs.name as linked_service_name
                FROM product_names pn
                JOIN sections s ON s.id = pn.section_id
                JOIN categories c ON c.id = s.category_id
                LEFT JOIN catalog_services cs ON cs.id = pn.linked_service_id
                WHERE c.code IN ('equipment','materials')";
        if ($q !== '') {
            $st = $db->prepare($sql . " AND (pn.name LIKE ? OR COALESCE(pn.marking_size, '') LIKE ? OR s.name LIKE ? OR c.name LIKE ?)
                ORDER BY c.sort_order, s.sort_order, pn.name, pn.marking_size");
            $like = '%' . $q . '%';
            $st->execute([$like, $like, $like, $like]);
            jsonResponse($st->fetchAll());
        }
        $sql .= "
                ORDER BY c.sort_order, s.sort_order, pn.name, pn.marking_size";
        jsonResponse($db->query($sql)->fetchAll());
        break;

    case 'services':
        $where = [];
        $params = [];
        $q = trim($_GET['search'] ?? '');
        $workSectionCode = trim((string)($_GET['work_section_code'] ?? ''));
        $serviceCategory = trim((string)($_GET['service_category'] ?? ''));
        $linksReady = catalogProductServiceLinksSchemaReady($db);
        if ($q !== '') {
            $searchWhere = "(cs.name LIKE ?";
            $params[] = '%' . $q . '%';
            if ($linksReady) {
                $searchWhere .= " OR EXISTS (
                    SELECT 1
                      FROM product_service_links pslq
                      JOIN product_names pnq ON pnq.id = pslq.product_name_id
                     WHERE pslq.service_id = cs.id
                       AND pnq.name LIKE ?
                )";
                $params[] = '%' . $q . '%';
            }
            $searchWhere .= " OR EXISTS (
                SELECT 1
                  FROM product_names pnlegacy
                 WHERE pnlegacy.linked_service_id = cs.id
                   AND pnlegacy.name LIKE ?
            ))";
            $params[] = '%' . $q . '%';
            $where[] = $searchWhere;
        }
        if ($serviceCategory === 'work') {
            $where[] = catalogServiceWorkSectionExpr($db, 'cs') . " IN ('installation', 'dismantling')";
        } elseif ($serviceCategory === 'construction_works') {
            $where[] = catalogServiceWorkSectionExpr($db, 'cs') . " = ?";
            $params[] = 'construction';
        } elseif ($workSectionCode !== '') {
            $where[] = catalogServiceWorkSectionExpr($db, 'cs') . " = ?";
            $params[] = $workSectionCode;
        }
        $pricingReady = catalogServicePricingSchemaReady($db);
        $workSectionSortExpr = "CASE " . catalogServiceWorkSectionExpr($db, 'cs') .
            " WHEN 'installation' THEN 1" .
            " WHEN 'construction' THEN 2" .
            " WHEN 'dismantling' THEN 3" .
            " ELSE 9 END";
        $linkedCountExpr = $linksReady
            ? "(
                (SELECT COUNT(DISTINCT pslc.product_name_id)
                   FROM product_service_links pslc
                  WHERE pslc.service_id = cs.id)
                +
                (SELECT COUNT(DISTINCT pnlegacy_count.id)
                   FROM product_names pnlegacy_count
                  WHERE pnlegacy_count.linked_service_id = cs.id
                    AND NOT EXISTS (
                        SELECT 1
                          FROM product_service_links pslc2
                         WHERE pslc2.product_name_id = pnlegacy_count.id
                           AND pslc2.service_id = cs.id
                    ))
              )"
            : "(SELECT COUNT(DISTINCT pnlegacy_count.id)
                  FROM product_names pnlegacy_count
                 WHERE pnlegacy_count.linked_service_id = cs.id)";
        $sql = "SELECT cs.id, cs.name, cs.cost, ".catalogServiceRetailExpr($db, 'cs')." AS retail_price, ".
                      ($pricingReady ? "cs.marking_size, cs.purchase_price, cs.minimal_price, " : "NULL AS marking_size, NULL AS purchase_price, NULL AS minimal_price, ").
                      (catalogServiceSortOrderSchemaReady($db) ? "COALESCE(cs.sort_order, 0) AS sort_order, " : "0 AS sort_order, ").
                      "cs.unit, ".catalogServiceWorkSectionExpr($db, 'cs')." AS work_section_code,
                       {$linkedCountExpr} as linked_products_count
                  FROM catalog_services cs";
        $serviceWhereSql = $where ? " WHERE " . implode(' AND ', $where) : '';
        if ($where) $sql .= $serviceWhereSql;
        $groupOrderSql = catalogServiceSortOrderSchemaReady($db)
            ? " ORDER BY {$workSectionSortExpr}, cs.sort_order, cs.name"
            : " ORDER BY {$workSectionSortExpr}, cs.name";
        $pagination = paginationFromRequest(CATALOG_DEFAULT_PER_PAGE, CATALOG_MAX_PER_PAGE);
        $sql .= $groupOrderSql . paginationLimitSql($pagination);
        $st = $db->prepare($sql);
        $st->execute($params);
        $items = $st->fetchAll();
        $total = count($items);
        if ($pagination) {
            $countSql = "SELECT COUNT(*) AS cnt
                  FROM catalog_services cs
                  {$serviceWhereSql}";
            $countSt = $db->prepare($countSql);
            $countSt->execute($params);
            $total = intval($countSt->fetch()['cnt'] ?? 0);
        }
        jsonPaginatedResponse($items, $pagination, $total);
        break;

    case 'create_service':
        accessAssert($user, 'catalog', 'create');
        if (!catalogServicePricingSchemaReady($db)) jsonResponse(['error' => 'Примените schema.sql перед сохранением работ'], 409);
        $name = trim($input['name'] ?? '');
        $marking = trim((string)($input['marking_size'] ?? ''));
        $purchasePrice = ($input['purchase_price'] ?? '') !== '' ? catalogIntValue($input['purchase_price']) : null;
        $minimalPrice = ($input['minimal_price'] ?? '') !== '' ? catalogIntValue($input['minimal_price']) : null;
        $retailPrice = ($input['retail_price'] ?? '') !== '' ? catalogIntValue($input['retail_price']) : 0;
        $cost = $retailPrice;
        $scopeCode = '';
        $workSectionCode = trim((string)($input['work_section_code'] ?? 'installation')) ?: 'installation';
        if ($workSectionCode === 'construction') $scopeCode = '';
        $unit = trim((string)($input['unit'] ?? ''));
        if (!$name) jsonResponse(['error' => 'Название обязательно'], 400);
        if (catalogServiceWorkSectionSchemaReady($db)) {
            $db->prepare("INSERT INTO catalog_services (name, cost, marking_size, purchase_price, minimal_price, retail_price, unit, work_section_code, linked_product_name_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)")
               ->execute([$name, $cost, $marking ?: null, $purchasePrice, $minimalPrice, $retailPrice, $unit ?: null, $workSectionCode]);
        } else {
            $db->prepare("INSERT INTO catalog_services (name, cost, marking_size, purchase_price, minimal_price, retail_price, unit, linked_product_name_id) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)")
               ->execute([$name, $cost, $marking ?: null, $purchasePrice, $minimalPrice, $retailPrice, $unit ?: null]);
        }
        jsonResponse(['ok' => true, 'id' => intval($db->lastInsertId())]);
        $linkedProductNameId = intval($input['linked_product_name_id'] ?? 0) ?: null;
        $scopeCode = '';
        $unit = trim((string)($input['unit'] ?? ''));
        if (!$name) jsonResponse(['error' => 'Название обязательно'], 400);
        if ($linkedProductNameId) {
            $productConflict = findOtherServiceForProduct($db, $linkedProductNameId, 0);
            if ($productConflict) {
                jsonResponse(['error' => 'К выбранному товару уже привязан монтаж: ' . $productConflict['name']], 409);
            }
        }
        $db->prepare("INSERT INTO catalog_services (name, cost, unit, linked_product_name_id) VALUES (?, ?, ?, NULL)")
           ->execute([$name, $cost, $unit ?: null]);
        $newId = intval($db->lastInsertId());
        if ($linkedProductNameId) {
            syncProductServiceLink($db, $linkedProductNameId, $newId);
        }
        jsonResponse(['ok' => true, 'id' => $newId]);
        break;

    case 'update_service':
        accessAssert($user, 'catalog', 'edit');
        if (!catalogServicePricingSchemaReady($db)) jsonResponse(['error' => 'Примените schema.sql перед сохранением работ'], 409);
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);
        $name = trim($input['name'] ?? '');
        $marking = trim((string)($input['marking_size'] ?? ''));
        $purchasePrice = ($input['purchase_price'] ?? '') !== '' ? catalogIntValue($input['purchase_price']) : null;
        $minimalPrice = ($input['minimal_price'] ?? '') !== '' ? catalogIntValue($input['minimal_price']) : null;
        $retailPrice = ($input['retail_price'] ?? '') !== '' ? catalogIntValue($input['retail_price']) : 0;
        $cost = $retailPrice;
        $scopeCode = '';
        $workSectionCode = trim((string)($input['work_section_code'] ?? 'installation')) ?: 'installation';
        if ($workSectionCode === 'construction') $scopeCode = '';
        $unit = trim((string)($input['unit'] ?? ''));
        if (!$name) jsonResponse(['error' => 'Название обязательно'], 400);
        if (catalogServiceWorkSectionSchemaReady($db)) {
            $db->prepare("UPDATE catalog_services SET name = ?, cost = ?, marking_size = ?, purchase_price = ?, minimal_price = ?, retail_price = ?, unit = ?, work_section_code = ?, linked_product_name_id = NULL WHERE id = ?")
               ->execute([$name, $cost, $marking ?: null, $purchasePrice, $minimalPrice, $retailPrice, $unit ?: null, $workSectionCode, $id]);
        } else {
            $db->prepare("UPDATE catalog_services SET name = ?, cost = ?, marking_size = ?, purchase_price = ?, minimal_price = ?, retail_price = ?, unit = ?, linked_product_name_id = NULL WHERE id = ?")
               ->execute([$name, $cost, $marking ?: null, $purchasePrice, $minimalPrice, $retailPrice, $unit ?: null, $id]);
        }
        jsonResponse(['ok' => true]);
        $linkedProductNameId = intval($input['linked_product_name_id'] ?? 0) ?: null;
        $scopeCode = '';
        $unit = trim((string)($input['unit'] ?? ''));
        if (!$name) jsonResponse(['error' => 'Название обязательно'], 400);
        $prev = $db->prepare("SELECT id FROM product_names WHERE linked_service_id = ? LIMIT 1");
        $prev->execute([$id]);
        $prevLinkedProductId = intval(($prev->fetch()['id'] ?? 0));
        if ($linkedProductNameId) {
            $productConflict = findOtherServiceForProduct($db, $linkedProductNameId, $id);
            if ($productConflict) {
                jsonResponse(['error' => 'К выбранному товару уже привязан монтаж: ' . $productConflict['name']], 409);
            }
        }
        $db->prepare("UPDATE catalog_services SET name = ?, cost = ?, unit = ?, linked_product_name_id = NULL WHERE id = ?")
           ->execute([$name, $cost, $unit ?: null, $id]);
        if ($linkedProductNameId) {
            syncProductServiceLink($db, $linkedProductNameId, $id);
        } elseif ($prevLinkedProductId) {
            $db->prepare("UPDATE product_names SET labor_price = NULL, linked_service_id = NULL WHERE linked_service_id = ?")
               ->execute([$id]);
        }
        jsonResponse(['ok' => true]);
        break;

    case 'delete_service':
        accessAssert($user, 'catalog', 'delete');
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);
        $db->prepare("UPDATE product_names SET labor_price = NULL, linked_service_id = NULL WHERE linked_service_id = ?")
           ->execute([$id]);
        $db->prepare("DELETE FROM catalog_services WHERE id = ?")->execute([$id]);
        jsonResponse(['ok' => true]);
        break;

    case 'delete_name':
        accessAssert($user, 'catalog', 'delete');
        $id = intval($input['id'] ?? 0);
        if (!$id) jsonResponse(['error' => 'id required'], 400);
        $db->beginTransaction();
        try {
            deleteProductNameReferences($db, $id);
            $db->prepare("DELETE FROM product_names WHERE id = ?")->execute([$id]);
            $db->commit();
            jsonResponse(['ok' => true]);
        } catch (Throwable $e) {
            $db->rollBack();
            jsonResponse(['error' => 'Не удалось удалить товар: ' . $e->getMessage()], 500);
        }
        break;

    default:
        jsonResponse(['error' => 'Unknown action'], 400);
}
