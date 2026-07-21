$ErrorActionPreference = 'Stop'

$path = 'E:\Program Files\XAMPP\htdocs\index.php'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

$titleRegex = [regex]::new('<title>.*?</title>')
$text = $titleRegex.Replace(
  $text,
  '<title>&#1057;&#1082;&#1083;&#1072;&#1076; &#1050;&#1086;&#1084;&#1092;&#1086;&#1088;&#1090;&#1072;</title>',
  1
)

$scriptBlock = @"
<script src="assets/js/app.constants.js"></script>
<script src="assets/js/app.state.js"></script>
<script src="assets/js/app.init.js"></script>
<script src="assets/js/app.auth.js"></script>
<script src="assets/js/app.nav.js"></script>
<script src="assets/js/spaces/catalog.js"></script>
<script src="assets/js/spaces/orders.js"></script>
<script src="assets/js/builder/core.js"></script>
<script src="assets/js/builder/catalog-fields.js"></script>
<script src="assets/js/builder/flow.js"></script>
<script src="assets/js/builder/dom.js"></script>
<script src="assets/js/builder/render.js"></script>
<script src="assets/js/builder/save.js"></script>
<script src="assets/js/spaces/kp/state.js"></script>
<script src="assets/js/spaces/kp/catalog.js"></script>
<script src="assets/js/spaces/kp/builder-core.js"></script>
<script src="assets/js/spaces/kp/render.js"></script>
<script src="assets/js/spaces/kp/save.js"></script>
<script src="assets/js/spaces/users.js"></script>
<script src="assets/js/app.modals.js"></script>
<script src="assets/js/app.api.js"></script>
<script src="assets/js/app.helpers.js"></script>
"@

$scriptRegex = [regex]::new('<script>[\s\S]*?</script>')
$text = $scriptRegex.Replace($text, $scriptBlock, 1)
[System.IO.File]::WriteAllText($path, $text, $utf8)
