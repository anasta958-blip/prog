<?php
require_once __DIR__ . '/../includes/assets.php';

$root = dirname(__DIR__);
$version = calculateApplicationVersion();
$payload = [
    'version' => $version,
    'generated_at' => date('c'),
    'files' => count(applicationVersionFiles($root)),
];

$json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
if ($json === false) {
    fwrite(STDERR, "Не удалось сформировать version.json\n");
    exit(1);
}

$target = $root . '/version.json';
if (file_put_contents($target, $json . "\n", LOCK_EX) === false) {
    fwrite(STDERR, "Не удалось записать version.json\n");
    exit(1);
}

echo "version.json обновлён: {$version}\n";
