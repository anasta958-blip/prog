$ErrorActionPreference = 'Stop'

$php = 'E:\Program Files\XAMPP\php\php.exe'
$hostName = '127.0.0.1'
$port = 8092
$docRoot = 'E:\Program Files\XAMPP\htdocs'

if (!(Test-Path $php)) {
  throw "php.exe not found at $php"
}

$env:DB_HOST = 'localhost'
$env:DB_NAME = 'kompl_test'
$env:DB_USER = 'root'
$env:DB_PASS = ''

Write-Host "Starting test server at http://$hostName`:$port using database '$($env:DB_NAME)'."
& $php -S "$hostName`:$port" -t $docRoot
