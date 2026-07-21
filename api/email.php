<?php

if (!defined('SMTP_HOST')) define('SMTP_HOST', 'smtp.gmail.com');
if (!defined('SMTP_PORT')) define('SMTP_PORT', 587);
if (!defined('SMTP_USER')) define('SMTP_USER', 'ewqq6653@gmail.com');
if (!defined('SMTP_PASS')) define('SMTP_PASS', 'zqlv xksv mnzt qsbj');
if (!defined('SMTP_FROM')) define('SMTP_FROM', 'ewqq6653@gmail.com');
if (!defined('SMTP_FROM_NAME')) define('SMTP_FROM_NAME', 'СтройСклад');

function emailLog(string $message): void {
    if (function_exists('appLog')) {
        appLog($message);
        return;
    }
    error_log($message);
}

function emailSafeUnlink(?string $path): void {
    if (!$path || !file_exists($path)) return;
    if (function_exists('appSafeUnlink')) {
        appSafeUnlink($path);
        return;
    }
    if (!unlink($path)) {
        emailLog('Не удалось удалить временный файл: ' . $path);
    }
}

/**
 * Generates PDF from HTML using mPDF or wkhtmltopdf.
 */
function generatePdfFromHtml(string $html): ?string {
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

    $wk = '';
    if (function_exists('shell_exec')) {
        $wk = trim((string)shell_exec('command -v wkhtmltopdf 2>/dev/null'));
    }
    if ($wk) {
        $tmpIn = tempnam(sys_get_temp_dir(), 'em_') . '.html';
        $tmpOut = tempnam(sys_get_temp_dir(), 'em_') . '.pdf';
        file_put_contents($tmpIn, $html);
        $cmd = escapeshellcmd($wk)
            . ' --orientation Landscape --page-size A4'
            . ' --encoding utf-8 --quiet'
            . ' ' . escapeshellarg($tmpIn)
            . ' ' . escapeshellarg($tmpOut);
        shell_exec($cmd);
        $pdf = file_exists($tmpOut) ? file_get_contents($tmpOut) : null;
        emailSafeUnlink($tmpIn);
        emailSafeUnlink($tmpOut);
        if ($pdf) return $pdf;
    }

    return null;
}

function buildMailMessage(string $to, string $subject, string $messageBody, string $filename, string $fileBytes, string $mimeType, string &$headers): string {
    $boundary = '----MailBoundary' . bin2hex(random_bytes(8));
    $fromHeader = SMTP_FROM_NAME
        ? '=?UTF-8?B?' . base64_encode(SMTP_FROM_NAME) . '?= <' . (SMTP_FROM ?: 'noreply@localhost') . '>'
        : (SMTP_FROM ?: 'noreply@localhost');

    $headers = "From: {$fromHeader}\r\n";
    $headers .= "Reply-To: " . (SMTP_FROM ?: 'noreply@localhost') . "\r\n";
    $headers .= "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: multipart/mixed; boundary=\"{$boundary}\"\r\n";

    $body = "--{$boundary}\r\n";
    $body .= "Content-Type: text/html; charset=UTF-8\r\n";
    $body .= "Content-Transfer-Encoding: base64\r\n\r\n";
    $body .= chunk_split(base64_encode($messageBody)) . "\r\n";

    $body .= "--{$boundary}\r\n";
    $body .= "Content-Type: {$mimeType}; name=\"{$filename}\"\r\n";
    $body .= "Content-Disposition: attachment; filename=\"{$filename}\"\r\n";
    $body .= "Content-Transfer-Encoding: base64\r\n\r\n";
    $body .= chunk_split(base64_encode($fileBytes)) . "\r\n";
    $body .= "--{$boundary}--\r\n";

    $encSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    $headers = "To: {$to}\r\nSubject: {$encSubject}\r\n" . $headers;
    return $body;
}

function buildSimpleMailMessage(string $to, string $subject, string $messageBody, string &$headers): string {
    $fromHeader = SMTP_FROM_NAME
        ? '=?UTF-8?B?' . base64_encode(SMTP_FROM_NAME) . '?= <' . (SMTP_FROM ?: 'noreply@localhost') . '>'
        : (SMTP_FROM ?: 'noreply@localhost');

    $headers = "From: {$fromHeader}\r\n";
    $headers .= "Reply-To: " . (SMTP_FROM ?: 'noreply@localhost') . "\r\n";
    $headers .= "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
    $headers .= "Content-Transfer-Encoding: base64\r\n";

    $encSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    $headers = "To: {$to}\r\nSubject: {$encSubject}\r\n" . $headers;
    return chunk_split(base64_encode($messageBody));
}

