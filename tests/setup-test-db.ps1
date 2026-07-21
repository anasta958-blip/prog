$ErrorActionPreference = 'Stop'

$mysql = 'E:\Program Files\XAMPP\mysql\bin\mysql.exe'
$php = 'E:\Program Files\XAMPP\php\php.exe'
$sourceDb = 'kompl'
$testDb = 'kompl_test'

if (!(Test-Path $mysql)) {
  throw "mysql.exe not found at $mysql"
}

if (!(Test-Path $php)) {
  throw "php.exe not found at $php"
}

$tables = & $mysql -uroot -N -D $sourceDb -e "SHOW TABLES"
& $mysql -uroot -e "DROP DATABASE IF EXISTS $testDb; CREATE DATABASE $testDb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

foreach ($table in $tables) {
  & $mysql -uroot -e "CREATE TABLE $testDb.$table LIKE $sourceDb.$table; INSERT INTO $testDb.$table SELECT * FROM $sourceDb.$table;"
}

$companyProfilesUpdate = Join-Path $PSScriptRoot '..\update_2026_06_29_company_profiles_multi.sql'
if (Test-Path $companyProfilesUpdate) {
  & $mysql -uroot -D $testDb -e "SOURCE $companyProfilesUpdate"
}

$kpCreatedOrderUpdate = Join-Path $PSScriptRoot '..\update_2026_07_01_kp_created_order_id.sql'
if (Test-Path $kpCreatedOrderUpdate) {
  & $mysql -uroot -D $testDb -e "SOURCE $kpCreatedOrderUpdate"
}

$performanceIndexesUpdate = Join-Path $PSScriptRoot '..\update_2026_07_03_performance_indexes.sql'
if (Test-Path $performanceIndexesUpdate) {
  & $mysql -uroot -D $testDb -e "SOURCE $performanceIndexesUpdate"
}

& $mysql -uroot -D $testDb -e "CREATE TABLE IF NOT EXISTS company_director (
  singleton_id TINYINT UNSIGNED NOT NULL DEFAULT 1 PRIMARY KEY,
  user_id INT NOT NULL UNIQUE,
  updated_by INT DEFAULT NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_company_director_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_company_director_updated_by FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

& $mysql -uroot -D $testDb -e "CREATE TABLE IF NOT EXISTS documents_templates (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  source_quote_id INT DEFAULT NULL,
  title VARCHAR(255) NOT NULL,
  page_format VARCHAR(40) DEFAULT 'a4',
  theme_name VARCHAR(40) DEFAULT 'clean',
  payload_json LONGTEXT DEFAULT NULL,
  current_version_id INT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_documents_templates_user (user_id),
  INDEX idx_documents_templates_quote (source_quote_id),
  INDEX idx_documents_templates_current_version (current_version_id)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

& $mysql -uroot -D $testDb -e "CREATE TABLE IF NOT EXISTS documents_template_versions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  template_id INT NOT NULL,
  version_no INT NOT NULL,
  version_name VARCHAR(255) NOT NULL,
  source_quote_id INT DEFAULT NULL,
  page_format VARCHAR(40) DEFAULT 'a4',
  theme_name VARCHAR(40) DEFAULT 'clean',
  payload_json LONGTEXT DEFAULT NULL,
  created_by INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_documents_template_versions_template (template_id),
  INDEX idx_documents_template_versions_version (template_id, version_no)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

$hash = & $php -r "echo password_hash('password', PASSWORD_BCRYPT), PHP_EOL;"
$hash = $hash.Trim()
& $mysql -uroot -D $testDb -e "UPDATE users SET password = '$hash'; TRUNCATE TABLE role_access_policies;"

$fixtureSql = @"
SET @approved_status = CAST(0xD0A1D0BED0B3D0BBD0B0D181D0BED0B2D0B0D0BDD0BE AS CHAR CHARACTER SET utf8mb4);

