async function saveDocument(){
  if(!accessCanUi('orders','create')){toast('Нет прав','err');return;}
  var addr=document.getElementById('doc-addr').value.trim();
  var orderType=document.getElementById('doc-type').value;
  var clientType=document.getElementById('doc-num').value.trim();
  if(!addr){toast('Введите адрес','err');return;}
  if(!orderType){toast('Выберите тип объекта','err');return;}
  if(!clientType){toast('Введите тип клиента','err');return;}
  var items=collectItems(docCats);
  if(!items.length){toast('Нет товаров с количеством','err');return;}
  try{
    var r=await api('orders.php',{action:'save_order',address:addr,order_type:orderType,client_type:clientType,items:items,snapshot:docCats});
    toast('Заявка №'+r.order_number+' сохранена ✓');
    clearOrderBuilderDraft('create',0);
    docCats=[];
    document.getElementById('doc-addr').value='';
    document.getElementById('doc-type').value='';
    document.getElementById('doc-num').value='';
    renderDocBuilder();
    initializeOrderBuilderDraftTracking('create');
    await showPage('orders');
  }catch(e){toast(e.message,'err');}
}

// ===================== PRINT =====================
function getDocMeta(t){
  if(t==='oe'){
    return {addr:document.getElementById('oe-addr').value,mgr:document.getElementById('oe-mgr').value,num:document.getElementById('oe-num').value,type:document.getElementById('oe-type').value,clientType:document.getElementById('oe-client-type').value};
  }
  return {addr:document.getElementById('doc-addr').value,mgr:CU.full_name,num:document.getElementById('doc-num').value,type:document.getElementById('doc-type').value,clientType:''};
}
// PRINT COLUMN WIDTHS — fixed for all sections/categories to avoid misaligned separators
var PRINT_COL_WIDTHS_BASE = 'style="width:30px",' +   // #
  'style="width:220px",' +  // name
  'style="width:120px",' +  // marking/komplekt
  'style="width:120px",' +  // note
  'style="width:55px",' +   // qty
  'style="width:45px",' +   // unit
  'style="width:130px"';    // supplier

function buildPrintRows(cat,sec,filterSup,filterShip,isOE){
  var rows='',n=1,isCons=cat.catCode==='consumables';
  var MONTAGE_STATUSES_P=['Монтаж','Монтаж завершён','Выполнено'];
  var curStatusP=document.getElementById('oe-status')?document.getElementById('oe-status').value:'';
  var canHighlightP=MONTAGE_STATUSES_P.indexOf(curStatusP)>=0;
  sec.items.forEach(function(it){
    if(filterSup&&it.supplier!==filterSup) return;
    if(filterShip&&it.shipment_status!==filterShip) return;
    if(!it.nameTxt&&!it.quantity) return;
    var newRow=isOE&&it.dozakaz==1&&canHighlightP?'background:#fffbea;':'';
    rows+='<tr style="'+newRow+'">'+
      '<td>'+n+'</td>'+
      (isCons?'<td>'+esc(it.group_name||'—')+'</td>':'')+
      '<td>'+esc(it.nameTxt||'—')+'</td>'+ 
      '<td>'+esc(it.marking_size||'—')+'</td>'+ 
      (isCons?'<td>'+esc(it.komplektaciya||'—')+'</td>':'<td>'+esc(it.quantity||'—')+'</td>')+
      '<td>'+esc(it.unit||'—')+'</td>'+ 
      '<td>'+esc(it.supplier||'—')+'</td>'+ 
      (isOE&&!isCons?'<td style="color:'+(it.invoice_check==='Ошибка'?'#dc2626':it.invoice_check==='Проверено'?'#16a34a':'#555')+'">'+esc(it.invoice_check||'—')+'</td>':'')+ 
      (isOE&&!isCons?'<td>'+esc(it.shipment_status||'—')+'</td>':'')+
      '</tr>';n++;
  });
  return rows;
}
function buildPrintTbl(cat,rows,isOE){
  var isCons=cat.catCode==='consumables';
  // Fixed col widths so all sections/categories align identically
  var colgroup=isCons
    ? '<colgroup><col style="width:30px"><col style="width:130px"><col style="width:190px"><col style="width:120px"><col style="width:150px"><col style="width:55px"><col style="width:130px">'
    : '<colgroup><col style="width:30px"><col style="width:220px"><col style="width:120px"><col style="width:55px"><col style="width:45px"><col style="width:130px">';
  if(isOE&&!isCons) colgroup+='<col style="width:90px"><col style="width:90px">';
  colgroup+='</colgroup>';
  return '<table border="1" cellpadding="5" style="width:100%;border-collapse:collapse;margin-bottom:14px;table-layout:fixed">'+
    colgroup+
    '<thead><tr style="background:#f3f4f6"><th>#</th>'+ 
    (isCons?'<th>Группа</th>':'')+'<th>Название</th>'+ 
    '<th>Марк./Размер</th>'+ 
    (isCons?'<th>Комплектация</th>':'<th>Кол-во</th>')+'<th>Ед.</th><th>Поставщик</th>'+ 
    (isOE&&!isCons?'<th>Пров.счёта</th><th>Статус отгр.</th>':'')+
    '</tr></thead>'+rows+'</table>';
}
function makePDoc(title,body,meta){
  return '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>'+esc(title)+'</title>'+
    '<style>body{font-family:Arial,sans-serif;padding:20px;font-size:12px}h1{font-size:15px;margin-bottom:7px}'+
    '.inf{background:#f9f9f9;padding:9px;border-radius:4px;margin-bottom:12px}h3{font-size:12px;color:#333;margin:14px 0 4px}'+
    'table{font-size:11px;word-break:break-word}td,th{vertical-align:top;padding:5px 6px}'+
    '@media print{h3{page-break-inside:avoid}table{page-break-inside:auto}tr{page-break-inside:avoid}}</style></head><body>'+
    '<h1>'+esc(title)+'</h1><div class="inf"><strong>Адрес:</strong> '+(esc(meta.addr)||'—')+
    ' | <strong>Менеджер:</strong> '+esc(meta.mgr)+' | <strong>Новая комплектация №:</strong> '+esc(meta.num)+
    (meta.type?' | <strong>Тип объекта:</strong> '+esc(meta.type):'')+
    ' | <strong>Дата:</strong> '+fmtDate(new Date().toISOString())+'</div>'+body+'</body></html>';
}
function doPrint(html){var w=window.open('','_blank');w.document.write(html);w.document.close();w.print();}

