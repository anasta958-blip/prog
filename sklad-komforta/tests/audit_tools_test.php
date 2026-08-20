<?php

declare(strict_types=1);

if ($argc < 3) {
    fwrite(STDERR, "Usage: php audit_tools_test.php <current-schema.sql> <legacy-dump.sql>\n");
    exit(1);
}

function runJsonTool(string $script, array $arguments): array
{
    $command = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($script);
    foreach ($arguments as $argument) {
        $command .= ' ' . escapeshellarg($argument);
    }
    $output = shell_exec($command);
    $decoded = json_decode((string)$output, true, 512, JSON_THROW_ON_ERROR);
    if (!is_array($decoded)) {
        throw new RuntimeException("Tool {$script} did not return an object");
    }
    return $decoded;
}

function assertSameValue(mixed $expected, mixed $actual, string $message): void
{
    if ($expected !== $actual) {
        throw new RuntimeException($message . ': expected ' . var_export($expected, true) . ', got ' . var_export($actual, true));
    }
}

$root = dirname(__DIR__);
$audit = runJsonTool($root . '/scripts/audit_legacy_dump.php', [$argv[2]]);
assertSameValue(3814, $audit['row_counts']['product_names'] ?? null, 'Product count');
assertSameValue(55, $audit['row_counts']['kp_quotes'] ?? null, 'KP count');
assertSameValue(23, $audit['row_counts']['pkp_quotes'] ?? null, 'PKP count');
assertSameValue(13, $audit['kp_quotes']['legacy_without_proposal_types'] ?? null, 'Legacy KP count');
assertSameValue(1, $audit['pkp_quotes']['legacy_without_proposal_types'] ?? null, 'Legacy PKP count');

$difference = runJsonTool($root . '/scripts/compare_legacy_schema.php', [$argv[1], $argv[2]]);
assertSameValue(1, count($difference['differences'] ?? []), 'Schema difference count');
assertSameValue(
    ['category_scope_code'],
    $difference['differences']['catalog_services']['columns_only_in_current_schema'] ?? null,
    'Schema-only catalog_services columns'
);

fwrite(STDOUT, "Audit tool tests passed.\n");
