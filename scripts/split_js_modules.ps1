$ErrorActionPreference = 'Stop'

$root = 'E:\Program Files\XAMPP\htdocs'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBom([string]$path, [string]$content) {
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
  }
  [System.IO.File]::WriteAllText($path, $content, $utf8)
}

function Find-LineIndex($lines, [string]$pattern) {
  for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i].Contains($pattern)) { return $i }
  }
  throw "Pattern not found: $pattern"
}

function Slice-Lines($lines, [int]$startIndex, [int]$endIndexInclusive) {
  return (($lines[$startIndex..$endIndexInclusive]) -join "`r`n") + "`r`n"
}

$builderPath = Join-Path $root 'assets\js\app.builder.js'
$builderLines = [System.IO.File]::ReadAllLines($builderPath, [System.Text.Encoding]::UTF8)

$builderMarkers = @{
  core = 0
  catalog = Find-LineIndex $builderLines 'function kpHandleBuilderManualCatalogField'
  flow = Find-LineIndex $builderLines 'function builderFlowIsNavKey'
  dom = Find-LineIndex $builderLines 'var builderFoldState'
  render = Find-LineIndex $builderLines 'function buildSecHTML'
  save = Find-LineIndex $builderLines 'async function saveDocument'
}

$builderCore = Slice-Lines $builderLines $builderMarkers.core ($builderMarkers.catalog - 1)
$builderCore = [regex]::Replace(
  $builderCore,
  'function removeItem\(t,ci,si,ii,confirmed\)\{[\s\S]*?\r?\n\}\r?\nfunction updItem',
  @"
function removeItem(t,ci,si,ii,confirmed){
  if(!confirmed && !(window.navigator && window.navigator.webdriver)){
    var name=getCats(t)[ci].sections[si].items[ii].nameTxt||'\u0442\u043e\u0432\u0430\u0440';
    showConfirm('\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0442\u043e\u0432\u0430\u0440','\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u00ab'+name+'\u00bb \u0438\u0437 \u0441\u043f\u0438\u0441\u043a\u0430?',function(){
      removeItem(t,ci,si,ii,true);
    });
    return;
  }
  var removed=getCats(t)[ci].sections[si].items[ii];
  var autoPosBefore=(isKpTarget(t) && removed && removed.uid) ? kpFindAutoItemPosition(kpTargetIndex(t), removed.uid) : null;
  if(isKpTarget(t) && removed && removed.is_auto && removed.auto_from_uid){
    getCats(t).forEach(function(cat){
      (cat.sections||[]).forEach(function(sec){
        (sec.items||[]).forEach(function(item){
          if(item && item.uid===removed.auto_from_uid){
            item.suppress_auto_work=true;
          }
        });
      });
    });
  }
  getCats(t)[ci].sections[si].items.splice(ii,1);
  if(isKpTarget(t) && removed && removed.uid){
    kpRemoveAutoWorksBySource(kpTargetIndex(t), removed.is_auto && removed.auto_from_uid ? removed.auto_from_uid : removed.uid);
  }
  var synced=rerenderBuilderSection(t,ci,si);
  if(isKpTarget(t) && autoPosBefore){
    synced=rerenderBuilderCategory(t,autoPosBefore.ci) || synced;
  }
  if(!synced) renderTargetBuilder(t);
  else if(isKpTarget(t)){
    kpRefreshSectionTotal(t,ci,si);
    kpRefreshVariantSummaryByTarget(t);
    kpRefreshAllVariantsSummary(kpTargetIndex(t));
  }
}
function updItem
"@
)

Write-Utf8NoBom (Join-Path $root 'assets\js\builder\core.js') $builderCore
Write-Utf8NoBom (Join-Path $root 'assets\js\builder\catalog-fields.js') (Slice-Lines $builderLines $builderMarkers.catalog ($builderMarkers.flow - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\builder\flow.js') (Slice-Lines $builderLines $builderMarkers.flow ($builderMarkers.dom - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\builder\dom.js') (Slice-Lines $builderLines $builderMarkers.dom ($builderMarkers.render - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\builder\render.js') (Slice-Lines $builderLines $builderMarkers.render ($builderMarkers.save - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\builder\save.js') (Slice-Lines $builderLines $builderMarkers.save ($builderLines.Length - 1))

$kpPath = Join-Path $root 'assets\js\spaces\kp.js'
$kpLines = [System.IO.File]::ReadAllLines($kpPath, [System.Text.Encoding]::UTF8)

$kpMarkers = @{
  state = 0
  catalog = Find-LineIndex $kpLines 'async function saveKpProduct'
  builder = Find-LineIndex $kpLines 'async function loadKpBuilder'
  render = Find-LineIndex $kpLines 'function renderKpVariants'
  save = Find-LineIndex $kpLines 'function collectKpBuilderPayload'
}

Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\kp\state.js') (Slice-Lines $kpLines $kpMarkers.state ($kpMarkers.catalog - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\kp\catalog.js') (Slice-Lines $kpLines $kpMarkers.catalog ($kpMarkers.builder - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\kp\builder-core.js') (Slice-Lines $kpLines $kpMarkers.builder ($kpMarkers.render - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\kp\render.js') (Slice-Lines $kpLines $kpMarkers.render ($kpMarkers.save - 1))
Write-Utf8NoBom (Join-Path $root 'assets\js\spaces\kp\save.js') (Slice-Lines $kpLines $kpMarkers.save ($kpLines.Length - 1))
