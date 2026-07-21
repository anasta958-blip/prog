function kpUpdateProposalTypeLabelInput(input){
  kpEnsureProposalTypesOnState(kpBuilder);
  var idx=kpBuilder.active_type_index||0;
  var type=kpBuilder.proposal_types[idx];
  if(!type) return;
  type.label=String((input&&input.value)||'').trim()||kpProposalTypeDefaultLabel(idx);
  var label=type.label;
  var title=document.querySelector('.kp-proposal-type-editor > .catblk-h .catblk-t');
  if(title) title.textContent=label;
  var tab=document.querySelector('.kp-proposal-type-tabs [data-kp-type-index="'+idx+'"]');
  if(tab){
    var badge=tab.querySelector('.badge-cnt');
    tab.textContent=label+' ';
    if(badge) tab.appendChild(badge);
  }
  if(input) input.value=label;
}

function kpUpdateVariantLabelInput(input, vi){
  ensureKpVariants();
  vi=Math.max(0, Math.min(parseInt(vi,10)||0, kpBuilder.variants.length-1));
  var variant=kpBuilder.variants[vi];
  if(!variant) return;
  variant.label=String((input&&input.value)||'').trim()||kpVariantDefaultLabel(vi);
  var label=variant.label;
  var tab=document.querySelector('.kp-variant-tabs [data-kp-variant-index="'+vi+'"]');
  if(tab) tab.textContent=label;
  if(vi===kpBuilder.active_variant_index){
    var title=document.querySelector('.kp-variant[data-kp-target="'+kpTargetName(vi)+'"] > .catblk-h .catblk-t');
    if(title) title.textContent=label;
  }
  if(input) input.value=label;
  kpSyncBuilderActiveTypeVariants(kpBuilder);
  kpRefreshAllVariantsSummary(vi);
}