function smtpRead($fp): string {
    $data = '';
    while (($line = fgets($fp, 515)) !== false) {
        $data .= $line;
        if (isset($line[3]) && $line[3] === ' ') break;
    }
    return $data;
}

function smtpCmd($fp, string $cmd, array $ok): string {
    fwrite($fp, $cmd . "\r\n");
    $res = smtpRead($fp);
    $code = (int)substr($res, 0, 3);
    if (!in_array($code, $ok, true)) {
        throw new RuntimeException(trim($res));
    }
    return $res;
}

function sendSmtp(string $to, string $subject, string $messageBody, string $filename, string $fileBytes, string $mimeType): bool {
    $headers = '';
    $body = buildMailMessage($to, $subject, $messageBody, $filename, $fileBytes, $mimeType, $headers);
    $host = SMTP_HOST;
    $port = SMTP_PORT;
    $remote = ($port == 465 ? 'ssl://' : '') . $host . ':' . $port;
    $fp = @stream_socket_client($remote, $errno, $errstr, 20);
    if (!$fp) throw new RuntimeException($errstr ?: 'SMTP connection failed');
    stream_set_timeout($fp, 30);
    smtpRead($fp);
    smtpCmd($fp, 'EHLO ' . ($_SERVER['SERVER_NAME'] ?? 'localhost'), [250]);
    if ($port != 465) {
        smtpCmd($fp, 'STARTTLS', [220]);
        if (!stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
            throw new RuntimeException('STARTTLS failed');
        }
        smtpCmd($fp, 'EHLO ' . ($_SERVER['SERVER_NAME'] ?? 'localhost'), [250]);
    }
    smtpCmd($fp, 'AUTH LOGIN', [334]);
    smtpCmd($fp, base64_encode(SMTP_USER), [334]);
    smtpCmd($fp, base64_encode(SMTP_PASS), [235]);
    smtpCmd($fp, 'MAIL FROM:<' . (SMTP_FROM ?: SMTP_USER) . '>', [250]);
    smtpCmd($fp, 'RCPT TO:<' . $to . '>', [250, 251]);
    smtpCmd($fp, 'DATA', [354]);
    fwrite($fp, $headers . "\r\n" . $body . "\r\n.\r\n");
    $res = smtpRead($fp);
    smtpCmd($fp, 'QUIT', [221]);
    fclose($fp);
    return ((int)substr($res, 0, 3)) === 250;
}

function sendSimpleSmtp(string $to, string $subject, string $messageBody): bool {
    $headers = '';
    $body = buildSimpleMailMessage($to, $subject, $messageBody, $headers);
    $host = SMTP_HOST;
    $port = SMTP_PORT;
    $remote = ($port == 465 ? 'ssl://' : '') . $host . ':' . $port;
    $fp = @stream_socket_client($remote, $errno, $errstr, 20);
    if (!$fp) throw new RuntimeException($errstr ?: 'SMTP connection failed');
    stream_set_timeout($fp, 30);
    smtpRead($fp);
    smtpCmd($fp, 'EHLO ' . ($_SERVER['SERVER_NAME'] ?? 'localhost'), [250]);
    if ($port != 465) {
        smtpCmd($fp, 'STARTTLS', [220]);
        if (!stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
            throw new RuntimeException('STARTTLS failed');
        }
        smtpCmd($fp, 'EHLO ' . ($_SERVER['SERVER_NAME'] ?? 'localhost'), [250]);
    }
    smtpCmd($fp, 'AUTH LOGIN', [334]);
    smtpCmd($fp, base64_encode(SMTP_USER), [334]);
    smtpCmd($fp, base64_encode(SMTP_PASS), [235]);
    smtpCmd($fp, 'MAIL FROM:<' . (SMTP_FROM ?: SMTP_USER) . '>', [250]);
    smtpCmd($fp, 'RCPT TO:<' . $to . '>', [250, 251]);
    smtpCmd($fp, 'DATA', [354]);
    fwrite($fp, $headers . "\r\n" . $body . "\r\n.\r\n");
    $res = smtpRead($fp);
    smtpCmd($fp, 'QUIT', [221]);
    fclose($fp);
    return ((int)substr($res, 0, 3)) === 250;
}

/**
 * Sends email with attachment using PHPMailer, built-in SMTP, or native mail().
 */
