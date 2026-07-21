<?php
require_once __DIR__ . '/includes/auth.php';
releaseSessionLock();

$db = getDB();
$token = trim((string)($_GET['token'] ?? $_POST['token'] ?? ''));

function quoteLoadByToken(PDO $db, string $token): ?array {
    foreach (['kp_quotes', 'pkp_quotes'] as $table) {
        $st = $db->prepare("SELECT * FROM {$table} WHERE public_token = ? LIMIT 1");
        $st->execute([$token]);
        $row = $st->fetch();
        if ($row) {
            $row['_quote_table'] = $table;
            return $row;
        }
    }
    return null;
}

function quoteStatusLabel(string $status): string {
    $map = [
        'created' => 'Создано',
        'sent' => 'Отправлено',
        'viewed' => 'Просмотрено',
        'chosen' => 'Выбран вариант',
        'rejected' => 'Отказ',
        'completed' => 'Выполнено',
    ];
    return $map[$status] ?? $status;
}

function h($v): string {
    return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
}

function money($v): string {
    if ($v === null || $v === '') return '—';
    return number_format(round((float)$v), 0, '.', ' ') . ' ₽';
}

function percent($v): string {
    if ($v === null || $v === '') return '0%';
    return number_format(round((float)$v), 0, '.', '') . '%';
}

function quoteCategoryLabel(string $code): string {
    $map = [
        'equipment' => 'Оборудование',
        'materials' => 'Материалы',
        'work' => 'Работы',
        'construction_works' => 'Строительные работы',
        'incidental_expenses' => 'Сопутствующие расходы',
        'maintenance' => 'Обслуживание',
    ];
    return $map[$code] ?? $code;
}

function quoteCompanyFieldLabel(string $key, array $company): string {
    $type = (string)($company['company_type'] ?? 'ooo');
    $map = [
        'company_type' => 'Тип компании',
        'company_name' => 'Компания',
        'legal_name' => ($type === 'ip' ? 'ФИО ИП' : 'Юридическое название'),
        'inn' => 'ИНН',
        'ogrn' => ($type === 'ip' ? 'ОГРНИП' : 'ОГРН'),
        'kpp' => 'КПП',
        'address' => 'Адрес',
        'phone' => 'Телефон',
        'email' => 'Email',
        'website' => 'Сайт',
        'director_name' => 'Директор',
        'signatory_name' => 'Подписант',
        'signatory_title' => 'Должность подписанта',
        'bank_name' => 'Банк',
        'bank_bik' => 'БИК',
        'bank_account' => 'Расчётный счёт',
        'corr_account' => 'Корр. счёт',
    ];
    return $map[$key] ?? $key;
}

function quoteCompanyVisibleRows(array $company): array {
    $order = [
        'company_type',
        'company_name',
        'legal_name',
        'inn',
        'ogrn',
        'kpp',
        'address',
        'phone',
        'email',
        'website',
        'director_name',
        'signatory_name',
        'signatory_title',
        'bank_name',
        'bank_bik',
        'bank_account',
        'corr_account',
    ];
    $rows = [];
    foreach ($order as $key) {
        if (!array_key_exists($key, $company)) continue;
        $value = trim((string)($company[$key] ?? ''));
        if ($value === '') continue;
        $rows[] = [
            'label' => quoteCompanyFieldLabel($key, $company),
            'value' => ($key === 'company_type' ? strtoupper($value) : $value),
            'multiline' => ($key === 'address'),
        ];
    }
    return $rows;
}

function quoteUpdateTable(array $quote): string {
    $table = (string)($quote['_quote_table'] ?? 'kp_quotes');
    return $table === 'pkp_quotes' ? 'pkp_quotes' : 'kp_quotes';
}

function quoteHasLastOpenedAt(array $quote): bool {
    return quoteUpdateTable($quote) === 'kp_quotes';
}

function quoteVatRateValue(?string $mode): float {
    if ($mode === '5') return 5.0;
    if ($mode === '22') return 22.0;
    return 0.0;
}