function renderKpVariants(){
  ensureKpVariants();
  var wrap=document.getElementById('kp-variants-wrap');
  if(!wrap) return;
  var proposalTypes=kpBuilder.proposal_types||[];
  var activeType=kpCurrentProposalType();
  if(!activeType) return;
  var activeIndex=Math.max(0, Math.min(kpBuilder.active_variant_index||0, kpBuilder.variants.length-1));
  kpBuilder.active_variant_index=activeIndex;
  kpPrepareVariant(activeIndex);
  var v=kpBuilder.variants[activeIndex];
  var cats=kpEnsureVariantCats(activeIndex);
  var totals=kpGetVariantTotals(v);
  var typesHtml='<div class="catblk kp-proposal-types">'+
    '<div class="catblk-h"><div class="catblk-t">Типы предложения</div><div class="pa"><button class="btn btn-p btn-sm" id="kp-builder-add-type-btn" onclick="addKpProposalType()">➕ Добавить тип предложения</button></div></div>'+
    '<div class="kp-proposal-type-tabs">'+proposalTypes.map(function(type, ti){
      var isActive=ti===kpBuilder.active_type_index;
      return '<button type="button" class="btn '+(isActive?'btn-p':'btn-ghost')+' btn-sm" data-kp-type-index="'+ti+'" onclick="setActiveKpProposalType('+ti+')">'+esc(type.label||kpProposalTypeDefaultLabel(ti))+' <span class="badge-cnt">'+((type.variants||[]).length||0)+'</span></button>';
    }).join('')+'</div>'+
  '</div>';
  var typeHeaderHtml='<div class="catblk kp-proposal-type-editor">'+
    '<div class="catblk-h"><div class="catblk-t">'+esc(activeType.label||kpProposalTypeDefaultLabel(kpBuilder.active_type_index))+'</div><div class="pa">'+
      (proposalTypes.length>1?'<button class="btn btn-rd btn-sm" onclick="removeKpProposalType('+kpBuilder.active_type_index+')">🗑 Удалить тип</button>':'')+
    '</div></div>'+
    '<div class="kp-proposal-type-body"><div class="frow">'+
      '<div class="field"><label>Тип предложения</label><input class="finp" value="'+esc(activeType.label||'')+'" onblur="kpUpdateProposalTypeLabelInput(this)" onchange="kpUpdateProposalTypeLabelInput(this)"></div>'+
      '<div class="field"><label>Варианты внутри типа</label><div class="pa" style="justify-content:flex-start"><button class="btn btn-p btn-sm" id="kp-builder-add-variant-btn" onclick="addKpVariant()">➕ Добавить вариант</button></div></div>'+
    '</div></div>'+
  '</div>';
  var variantTabsHtml='<div class="kp-variant-tabs" style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px">'+kpBuilder.variants.map(function(variant,vi){
    var isActive=vi===activeIndex;
    return '<button class="btn '+(isActive?'btn-p':'btn-ghost')+'" type="button" data-kp-variant-index="'+vi+'" onclick="setActiveKpVariant('+vi+')" style="min-width:140px">'+esc(variant.label||kpVariantDefaultLabel(vi))+'</button>';
  }).join('')+'</div>';
  var variantActions='<button class="btn btn-g btn-sm" onclick="copyKpVariant('+activeIndex+')">⧉ Скопировать вариант</button>'+
      (kpBuilder.variants.length>1?'<button class="btn btn-rd btn-sm" onclick="removeKpVariant('+activeIndex+')">🗑 Удалить вариант</button>':'');
  var variantHtml='<div class="catblk kp-variant" data-kp-target="'+esc(kpTargetName(activeIndex))+'">'+
      variantTabsHtml+
      '<div class="catblk-h"><div class="catblk-t">'+esc(v.label||kpVariantDefaultLabel(activeIndex))+'</div><div class="pa">'+variantActions+'</div></div>'+
      '<div class="kp-variant-body">'+
        '<div class="frow">'+
          '<div class="field"><label>Подпись варианта</label><input class="finp" value="'+esc(v.label||'')+'" onblur="kpUpdateVariantLabelInput(this,'+activeIndex+')" onchange="kpUpdateVariantLabelInput(this,'+activeIndex+')"></div>'+
          '<div class="field"><label>НДС варианта</label><select class="finp" onchange="kpBuilder.variants['+activeIndex+'].vat_mode=this.value;kpRefreshVariantSummary('+activeIndex+');kpRefreshAllVariantsSummary('+activeIndex+')"><option value="none"'+((v.vat_mode||'none')==='none'?' selected':'')+'>Без НДС</option><option value="5"'+((v.vat_mode||'none')==='5'?' selected':'')+'>5%</option><option value="22"'+((v.vat_mode||'none')==='22'?' selected':'')+'>22%</option></select></div>'+
        '</div>'+
        '<div style="margin:12px 0 14px"><button class="btn btn-p" type="button" data-kp-add-cat-btn="1" onclick="_addCatModal(\''+kpTargetName(activeIndex)+'\')">➕ Добавить категорию</button></div>'+
        buildCatsHTML(kpTargetName(activeIndex),cats)+
        '<div class="kp-summary"><div class="ctitle" style="margin-bottom:10px">Сводка варианта</div>'+
          '<div class="kp-variant-summary-split">'+
            '<div><div class="kp-summary-label"><div class="mlb" style="color: white;">Для клиента</div></div>'+
              '<div class="kp-summary-row"><div><div class="mlb">Сумма</div><div class="mvl" id="kp-summary-total-'+activeIndex+'">'+esc(totals.total.toFixed(0))+' ₽</div></div><div><div class="mlb">Сумма НДС</div><div class="mvl" id="kp-summary-vat-'+activeIndex+'">'+esc(totals.vat_sum.toFixed(0))+' ₽</div></div><div><div class="mlb">Ставка НДС</div><div class="mvl" id="kp-summary-rate-'+activeIndex+'">'+(totals.vat_rate?esc(String(totals.vat_rate))+'%':'Без НДС')+'</div></div><div><div class="mlb">Сумма с НДС</div><div class="mvl" id="kp-summary-with-vat-'+activeIndex+'">'+esc(totals.total_with_vat.toFixed(0))+' ₽</div></div></div>'+
            '</div>'+
            '<div><div class="kp-summary-label"><div class="mlb" style="color: white;">Для менеджера</div></div>'+
              '<div class="kp-summary-row"><div><div class="mlb">Итог закупка</div><div class="mvl" id="kp-summary-purchase-'+activeIndex+'">'+esc(totals.purchase_total.toFixed(0))+' ₽</div></div><div><div class="mlb">Маржа</div><div class="mvl" id="kp-summary-margin-'+activeIndex+'">'+esc(totals.margin_value.toFixed(0))+' ₽'+(totals.margin_percent!=null?' ('+esc(totals.margin_percent.toFixed(0))+'%)':'')+'</div></div></div>'+
            '</div>'+
          '</div>'+
        '</div>'+
        '<div id="kp-all-variants-summary-wrap"></div>'+
      '</div>'+
    '</div>'+
    (typeof kpBuildProposalTypeSummaryHtml==='function'?kpBuildProposalTypeSummaryHtml(activeType):'');
  wrap.innerHTML=typesHtml+typeHeaderHtml+variantHtml;
  enhanceKpCategoryBulkUi(wrap, kpTargetName(activeIndex));
  enhanceBuilderFolding(wrap, kpTargetName(activeIndex));
  kpNormalizeBuilderSelects(wrap);
  stripNumericFieldDecimals(document.getElementById('kp-variants-wrap')||document);
  syncKpBuilderAccessUi();
  if(typeof kpSyncClientChoiceModeControl==='function') kpSyncClientChoiceModeControl();
  setTimeout(function(){
    if(kpBuilder.active_variant_index===activeIndex) kpRefreshAllVariantsSummary(activeIndex);
  },0);
}
function renderKpVariantCats(){
  renderKpVariants();
}
function kpQuoteModeOf(row){
  return kpNormalizeQuoteMode((row&&row.quote_mode)||'kp');
}
function kpColumnMatchesQuote(column,row){
  return kpNormalizeQuoteMode(column.mode)===kpQuoteModeOf(row) && kpCanonicalWorkflowStatus(row.workflow_status||getDefaultQuoteWorkflowStatus(), column.mode)===kpCanonicalWorkflowStatus(column.status, column.mode);
}
var KP_KANBAN_PAGE_SIZE=5;
var kpKanbanPaginationState={};
function kpKanbanColumnStateKey(mode,status){
  return kpNormalizeQuoteMode(mode)+'::'+kpCanonicalWorkflowStatus(status, mode);
}
function kpResetKanbanPagination(){
  kpKanbanPaginationState={};
}
function kpNormalizeQuoteRowsForBoard(rows,mode){
  mode=kpNormalizeQuoteMode(mode||'kp');
  return (rows||[]).map(function(row){
    row.quote_mode=mode;
    row.workflow_status=kpCanonicalWorkflowStatus(row.workflow_status, mode)||getQuoteWorkflowStatusesForMode(mode)[0];
    return row;
  });
}
function kpMergeBoardQuotes(rows){
  var byKey={};
  (kpQuotes||[]).forEach(function(row){
    byKey[kpQuoteModeOf(row)+'::'+row.id]=row;
  });
  (rows||[]).forEach(function(row){
    byKey[kpQuoteModeOf(row)+'::'+row.id]=row;
  });
  kpQuotes=Object.keys(byKey).map(function(key){return byKey[key];});
}
async function kpLoadBoardColumnQuotes(column,page){
  var mode=kpNormalizeQuoteMode(column.mode||'kp');
  var status=kpCanonicalWorkflowStatus(column.status||'', mode);
  if(mode==='kp' && status==='Закупить материал') return [];
  var key=kpKanbanColumnStateKey(mode,status);
  page=Math.max(parseInt(page||1,10)||1,1);
  var response=await api(getQuoteApiFileByMode(mode)+'?action=quotes&workflow_status='+encodeURIComponent(status)+'&page='+page+'&per_page='+KP_KANBAN_PAGE_SIZE);
  var meta=apiPagination(response)||{page:page,per_page:KP_KANBAN_PAGE_SIZE,total:0,pages:1,has_next:false};
  kpKanbanPaginationState[key]=meta;
  return kpNormalizeQuoteRowsForBoard(apiItems(response),mode);
}
function kpKanbanLoadedPageForColumn(column){
  var mode=kpNormalizeQuoteMode(column.mode||'kp');
  var status=kpCanonicalWorkflowStatus(column.status||'', mode);
  var meta=kpKanbanPaginationState[kpKanbanColumnStateKey(mode,status)]||null;
  return Math.max(parseInt(meta&&meta.page||1,10)||1,1);
}
async function kpLoadBoardColumnPages(column,pages){
  pages=Math.max(parseInt(pages||1,10)||1,1);
  var rows=[];
  for(var page=1; page<=pages; page++){
    rows=rows.concat(await kpLoadBoardColumnQuotes(column,page));
  }
  return rows;
}
async function kpLoadBoardQuotes(columns,opts){
  opts=opts||{};
  columns=columns||getUnifiedQuoteKanbanColumns();
  var tasks=columns.map(function(column){
    return kpLoadBoardColumnPages(column, opts.preservePagination ? kpKanbanLoadedPageForColumn(column) : 1);
  });
  var loaded=await Promise.all(tasks);
  return loaded.reduce(function(acc,rows){return acc.concat(rows||[]);},[]);
}
function kpKanbanMoreButtonHtml(mode,status){
  var key=kpKanbanColumnStateKey(mode,status);
  var meta=kpKanbanPaginationState[key]||null;
  if(!meta) return '';
  var page=parseInt(meta.page||1,10)||1;
  var html='';
  if(meta.has_next){
    html+='<button class="btn btn-cy btn-xs kanban-more-btn" onclick="event.stopPropagation();kpLoadNextQuoteKanbanPage(\''+esc(mode)+'\',\''+esc(status)+'\')">Показать следующие '+KP_KANBAN_PAGE_SIZE+'</button>';
  }
  if(page>1){
    html+='<button class="btn btn-ghost btn-xs kanban-more-btn" onclick="event.stopPropagation();kpHideLastQuoteKanbanPage(\''+esc(mode)+'\',\''+esc(status)+'\')">Скрыть последние '+KP_KANBAN_PAGE_SIZE+'</button>';
    html+='<button class="btn btn-ghost btn-xs kanban-more-btn" onclick="event.stopPropagation();kpHideAllExtraQuoteKanbanPages(\''+esc(mode)+'\',\''+esc(status)+'\')">Скрыть все</button>';
  }
  return html ? '<div class="kanban-more-wrap">'+html+'</div>' : '';
}
async function kpLoadNextQuoteKanbanPage(mode,status){
  mode=kpNormalizeQuoteMode(mode||'kp');
  status=kpCanonicalWorkflowStatus(status||'', mode);
  var key=kpKanbanColumnStateKey(mode,status);
  var meta=kpKanbanPaginationState[key]||{page:1,pages:1,has_next:false};
  if(!meta.has_next) return;
  try{
    var rows=await kpLoadBoardColumnQuotes({mode:mode,status:status},(parseInt(meta.page||1,10)||1)+1);
    kpMergeBoardQuotes(rows);
    loadKpQuotes({preserveScroll:true,silent:true,skipFetch:true});
  }catch(e){
    toast((e&&e.message)||'Ошибка загрузки','err');
  }
}
function kpSetQuoteKanbanVisiblePages(mode,status,pages){
  mode=kpNormalizeQuoteMode(mode||'kp');
  status=kpCanonicalWorkflowStatus(status||'', mode);
  var key=kpKanbanColumnStateKey(mode,status);
  var meta=kpKanbanPaginationState[key]||null;
  if(!meta) return;
  pages=Math.max(parseInt(pages||1,10)||1,1);
  meta.page=pages;
  kpKanbanPaginationState[key]=meta;
  loadKpQuotes({preserveScroll:true,silent:true,preservePagination:true});
}
function kpHideLastQuoteKanbanPage(mode,status){
  mode=kpNormalizeQuoteMode(mode||'kp');
  status=kpCanonicalWorkflowStatus(status||'', mode);
  var meta=kpKanbanPaginationState[kpKanbanColumnStateKey(mode,status)]||null;
  var page=parseInt(meta&&meta.page||1,10)||1;
  if(page<=1) return;
  kpSetQuoteKanbanVisiblePages(mode,status,page-1);
}
function kpHideAllExtraQuoteKanbanPages(mode,status){
  kpSetQuoteKanbanVisiblePages(mode,status,1);
}

