<?php
require_once __DIR__ . '/includes/auth.php';
releaseSessionLock();
require_once __DIR__ . '/includes/assets.php';
?>
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Склад Комфорта</title>
  <link rel="stylesheet" href="<?= assetUrl('assets/css/app.css') ?>">
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
<?php require __DIR__ . '/templates/spaces/kp/contractors.php'; ?>
<?php require __DIR__ . '/templates/spaces/kp/builder.php'; ?>
<?php require __DIR__ . '/templates/spaces/kp/list.php'; ?>
<?php require __DIR__ . '/templates/spaces/documents/builder.php'; ?>
<?php require __DIR__ . '/templates/spaces/orders/employees.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/users.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/units.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/suppliers.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/groups.php'; ?>
<?php require __DIR__ . '/templates/spaces/settings/access.php'; ?>
<?php require __DIR__ . '/templates/layout/app-shell-end.php'; ?>
<?php require __DIR__ . '/templates/modals/all.php'; ?>
<script>window.APP_VERSION=<?= json_encode(applicationVersion(), JSON_UNESCAPED_SLASHES) ?>;</script>
<script>
window.APP_LAZY_ASSETS={
  'assets/js/shared/employees.js':<?= json_encode(assetUrl('assets/js/shared/employees.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/users.js':<?= json_encode(assetUrl('assets/js/spaces/users.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/settings.js':<?= json_encode(assetUrl('assets/js/spaces/settings.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/orders.js':<?= json_encode(assetUrl('assets/js/spaces/orders.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/catalog.js':<?= json_encode(assetUrl('assets/js/spaces/catalog.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/kp/state.js':<?= json_encode(assetUrl('assets/js/spaces/kp/state.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/kp/catalog.js':<?= json_encode(assetUrl('assets/js/spaces/kp/catalog.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/kp/builder-core.js':<?= json_encode(assetUrl('assets/js/spaces/kp/builder-core.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/kp/render.js':<?= json_encode(assetUrl('assets/js/spaces/kp/render.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/kp/save.js':<?= json_encode(assetUrl('assets/js/spaces/kp/save.js'), JSON_UNESCAPED_SLASHES) ?>,
  'node_modules/jspdf/dist/jspdf.umd.min.js':<?= json_encode(assetUrl('node_modules/jspdf/dist/jspdf.umd.min.js'), JSON_UNESCAPED_SLASHES) ?>,
  'node_modules/jspdf-autotable/dist/jspdf.plugin.autotable.min.js':<?= json_encode(assetUrl('node_modules/jspdf-autotable/dist/jspdf.plugin.autotable.min.js'), JSON_UNESCAPED_SLASHES) ?>,
  'assets/js/spaces/documents.js':<?= json_encode(assetUrl('assets/js/spaces/documents.js'), JSON_UNESCAPED_SLASHES) ?>
};
</script>
<script src="<?= assetUrl('assets/js/app.constants.js') ?>"></script>
<script src="<?= assetUrl('assets/js/app.state.js') ?>"></script>
<script src="<?= assetUrl('assets/js/app.api.js') ?>"></script>
<script src="<?= assetUrl('assets/js/app.loader.js') ?>"></script>
<script src="<?= assetUrl('assets/js/app.init.js') ?>"></script>
<script src="<?= assetUrl('assets/js/app.auth.js') ?>"></script>
<script src="<?= assetUrl('assets/js/app.nav.js') ?>"></script>
<script src="<?= assetUrl('assets/js/builder/core.js') ?>"></script>
<script src="<?= assetUrl('assets/js/builder/catalog-fields.js') ?>"></script>
<script src="<?= assetUrl('assets/js/builder/flow.js') ?>"></script>
<script src="<?= assetUrl('assets/js/builder/dom.js') ?>"></script>
<script src="<?= assetUrl('assets/js/builder/render.js') ?>"></script>
<script src="<?= assetUrl('assets/js/builder/drafts.js') ?>"></script>
<script src="<?= assetUrl('assets/js/builder/save.js') ?>"></script>
<script src="<?= assetUrl('assets/js/app.modals.js') ?>"></script>
<script src="<?= assetUrl('assets/js/app.helpers.js') ?>"></script>
</body>
</html>
