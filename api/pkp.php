<?php
require_once __DIR__ . '/../includes/auth.php';
require_once __DIR__ . '/../includes/access_middleware.php';
require_once __DIR__ . '/../includes/pagination.php';
require_once __DIR__ . '/../includes/quotes/quote_common.php';
require_once __DIR__ . '/email.php';

header('Content-Type: application/json; charset=utf-8');

$user   = requireAuth();
$method = $_SERVER['REQUEST_METHOD'];
$role   = $user['role'];
$uid    = intval($user['id']);
$input  = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) $input = [];
$action = $_GET['action'] ?? ($input['action'] ?? '');
accessMiddlewareAssertAction($user, (string)$action, [
    'save_catalog_product' => ['space_any' => [['catalog', 'create'], ['catalog', 'edit']]],
    'delete_catalog_product' => ['space' => 'catalog', 'action' => 'delete'],
    'save_catalog_service' => ['space_any' => [['catalog', 'create'], ['catalog', 'edit']]],
    'delete_catalog_service' => ['space' => 'catalog', 'action' => 'delete'],
    'company_save' => ['space_any' => [['company', 'create'], ['company', 'edit']]],
    'company_set_default' => ['space' => 'company', 'action' => 'edit'],
    'company_delete' => ['space' => 'company', 'action' => 'delete'],
    'save_client' => ['space_any' => [['company', 'create'], ['company', 'edit']]],
    'delete_client' => ['space' => 'company', 'action' => 'delete'],
    'save_quote' => ['space_any' => [['kp', 'create'], ['kp', 'edit']]],
    'delete_quote' => ['space' => 'kp', 'action' => 'delete'],
    'set_quote_kanban_orders' => ['space' => 'kp', 'action' => 'edit'],
    'set_quote_status' => ['space' => 'kp', 'action' => 'edit'],
    'set_quote_workflow' => ['space' => 'kp', 'action' => 'edit'],
    'transfer_to_kp' => ['space' => 'kp', 'action' => 'edit'],
    'set_quote_archive' => ['space' => 'kp', 'action' => 'edit'],
]);
$db = getDB();

function kpQuoteSelectFields(): string {
    return "id, user_id, client_id, title, status, workflow_status, selected_variant_label, company_snapshot_json, client_snapshot_json, payload_json, public_token, public_open_count, created_at, updated_at, sent_at, viewed_at, chosen_at, rejected_at, completed_at, is_archived, archived_at";
}

function kpAllowedSection($db, $sectionId) {
    $st = $db->prepare(
        "SELECT s.id, s.name, c.code AS category_code, c.name AS category_name
           FROM sections s
           JOIN categories c ON c.id = s.category_id
          WHERE s.id = ?
             AND c.code IN ('equipment','incidental_expenses')"
    );
    $st->execute([intval($sectionId)]);
    return $st->fetch() ?: null;
}

function kpValidateProductServiceScope($db, $section, $serviceId) {
    $serviceId = intval($serviceId);
    if (!$serviceId) return null;
    return null;
    if (false) {
        return 'Не удалось определить категорию товара или раздел монтажа';
    }
    if (false) {
        return $sectionCode === 'materials'
            ? 'Для материалов можно выбрать только монтаж материалов'
            : 'Для оборудования можно выбрать только монтаж оборудования';
    }
    return null;
}

function kpCatalogSyncCandidate($item) {
    if (!is_array($item)) return false;
    if (trim((string)($item['item_type'] ?? 'product')) === 'work') return false;
    if (trim((string)($item['category_code'] ?? '')) === 'incidental_expenses') return false;
    if (intval($item['product_name_id'] ?? 0) > 0) return false;
    if (trim((string)($item['name'] ?? '')) === '') return false;
    if (trim((string)($item['marking_size'] ?? '')) === '') return false;
    if (kpNullableInt($item['purchase_price'] ?? null) === null) return false;
    return intval($item['section_id'] ?? 0) > 0;
}

function kpApplyCatalogSyncNode(array &$node, array $sync) {
    $node['product_name_id'] = intval($sync['id']);
    if (array_key_exists('nameId', $node)) $node['nameId'] = intval($sync['id']);
    $node['category_id'] = intval($sync['category_id'] ?? ($node['category_id'] ?? 0));
    $node['category_code'] = $sync['category_code'] ?? ($node['category_code'] ?? '');
    $node['category_name'] = $sync['category_name'] ?? ($node['category_name'] ?? '');
    $node['section_id'] = intval($sync['section_id'] ?? ($node['section_id'] ?? 0));
    $node['section_name'] = $sync['section_name'] ?? ($node['section_name'] ?? '');
    $node['group_name'] = $sync['group_name'] ?? ($node['group_name'] ?? '');
    $node['name'] = $sync['name'] ?? ($node['name'] ?? '');
    $node['unit'] = $sync['unit'] ?? ($node['unit'] ?? '');
    $node['supplier'] = $sync['supplier'] ?? ($node['supplier'] ?? '');
    $node['purchase_price'] = $sync['purchase_price'] ?? ($node['purchase_price'] ?? null);
    if (array_key_exists('minimal_price', $sync)) $node['minimal_price'] = $sync['minimal_price'];
    if (array_key_exists('retail_price', $sync)) $node['retail_price'] = $sync['retail_price'];
}

function kpSyncPendingCatalogProducts($db, array &$payloadData, int $creatorId = 0) {
    if (empty($payloadData['variants']) || !is_array($payloadData['variants'])) return 0;
    $findSt = $db->prepare(
        "SELECT pn.id, pn.purchase_price, pn.minimal_price, pn.retail_price,
                s.id AS section_id, s.name AS section_name, c.id AS category_id, c.code AS category_code, c.name AS category_name
           FROM product_names pn
           JOIN sections s ON s.id = pn.section_id
          JOIN categories c ON c.id = s.category_id
          WHERE pn.section_id = ?
            AND COALESCE(pn.group_name,'') = ?
            AND pn.name = ?
            AND COALESCE(pn.marking_size,'') = ?
          ORDER BY pn.id DESC
          LIMIT 1"
    );
    $insertSt = $db->prepare(
        "INSERT INTO product_names
            (section_id, group_name, name, status, note, marking_size, unit, supplier, purchase_price, minimal_price, retail_price, created_by)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"
    );
    $updatePendingSt = $db->prepare(
        "UPDATE product_names
            SET note = ?, purchase_price = ?, retail_price = ?
          WHERE id = ?
            AND status <> 'Согласовано'"
    );

    $synced = 0;
    foreach ($payloadData['variants'] as &$variant) {
        if (!is_array($variant)) continue;
        $resolvedByUid = [];
        if (!empty($variant['items']) && is_array($variant['items'])) {
            foreach ($variant['items'] as &$item) {
                if (!kpCatalogSyncCandidate($item)) continue;
                $section = kpAllowedSection($db, intval($item['section_id'] ?? 0));
                if (!$section) continue;
                if (trim((string)($section['category_code'] ?? '')) === 'incidental_expenses') continue;
                $name = trim((string)($item['name'] ?? ''));
                $groupName = kpResolveCatalogGroupName($db, intval($section['id']), $item['group_name'] ?? '');
                $marking = trim((string)($item['marking_size'] ?? ''));
                $unit = trim((string)($item['unit'] ?? ''));
                $supplier = trim((string)($item['supplier'] ?? ''));
                $purchase = kpNullableInt($item['purchase_price'] ?? null);
                if ($purchase === null) continue;
                $retail = kpNullableInt($item['retail_price'] ?? ($item['base_price'] ?? ($item['final_price'] ?? null)));
                $note = trim((string)($item['note'] ?? ''));

                $findSt->execute([intval($section['id']), $groupName, $name, $marking]);
                $row = $findSt->fetch();
                if ($row) {
                    $updatePendingSt->execute([$note !== '' ? $note : null, $purchase, $retail, intval($row['id'])]);
                    $sync = [
                        'id' => intval($row['id']),
                        'category_id' => intval($row['category_id'] ?? 0),
                        'category_code' => $row['category_code'] ?? '',
                        'category_name' => $row['category_name'] ?? '',
                        'section_id' => intval($row['section_id'] ?? 0),
                        'section_name' => $row['section_name'] ?? '',
                        'group_name' => $groupName,
                        'name' => $name,
                        'unit' => $unit,
                        'supplier' => $supplier,
                        'purchase_price' => $row['purchase_price'] !== null ? intval($row['purchase_price']) : $purchase,
                        'minimal_price' => $row['minimal_price'] !== null ? intval($row['minimal_price']) : null,
                        'retail_price' => $row['retail_price'] !== null ? intval($row['retail_price']) : $retail
                    ];
                } else {
                    if ($retail === null || intval($retail) <= 0) continue;
                    $insertSt->execute([
                        intval($section['id']),
                        $groupName !== '' ? $groupName : null,
                        $name,
                        'Не согласовано',
                        $note !== '' ? $note : null,
                        $marking !== '' ? $marking : null,
                        $unit !== '' ? $unit : null,
                        $supplier !== '' ? $supplier : null,
                        $purchase,
                        null,
                        $retail,
                        $creatorId ?: null
                    ]);
                    $sync = [
                        'id' => intval($db->lastInsertId()),
                        'category_id' => 0,
                        'category_code' => $section['category_code'] ?? '',
                        'category_name' => $section['category_name'] ?? '',
                        'section_id' => intval($section['id']),
                        'section_name' => $section['name'] ?? '',
                        'group_name' => $groupName,
                        'name' => $name,
                        'unit' => $unit,
                        'supplier' => $supplier,
                        'purchase_price' => $purchase,
                        'minimal_price' => null,
                        'retail_price' => $retail
                    ];
                }
                kpApplyCatalogSyncNode($item, $sync);
                $uid = trim((string)($item['uid'] ?? ''));
                if ($uid !== '') $resolvedByUid[$uid] = $sync;
                $synced++;
            }
            unset($item);
        }
        if (!empty($resolvedByUid) && !empty($variant['snapshot']) && is_array($variant['snapshot'])) {
            foreach ($variant['snapshot'] as &$cat) {
                if (empty($cat['sections']) || !is_array($cat['sections'])) continue;
                foreach ($cat['sections'] as &$sec) {
                    if (empty($sec['items']) || !is_array($sec['items'])) continue;
                    foreach ($sec['items'] as &$snapItem) {
                        $uid = trim((string)($snapItem['uid'] ?? ''));
                        if ($uid === '' || empty($resolvedByUid[$uid])) continue;
                        kpApplyCatalogSyncNode($snapItem, $resolvedByUid[$uid]);
                    }
                    unset($snapItem);
                }
                unset($sec);
            }
            unset($cat);
        }
    }
    unset($variant);
    return $synced;
}