function enhanceQuotesKanbanArchive(){
  var root=document.getElementById('kp-quotes-kanban');
  if(!root) return;
  (root.querySelectorAll ? root.querySelectorAll('.kanban-col[data-kp-status]') : []).forEach(function(col){
    var status=col.getAttribute('data-kp-status')||'';
    var mode=kpNormalizeQuoteMode(col.getAttribute('data-kp-mode')||'kp');
    var cardsWrap=col.querySelector('.kanban-cards');
    var headerBadge=col.querySelector('.kanban-col-h .badge-cnt');
    var details=ensureKanbanArchiveSection(col,'quotes',mode+'::'+status);
    var archiveBody=details.querySelector('.kanban-archive-body');
    var archivedRows=(kpQuotes||[]).filter(function(q){
      return kpQuoteModeOf(q)===mode && kpCanonicalWorkflowStatus(q.workflow_status||getDefaultQuoteWorkflowStatus(), mode)===kpCanonicalWorkflowStatus(status, mode) && !!parseInt(q.is_archived||0,10);
    });
    archivedRows.forEach(function(q){
      var card=root.querySelector('.kanban-card[data-kp-id="'+q.id+'"][data-kp-mode="'+mode+'"]');
      if(!card){
        var color=getKpWorkflowColor(status);
        var tmp=document.createElement('div');
        tmp.innerHTML=kpBuildQuoteKanbanCardHtml(q,color,true);
        card=tmp.firstElementChild||null;
      }
      if(!card) return;
      card.classList.add('archived-card');
      card.removeAttribute('draggable');
      card.removeAttribute('ondragstart');
      card.removeAttribute('ondragend');
      archiveBody.appendChild(card);
      ensureQuoteArchiveButton(card,q.id,true,mode);
    });
    Array.prototype.forEach.call(cardsWrap.querySelectorAll('.kanban-card[data-kp-id][data-kp-mode]'), function(card){
      ensureQuoteArchiveButton(card,card.getAttribute('data-kp-id'),false,card.getAttribute('data-kp-mode'));
    });
    if(headerBadge){
      var activeCount=(kpQuotes||[]).filter(function(q){
        return kpQuoteModeOf(q)===mode && kpCanonicalWorkflowStatus(q.workflow_status||getDefaultQuoteWorkflowStatus(), mode)===kpCanonicalWorkflowStatus(status, mode) && !parseInt(q.is_archived||0,10);
      }).length;
      headerBadge.textContent=String(activeCount);
    }
    var archiveBadge=details.querySelector('.badge-cnt');
    if(archiveBadge) archiveBadge.textContent=String(archivedRows.length);
    updateKanbanArchiveEmptyState(archiveBody);
    ensureKanbanCardsEmptyState(cardsWrap);
  });
}

