<?php

function assetUrl(string $relativePath): string {
    $relativePath = ltrim(str_replace('\\', '/', $relativePath), '/');
    $absolutePath = dirname(__DIR__) . '/' . $relativePath;
    $version = is_file($absolutePath) ? (string)filemtime($absolutePath) : '0';

    return htmlspecialchars($relativePath . '?v=' . $version, ENT_QUOTES, 'UTF-8');
}

function applicationVersion(): string {
    $generated = generatedApplicationVersion();
    if ($generated !== null) {
        return $generated;
    }

    return calculateApplicationVersion();
}

function generatedApplicationVersion(): ?string {
    $root = dirname(__DIR__);
    $versionFile = $root . '/version.json';
    if (!is_file($versionFile)) {
        return null;
    }

    $versionMtime = filemtime($versionFile);
    if ($versionMtime === false || $versionMtime < latestApplicationSourceMtime($root)) {
        return null;
    }

    $raw = file_get_contents($versionFile);
    if ($raw === false || $raw === '') {
        return null;
    }

    $data = json_decode($raw, true);
    $version = is_array($data) ? (string)($data['version'] ?? '') : '';
    return preg_match('/^[a-f0-9]{64}$/i', $version) ? strtolower($version) : null;
}

function applicationVersionPaths(string $root): array {
    return [
        $root . '/assets',
        $root . '/api',
        $root . '/includes',
        $root . '/templates',
        $root . '/index.php',
        $root . '/schema.sql',
    ];
}

function latestApplicationSourceMtime(string $root): int {
    $latest = 0;
    foreach (applicationVersionFiles($root) as $file) {
        $mtime = filemtime($file);
        if ($mtime !== false && $mtime > $latest) {
            $latest = $mtime;
        }
    }
    return $latest;
}

function calculateApplicationVersion(): string {
    $root = dirname(__DIR__);
    $files = applicationVersionFiles($root);
    $signature = [];

    foreach ($files as $file) {
        $signature[] = str_replace('\\', '/', substr($file, strlen($root) + 1))
            . ':' . filesize($file)
            . ':' . filemtime($file);
    }

    return hash('sha256', implode("\n", $signature));
}

function applicationVersionFiles(string $root): array {
    $paths = [
        ...applicationVersionPaths($root),
    ];
    $files = [];

    foreach ($paths as $path) {
        if (is_file($path)) {
            $files[] = $path;
            continue;
        }
        if (!is_dir($path)) continue;

        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS)
        );
        foreach ($iterator as $file) {
            if (!$file->isFile()) continue;
            $files[] = $file->getPathname();
        }
    }

    sort($files, SORT_STRING);
    return $files;
}
