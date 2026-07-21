function collectKpBuilderPayload(){
  ensureKpVariants();
  var proposalTypes=(kpBuilder.proposal_types||[]).map(function(type, ti){
    var variants=Array.isArray(type.variants)&&type.variants.length ? type.variants : [kpEmptyVariant(0)];
    return {
      id:type.id||('ptype-'+ti),
      label:(type.label||kpProposalTypeDefaultLabel(ti)).trim(),
      selected_variant_id:type.selected_variant_id||'',
      variants:variants.map(function(v, vi){
        var cats=v.cats||kpItemsToCats(v.items||[]);
        var items=kpCatsToItems(cats);
        var percentBase=0;
        items.forEach(function(item){
          if(!(typeof kpIsPercentIncidentalItem==='function' && kpIsPercentIncidentalItem(item))){
            percentBase+=kpGetProductSum(item);
          }
        });
        return {
          id:v.id||('var-'+vi),
          label:v.label||'',
          vat_mode:v.vat_mode||'none',
          snapshot:cats,
          items:items.map(function(item){
            return {
              product_name_id:item.product_name_id||0,
              category_id:item.category_id||0,
              category_code:item.category_code||'',
              category_name:item.category_name||'',
              catalog_status:item.catalog_status||item.status||'',
              section_id:item.section_id||0,
              section_name:item.section_name||'',
              group_name:item.group_name||'',
               item_type:item.item_type||'product',
               uid:item.uid||'',
               external_touched:!!(item.external_touched||item.rop_external_touched),
               service_id:item.service_id||0,
              name:item.name||'',
              marking_size:item.marking_size||'',
              unit:item.unit||'',
              supplier:item.supplier||'',
              note:item.note||'',
              quantity:parseFloat(item.quantity||0),
              base_price:item.base_price,
              price_type:item.price_type==='percent'?'percent':'fixed',
              markup_value:item.markup_value||0,
              discount_value:item.discount_value||0,
              final_price:kpGetProductFinalPrice(item),
              line_sum:kpGetProductSum(item, percentBase),
              purchase_price:item.purchase_price,
              retail_price:item.retail_price,
              minimal_price:item.minimal_price,
              linked_service_id:item.linked_service_id||0,
              linked_service_name:item.linked_service_name||'',
              linked_service_cost:item.linked_service_cost||0,
              linked_services:Array.isArray(item.linked_services)?item.linked_services.slice():[],
              linked_service_purchase_price:item.linked_service_purchase_price!=null?item.linked_service_purchase_price:null,
              linked_service_unit:item.linked_service_unit||'',
              suppress_auto_work:!!item.suppress_auto_work
            };
          })
        };
      })
    };
  });
  return {
    additional_info:document.getElementById('kp-quote-additional').value.trim(),
    vat_mode:(kpBuilder.variants[0]&&kpBuilder.variants[0].vat_mode)||'none',
    selection_mode:typeof kpGetClientSelectionMode==='function' ? kpGetClientSelectionMode() : 'variant',
    selected_type_id:(kpBuilder.payload&&kpBuilder.payload.selected_type_id)||'',
    quote_meta:getKpQuoteMeta(),
    proposal_types:proposalTypes
  };
}