getKanbanVariantMarkup=function(label){
  var raw=String(label||'').trim();
  var lower=raw.toLowerCase();
  var cls='';
  if(lower.indexOf('бюдж')===0) cls=' kanban-variant-budget';
  else if(lower.indexOf('оптим')===0) cls=' kanban-variant-optimal';
  else if(lower.indexOf('прем')===0 || lower.indexOf('прим')===0) cls=' kanban-variant-premium';
  return 'Вариант: <span class="kanban-variant-badge'+cls+'">'+esc(raw)+'</span>';
};
function kpGetQuoteVariantTotalByLabel(quote,label){
  var raw=String(label||'').trim();
  if(!raw) return null;
  var payload=(quote&&quote.payload&&typeof quote.payload==='object')?quote.payload:null;
  var variants=payload&&Array.isArray(payload.variants)?payload.variants:[];
  var variant=variants.find(function(v){return String((v&&v.label)||'').trim()===raw;})||null;
  if(!variant) return null;
  try{
    var items=Array.isArray(variant.items) && variant.items.length ? variant.items : kpCatsToItems((variant&&variant.cats)||[]);
    var total=0;
    items.forEach(function(item){
      if(!item || item.excluded_from_calc) return;
      var qty=Math.max(parseFloat(item.quantity||0)||0,0);
      var line=null;
      if(item.line_sum!=null && item.line_sum!==''){
        line=parseFloat(item.line_sum)||0;
      }else if(item.sum!=null && item.sum!==''){
        line=parseFloat(item.sum)||0;
      }else{
        var base=item.final_price!=null && item.final_price!=='' ? parseFloat(item.final_price||0) : parseFloat(item.base_price!=null ? item.base_price : item.retail_price)||0;
        line=base*qty;
      }
      total+=Math.max(line,0);
    });
    return isFinite(total)?total:null;
  }catch(e){
    return null;
  }
}
function kpGetQuoteSelectedVariantSummary(quote){
  if(quote && quote.selected_variant_summary && typeof quote.selected_variant_summary==='object'){
    var serverSummary=quote.selected_variant_summary;
    return {
      label:String(serverSummary.label||''),
      total:serverSummary.total===null || serverSummary.total===undefined || serverSummary.total==='' ? null : (parseFloat(serverSummary.total)||0),
      lines:Array.isArray(serverSummary.lines) ? serverSummary.lines : [],
      selection_mode:String(serverSummary.selection_mode||''),
      typeLabel:String(serverSummary.typeLabel||serverSummary.type_label||'')
    };
  }
  var payload=(quote&&quote.payload&&typeof quote.payload==='object')?quote.payload:{};
  var proposalTypes=kpGetPayloadProposalTypes(payload);
  if(proposalTypes.length){
    var selectionMode=String(payload.selection_mode||payload.client_selection_mode||'');
    var selectedTypeId=String(payload.selected_type_id||'').trim();
    if(selectionMode==='type' && selectedTypeId){
      var selectedType=proposalTypes.find(function(type){return String(type.id||'')===selectedTypeId;})||null;
      if(selectedType){
        var typeTotals=typeof kpGetProposalTypeTotals==='function' ? kpGetProposalTypeTotals(selectedType) : null;
        var typeLines=(selectedType.variants||[]).map(function(variant){
          return {typeLabel:String(selectedType.label||'').trim(),variantLabel:String(variant.label||'').trim()};
        });
        return {
          label:String(selectedType.label||'').trim()||'Выбранный тип',
          total:typeTotals ? typeTotals.total : null,
          lines:typeLines,
          selection_mode:'type',
          typeLabel:String(selectedType.label||'').trim()
        };
      }
    }
    var picked=[];
    var total=0;
    proposalTypes.forEach(function(type){
      var chosen=kpGetProposalTypeChosenVariant(type);
      if(!chosen) return;
      picked.push({
        typeLabel:String(type.label||'').trim(),
        variantLabel:String(chosen.label||'').trim()
      });
      var variantTotal=kpGetVariantTotals(chosen).total||0;
      total+=variantTotal;
    });
    if(!picked.length) return {label:'',total:null,lines:[]};
    return {
      label:picked.length===1 ? picked[0].variantLabel : ('Выбрано типов: '+picked.length),
      total:isFinite(total)?total:null,
      lines:picked
    };
  }
  var label=String((quote&&quote.selected_variant_label)||'').trim();
  if(!label) return {label:'',total:null,lines:[]};
  return {label:label,total:kpGetQuoteVariantTotalByLabel(quote,label),lines:[{typeLabel:'',variantLabel:label}]};
}
function kpFormatKanbanMoney(v){
  if(v===null || v===undefined || !isFinite(v)) return '';
  return String(Math.round(parseFloat(v)||0)).replace(/\B(?=(\d{3})+(?!\d))/g,' ')+' ₽';
}
function kpBuildKanbanSelectedSummaryHtml(summary){
  if(!summary || !summary.lines || !summary.lines.length) return 'Вариант не выбран';
  if(summary.selection_mode==='type'){
    return 'Тип: <span class="kanban-variant-badge">'+esc(summary.typeLabel||summary.label||'Выбранный тип')+'</span><br><span style="color:var(--tx2)">Вариантов внутри: '+esc(String(summary.lines.length))+'</span>';
  }
  if(summary.lines.length===1 && !summary.lines[0].typeLabel){
    return getKanbanVariantMarkup(summary.lines[0].variantLabel);
  }
  return summary.lines.map(function(line){
    var head=line.typeLabel ? (esc(line.typeLabel)+': ') : '';
    return head+'<span class="kanban-variant-badge">'+esc(line.variantLabel||'—')+'</span>';
  }).join('<br>');
}
function kpBuildQuoteChangeLine(label, meta){
  if(!meta) return '';
  var who=((meta.full_name||meta.login||'—') + (meta.role ? ' · ' + (ROLE_LABELS[meta.role]||meta.role) : ''));
  var when=meta.changed_at ? fmtDate(meta.changed_at) : '';
  return '<div style="font-size:.74rem;color:var(--tx3);margin-top:6px">'+esc(label)+': '+esc(who)+(when?' <span style="color:var(--tx3)">('+when+')</span>':'')+'</div>';
}
function kpBuildQuoteKanbanCardHtml(q, color, archived){
  var quoteMode=kpQuoteModeOf(q);
  var abs=buildPublicQuoteUrl(q.public_url);
  var lw=q.last_workflow_change||null;
  var lc=q.last_card_change||null;
  var top=q.object_address||q.title||'—';
  var headerColor=lw&&lw.role ? getRoleColor(lw.role) : color;
  var typeLine=getQuoteModeTitle(quoteMode)+' #'+q.id+(q.object_type?' · '+q.object_type:'');
  var selectedSummary=kpGetQuoteSelectedVariantSummary(q);
  var variantLine=selectedSummary.label
    ? kpBuildKanbanSelectedSummaryHtml(selectedSummary)+(selectedSummary.total!=null?(' · '+esc(kpFormatKanbanMoney(selectedSummary.total))):'')
    : 'Вариант не выбран';
  var viewsCount=parseInt(q.public_open_count||0,10)||0;
  var viewsLine='Просмотров: '+viewsCount+(q.viewed_at ? ' · Просмотрено' : '');
  return '<div class="kanban-card'+(archived?' archived-card':'')+'"'+(archived?'':' draggable="true"')+' onclick="kpCardClick(event,'+q.id+',\''+quoteMode+'\')" data-kp-id="'+q.id+'" data-kp-mode="'+quoteMode+'"><div class="kanban-card-top" style="background:'+headerColor+'">'+esc(top)+'</div><div class="kanban-card-body">'+
    '<div class="kanban-card-addr" style="font-size:.75rem;color:var(--tx2)">'+esc(typeLine)+'</div>'+
    '<div class="kanban-card-meta">'+esc(q.manager_name||'—')+(q.rop_name?' - '+esc(q.rop_name):'')+'<br>'+fmtDate(q.created_at)+'<br>'+variantLine+'<br>'+esc(viewsLine)+'</div>'+
    '<div style="font-size:.76rem;color:var(--tx2);margin-top:6px">'+esc(q.client_company_name||'—')+'</div>'+
    kpBuildQuoteChangeLine('Изменил', lc)+
    kpBuildQuoteChangeLine('Статус изменил', lw)+
    '<div class="pa" style="margin-top:10px">'+(accessCanUi('kp','edit')?'<button class="btn btn-g btn-xs" onclick="event.stopPropagation();editKpQuote('+q.id+',\''+quoteMode+'\')">✏️</button>':'')+'<button class="btn btn-cy btn-xs" onclick="event.stopPropagation();copyKpQuoteLink(\''+esc(abs)+'\')">🔗</button>'+(accessCanUi('kp','delete')?'<button class="btn btn-rd btn-xs" onclick="event.stopPropagation();deleteKpQuote('+q.id+',\''+quoteMode+'\')">🗑</button>':'')+'</div>'+
  '</div></div>';
}
var kpQuotesLoadGeneration=0;
loadKpQuotes=async function(opts){
  try{
    opts=opts||{};
    if(typeof navigationScrollRestoreToken!=='undefined') navigationScrollRestoreToken++;
    var loadGeneration=++kpQuotesLoadGeneration;
    var restoreSaved=!!(kpBoardScrollMemory && kpBoardScrollMemory.pendingRestore);
    var columns=getUnifiedQuoteKanbanColumns().filter(function(column){
      return accessTabVisibleUi('kp_list') && accessKanbanColumnVisibleUi('kp', column.mode, column.status);
    });
    if(!opts.skipFetch){
      if(!opts.preservePagination) kpResetKanbanPagination();
      var loadedQuotes=await kpLoadBoardQuotes(columns,{preservePagination:!!opts.preservePagination});
      if(loadGeneration!==kpQuotesLoadGeneration) return;
      kpQuotes=loadedQuotes;
    }
    var wrap=document.getElementById('kp-quotes-kanban');
    if(!wrap) return;
    var nextHtml='<div class="kanban-grid">'+columns.map(function(column){
      var status=column.status;
      var mode=column.mode;
      var cards=kpSortQuotesForKanban(kpQuotes.filter(function(q){return kpColumnMatchesQuote(column,q) && !parseInt(q.is_archived||0,10);}));
      var color=getKpWorkflowColor(status, mode);
      var columnTotal=cards.reduce(function(total,q){
        var selected=kpGetQuoteSelectedVariantSummary(q);
        return total + (selected.total||0);
      },0);
      var createBtn=status===getQuoteWorkflowStatusesForMode(mode)[0]
        ? '<button class="btn btn-g btn-xs" style="margin-left:auto" onclick="event.stopPropagation();openNewQuoteByMode(\''+mode+'\')">Составить '+esc(getQuoteModeTitle(mode))+'</button>'
        : '';
      var emptyState=cards.length
        ? ''
        : '<div class="es" style="margin:10px">'+(status===getQuoteWorkflowStatusesForMode(mode)[0] ? ('Нажмите кнопку, чтобы создать новое '+esc(getQuoteModeTitle(mode))) : 'Пусто')+'</div>';
      return '<div class="kanban-col" data-kp-status="'+esc(status)+'" data-kp-mode="'+mode+'"><div class="kanban-col-h" style="border-top:3px solid '+color+'"><span>'+esc(status)+(columnTotal>0?(' · '+esc(kpFormatKanbanMoney(columnTotal))):'')+'</span> <span class="badge-cnt">'+cards.length+'</span>'+createBtn+'</div><div class="kanban-cards" data-kp-mode="'+mode+'">'+cards.map(function(q){
        var abs=buildPublicQuoteUrl(q.public_url);
        var lw=q.last_workflow_change||null;
        var lc=q.last_card_change||null;
        var top=q.object_address||q.title||'—';
        var headerColor=lw&&lw.role ? getRoleColor(lw.role) : color;
        var quoteMode=kpQuoteModeOf(q);
        var typeLine=getQuoteModeTitle(quoteMode)+' #'+q.id+(q.object_type?' · '+q.object_type:'');
        var selectedSummary=kpGetQuoteSelectedVariantSummary(q);
        var variantLine=selectedSummary.label
          ? kpBuildKanbanSelectedSummaryHtml(selectedSummary)+(selectedSummary.total!=null?(' · '+esc(kpFormatKanbanMoney(selectedSummary.total))):'')
          : 'Вариант не выбран';
        var viewsCount=parseInt(q.public_open_count||0,10)||0;
        var viewsLine='Просмотров: '+viewsCount+(q.viewed_at ? ' · Просмотрено' : '');
        return '<div class="kanban-card" draggable="true" onclick="kpCardClick(event,'+q.id+',\''+quoteMode+'\')" data-kp-id="'+q.id+'" data-kp-mode="'+quoteMode+'"><div class="kanban-card-top" style="background:'+headerColor+'">'+esc(top)+'</div><div class="kanban-card-body">'+
          '<div class="kanban-card-addr" style="font-size:.75rem;color:var(--tx2)">'+esc(typeLine)+'</div>'+
          '<div class="kanban-card-meta">'+esc(q.manager_name||'—')+(q.rop_name?' - '+esc(q.rop_name):'')+'<br>'+fmtDate(q.created_at)+'<br>'+variantLine+'<br>'+esc(viewsLine)+'</div>'+
          '<div style="font-size:.76rem;color:var(--tx2);margin-top:6px">'+esc(q.client_company_name||'—')+'</div>'+
          kpBuildQuoteChangeLine('Изменил', lc)+
          kpBuildQuoteChangeLine('Статус изменил', lw)+
          '<div class="pa" style="margin-top:10px">'+(accessCanUi('kp','edit')?'<button class="btn btn-g btn-xs" onclick="event.stopPropagation();editKpQuote('+q.id+',\''+quoteMode+'\')">✏️</button>':'')+'<button class="btn btn-cy btn-xs" onclick="event.stopPropagation();copyKpQuoteLink(\''+esc(abs)+'\')">🔗</button>'+(accessCanUi('kp','delete')?'<button class="btn btn-rd btn-xs" onclick="event.stopPropagation();deleteKpQuote('+q.id+',\''+quoteMode+'\')">🗑</button>':'')+'</div>'+
        '</div></div>';
      }).join('')+emptyState+kpKanbanMoreButtonHtml(mode,status)+'</div></div>';
    }).join('')+'</div>';
    var main=document.querySelector('.main');
    var currentGrid=wrap.querySelector('.kanban-grid');
    var prevMainScroll=restoreSaved ? (kpBoardScrollMemory.main||0) : (main ? main.scrollTop : 0);
    var prevGridScroll=restoreSaved ? (kpBoardScrollMemory.grid||0) : (currentGrid ? currentGrid.scrollLeft : 0);
    if(wrap.__kpKanbanHtml===nextHtml){
      if(main) main.scrollTop=prevMainScroll;
      if(currentGrid) currentGrid.scrollLeft=prevGridScroll;
      requestAnimationFrame(function(){
        if(loadGeneration!==kpQuotesLoadGeneration) return;
        if(main) main.scrollTop=prevMainScroll;
        var activeGrid=wrap.querySelector('.kanban-grid');
        if(activeGrid) activeGrid.scrollLeft=prevGridScroll;
      });
      if(kpBoardScrollMemory) kpBoardScrollMemory.pendingRestore=false;
      return;
    }
    wrap.innerHTML=nextHtml;
    wrap.__kpKanbanHtml=nextHtml;
    initKanbanDragScroll(wrap);
    initQuoteKanbanDnd(wrap);
    enhanceQuotesKanbanArchive();
    document.querySelectorAll('#kp-quotes-kanban .pa .btn.btn-g.btn-xs').forEach(function(btn){
      if((btn.textContent||'').indexOf('✏️')>=0 || (btn.textContent||'').indexOf('Редактировать')>=0){
        btn.remove();
      }
    });
    enhanceQuotesKanbanLayout();
    var grid=wrap.querySelector('.kanban-grid');
    if(main) main.scrollTop=prevMainScroll;
    if(grid) grid.scrollLeft=prevGridScroll;
    requestAnimationFrame(function(){
      if(loadGeneration!==kpQuotesLoadGeneration) return;
      if(main) main.scrollTop=prevMainScroll;
      var activeGrid=wrap.querySelector('.kanban-grid');
      if(activeGrid) activeGrid.scrollLeft=prevGridScroll;
      if(kpBoardScrollMemory) kpBoardScrollMemory.pendingRestore=false;
    });
  }catch(e){
    if(!opts || !opts.silent) toast((e&&e.message)||'Ошибка загрузки','err');
  }
};

