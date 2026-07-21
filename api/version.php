<?php
require_once __DIR__ . '/../includes/assets.php';
require_once __DIR__ . '/../includes/auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0, private');
header('Pragma: no-cache');
header('Expires: 0');
header('X-Robots-Tag: noindex');

echo json_encode(
    apiResponseEnvelope([
        'version' => applicationVersion(),
        'update_dialog' => [
            'title' => 'Доступна новая версия',
            'message' => 'На сервер загружено обновление. Обновите страницу, чтобы использовать новую версию. Перед обновлением сохраните несохранённые изменения. юджаил',
            'later_label' => 'Позже',
            'refresh_label' => 'Обновить страницу',
        ],
    ]),
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
);
releaseSessionLock();