function sendEmail(string $to, string $subject, string $messageBody, string $filename, string $fileBytes, string $mimeType): bool {
    $autoload = __DIR__ . '/../vendor/autoload.php';
    if (file_exists($autoload)) {
        require_once $autoload;
        if (class_exists('PHPMailer\\PHPMailer\\PHPMailer')) {
            $mail = new PHPMailer\PHPMailer\PHPMailer(true);
            try {
                $mail->isSMTP();
                $mail->Host = SMTP_HOST;
                $mail->SMTPAuth = true;
                $mail->Username = SMTP_USER;
                $mail->Password = SMTP_PASS;
                $mail->SMTPSecure = (SMTP_PORT == 465) ? 'ssl' : 'tls';
                $mail->Port = SMTP_PORT;
                $mail->CharSet = 'UTF-8';
                $mail->setFrom(SMTP_FROM ?: SMTP_USER, SMTP_FROM_NAME);
                $mail->addAddress($to);
                $mail->Subject = $subject;
                $mail->isHTML(true);
                $mail->Body = $messageBody;
                $mail->AltBody = strip_tags($messageBody);
                $mail->addStringAttachment($fileBytes, $filename, 'base64', $mimeType);
                $mail->send();
                return true;
            } catch (Throwable $e) {
                emailLog('Ошибка PHPMailer: ' . $e->getMessage());
            }
        }
    }

    try {
        if (SMTP_HOST && SMTP_USER && SMTP_PASS && function_exists('stream_socket_client')) {
            return sendSmtp($to, $subject, $messageBody, $filename, $fileBytes, $mimeType);
        }
    } catch (Throwable $e) {
        emailLog('Ошибка SMTP: ' . $e->getMessage());
    }

    $headers = '';
    $body = buildMailMessage($to, $subject, $messageBody, $filename, $fileBytes, $mimeType, $headers);
    $headers = preg_replace("/^To:.*\r\nSubject:.*\r\n/sU", '', $headers);
    $encSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    return mail($to, $encSubject, $body, $headers);
}

function sendSimpleEmail(string $to, string $subject, string $messageBody): bool {
    $autoload = __DIR__ . '/../vendor/autoload.php';
    if (file_exists($autoload)) {
        require_once $autoload;
        if (class_exists('PHPMailer\\PHPMailer\\PHPMailer')) {
            $mail = new PHPMailer\PHPMailer\PHPMailer(true);
            try {
                $mail->isSMTP();
                $mail->Host = SMTP_HOST;
                $mail->SMTPAuth = true;
                $mail->Username = SMTP_USER;
                $mail->Password = SMTP_PASS;
                $mail->SMTPSecure = (SMTP_PORT == 465) ? 'ssl' : 'tls';
                $mail->Port = SMTP_PORT;
                $mail->CharSet = 'UTF-8';
                $mail->setFrom(SMTP_FROM ?: SMTP_USER, SMTP_FROM_NAME);
                $mail->addAddress($to);
                $mail->Subject = $subject;
                $mail->isHTML(true);
                $mail->Body = $messageBody;
                $mail->AltBody = trim(preg_replace('/\s+/', ' ', strip_tags($messageBody)));
                $mail->send();
                return true;
            } catch (Throwable $e) {
                emailLog('Ошибка PHPMailer: ' . $e->getMessage());
            }
        }
    }

    try {
        if (SMTP_HOST && SMTP_USER && SMTP_PASS && function_exists('stream_socket_client')) {
            return sendSimpleSmtp($to, $subject, $messageBody);
        }
    } catch (Throwable $e) {
        emailLog('Ошибка SMTP: ' . $e->getMessage());
    }

    $headers = '';
    $body = buildSimpleMailMessage($to, $subject, $messageBody, $headers);
    $headers = preg_replace("/^To:.*\r\nSubject:.*\r\n/sU", '', $headers);
    $encSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    return mail($to, $encSubject, $body, $headers);
}

if (realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    require_once __DIR__ . '/../includes/auth.php';

    header('Content-Type: application/json; charset=utf-8');
    requireAuth();

    $input = json_decode(file_get_contents('php://input'), true);
    if (empty($input['html']) || empty($input['to'])) {
        jsonResponse(['error' => 'Не указан получатель или HTML'], 400);
    }

    $to = trim($input['to']);
    $subject = $input['subject'] ?? 'Заявка';
    $html = $input['html'];
    $filename = $input['filename'] ?? 'order.pdf';

    if (!filter_var($to, FILTER_VALIDATE_EMAIL)) {
        jsonResponse(['error' => 'Некорректный email адрес'], 400);
    }

    try {
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
        $messageBody = '<p>Документ во вложении.</p>';
        $sent = sendEmail($to, $subject, $messageBody, $filename, $fileBytes, $mimeType);
    } catch (Throwable $e) {
        jsonResponse(['error' => 'Ошибка отправки письма: ' . $e->getMessage()], 500);
    }

    if ($sent) {
        jsonResponse(['ok' => true, 'mode' => $mode]);
    }

    jsonResponse(['error' => 'Не удалось отправить письмо. Проверьте настройки SMTP в api/email.php'], 500);
}
