<?php

function paginationFromRequest(int $defaultPerPage = 50, int $maxPerPage = 200): ?array {
    $hasPage = array_key_exists('page', $_GET) || array_key_exists('per_page', $_GET);
    if (!$hasPage) return null;

    $page = max(1, intval($_GET['page'] ?? 1));
    $perPage = intval($_GET['per_page'] ?? $defaultPerPage);
    if ($perPage <= 0) $perPage = $defaultPerPage;
    $perPage = min(max(1, $perPage), $maxPerPage);

    return [
        'page' => $page,
        'per_page' => $perPage,
        'offset' => ($page - 1) * $perPage,
    ];
}

function paginationLimitSql(?array $pagination): string {
    if (!$pagination) return '';
    return ' LIMIT ' . intval($pagination['per_page']) . ' OFFSET ' . intval($pagination['offset']);
}

function paginationCount(PDO $db, string $fromWhereSql, array $params = []): int {
    $st = $db->prepare('SELECT COUNT(*) AS cnt ' . $fromWhereSql);
    $st->execute($params);
    return intval($st->fetch()['cnt'] ?? 0);
}

function paginationPayload(array $items, int $total, array $pagination): array {
    $page = intval($pagination['page']);
    $perPage = intval($pagination['per_page']);
    $pages = $perPage > 0 ? (int)ceil($total / $perPage) : 1;
    if ($pages < 1) $pages = 1;

    return [
        'items' => $items,
        'pagination' => [
            'page' => $page,
            'per_page' => $perPage,
            'total' => $total,
            'pages' => $pages,
            'has_prev' => $page > 1,
            'has_next' => $page < $pages,
        ],
    ];
}

function jsonPaginatedResponse(array $items, ?array $pagination, int $total = 0): void {
    if (!$pagination) {
        jsonResponse($items);
    }
    jsonResponse(paginationPayload($items, $total, $pagination));
}