function printCat(t,ci){
  var cat=getCats(t)[ci], meta=getDocMeta(t), body='';
  cat.sections.forEach(function(sec){var rows=buildPrintRows(cat,sec,oeFilterSup,oeFilterShip,t==='oe');if(rows)body+='<h3>'+esc(sec.secName)+'</h3>'+buildPrintTbl(cat,rows,t==='oe');});
  if(!body){toast('Нет данных','err');return;}
  doPrint(makePDoc(cat.catName,body,meta));
}
function printSec(t,ci,si){
  var cat=getCats(t)[ci],sec=cat.sections[si],meta=getDocMeta(t);
  var rows=buildPrintRows(cat,sec,oeFilterSup,oeFilterShip,t==='oe');if(!rows){toast('Нет данных','err');return;}
  doPrint(makePDoc(cat.catName+' — '+sec.secName,buildPrintTbl(cat,rows,t==='oe'),meta));
}
function printFullDoc(){
  if(!docCats.length){toast('Документ пуст','err');return;}
  var meta=getDocMeta('doc'),body='';
  docCats.forEach(function(cat){cat.sections.forEach(function(sec){var rows=buildPrintRows(cat,sec,'','',false);if(rows)body+='<h3>'+esc(cat.catName)+' → '+esc(sec.secName)+'</h3>'+buildPrintTbl(cat,rows,false);});});
  if(!body){toast('Нет данных','err');return;}
  doPrint(makePDoc('Новая комплектация №'+meta.num,body,meta));
}
function printOrderDoc(){
  var meta=getDocMeta('oe'),body='';
  oeCats.forEach(function(cat){cat.sections.forEach(function(sec){var rows=buildPrintRows(cat,sec,oeFilterSup,oeFilterShip,true);if(rows)body+='<h3>'+esc(cat.catName)+' → '+esc(sec.secName)+'</h3>'+buildPrintTbl(cat,rows,true);});});
  if(!body){toast('Нет данных','err');return;}
  doPrint(makePDoc('Новая комплектация №'+meta.num,body,meta));
}