function quoteItemPrice(array $item): float {
    if (isset($item['final_price']) && $item['final_price'] !== '' && $item['final_price'] !== null) {
        return (float)$item['final_price'];
    }
    $base = isset($item['base_price']) ? (float)$item['base_price'] : (isset($item['retail_price']) ? (float)$item['retail_price'] : 0.0);
    $markup = isset($item['markup_value']) ? (float)$item['markup_value'] : 0.0;
    $discount = isset($item['discount_value']) ? (float)$item['discount_value'] : 0.0;
    return max($base + $markup - $discount, 0.0);
}

function quoteItemSum(array $item): float {
    if (isset($item['line_sum']) && $item['line_sum'] !== '' && $item['line_sum'] !== null) {
        return (float)$item['line_sum'];
    }
    $qty = isset($item['quantity']) ? (float)$item['quantity'] : 0.0;
    return quoteItemPrice($item) * $qty;
}

function quoteVariantItems(array $variant): array {
    if (!empty($variant['items']) && is_array($variant['items'])) return $variant['items'];
    $items = [];
    $cats = is_array($variant['cats'] ?? null) ? $variant['cats'] : (is_array($variant['snapshot'] ?? null) ? $variant['snapshot'] : []);
    foreach ($cats as $cat) {
        $sections = is_array($cat['sections'] ?? null) ? $cat['sections'] : [];
        foreach ($sections as $section) {
            $rows = is_array($section['items'] ?? null) ? $section['items'] : [];
            foreach ($rows as $row) {
                if (is_array($row)) $items[] = $row;
            }
        }
    }
    return $items;
}

function quoteVariantTotals(array $variant, ?string $vatMode): array {
    $total = 0.0;
    $vatBase = 0.0;
    $rate = quoteVatRateValue($vatMode);
    foreach (quoteVariantItems($variant) as $item) {
        $line = quoteItemSum($item);
        $total += $line;
        if (($item['category_code'] ?? '') !== 'equipment') {
            $vatBase += $line;
        }
    }
    $vat = $vatBase * ($rate / 100);
    return ['total' => $total, 'vat' => $vat, 'total_with_vat' => $total + $vat, 'rate' => $rate];
}

function quoteSelectionMode(array $payload): string {
    $mode = trim((string)($payload['selection_mode'] ?? $payload['client_selection_mode'] ?? ''));
    return $mode === 'type' ? 'type' : 'variant';
}

function quoteSelectedTypeId(array $payload): string {
    return trim((string)($payload['selected_type_id'] ?? ''));
}

function quoteProposalTypeTotals(array $type, ?string $defaultVatMode): array {
    $totals = ['variants' => 0, 'items' => 0, 'total' => 0.0, 'vat' => 0.0, 'total_with_vat' => 0.0];
    foreach (($type['variants'] ?? []) as $variant) {
        if (!is_array($variant)) continue;
        $totals['variants']++;
        $totals['items'] += count(quoteVariantItems($variant));
        $variantTotals = quoteVariantTotals($variant, (string)($variant['vat_mode'] ?? $defaultVatMode ?? 'none'));
        $totals['total'] += $variantTotals['total'];
        $totals['vat'] += $variantTotals['vat'];
        $totals['total_with_vat'] += $variantTotals['total_with_vat'];
    }
    return $totals;
}

function quoteNormalizeProposalTypes(array $payload): array {
    $legacyVatMode = (string)($payload['vat_mode'] ?? 'none');
    $proposalTypes = $payload['proposal_types'] ?? null;
    if (!is_array($proposalTypes) || !$proposalTypes) {
        $proposalTypes = [[
            'id' => 'ptype-default',
            'label' => 'Основное предложение',
            'selected_variant_id' => '',
            'variants' => is_array($payload['variants'] ?? null) ? $payload['variants'] : [],
        ]];
    }
    $result = [];
    foreach (array_values($proposalTypes) as $typeIndex => $type) {
        $variantsRaw = is_array($type['variants'] ?? null) && $type['variants'] ? $type['variants'] : [];
        $variants = [];
        foreach (array_values($variantsRaw) as $variantIndex => $variant) {
            $variants[] = array_merge($variant, [
                'id' => trim((string)($variant['id'] ?? '')) ?: ('var-' . $typeIndex . '-' . $variantIndex),
                'label' => (string)($variant['label'] ?? ('Вариант ' . ($variantIndex + 1))),
                'vat_mode' => (string)($variant['vat_mode'] ?? $legacyVatMode),
                'items' => is_array($variant['items'] ?? null) ? $variant['items'] : [],
            ]);
        }
        if (!$variants) {
            $variants[] = [
                'id' => 'var-' . $typeIndex . '-0',
                'label' => 'Вариант 1',
                'vat_mode' => $legacyVatMode,
                'items' => [],
            ];
        }
        $selectedVariantId = trim((string)($type['selected_variant_id'] ?? ''));
        if ($selectedVariantId !== '') {
            $known = false;
            foreach ($variants as $variant) {
                if ((string)($variant['id'] ?? '') === $selectedVariantId) {
                    $known = true;
                    break;
                }
            }
            if (!$known) $selectedVariantId = '';
        }
        $result[] = [
            'id' => trim((string)($type['id'] ?? '')) ?: ('ptype-' . $typeIndex),
            'label' => trim((string)($type['label'] ?? '')) ?: ($typeIndex === 0 ? 'Основное предложение' : ('Тип предложения ' . ($typeIndex + 1))),
            'selected_variant_id' => $selectedVariantId,
            'variants' => $variants,
        ];
    }
    return $result;
}

