param([string]$Container = 'sklad-komforta-postgres-1')
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$schema = 'supplier_test_' + [Guid]::NewGuid().ToString('N')
$migration = (Get-Content -Raw -LiteralPath (Join-Path $root 'migrations/tenant/0044_remove_legacy_supplier.sql')).Replace('__TENANT_SCHEMA__', $schema)
$sql = (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'remove_legacy_supplier.sql')).Replace('supplier_removal_regression', $schema)
$sql = $sql.Replace('-- APPLY_MIGRATION_TWICE', "$migration`n$migration")
$sql | docker exec -i $Container sh -lc 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
if ($LASTEXITCODE -ne 0) { throw 'Supplier removal migration regression failed.' }