async function exportToTelegram(){
  var meta = getDocMeta('oe');

  // Строим HTML-документ в том же виде, что и страницы для печати
  var body = '';
  oeCats.forEach(function(cat){
    cat.sections.forEach(function(sec){
      var rows = buildPrintRows(cat, sec, oeFilterSup, oeFilterShip, true);
      if (rows) body += '<h3>' + esc(cat.catName) + ' → ' + esc(sec.secName) + '</h3>' + buildPrintTbl(cat, rows, true);
    });
  });

  if (!body) { toast('Нет данных для отправки', 'err'); return; }

  var orderNum = meta.num || '—';
  var caption  = 'Новая комплектация №' + orderNum + ' | ' + (meta.addr || '—') + ' | ' + fmtDate(new Date().toISOString());
  var filename = 'order_' + orderNum.replace(/[^a-zа-яё0-9_\-]/gi, '_') + '.pdf';
  var html     = makePDoc('Новая комплектация №' + orderNum, body, meta);

  // Строим fallback-текст на случай, если PDF недоступен
  var lines = [];
  lines.push('📦 Новая комплектация №' + orderNum);
  lines.push(' Адрес: ' + (meta.addr || '—'));
  lines.push(' Менеджер: ' + (meta.mgr || '—'));
  if (meta.type) lines.push('🏗️ Тип объекта: ' + esc(meta.type));
  lines.push('📅 ' + fmtDate(new Date().toISOString()));
  lines.push('');
  oeCats.forEach(function(cat){
    lines.push('--------------------');
    lines.push('📁 ' + cat.catName);
    cat.sections.forEach(function(sec){
      var items = sec.items.filter(function(it){ return it.nameTxt || it.quantity; });
      if (!items.length) return;
      lines.push('  📂 ' + sec.secName);
      items.forEach(function(it, idx){
        var row = '    ' + (idx + 1) + '. ' + (it.nameTxt || '—');
        if (it.marking_size)    row += ' | ' + it.marking_size;
        if (it.quantity)        row += ' | ' + it.quantity + ' ' + (it.unit || getDefaultUnit());
        if (it.supplier)        row += ' | ' + it.supplier;
        if (it.invoice_check)   row += ' | ' + it.invoice_check;
        if (it.shipment_status) row += ' | ' + it.shipment_status;
        if (it.dozakaz == 1)    row += ' ⭐';
        lines.push(row);
      });
    });
    lines.push('');
  });
  var fallbackText = lines.join('\n');

  // Показываем индикатор загрузки на кнопке
  var btn = document.querySelector('[onclick="exportToTelegram()"]');
  var origHtml = btn ? btn.innerHTML : '';
  if (btn) { btn.innerHTML = '⏳ Отправка...'; btn.disabled = true; }

  try {
    var r = await api('telegram.php', { html: html, caption: caption, filename: filename });
    if (r.mode === 'pdf') {
      toast('Новая комплектация отправлена в Telegram (PDF) ✓');
    } else {
      toast('Новая комплектация отправлена в Telegram (HTML-файл) ✓');
    }
  } catch(e) {
    toast('Ошибка отправки: ' + (e.message || e), 'err');
  } finally {
    if (btn) { btn.innerHTML = origHtml; btn.disabled = false; }
  }
}

// ===================== EMAIL =====================
function exportToEmail(){
  document.getElementById('email-to').value=(CU&&CU.email)?CU.email:'';
  om('m-email');
}

async function doSendEmail(){
  var emailTo=document.getElementById('email-to').value.trim();
  if(!emailTo||emailTo.indexOf('@')<0){toast('Введите корректный email','err');return;}

  var meta = getDocMeta('oe');
  var body = '';
  oeCats.forEach(function(cat){
    cat.sections.forEach(function(sec){
      var rows = buildPrintRows(cat, sec, oeFilterSup, oeFilterShip, true);
      if (rows) body += '<h3>' + esc(cat.catName) + ' → ' + esc(sec.secName) + '</h3>' + buildPrintTbl(cat, rows, true);
    });
  });

  if (!body) { toast('Нет данных для отправки', 'err'); return; }

  var orderNum = meta.num || '—';
  var subject  = 'Новая комплектация №' + orderNum + ' | ' + (meta.addr || '—');
  var filename = 'order_' + orderNum.replace(/[^a-zа-яё0-9_\-]/gi, '_') + '.pdf';
  var html     = makePDoc('Новая комплектация №' + orderNum, body, meta);

  cm('m-email');
  var btn = document.querySelector('[onclick="exportToEmail()"]');
  var origHtml = btn ? btn.innerHTML : '';
  if (btn) { btn.innerHTML = '⏳ Отправка...'; btn.disabled = true; }

  try {
    var r = await api('email.php', { html: html, subject: subject, filename: filename, to: emailTo });
    toast('Письмо отправлено на ' + emailTo + ' ✓');
  } catch(e) {
    toast('Ошибка отправки: ' + (e.message || e), 'err');
  } finally {
    if (btn) { btn.innerHTML = origHtml; btn.disabled = false; }
  }
}

