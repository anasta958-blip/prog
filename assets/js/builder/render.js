function buildSecHTML(t,cat,ci,sec,si){
  var isCons=cat.catCode==='consumables';
  var isOE=(t==='oe');
  var isKP=isKpTarget(t);
  var noteLabel='Примечание';
  var hasGroupColumn=!builderIsWorkCategoryCode(cat.catCode);
  var rows='';

  for(var ii=0;ii<(sec.items||[]).length;ii++){
    var it=sec.items[ii];
    if(isOE&&(oeFilterSup||oeFilterShip)){
      var sup2=oeFilterSup?it.supplier===oeFilterSup:true;
      var ship2=oeFilterShip?it.shipment_status===oeFilterShip:true;
      if(!sup2||!ship2) continue;
    }
    var key='ac-'+t+'-'+ci+'-'+si+'-'+ii;
    var mskey='acms-'+t+'-'+ci+'-'+si+'-'+ii;
    var rowKey=isKP?kpDomKey(t,ci,si,ii):'';
    var rowSelectId=isKP?('kp-row-check-'+rowKey):builderRowSelectId(t,ci,si,ii);
    var MONTAGE_STATUSES=['Монтаж','Монтаж завершён','Выполнено'];
    var curOeStatus=document.getElementById('oe-status')?document.getElementById('oe-status').value:'';
    var highlightNew=isOE&&it.dozakaz==1&&MONTAGE_STATUSES.indexOf(curOeStatus)>=0;
    var highlightManualWork=isKP && builderIsWorkCategoryCode(cat.catCode) && !it.is_auto;
    var highlightCatalogPending=isKP && kpIsPendingCatalogItem(it);
    var highlightExternalTouched=(isKP||isOE) && !!(it.external_touched||it.rop_external_touched);
    var rowCls=(highlightNew||highlightManualWork)?'row-dozakaz':'';
    if(highlightCatalogPending) rowCls+=(rowCls?' ':'')+'row-catalog-pending';
    if(highlightExternalTouched && !highlightCatalogPending) rowCls+=(rowCls?' ':'')+'row-external-touched';
    if(isKP && it.excluded_from_calc) rowCls+=(rowCls?' ':'')+'row-excluded';
    rows+='<tr class="'+rowCls+'" ondragover="builderItemDragOver(event,\''+t+'\','+ci+','+si+','+ii+')" ondragleave="builderItemDragLeave(event)" ondrop="builderItemDrop(event,\''+t+'\','+ci+','+si+','+ii+')">';
    var price=isKP?kpGetProductFinalPrice(it):0;
    var sum=isKP?kpGetProductSum(it):0;
    rows+='<td class="builder-row-drag-cell" style="width:24px"><button type="button" class="builder-row-drag-handle" draggable="true" title="Перетащить строку" ondragstart="builderItemDragStart(event,\''+t+'\','+ci+','+si+','+ii+')" ondragend="builderItemDragEnd(event)">||</button></td>';
    rows+='<td class="kp-row-check" style="width:24px"><input type="checkbox" id="'+rowSelectId+'" onchange="builderSyncSectionSelectionState(\''+t+'\','+ci+','+si+')"></td>';
    rows+='<td style="text-align:center;color:var(--tx3);width:26px">'+(ii+1)+'</td>';
    if(hasGroupColumn) rows+='<td style="width:140px">'+mkGroupSel(t,ci,si,ii,it.group_name||'')+'</td>';
    rows+='<td style="min-width:150px"><div class="ac-wrap">'+
      '<input class="ac-inp" id="'+key+'-inp" value="'+esc(it.nameTxt||'')+'" placeholder="Наименование" '+
      'oninput="'+(isKP?'updKpItem':'acNameInput')+'(\''+t+'\','+ci+','+si+','+ii+','+(isKP?'\'nameTxt\',':'')+'this.value)'+(isKP?';showNameDrop(\''+t+'\','+ci+','+si+','+ii+',this.value)':'')+'" onfocus="acNameFocus(\''+t+'\','+ci+','+si+','+ii+')" onkeydown="return builderFlowHandleNameKeydown(event,\''+t+'\','+ci+','+si+','+ii+')" '+(isKP?'data-builder-flow="1" ':'')+'autocomplete="off">'+
      '<div class="ac-drop" id="'+key+'-drop"></div></div></td>';
    rows+='<td style="min-width:120px"><div class="ac-wrap">'+
      '<input class="ac-inp" id="'+mskey+'-inp" value="'+esc(it.marking_size||'')+'" placeholder="Марк./Размер" '+
      'oninput="'+(isKP?'kpHandleBuilderManualCatalogField(\''+t+'\','+ci+','+si+','+ii+',\'marking_size\',this.value);showMsDrop(\''+t+'\','+ci+','+si+','+ii+',this.value)':'acMsInput(\''+t+'\','+ci+','+si+','+ii+',this.value)')+'" onchange="syncItemCatalogData(\''+t+'\','+ci+','+si+','+ii+')" onfocus="acMsFocus(\''+t+'\','+ci+','+si+','+ii+')" onkeydown="return builderFlowHandleMarkingKeydown(event,\''+t+'\','+ci+','+si+','+ii+')" '+(isKP?'data-builder-flow="1" ':'')+'autocomplete="off">'+
      '<div class="ac-drop" id="'+mskey+'-drop">'+
      (it.markingSizeOptions&&it.markingSizeOptions.length?it.markingSizeOptions.map(function(o){return '<div class="ac-item" onclick="applyBuilderMarkingOption(\''+t+'\','+ci+','+si+','+ii+','+JSON.stringify(String(o))+')">' + esc(o) + '</div>';}).join(''):'')+
      '</div></div></td>';
    if(isCons){
      var kkkey='ackk-'+t+'-'+ci+'-'+si+'-'+ii;
      rows+='<td style="min-width:140px"><div class="ac-wrap"><input class="ac-inp" id="'+kkkey+'-inp" value="'+esc(it.komplektaciya||'')+'" placeholder="Комплектация" oninput="acKkInput(\''+t+'\','+ci+','+si+','+ii+',this.value)" onfocus="acKkFocus(\''+t+'\','+ci+','+si+','+ii+')" autocomplete="off"><div class="ac-drop" id="'+kkkey+'-drop"></div></div></td>';
    }else{
      rows+='<td><input '+(isKP?'id="kp-note-'+rowKey+'" ':'')+'type="text" value="'+esc(it.note||'')+'" placeholder="'+noteLabel+'" onchange="'+(isKP?'updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'note\',this.value)':'updItem(\''+t+'\','+ci+','+si+','+ii+',\'note\',this.value)')+'"></td>';
      rows+='<td style="width:70px"><input id="'+(isKP?'kp-qty-'+rowKey:'qty-'+t+'-'+ci+'-'+si+'-'+ii)+'" type="number" value="'+esc((it.quantity===undefined||it.quantity===null||it.quantity==='')?1:it.quantity)+'" placeholder="0" min="0" step="1" oninput="kpNonNegativeInput(this);if(this.value!==\'\'){'+(isKP?'updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'quantity\',this.value)':'updItem(\''+t+'\','+ci+','+si+','+ii+',\'quantity\',this.value)')+'}" onchange="builderValidateQuantityField(\''+t+'\','+ci+','+si+','+ii+')" onblur="builderValidateQuantityField(\''+t+'\','+ci+','+si+','+ii+')" onkeydown="return builderFlowHandleQtyKeydown(event,\''+t+'\','+ci+','+si+','+ii+')" ></td>';
    }
    rows+='<td style="width:78px">'+mkUnitSel(t,ci,si,ii,it.unit).replace('<select ','<select id="'+(isKP?'kp-unit-'+rowKey:'unit-'+t+'-'+ci+'-'+si+'-'+ii)+'" '+(!isKP?'onkeydown="return builderFlowHandleUnitKeydown(event,\''+t+'\','+ci+','+si+','+ii+')" ':'') )+'</td>';
    if(isKP){
      rows+='<td style="min-width:130px">'+(builderIsWorkCategoryCode(cat.catCode)?'<input type="text" value="">':mkSupSel(t,ci,si,ii,it.supplier).replace('<select ','<select id="kp-supplier-'+rowKey+'" '))+'</td>';
      rows+='<td style="width:92px"><input id="kp-purchase-'+rowKey+'" type="number" min="0" step="1" value="'+esc((parseFloat(it.purchase_price||0)||0).toFixed(0))+'" '+(highlightCatalogPending?'':'disabled ')+'oninput="kpNonNegativeInput(this);updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'purchase_price\',this.value)" onchange="updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'purchase_price\',this.value)"></td>';
      rows+='<td style="width:84px"><div class="kp-pct-input"><input id="kp-markup-'+rowKey+'" type="number" step="1" value="'+esc(it.markup_value||0)+'" oninput="updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'markup_value\',this.value)" onchange="updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'markup_value\',this.value)"><span>%</span></div></td>';
      rows+='<td style="width:92px"><input id="kp-price-'+rowKey+'" type="number" min="0" step="1" value="'+esc(price.toFixed(0))+'" oninput="kpNonNegativeInput(this);kpPreviewTargetItemFinalPrice(\''+t+'\','+ci+','+si+','+ii+',this.value)" onchange="kpSetTargetItemFinalPrice(\''+t+'\','+ci+','+si+','+ii+',this.value)" onblur="kpSetTargetItemFinalPrice(\''+t+'\','+ci+','+si+','+ii+',this.value)"></td>';
      rows+='<td style="width:84px"><div class="kp-pct-input"><input id="kp-discount-'+rowKey+'" type="number" min="0" step="1" value="'+esc(it.discount_value||0)+'" oninput="kpNonNegativeInput(this);updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'discount_value\',this.value)" onchange="updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'discount_value\',this.value)"><span>%</span></div></td>';
      rows+='<td style="width:92px"><input id="kp-sum-'+rowKey+'" type="text" value="'+esc(sum.toFixed(0))+'" disabled></td>';
      rows+='<td class="kp-exclude-cell" style="width:66px"><label class="kp-exclude-toggle"><input type="checkbox" '+(it.excluded_from_calc?'checked ':'')+'onchange="updKpItem(\''+t+'\','+ci+','+si+','+ii+',\'excluded_from_calc\',this.checked)">не считать</label></td>';
    }else{
      rows+='<td style="min-width:130px">'+mkSupSel(t,ci,si,ii,it.supplier).replace('<select ','<select id="sup-'+t+'-'+ci+'-'+si+'-'+ii+'" ')+'</td>';
    }
    if(isOE && !isCons){
      rows+='<td style="width:110px">'+mkInvSel(t,ci,si,ii,it.invoice_check||'')+'</td>';
      rows+='<td style="width:110px">'+mkEnumSel(['','Купить','На складе','Заказано','На объекте'],t,ci,si,ii,'shipment_status',it.shipment_status||'')+'</td>';
    }
    rows+='<td style="width:36px"><button class="btn btn-rd btn-xs" onclick="removeItem(\''+t+'\','+ci+','+si+','+ii+')">🗑</button></td>';
    rows+='</tr>';
  }

  var h='<div class="secblk" data-sec-id="'+esc(String(sec.secId||''))+'" data-sec-code="'+esc(String(sec.secCode||''))+'">';
  h+='<div class="secblk-h"><div style="display:flex;align-items:center;gap:8px;min-width:0;flex-wrap:wrap"><div class="secblk-t">📂 '+esc(sec.secName)+'</div><button class="btn btn-g btn-sm" onclick="addFromList(\''+t+'\','+ci+','+si+')">'+(builderIsWorkCategoryCode(cat.catCode)?'＋ Работа':'➕ Товар')+'</button>';
  if(isKP) h+='<div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap"><span class="kp-cat-bulk-label">Наценка</span><div class="kp-bulk-input"><input class="finp" id="'+kpBulkFieldId(t,ci,si,'markup_value')+'" type="number" step="1" value="" placeholder="0"><span>%</span></div><button class="btn btn-g btn-xs" onclick="kpApplyBulkFieldToSection(\''+t+'\','+ci+','+si+',\'markup_value\')">Применить</button><span class="kp-cat-bulk-label">Скидка</span><div class="kp-bulk-input"><input class="finp" id="'+kpBulkFieldId(t,ci,si,'discount_value')+'" type="number" min="0" step="1" value="" placeholder="0"><span>%</span></div><button class="btn btn-g btn-xs" onclick="kpApplyBulkFieldToSection(\''+t+'\','+ci+','+si+',\'discount_value\')">Применить</button></div>';
  h+='</div>';
  h+='<div style="display:flex;align-items:center;gap:7px;margin-left:auto"><button class="btn btn-rd btn-xs" onclick="removeSelectedItems(\''+t+'\','+ci+','+si+')">Удалить выбранные</button><button class="btn btn-rd btn-xs" onclick="removeSec(\''+t+'\','+ci+','+si+')">✕</button>';
  h+='</div></div>';

  if(rows){
    h+='<div style="padding:8px 10px 0;overflow-x:auto"><table class="itbl" style="table-layout:fixed"><colgroup>';
    h+='<col style="width:24px">';
    h+='<col style="width:24px">';
    h+='<col style="width:26px">';
    if(hasGroupColumn) h+='<col style="width:140px">';
    h+='<col style="width:150px"><col style="width:120px">';
    h+=isCons?'<col style="width:140px"><col style="width:78px">':'<col style="width:100px"><col style="width:70px"><col style="width:78px">';
    if(isKP) h+='<col style="width:130px"><col style="width:92px"><col style="width:84px"><col style="width:92px"><col style="width:84px"><col style="width:92px"><col style="width:96px">';
    else h+='<col style="width:130px">';
    if(isOE && !isCons) h+='<col style="width:110px"><col style="width:110px">';
    h+='<col style="width:36px"></colgroup>';
    h+='<thead><tr>';
    h+='<th style="width:24px"></th>';
    h+='<th class="kp-row-check" style="width:24px"><input type="checkbox" id="'+(isKP?kpSectionSelectAllId(t,ci,si):builderSectionSelectAllId(t,ci,si))+'" onchange="builderToggleSectionSelection(\''+t+'\','+ci+','+si+',this.checked)"></th>';
    h+='<th style="width:26px">#</th>';
    if(hasGroupColumn) h+='<th>Группа</th>';
    h+='<th>Наименование</th>';
    h+='<th>Марк./Размер</th>';
    h+=isCons?'<th>Комплектация</th><th>Ед.</th>':'<th>'+noteLabel+'</th><th>Кол-во</th><th>Ед.</th>';
    if(isKP) h+='<th>Поставщик</th><th>Закупка</th><th>Наценка</th><th>Цена</th><th>Скидка</th><th>Сумма</th><th>Не считать</th>';
    else h+='<th>Поставщик</th>';
    if(isOE && !isCons) h+='<th>Пров.счёта</th><th>Статус отгр.</th>';
    h+='<th></th></tr></thead>';
    h+='<tbody>'+rows+'</tbody></table></div>';
  }else{
    h+='<div style="padding:12px 14px;color:var(--tx3);font-size:.8rem">Добавьте товар.</div>';
  }
  h+='</div>';
  return h;
}