function quoteProposalTypeChosenVariant(array $type): ?array {
    $chosenId = trim((string)($type['selected_variant_id'] ?? ''));
    if ($chosenId === '') return null;
    foreach (($type['variants'] ?? []) as $variant) {
        if ((string)($variant['id'] ?? '') === $chosenId) return $variant;
    }
    return null;
}

function quoteRenderProposalType(array $type, ?string $defaultVatMode, string $selectionMode = 'variant', string $selectedTypeId = ''): string {
    $chosen = quoteProposalTypeChosenVariant($type);
    $typeId = (string)($type['id'] ?? '');
    $typeChosen = $selectionMode === 'type' && $selectedTypeId !== '' && $selectedTypeId === $typeId;
    $variantsHtml = '';
    foreach (($type['variants'] ?? []) as $variant) {
        $isChosen = $typeChosen || ($chosen && (string)($chosen['id'] ?? '') === (string)($variant['id'] ?? ''));
        $variantsHtml .= quoteRenderVariant($variant, $isChosen, $defaultVatMode, $typeId, $selectionMode, $typeChosen);
    }
    $totals = quoteProposalTypeTotals($type, $defaultVatMode);
    $typeButton = '';
    if ($selectionMode === 'type') {
        $typeButton = $typeChosen
            ? '<button class="pick picked" type="button" disabled>Выбранный тип</button>'
            : '<button class="pick" type="button" data-type-id="' . h($typeId) . '" onclick="pickType(this.dataset.typeId)">Выбрать тип</button>';
    }
    $typeSummaryHtml = '<div class="group type-summary"><div class="group-head"><h4>Сводка типа</h4><span>' . money($totals['total']) . '</span></div>'
        . '<table><tbody>'
        . '<tr><td>Вариантов</td><td>' . h((string)$totals['variants']) . '</td></tr>'
        . '<tr><td>Позиций</td><td>' . h((string)$totals['items']) . '</td></tr>'
        . '<tr><td>Итого</td><td>' . money($totals['total']) . '</td></tr>'
        . '<tr><td>Сумма НДС</td><td>' . money($totals['vat']) . '</td></tr>'
        . '<tr><td>Сумма с НДС</td><td>' . money($totals['total_with_vat']) . '</td></tr>'
        . '</tbody></table></div>';
    return '<section class="card footer-card' . ($typeChosen ? ' variant chosen' : '') . '"><div class="variant-head"><div><h3>' . h($type['label'] ?? 'Тип предложения') . '</h3></div>' . $typeButton . '</div>'
        . '<div class="variants">' . $variantsHtml . '</div>'
        . $typeSummaryHtml
        . '</section>';
}