function kpServiceCard($db, $serviceId) {
    $st = $db->prepare("SELECT id, name, cost, unit FROM catalog_services WHERE id = ?");
    $st->execute([intval($serviceId)]);
    return $st->fetch() ?: null;
}

function kpSyncProductService($db, $productId, $serviceId) {
    $productId = intval($productId);
    $serviceId = intval($serviceId);
    if (!$productId) return;

    if (!$serviceId) {
        $db->prepare("UPDATE product_names SET linked_service_id = NULL, labor_price = NULL WHERE id = ?")
           ->execute([$productId]);
        return;
    }

    $service = kpServiceCard($db, $serviceId);
    if (!$service) return;
    $serviceCost = $service['cost'] !== null ? intval(round(floatval($service['cost']))) : null;
    $db->prepare("UPDATE product_names SET linked_service_id = ?, labor_price = ? WHERE id = ?")
       ->execute([$serviceId, $serviceCost, $productId]);
}

function kpSyncServiceProduct($db, $serviceId, $productId) {
    $serviceId = intval($serviceId);
    $productId = intval($productId);
    if (!$serviceId) return;

    if (!$productId) {
        $db->prepare("UPDATE product_names SET linked_service_id = NULL, labor_price = NULL WHERE linked_service_id = ?")
           ->execute([$serviceId]);
        return;
    }

    $service = kpServiceCard($db, $serviceId);
    if (!$service) return;
    $serviceCost = $service['cost'] !== null ? intval(round(floatval($service['cost']))) : null;
    $db->prepare("UPDATE product_names SET linked_service_id = ?, labor_price = ? WHERE id = ?")
       ->execute([$serviceId, $serviceCost, $productId]);
}

function kpEnrichProductsWithLinkedServices($db, $rows) {
    if (!$rows) return $rows;
    $map = [];
    foreach ($rows as $idx => $row) {
        $rows[$idx]['linked_services'] = [];
        $id = intval($row['id'] ?? 0);
        if ($id) $map[$id] = $idx;
    }
    if (!$map) return $rows;
    if (kpProductServiceLinksSchemaReady($db)) {
        $ids = array_keys($map);
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $sql = "SELECT psl.product_name_id, cs.id, cs.name, cs.marking_size, COALESCE(cs.retail_price, cs.cost) AS retail_price,
                       cs.purchase_price, cs.unit, COALESCE(NULLIF(cs.work_section_code,''), 'installation') AS work_section_code
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
                'retail_price' => $svc['retail_price'] !== null ? kpIntValue($svc['retail_price']) : null,
                'purchase_price' => $svc['purchase_price'] !== null ? kpIntValue($svc['purchase_price']) : null,
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
                'retail_price' => $row['linked_service_cost'] !== null ? kpIntValue($row['linked_service_cost']) : null,
                'purchase_price' => ($row['linked_service_purchase_price'] ?? null) !== null
                    ? kpIntValue($row['linked_service_purchase_price'])
                    : null,
                'unit' => $row['linked_service_unit'] ?? '',
                'work_section_code' => $row['work_section_code'] ?? '',
            ];
        }
    }
    return $rows;
}