function kpPreviewMoney(v){
  if(v===null || v===undefined || v==='') return '\u2014';
  return String(Math.round(parseFloat(v)||0)).replace(/\B(?=(\d{3})+(?!\d))/g,' ')+' \u20BD';
}
function kpPreviewPercent(v){
  return String(Math.round(parseFloat(v)||0))+'%';
}
function kpPreviewVariantTone(label){
  var key=String(label||'').trim().toLowerCase();
  if(key.indexOf('\u0431\u044e\u0434\u0436')===0) return 'tone-budget';
  if(key.indexOf('\u043e\u043f\u0442\u0438\u043c')===0) return 'tone-optimal';
  if(key.indexOf('\u043f\u0440\u0435\u043c')===0 || key.indexOf('\u043f\u0440\u0438\u043c')===0) return 'tone-premium';
  return '';
}
function kpGetPreviewChosenMap(payload){
  var map={};
  kpGetPayloadProposalTypes(payload).forEach(function(type){
    if(type && type.selected_variant_id){
      map[String(type.id||'')]=String(type.selected_variant_id||'');
    }
  });
  return map;
}
function kpBuildPreviewQuoteState(){
  var title=(document.getElementById('kp-quote-title')||{}).value||'';
  var payload=collectKpBuilderPayload();
  var company=getKpCompanySnapshotForQuote();
  var companyEl=document.getElementById('kp-quote-client-company');
  var recipientEl=document.getElementById('kp-quote-recipient');
  var client={
    company_name:(companyEl&&companyEl.value)||((kpBuilder.client_snapshot&&kpBuilder.client_snapshot.company_name)||''),
    recipient_name:(recipientEl&&recipientEl.value)||((kpBuilder.client_snapshot&&kpBuilder.client_snapshot.recipient_name)||''),
    company_type:(kpBuilder.client_snapshot&&kpBuilder.client_snapshot.company_type)||'ooo'
  };
  return {
    title:title.trim()||getDefaultProposalTitle(),
    status:'created',
    company:company||{},
    client:client,
    payload:payload,
    chosenMap:kpGetPreviewChosenMap(payload)
  };
}
function kpPreviewCompanyFieldLabel(key, company){
  var type=String((company&&company.company_type)||'ooo');
  var map={
    company_type:'\u0422\u0438\u043f \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438',
    company_name:'\u041a\u043e\u043c\u043f\u0430\u043d\u0438\u044f',
    legal_name:(type==='ip' ? '\u0424\u0418\u041e \u0418\u041f' : '\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435 \u043d\u0430\u0437\u0432\u0430\u043d\u0438\u0435'),
    inn:'\u0418\u041d\u041d',
    ogrn:(type==='ip' ? '\u041e\u0413\u0420\u041d\u0418\u041f' : '\u041e\u0413\u0420\u041d'),
    kpp:'\u041a\u041f\u041f',
    address:'\u0410\u0434\u0440\u0435\u0441',
    phone:'\u0422\u0435\u043b\u0435\u0444\u043e\u043d',
    email:'Email',
    website:'\u0421\u0430\u0439\u0442',
    director_name:'\u0414\u0438\u0440\u0435\u043a\u0442\u043e\u0440',
    signatory_name:'\u041f\u043e\u0434\u043f\u0438\u0441\u0430\u043d\u0442',
    signatory_title:'\u0414\u043e\u043b\u0436\u043d\u043e\u0441\u0442\u044c \u043f\u043e\u0434\u043f\u0438\u0441\u0430\u043d\u0442\u0430',
    bank_name:'\u0411\u0430\u043d\u043a',
    bank_bik:'\u0411\u0418\u041a',
    bank_account:'\u0420\u0430\u0441\u0447\u0451\u0442\u043d\u044b\u0439 \u0441\u0447\u0451\u0442',
    corr_account:'\u041a\u043e\u0440\u0440. \u0441\u0447\u0451\u0442'
  };
  return map[key]||key;
}
function kpPreviewCompanyMetaHtml(company){
  var order=['company_type','company_name','legal_name','inn','ogrn','kpp','address','phone','email','website','director_name','signatory_name','signatory_title','bank_name','bank_bik','bank_account','corr_account'];
  var rows=[];
  order.forEach(function(key){
    if(!company || !Object.prototype.hasOwnProperty.call(company,key)) return;
    var value=String(company[key]||'').trim();
    if(!value) return;
    rows.push('<div class="meta-line"><strong>'+esc(kpPreviewCompanyFieldLabel(key, company))+'</strong>'+esc(key==='company_type' ? value.toUpperCase() : value).replace(/\n/g,'<br>')+'</div>');
  });
  return rows.length ? rows.join('') : '<div class="meta-line">&mdash;</div>';
}
function kpRenderPreviewVariant(variant, chosen){
  var groups={};
  var variantItems=variant.items||[];
  var percentBase=0;
  variantItems.forEach(function(item){
    if(!(typeof kpIsPercentIncidentalItem==='function' && kpIsPercentIncidentalItem(item))){
      percentBase+=kpGetProductSum(item);
    }
  });
  variantItems.forEach(function(item){
    var code=String(item.category_code||((item.item_type||'')==='work'?'work':'equipment'));
    if(!groups[code]) groups[code]=[];
    groups[code].push(item);
  });
  var order=['equipment','materials','work','construction_works','incidental_expenses','maintenance'];
  var tables='';
  order.forEach(function(code){
    var items=groups[code]||[];
    if(!items.length) return;
    var rows='', sum=0;
    items.forEach(function(item){
      var isPercentLine=typeof kpIsPercentIncidentalItem==='function' && kpIsPercentIncidentalItem(item);
      var line=(!isPercentLine && item.line_sum!==undefined && item.line_sum!==null && item.line_sum!=='') ? parseFloat(item.line_sum||0) : kpGetProductSum(item, percentBase);
      var price=(item.final_price!==undefined && item.final_price!==null && item.final_price!=='') ? parseFloat(item.final_price||0) : kpGetProductFinalPrice(item);
      sum+=line;
      rows+='<tr>'+
        '<td>'+esc(item.name||'')+'</td>'+
        '<td>'+esc(item.marking_size||'\u2014')+'</td>'+
        '<td>'+esc(item.quantity||'\u2014')+'</td>'+
        '<td>'+esc(item.unit||'\u2014')+'</td>'+
        '<td>'+kpPreviewPercent(item.discount_value||0)+'</td>'+
        '<td>'+kpPreviewMoney(price)+'</td>'+
        '<td>'+kpPreviewMoney(line)+'</td>'+
      '</tr>';
    });
    tables+='<div class="group">'+
      '<div class="group-head"><h4>'+esc(kpBuilderCategoryLabel(code))+'</h4><span>'+kpPreviewMoney(sum)+'</span></div>'+
      '<table class="quote-items-table"><colgroup><col style="width:39%"><col style="width:19%"><col style="width:7%"><col style="width:7%"><col style="width:8%"><col style="width:10%"><col style="width:10%"></colgroup><thead><tr><th>\u041d\u0430\u0438\u043c\u0435\u043d\u043e\u0432\u0430\u043d\u0438\u0435</th><th>\u041c\u0430\u0440\u043a\u0438\u0440\u043e\u0432\u043a\u0430 / \u0440\u0430\u0437\u043c\u0435\u0440</th><th>\u041a\u043e\u043b-\u0432\u043e</th><th>\u0415\u0434. \u0438\u0437\u043c.</th><th>\u0421\u043a\u0438\u0434\u043a\u0430</th><th>\u0426\u0435\u043d\u0430</th><th>\u0421\u0443\u043c\u043c\u0430</th></tr></thead><tbody>'+
      rows+
      '</tbody><tfoot><tr><td colspan="6">\u0418\u0442\u043e\u0433\u043e</td><td>'+kpPreviewMoney(sum)+'</td></tr></tfoot></table>'+
    '</div>';
  });
  var totals=kpGetVariantTotals(variant);
  var label=String(variant.label||'').trim()||'\u0412\u0430\u0440\u0438\u0430\u043d\u0442';
  var isChosen=!!chosen;
  var tone=kpPreviewVariantTone(label);
  return '<section class="variant'+(isChosen?' chosen '+tone:'')+'" data-label="'+esc(label)+'">'+
    '<div class="variant-head"><div><h3>'+esc(label)+'</h3></div>'+
    (isChosen?'<button class="pick picked" type="button" disabled>\u0412\u044b\u0431\u0440\u0430\u043d\u043d\u044b\u0439 \u0432\u0430\u0440\u0438\u0430\u043d\u0442</button>':'<button class="pick" type="button" disabled>\u0412\u044b\u0431\u0440\u0430\u0442\u044c \u0432\u0430\u0440\u0438\u0430\u043d\u0442</button>')+
    '</div>'+
    tables+
    '<div class="group"><div class="group-head"><h4>\u0421\u0432\u043e\u0434\u043a\u0430 \u0432\u0430\u0440\u0438\u0430\u043d\u0442\u0430</h4><span>'+(totals.vat_rate ? esc(String(totals.vat_rate))+'%' : '\u0411\u0435\u0437 \u041d\u0414\u0421')+'</span></div>'+
    '<table><tbody>'+
    '<tr><td>\u0418\u0442\u043e\u0433\u043e</td><td>'+kpPreviewMoney(totals.total)+'</td></tr>'+
    '<tr><td>\u0421\u0443\u043c\u043c\u0430 \u041d\u0414\u0421</td><td>'+kpPreviewMoney(totals.vat_sum)+'</td></tr>'+
    '<tr><td>\u0421\u0443\u043c\u043c\u0430 \u0441 \u041d\u0414\u0421</td><td>'+kpPreviewMoney(totals.total_with_vat)+'</td></tr>'+
    '</tbody></table></div>'+
  '</section>';
}
function kpRenderPreviewProposalType(type, chosenMap, selectionMode, selectedTypeId){
  selectionMode=String(selectionMode||'')==='type'?'type':'variant';
  selectedTypeId=String(selectedTypeId||'').trim();
  var chosenId=String((chosenMap&&chosenMap[String(type.id||'')])||type.selected_variant_id||'').trim();
  var variants=(type&&Array.isArray(type.variants))?type.variants:[];
  var typeTotals=typeof kpGetProposalTypeTotals==='function' ? kpGetProposalTypeTotals(type) : null;
  var typeChosen=selectionMode==='type' && selectedTypeId!=='' && String(type.id||'')===selectedTypeId;
  var typeButton='';
  if(selectionMode==='type'){
    typeButton=typeChosen
      ? '<button class="pick picked" type="button" disabled>Выбранный тип</button>'
      : '<button class="pick" type="button" disabled>Выбрать тип</button>';
  }
  var typeSummary=typeTotals ? '<div class="group type-summary"><div class="group-head"><h4>Сводка типа</h4><span>'+kpPreviewMoney(typeTotals.total)+'</span></div>'+
    '<table><tbody>'+
    '<tr><td>Вариантов</td><td>'+esc(String(typeTotals.variants_count||0))+'</td></tr>'+
    '<tr><td>Позиций</td><td>'+esc(String(typeTotals.items_count||0))+'</td></tr>'+
    '<tr><td>Итого</td><td>'+kpPreviewMoney(typeTotals.total)+'</td></tr>'+
    '<tr><td>Сумма НДС</td><td>'+kpPreviewMoney(typeTotals.vat_sum)+'</td></tr>'+
    '<tr><td>Сумма с НДС</td><td>'+kpPreviewMoney(typeTotals.total_with_vat)+'</td></tr>'+
    '</tbody></table></div>' : '';
  return '<section class="card footer-card'+(typeChosen?' variant chosen':'')+'"><div class="variant-head"><div><h3>'+esc(type.label||'Тип предложения')+'</h3></div>'+typeButton+'</div><div class="variants">'+variants.map(function(variant){
    return kpRenderPreviewVariant(variant, typeChosen || (selectionMode==='variant' && chosenId!=='' && String(variant.id||'')===chosenId));
  }).join('')+'</div>'+typeSummary+'</section>';
}
function kpGetPrintProposalTypes(payload){
  var types=kpGetPayloadProposalTypes(payload);
  if(!types.length) return [];
  var typeIndex=parseInt(kpBuilder.active_type_index,10);
  if(!isFinite(typeIndex)) typeIndex=0;
  typeIndex=Math.max(0, Math.min(typeIndex, types.length-1));
  var type=types[typeIndex]||types[0];
  var variants=Array.isArray(type.variants) ? type.variants : [];
  if(!variants.length) return [type];
  var variantIndex=parseInt(kpBuilder.active_variant_index,10);
  if(!isFinite(variantIndex)) variantIndex=0;
  variantIndex=Math.max(0, Math.min(variantIndex, variants.length-1));
  var variant=variants[variantIndex]||variants[0];
  return [Object.assign({}, type, {
    selected_variant_id:String(variant.id||''),
    variants:[variant]
  })];
}
function kpBuildQuoteDocumentHtml(mode){
  var autoPrint=mode==='print';
  var state=kpBuildPreviewQuoteState();
  var statusLabel='\u0421\u043e\u0437\u0434\u0430\u043d\u043e';
  var proposalTypes=autoPrint ? kpGetPrintProposalTypes(state.payload) : kpGetPayloadProposalTypes(state.payload);
  var selectionMode=String((state.payload&&state.payload.selection_mode)||(state.payload&&state.payload.client_selection_mode)||'')==='type'?'type':'variant';
  var selectedTypeId=String((state.payload&&state.payload.selected_type_id)||'').trim();
  var variantsHtml=proposalTypes.map(function(type){
    return kpRenderPreviewProposalType(type, state.chosenMap, selectionMode, selectedTypeId);
  }).join('');
  return '<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">'+
    '<title>'+esc(state.title)+'</title>'+
    '<style>'+
    ':root{--bg:#f4efe7;--card:#fffdf9;--bd:#e5d7c6;--tx:#1f2937;--tx2:#6b7280;--ac:#0f766e;--ac2:#115e59;--mut:#f7f0e6}'+
    '*{box-sizing:border-box}body{margin:0;font-family:Geologica,Arial,sans-serif;background:linear-gradient(180deg,#f7f1e8 0%,#efe7db 100%);color:var(--tx)}'+
    '.wrap{max-width:1240px;margin:0 auto;padding:32px 18px 60px}.hero,.card,.variant,.group{background:var(--card);border:1px solid var(--bd);border-radius:24px}'+
    '.hero{padding:28px}.muted{color:var(--tx2)}.status{display:inline-flex;align-items:center;padding:6px 12px;border-radius:999px;background:var(--mut);font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}'+
    'h1{margin:14px 0 8px;font-size:clamp(1.8rem,4vw,2.8rem);line-height:1.05}.hero-lead{font-size:1rem;color:var(--tx2);margin:0}.grid{display:grid;grid-template-columns:1.1fr .9fr;gap:18px;margin-top:20px}'+
    '.card{padding:20px}.card h3{margin:0 0 10px;font-size:1rem}.meta{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px 16px}.meta-line strong{display:block;font-size:.78rem;text-transform:uppercase;letter-spacing:.06em;color:var(--tx2);margin-bottom:2px}'+
    '.proposal-text{margin-top:14px;white-space:pre-wrap;line-height:1.55}.variants{display:grid;gap:18px;margin-top:22px}.variant{padding:20px}.variant.chosen{border-width:2px;box-shadow:0 10px 28px rgba(15,23,42,.08)}'+
    '.variant.chosen.tone-budget{border-color:#22c55e;background:linear-gradient(180deg,rgba(34,197,94,.12),rgba(255,253,249,1) 30%)}'+
    '.variant.chosen.tone-optimal{border-color:#f59e0b;background:linear-gradient(180deg,rgba(245,158,11,.14),rgba(255,253,249,1) 30%)}'+
    '.variant.chosen.tone-premium{border-color:#3b82f6;background:linear-gradient(180deg,rgba(59,130,246,.14),rgba(255,253,249,1) 30%)}'+
    '.variant-head{display:flex;justify-content:space-between;gap:18px;align-items:flex-start;margin-bottom:18px}.variant-head h3{margin:0;font-size:1.2rem}.pick{border:none;background:linear-gradient(135deg,var(--ac),var(--ac2));color:#fff;padding:12px 18px;border-radius:16px;font-weight:700;cursor:default}.pick.picked{background:#d1fae5;color:#065f46}'+
    '.group{padding:18px;margin-top:14px}.type-summary{border-color:#bfdbfe;background:#eff6ff}.group-head{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-bottom:12px}.group-head h4{margin:0;font-size:1rem}'+
    'table{width:100%;border-collapse:collapse;font-size:.95rem}th,td{padding:10px 8px;border-bottom:1px solid #efe4d7;text-align:left;vertical-align:top}th{font-size:.78rem;text-transform:uppercase;letter-spacing:.06em;color:var(--tx2)}tfoot td{font-weight:700;border-bottom:none}'+
    '.quote-items-table{table-layout:fixed}.quote-items-table th,.quote-items-table td{overflow-wrap:anywhere;word-break:break-word}.quote-items-table th:nth-child(3),.quote-items-table td:nth-child(3),.quote-items-table th:nth-child(4),.quote-items-table td:nth-child(4),.quote-items-table th:nth-child(5),.quote-items-table td:nth-child(5),.quote-items-table th:nth-child(6),.quote-items-table td:nth-child(6),.quote-items-table th:nth-child(7),.quote-items-table td:nth-child(7),.quote-items-table tfoot td:last-child{white-space:nowrap;overflow-wrap:normal;word-break:normal}'+
    '.footer-card{margin-top:22px}@media (max-width:860px){.grid,.variant-head{grid-template-columns:1fr;display:grid}.meta{grid-template-columns:1fr}.variant-head{gap:12px}table{display:block;overflow:auto;white-space:nowrap}}'+
    '.quote-print{background:#fff;color:#111;font-family:Arial,"Helvetica Neue",sans-serif}.quote-print .wrap{max-width:none;width:100%;margin:0;padding:0}.quote-print .hero,.quote-print .card,.quote-print .variant,.quote-print .group{background:#fff;border:1px solid #b8b8b8;border-radius:0;box-shadow:none}.quote-print .hero{padding:0 0 12px;border:none;border-bottom:2px solid #111}.quote-print .status{display:none}.quote-print h1{margin:0 0 8px;font-size:20pt;line-height:1.18;color:#111}.quote-print .hero-lead{margin:0;color:#111;font-size:11pt}.quote-print .grid{display:grid;grid-template-columns:1fr 1fr;gap:10mm;margin-top:10mm}.quote-print .card{padding:8px}.quote-print .card h3,.quote-print .variant-head h3,.quote-print .group-head h4{color:#111}.quote-print .meta{display:grid;grid-template-columns:1fr 1fr;gap:5px 12px}.quote-print .meta-line{font-size:9.5pt;line-height:1.35;color:#111}.quote-print .meta-line strong{font-size:7.5pt;color:#444;letter-spacing:.03em}.quote-print .variants{display:block;margin-top:10mm}.quote-print .variant{padding:0;border:none;margin:0 0 10mm}.quote-print .variant-head{display:block;margin:0 0 6px;padding-bottom:5px;border-bottom:1px solid #111}.quote-print .pick{display:none}.quote-print .group{padding:0;border:none;margin:6mm 0 0}.quote-print .type-summary{border-top:1px solid #111;border-bottom:1px solid #111;padding:4px 0}.quote-print .group-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-end;margin:0 0 5px;border-bottom:1px solid #666;padding-bottom:3px}.quote-print .group-head h4{margin:0;font-size:11pt}.quote-print .group-head span{font-size:10pt;font-weight:700;color:#111}.quote-print table{width:100%;border-collapse:collapse;table-layout:fixed;font-size:8.8pt;line-height:1.25;color:#111}.quote-print thead{display:table-header-group}.quote-print tfoot{display:table-row-group}.quote-print tr{break-inside:avoid;page-break-inside:avoid}.quote-print th,.quote-print td{border:1px solid #9f9f9f;padding:4px 5px;text-align:left;vertical-align:top;color:#111;background:#fff;overflow-wrap:anywhere;word-break:normal}.quote-print th{font-size:7.4pt;font-weight:700;text-transform:none;letter-spacing:0}.quote-print tfoot td{font-weight:700;background:#fff}.quote-print .proposal-text{font-size:10pt;line-height:1.45;color:#111}.quote-print .footer-card{margin-top:8mm;break-inside:auto;page-break-inside:auto}'+
    '@page{size:A4;margin:14mm}'+
    '@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}html,body{width:auto;min-width:0;background:#fff!important;color:#111!important}.wrap{max-width:none!important;width:100%!important;margin:0!important;padding:0!important}.hero,.card,.variant,.group{background:#fff!important;color:#111!important;box-shadow:none!important;border-color:#b8b8b8!important;border-radius:0!important}.hero,.card{break-inside:avoid;page-break-inside:avoid}.variant,.group,table{break-inside:auto;page-break-inside:auto}.hero{padding:0 0 12px!important;border:none!important;border-bottom:2px solid #111!important}.status,.pick{display:none!important}.group-head,.variant-head{break-after:avoid;page-break-after:avoid;color:#111!important}.variant.chosen,.variant.chosen.tone-budget,.variant.chosen.tone-optimal,.variant.chosen.tone-premium{border-color:#111!important;background:#fff!important}.grid{grid-template-columns:1fr 1fr!important;gap:10mm!important}.variants{display:block!important;margin-top:10mm!important}.variant{padding:0!important;border:none!important;margin:0 0 10mm!important}.group{padding:0!important;border:none!important;margin:6mm 0 0!important}table{display:table!important;width:100%!important;border-collapse:collapse!important;table-layout:fixed!important;font-size:8.5pt!important;line-height:1.25!important;white-space:normal!important;color:#111!important}thead{display:table-header-group!important}tfoot{display:table-row-group!important}tr{break-inside:avoid;page-break-inside:avoid}th,td{border:1px solid #9f9f9f!important;padding:3.5px 4px!important;color:#111!important;background:#fff!important;overflow-wrap:anywhere!important;word-break:normal!important;white-space:normal!important}th{font-size:7.4pt!important;font-weight:700!important;text-transform:none!important;letter-spacing:0!important}.quote-items-table th:nth-child(3),.quote-items-table td:nth-child(3),.quote-items-table th:nth-child(4),.quote-items-table td:nth-child(4),.quote-items-table th:nth-child(5),.quote-items-table td:nth-child(5),.quote-items-table th:nth-child(6),.quote-items-table td:nth-child(6),.quote-items-table th:nth-child(7),.quote-items-table td:nth-child(7),.quote-items-table tfoot td:last-child{white-space:normal!important;overflow-wrap:anywhere!important}}'+
    '</style></head><body class="'+(autoPrint?'quote-print':'quote-preview')+'"><div class="wrap">'+
    '<div class="hero">'+
      '<div class="status">'+esc(statusLabel)+'</div>'+
      '<h1>'+esc((state.payload.quote_meta&&state.payload.quote_meta.proposal_title)||getDefaultProposalTitle())+'</h1>'+
      '<p class="hero-lead">'+esc(state.client.recipient_name||'')+'</p>'+
      '<div class="grid">'+
        '<div class="card"><h3>\u041e \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438</h3><div class="meta">'+kpPreviewCompanyMetaHtml(state.company)+'</div></div>'+
        '<div class="card"><h3>\u041a\u043b\u0438\u0435\u043d\u0442</h3><div class="meta">'+
          '<div class="meta-line"><strong>\u041a\u043e\u043c\u043f\u0430\u043d\u0438\u044f</strong>'+esc(state.client.company_name||'\u2014')+'</div>'+
          '<div class="meta-line"><strong>\u041f\u043e\u043b\u0443\u0447\u0430\u0442\u0435\u043b\u044c</strong>'+esc(state.client.recipient_name||'\u2014')+'</div>'+
        '</div></div>'+
      '</div>'+
    '</div>'+
    '<div class="variants">'+variantsHtml+'</div>'+
    (state.payload.additional_info?'<div class="card footer-card"><h3>\u0414\u043e\u043f\u043e\u043b\u043d\u0438\u0442\u0435\u043b\u044c\u043d\u0430\u044f \u0438\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f</h3><div class="proposal-text">'+esc(state.payload.additional_info).replace(/\n/g,'<br>')+'</div></div>':'')+
    '</div>'+
    (autoPrint?'<script>window.addEventListener("load",function(){setTimeout(function(){window.print();},120);});<\/script>':'')+
    '</body></html>';
}
function kpBuildPreviewQuoteHtml(){
  return kpBuildQuoteDocumentHtml('preview');
}
function kpBuildPrintQuoteHtml(){
  return kpBuildQuoteDocumentHtml('print');
}
function openKpQuotePreviewWindow(autoPrint){
  var html=autoPrint ? kpBuildPrintQuoteHtml() : kpBuildPreviewQuoteHtml();
  var w=window.open('','_blank');
  if(!w){toast('\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u0442\u043a\u0440\u044b\u0442\u044c \u043e\u043a\u043d\u043e','err');return;}
  w.document.write(html);
  w.document.close();
}
function previewKpQuoteDoc(){
  openKpQuotePreviewWindow(false);
}
function printKpQuoteDoc(){
  kpTogglePrintMenu();
}

