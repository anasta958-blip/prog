$ErrorActionPreference = 'Stop'

$root = 'E:\Program Files\XAMPP\htdocs'
$src = Join-Path $root '_restore\index.php'
$lines = [System.IO.File]::ReadAllLines($src, [System.Text.Encoding]::UTF8)
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBom([string]$path, [string]$content) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
  }
  [System.IO.File]::WriteAllText($path, $content, $utf8)
}

function Slice([int]$start, [int]$end) {
  return (($lines[($start - 1)..($end - 1)]) -join "`r`n") + "`r`n"
}

$dirs = @(
  'templates\layout',
  'templates\spaces\catalog',
  'templates\spaces\orders',
  'templates\spaces\kp',
  'templates\spaces\pkp',
  'templates\spaces\settings',
  'templates\modals',
  'assets\css',
  'assets\js\spaces'
)

foreach ($d in $dirs) {
  [System.IO.Directory]::CreateDirectory((Join-Path $root $d)) | Out-Null
}

Write-Utf8NoBom (Join-Path $root 'assets\css\app.css') (Slice 9 563)

Write-Utf8NoBom (Join-Path $root 'templates\layout\login.php') (Slice 565 654)
Write-Utf8NoBom (Join-Path $root 'templates\layout\app-shell-start.php') (Slice 655 655)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\home.php') (Slice 656 664)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\catalog\catalog.php') (Slice 666 703)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\orders\catalog-orders.php') (Slice 705 729)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\orders\orders.php') (Slice 731 759)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\orders\order-edit.php') (Slice 761 819)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\orders\new-request.php') (Slice 821 849)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\kp\catalog.php') (Slice 851 879)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\kp\company.php') (Slice 881 940)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\kp\clients.php') (Slice 942 961)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\kp\builder.php') (Slice 963 1004)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\kp\list.php') (Slice 1006 1013)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\pkp\presets.php') (Slice 1015 1026)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\orders\employees.php') (Slice 1028 1039)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\settings\users.php') (Slice 1041 1054)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\settings\units.php') (Slice 1056 1077)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\settings\suppliers.php') (Slice 1079 1098)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\settings\groups.php') (Slice 1100 1122)
Write-Utf8NoBom (Join-Path $root 'templates\spaces\settings\access.php') (Slice 1124 1142)
Write-Utf8NoBom (Join-Path $root 'templates\layout\app-shell-end.php') (Slice 1144 1146)
Write-Utf8NoBom (Join-Path $root 'templates\modals\all.php') (Slice 1148 1465)

$startConstants = 1468
$startState = 1603
$startInit = 1626
$startAuth = 1746
$startNav = 1760
$startCatalog = 1959
$startOrders = 2724
$startBuilder = 3249
$startKp = 5244
$startUsers = 8784
$startModals = 8910
$startApi = 8943
$startHelpers = 8962
$endScript = 10837

Write-Utf8NoBom (Join-Path $root 'assets\js\app.constants.js') (Slice $startConstants ($startState - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\app.state.js') (Slice $startState ($startInit - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\app.init.js') (Slice $startInit ($startAuth - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\app.auth.js') (Slice $startAuth ($startNav - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\app.nav.js') (Slice $startNav ($startCatalog - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\catalog.js') (Slice $startCatalog ($startOrders - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\orders.js') (Slice $startOrders ($startBuilder - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\app.builder.js') (Slice $startBuilder ($startKp - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\kp.js') (Slice $startKp ($startUsers - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\users.js') (Slice $startUsers ($startModals - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\app.modals.js') (Slice $startModals ($startApi - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\app.api.js') (Slice $startApi ($startHelpers - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\app.helpers.js') (Slice $startHelpers $endScript)

$index = @"
<?php require_once __DIR__ . '/includes/auth.php'; ?>
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Склад Комфорта</title>
  <link rel="stylesheet" href="assets/css/app.css">
</head>
<body>
<?php require __DIR__ . '/templates/layout/login.php'; ?>
<?php require __DIR__ . '/templates/layout/app-shell-start.php'; ?>
<?php require __DIR__ . '/templates/spaces/home.php'; ?>
<?php require __DIR__ . '/templates/spaces/catalog/catalog.php'; ?>
<?php require __DIR__ . '/templates/spaces/orders/catalog-orders.php'; ?>
<?php require __DIR__ . '/templates/spaces/orders/orders.php'; ?>
<?php require __DIR__ . '/templates/spaces/orders/order-edit.php'; ?>
<?php require __DIR__ . '/templates/spaces/orders/new-request.php'; ?>
<?php require __DIR__ . '/templates/spaces/kp/catalog.php'; ?>
<?php require __DIR__ . '/templates/spaces/kp/company.php'; ?>
<?php require __DIR__ . '/templates/spaces/kp/clients.php'; ?>
<?php require __DIR__ . '/templates/spaces/kp/builder.php'; ?>
<?php require __DIR__ . '/templates/spaces/kp/list.php'; ?>
<?php require __DIR__ . '/templates/spaces/pkp/presets.php'; ?>
<?php require __DIR__ . '/templates/spaces/orders/employees.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/users.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/units.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/suppliers.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/groups.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/access.php'; ?>
<?php require __DIR__ . '/templates/layout/app-shell-end.php'; ?>
<?php require __DIR__ . '/templates/modals/all.php'; ?>
<script>
<?php require __DIR__ . '/assets/js/app.constants.js'; ?>
<?php require __DIR__ . '/assets/js/app.state.js'; ?>
<?php require __DIR__ . '/assets/js/app.init.js'; ?>
<?php require __DIR__ . '/assets/js/app.auth.js'; ?>
<?php require __DIR__ . '/assets/js/app.nav.js'; ?>
<?php require __DIR__ . '/assets/js/spaces/catalog.js'; ?>
<?php require __DIR__ . '/assets/js/spaces/orders.js'; ?>
<?php require __DIR__ . '/assets/js/app.builder.js'; ?>
<?php require __DIR__ . '/assets/js/spaces/kp.js'; ?>
<?php require __DIR__ . '/assets/js/spaces/users.js'; ?>
<?php require __DIR__ . '/assets/js/app.modals.js'; ?>
<?php require __DIR__ . '/assets/js/app.api.js'; ?>
<?php require __DIR__ . '/assets/js/app.helpers.js'; ?>
</script>
</body>
</html>
"@

Write-Utf8NoBom (Join-Path $root 'index.php') $index

foreach ($rel in @('assets\css\app.css', 'assets\js\spaces\kp.js', 'templates\spaces\settings\access.php', 'index.php')) {
  $path = Join-Path $root $rel
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $head = ($bytes[0..([Math]::Min(3, $bytes.Length - 1))] | ForEach-Object { $_.ToString('X2') }) -join ' '
  Write-Output ("WROTE`t{0}`t{1}" -f $rel, $head)
}