function buildCatsHTML(t,cats){
  var h='';
  for(var ci=0;ci<cats.length;ci++){
    var cat=cats[ci];
    var catTotals=isKpTarget(t)?kpGetCategoryTotals(cat):null;
    h+='<div class="catblk fi2" data-cat-code="'+esc(String(cat.catCode||''))+'"><div class="catblk-h">';
    h+='<div style="display:flex;align-items:center;gap:8px;min-width:0;flex-wrap:wrap"><div class="catblk-t">📁 '+esc(cat.catName)+'</div><button class="btn btn-g btn-sm" onclick="_addSecModal(\''+t+'\','+ci+')">➕ Раздел</button>';
    h+='</div>';
    h+='<div style="display:flex;align-items:center;gap:7px;margin-left:auto"><button class="btn btn-rd btn-sm" onclick="removeCat(\''+t+'\','+ci+')">✕</button>';
    h+='</div></div>';
    h+='<div style="padding:6px 0 12px">';
    if(builderIsWorkCategoryCode(cat.catCode) && typeof kpSortSections==='function') kpSortSections(cat);
    for(var si=0;si<cat.sections.length;si++) h+=buildSecHTML(t,cat,ci,cat.sections[si],si);
    if(isKpTarget(t)){
      h+='<div class="kp-summary" style="margin:10px 14px 0"><div class="ctitle" style="margin-bottom:10px">Сводка категории</div><div class="kp-summary-row">'+
      '<div><div class="mlb">Итог закупка</div><div class="mvl" id="kp-category-purchase-'+esc(kpDomKey(t,ci,'summary','purchase'))+'">'+esc(catTotals.purchase.toFixed(0))+' ₽</div></div>'+
      '<div><div class="mlb">Итог розница</div><div class="mvl" id="kp-category-retail-'+esc(kpDomKey(t,ci,'summary','retail'))+'">'+esc(catTotals.retail.toFixed(0))+' ₽</div></div>'+
      '<div><div class="mlb">Маржа</div><div class="mvl" id="kp-category-margin-'+esc(kpDomKey(t,ci,'summary','margin'))+'">'+(catTotals.margin_percent!=null?esc(catTotals.margin_percent.toFixed(0))+'%':'—')+'</div></div>'+
      '</div></div>';
    }
    h+='</div></div>';
  }
  return h;
}