function printKpQuoteDefault(){
  kpClosePrintMenu();
  openKpQuotePreviewWindow(true);
}

function kpClosePrintMenu(){
  var menu=document.getElementById('kp-builder-print-menu');
  if(menu) menu.style.display='none';
}

async function kpEnsureDocumentsPrintRuntime(){
  if(typeof documentsBuildExportHtml==='function' && typeof documentsNormalizeState==='function') return;
  if(typeof loadAppScripts!=='function') throw new Error('Не удалось загрузить модуль документов');
  await loadAppScripts(['assets/js/spaces/documents.js']);
}

function kpBuildDocumentPrintQuoteDetail(){
  var payload=collectKpBuilderPayload();
  var companySnapshot=typeof getKpCompanySnapshotForQuote==='function' ? getKpCompanySnapshotForQuote() : {};
  return {
    id:kpBuilder.id||0,
    title:kpBuilder.title||((document.getElementById('kp-quote-title')||{}).value||''),
    status:kpBuilder.status||'created',
    workflow_status:kpBuilder.workflow_status||getDefaultQuoteWorkflowStatus(),
    selected_variant_label:kpBuilder.selected_variant_label||'',
    company_snapshot:companySnapshot||{},
    client_snapshot:kpBuilder.client_snapshot||{},
    payload:payload,
    created_at:kpBuilder.created_at||new Date().toISOString()
  };
}

