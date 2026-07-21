<?php
require_once __DIR__ . '/../includes/auth.php';

header('Content-Type: application/json; charset=utf-8');
requireAuth();

// Настройки
define('TG_BOT_TOKEN', '8048021750:AAH8QmtIo62Zvii192FdHuI4X2AyWYA0M64');   // токен от @BotFather
define('TG_CHAT_ID', '-1003743594367');       // ID группы, например -1001234567890

$input = json_decode(file_get_contents('php://input'), true);
if (empty($input['html'])) {
    jsonResponse(['error' => 'Нет данных'], 400);
}

/**
 * Генерирует PDF из HTML с помощью mPDF или wkhtmltopdf.
 */
function generatePdfFromHtml(string $html): ?string {
    // Попытка 1: mPDF, если установлен через Composer.
    $mpdfAutoload = __DIR__ . '/../vendor/autoload.php';
    if (file_exists($mpdfAutoload)) {
        require_once $mpdfAutoload;
        if (class_exists('\\Mpdf\\Mpdf')) {
            $mpdf = new \Mpdf\Mpdf([
                'mode' => 'utf-8',
                'format' => 'A4',
                'orientation' => 'L',
                'margin_top' => 10,
                'margin_bottom' => 10,
                'margin_left' => 10,
                'margin_right' => 10,
            ]);
            $mpdf->WriteHTML($html);
            return $mpdf->Output('', 'S');
        }
    }

    // Попытка 2: wkhtmltopdf.
    $wk = '';
    if (function_exists('shell_exec')) {
        $wk = trim((string)shell_exec('command -v wkhtmltopdf 2>/dev/null'));
    }
    if ($wk) {
        $tmpIn = tempnam(sys_get_temp_dir(), 'tg_') . '.html';
        $tmpOut = tempnam(sys_get_temp_dir(), 'tg_') . '.pdf';
        file_put_contents($tmpIn, $html);
        $cmd = escapeshellcmd($wk)
            . ' --orientation Landscape --page-size A4'
            . ' --encoding utf-8 --quiet'
            . ' ' . escapeshellarg($tmpIn)
            . ' ' . escapeshellarg($tmpOut);
        shell_exec($cmd);
        $pdf = file_exists($tmpOut) ? file_get_contents($tmpOut) : null;
        appSafeUnlink($tmpIn);
        appSafeUnlink($tmpOut);
        if ($pdf) return $pdf;
    }

    return null;
}

/**
 * Отправляет PDF-документ в Telegram через sendDocument (multipart).
 */
function sendTgDocument(string $token, string $chatId, string $fileBytes, string $caption, string $filename, string $mimeType): array {
    $url = "https://api.telegram.org/bot{$token}/sendDocument";
    $boundary = '----TgBoundary' . bin2hex(random_bytes(8));

    $body = "--{$boundary}\r\n";
    $body .= "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n{$chatId}\r\n";
    $body .= "--{$boundary}\r\n";
    $body .= "Content-Disposition: form-data; name=\"caption\"\r\n\r\n{$caption}\r\n";
    $body .= "--{$boundary}\r\n";
    $body .= "Content-Disposition: form-data; name=\"document\"; filename=\"{$filename}\"\r\n";
    $body .= "Content-Type: {$mimeType}\r\n\r\n";
    $body .= $fileBytes . "\r\n";
    $body .= "--{$boundary}--\r\n";

    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $body,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 30,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_HTTPHEADER => ["Content-Type: multipart/form-data; boundary={$boundary}"],
            CURLOPT_SSL_VERIFYPEER => true,
        ]);
        $resp = curl_exec($ch);
        $err = curl_error($ch);
        curl_close($ch);
        if ($resp === false) return ['ok' => false, 'description' => 'cURL error: ' . $err];
    } else {
        $ctx = stream_context_create(['http' => [
            'method' => 'POST',
            'header' => "Content-Type: multipart/form-data; boundary={$boundary}\r\nContent-Length: " . strlen($body),
            'content' => $body,
            'timeout' => 30,
        ]]);
        $resp = appFileGetContents($url, false, $ctx, 0, null, 'telegramSendDocument');
        if ($resp === false) return ['ok' => false, 'description' => 'Ошибка соединения с Telegram'];
    }

    $decoded = json_decode($resp, true);
    if (!$decoded) return ['ok' => false, 'description' => 'Неверный ответ Telegram: ' . substr($resp, 0, 200)];
    return $decoded;
}

$html = $input['html'] ?? '';
$caption = $input['caption'] ?? 'Новая комплектация';
$filename = $input['filename'] ?? 'order.pdf';
$pdfBytes = generatePdfFromHtml($html);
if ($pdfBytes) {
    $fileBytes = $pdfBytes;
    $mimeType = 'application/pdf';
    $mode = 'pdf';
} else {
    $fileBytes = $html;
    $mimeType = 'text/html; charset=UTF-8';
    $filename = preg_replace('/\.pdf$/i', '.html', $filename);
    $mode = 'html';
}

$result = sendTgDocument(TG_BOT_TOKEN, TG_CHAT_ID, $fileBytes, $caption, $filename, $mimeType);
if (empty($result['ok'])) {
    jsonResponse(['error' => $result['description'] ?? 'Ошибка Telegram при отправке документа'], 500);
}

jsonResponse(['ok' => true, 'mode' => $mode]);