function enhanceQuotesKanbanLayout(){
  var root=document.getElementById('kp-quotes-kanban');
  if(!root) return;
  Array.prototype.forEach.call(root.querySelectorAll('.kanban-col[data-kp-status]'), function(col){
    var status=String(col.getAttribute('data-kp-status')||'');
    var mode=kpNormalizeQuoteMode(col.getAttribute('data-kp-mode')||'kp');
    var head=col.querySelector('.kanban-col-h');
    if(!head) return;
    var titleEl=head.querySelector('span');
    var badgeEl=head.querySelector('.badge-cnt');
    var actionBtn=head.querySelector('button');
    var sum=(kpQuotes||[]).reduce(function(total,q){
      var sameStatus=kpQuoteModeOf(q)===mode && kpCanonicalWorkflowStatus(q.workflow_status||getDefaultQuoteWorkflowStatus(), mode)===kpCanonicalWorkflowStatus(status, mode);
      var active=!parseInt(q.is_archived||0,10);
      if(!sameStatus || !active) return total;
      var selected=kpGetQuoteSelectedVariantSummary(q);
      return total + (selected.total||0);
    },0);
    var leftHtml='<div style="display:flex;flex-direction:column;align-items:flex-start;gap:2px"><span>'+esc(status)+'</span>'+(sum>0?'<span style="font-size:.74rem;font-weight:600;color:var(--tx2)">'+esc(kpFormatKanbanMoney(sum))+'</span>':'')+'</div>';
    var rightHtml='<div style="display:flex;align-items:center;gap:8px">'+(badgeEl?badgeEl.outerHTML:'')+(actionBtn?actionBtn.outerHTML:'')+'</div>';
    head.innerHTML=leftHtml+rightHtml;
  });
  Array.prototype.forEach.call(root.querySelectorAll('.kanban-card[data-kp-id]'), function(card){
    var id=card.getAttribute('data-kp-id');
    var q=(kpQuotes||[]).find(function(row){return String(row.id)===String(id);});
    if(!q) return;
    var meta=card.querySelector('.kanban-card-meta');
    if(!meta) return;
    var lines=(meta.innerHTML||'').split('<br>');
    var selected=kpGetQuoteSelectedVariantSummary(q);
    var variantHtml=selected.label
      ? kpBuildKanbanSelectedSummaryHtml(selected)+(selected.total!=null?'<div style="font-size:.74rem;color:var(--tx2);margin-top:2px">'+esc(kpFormatKanbanMoney(selected.total))+'</div>':'')
      : 'Вариант не выбран';
    if(lines.length>=3) lines[2]=variantHtml;
    else lines.push(variantHtml);
    meta.innerHTML=lines.join('<br>');
  });
}

function applyKpContractorPreset(id){
  if(!kpBuilder.payload || typeof kpBuilder.payload!=='object') kpBuilder.payload={};
  if(!kpBuilder.payload.quote_meta || typeof kpBuilder.payload.quote_meta!=='object') kpBuilder.payload.quote_meta={};
  var contractor=(kpContractors||[]).find(function(x){return String(x.id)===String(id);})||null;
  kpBuilder.payload.quote_meta.contractor_id=contractor ? parseInt(contractor.id||0,10)||0 : 0;
  kpBuilder.payload.quote_meta.contractor_name=contractor ? (contractor.company_name||contractor.legal_name||'') : '';
  kpBuilder.payload.quote_meta.contractor_snapshot=contractor ? {
    company_type:contractor.company_type||'ooo',
    company_name:contractor.company_name||'',
    legal_name:contractor.legal_name||'',
    recipient_name:contractor.recipient_name||contractor.legal_name||'',
    inn:contractor.inn||'',
    ogrn:contractor.ogrn||'',
    kpp:contractor.kpp||'',
    object_address:contractor.object_address||'',
    phone:contractor.phone||'',
    email:contractor.email||'',
    bank_name:contractor.bank_name||'',
    bank_bik:contractor.bank_bik||'',
    note:contractor.note||''
  } : {};
  var sel=document.getElementById('kp-quote-contractor');
  if(sel) sel.value=contractor ? String(contractor.id) : '';
  if(typeof syncKpPartyInput==='function') syncKpPartyInput('contractor');
}

function pkpPresetEmptyItem(){
  return {section_id:'', price:''};
}

function pkpNormalizePresetPayload(payload){
  payload=(payload&&typeof payload==='object')?payload:{};
  if(payload.section_id || payload.price!=null){
    return {
      section_id:String(payload.section_id||''),
      price:payload.price!=null?payload.price:'',
      name:payload.name||''
    };
  }
  var first=(Array.isArray(payload.items)&&payload.items.length)?payload.items[0]:null;
  if(!first) return {section_id:'',price:'',name:''};
  var price=first.base_price;
  if(price==null) price=first.final_price;
  if(price==null) price=first.line_sum;
  if(price==null && first.object_id){
    var product=kpCatalogProducts.find(function(p){return String(p.id)===String(first.object_id);});
    if(product) price=product.retail_price;
  }
  return {
    section_id:String(first.section_id||''),
    price:price!=null?price:'',
    name:first.name||''
  };
}

function renderPkpPresets(){
  var wrap=document.getElementById('pkp-presets-list');
  if(!wrap) return;
  if(!pkpPresets.length){
    wrap.innerHTML='<div class="es">Комплекты пока не созданы</div>';
    return;
  }
  wrap.innerHTML='<div class="pgrid">'+pkpPresets.map(function(p){
    var meta=pkpNormalizePresetPayload(p.payload||{});
    var sec=kpCatalogSections.find(function(s){return String(s.id)===String(meta.section_id||'');});
    return '<div class="ccard fi2 cs-pend">'+
      '<div class="ch"><div><div class="ctitle">'+esc(p.name||'—')+'</div><div class="cmark">Оборудование</div></div><span class="kp-link-state linked">Комплект</span></div>'+
      '<div class="cmeta">'+
        '<div><div class="mlb">Раздел</div><div class="mvl">'+esc(sec&&sec.name?sec.name:'—')+'</div></div>'+
        '<div><div class="mlb">Стоимость</div><div class="mvl">'+(meta.price!==''?esc(String(meta.price))+' ₽':'—')+'</div></div>'+
      '</div>'+
      '<div class="cft">'+(accessCanUi('kp','edit')?'<button class="btn btn-g btn-sm" onclick="openPkpPresetModal('+p.id+')">✏️ Редактировать</button>':'')+(accessCanUi('kp','delete')?'<button class="btn btn-rd btn-sm" onclick="deletePkpPreset('+p.id+')">🗑 Удалить</button>':'')+'</div>'+
    '</div>';
  }).join('')+'</div>';
}