async function kpLoadDocumentPrintTemplates(){
  var mode=kpNormalizeQuoteMode(quoteWorkspaceMode||'kp');
  var response=await api('documents.php?action=list&document_type='+encodeURIComponent(mode)+'&limit=150');
  return apiItems(response);
}

async function kpTogglePrintMenu(){
  var menu=document.getElementById('kp-builder-print-menu');
  if(!menu){
    printKpQuoteDefault();
    return;
  }
  if(menu.style.display==='block'){
    menu.style.display='none';
    return;
  }
  menu.style.display='block';
  menu.innerHTML='<button type="button" onclick="printKpQuoteDefault()">Обычная печать</button><div class="kp-print-menu-note">Загрузка шаблонов...</div>';
  try{
    await kpEnsureDocumentsPrintRuntime();
    var templates=await kpLoadDocumentPrintTemplates();
    var html='<button type="button" onclick="printKpQuoteDefault()">Обычная печать</button>';
    if(templates.length){
      html+='<div class="kp-print-menu-title">Шаблоны документов</div>'+templates.map(function(row){
        var name=row.title||('Шаблон #'+row.id);
        if(row.current_version_name) name+=' · '+row.current_version_name;
        return '<button type="button" onclick="kpPrintQuoteWithDocumentTemplate('+parseInt(row.id||0,10)+')">'+esc(name)+'</button>';
      }).join('');
    }else{
      html+='<div class="kp-print-menu-note">Нет шаблонов для '+(quoteWorkspaceMode==='pkp'?'ПКП':'КП')+'</div>';
    }
    menu.innerHTML=html;
  }catch(e){
    menu.innerHTML='<button type="button" onclick="printKpQuoteDefault()">Обычная печать</button><div class="kp-print-menu-note error">'+esc(e.message||'Ошибка загрузки шаблонов')+'</div>';
  }
}

async function kpPrintQuoteWithDocumentTemplate(templateId){
  templateId=parseInt(templateId||0,10)||0;
  if(!templateId) return;
  kpClosePrintMenu();
  try{
    await kpEnsureDocumentsPrintRuntime();
    if(typeof documentsLoadCompanies==='function') await documentsLoadCompanies();
    if(typeof documentsLoadClients==='function') await documentsLoadClients();
    var row=await api('documents.php?action=detail&id='+templateId);
    var prevState=documentsState;
    var prevSource=documentsSourceQuoteDetail;
    try{
      documentsState=documentsNormalizeState(row.payload||documentsDefaultState());
      documentsState.id=parseInt(row.id||0,10)||0;
      documentsState.document_type=kpNormalizeQuoteMode(quoteWorkspaceMode||'kp');
      documentsState.source_quote_id=kpBuilder.id?String(kpBuilder.id):'';
      if(row.page_format) documentsState.page_format=String(row.page_format);
      documentsSourceQuoteDetail=kpBuildDocumentPrintQuoteDetail();
      documentsEnsureVariantSelection();
      documentsPrint({flow:true});
    }finally{
      documentsState=prevState;
      documentsSourceQuoteDetail=prevSource;
    }
  }catch(e){
    toast(e.message||'Не удалось напечатать по шаблону','err');
  }
}
function kpValidatePendingCatalogItems(){
  ensureKpVariants();
  for(var ti=0;ti<(kpBuilder.proposal_types||[]).length;ti++){
    kpBuilder.active_type_index=ti;
    kpSyncBuilderActiveTypeVariants(kpBuilder);
    for(var vi=0;vi<kpBuilder.variants.length;vi++){
      var cats=kpEnsureVariantCats(vi);
      for(var ci=0;ci<cats.length;ci++){
        for(var si=0;si<(cats[ci].sections||[]).length;si++){
          for(var ii=0;ii<(cats[ci].sections[si].items||[]).length;ii++){
            var item=cats[ci].sections[si].items[ii];
            if(!kpIsPendingCatalogItem(item)) continue;
            if((parseFloat(item.purchase_price||0)||0)<=0){
              toast('Укажите закупочную цену для новой позиции вне каталога','err');
              return false;
            }
          }
        }
      }
    }
  }
  kpSyncBuilderActiveTypeVariants(kpBuilder);
  return true;
}

function kpPayloadHasFilledItems(payload){
  return kpGetPayloadProposalTypes(payload).some(function(type){
    return (type.variants||[]).some(function(variant){
      var items=variant && Array.isArray(variant.items) ? variant.items : [];
      return items.some(function(item){
        return !!String((item && item.name) || '').trim();
      });
    });
  });
}

var kpSaveInFlight=false;