function renderDocBuilder(){document.getElementById('doc-builder').innerHTML=buildCatsHTML('doc',docCats);}
function renderOEBuilder(){
  var wrap=document.getElementById('oe-docbuilder');
  if(!wrap) return;
  wrap.innerHTML=buildCatsHTML('oe',oeCats);
}

function syncOrdersAccessUi(){
  var canCreate=accessCanUi('orders','create');
  var canEdit=accessCanUi('orders','edit');
  var canDelete=accessCanUi('orders','delete');
  var docSaveBtn=document.querySelector('#page-doc .btn.btn-gr[onclick="saveDocument()"]');
  if(docSaveBtn) docSaveBtn.style.display=canCreate?'':'none';
  var docAddCatBtn=document.getElementById('doc-add-cat-btn');
  if(docAddCatBtn) docAddCatBtn.style.display=canCreate?'':'none';
  var oeSaveBtn=document.getElementById('oe-save-btn');
  if(oeSaveBtn) oeSaveBtn.style.display=canEdit?'':'none';
  var oeAddCatBtn=document.getElementById('oe-add-cat-btn');
  if(oeAddCatBtn) oeAddCatBtn.style.display=canEdit?'':'none';
  var oeDeleteBtn=document.getElementById('oe-delete-btn');
  if(oeDeleteBtn) oeDeleteBtn.style.display=canDelete?'':'none';
}

// ===================== TYPE CHANGE =====================
async function docTypeChange(){
  // Object type change no longer auto-generates order number
  // order number is assigned on save
}

// ===================== COLLECT ITEMS =====================
function collectItems(cats){
  var items=[];
  for(var ci=0;ci<cats.length;ci++){
    var cat=cats[ci];
    for(var si=0;si<cat.sections.length;si++){
      var sec=cat.sections[si];
      for(var ii=0;ii<sec.items.length;ii++){
        var it=sec.items[ii];
        if(!it.quantity&&!it.nameTxt) continue;
        items.push({
          category_id:cat.catId, section_id:sec.secId, group_name:it.group_name||'',
          product_name_id:it.nameId||null, custom_name:it.nameTxt||null, name_txt:it.nameTxt||null,
          marking:it.marking_size, size_value:it.marking_size,
          marking_size:it.marking_size, quantity:it.quantity, dozakaz:it.dozakaz||0,
          unit:it.unit, note:it.note, supplier:it.supplier, komplektaciya:it.komplektaciya||'',
          invoice_check:it.invoice_check||'', shipment_status:it.shipment_status||''
        });
      }
    }
  }
  return items;
}

// ===================== SAVE DOCUMENT =====================