function openPkpPresetModal(id){
  var preset=id ? pkpPresets.find(function(x){return x.id==id;}) : null;
  var meta=pkpNormalizePresetPayload(preset?preset.payload:null);
  pkpPresetDraft={
    id:preset?preset.id:0,
    name:preset?preset.name||meta.name||'':'',
    items:[{section_id:meta.section_id||'',price:meta.price!==''?meta.price:''}]
  };
  document.getElementById('m-pkp-preset-title').textContent=(id?'✏️ ':'➕ ')+'Комплект';
  document.getElementById('pkpp-id').value=pkpPresetDraft.id||0;
  document.getElementById('pkpp-name').value=pkpPresetDraft.name||'';
  renderPkpPresetItems();
  om('m-pkp-preset');
}

function renderPkpPresetItems(){
  var wrap=document.getElementById('pkp-preset-items');
  if(!wrap) return;
  var item=(pkpPresetDraft.items&&pkpPresetDraft.items[0])?pkpPresetDraft.items[0]:pkpPresetEmptyItem();
  var sections=kpCatalogSections.filter(function(s){return s.category_code==='equipment';});
  wrap.innerHTML=
    '<div class="frow">'+
      '<div class="field"><label>Раздел</label><select id="pkpp-section" class="finp"><option value="">— выберите —</option>'+sections.map(function(sec){return '<option value="'+sec.id+'"'+(String(sec.id)===String(item.section_id||'')?' selected':'')+'>'+esc(sec.name)+'</option>';}).join('')+'</select></div>'+
      '<div class="field"><label>Стоимость</label><input id="pkpp-price" type="number" min="0" step="1" class="finp" value="'+esc(item.price!==''?String(item.price):'')+'"></div>'+
    '</div>';
}

async function savePkpPreset(){
  var name=document.getElementById('pkpp-name').value.trim();
  var sectionId=(document.getElementById('pkpp-section').value||'').trim();
  var price=(document.getElementById('pkpp-price').value||'').trim();
  if(!name){toast('Укажите название комплекта','err');return;}
  if(!sectionId){toast('Выберите раздел','err');return;}
  if(price===''){toast('Укажите стоимость','err');return;}
  try{
    await api(quoteApiFile(),{
      action:'catalog_kits_are_used_now',
      id:parseInt(document.getElementById('pkpp-id').value||'0',10),
      name:name,
      payload:{
        category_code:'equipment',
        section_id:sectionId,
        price:Math.max(parseFloat(price||0)||0,0)
      }
    });
    cm('m-pkp-preset');
    toast('Комплект сохранён');
    loadPkpPresets();
  }catch(e){toast(e.message,'err');}
}

function applyPkpPresetToVariant(vi,presetId){
  var preset=pkpPresets.find(function(x){return String(x.id)===String(presetId);});
  if(!preset){toast('Комплект не найден','err');return;}
  var meta=pkpNormalizePresetPayload(preset.payload||{});
  if(!meta.section_id){toast('У комплекта не указан раздел','err');return;}
  var secMeta=kpCatalogSections.find(function(s){return String(s.id)===String(meta.section_id);});
  if(!secMeta){toast('Раздел комплекта не найден','err');return;}
  var cats=kpEnsureVariantCats(vi);
  var cat=kpFindOrCreateCat(cats,'equipment');
  var sec=kpFindOrCreateSection(cat,secMeta.id,secMeta.name||'',secMeta.code||'',false);
  var item=kpNormalizeBuilderItem({
    uid:'pkpp-'+Date.now()+'-'+Math.random().toString(36).slice(2,8),
    item_type:'product',
    category_code:'equipment',
    category_name:cat.catName||kpBuilderCategoryLabel('equipment'),
    section_id:secMeta.id,
    section_name:secMeta.name||'',
    section_code:secMeta.code||'',
    name:preset.name||meta.name||'Комплект',
    quantity:1,
    unit:getDefaultUnit(),
    note:'',
    purchase_price:null,
    minimal_price:null,
    retail_price:parseFloat(meta.price||0)||0,
    base_price:parseFloat(meta.price||0)||0,
    markup_value:0,
    discount_value:0,
    linked_service_id:0,
    linked_service_name:'',
    linked_service_cost:0,
    linked_service_purchase_price:null,
    linked_service_unit:''
  },cat.catCode,cat.catName,sec.secId,sec.secName,sec.secCode);
  sec.items.push(item);
  kpBuilder.variants[vi].cats=cats;
  kpSyncVariantFromCats(vi);
  kpSyncVariantAutoWorks(vi);
  kpSyncVariantFromCats(vi);
  renderKpVariants();
  toast('Комплект применён');
}

async function _addSecModal(t,ci){
  pSecTarget=t;
  pSecCatIdx=ci;
  var cat=getCats(t)[ci];
  var sel=document.getElementById('dc-sec');
  var options=['<option value="">Выберите...</option>'];
  if(isKpTarget(t)){
    if(!kpCatalogSections.length){
      try{ await loadKpCatalogSections(); }catch(e){}
    }
    var list=builderIsWorkCategoryCode(cat.catCode)
      ? [{id:'equipment',name:'Оборудование',code:'equipment'},{id:'materials',name:'Материалы',code:'materials'}]
      : kpCatalogSections.filter(function(s){return s.category_code===cat.catCode && s.name;}).map(function(s){return {id:s.id,name:s.name,code:s.code};});
    list=kpGetBuilderSections(cat.catCode||'');
    if(!list.length){
      try{
        await loadKpCatalogSections();
      }catch(e){}
      list=builderIsWorkCategoryCode(cat.catCode)
        ? [{id:'equipment',name:'Оборудование',code:'equipment'},{id:'materials',name:'Материалы',code:'materials'}]
        : kpCatalogSections.filter(function(s){return s.category_code===cat.catCode && s.name;}).map(function(s){return {id:s.id,name:s.name,code:s.code};});
      list=kpGetBuilderSections(cat.catCode||'');
    }
    list
      .filter(function(s){return !cat.sections.find(function(x){return String(x.secId)===String(s.id) || String(x.secCode||'')===String(s.code||'');});})
      .forEach(function(s){options.push('<option value="'+s.id+'" data-code="'+esc(s.code||'')+'">'+esc(s.name)+'</option>');});
    sel.innerHTML=options.join('');
    if(sel.options.length<=1){
      toast('Нет доступных разделов для этой категории','err');
      return;
    }
  }else{
    allSecs
      .filter(function(s){return s.category_id==cat.catId && s.name && !cat.sections.find(function(x){return x.secId==s.id;});})
      .forEach(function(s){options.push('<option value="'+s.id+'" data-code="'+esc(s.code||'')+'">'+esc(s.name)+'</option>');});
    sel.innerHTML=options.join('');
  }
  om('m-add-sec');
}

function updateKpClientTypeUi(){
  var type=(document.getElementById('kpc-company-type')||{}).value||'person';
  var companyLabel=document.getElementById('kpc-company-label');
  var legalWrap=document.getElementById('kpc-legal') ? document.getElementById('kpc-legal').closest('.field') : null;
  var innField=document.getElementById('kpc-inn') ? document.getElementById('kpc-inn').closest('.field') : null;
  var ogrnField=document.getElementById('kpc-ogrn') ? document.getElementById('kpc-ogrn').closest('.field') : null;
  var kppField=document.getElementById('kpc-kpp') ? document.getElementById('kpc-kpp').closest('.field') : null;
  var bankNameField=document.getElementById('kpc-bank-name') ? document.getElementById('kpc-bank-name').closest('.field') : null;
  var bankBikField=document.getElementById('kpc-bank-bik') ? document.getElementById('kpc-bank-bik').closest('.field') : null;
  var passportRow=document.getElementById('kpc-passport-row');
  var addressLabel=document.getElementById('kpc-address-label');
  var bankExtraRow=document.getElementById('kpc-bank-extra-row');
  var ogrnLabel=document.getElementById('kpc-ogrn-label');
  if(companyLabel) companyLabel.textContent=type==='ooo' ? 'Название компании' : (type==='ip' ? 'Наименование ИП' : 'ФИО');
  if(addressLabel) addressLabel.textContent=type==='person' ? 'Адрес регистрации' : 'Юридический адрес';
  if(ogrnLabel) ogrnLabel.textContent=type==='ip' ? 'ОГРНИП' : 'ОГРН';
  if(legalWrap) legalWrap.style.display='none';
  if(passportRow) passportRow.style.display=type==='person' ? '' : 'none';
  if(innField) innField.style.display=type==='person' ? 'none' : '';
  if(ogrnField) ogrnField.style.display=type==='person' ? 'none' : '';
  if(kppField) kppField.style.display=type==='ooo' ? '' : 'none';
  if(bankNameField) bankNameField.style.display=type==='person' ? 'none' : '';
  if(bankBikField) bankBikField.style.display=type==='person' ? 'none' : '';
  if(bankExtraRow) bankExtraRow.style.display=type==='person' ? 'none' : '';
}

