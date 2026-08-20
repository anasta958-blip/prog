<?php

declare(strict_types=1);

if ($argc < 3 || !is_file($argv[1]) || !is_file($argv[2])) {
    fwrite(STDERR, "Usage: php compare_legacy_schema.php <current-schema.sql> <legacy-dump.sql>\n");
    exit(1);
}

function schemaInventory(string $path): array
{
    $sql = file_get_contents($path);
    if ($sql === false) {
        throw new RuntimeException("Cannot read {$path}");
    }
    preg_match_all('/CREATE TABLE `([^`]+)`\s*\((.*?)\)\s*ENGINE=/s', $sql, $matches, PREG_SET_ORDER);
    $tables = [];
    foreach ($matches as $match) {
        preg_match_all('/^\s*`([^`]+)`\s+/m', $match[2], $columnMatches);
        $tables[$match[1]] = array_values(array_unique($columnMatches[1]));
    }
    ksort($tables);
    return $tables;
}

$current = schemaInventory($argv[1]);
$dump = schemaInventory($argv[2]);
$allTables = array_values(array_unique([...array_keys($current), ...array_keys($dump)]));
sort($allTables);
$differences = [];

foreach ($allTables as $table) {
    $currentColumns = $current[$table] ?? [];
    $dumpColumns = $dump[$table] ?? [];
    $onlyCurrent = array_values(array_diff($currentColumns, $dumpColumns));
    $onlyDump = array_values(array_diff($dumpColumns, $currentColumns));
    if ($onlyCurrent || $onlyDump || !isset($current[$table]) || !isset($dump[$table])) {
        $differences[$table] = [
            'missing_from_current_schema' => !isset($current[$table]),
            'missing_from_dump_schema' => !isset($dump[$table]),
            'columns_only_in_current_schema' => $onlyCurrent,
            'columns_only_in_dump_schema' => $onlyDump,
        ];
    }
}

echo json_encode([
    'current_table_count' => count($current),
    'dump_table_count' => count($dump),
    'differences' => $differences,
], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . PHP_EOL;