function kpBuildSaveSignature(payloadOverride, metaOverride){
  var payload=payloadOverride||collectKpBuilderPayload();
  var meta=metaOverride||{};
  return JSON.stringify({
    title:meta.title||'',
    status:meta.status||'created',
    workflow_status:meta.workflow_status||'',
    selected_variant_label:meta.selected_variant_label||'',
    client_id:String(meta.client_id||''),
    company_snapshot:meta.company_snapshot||{},
    client_snapshot:meta.client_snapshot||{},
    payload:payload||{}
  });
}

function kpBuilderStateFromQuoteResponse(q, payloadLoading){
  q=q||{};
  var payload=(!payloadLoading && q.payload && typeof q.payload==='object') ? q.payload : {};
  if(payloadLoading && q.payload_meta && typeof q.payload_meta==='object'){
    payload.quote_meta=q.payload_meta;
  }
  if(payloadLoading && Object.prototype.hasOwnProperty.call(q,'payload_additional_info')){
    payload.additional_info=String(q.payload_additional_info||'');
  }
  var state=normalizeKpBuilderState({
    id:q.id,
    title:q.title||'',
    status:q.status||'created',
    workflow_status:q.workflow_status||getDefaultQuoteWorkflowStatus(),
    selected_variant_label:q.selected_variant_label||'',
    client_id:q.client_id||'',
    owner_user_id:parseInt(q.user_id||0,10)||0,
    client_snapshot:q.client_snapshot||{},
    payload:payload,
    proposal_types:payload.proposal_types||[],
    variants:payload.variants||[]
  });
  state.__payloadLoading=!!payloadLoading;
  return state;
}

function kpStoreLastSavedSignatureFromQuote(q){
  if(!q || !q.payload) return;
  kpBuilder.__lastSavedSignature=kpBuildSaveSignature(kpBuilder.payload||{},{
    title:kpBuilder.title||'',
    status:kpBuilder.status||'created',
    workflow_status:kpBuilder.workflow_status||getDefaultQuoteWorkflowStatus(),
    selected_variant_label:kpBuilder.selected_variant_label||'',
    client_id:kpBuilder.client_id||'',
    company_snapshot:q.company_snapshot||{},
    client_snapshot:kpBuilder.client_snapshot||{}
  });
  kpInitializeDraftTracking();
}

async function saveKpQuote(){
  if(kpSaveInFlight) return;
  if(kpBuilder && kpBuilder.__payloadLoading){
    toast('\u0414\u043e\u0436\u0434\u0438\u0442\u0435\u0441\u044c \u0437\u0430\u0433\u0440\u0443\u0437\u043a\u0438 \u043f\u043e\u0437\u0438\u0446\u0438\u0439','err');
    return;
  }
  var title=document.getElementById('kp-quote-title').value.trim();
  if(!title){toast('Укажите название КП','err');return;}
  if(typeof commitKpPartyInput==='function' && !commitKpPartyInput('client')){
    toast('Выберите заказчика из списка','err');
    return;
  }
  if(!String((document.getElementById('kp-quote-client')||{}).value||'').trim()){
    toast('Выберите заказчика','err');
    return;
  }
  if(typeof commitKpPartyInput==='function' && !commitKpPartyInput('contractor')){
    toast('Выберите исполнителя из списка','err');
    return;
  }
  if(!String((document.getElementById('kp-quote-contractor')||{}).value||'').trim()){
    toast('Выберите исполнителя','err');
    return;
  }
  if(!kpValidatePendingCatalogItems()) return;
  var payload=collectKpBuilderPayload();
  if(quoteWorkspaceMode!=='pkp' && !kpPayloadHasFilledItems(payload)){
    toast('\u0414\u043e\u0431\u0430\u0432\u044c\u0442\u0435 \u0442\u043e\u0432\u0430\u0440\u044b \u0432 \u041a\u041f','err');
    return;
  }
  kpBuilder.title=title;
  kpBuilder.status=kpBuilder.id ? (kpBuilder.status||'created') : 'created';
  if(!kpBuilder.workflow_status) kpBuilder.workflow_status=getDefaultQuoteWorkflowStatus();
  kpBuilder.client_id=document.getElementById('kp-quote-client').value||'';
  var companyEl=document.getElementById('kp-quote-client-company');
  var recipientEl=document.getElementById('kp-quote-recipient');
  var currentClient=(Array.isArray(kpClients)?kpClients:[]).find(function(x){return String(x.id)===String(kpBuilder.client_id);})||{};
  var previousClient=(kpBuilder.client_snapshot&&typeof kpBuilder.client_snapshot==='object')?kpBuilder.client_snapshot:{};
  kpBuilder.client_snapshot={
    company_type:previousClient.company_type||currentClient.company_type||'ooo',
    company_name:companyEl ? companyEl.value.trim() : (previousClient.company_name||currentClient.company_name||''),
    legal_name:previousClient.legal_name||currentClient.legal_name||'',
    recipient_name:recipientEl ? recipientEl.value.trim() : (previousClient.recipient_name||currentClient.recipient_name||currentClient.legal_name||''),
    inn:previousClient.inn||currentClient.inn||'',
    ogrn:previousClient.ogrn||currentClient.ogrn||'',
    kpp:previousClient.kpp||currentClient.kpp||'',
    object_type:previousClient.object_type||currentClient.object_type||'',
    object_address:previousClient.object_address||currentClient.object_address||'',
    phone:previousClient.phone||currentClient.phone||'',
    email:previousClient.email||currentClient.email||'',
    bank_name:previousClient.bank_name||currentClient.bank_name||'',
    bank_bik:previousClient.bank_bik||currentClient.bank_bik||'',
    note:previousClient.note||currentClient.note||''
  };
  var currentSignature=kpBuildSaveSignature(payload,{
    title:title,
    status:kpBuilder.status,
    workflow_status:kpBuilder.workflow_status,
    selected_variant_label:kpBuilder.selected_variant_label||'',
    client_id:kpBuilder.client_id||'',
    company_snapshot:getKpCompanySnapshotForQuote(),
    client_snapshot:kpBuilder.client_snapshot
  });
  if(parseInt(kpBuilder.id||0,10)>0 && kpBuilder.__lastSavedSignature===currentSignature){
    toast('Нет изменений');
    return;
  }
  var saveBtn=document.getElementById('kp-builder-save-btn');
  var draftEntityId=parseInt(kpBuilder.id||0,10)||0;
  try{
    kpSaveInFlight=true;
    if(saveBtn) saveBtn.disabled=true;
    var res=await api(quoteApiFile(),{
      action:'save_quote',
      id:kpBuilder.id||0,
      client_id:kpBuilder.client_id?parseInt(kpBuilder.client_id,10):0,
      title:title,
      status:kpBuilder.status,
      workflow_status:kpBuilder.workflow_status,
      selected_variant_label:kpBuilder.selected_variant_label||'',
      company_snapshot:getKpCompanySnapshotForQuote(),
      client_snapshot:kpBuilder.client_snapshot,
      payload:payload
    });
    kpBuilder.id=res.id||kpBuilder.id;
    kpBuilder.payload=payload;
    kpBuilder.proposal_types=payload.proposal_types||kpBuilder.proposal_types||[];
    kpBuilder.variants=(kpBuilder.proposal_types[0]&&kpBuilder.proposal_types[0].variants)||kpBuilder.variants||[];
    kpBuilder.__lastSavedSignature=currentSignature;
    kpInitializeDraftTracking();
    clearKpBuilderDraft(quoteWorkspaceMode,draftEntityId);
    if(draftEntityId!==parseInt(kpBuilder.id||0,10)) clearKpBuilderDraft(quoteWorkspaceMode,kpBuilder.id||0);
    toast('КП сохранено ✓');
  }catch(e){toast(e.message,'err');}
  finally{
    kpSaveInFlight=false;
    if(saveBtn) saveBtn.disabled=false;
  }
}

function resetKpBuilder(){
  clearKpBuilderDraft(quoteWorkspaceMode,0);
  kpBuilder=normalizeKpBuilderState({
    id:0,
    title:'',
    status:'created',
    workflow_status:getDefaultQuoteWorkflowStatus(),
    selected_variant_label:'',
    client_id:'',
    owner_user_id:parseInt((CU&&CU.id)||0,10)||0,
    client_snapshot:{},
    proposal_types:[kpEmptyProposalType(0)]
  });
  loadKpBuilder();
  kpInitializeDraftTracking();
}
function rememberKpBoardScrollPosition(){
  if(!kpBoardScrollMemory) return;
  var main=document.querySelector('.main');
  var grid=document.querySelector('#kp-quotes-kanban .kanban-grid');
  kpBoardScrollMemory.mode='quotes-board';
  kpBoardScrollMemory.main=main?main.scrollTop:0;
  kpBoardScrollMemory.grid=grid?grid.scrollLeft:0;
}