var KP_CLIENT_META_PREFIX='__kp_client_meta__:';
function kpParseClientMetaNote(note){
  var meta={legacy_note:''};
  var raw=String(note||'').trim();
  if(!raw) return meta;
  if(raw.indexOf(KP_CLIENT_META_PREFIX)!==0){
    meta.legacy_note=raw;
    return meta;
  }
  try{
    meta=JSON.parse(raw.slice(KP_CLIENT_META_PREFIX.length))||{};
  }catch(e){
    meta={legacy_note:raw};
  }
  if(!meta || typeof meta!=='object') meta={legacy_note:''};
  if(typeof meta.legacy_note!=='string') meta.legacy_note='';
  return meta;
}
function kpBuildClientMetaNote(meta){
  var payload={
    passport_series:String(meta.passport_series||'').trim(),
    passport_number:String(meta.passport_number||'').trim(),
    passport_issued_by:String(meta.passport_issued_by||'').trim(),
    bank_account:String(meta.bank_account||'').trim(),
    corr_account:String(meta.corr_account||'').trim(),
    legacy_note:String(meta.legacy_note||'').trim()
  };
  var hasData=payload.passport_series||payload.passport_number||payload.passport_issued_by||payload.bank_account||payload.corr_account;
  if(!hasData) return payload.legacy_note||'';
  return KP_CLIENT_META_PREFIX+JSON.stringify(payload);
}

async function lookupKpClientInn(){
  var inn=document.getElementById('kpc-inn').value.trim();
  if(!inn){toast('Введите ИНН','err');return;}
  try{
    var row=await api('kp.php',{action:'company_lookup_inn',inn:inn});
    if(row.company_type) document.getElementById('kpc-company-type').value=row.company_type;
    updateKpClientTypeUi();
    if(row.company_name) document.getElementById('kpc-company').value=row.company_name;
    if(row.legal_name) document.getElementById('kpc-legal').value=row.legal_name;
    if(row.inn) document.getElementById('kpc-inn').value=row.inn;
    if(row.ogrn) document.getElementById('kpc-ogrn').value=row.ogrn;
    if(row.kpp) document.getElementById('kpc-kpp').value=row.kpp;
    if(row.phone) document.getElementById('kpc-phone').value=row.phone;
    if(row.email) document.getElementById('kpc-email').value=row.email;
    if(row.bank_name) document.getElementById('kpc-bank-name').value=row.bank_name;
    if(row.bank_bik) document.getElementById('kpc-bank-bik').value=row.bank_bik;
    if(row.address) document.getElementById('kpc-address').value=row.address;
    if(row.bank_account) document.getElementById('kpc-bank-account').value=row.bank_account;
    if(row.corr_account) document.getElementById('kpc-corr-account').value=row.corr_account;
    toast('Данные по ИНН загружены ✓');
  }catch(e){toast(e.message,'err');}
}

function renderKpClients(){
  var wrap=document.getElementById('kp-clients-list');
  if(!wrap) return;
  var typeFilter=document.getElementById('kp-client-type-filter');
  var selectedType=typeFilter ? (typeFilter.value||'') : '';
  var searchInput=document.getElementById('kp-client-search');
  var query=searchInput ? String(searchInput.value||'').trim().toLowerCase() : '';
  var typeOrder={person:0,ip:1,ooo:2};
  var rows=kpClients.filter(function(c){
    if(selectedType && (c.company_type||'ooo')!==selectedType) return false;
    if(!query) return true;
    var haystack=[
      c.company_name,c.legal_name,c.recipient_name,c.inn,c.ogrn,c.kpp,
      c.object_address,c.phone,c.email,c.bank_name,c.bank_bik,c.note
    ].map(function(v){return String(v||'').toLowerCase();}).join(' ');
    return haystack.indexOf(query)>=0;
  }).slice().sort(function(a,b){
    var ao=typeOrder[a.company_type||'ooo'];
    var bo=typeOrder[b.company_type||'ooo'];
    if(ao!==bo) return ao-bo;
    return String(a.company_name||'').localeCompare(String(b.company_name||''),'ru',{sensitivity:'base'});
  });
  if(!rows.length){
    var emptyText=!kpClients.length?'Клиентов пока нет':(query?'Клиенты по поиску не найдены':'Клиенты по выбранному типу не найдены');
    wrap.innerHTML='<div class="es">'+emptyText+'</div>';
    return;
  }
  var typeMap={person:'Физ лицо',ip:'ИП',ooo:'ООО'};
  wrap.innerHTML='<div class="pgrid">'+rows.map(function(c){
    var legalName=c.legal_name||c.recipient_name||'—';
    var contact=((c.phone||'')+' '+(c.email||'')).trim()||'—';
    var regData=[c.inn?('ИНН '+c.inn):'',c.ogrn?((c.company_type==='ip'?'ОГРНИП ':'ОГРН ')+c.ogrn):'',c.kpp?('КПП '+c.kpp):''].filter(Boolean).join(' · ')||'—';
    var bankData=[c.bank_name||'',c.bank_bik?('БИК '+c.bank_bik):''].filter(Boolean).join(' · ')||'—';
    return '<div class="ccard fi2 cs-pend">'+
      '<div class="ch"><div><div class="ctitle">'+esc(c.company_name)+'</div><div class="cmark">'+esc(legalName)+'</div></div><span class="kp-link-state linked">'+esc(typeMap[c.company_type]||'ООО')+'</span></div>'+
      '<div class="cmeta">'+
        '<div><div class="mlb">Тип компании</div><div class="mvl">'+esc(typeMap[c.company_type]||'ООО')+'</div></div>'+
        '<div><div class="mlb">Реквизиты</div><div class="mvl">'+esc(regData)+'</div></div>'+
        '<div><div class="mlb">Контакты</div><div class="mvl">'+esc(contact)+'</div></div>'+
        '<div><div class="mlb">Банк</div><div class="mvl">'+esc(bankData)+'</div></div>'+
      '</div>'+
      '<div class="cft">'+(accessCanUi('company','edit')?'<button class="btn btn-g btn-sm" onclick="openKpClientModal('+c.id+')">✏️ Редактировать</button>':'')+(accessCanUi('company','delete')?'<button class="btn btn-rd btn-sm" onclick="deleteKpClient('+c.id+')">🗑 Удалить</button>':'')+'</div>'+
    '</div>';
  }).join('')+'</div>';
}

var kpClientModalKind='client';
function renderKpContractors(){
  var wrap=document.getElementById('kp-contractors-list');
  if(!wrap) return;
  var typeFilter=document.getElementById('kp-contractor-type-filter');
  var selectedType=typeFilter ? (typeFilter.value||'') : '';
  var typeOrder={person:0,ip:1,ooo:2};
  var rows=kpContractors.filter(function(c){
    return !selectedType || (c.company_type||'ooo')===selectedType;
  }).slice().sort(function(a,b){
    var ao=typeOrder[a.company_type||'ooo'];
    var bo=typeOrder[b.company_type||'ooo'];
    if(ao!==bo) return ao-bo;
    return String(a.company_name||'').localeCompare(String(b.company_name||''),'ru',{sensitivity:'base'});
  });
  if(!rows.length){wrap.innerHTML='<div class="es">'+(kpContractors.length?'Подрядчики по выбранному типу не найдены':'Подрядчиков пока нет')+'</div>';return;}
  var typeMap={person:'Физ лицо',ip:'ИП',ooo:'ООО'};
  wrap.innerHTML='<div class="pgrid">'+rows.map(function(c){
    var legalName=c.legal_name||c.recipient_name||'—';
    var contact=((c.phone||'')+' '+(c.email||'')).trim()||'—';
    var regData=[c.inn?('ИНН '+c.inn):'',c.ogrn?((c.company_type==='ip'?'ОГРНИП ':'ОГРН ')+c.ogrn):'',c.kpp?('КПП '+c.kpp):''].filter(Boolean).join(' · ')||'—';
    var bankData=[c.bank_name||'',c.bank_bik?('БИК '+c.bank_bik):''].filter(Boolean).join(' · ')||'—';
    return '<div class="ccard fi2 cs-pend">'+
      '<div class="ch"><div><div class="ctitle">'+esc(c.company_name)+'</div><div class="cmark">'+esc(legalName)+'</div></div><span class="kp-link-state linked">'+esc(typeMap[c.company_type]||'ООО')+'</span></div>'+
      '<div class="cmeta">'+
        '<div><div class="mlb">Тип компании</div><div class="mvl">'+esc(typeMap[c.company_type]||'ООО')+'</div></div>'+
        '<div><div class="mlb">Реквизиты</div><div class="mvl">'+esc(regData)+'</div></div>'+
        '<div><div class="mlb">Контакты</div><div class="mvl">'+esc(contact)+'</div></div>'+
        '<div><div class="mlb">Банк</div><div class="mvl">'+esc(bankData)+'</div></div>'+
      '</div>'+
      '<div class="cft">'+(accessCanUi('company','edit')?'<button class="btn btn-g btn-sm" onclick="openKpContractorModal('+c.id+')">✏️ Редактировать</button>':'')+(accessCanUi('company','delete')?'<button class="btn btn-rd btn-sm" onclick="deleteKpContractor('+c.id+')">🗑 Удалить</button>':'')+'</div>'+
    '</div>';
  }).join('')+'</div>';
}

