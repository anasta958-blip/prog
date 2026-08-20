<?php

declare(strict_types=1);

if ($argc < 2 || !is_file($argv[1])) {
    fwrite(STDERR, "Usage: php audit_legacy_dump.php <dump.sql>\n");
    exit(1);
}

function decodeSqlToken(string $token): mixed
{
    $token = trim($token);
    if (strcasecmp($token, 'NULL') === 0) {
        return null;
    }
    if (strlen($token) >= 2 && $token[0] === "'" && $token[strlen($token) - 1] === "'") {
        return strtr(substr($token, 1, -1), [
            '\\0' => "\0",
            '\\n' => "\n",
            '\\r' => "\r",
            '\\t' => "\t",
            "\\'" => "'",
            '\\"' => '"',
            '\\\\' => '\\',
        ]);
    }
    return is_numeric($token) ? $token + 0 : $token;
}

function splitSqlTuple(string $tuple): array
{
    $values = [];
    $buffer = '';
    $inString = false;
    $escaped = false;
    $depth = 0;
    $length = strlen($tuple);

    for ($index = 0; $index < $length; $index++) {
        $char = $tuple[$index];
        if ($inString) {
            $buffer .= $char;
            if ($escaped) {
                $escaped = false;
            } elseif ($char === '\\') {
                $escaped = true;
            } elseif ($char === "'") {
                $inString = false;
            }
            continue;
        }
        if ($char === "'") {
            $inString = true;
            $buffer .= $char;
        } elseif ($char === '(') {
            $depth++;
            $buffer .= $char;
        } elseif ($char === ')') {
            $depth--;
            $buffer .= $char;
        } elseif ($char === ',' && $depth === 0) {
            $values[] = decodeSqlToken($buffer);
            $buffer = '';
        } else {
            $buffer .= $char;
        }
    }
    $values[] = decodeSqlToken($buffer);
    return $values;
}

function parseInsertStatement(string $statement): ?array
{
    if (!preg_match('/^INSERT INTO `([^`]+)`\s*\((.*?)\) VALUES\s*(.*);\s*$/s', $statement, $match)) {
        return null;
    }
    preg_match_all('/`([^`]+)`/', $match[2], $columnMatches);
    $columns = $columnMatches[1];
    $body = $match[3];
    $rows = [];
    $buffer = '';
    $depth = 0;
    $inString = false;
    $escaped = false;
    $length = strlen($body);

    for ($index = 0; $index < $length; $index++) {
        $char = $body[$index];
        if ($inString) {
            if ($depth > 0) {
                $buffer .= $char;
            }
            if ($escaped) {
                $escaped = false;
            } elseif ($char === '\\') {
                $escaped = true;
            } elseif ($char === "'") {
                $inString = false;
            }
            continue;
        }
        if ($char === "'") {
            $inString = true;
            if ($depth > 0) {
                $buffer .= $char;
            }
        } elseif ($char === '(') {
            if ($depth > 0) {
                $buffer .= $char;
            }
            $depth++;
        } elseif ($char === ')') {
            $depth--;
            if ($depth > 0) {
                $buffer .= $char;
            } elseif ($depth === 0) {
                $values = splitSqlTuple($buffer);
                $row = [];
                foreach ($columns as $columnIndex => $column) {
                    $row[$column] = $values[$columnIndex] ?? null;
                }
                $rows[] = $row;
                $buffer = '';
            }
        } elseif ($depth > 0) {
            $buffer .= $char;
        }
    }

    return ['table' => $match[1], 'rows' => $rows];
}

function repairMojibake(string $value): string
{
    if ($value === '') {
        return $value;
    }
    $bytes = @mb_convert_encoding($value, 'Windows-1251', 'UTF-8');
    return $bytes !== false && mb_check_encoding($bytes, 'UTF-8') ? $bytes : $value;
}

function countBy(array $rows, callable $selector): array
{
    $result = [];
    foreach ($rows as $row) {
        $key = (string)$selector($row);
        $result[$key] = ($result[$key] ?? 0) + 1;
    }
    ksort($result);
    return $result;
}

$selectedTables = [
    'categories', 'sections', 'users', 'product_names', 'catalog_services',
    'kp_quotes', 'pkp_quotes', 'products', 'product_service_links', 'orders',
];
$selectedData = array_fill_keys($selectedTables, []);
$rowCounts = [];
$handle = fopen($argv[1], 'rb');
$buffer = '';

while (($line = fgets($handle)) !== false) {
    if ($buffer === '' && str_starts_with($line, 'INSERT INTO `')) {
        $buffer = $line;
    } elseif ($buffer !== '') {
        $buffer .= $line;
    }
    if ($buffer === '' || !preg_match('/;\s*$/', $line)) {
        continue;
    }
    $parsed = parseInsertStatement($buffer);
    $buffer = '';
    if ($parsed === null) {
        continue;
    }
    $table = $parsed['table'];
    $rowCounts[$table] = ($rowCounts[$table] ?? 0) + count($parsed['rows']);
    if (array_key_exists($table, $selectedData)) {
        array_push($selectedData[$table], ...$parsed['rows']);
    }
}
fclose($handle);
ksort($rowCounts);