function openNewKpQuote(){
  var draft=loadKpBuilderDraft(quoteWorkspaceMode,0);
  if(draft && !parseInt(draft.id||0,10)){
    kpBuilder=draft;
    return showPage('kp-builder');
  }
  resetKpBuilder();
  showPage('kp-builder');
}

function openNewQuoteByMode(mode){
  quoteWorkspaceMode=kpNormalizeQuoteMode(mode);
  updateQuoteWorkspaceUi();
  openNewKpQuote();
}

function backFromKpBuilder(){
  if(kpBoardScrollMemory){
    kpBoardScrollMemory.mode='quotes-board';
    kpBoardScrollMemory.pendingRestore=true;
  }
  openQuoteWorkspace(quoteWorkspaceMode,'list');
}

async function confirmQuoteBoardTransfer(status){
  if(quoteWorkspaceMode==='pkp' && kpCanonicalWorkflowStatus(status, 'pkp')==='ПКП согласовано'){
    return await showConfirmDialog({
      title:'Подтвердить перенос',
      message:'Перенести карточку из ПКП в КП со статусом «Составить КП»?',
      icon:'🔁',
      confirmText:'Перенести',
      confirmClass:'btn-p'
    });
  }
  if(quoteWorkspaceMode!=='pkp' && status==='Закупить материал'){
    return await showConfirmDialog({
      title:'Подтвердить перенос',
      message:'Перенести карточку из КП в Комплектацию?',
      icon:'🔁',
      confirmText:'Перенести',
      confirmClass:'btn-p'
    });
  }
  return true;
}

async function confirmOrderBoardTransfer(status){
  if(status==='Монтаж завершён'){
    return await showConfirmDialog({
      title:'Подтвердить перенос',
      message:'Перенести карточку из Комплектации в КП со статусом «Получить финальную оплату»?',
      icon:'🔁',
      confirmText:'Перенести',
      confirmClass:'btn-p'
    });
  }
  return true;
}

function getKpTransferMetaFromQuote(quote){
  var payload=(quote&&quote.payload&&typeof quote.payload==='object')?quote.payload:{};
  var saved=(payload&&payload.transfer_meta&&typeof payload.transfer_meta==='object')?payload.transfer_meta:{};
  var meta=(payload&&payload.quote_meta&&typeof payload.quote_meta==='object')?payload.quote_meta:{};
  var client=(quote&&quote.client_snapshot&&typeof quote.client_snapshot==='object')?quote.client_snapshot:{};
  var quoteTitle=String((quote&&quote.title)||'').trim();
  return {
    address:(saved.address||meta.object_address||quoteTitle||'Адрес уточняется').trim(),
    manager_id:parseInt(saved.manager_id||meta.manager_id||CU.id||0,10)||0,
    order_type:(saved.order_type||meta.object_type||'Не указан').trim(),
    client_type:(saved.client_type||client.company_name||'').trim()
  };
}

function stopKpQuotesLiveRefresh(){
  if(kpQuotesLiveTimer){
    clearInterval(kpQuotesLiveTimer);
    kpQuotesLiveTimer=0;
  }
}

function startKpQuotesLiveRefresh(){
  stopKpQuotesLiveRefresh();
  kpQuotesLiveTimer=setInterval(function(){
    if(activePage!=='kp-list') return;
    var page=document.getElementById('page-kp-list');
    if(!page || page.style.display==='none') return;
    loadKpQuotes({preserveScroll:true,silent:true,preservePagination:true});
  }, 10000);
}


function kpTransferMetaReady(meta){
  return !!(meta&&meta.address&&meta.order_type&&meta.client_type&&parseInt(meta.manager_id||0,10));
}

async function ensureKpTransferUsers(){
  if(kpTransferUsers.length) return kpTransferUsers;
  var rows=await loadUsersDirectory();
  kpTransferUsers=(rows||[]).map(function(u){
    return {
      id:parseInt(u.id,10)||0,
      full_name:u.full_name||u.username||('Пользователь #'+u.id),
      role:u.role||''
    };
  }).filter(function(u){return u.id;});
  return kpTransferUsers;
}

function fillKpTransferManagerSelect(selectedId){
  var sel=document.getElementById('kpt-manager');
  if(!sel) return;
  sel.innerHTML='<option value="">— выберите менеджера —</option>'+kpTransferUsers.map(function(u){
    var label=u.full_name+(u.role?' · '+(ROLE_LABELS[u.role]||u.role):'');
    return '<option value="'+u.id+'">'+esc(label)+'</option>';
  }).join('');
  sel.value=String(selectedId||'');
  if(!sel.value && kpTransferUsers.length){
    sel.value=String(kpTransferUsers[0].id);
  }
}

async function openKpTransferModal(id){
  var quote=await api(quoteApiFile()+'?action=quote_detail&id='+id);
  await ensureKpTransferUsers();
  var meta=getKpTransferMetaFromQuote(quote);
  document.getElementById('kpt-quote-id').value=id;
  document.getElementById('kpt-address').value=meta.address||'';
  document.getElementById('kpt-order-type').value=meta.order_type||'';
  document.getElementById('kpt-client-type').value=meta.client_type||'';
  fillKpTransferManagerSelect(meta.manager_id||CU.id||0);
  om('m-kp-transfer');
}

async function confirmKpTransferToComplectation(){
  var id=parseInt(document.getElementById('kpt-quote-id').value||'0',10);
  if(quoteWorkspaceMode==='pkp'){
    cm('m-kp-transfer');
    return;
  }
  var transferMeta={
    address:document.getElementById('kpt-address').value.trim(),
    manager_id:parseInt(document.getElementById('kpt-manager').value||'0',10)||0,
    order_type:document.getElementById('kpt-order-type').value,
    client_type:document.getElementById('kpt-client-type').value.trim()
  };
  if(!transferMeta.address) transferMeta.address='Адрес уточняется';
  if(!transferMeta.manager_id){toast('Выберите менеджера','err');return;}
  if(!transferMeta.order_type) transferMeta.order_type='Не указан';
  if(!transferMeta.client_type){toast('Введите тип клиента','err');return;}
  try{
    var res=await api(quoteApiFile(),{action:'set_quote_workflow',id:id,workflow_status:'Закупить материал',transfer_meta:transferMeta});
    cm('m-kp-transfer');
    if(res.order_id){toast('Сделка перенесена в Комплектацию ✓');}
    loadKpQuotes({preserveScroll:true});
  }catch(err){toast(err.message,'err');}
}