function openKpClientModal(id){
  kpClientModalKind='client';
  var title=document.getElementById('m-kp-client-title');
  if(!id){
    title.textContent='➕ Клиент';
    ['kpc-id','kpc-company','kpc-legal','kpc-inn','kpc-ogrn','kpc-kpp','kpc-phone','kpc-email','kpc-bank-name','kpc-bank-bik','kpc-address','kpc-passport-series','kpc-passport-number','kpc-passport-issued','kpc-bank-account','kpc-corr-account','kpc-note-legacy'].forEach(function(id){var el=document.getElementById(id); if(el) el.value='';});
    document.getElementById('kpc-company-type').value='person';
    updateKpClientTypeUi();
    om('m-kp-client');
    return;
  }
  var c=kpClients.find(function(x){return x.id==id;});
  if(!c) return;
  var meta=kpParseClientMetaNote(c.note||'');
  title.textContent='✏️ Клиент';
  document.getElementById('kpc-id').value=c.id;
  document.getElementById('kpc-company-type').value=c.company_type||'ooo';
  updateKpClientTypeUi();
  document.getElementById('kpc-company').value=c.company_name||'';
  document.getElementById('kpc-legal').value=c.legal_name||c.recipient_name||c.company_name||'';
  document.getElementById('kpc-inn').value=c.inn||'';
  document.getElementById('kpc-ogrn').value=c.ogrn||'';
  document.getElementById('kpc-kpp').value=c.kpp||'';
  document.getElementById('kpc-phone').value=c.phone||'';
  document.getElementById('kpc-email').value=c.email||'';
  document.getElementById('kpc-bank-name').value=c.bank_name||'';
  document.getElementById('kpc-bank-bik').value=c.bank_bik||'';
  document.getElementById('kpc-address').value=c.object_address||'';
  document.getElementById('kpc-passport-series').value=meta.passport_series||'';
  document.getElementById('kpc-passport-number').value=meta.passport_number||'';
  document.getElementById('kpc-passport-issued').value=meta.passport_issued_by||'';
  document.getElementById('kpc-bank-account').value=meta.bank_account||'';
  document.getElementById('kpc-corr-account').value=meta.corr_account||'';
  document.getElementById('kpc-note-legacy').value=meta.legacy_note||'';
  om('m-kp-client');
}

function openKpContractorModal(id){
  kpClientModalKind='contractor';
  var title=document.getElementById('m-kp-client-title');
  if(!id){
    title.textContent='➕ Подрядчик';
    ['kpc-id','kpc-company','kpc-legal','kpc-inn','kpc-ogrn','kpc-kpp','kpc-phone','kpc-email','kpc-bank-name','kpc-bank-bik','kpc-address','kpc-passport-series','kpc-passport-number','kpc-passport-issued','kpc-bank-account','kpc-corr-account','kpc-note-legacy'].forEach(function(id){var el=document.getElementById(id); if(el) el.value='';});
    document.getElementById('kpc-company-type').value='person';
    updateKpClientTypeUi();
    om('m-kp-client');
    return;
  }
  var c=kpContractors.find(function(x){return x.id==id;});
  if(!c) return;
  var meta=kpParseClientMetaNote(c.note||'');
  title.textContent='✏️ Подрядчик';
  document.getElementById('kpc-id').value=c.id;
  document.getElementById('kpc-company-type').value=c.company_type||'ooo';
  updateKpClientTypeUi();
  document.getElementById('kpc-company').value=c.company_name||'';
  document.getElementById('kpc-legal').value=c.legal_name||c.recipient_name||c.company_name||'';
  document.getElementById('kpc-inn').value=c.inn||'';
  document.getElementById('kpc-ogrn').value=c.ogrn||'';
  document.getElementById('kpc-kpp').value=c.kpp||'';
  document.getElementById('kpc-phone').value=c.phone||'';
  document.getElementById('kpc-email').value=c.email||'';
  document.getElementById('kpc-bank-name').value=c.bank_name||'';
  document.getElementById('kpc-bank-bik').value=c.bank_bik||'';
  document.getElementById('kpc-address').value=c.object_address||'';
  document.getElementById('kpc-passport-series').value=meta.passport_series||'';
  document.getElementById('kpc-passport-number').value=meta.passport_number||'';
  document.getElementById('kpc-passport-issued').value=meta.passport_issued_by||'';
  document.getElementById('kpc-bank-account').value=meta.bank_account||'';
  document.getElementById('kpc-corr-account').value=meta.corr_account||'';
  document.getElementById('kpc-note-legacy').value=meta.legacy_note||'';
  om('m-kp-client');
}

async function saveKpClient(){
  try{
    var isContractor=kpClientModalKind==='contractor';
    var companyType=document.getElementById('kpc-company-type').value;
    var companyName=document.getElementById('kpc-company').value.trim();
    var noteMeta=kpBuildClientMetaNote({
      passport_series:document.getElementById('kpc-passport-series').value.trim(),
      passport_number:document.getElementById('kpc-passport-number').value.trim(),
      passport_issued_by:document.getElementById('kpc-passport-issued').value.trim(),
      bank_account:document.getElementById('kpc-bank-account').value.trim(),
      corr_account:document.getElementById('kpc-corr-account').value.trim(),
      legacy_note:document.getElementById('kpc-note-legacy').value.trim()
    });
    await api('kp.php',{
      action:isContractor?'save_contractor':'save_client',
      id:parseInt(document.getElementById('kpc-id').value||'0',10),
      company_type:companyType,
      company_name:companyName,
      legal_name:companyName,
      recipient_name:companyName,
      inn:companyType==='person' ? '' : document.getElementById('kpc-inn').value.trim(),
      ogrn:companyType==='person' ? '' : document.getElementById('kpc-ogrn').value.trim(),
      kpp:companyType==='ooo' ? document.getElementById('kpc-kpp').value.trim() : '',
      object_address:document.getElementById('kpc-address').value.trim(),
      phone:document.getElementById('kpc-phone').value.trim(),
      email:document.getElementById('kpc-email').value.trim(),
      bank_name:companyType==='person' ? '' : document.getElementById('kpc-bank-name').value.trim(),
      bank_bik:companyType==='person' ? '' : document.getElementById('kpc-bank-bik').value.trim(),
      note:noteMeta
    });
    cm('m-kp-client');
    toast((isContractor?'Подрядчик':'Клиент')+' сохранён');
    if(isContractor) loadKpContractors(true);
    else loadKpClients(true);
  }catch(e){toast(e.message,'err');}
}

async function deleteKpContractor(id){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  if(!confirm('Удалить подрядчика?')) return;
  try{
    await api('kp.php',{action:'delete_contractor',id:id});
    toast('Подрядчик удалён');
    loadKpContractors(true);
  }catch(e){toast(e.message,'err');}
}

function applyKpClientPreset(id){
  var client=kpClients.find(function(x){return String(x.id)===String(id);});
  kpBuilder.client_id=id||'';
  kpBuilder.client_snapshot=client?{
    company_type:client.company_type||'ooo',
    company_name:client.company_name||'',
    legal_name:client.legal_name||'',
    recipient_name:client.recipient_name||client.legal_name||'',
    inn:client.inn||'',
    ogrn:client.ogrn||'',
    kpp:client.kpp||'',
    object_type:client.object_type||'',
    object_address:client.object_address||'',
    phone:client.phone||'',
    email:client.email||'',
    bank_name:client.bank_name||'',
    bank_bik:client.bank_bik||'',
    note:client.note||''
  }:{};
  renderKpBuilderFields();
}
