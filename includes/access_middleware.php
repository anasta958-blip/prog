<?php

require_once __DIR__ . '/auth.php';

function accessMiddlewareAssertRule(array $user, array $rule): void {
    if (!empty($rule['admin'])) {
        if (($user['role'] ?? '') !== 'admin') jsonResponse(['error' => 'Forbidden'], 403);
        return;
    }

    if (isset($rule['tab'])) {
        if (!accessTabVisible($user, (string)$rule['tab'])) jsonResponse(['error' => 'Forbidden'], 403);
        return;
    }

    if (isset($rule['tabs_any']) && is_array($rule['tabs_any'])) {
        foreach ($rule['tabs_any'] as $tab) {
            if (accessTabVisible($user, (string)$tab)) return;
        }
        jsonResponse(['error' => 'Forbidden'], 403);
    }

    if (isset($rule['space'], $rule['action'])) {
        accessAssert($user, (string)$rule['space'], (string)$rule['action']);
        return;
    }

    if (isset($rule['space_any']) && is_array($rule['space_any'])) {
        foreach ($rule['space_any'] as $pair) {
            if (!is_array($pair) || count($pair) < 2) continue;
            if (accessCan($user, (string)$pair[0], (string)$pair[1])) return;
        }
        jsonResponse(['error' => 'Forbidden'], 403);
    }
}

function accessMiddlewareAssertAction(array $user, string $action, array $rules): void {
    if (!isset($rules[$action])) return;
    $rule = $rules[$action];
    if (!is_array($rule)) return;

    if (array_is_list($rule) && isset($rule[0]) && is_array($rule[0])) {
        foreach ($rule as $item) accessMiddlewareAssertRule($user, $item);
        return;
    }

    accessMiddlewareAssertRule($user, $rule);
}