var _kpDraggingId=0;
var _kpDraggingMode='kp';
var _kpJustDragged=false;
var _kpDropPlaceholder=null;
var _kpDropTargetCard=null;
var _kpDropTargetSide='';
var _kpDropColumn=null;
function kpDragStart(e,id,mode){_kpDraggingId=id; _kpDraggingMode=kpNormalizeQuoteMode(mode||'kp'); _kpJustDragged=false; e.dataTransfer.setData('text/plain',_kpDraggingMode+'|'+String(id));}
function kpClearDropIndicators(){
  if(_kpDropPlaceholder && _kpDropPlaceholder.parentNode) _kpDropPlaceholder.parentNode.removeChild(_kpDropPlaceholder);
  _kpDropPlaceholder=null;
  if(_kpDropTargetCard){
    _kpDropTargetCard.classList.remove('drop-target-top');
    _kpDropTargetCard.classList.remove('drop-target-bottom');
  }
  _kpDropTargetCard=null;
  _kpDropTargetSide='';
  _kpDropColumn=null;
}
function kpEnsureDropPlaceholder(){
  if(_kpDropPlaceholder) return _kpDropPlaceholder;
  _kpDropPlaceholder=document.createElement('div');
  _kpDropPlaceholder.className='kanban-drop-placeholder';
  return _kpDropPlaceholder;
}
function kpSetDropIndicator(col, target, side){
  var ph=kpEnsureDropPlaceholder();
  if(_kpDropTargetCard && _kpDropTargetCard!==target){
    _kpDropTargetCard.classList.remove('drop-target-top');
    _kpDropTargetCard.classList.remove('drop-target-bottom');
  }
  if(target){
    if(target!==_kpDropTargetCard || side!==_kpDropTargetSide){
      target.classList.remove('drop-target-top');
      target.classList.remove('drop-target-bottom');
      target.classList.add(side==='top' ? 'drop-target-top' : 'drop-target-bottom');
    }
    var anchor=side==='top' ? target : target.nextSibling;
    if(ph.parentNode!==col || ph.nextSibling!==anchor) col.insertBefore(ph, anchor);
  }else{
    if(_kpDropTargetCard){
      _kpDropTargetCard.classList.remove('drop-target-top');
      _kpDropTargetCard.classList.remove('drop-target-bottom');
    }
    if(ph.parentNode!==col || ph!==col.lastChild) col.appendChild(ph);
  }
  _kpDropTargetCard=target||null;
  _kpDropTargetSide=target ? side : '';
  _kpDropColumn=col||null;
}
function kpFindDropTarget(col, dragging, clientY){
  var cards=Array.prototype.filter.call(col.querySelectorAll('.kanban-card[data-kp-id]'), function(card){
    return card!==dragging;
  });
  if(!cards.length) return {target:null, side:''};
  for(var i=0;i<cards.length;i++){
    var card=cards[i];
    var rect=card.getBoundingClientRect();
    var mid=rect.top + rect.height/2;
    if(clientY < mid){
      return {target:card, side:'top'};
    }
  }
  return {target:cards[cards.length-1], side:'bottom'};
}
function kpIsDragPointInsideCol(col, clientX, clientY){
  if(!col) return false;
  if(typeof clientX!=='number' || typeof clientY!=='number') return false;
  var el=document.elementFromPoint(clientX, clientY);
  return !!(el && col.contains(el));
}
function kpGetKanbanOrderValue(q){
  if(q && q.kanban_order!==null && q.kanban_order!==undefined && q.kanban_order!==''){
    var direct=parseInt(q.kanban_order,10);
    if(isFinite(direct)) return direct;
  }
  var payload=(q&&q.payload)||{};
  var parsed=parseInt(payload.kanban_order,10);
  return isFinite(parsed) ? parsed : null;
}
function kpQuoteChangeTime(q){
  function parseChange(meta){
    var value=meta&&meta.changed_at ? Date.parse(String(meta.changed_at).replace(' ','T')) : NaN;
    return isFinite(value) ? value : 0;
  }
  var workflow=parseChange(q&&q.last_workflow_change);
  var card=parseChange(q&&q.last_card_change);
  var explicit=Math.max(workflow, card);
  if(explicit>0) return explicit;
  var updated=Date.parse(String((q&&q.updated_at)||'').replace(' ','T'));
  var created=Date.parse(String((q&&q.created_at)||'').replace(' ','T'));
  return Math.max(isFinite(updated)?updated:0, isFinite(created)?created:0);
}
function kpSortQuotesForKanban(cards){
  return (cards||[]).slice().sort(function(a,b){
    var at=kpQuoteChangeTime(a);
    var bt=kpQuoteChangeTime(b);
    if(at!==bt) return bt-at;
    var ao=kpGetKanbanOrderValue(a), bo=kpGetKanbanOrderValue(b);
    if(ao!==null && bo!==null && ao!==bo) return ao-bo;
    var updatedA=String(a.updated_at||a.created_at||'');
    var updatedB=String(b.updated_at||b.created_at||'');
    if(updatedA!==updatedB) return updatedA>updatedB ? -1 : 1;
    return (parseInt(b.id,10)||0)-(parseInt(a.id,10)||0);
  });
}
async function kpSaveKanbanOrders(status, orderedIds, mode){
  var ids=(orderedIds||[]).map(function(x){return parseInt(x,10)||0;}).filter(Boolean);
  if(!status || !ids.length) return;
  await api(getQuoteApiFileByMode(mode||quoteWorkspaceMode),{action:'set_quote_kanban_orders',workflow_status:status,ordered_ids:ids});
}
function kpReorderQuotesForKanban(mode,status,orderedIds){
  mode=kpNormalizeQuoteMode(mode||'kp');
  if(!orderedIds || !orderedIds.length) return;
  var idSet={};
  orderedIds.forEach(function(x){idSet[String(x)]=true;});
  var movedRows=(kpQuotes||[]).filter(function(q){
    return kpNormalizeQuoteMode(q.quote_mode||'kp')===mode &&
      kpCanonicalWorkflowStatus(q.workflow_status||getDefaultQuoteWorkflowStatus(), mode)===kpCanonicalWorkflowStatus(status, mode) &&
      idSet[String(q.id)];
  });
  var movedMap={};
  movedRows.forEach(function(q){movedMap[String(q.id)]=q;});
  var orderedRows=orderedIds.map(function(x){return movedMap[String(x)]||null;}).filter(Boolean);
  var inserted=false;
  kpQuotes=(kpQuotes||[]).filter(function(q){
    return !(kpNormalizeQuoteMode(q.quote_mode||'kp')===mode && idSet[String(q.id)]);
  }).reduce(function(acc,q){
    var sameColumn=kpNormalizeQuoteMode(q.quote_mode||'kp')===mode &&
      kpCanonicalWorkflowStatus(q.workflow_status||getDefaultQuoteWorkflowStatus(), mode)===kpCanonicalWorkflowStatus(status, mode);
    if(!inserted && sameColumn){
      inserted=true;
      return acc.concat(orderedRows,[q]);
    }
    acc.push(q);
    return acc;
  },[]);
  if(!inserted) kpQuotes=kpQuotes.concat(orderedRows);
}
function kpApplyColumnDomOrder(mode,status,orderedIds){
  mode=kpNormalizeQuoteMode(mode||'kp');
  if(!orderedIds || !orderedIds.length) return false;
  var cols=Array.prototype.slice.call(document.querySelectorAll('.kanban-col[data-kp-mode][data-kp-status]'));
  var col=cols.find(function(node){
    return kpNormalizeQuoteMode(node.getAttribute('data-kp-mode')||'kp')===mode &&
      kpCanonicalWorkflowStatus(node.getAttribute('data-kp-status')||'', mode)===kpCanonicalWorkflowStatus(status, mode);
  });
  var cardsWrap=col ? col.querySelector('.kanban-cards') : null;
  if(!cardsWrap) return false;
  var cards={};
  Array.prototype.slice.call(cardsWrap.querySelectorAll('.kanban-card[data-kp-id][data-kp-mode]')).forEach(function(card){
    if(kpNormalizeQuoteMode(card.getAttribute('data-kp-mode')||'kp')!==mode) return;
    cards[String(card.getAttribute('data-kp-id')||'')]=card;
  });
  var orderedKeySet={};
  var fragment=document.createDocumentFragment();
  orderedIds.forEach(function(id){
    orderedKeySet[String(id)]=true;
    var card=cards[String(id)];
    if(card) fragment.appendChild(card);
  });
  Object.keys(cards).forEach(function(id){
    if(!orderedKeySet[String(id)]) fragment.appendChild(cards[id]);
  });
  cardsWrap.appendChild(fragment);
  return true;
}
function kpDragEnd(){kpClearDropIndicators();setTimeout(function(){_kpJustDragged=true; _kpDraggingId=0; _kpDraggingMode='kp'; setTimeout(function(){_kpJustDragged=false;},120);},0);}
function kpCardClick(e,id,mode){
  if(_kpJustDragged) return;
  if(e && e.target && e.target.closest && e.target.closest('button')) return;
  rememberKpBoardScrollPosition();
  editKpQuote(id, mode);
}
async function updateQuoteWorkflowStatus(id,status,transferMeta){
  if(quoteWorkspaceMode==='pkp'){
    return api(quoteApiFile(),{action:'set_quote_status',id:id,status:'created',workflow_status:status});
  }
  return api(quoteApiFile(),{action:'set_quote_workflow',id:id,workflow_status:status,transfer_meta:transferMeta});
}
async function transferPkpQuoteToKpStatus(id,status,orderedIds){
  var pkpId=parseInt(id,10)||0;
  var targetStatus=String(status||'Составить КП');
  if(!pkpId) throw new Error('Не найдено ПКП для переноса');
  var pkpQuote=await api('pkp.php?action=quote_detail&id='+pkpId);
  var pkpPayload=(pkpQuote && pkpQuote.payload && typeof pkpQuote.payload==='object') ? pkpQuote.payload : {};
  var transferMeta=null;
  if(targetStatus==='Закупить материал'){
    transferMeta=getKpTransferMetaFromQuote(pkpQuote);
    if(!kpTransferMetaReady(transferMeta)){
      throw new Error('Для переноса в комплектацию сначала заполните данные сделки');
    }
  }
  var transferRes=await api('pkp.php',{action:'transfer_to_kp',id:pkpId});
  var kpQuoteId=parseInt((transferRes&&transferRes.kp_quote_id)||pkpPayload.created_kp_quote_id||0,10)||0;
  if(!kpQuoteId){
    var refreshedPkpQuote=await api('pkp.php?action=quote_detail&id='+pkpId);
    var refreshedPayload=(refreshedPkpQuote && refreshedPkpQuote.payload && typeof refreshedPkpQuote.payload==='object') ? refreshedPkpQuote.payload : {};
    kpQuoteId=parseInt(refreshedPayload.created_kp_quote_id||0,10)||0;
  }
  if(!kpQuoteId) throw new Error('Не удалось перенести ПКП в КП');
  await api('pkp.php',{action:'set_quote_archive',id:pkpId,archived:1});
  if(targetStatus!=='Составить КП'){
    await api('kp.php',{
      action:'set_quote_workflow',
      id:kpQuoteId,
      workflow_status:targetStatus,
      transfer_meta:transferMeta||undefined
    });
  }
  var targetOrderedIds=(orderedIds||[]).map(function(cardId){
    return parseInt(cardId,10)===pkpId ? kpQuoteId : (parseInt(cardId,10)||0);
  }).filter(Boolean);
  if(targetOrderedIds.length){
    await api('kp.php',{action:'set_quote_kanban_orders',workflow_status:targetStatus,ordered_ids:targetOrderedIds});
  }
  return {kpQuoteId:kpQuoteId, transferMeta:transferMeta};
}
function kpParseDragData(raw){
  var parts=String(raw||'').split('|');
  if(parts.length>=2) return {mode:kpNormalizeQuoteMode(parts[0]), id:parseInt(parts[1],10)||0};
  return {mode:_kpDraggingMode||'kp', id:parseInt(parts[0]||'0',10)||0};
}
async function kpDropToStatus(e,status,mode){
  mode=kpNormalizeQuoteMode(mode||'kp');
  var dragData=kpParseDragData(e.dataTransfer.getData('text/plain')||'');
  var id=_kpDraggingId||dragData.id;
  var dragMode=kpNormalizeQuoteMode(_kpDraggingMode||dragData.mode);
  var crossModePkpToKp=(dragMode==='pkp' && mode==='kp');
  if(dragMode!==mode && !crossModePkpToKp){
    kpClearDropIndicators();
    _kpDraggingId=0;
    _kpDraggingMode='kp';
    return;
  }
  if(!id||!status) return;
  var currentQuote=kpFindQuoteRow(id, dragMode);
  var currentStatus=currentQuote ? String(currentQuote.workflow_status||getDefaultQuoteWorkflowStatus()) : '';
  var cardsWrap=e && e.currentTarget && e.currentTarget.classList && e.currentTarget.classList.contains('kanban-cards') ? e.currentTarget : null;
  var orderedIds=[];
  if(cardsWrap){
    orderedIds=Array.prototype.map.call(cardsWrap.querySelectorAll('.kanban-card[data-kp-id]'), function(card){
      return parseInt(card.getAttribute('data-kp-id')||'0',10)||0;
    }).filter(Boolean).filter(function(cardId){ return cardId!==id; });
    if(_kpDropPlaceholder && _kpDropPlaceholder.parentNode===cardsWrap){
      var insertIndex=Array.prototype.indexOf.call(cardsWrap.children, _kpDropPlaceholder);
      if(insertIndex<0) insertIndex=orderedIds.length;
      orderedIds.splice(insertIndex,0,id);
    }else{
      orderedIds.push(id);
    }
  }
  if(!crossModePkpToKp && currentStatus===String(status)){
    try{
      if(orderedIds.length) await kpSaveKanbanOrders(status, orderedIds, mode);
      kpReorderQuotesForKanban(mode,status,orderedIds);
      kpClearDropIndicators();
      if(!kpApplyColumnDomOrder(mode,status,orderedIds)) loadKpQuotes({preserveScroll:true});
    }catch(err){toast(err.message,'err');}
    _kpDraggingId=0;
    _kpJustDragged=true;
    setTimeout(function(){_kpJustDragged=false;},120);
    return;
  }
  quoteWorkspaceMode=mode;
  if(!crossModePkpToKp && mode!=='pkp' && !(await confirmQuoteBoardTransfer(status))){
    kpClearDropIndicators();
    _kpDraggingId=0;
    _kpDraggingMode='kp';
    _kpJustDragged=true;
    setTimeout(function(){_kpJustDragged=false;},120);
    return;
  }
  try{
    if(crossModePkpToKp){
      await transferPkpQuoteToKpStatus(id,status,orderedIds);
      toast('ПКП перенесено в КП: '+status);
    }else if(status==='Закупить материал' && mode!=='pkp'){
      var quote=await api(getQuoteApiFileByMode(mode)+'?action=quote_detail&id='+id);
      var meta=getKpTransferMetaFromQuote(quote);
      if(!kpTransferMetaReady(meta)){
        await openKpTransferModal(id);
        _kpDraggingId=0;
        _kpDraggingMode='kp';
        return;
      }
      var res=await updateQuoteWorkflowStatus(id,status,meta);
      if(res.order_id){toast('Сделка перенесена в Комплектацию ✓');}
    } else {
      await updateQuoteWorkflowStatus(id,status);
      toast('Статус изменён: '+status);
    }
    if(!crossModePkpToKp && orderedIds.length) await kpSaveKanbanOrders(status, orderedIds, mode);
    loadKpQuotes({preserveScroll:true});
  }catch(err){toast(err.message,'err');}
  kpClearDropIndicators();
  _kpDraggingId=0;
  _kpDraggingMode='kp';
  _kpJustDragged=true;
  setTimeout(function(){_kpJustDragged=false;},120);
}
function initQuoteKanbanDnd(root){
  root=root||document.getElementById('kp-quotes-kanban');
  if(!root) return;
  Array.prototype.forEach.call(root.querySelectorAll('.kanban-card[data-kp-id]'), function(card){
    card.addEventListener('dragstart', function(e){
      _kpDraggingId=parseInt(card.getAttribute('data-kp-id')||'0',10)||0;
      _kpDraggingMode=kpNormalizeQuoteMode(card.getAttribute('data-kp-mode')||'kp');
      _kpJustDragged=false;
      e.dataTransfer.effectAllowed='move';
      e.dataTransfer.setData('text/plain', _kpDraggingMode+'|'+String(_kpDraggingId));
      setTimeout(function(){ card.classList.add('dragging'); },0);
    });
    card.addEventListener('dragend', function(){
      card.classList.remove('dragging');
      kpDragEnd();
    });
  });
  Array.prototype.forEach.call(root.querySelectorAll('.kanban-cards'), function(col){
    col.addEventListener('dragover', function(e){
      e.preventDefault();
      var dragging=root.querySelector('.kanban-card.dragging');
      if(!dragging) return;
      var drop=kpFindDropTarget(col, dragging, e.clientY);
      kpSetDropIndicator(col, drop.target, drop.side);
    });
    col.addEventListener('dragleave', function(e){
      if(_kpDropColumn!==col) return;
      if(e.relatedTarget && col.contains(e.relatedTarget)) return;
      var x=e.clientX, y=e.clientY;
      requestAnimationFrame(function(){
        if(_kpDropColumn!==col) return;
        if(kpIsDragPointInsideCol(col, x, y)) return;
        kpClearDropIndicators();
      });
    });
    col.addEventListener('drop', function(e){
      e.preventDefault();
      kpDropToStatus(e, col.parentElement.getAttribute('data-kp-status'), col.getAttribute('data-kp-mode'));
    });
  });
}