function kpDeleteProductNameReferences($db, $id) {
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

function kpFindServiceLinkedToOtherProduct($db, $serviceId, $productId = 0) {
    $st = $db->prepare("SELECT id, name FROM product_names WHERE linked_service_id = ? AND id <> ? LIMIT 1");
    $st->execute([intval($serviceId), intval($productId)]);
    return $st->fetch() ?: null;
}

function kpFindOtherServiceForProduct($db, $productId, $serviceId = 0) {
    $productId = intval($productId);
    if (!$productId) return null;
    $st = $db->prepare("SELECT cs.id, cs.name
                          FROM product_names pn
                          JOIN catalog_services cs ON cs.id = pn.linked_service_id
                         WHERE pn.id = ?
                           AND (? = 0 OR cs.id <> ?)
                         LIMIT 1");
    $st->execute([$productId, intval($serviceId), intval($serviceId)]);
    return $st->fetch() ?: null;
}

function kpWorkflowStatuses() {
    return [
        'Составить ПКП',
        'Согласовать ПКП',
        'Согласовать с клиентом',
        'ПКП согласовано',
    ];
}

function kpNormalizeWorkflowStatus($status) {
    $status = trim((string)$status);
    if (preg_match('/^ПКП согласован/u', $status)) $status = 'ПКП согласовано';
    return in_array($status, kpWorkflowStatuses(), true) ? $status : 'Составить ПКП';
}

function kpTransferPkpToKpQuote($db, $quote, array &$payload, $uid) {
    $kpQuoteId = intval($payload['created_kp_quote_id'] ?? 0);
    $title = trim((string)($quote['title'] ?? ''));
    $clientId = !empty($quote['client_id']) ? intval($quote['client_id']) : null;
    $selectedVariant = trim((string)($quote['selected_variant_label'] ?? ''));
    $companySnapshot = $quote['company_snapshot_json'] ?? null;
    $clientSnapshot = $quote['client_snapshot_json'] ?? null;

    $kpPayload = is_array($payload) ? $payload : [];
    $kpPayload['source_workspace'] = 'pkp';
    $kpPayload['source_pkp_quote_id'] = intval($quote['id'] ?? 0);
    $kpPayloadJson = kpEncodePayloadValue($kpPayload);

    if ($kpQuoteId) {
        $st = $db->prepare("SELECT id FROM kp_quotes WHERE id = ? LIMIT 1");
        $st->execute([$kpQuoteId]);
        if ($st->fetch()) {
            $db->prepare("UPDATE kp_quotes
                             SET client_id = ?, title = ?, status = ?, workflow_status = ?, selected_variant_label = ?,
                                 company_snapshot_json = ?, client_snapshot_json = ?, payload_json = ?
                           WHERE id = ?")
               ->execute([$clientId, $title, 'created', 'Составить КП', $selectedVariant ?: null, $companySnapshot, $clientSnapshot, $kpPayloadJson, $kpQuoteId]);
            $payload['created_kp_quote_id'] = $kpQuoteId;
            return $kpQuoteId;
        }
        $kpQuoteId = 0;
    }

    $token = kpMakeToken();
    $db->prepare("INSERT INTO kp_quotes
        (user_id, client_id, title, status, workflow_status, selected_variant_label, company_snapshot_json, client_snapshot_json, payload_json, public_token)
        VALUES (?,?,?,?,?,?,?,?,?,?)")
       ->execute([$uid, $clientId, $title, 'created', 'Составить КП', $selectedVariant ?: null, $companySnapshot, $clientSnapshot, $kpPayloadJson, $token]);
    $kpQuoteId = intval($db->lastInsertId());
    $payload['created_kp_quote_id'] = $kpQuoteId;
    return $kpQuoteId;
}
function kpExtractQuoteMeta($quote, $payload = null) {
    $payload = is_array($payload) ? $payload : kpDecodePayloadRow($quote);
    $client = kpDecodeJsonField($quote['client_snapshot_json'] ?? null);
    $meta = is_array($payload['quote_meta'] ?? null) ? $payload['quote_meta'] : [];
    return [
        'object_address' => trim((string)($meta['object_address'] ?? ($client['object_address'] ?? ''))),
        'object_type' => trim((string)($meta['object_type'] ?? ($client['object_type'] ?? ''))),
        'manager_name' => trim((string)($meta['manager_name'] ?? '')),
        'manager_id' => intval($meta['manager_id'] ?? 0),
        'rop_name' => trim((string)($meta['rop_name'] ?? '')),
        'rop_id' => intval($meta['rop_id'] ?? 0),
    ];
}

function kpNormalizeQuoteMetaForUser(PDO $db, array $user, array &$payloadData, array $existingPayload = []) {
    $meta = is_array($payloadData['quote_meta'] ?? null) ? $payloadData['quote_meta'] : [];
    if (($user['role'] ?? '') !== 'admin') {
        $existingMeta = is_array($existingPayload['quote_meta'] ?? null) ? $existingPayload['quote_meta'] : [];
        if (intval($existingMeta['manager_id'] ?? 0) > 0) {
            foreach (['manager_id', 'manager_name', 'rop_id', 'rop_name'] as $key) {
                if (array_key_exists($key, $existingMeta)) $meta[$key] = $existingMeta[$key];
            }
            $payloadData['quote_meta'] = $meta;
            return;
        }
        $managerId = intval($user['id'] ?? 0);
        $ropId = getManagerRop($managerId);
        $ropName = '';
        if ($ropId) {
            $st = $db->prepare("SELECT full_name, username FROM users WHERE id = ? LIMIT 1");
            $st->execute([$ropId]);
            $rop = $st->fetch();
            $ropName = trim((string)($rop['full_name'] ?? '')) ?: trim((string)($rop['username'] ?? ''));
        }
        $meta['manager_id'] = $managerId;
        $meta['manager_name'] = trim((string)($user['full_name'] ?? '')) ?: trim((string)($user['username'] ?? ''));
        $meta['rop_id'] = intval($ropId ?? 0);
        $meta['rop_name'] = $ropName;
        $payloadData['quote_meta'] = $meta;
        return;
    }

    $managerId = intval($meta['manager_id'] ?? 0);
    if ($managerId) {
        $st = $db->prepare("SELECT id, full_name, username FROM users WHERE id = ? LIMIT 1");
        $st->execute([$managerId]);
        $manager = $st->fetch();
        if (!$manager) kpJson(['error' => 'Выбранный менеджер не найден'], 400);
        $meta['manager_id'] = intval($manager['id']);
        $meta['manager_name'] = trim((string)($manager['full_name'] ?? '')) ?: trim((string)($manager['username'] ?? ''));
    }

    $ropId = intval($meta['rop_id'] ?? 0);
    if (!$ropId && $managerId) $ropId = intval(getManagerRop($managerId) ?? 0);
    if ($ropId) {
        $st = $db->prepare("SELECT id, full_name, username FROM users WHERE id = ? AND role = 'rop' LIMIT 1");
        $st->execute([$ropId]);
        $rop = $st->fetch();
        if (!$rop) kpJson(['error' => 'Выбранный РОП не найден'], 400);
        $meta['rop_id'] = intval($rop['id']);
        $meta['rop_name'] = trim((string)($rop['full_name'] ?? '')) ?: trim((string)($rop['username'] ?? ''));
    } else {
        $meta['rop_id'] = 0;
        $meta['rop_name'] = '';
    }
    $payloadData['quote_meta'] = $meta;
}

function kpGetSelectedVariant($quote) {
    $payload = kpGetQuotePayload($quote);
    $variants = $payload['variants'] ?? [];
    if (!$variants) return [null, $payload];
    $target = $variants[0];
    $selected = trim((string)($quote['selected_variant_label'] ?? ''));
    if ($selected !== '') {
        foreach ($variants as $variant) {
            if (($variant['label'] ?? '') === $selected) {
                $target = $variant;
                break;
            }
        }
    }
    return [$target, $payload];
}

function kpGetTransferMeta($quote, $incomingMeta, $defaultManagerId) {
    [, $payload] = kpGetSelectedVariant($quote);
    $saved = [];
    if (!empty($payload['transfer_meta']) && is_array($payload['transfer_meta'])) {
        $saved = $payload['transfer_meta'];
    }
    $quoteMeta = kpExtractQuoteMeta($quote, $payload);
    $client = $quote['client_snapshot_json'] ? json_decode($quote['client_snapshot_json'], true) : [];
    if (!is_array($client)) $client = [];
    $meta = array_merge($saved, is_array($incomingMeta) ? $incomingMeta : []);
    $meta['address'] = trim((string)($meta['address'] ?? ($quoteMeta['object_address'] ?? 'Адрес уточняется')));
    if ($meta['address'] === '') $meta['address'] = 'Адрес уточняется';
    $meta['order_type'] = trim((string)($meta['order_type'] ?? ($quoteMeta['object_type'] ?? 'Не указан')));
    if ($meta['order_type'] === '') $meta['order_type'] = 'Не указан';
    $meta['client_type'] = trim((string)($meta['client_type'] ?? ($client['company_name'] ?? '')));
    $meta['manager_id'] = intval($meta['manager_id'] ?? ($quoteMeta['manager_id'] ?? $defaultManagerId));
    return $meta;
}

function kpAssertTransferMeta($db, $meta) {
    if (trim((string)($meta['address'] ?? '')) === '') $meta['address'] = 'Адрес уточняется';
    if (trim((string)($meta['order_type'] ?? '')) === '') $meta['order_type'] = 'Не указан';
    if (trim((string)($meta['client_type'] ?? '')) === '') {
        throw new RuntimeException('Укажите тип клиента');
    }
    $managerId = intval($meta['manager_id'] ?? 0);
    if (!$managerId) {
        throw new RuntimeException('Укажите менеджера');
    }
    $st = $db->prepare("SELECT id FROM users WHERE id = ? LIMIT 1");
    $st->execute([$managerId]);
    if (!$st->fetch()) {
        throw new RuntimeException('Выбранный менеджер не найден');
    }
}

function kpLoadProductCard($db, $productNameId) {
    static $cache = [];
    $productNameId = intval($productNameId);
    if (!$productNameId) return null;
    if (array_key_exists($productNameId, $cache)) return $cache[$productNameId];
    $st = $db->prepare(
        "SELECT pn.id, pn.name, pn.marking_size, pn.unit, pn.supplier,
                pn.section_id, s.name AS section_name,
                c.id AS category_id, c.name AS category_name, c.code AS category_code
           FROM product_names pn
           JOIN sections s ON s.id = pn.section_id
           JOIN categories c ON c.id = s.category_id
          WHERE pn.id = ?
          LIMIT 1"
    );
    $st->execute([$productNameId]);
    $cache[$productNameId] = $st->fetch() ?: null;
    return $cache[$productNameId];
}

function kpLoadSectionCard($db, $sectionId) {
    static $cache = [];
    $sectionId = intval($sectionId);
    if (!$sectionId) return null;
    if (array_key_exists($sectionId, $cache)) return $cache[$sectionId];
    $st = $db->prepare(
        "SELECT s.id AS section_id, s.name AS section_name, s.code AS section_code,
                c.id AS category_id, c.name AS category_name, c.code AS category_code
           FROM sections s
           JOIN categories c ON c.id = s.category_id
          WHERE s.id = ?
          LIMIT 1"
    );
    $st->execute([$sectionId]);
    $cache[$sectionId] = $st->fetch() ?: null;
    return $cache[$sectionId];
}

function kpBuildComplectationSnapshot($db, $items) {
    $cats = [];
    $catIndex = [];
    foreach ($items as $item) {
    $qty = kpIntValue($item['quantity'] ?? 0);
        $nameId = intval($item['product_name_id'] ?? 0);
        $card = $nameId ? kpLoadProductCard($db, $nameId) : null;
        $sectionMeta = !$card ? kpLoadSectionCard($db, intval($item['section_id'] ?? 0)) : null;
        if (!kpIsComplectationCategoryAllowed($item, $card ?: $sectionMeta)) continue;
        $catId = intval($item['category_id'] ?? ($card['category_id'] ?? ($sectionMeta['category_id'] ?? 0)));
        $secId = intval($item['section_id'] ?? ($card['section_id'] ?? ($sectionMeta['section_id'] ?? 0)));
        $name = trim((string)($item['name'] ?? ($card['name'] ?? '')));
        if ($qty <= 0 || !$catId || !$secId || $name === '') continue;

        $catName = trim((string)($item['category_name'] ?? ($card['category_name'] ?? ($sectionMeta['category_name'] ?? ''))));
        $catCode = trim((string)($item['category_code'] ?? ($card['category_code'] ?? ($sectionMeta['category_code'] ?? ''))));
        $secName = trim((string)($item['section_name'] ?? ($card['section_name'] ?? ($sectionMeta['section_name'] ?? ''))));
        $marking = trim((string)($item['marking_size'] ?? ($card['marking_size'] ?? '')));
        $unit = trim((string)($item['unit'] ?? ($card['unit'] ?? getDefaultMeasurementUnitName())));
        $supplier = trim((string)($item['supplier'] ?? ($card['supplier'] ?? '')));
        $catKey = 'c' . $catId;
        if (!isset($catIndex[$catKey])) {
            $catIndex[$catKey] = count($cats);
            $cats[] = [
                'catId' => $catId,
                'catName' => $catName ?: 'Категория',
                'catCode' => $catCode,
                'sections' => [],
            ];
        }
        $ci = $catIndex[$catKey];
        if (!isset($cats[$ci]['_secIndex'])) $cats[$ci]['_secIndex'] = [];
        $secKey = 's' . $secId;
        if (!isset($cats[$ci]['_secIndex'][$secKey])) {
            $cats[$ci]['_secIndex'][$secKey] = count($cats[$ci]['sections']);
            $cats[$ci]['sections'][] = [
                'secId' => $secId,
                'secName' => $secName ?: 'Раздел',
                'isDozakaz' => false,
                'items' => [],
            ];
        }
        $si = $cats[$ci]['_secIndex'][$secKey];
        $cats[$ci]['sections'][$si]['items'][] = [
            'nameId' => $nameId ?: null,
            'nameTxt' => $name,
            'isCustom' => !$nameId,
            'marking_size' => $marking,
            'quantity' => $qty,
            'unit' => $unit,
            'note' => trim((string)($item['note'] ?? '')),
            'supplier' => $supplier,
            'komplektaciya' => $marking,
            'dozakaz' => 0,
            'invoice_check' => '',
            'shipment_status' => '',
            'markingSizeOptions' => $marking !== '' ? [$marking] : [],
            'komplektaciyaOptions' => [],
        ];
    }
    foreach ($cats as &$cat) {
        unset($cat['_secIndex']);
    }
    unset($cat);
    return $cats;
}

function kpBuildComplectationItems($db, $items) {
    $rows = [];
    foreach ($items as $item) {
    $qty = kpIntValue($item['quantity'] ?? 0);
        $nameId = intval($item['product_name_id'] ?? 0);
        $card = $nameId ? kpLoadProductCard($db, $nameId) : null;
        $sectionMeta = !$card ? kpLoadSectionCard($db, intval($item['section_id'] ?? 0)) : null;
        if (!kpIsComplectationCategoryAllowed($item, $card ?: $sectionMeta)) continue;
        $catId = intval($item['category_id'] ?? ($card['category_id'] ?? ($sectionMeta['category_id'] ?? 0)));
        $secId = intval($item['section_id'] ?? ($card['section_id'] ?? ($sectionMeta['section_id'] ?? 0)));
        $name = trim((string)($item['name'] ?? ($card['name'] ?? '')));
        if ($qty <= 0 || !$catId || !$secId || $name === '') continue;
        $marking = trim((string)($item['marking_size'] ?? ($card['marking_size'] ?? '')));
        $unit = trim((string)($item['unit'] ?? ($card['unit'] ?? getDefaultMeasurementUnitName())));
        $supplier = trim((string)($item['supplier'] ?? ($card['supplier'] ?? '')));
        $rows[] = [
            'category_id' => $catId,
            'section_id' => $secId,
            'product_name_id' => $nameId ?: null,
            'custom_name' => $nameId ? null : $name,
            'name_txt' => $name,
            'marking' => $marking,
            'size_value' => $marking,
            'marking_size' => $marking,
            'quantity' => $qty,
            'dozakaz' => 0,
            'unit' => $unit,
            'note' => trim((string)($item['note'] ?? '')),
            'supplier' => $supplier,
            'komplektaciya' => $marking,
            'invoice_check' => '',
            'shipment_status' => '',
        ];
    }
    return $rows;
}

function kpCreateOrderFromQuote($db, $quote, $userId, $transferMeta) {
    [$target] = kpGetSelectedVariant($quote);
    if (!$target) return null;
    $items = $target['items'] ?? [];
    if (!$items) return null;

    kpAssertTransferMeta($db, $transferMeta);
    $snapshotRows = kpBuildComplectationSnapshot($db, $items);
    $productRows = kpBuildComplectationItems($db, $items);
    if (!$snapshotRows || !$productRows) {
        throw new RuntimeException('В выбранном варианте КП нет подходящих товаров для комплектации');
    }

    $managerId = intval($transferMeta['manager_id']);
    $address = trim((string)$transferMeta['address']);
    $orderType = trim((string)$transferMeta['order_type']);
    $clientType = trim((string)$transferMeta['client_type']);
    $orderNum = getNextOrderNumber($orderType ?: null);
    $ropId = getManagerRop($managerId);
    $snapshot = json_encode($snapshotRows, JSON_UNESCAPED_UNICODE);

    $db->prepare("INSERT INTO orders (order_number, address, manager_id, rop_id, order_type, client_type, status_order, doc_snapshot)
                  VALUES (?,?,?,?,?,?,'Составление комплектации',?)")
       ->execute([$orderNum, $address, $managerId, $ropId, $orderType, $clientType, $snapshot]);
    $orderId = intval($db->lastInsertId());

    $insertProduct = $db->prepare("INSERT INTO products
        (category_id, section_id, product_name_id, custom_name, order_id, marking, size_value, quantity, dozakaz, unit, note, komplektaciya, supplier, address, status, invoice_check, shipment_status, created_by)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");

    foreach ($productRows as $item) {
        $insertProduct->execute([
            intval($item['category_id']),
            intval($item['section_id']),
            $item['product_name_id'],
            $item['custom_name'],
            $orderId,
            $item['marking'],
            $item['size_value'],
            kpIntValue($item['quantity']),
            0,
            $item['unit'],
            $item['note'],
            $item['komplektaciya'],
            $item['supplier'],
            $address,
            'Согласовано',
            '',
            '',
            $managerId
        ]);
    }
    return $orderId;
}

switch ($action) {
    case 'catalog_products':
        $sql = "SELECT pn.id, pn.group_name, pn.name, pn.note, pn.marking_size, pn.unit, pn.purchase_price, pn.minimal_price, pn.retail_price, pn.price_type,
                       pn.labor_price, pn.supplier, pn.section_id, s.name AS section_name, c.id AS category_id,
                       s.code AS section_code, c.name AS category_name, c.code AS category_code,
                       pn.linked_service_id, cs.name AS linked_service_name, cs.cost AS linked_service_cost, cs.unit AS linked_service_unit
                  FROM product_names pn
                  JOIN sections s ON s.id = pn.section_id
                  JOIN categories c ON c.id = s.category_id
                  LEFT JOIN catalog_services cs ON cs.id = pn.linked_service_id
                 WHERE c.code IN ('equipment','incidental_expenses','kits')
                   AND pn.status = 'Согласовано'
                 ORDER BY c.sort_order, s.sort_order, pn.sort_order, pn.name, pn.marking_size";
        kpJson(kpEnrichProductsWithLinkedServices($db, $db->query($sql)->fetchAll()));
        break;

    case 'catalog_services':
        $linksReady = kpProductServiceLinksSchemaReady($db);
        $linkedCountExpr = $linksReady ? "COUNT(DISTINCT COALESCE(psl.product_name_id, pn.id))" : "COUNT(DISTINCT pn.id)";
        $linkJoinSql = $linksReady
            ? "LEFT JOIN product_service_links psl ON psl.service_id = cs.id
                  LEFT JOIN product_names pn ON pn.id = psl.product_name_id OR pn.linked_service_id = cs.id"
            : "LEFT JOIN product_names pn ON pn.linked_service_id = cs.id";
        $sql = "SELECT cs.id, cs.name, cs.cost, COALESCE(cs.retail_price, cs.cost) AS retail_price,
                       cs.marking_size, cs.purchase_price, cs.minimal_price,
                       cs.unit, COALESCE(NULLIF(cs.work_section_code,''), 'installation') AS work_section_code,
                       {$linkedCountExpr} AS linked_products_count
                  FROM catalog_services cs
                  {$linkJoinSql}
                 GROUP BY cs.id
                 ORDER BY cs.name, cs.id DESC";
        kpJson($db->query($sql)->fetchAll());
        break;

    case 'catalog_sections':
        $st = $db->query("SELECT s.id, s.name, s.code, c.name AS category_name, c.code AS category_code
                            FROM sections s
                            JOIN categories c ON c.id = s.category_id
                           WHERE c.code IN ('equipment','materials','work','construction_works','maintenance','incidental_expenses','kits')
                           ORDER BY c.sort_order, s.sort_order, s.name");
        kpJson($st->fetchAll());
        break;

    case 'save_catalog_product':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        $sectionId = intval($input['section_id'] ?? 0);
        $section = kpAllowedSection($db, $sectionId);
        if (!$section) kpJson(['error' => 'Раздел должен относиться к Оборудованию или Материалам'], 400);

        $name = trim((string)($input['name'] ?? ''));
        if ($name === '') kpJson(['error' => 'Название обязательно'], 400);
        $groupName = trim((string)($input['group_name'] ?? ''));
        $marking = trim((string)($input['marking_size'] ?? ''));
        $note = trim((string)($input['note'] ?? ''));
        $unit = trim((string)($input['unit'] ?? getDefaultMeasurementUnitName()));
        $supplier = trim((string)($input['supplier'] ?? ''));
        $purchase = ($input['purchase_price'] ?? '') !== '' ? kpIntValue($input['purchase_price']) : null;
        $retail = ($input['retail_price'] ?? '') !== '' ? kpIntValue($input['retail_price']) : null;
        $minimal = ($input['minimal_price'] ?? '') !== '' ? kpIntValue($input['minimal_price']) : null;
        $linkedServiceId = intval($input['linked_service_id'] ?? 0);
        if (!$id && ($retail === null || intval($retail) <= 0)) kpJson(['error' => 'Розничная цена должна быть больше 0'], 400);
        $scopeError = kpValidateProductServiceScope($db, $section, $linkedServiceId);
        if ($scopeError) kpJson(['error' => $scopeError], 409);
        if (false && $linkedServiceId) {
            $serviceConflict = kpFindServiceLinkedToOtherProduct($db, $linkedServiceId, $id);
            if ($serviceConflict) kpJson(['error' => 'Эта работа уже привязана к другому товару'], 409);
        }

        if ($id) {
            $db->prepare("UPDATE product_names
                             SET section_id = ?, group_name = ?, name = ?, status = 'Согласовано', note = ?, marking_size = ?, unit = ?, supplier = ?,
                                 purchase_price = ?, minimal_price = ?, retail_price = ?
                           WHERE id = ?")
               ->execute([$sectionId, $groupName !== '' ? $groupName : null, $name, $note ?: null, $marking, $unit, $supplier, $purchase, $minimal, $retail, $id]);
            kpSyncProductService($db, $id, $linkedServiceId);
            kpJson(['ok' => true, 'id' => $id]);
        }

        $db->prepare("INSERT INTO product_names
            (section_id, group_name, name, status, note, marking_size, unit, supplier, purchase_price, minimal_price, retail_price, created_by)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)")
           ->execute([$sectionId, $groupName !== '' ? $groupName : null, $name, 'Согласовано', $note ?: null, $marking, $unit, $supplier, $purchase, $minimal, $retail, $uid ?: null]);
        $newId = intval($db->lastInsertId());
        kpSyncProductService($db, $newId, $linkedServiceId);
        kpJson(['ok' => true, 'id' => $newId]);
        break;

    case 'delete_catalog_product':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        if (!kpCanDelete($role)) kpJson(['error' => 'Forbidden'], 403);
        $id = intval($input['id'] ?? 0);
        if ($id <= 0) kpJson(['error' => 'Invalid id'], 400);
        $st = $db->prepare(
            "SELECT pn.id
               FROM product_names pn
               JOIN sections s ON s.id = pn.section_id
               JOIN categories c ON c.id = s.category_id
              WHERE pn.id = ?
                AND c.code IN ('equipment','materials')
              LIMIT 1"
        );
        $st->execute([$id]);
        if (!$st->fetch()) kpJson(['error' => 'Product not found'], 404);
        try {
            $db->beginTransaction();
            kpDeleteProductNameReferences($db, $id);
            $db->prepare("UPDATE product_names SET linked_service_id = NULL, labor_price = NULL WHERE id = ?")->execute([$id]);
            $db->prepare("DELETE FROM product_names WHERE id = ?")->execute([$id]);
            $db->commit();
            kpJson(['ok' => true]);
        } catch (Throwable $e) {
            if ($db->inTransaction()) $db->rollBack();
            kpJson(['error' => 'Не удалось удалить товар'], 500);
        }
        break;

    case 'delete_catalog_service':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        if (!kpCanDelete($role)) kpJson(['error' => 'Forbidden'], 403);
        $id = intval($input['id'] ?? 0);
        if ($id <= 0) kpJson(['error' => 'Invalid id'], 400);
        try {
            $db->beginTransaction();
            $db->prepare("UPDATE product_names SET linked_service_id = NULL, labor_price = NULL WHERE linked_service_id = ?")
               ->execute([$id]);
            $db->prepare("DELETE FROM catalog_services WHERE id = ?")->execute([$id]);
            $db->commit();
            kpJson(['ok' => true]);
        } catch (Throwable $e) {
            if ($db->inTransaction()) $db->rollBack();
            kpJson(['error' => 'Не удалось удалить монтаж'], 500);
        }
        break;

    case 'save_catalog_service':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        $name = trim((string)($input['name'] ?? ''));
        if ($name === '') kpJson(['error' => 'Название обязательно'], 400);
        $cost = ($input['cost'] ?? '') !== '' ? kpIntValue($input['cost']) : 0;
        $productId = intval($input['linked_product_name_id'] ?? 0);
        $scopeCode = '';
        $unit = trim((string)($input['unit'] ?? ''));
        if ($id) {
            $db->prepare("UPDATE catalog_services SET name = ?, cost = ?, unit = ?, linked_product_name_id = NULL WHERE id = ?")
               ->execute([$name, $cost, $unit ?: null, $id]);
            kpJson(['ok' => true, 'id' => $id]);
        }

        $db->prepare("INSERT INTO catalog_services (name, cost, unit, linked_product_name_id) VALUES (?, ?, ?, NULL)")
           ->execute([$name, $cost, $unit ?: null]);
        $newId = intval($db->lastInsertId());
        kpJson(['ok' => true, 'id' => $newId]);
        if ($productId) {
            $check = $db->prepare(
                "SELECT pn.id
                   FROM product_names pn
                   JOIN sections s ON s.id = pn.section_id
                   JOIN categories c ON c.id = s.category_id
                  WHERE pn.id = ?
                    AND c.code IN ('equipment','materials')
                  LIMIT 1"
            );
            $check->execute([$productId]);
            if (!$check->fetch()) kpJson(['error' => 'Можно привязать только товар из оборудования или материалов'], 400);
            $productConflict = kpFindOtherServiceForProduct($db, $productId, $id);
            if ($productConflict) kpJson(['error' => 'К выбранному товару уже привязана работа: ' . $productConflict['name']], 409);
        }

        if ($id) {
            $db->prepare("UPDATE catalog_services SET name = ?, cost = ?, unit = ?, linked_product_name_id = NULL WHERE id = ?")
               ->execute([$name, $cost, $unit ?: null, $id]);
            kpSyncServiceProduct($db, $id, $productId);
            kpJson(['ok' => true, 'id' => $id]);
        }

        $db->prepare("INSERT INTO catalog_services (name, cost, unit, linked_product_name_id) VALUES (?, ?, ?, NULL)")
           ->execute([$name, $cost, $unit ?: null]);
        $newId = intval($db->lastInsertId());
        kpSyncServiceProduct($db, $newId, $productId);
        kpJson(['ok' => true, 'id' => $newId]);
        break;
    case 'company_get':
        $rows = kpLoadSharedCompanyProfiles($db, $uid);
        foreach ($rows as &$profileRow) {
            $profileRow['autofill_fields_json'] = $profileRow['autofill_fields_json'] ?: json_encode([]);
        }
        unset($profileRow);
        $row = $rows[0] ?? ['autofill_fields_json' => json_encode([]), 'profiles' => []];
        $row['profiles'] = $rows;
        kpJson($row);
        break;

    case 'company_save':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        $fields = [
            'company_type','company_name','legal_name','inn','ogrn','kpp','address','phone','email','website',
            'director_name','signatory_name','signatory_title','bank_name','bank_bik',
            'bank_account','corr_account','intro_default','footer_default'
        ];
        $payload = [];
        foreach ($fields as $field) {
            $payload[$field] = trim((string)($input[$field] ?? ''));
        }
        $autofill = $input['autofill_fields'] ?? [];
        if (!is_array($autofill)) $autofill = [];
        $json = json_encode(array_values(array_unique(array_map('strval', $autofill))), JSON_UNESCAPED_UNICODE);

        $profileUserId = kpCompanyProfileOwnerId($db, $uid);
        $id = intval($input['id'] ?? 0);
        if ($id > 0) {
            $check = $db->prepare("SELECT id FROM company_profiles WHERE id = ? AND user_id = ?");
            $check->execute([$id, $profileUserId]);
            if (!$check->fetch()) kpJson(['error' => 'Компания не найдена'], 404);
        }
        accessAssert($user, 'company', $id ? 'edit' : 'create');
        if ($id) {
            $db->prepare("UPDATE company_profiles SET
                company_type=?, company_name=?, legal_name=?, inn=?, ogrn=?, kpp=?, address=?, phone=?, email=?, website=?,
                director_name=?, signatory_name=?, signatory_title=?, bank_name=?, bank_bik=?, bank_account=?,
                corr_account=?, intro_default=?, footer_default=?, autofill_fields_json=?
                WHERE id=? AND user_id=?")
               ->execute([
                   $payload['company_type'] ?: 'ooo', $payload['company_name'], $payload['legal_name'], $payload['inn'], $payload['ogrn'], $payload['kpp'],
                   $payload['address'], $payload['phone'], $payload['email'], $payload['website'],
                   $payload['director_name'], $payload['signatory_name'], $payload['signatory_title'],
                   $payload['bank_name'], $payload['bank_bik'], $payload['bank_account'],
                   $payload['corr_account'], $payload['intro_default'], $payload['footer_default'], $json, $id, $profileUserId
               ]);
        } else {
            $hasDefault = $db->prepare("SELECT id FROM company_profiles WHERE user_id = ? AND is_default = 1 LIMIT 1");
            $hasDefault->execute([$profileUserId]);
            $isDefault = $hasDefault->fetch() ? 0 : 1;
            $db->prepare("INSERT INTO company_profiles
                (user_id, company_type, company_name, legal_name, inn, ogrn, kpp, address, phone, email, website,
                 director_name, signatory_name, signatory_title, bank_name, bank_bik, bank_account,
                 corr_account, intro_default, footer_default, autofill_fields_json, is_default)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
               ->execute([
                   $profileUserId, $payload['company_type'] ?: 'ooo', $payload['company_name'], $payload['legal_name'], $payload['inn'], $payload['ogrn'], $payload['kpp'],
                   $payload['address'], $payload['phone'], $payload['email'], $payload['website'],
                   $payload['director_name'], $payload['signatory_name'], $payload['signatory_title'],
                   $payload['bank_name'], $payload['bank_bik'], $payload['bank_account'],
                   $payload['corr_account'], $payload['intro_default'], $payload['footer_default'], $json, $isDefault
               ]);
            $id = intval($db->lastInsertId());
        }
        kpJson(['ok' => true, 'id' => $id]);
        break;

    case 'company_set_default':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'company', 'edit');
        $profileUserId = kpCompanyProfileOwnerId($db, $uid);
        $id = intval($input['id'] ?? 0);
        if ($id <= 0) kpJson(['error' => 'Компания не выбрана'], 400);
        $check = $db->prepare("SELECT id FROM company_profiles WHERE id = ? AND user_id = ?");
        $check->execute([$id, $profileUserId]);
        if (!$check->fetch()) kpJson(['error' => 'Компания не найдена'], 404);
        $db->beginTransaction();
        $db->prepare("UPDATE company_profiles SET is_default = 0 WHERE user_id = ?")->execute([$profileUserId]);
        $db->prepare("UPDATE company_profiles SET is_default = 1 WHERE id = ? AND user_id = ?")->execute([$id, $profileUserId]);
        $db->commit();
        kpJson(['ok' => true]);
        break;

    case 'company_delete':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'company', 'delete');
        $profileUserId = kpCompanyProfileOwnerId($db, $uid);
        $id = intval($input['id'] ?? 0);
        if ($id <= 0) kpJson(['error' => 'Компания не выбрана'], 400);
        $count = $db->prepare("SELECT COUNT(*) AS cnt FROM company_profiles WHERE user_id = ?");
        $count->execute([$profileUserId]);
        if (intval($count->fetch()['cnt'] ?? 0) <= 1) kpJson(['error' => 'Нельзя удалить единственную компанию'], 400);
        $db->prepare("DELETE FROM company_profiles WHERE id = ? AND user_id = ?")->execute([$id, $profileUserId]);
        $hasDefault = $db->prepare("SELECT id FROM company_profiles WHERE user_id = ? AND is_default = 1 LIMIT 1");
        $hasDefault->execute([$profileUserId]);
        if (!$hasDefault->fetch()) {
            $first = $db->prepare("SELECT id FROM company_profiles WHERE user_id = ? ORDER BY id LIMIT 1");
            $first->execute([$profileUserId]);
            $firstId = intval($first->fetch()['id'] ?? 0);
            if ($firstId) $db->prepare("UPDATE company_profiles SET is_default = 1 WHERE id = ?")->execute([$firstId]);
        }
        kpJson(['ok' => true]);
        break;

    case 'company_lookup_inn':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        $inn = preg_replace('/\D+/', '', (string)($input['inn'] ?? ''));
        if ($inn === '') kpJson(['error' => 'ИНН обязателен'], 400);
        try {
            $extract = kpFetchOfficialExtractByInn($inn);
            $pdfText = kpPdfExtractText((string)($extract['pdf'] ?? ''));
            $parsed = kpParseCompanyExtract($pdfText, $inn);
            $row = is_array($extract['row'] ?? null) ? $extract['row'] : [];
        } catch (Throwable $e) {
            kpJson(['error' => 'Не удалось получить официальную выписку ФНС: ' . $e->getMessage()], 502);
        }

        $companyType = $parsed['company_type'] ?: (strlen($inn) === 12 ? 'ip' : 'ooo');
        $companyName = $parsed['company_name']
            ?: kpSearchRowValue($row, ['n', 'name', 'full_name', 'fullName', 'c', 'na']);
        $legalName = $parsed['legal_name'] ?: $companyName;
        $ogrn = $parsed['ogrn']
            ?: kpSearchRowValue($row, ['o', 'ogrn', 'ogrnip', 'ogrnip', 'ОГРН', 'ОГРНИП']);
        $ogrnDigits = preg_replace('/\D+/', '', (string)$ogrn);
        if ($ogrnDigits !== '' && in_array(strlen($ogrnDigits), [13, 15], true)) {
            $ogrn = $ogrnDigits;
        }
        $kpp = $parsed['kpp']
            ?: kpSearchRowValue($row, ['k', 'kpp', 'КПП']);
        $address = $parsed['address']
            ?: kpSearchRowValue($row, ['a', 'a1', 'address', 'addr', 'АдресПолн', 'АдрПолн', 'Адрес', 'ЮрАдрес']);
        $directorName = $parsed['director_name']
            ?: kpSearchRowValue($row, ['g', 'gen', 'director', 'Руководитель', 'manager']);
        $bankName = $parsed['bank_name']
            ?: kpSearchRowValue($row, ['bank_name', 'bank']);

        kpJson([
            'company_type' => $companyType,
            'company_name' => $companyName,
            'legal_name' => $legalName,
            'inn' => $parsed['inn'] ?: $inn,
            'ogrn' => $ogrn,
            'kpp' => $kpp,
            'address' => $address,
            'director_name' => $directorName,
            'bank_name' => $bankName,
            'bank_bik' => $parsed['bank_bik'],
            'bank_account' => $parsed['bank_account'],
            'corr_account' => $parsed['corr_account'],
            'email' => $parsed['email']
        ]);
        break;

    case 'clients':
        $pagination = paginationFromRequest(50, 200);
        $baseSql = "FROM kp_clients";
        $st = $db->prepare("SELECT id, user_id, company_type, company_name, legal_name, inn, ogrn, kpp, object_type, object_address, recipient_name, salutation, proposal_title, intro_text, phone, email, bank_name, bank_bik, note, created_at, updated_at {$baseSql} ORDER BY updated_at DESC, id DESC" . paginationLimitSql($pagination));
        $st->execute();
        $items = $st->fetchAll();
        if ($pagination) kpJson(paginationPayload($items, paginationCount($db, $baseSql), $pagination));
        kpJson($items);
        break;

    case 'save_client':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        accessAssert($user, 'company', $id > 0 ? 'edit' : 'create');
        $companyName = trim((string)($input['company_name'] ?? ''));
        if ($companyName === '') kpJson(['error' => 'Название компании обязательно'], 400);
        $companyType = trim((string)($input['company_type'] ?? 'ooo'));
        if (!in_array($companyType, ['person', 'ip', 'ooo'], true)) {
            $companyType = 'ooo';
        }
        $legalName = trim((string)($input['legal_name'] ?? $input['recipient_name'] ?? ''));
        $vals = [
            $companyType,
            $companyName,
            $legalName,
            trim((string)($input['inn'] ?? '')),
            trim((string)($input['ogrn'] ?? '')),
            trim((string)($input['kpp'] ?? '')),
            trim((string)($input['object_address'] ?? '')),
            $legalName,
            trim((string)($input['phone'] ?? '')),
            trim((string)($input['email'] ?? '')),
            trim((string)($input['bank_name'] ?? '')),
            trim((string)($input['bank_bik'] ?? '')),
            trim((string)($input['note'] ?? '')),
        ];
        if ($id) {
            $db->prepare("UPDATE kp_clients
                             SET company_type=?, company_name=?, legal_name=?, inn=?, ogrn=?, kpp=?, object_address=?, recipient_name=?, phone=?, email=?, bank_name=?, bank_bik=?, note=?
                           WHERE id=?")
               ->execute(array_merge($vals, [$id]));
            kpJson(['ok' => true, 'id' => $id]);
        }
        $db->prepare("INSERT INTO kp_clients
            (user_id, company_type, company_name, legal_name, inn, ogrn, kpp, object_address, recipient_name, phone, email, bank_name, bank_bik, note)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
           ->execute(array_merge([$uid], $vals));
        kpJson(['ok' => true, 'id' => intval($db->lastInsertId())]);
        break;

    case 'delete_client':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'company', 'delete');
        $id = intval($input['id'] ?? 0);
        $db->prepare("DELETE FROM kp_clients WHERE id = ?")->execute([$id]);
        kpJson(['ok' => true]);
        break;

    case 'quotes':
        $pagination = paginationFromRequest(50, 200);
        $scopeIds = kpScopeUserIds($user);
        $whereParts = [];
        $params = [];
        if ($scopeIds) {
            $whereParts[] = "q.user_id IN (" . implode(',', array_fill(0, count($scopeIds), '?')) . ")";
            foreach ($scopeIds as $sid) $params[] = intval($sid);
        }
        $workflowStatus = trim((string)($_GET['workflow_status'] ?? ''));
        if ($workflowStatus !== '') {
            $whereParts[] = "q.workflow_status = ?";
            $params[] = kpNormalizeWorkflowStatus($workflowStatus);
        }
        $where = $whereParts ? "WHERE " . implode(' AND ', $whereParts) : '';
        $changeOrderSql = "CASE
            WHEN NULLIF(JSON_UNQUOTE(JSON_EXTRACT(q.payload_json, '$.last_workflow_change.changed_at')), '') IS NOT NULL
              OR NULLIF(JSON_UNQUOTE(JSON_EXTRACT(q.payload_json, '$.last_card_change.changed_at')), '') IS NOT NULL
            THEN GREATEST(
                COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(q.payload_json, '$.last_workflow_change.changed_at')), ''), '0000-00-00 00:00:00'),
                COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(q.payload_json, '$.last_card_change.changed_at')), ''), '0000-00-00 00:00:00')
            )
            ELSE GREATEST(
                COALESCE(q.updated_at, '0000-00-00 00:00:00'),
                COALESCE(q.created_at, '0000-00-00 00:00:00')
            )
        END";
        $st = $db->prepare("SELECT q.id, q.title, q.status, q.workflow_status, q.selected_variant_label, q.public_token, q.public_open_count,
                                   q.created_at, q.updated_at, q.sent_at, q.viewed_at, q.is_archived, q.archived_at, q.payload_json, q.client_snapshot_json,
                                   c.company_name AS client_company_name
                              FROM pkp_quotes q
                              LEFT JOIN kp_clients c ON c.id = q.client_id
                              $where
                             ORDER BY $changeOrderSql DESC, q.id DESC" . paginationLimitSql($pagination));
        $st->execute($params);
        $rows = $st->fetchAll();
        foreach ($rows as &$row) {
            $payload = kpDecodePayloadRow($row);
            $row['payload'] = $payload;
            $row['last_workflow_change'] = $payload['last_workflow_change'] ?? null;
            $row['last_card_change'] = $payload['last_card_change'] ?? null;
            $meta = kpExtractQuoteMeta($row, $payload);
            $row['object_address'] = $meta['object_address'];
            $row['object_type'] = $meta['object_type'];
            $row['manager_name'] = $meta['manager_name'];
            $row['rop_name'] = $meta['rop_name'];
            $row['public_url'] = '/quote.php?token=' . $row['public_token'];
            $summary = kpQuoteListSummary($payload, (string)($row['selected_variant_label'] ?? ''));
            $row['selected_variant_summary'] = $summary;
            $row['selected_variant_total'] = $summary['total'];
            $row['kanban_order'] = $summary['kanban_order'];
            unset($row['payload'], $row['payload_json']);
        }
        if ($pagination) {
            $countFrom = "FROM pkp_quotes q $where";
            kpJson(paginationPayload($rows, paginationCount($db, $countFrom, $params), $pagination));
        }
        kpJson($rows);
        break;

    case 'quote_meta':
        $id = intval($_GET['id'] ?? 0);
        $st = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $row = $st->fetch();
        if (!$row) kpJson(['error' => 'Not found'], 404);
        kpAssertQuoteAccess($user, $row);
        $row['company_snapshot'] = $row['company_snapshot_json'] ? json_decode($row['company_snapshot_json'], true) : null;
        $row['client_snapshot'] = $row['client_snapshot_json'] ? json_decode($row['client_snapshot_json'], true) : null;
        $payload = kpDecodePayloadRow($row);
        $row['payload_meta'] = is_array($payload['quote_meta'] ?? null) ? $payload['quote_meta'] : [];
        $row['payload_additional_info'] = array_key_exists('additional_info', $payload) ? (string)$payload['additional_info'] : '';
        $row['last_workflow_change'] = $payload['last_workflow_change'] ?? null;
        $row['last_card_change'] = $payload['last_card_change'] ?? null;
        $row['payload_loaded'] = false;
        $row['public_url'] = '/quote.php?token=' . $row['public_token'];
        unset($row['payload_json']);
        kpJson($row);
        break;

    case 'quote_detail':
        $id = intval($_GET['id'] ?? 0);
        $st = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $row = $st->fetch();
        if (!$row) kpJson(['error' => 'Не найдено'], 404);
        kpAssertQuoteAccess($user, $row);
        $row['company_snapshot'] = $row['company_snapshot_json'] ? json_decode($row['company_snapshot_json'], true) : null;
        $row['client_snapshot'] = $row['client_snapshot_json'] ? json_decode($row['client_snapshot_json'], true) : null;
        $row['payload'] = $row['payload_json'] ? json_decode($row['payload_json'], true) : null;
        $row['last_workflow_change'] = is_array($row['payload']) ? ($row['payload']['last_workflow_change'] ?? null) : null;
        $row['last_card_change'] = is_array($row['payload']) ? ($row['payload']['last_card_change'] ?? null) : null;
        $row['public_url'] = '/quote.php?token=' . $row['public_token'];
        kpJson($row);
        break;

    case 'save_quote':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        $id = intval($input['id'] ?? 0);
        if ($id) {
            $ownSt = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
            $ownSt->execute([$id]);
            $ownQuote = $ownSt->fetch();
            if (!$ownQuote) kpJson(['error' => 'Не найдено'], 404);
            kpAssertQuoteAccess($user, $ownQuote);
            accessAssert($user, 'kp', 'edit');
        } else {
            accessAssert($user, 'kp', 'create');
        }
        $title = trim((string)($input['title'] ?? ''));
        if ($title === '') kpJson(['error' => 'Название ПКП обязательно'], 400);
        $status = kpNormalizeStatus((string)($input['status'] ?? 'created'));
        $workflowStatus = trim((string)($input['workflow_status'] ?? 'Составить ПКП'));
        $clientId = intval($input['client_id'] ?? 0) ?: null;
        $companySnapshot = json_encode($input['company_snapshot'] ?? null, JSON_UNESCAPED_UNICODE);
        $clientSnapshot = json_encode($input['client_snapshot'] ?? null, JSON_UNESCAPED_UNICODE);
        $payloadData = is_array($input['payload'] ?? null) ? kpNormalizeNumericPayload($input['payload']) : [];
        $selectedVariantProvided = array_key_exists('selected_variant_label', $input);
        $selectedVariant = trim((string)($input['selected_variant_label'] ?? ''));

        if ($id) {
            $oldPayload = [];
            $st = $db->prepare("SELECT payload_json, selected_variant_label FROM pkp_quotes WHERE id = ? LIMIT 1");
            $st->execute([$id]);
            $existing = $st->fetch();
            if ($existing) {
                if (!$selectedVariantProvided) {
                    $selectedVariant = trim((string)($existing['selected_variant_label'] ?? ''));
                }
                $oldPayload = kpDecodePayloadRow($existing);
                foreach (['last_workflow_change', 'created_kp_quote_id'] as $key) {
                    if (array_key_exists($key, $oldPayload) && !array_key_exists($key, $payloadData)) {
                        $payloadData[$key] = $oldPayload[$key];
                    }
                }
            }
            kpNormalizeQuoteMetaForUser($db, $user, $payloadData, $oldPayload);
            $payloadData['last_card_change'] = kpBuildWorkflowChangedMeta($user, $workflowStatus);
            kpSyncPendingCatalogProducts($db, $payloadData, $uid);
            $payload = json_encode($payloadData, JSON_UNESCAPED_UNICODE);
            $db->prepare("UPDATE pkp_quotes
                             SET client_id=?, title=?, status=?, workflow_status=?, selected_variant_label=?, company_snapshot_json=?, client_snapshot_json=?, payload_json=?
                           WHERE id=?")
               ->execute([$clientId, $title, $status, $workflowStatus, $selectedVariant ?: null, $companySnapshot, $clientSnapshot, $payload, $id]);
            kpSyncQuotePayloadRows($db, 'pkp', $id, $payloadData);
            kpJson(['ok' => true, 'id' => $id]);
        }

        $token = kpMakeToken();
        kpNormalizeQuoteMetaForUser($db, $user, $payloadData);
        $payloadData['last_card_change'] = kpBuildWorkflowChangedMeta($user, $workflowStatus);
        kpSyncPendingCatalogProducts($db, $payloadData, $uid);
        $payload = json_encode($payloadData, JSON_UNESCAPED_UNICODE);
        $db->prepare("INSERT INTO pkp_quotes
            (user_id, client_id, title, status, workflow_status, selected_variant_label, company_snapshot_json, client_snapshot_json, payload_json, public_token)
            VALUES (?,?,?,?,?,?,?,?,?,?)")
           ->execute([$uid, $clientId, $title, $status, $workflowStatus, $selectedVariant ?: null, $companySnapshot, $clientSnapshot, $payload, $token]);
        $newId = intval($db->lastInsertId());
        kpSyncQuotePayloadRows($db, 'pkp', $newId, $payloadData);
        kpJson(['ok' => true, 'id' => $newId, 'public_url' => '/quote.php?token=' . $token]);
        break;

    case 'delete_quote':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'kp', 'delete');
        $id = intval($input['id'] ?? 0);
        $st = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $quote = $st->fetch();
        if (!$quote) kpJson(['error' => 'Не найдено'], 404);
        kpAssertQuoteAccess($user, $quote);
        kpDeleteQuotePayloadRows($db, 'pkp', $id);
        $db->prepare("DELETE FROM pkp_quotes WHERE id = ?")->execute([$id]);
        kpJson(['ok' => true]);
        break;

    case 'set_quote_kanban_orders':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'kp', 'edit');
        $orderedIds = $input['ordered_ids'] ?? [];
        if (!is_array($orderedIds) || !$orderedIds) kpJson(['ok' => true]);
        $workflowStatus = trim((string)($input['workflow_status'] ?? ''));
        $selectSt = $db->prepare("SELECT id, payload_json, workflow_status FROM pkp_quotes WHERE id = ? LIMIT 1");
        $updateSt = $db->prepare("UPDATE pkp_quotes SET payload_json = ? WHERE id = ?");
        foreach ($orderedIds as $idx => $rawId) {
            $id = intval($rawId);
            if (!$id) continue;
            $selectSt->execute([$id]);
            $quote = $selectSt->fetch();
            if (!$quote) continue;
            kpAssertQuoteAccess($user, $quote);
            if ($workflowStatus !== '' && trim((string)($quote['workflow_status'] ?? '')) !== $workflowStatus) continue;
            $payload = kpDecodePayloadRow($quote);
            $payload['kanban_order'] = intval($idx);
            $updateSt->execute([kpEncodePayloadValue($payload), $id]);
        }
        kpJson(['ok' => true]);
        break;

    case 'set_quote_status':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'kp', 'edit');
        $id = intval($input['id'] ?? 0);
        $scopeSt = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
        $scopeSt->execute([$id]);
        $scopeQuote = $scopeSt->fetch();
        if (!$scopeQuote) kpJson(['error' => 'Не найдено'], 404);
        kpAssertQuoteAccess($user, $scopeQuote);
        $status = kpNormalizeStatus((string)($input['status'] ?? 'created'));
        $selectedVariantProvided = array_key_exists('selected_variant_label', $input);
        $selectedVariant = trim((string)($input['selected_variant_label'] ?? ''));
        $workflowStatusProvided = array_key_exists('workflow_status', $input);
        $workflowStatus = trim((string)($input['workflow_status'] ?? ''));
        $st = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $quote = $st->fetch();
        if (!$quote) kpJson(['error' => 'Не найдено'], 404);
        $previousWorkflowStatus = kpNormalizeWorkflowStatus($quote['workflow_status'] ?? '');
        $nextWorkflowStatus = $workflowStatusProvided && $workflowStatus !== ''
            ? kpNormalizeWorkflowStatus($workflowStatus)
            : $previousWorkflowStatus;
        $payload = kpDecodePayloadRow($quote);
        $payloadChanged = false;
        if ($nextWorkflowStatus !== $previousWorkflowStatus) {
            $payload['last_workflow_change'] = kpBuildWorkflowChangedMeta($user, $nextWorkflowStatus);
            $payloadChanged = true;
        }
        $sets = "status = ?";
        $params = [$status];
        if ($selectedVariantProvided) {
            $sets .= ", selected_variant_label = ?";
            $params[] = $selectedVariant ?: null;
        }
        if ($workflowStatusProvided && $workflowStatus !== '') {
            $sets .= ", workflow_status = ?";
            $params[] = $nextWorkflowStatus;
        }
        if ($payloadChanged) {
            $sets .= ", payload_json = ?";
            $params[] = kpEncodePayloadValue($payload);
        }
        if ($status === 'sent') {
            $sets .= ", sent_at = NOW()";
        } elseif ($status === 'rejected') {
            $sets .= ", rejected_at = NOW()";
        } elseif ($status === 'completed') {
            $sets .= ", completed_at = NOW()";
        }
        $params[] = $id;
        $db->prepare("UPDATE pkp_quotes SET $sets WHERE id = ?")->execute($params);
        kpJson(['ok' => true]);
        break;

    case 'set_quote_workflow':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'kp', 'edit');
        $id = intval($input['id'] ?? 0);
        $workflowStatus = kpNormalizeWorkflowStatus($input['workflow_status'] ?? '');
        $st = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $quote = $st->fetch();
        if (!$quote) kpJson(['error' => 'Не найдено'], 404);
        kpAssertQuoteAccess($user, $quote);
        $previousWorkflowStatus = kpNormalizeWorkflowStatus($quote['workflow_status'] ?? '');
        $payload = kpDecodePayloadRow($quote);
        $payload['last_workflow_change'] = kpBuildWorkflowChangedMeta($user, $workflowStatus);
        $db->prepare("UPDATE pkp_quotes SET workflow_status = ?, payload_json = ? WHERE id = ?")
           ->execute([$workflowStatus, kpEncodePayloadValue($payload), $id]);
        kpJson(['ok' => true]);
        break;

    case 'transfer_to_kp':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'kp', 'edit');
        $id = intval($input['id'] ?? 0);
        if (!$id) kpJson(['error' => 'id required'], 400);
        $st = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $quote = $st->fetch();
        if (!$quote) kpJson(['error' => 'Не найдено'], 404);
        kpAssertQuoteAccess($user, $quote);
        $payload = kpDecodePayloadRow($quote);
        try {
            $db->beginTransaction();
            $kpQuoteId = kpTransferPkpToKpQuote($db, $quote, $payload, $uid);
            $db->prepare("UPDATE pkp_quotes SET payload_json = ? WHERE id = ?")
               ->execute([kpEncodePayloadValue($payload), $id]);
            $db->commit();
            kpJson(['ok' => true, 'kp_quote_id' => $kpQuoteId]);
        } catch (Throwable $e) {
            if ($db->inTransaction()) $db->rollBack();
            kpJson(['error' => $e->getMessage()], 500);
        }
        break;

    case 'set_quote_archive':
        if ($method !== 'POST') kpJson(['error' => 'POST required'], 405);
        accessAssert($user, 'kp', 'edit');
        $id = intval($input['id'] ?? 0);
        if (!$id) kpJson(['error' => 'id required'], 400);
        $archived = !empty($input['archived']) ? 1 : 0;
        $st = $db->prepare("SELECT " . kpQuoteSelectFields() . " FROM pkp_quotes WHERE id = ? LIMIT 1");
        $st->execute([$id]);
        $quote = $st->fetch();
        if (!$quote) kpJson(['error' => 'Не найдено'], 404);
        kpAssertQuoteAccess($user, $quote);
        $db->prepare("UPDATE pkp_quotes SET is_archived = ?, archived_at = ? WHERE id = ?")
           ->execute([$archived, $archived ? date('Y-m-d H:i:s') : null, $id]);
        kpJson(['ok' => true]);
        break;

    default:
        kpJson(['error' => 'Unknown action'], 404);
}