$report = ['row_counts' => $rowCounts];
$report['categories'] = array_map(
    static fn(array $row): array => [
        'id' => $row['id'],
        'code' => $row['code'],
        'name' => repairMojibake((string)$row['name']),
    ],
    $selectedData['categories']
);
$report['sections'] = array_map(
    static fn(array $row): array => [
        'id' => $row['id'],
        'category_id' => $row['category_id'],
        'code' => $row['code'],
        'name' => repairMojibake((string)$row['name']),
    ],
    $selectedData['sections']
);
$report['roles'] = countBy($selectedData['users'], static fn(array $row): string => (string)$row['role']);
$report['password_hash_algorithms'] = countBy(
    $selectedData['users'],
    static fn(array $row): string => (string)(password_get_info((string)$row['password'])['algoName'] ?? 'unknown')
);
$report['product_names'] = [
    'total' => count($selectedData['product_names']),
    'retail_zero' => count(array_filter($selectedData['product_names'], static fn(array $row): bool => $row['retail_price'] !== null && (float)$row['retail_price'] <= 0)),
    'retail_missing' => count(array_filter($selectedData['product_names'], static fn(array $row): bool => $row['retail_price'] === null || $row['retail_price'] === '')),
    'purchase_zero_or_missing' => count(array_filter($selectedData['product_names'], static fn(array $row): bool => $row['purchase_price'] === null || (float)$row['purchase_price'] <= 0)),
    'status' => countBy($selectedData['product_names'], static fn(array $row): string => repairMojibake((string)$row['status'])),
];
$report['services'] = [
    'total' => count($selectedData['catalog_services']),
    'retail_zero_or_missing' => count(array_filter($selectedData['catalog_services'], static fn(array $row): bool => $row['retail_price'] === null || (float)$row['retail_price'] <= 0)),
    'scope' => countBy($selectedData['catalog_services'], static fn(array $row): string => (string)($row['category_scope_code'] ?? '')),
    'sections' => countBy($selectedData['catalog_services'], static fn(array $row): string => (string)($row['work_section_code'] ?? '')),
];

foreach (['kp_quotes', 'pkp_quotes'] as $table) {
    $summary = [
        'total' => count($selectedData[$table]),
        'client_missing' => 0,
        'invalid_json' => 0,
        'legacy_without_proposal_types' => 0,
        'executor_missing' => 0,
        'client_missing_ids' => [],
        'legacy_quote_ids' => [],
        'executor_missing_ids' => [],
        'payload_top_keys' => [],
    ];
    foreach ($selectedData[$table] as $row) {
        if (empty($row['client_id'])) {
            $summary['client_missing']++;
            $summary['client_missing_ids'][] = (int)$row['id'];
        }
        $payload = json_decode((string)($row['payload_json'] ?? ''), true);
        if (!is_array($payload)) {
            $summary['invalid_json']++;
            continue;
        }
        if (!isset($payload['proposal_types']) || !is_array($payload['proposal_types'])) {
            $summary['legacy_without_proposal_types']++;
            $summary['legacy_quote_ids'][] = (int)$row['id'];
        }
        $keys = array_keys($payload);
        sort($keys);
        $signature = implode(',', $keys);
        $summary['payload_top_keys'][$signature] = ($summary['payload_top_keys'][$signature] ?? 0) + 1;
        $companySnapshot = json_decode((string)($row['company_snapshot_json'] ?? ''), true);
        $hasExecutor = is_array($companySnapshot) && count(array_filter(
            $companySnapshot,
            static fn(mixed $value): bool => !is_array($value) && !is_object($value) && trim((string)$value) !== ''
        )) > 0;
        if (!$hasExecutor) {
            $summary['executor_missing']++;
            $summary['executor_missing_ids'][] = (int)$row['id'];
        }
    }
    $report[$table] = $summary;
}

$report['products'] = [
    'total' => count($selectedData['products']),
    'missing_category' => count(array_filter($selectedData['products'], static fn(array $row): bool => empty($row['category_id']))),
    'missing_section' => count(array_filter($selectedData['products'], static fn(array $row): bool => empty($row['section_id']))),
    'missing_product_name' => count(array_filter($selectedData['products'], static fn(array $row): bool => empty($row['product_name_id']))),
];
$report['product_service_links'] = ['total' => count($selectedData['product_service_links'])];
$report['orders'] = [
    'total' => count($selectedData['orders']),
    'statuses' => countBy($selectedData['orders'], static fn(array $row): string => repairMojibake((string)($row['status_order'] ?? ''))),
];

echo json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL;