async function editKpQuote(id,mode){
  try{
    quoteWorkspaceMode=kpNormalizeQuoteMode(mode||quoteWorkspaceMode);
    var requestedMode=quoteWorkspaceMode;
    updateQuoteWorkspaceUi();
    rememberKpBoardScrollPosition();
    var draft=loadKpBuilderDraft(quoteWorkspaceMode,id);
    if(draft && parseInt(draft.id||0,10)===parseInt(id,10)){
      kpBuilder=draft;
      return showPage('kp-builder');
    }
    var meta=await api(getQuoteApiFileByMode(requestedMode)+'?action=quote_meta&id='+id);
    kpBuilder=kpBuilderStateFromQuoteResponse(meta,true);
    await showPage('kp-builder');
    var q=await api(getQuoteApiFileByMode(requestedMode)+'?action=quote_detail&id='+id);
    if(kpNormalizeQuoteMode(quoteWorkspaceMode)!==requestedMode) return;
    if(parseInt(kpBuilder.id||0,10)!==parseInt(id,10)) return;
    kpBuilder=kpBuilderStateFromQuoteResponse(q,false);
    kpStoreLastSavedSignatureFromQuote(q);
    if(activePage==='kp-builder') loadKpBuilder();
  }catch(e){toast(e.message,'err');}
}


async function markKpQuoteSent(id){
  try{await api(quoteApiFile(),{action:'set_quote_status',id:id,status:'sent'});toast('Статус обновлён');loadKpQuotes();}catch(e){toast(e.message,'err');}
}