DELETE FROM kp_quotes WHERE public_token IN ('e2e-manager-kp','e2e-admin-kp');
INSERT INTO kp_quotes (user_id, client_id, title, status, workflow_status, selected_variant_label, company_snapshot_json, client_snapshot_json, payload_json, public_token)
SELECT 10, NULL, 'E2E MANAGER KP', status, workflow_status, NULL, NULL, NULL, '{}', 'e2e-manager-kp'
FROM kp_quotes
ORDER BY id DESC
LIMIT 1;
INSERT INTO kp_quotes (user_id, client_id, title, status, workflow_status, selected_variant_label, company_snapshot_json, client_snapshot_json, payload_json, public_token)
SELECT 9, NULL, 'E2E ADMIN KP', status, workflow_status, NULL, NULL, NULL, '{}', 'e2e-admin-kp'
FROM kp_quotes
ORDER BY id DESC
LIMIT 1;

DELETE FROM pkp_quotes WHERE public_token IN ('e2e-manager-pkp','e2e-admin-pkp');
INSERT INTO pkp_quotes (user_id, client_id, title, status, workflow_status, selected_variant_label, company_snapshot_json, client_snapshot_json, payload_json, public_token)
SELECT 10, NULL, 'E2E MANAGER PKP', status, workflow_status, NULL, NULL, NULL, '{}', 'e2e-manager-pkp'
FROM pkp_quotes
ORDER BY id DESC
LIMIT 1;
INSERT INTO pkp_quotes (user_id, client_id, title, status, workflow_status, selected_variant_label, company_snapshot_json, client_snapshot_json, payload_json, public_token)
SELECT 9, NULL, 'E2E ADMIN PKP', status, workflow_status, NULL, NULL, NULL, '{}', 'e2e-admin-pkp'
FROM pkp_quotes
ORDER BY id DESC
LIMIT 1;

DELETE FROM orders WHERE address IN ('E2E ORDER MANAGER', 'E2E ORDER ADMIN');
INSERT INTO orders (order_number, address, manager_id, rop_id, status, status_order, doc_snapshot, order_type, client_type)
VALUES
  ('E2E-MANAGER-ORDER', 'E2E ORDER MANAGER', 10, 12, 'active', 'Составление комплектации', '[]', 'Дом', 'Тест'),
  ('E2E-ADMIN-ORDER', 'E2E ORDER ADMIN', 9, 12, 'active', 'Составление комплектации', '[]', 'Дом', 'Тест');

DELETE FROM product_names WHERE name IN ('E2E FLOW ITEM','E2E AUTO ITEM');
DELETE FROM catalog_services WHERE name = 'E2E AUTO WORK';
DELETE FROM catalog_groups WHERE section_id = 1 AND name = 'E2E GROUP';

INSERT INTO catalog_groups (section_id, name, sort_order)
VALUES (1, 'E2E GROUP', 9999);

INSERT INTO catalog_services (
  name, cost, marking_size, purchase_price, minimal_price, retail_price, linked_product_name_id, unit, sort_order
) VALUES (
  'E2E AUTO WORK', 500, 'WORK-MARK', 300, 400, 500, NULL, 'svc', 9999
);
SET @e2e_service_id = LAST_INSERT_ID();

INSERT INTO product_names (
  section_id, group_name, name, sort_order, is_custom, status, supplier, marking_size, note, unit,
  purchase_price, retail_price, discount_value, labor_price, minimal_price, linked_service_id, technical_note
) VALUES
  (1, 'E2E GROUP', 'E2E FLOW ITEM', 9998, 0, @approved_status, 'E2E SUP', 'SIZE-A', '', 'pcs', 1000, 1500, 0, 0, 1200, @e2e_service_id, ''),
  (1, 'E2E GROUP', 'E2E FLOW ITEM', 9999, 0, @approved_status, 'E2E SUP', 'SIZE-B', '', 'pcs', 1100, 1600, 0, 0, 1300, @e2e_service_id, ''),
  (1, 'E2E GROUP', 'E2E AUTO ITEM', 10000, 0, @approved_status, 'E2E SUP', 'AUTO-1', '', 'pcs', 2000, 2600, 0, 0, 2200, @e2e_service_id, '');
"@

& $mysql -uroot -D $testDb -e $fixtureSql

Write-Host "Test database '$testDb' has been rebuilt from '$sourceDb'."
Write-Host "All test users now use password: password"