function quoteRenderVariant(array $variant, bool $isChosen, ?string $defaultVatMode, string $typeId = '', string $selectionMode = 'variant', bool $typeChosen = false): string {
    $groups = [];
    foreach (quoteVariantItems($variant) as $item) {
        $code = (string)($item['category_code'] ?? '');
        if ($code === '') {
            $code = (($item['item_type'] ?? '') === 'work') ? 'work' : 'equipment';
        }
        if (!isset($groups[$code])) $groups[$code] = [];
        $groups[$code][] = $item;
    }

    $categoryOrder = ['equipment', 'materials', 'work', 'incidental_expenses', 'maintenance', 'construction_works'];
    $tables = '';

    foreach ($categoryOrder as $code) {
        $items = $groups[$code] ?? [];
        if (!$items) continue;

        $sum = 0.0;
        $rows = '';
        foreach ($items as $item) {
            $line = quoteItemSum($item);
            $sum += $line;
            $rows .= '<tr>'
                . '<td>' . h($item['name'] ?? '') . '</td>'
                . '<td>' . h($item['marking_size'] ?? '—') . '</td>'
                . '<td>' . h($item['quantity'] ?? '—') . '</td>'
                . '<td>' . h($item['unit'] ?? '—') . '</td>'
                . '<td>' . h($item['note'] ?? '—') . '</td>'
                . '<td>' . percent($item['discount_value'] ?? 0) . '</td>'
                . '<td>' . money(quoteItemPrice($item)) . '</td>'
                . '<td>' . money($line) . '</td>'
                . '</tr>';
        }

        $tables .= '<div class="group">'
            . '<div class="group-head"><h4>' . h(quoteCategoryLabel($code)) . '</h4><span>' . money($sum) . '</span></div>'
            . '<table><thead><tr><th>Наименование</th><th>Маркировка / размер</th><th>Кол-во</th><th>Ед. изм.</th><th>Примечание</th><th>Скидка</th><th>Цена</th><th>Сумма</th></tr></thead><tbody>'
            . $rows
            . '</tbody><tfoot><tr><td colspan="7">Итого</td><td>' . money($sum) . '</td></tr></tfoot></table>'
            . '</div>';
    }

    $label = trim((string)($variant['label'] ?? '')) ?: 'Вариант';
    if ($selectionMode === 'type') {
        $buttonHtml = $typeChosen
            ? '<button class="pick picked" type="button" disabled>В составе выбранного типа</button>'
            : '';
    } else {
        $buttonHtml = $isChosen
            ? '<button class="pick picked" type="button" disabled>Выбранный вариант</button>'
            : '<button class="pick" type="button" data-type-id="' . h($typeId) . '" data-variant-id="' . h((string)($variant['id'] ?? '')) . '" onclick="pickVariant(this.dataset.typeId,this.dataset.variantId)">Выбрать вариант</button>';
    }

    $variantVatMode = (string)($variant['vat_mode'] ?? $defaultVatMode ?? 'none');
    $totals = quoteVariantTotals($variant, $variantVatMode);
    return '<section class="variant" data-label="' . h($label) . '">'
        . '<div class="variant-head"><div><h3>' . h($label) . '</h3>'
        . ''
        . '</div>' . $buttonHtml . '</div>'
        . $tables
        . '<div class="group"><div class="group-head"><h4>Сводка варианта</h4><span>' . ($totals['rate'] ? h(rtrim(rtrim(number_format($totals['rate'], 2, '.', ''), '0'), '.')) . '%' : 'Без НДС') . '</span></div>'
        . '<table><tbody>'
        . '<tr><td>Итого</td><td>' . money($totals['total']) . '</td></tr>'
        . '<tr><td>Сумма НДС</td><td>' . money($totals['vat']) . '</td></tr>'
        . '<tr><td>Сумма с НДС</td><td>' . money($totals['total_with_vat']) . '</td></tr>'
        . '</tbody></table></div>'
        . '</section>';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    if ($token === '') jsonResponse(['error' => 'token required'], 400);
    $quote = quoteLoadByToken($db, $token);
    if (!$quote) jsonResponse(['error' => 'not found'], 404);
    $payload = $quote['payload_json'] ? json_decode($quote['payload_json'], true) : [];
    $proposalTypes = quoteNormalizeProposalTypes(is_array($payload) ? $payload : []);
    $selectionMode = quoteSelectionMode(is_array($payload) ? $payload : []);
    $typeId = trim((string)($_POST['type_id'] ?? ''));
    $variantId = trim((string)($_POST['variant_id'] ?? ''));
    $variantLabel = trim((string)($_POST['variant_label'] ?? ''));
    $selectedLabel = null;
    $updated = false;
    if ($selectionMode === 'type' && $typeId !== '' && $variantId === '') {
        foreach ($proposalTypes as $type) {
            if ((string)($type['id'] ?? '') !== $typeId) continue;
            $payload['selection_mode'] = 'type';
            $payload['selected_type_id'] = $typeId;
            $selectedLabel = trim((string)($type['label'] ?? ''));
            $updated = true;
            break;
        }
    } elseif ($typeId !== '' && $variantId !== '') {
        foreach ($proposalTypes as &$type) {
            if ((string)($type['id'] ?? '') !== $typeId) continue;
            foreach (($type['variants'] ?? []) as $variant) {
                if ((string)($variant['id'] ?? '') !== $variantId) continue;
                $payload['selection_mode'] = 'variant';
                unset($payload['selected_type_id']);
                $type['selected_variant_id'] = $variantId;
                $selectedLabel = trim((string)($variant['label'] ?? ''));
                $updated = true;
                break 2;
            }
        }
        unset($type);
    } elseif ($variantLabel !== '') {
        foreach ($proposalTypes as &$type) {
            foreach (($type['variants'] ?? []) as $variant) {
                if (trim((string)($variant['label'] ?? '')) !== $variantLabel) continue;
                $payload['selection_mode'] = 'variant';
                unset($payload['selected_type_id']);
                $type['selected_variant_id'] = (string)($variant['id'] ?? '');
                $selectedLabel = $variantLabel;
                $updated = true;
                break 2;
            }
        }
        unset($type);
    }
    if (!$updated) jsonResponse(['error' => 'unknown variant'], 400);
    $payload['proposal_types'] = $proposalTypes;
    if (($payload['selection_mode'] ?? 'variant') === 'variant') {
        $selectedLabels = [];
        foreach ($proposalTypes as $type) {
            $picked = quoteProposalTypeChosenVariant($type);
            if (!$picked) continue;
            $label = trim((string)($picked['label'] ?? ''));
            if ($label !== '') $selectedLabels[] = $label;
        }
        if (count($selectedLabels) === 1) {
            $selectedLabel = $selectedLabels[0];
        } elseif (count($selectedLabels) > 1) {
            $selectedLabel = 'Выбрано типов: ' . count($selectedLabels);
        }
    }
    $sets = [
        "status = 'chosen'",
        "selected_variant_label = ?",
        "payload_json = ?",
        "chosen_at = NOW()",
    ];
    if (quoteHasLastOpenedAt($quote)) {
        $sets[] = "last_opened_at = NOW()";
    }
    $db->prepare("UPDATE " . quoteUpdateTable($quote) . "
                     SET " . implode(",\n                         ", $sets) . "
                   WHERE id = ?")
       ->execute([$selectedLabel, json_encode($payload, JSON_UNESCAPED_UNICODE), $quote['id']]);
    jsonResponse(['ok' => true]);
}

if ($token === '') {
    http_response_code(400);
    echo 'Quote token is required.';
    exit;
}

$quote = quoteLoadByToken($db, $token);
if (!$quote) {
    http_response_code(404);
    echo 'Quote not found.';
    exit;
}

$payload = $quote['payload_json'] ? json_decode($quote['payload_json'], true) : [];
$company = $quote['company_snapshot_json'] ? json_decode($quote['company_snapshot_json'], true) : [];
$client = $quote['client_snapshot_json'] ? json_decode($quote['client_snapshot_json'], true) : [];
$companyRows = quoteCompanyVisibleRows(is_array($company) ? $company : []);
$proposalTypes = quoteNormalizeProposalTypes(is_array($payload) ? $payload : []);
$selectionMode = quoteSelectionMode(is_array($payload) ? $payload : []);
$selectedTypeId = quoteSelectedTypeId(is_array($payload) ? $payload : []);
$chosenLabel = trim((string)($quote['selected_variant_label'] ?? ''));

if (!in_array($quote['status'], ['chosen', 'rejected', 'completed'], true)) {
    $sets = [
        "status = CASE WHEN status = 'created' THEN 'viewed' WHEN status = 'sent' THEN 'viewed' ELSE status END",
        "viewed_at = COALESCE(viewed_at, NOW())",
        "public_open_count = public_open_count + 1",
    ];
    if (quoteHasLastOpenedAt($quote)) {
        $sets[] = "last_opened_at = NOW()";
    }
    $db->prepare("UPDATE " . quoteUpdateTable($quote) . "
                     SET " . implode(",\n                         ", $sets) . "
                   WHERE id = ?")
       ->execute([$quote['id']]);
    $quote['status'] = in_array($quote['status'], ['created', 'sent'], true) ? 'viewed' : $quote['status'];
}
?>
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><?php echo h($quote['title']); ?></title>
  <style>
    :root{--bg:#f4efe7;--card:#fffdf9;--bd:#e5d7c6;--tx:#1f2937;--tx2:#6b7280;--ac:#0f766e;--ac2:#115e59;--mut:#f7f0e6}
    *{box-sizing:border-box}
    body{margin:0;font-family:Geologica,Arial,sans-serif;background:linear-gradient(180deg,#f7f1e8 0%,#efe7db 100%);color:var(--tx)}
    .wrap{max-width:1240px;margin:0 auto;padding:32px 18px 60px}
    .hero,.card,.variant,.group{background:var(--card);border:1px solid var(--bd);border-radius:24px}
    .hero{padding:28px}
    .muted{color:var(--tx2)}
    .status{display:inline-flex;align-items:center;padding:6px 12px;border-radius:999px;background:var(--mut);font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
    h1{margin:14px 0 8px;font-size:clamp(1.8rem,4vw,2.8rem);line-height:1.05}
    .hero-lead{font-size:1rem;color:var(--tx2);margin:0}
    .grid{display:grid;grid-template-columns:1.1fr .9fr;gap:18px;margin-top:20px}
    .card{padding:20px}
    .card h3{margin:0 0 10px;font-size:1rem}
    .meta{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px 16px}
    .meta-line strong{display:block;font-size:.78rem;text-transform:uppercase;letter-spacing:.06em;color:var(--tx2);margin-bottom:2px}
    .meta-line.wide{grid-column:1 / -1}
    .proposal-text{margin-top:14px;white-space:pre-wrap;line-height:1.55}
    .variants{display:grid;gap:18px;margin-top:22px}
    .variant{padding:20px}
    .variant.chosen{border-width:2px;box-shadow:0 10px 28px rgba(15,23,42,.08)}
    .variant.chosen.tone-budget{border-color:#22c55e;background:linear-gradient(180deg,rgba(34,197,94,.12),rgba(255,253,249,1) 30%)}
    .variant.chosen.tone-optimal{border-color:#f59e0b;background:linear-gradient(180deg,rgba(245,158,11,.14),rgba(255,253,249,1) 30%)}
    .variant.chosen.tone-premium{border-color:#3b82f6;background:linear-gradient(180deg,rgba(59,130,246,.14),rgba(255,253,249,1) 30%)}
    .variant-head{display:flex;justify-content:space-between;gap:16px;align-items:flex-start;margin-bottom:12px}
    .variant-head h3{margin:0;font-size:1.2rem}
    .variant-note{margin:8px 0 0;color:var(--tx2);line-height:1.5}
    .pick{border:none;background:var(--ac);color:#fff;border-radius:14px;padding:11px 16px;cursor:pointer;font-weight:700;white-space:nowrap}
    .pick:hover{background:var(--ac2)}
    .pick.picked{background:#cbd5e1;color:#334155;cursor:default}
    .group{padding:14px 16px;margin-top:14px}
    .type-summary{border-color:#bfdbfe;background:#eff6ff}
    .group-head{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-bottom:10px}
    .group-head h4{margin:0;font-size:1rem}
    .toast-stack{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);display:flex;flex-direction:column;gap:10px;z-index:9999;pointer-events:none}
    .toast{min-width:280px;max-width:min(92vw,420px);padding:14px 16px;border-radius:16px;border:1px solid #a7f3d0;background:#ecfdf5;color:#166534;box-shadow:0 12px 30px rgba(0,0,0,.16);font-size:14px;line-height:1.4;animation:toastIn .22s ease, toastOut .22s ease 3.2s forwards}
    .toast strong{display:block;font-size:15px;margin-bottom:4px}
    table{width:100%;border-collapse:collapse;font-size:14px}
    th,td{padding:10px 8px;border-bottom:1px solid #efe2d2;text-align:left;vertical-align:top}
    th{font-size:12px;text-transform:uppercase;letter-spacing:.05em;color:var(--tx2)}
    tfoot td{font-weight:700;border-bottom:none}
    .footer-card{margin-top:22px;padding:20px}
    @media (max-width: 900px){
      .grid{grid-template-columns:1fr}
      .meta{grid-template-columns:1fr}
      .variant-head{flex-direction:column;align-items:flex-start}
      .pick{width:100%;justify-content:center}
      .group{overflow:auto}
      table{min-width:760px}
    }
    @page{size:A4;margin:14mm}
    @media print{
      *{-webkit-print-color-adjust:exact;print-color-adjust:exact}
      html,body{width:auto;min-width:0;background:#fff!important;color:#111!important}
      body{font-family:Arial,"Helvetica Neue",sans-serif!important}
      .wrap{max-width:none!important;width:100%!important;margin:0!important;padding:0!important}
      .hero,.card,.variant,.group{background:#fff!important;color:#111!important;box-shadow:none!important;border-color:#b8b8b8!important;border-radius:0!important}
      .hero,.card{break-inside:avoid;page-break-inside:avoid}
      .variant,.group,table{break-inside:auto;page-break-inside:auto}
      .hero{padding:0 0 12px!important;border:none!important;border-bottom:2px solid #111!important}
      .status,.pick,.toast-stack{display:none!important}
      h1{margin:0 0 8px!important;font-size:20pt!important;line-height:1.18!important;color:#111!important}
      .hero-lead{margin:0!important;color:#111!important;font-size:11pt!important}
      .grid{display:grid!important;grid-template-columns:1fr 1fr!important;gap:10mm!important;margin-top:10mm!important}
      .card{padding:8px!important}
      .meta{display:grid!important;grid-template-columns:1fr 1fr!important;gap:5px 12px!important}
      .meta-line{font-size:9.5pt!important;line-height:1.35!important;color:#111!important}
      .meta-line strong{font-size:7.5pt!important;color:#444!important;letter-spacing:.03em!important}
      .variants{display:block!important;margin-top:10mm!important}
      .variant{padding:0!important;border:none!important;margin:0 0 10mm!important}
      .variant-head{display:block!important;margin:0 0 6px!important;padding-bottom:5px!important;border-bottom:1px solid #111!important;break-after:avoid;page-break-after:avoid}
      .variant.chosen,.variant.chosen.tone-budget,.variant.chosen.tone-optimal,.variant.chosen.tone-premium{border-color:#111!important;background:#fff!important}
      .group{padding:0!important;border:none!important;margin:6mm 0 0!important;overflow:visible!important}
      .type-summary{background:#fff!important;border-top:1px solid #111!important;border-bottom:1px solid #111!important;padding:4px 0!important}
      .group-head{break-after:avoid;page-break-after:avoid;color:#111!important;border-bottom:1px solid #666!important;padding-bottom:3px!important}
      table{display:table!important;width:100%!important;min-width:0!important;border-collapse:collapse!important;table-layout:fixed!important;font-size:8.5pt!important;line-height:1.25!important;white-space:normal!important;color:#111!important}
      thead{display:table-header-group!important}
      tfoot{display:table-row-group!important}
      tr{break-inside:avoid;page-break-inside:avoid}
      th,td{border:1px solid #9f9f9f!important;padding:3.5px 4px!important;color:#111!important;background:#fff!important;overflow-wrap:anywhere!important;word-break:normal!important;white-space:normal!important}
      th{font-size:7.4pt!important;font-weight:700!important;text-transform:none!important;letter-spacing:0!important}
    }
    @keyframes toastIn{
      from{opacity:0;transform:translateY(18px)}
      to{opacity:1;transform:translateY(0)}
    }
    @keyframes toastOut{
      from{opacity:1;transform:translateY(0)}
      to{opacity:0;transform:translateY(18px)}
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div class="status"><?php echo h(quoteStatusLabel((string)$quote['status'])); ?></div>
      <h1><?php echo h((($payload['quote_meta']['proposal_title'] ?? '') !== '' ? $payload['quote_meta']['proposal_title'] : (($quote['_quote_table'] ?? 'kp_quotes') === 'pkp_quotes' ? 'Предварительное коммерческое предложение' : 'Коммерческое предложение'))); ?></h1>
      <p class="hero-lead"><?php echo h($client['recipient_name'] ?? ''); ?></p>
      <div class="grid">
        <div class="card">
          <h3>О компании</h3>
          <div class="meta">
            <?php if ($companyRows): ?>
              <?php foreach ($companyRows as $row): ?>
                <div class="meta-line">
                  <strong><?php echo h($row['label']); ?></strong>
                  <?php echo $row['multiline'] ? nl2br(h($row['value'])) : h($row['value']); ?>
                </div>
              <?php endforeach; ?>
            <?php else: ?>
              <div class="meta-line">&mdash;</div>
            <?php endif; ?>
          </div>
        </div>
        <div class="card">
          <h3>Клиент</h3>
          <div class="meta">
            <div class="meta-line"><strong>Компания</strong><?php echo h($client['company_name'] ?? '—'); ?></div>
            <div class="meta-line"><strong>Получатель</strong><?php echo h($client['recipient_name'] ?? '—'); ?></div>
          </div>
        </div>
      </div>
    </div>

    <div class="variants">
      <?php foreach ($proposalTypes as $proposalType): ?>
        <?php echo quoteRenderProposalType($proposalType, $payload['vat_mode'] ?? 'none', $selectionMode, $selectedTypeId); ?>
      <?php endforeach; ?>
    </div>

    <?php if (!empty($payload['additional_info'])): ?>
      <div class="card footer-card">
        <h3>Дополнительная информация</h3>
        <div class="proposal-text"><?php echo nl2br(h($payload['additional_info'])); ?></div>
      </div>
    <?php endif; ?>
  </div>
  <div id="quote-toast-stack" class="toast-stack"></div>
  <script>
    function showQuoteToast(title, text){
      const stack=document.getElementById('quote-toast-stack');
      if(!stack) return;
      const el=document.createElement('div');
      el.className='toast';
      el.innerHTML='<strong>'+title+'</strong><div>'+text+'</div>';
      stack.appendChild(el);
      setTimeout(function(){
        if(el.parentNode) el.parentNode.removeChild(el);
      }, 3500);
    }

    pickVariant = async function(typeId, variantId){
      const fd=new FormData();
      fd.append('token', <?php echo json_encode($token, JSON_UNESCAPED_UNICODE); ?>);
      fd.append('type_id', typeId);
      fd.append('variant_id', variantId);
      const res=await fetch('quote.php', {method:'POST', body:fd});
      const data=await res.json();
      if(!res.ok){alert(data.error||'Не удалось выбрать вариант');return;}
      sessionStorage.setItem('quote_pick_success', '1');
      location.reload();
    };

    pickType = async function(typeId){
      const fd=new FormData();
      fd.append('token', <?php echo json_encode($token, JSON_UNESCAPED_UNICODE); ?>);
      fd.append('type_id', typeId);
      const res=await fetch('quote.php', {method:'POST', body:fd});
      const data=await res.json();
      if(!res.ok){alert(data.error||'Не удалось выбрать тип');return;}
      sessionStorage.setItem('quote_pick_type_success', '1');
      location.reload();
    };

    if(sessionStorage.getItem('quote_pick_success')==='1'){
      sessionStorage.removeItem('quote_pick_success');
      showQuoteToast('Вариант успешно выбран', 'Ожидайте связи менеджера.');
    }
    if(sessionStorage.getItem('quote_pick_type_success')==='1'){
      sessionStorage.removeItem('quote_pick_type_success');
      showQuoteToast('Тип успешно выбран', 'Ожидайте связи менеджера.');
    }
  </script>
  <script>
    document.querySelectorAll('.variant').forEach(function(el){
      const picked=el.querySelector('.pick.picked');
      if(!picked) return;
      const label=(el.getAttribute('data-label')||'').trim().toLowerCase();
      el.classList.add('chosen');
      if(label.indexOf('бюдж')===0) el.classList.add('tone-budget');
      else if(label.indexOf('оптим')===0) el.classList.add('tone-optimal');
      else if(label.indexOf('прем')===0 || label.indexOf('прим')===0) el.classList.add('tone-premium');
    });
  </script>
</body>
</html>
