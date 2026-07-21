// ===================== КАТАЛОГ ТОВАРОВ =====================
var catalogPagination={page:1,perPage:25,total:0,pages:1};
var catalogLastFilterKey='';

function catalogResetPage(){
  catalogPagination.page=1;
}

function catalogPageQuery(){
  return '&page='+encodeURIComponent(catalogPagination.page)+'&per_page='+encodeURIComponent(catalogPagination.perPage);
}

function catalogApplyPagination(meta){
  meta=meta||{};
  catalogPagination.page=parseInt(meta.page||catalogPagination.page||1,10)||1;
  catalogPagination.perPage=parseInt(meta.per_page||catalogPagination.perPage||60,10)||60;
  catalogPagination.total=parseInt(meta.total||0,10)||0;
  catalogPagination.pages=parseInt(meta.pages||1,10)||1;
}

function renderCatalogPager(meta){
  var pager=document.getElementById('gc-pager');
  if(!pager) return;
  if(meta) catalogApplyPagination(meta);
  var total=catalogPagination.total||0;
  var pages=catalogPagination.pages||1;
  var page=catalogPagination.page||1;
  if(!total || pages<=1){
    pager.innerHTML='';
    return;
  }
  var prevDisabled=page<=1?' disabled':'';
  var nextDisabled=page>=pages?' disabled':'';
  pager.innerHTML=
    '<div class="catalog-pager-info">Всего '+esc(total)+' · страница '+esc(page)+' из '+esc(pages)+'</div>'+
    '<div class="catalog-pager-actions">'+
      '<button class="btn btn-g btn-sm" type="button" '+prevDisabled+' onclick="catalogGoPage('+(page-1)+')">Назад</button>'+
      '<button class="btn btn-g btn-sm" type="button" '+nextDisabled+' onclick="catalogGoPage('+(page+1)+')">Вперёд</button>'+
    '</div>';
}

function catalogGoPage(page){
  page=parseInt(page||1,10)||1;
  if(page<1) page=1;
  if(catalogPagination.pages && page>catalogPagination.pages) page=catalogPagination.pages;
  if(page===catalogPagination.page) return;
  catalogPagination.page=page;
  loadCatalog();
}

async function loadCatalog(){
  var ui=getCatalogUi();
  var catId=ui.cat ? ui.cat.value : '', secId=ui.sec.value;
  if(!catId && activePage==='catalog' && !isGeneralCatalogServiceMode(generalCatalogMode)){
    var activeCat=getCategoryByCode(generalCatalogMode);
    catId=activeCat ? String(activeCat.id) : '';
  }
  if(activePage==='catalog' && !isGeneralCatalogServiceMode(generalCatalogMode) && ui.sec && ui.sec.options.length<=1){
    ensureCatalogSectionsOptions(ui, catId);
  }
  var st=ui.st.value, s=ui.search.value.trim();
  var grid=ui.grid;
  if(activePage==='catalog' && isAutoApprovedCatalogCategoryCode(generalCatalogMode)) st='';
  var filterKey=[generalCatalogMode,catId||'',secId||'',st||'',s||''].join('|');
  if(filterKey!==catalogLastFilterKey){
    catalogLastFilterKey=filterKey;
    catalogResetPage();
  }
  grid.innerHTML='<div class="es"><div class="spin" style="margin:0 auto 14px"></div>Загрузка...</div>';
  var pager=document.getElementById('gc-pager');
  if(pager) pager.innerHTML='';
  if(activePage==='catalog' && isGeneralCatalogServiceMode(generalCatalogMode)){
    try{
      if(ui.sec && ui.sec.options.length<=1){
        var workCat=getCategoryByCode(generalCatalogMode);
        if(workCat) ensureCatalogSectionsOptions(ui, String(workCat.id));
      }
      var workSectionCode='';
      var serviceCategory=generalCatalogMode==='construction_works' ? 'construction_works' : '';
      if(generalCatalogMode!=='construction_works' && secId){
        var workSection=(allSecs||[]).find(function(sec){ return String(sec.id)===String(secId); })||null;
        workSectionCode=workSection ? String(workSection.code||'').trim() : '';
      }
      if(generalCatalogMode==='work' && !workSectionCode) serviceCategory='work';
      var serviceUrl=
        'catalog.php?action=services&search='+encodeURIComponent(s)+
        (workSectionCode?'&work_section_code='+encodeURIComponent(workSectionCode):'')+
        (serviceCategory?'&service_category='+encodeURIComponent(serviceCategory):'')+
        catalogPageQuery();
      var serviceResponse=await api(serviceUrl);
      workServices=apiItems(serviceResponse);
      renderCatalogPager(apiPagination(serviceResponse));
      renderWorkServices();
    }catch(e){grid.innerHTML='<div class="es"><div class="ei">⚠️</div>'+esc(e.message)+'</div>';}
    return;
  }
  try{
    var url='catalog.php?action=all_names&category_code='+encodeURIComponent(generalCatalogMode)+catalogPageQuery();
    if(secId) url+='&section_id='+encodeURIComponent(secId);
    if(st) url+='&status='+encodeURIComponent(st);
    if(s) url+='&search='+encodeURIComponent(s);
    var response=await api(url);
    var names=apiItems(response);
    renderCatalogPager(apiPagination(response));
    catalogNames=names; renderCatalog();
  }catch(e){grid.innerHTML='<div class="es"><div class="ei">⚠️</div>'+esc(e.message)+'</div>';}
}

async function reloadCatalogPreserveScroll(){
  var page=document.getElementById('page-catalog');
  var viewport=document.querySelector('.main-scroll') || document.scrollingElement || document.documentElement;
  var pageTop=page ? page.getBoundingClientRect().top : 0;
  var scrollTop=viewport ? viewport.scrollTop : 0;
  await loadCatalog();
  requestAnimationFrame(function(){
    var currentPage=document.getElementById('page-catalog');
    if(!viewport || !currentPage) return;
    var nextTop=currentPage.getBoundingClientRect().top;
    viewport.scrollTop=scrollTop + (nextTop - pageTop);
  });
}

function applyCatalogNamePayloadLocally(id, payload){
  function patchRow(row){
    if(!row || String(row.id)!==String(id)) return row;
    var next=Object.assign({}, row);
    if(Object.prototype.hasOwnProperty.call(payload,'name')) next.name=payload.name;
    if(Object.prototype.hasOwnProperty.call(payload,'status')) next.status=payload.status;
    if(Object.prototype.hasOwnProperty.call(payload,'group_name')) next.group_name=payload.group_name||'';
    if(Object.prototype.hasOwnProperty.call(payload,'supplier')) next.supplier=payload.supplier||'';
    if(Object.prototype.hasOwnProperty.call(payload,'note')) next.note=payload.note||'';
    if(Object.prototype.hasOwnProperty.call(payload,'technical_note')) next.technical_note=payload.technical_note||'';
    if(Object.prototype.hasOwnProperty.call(payload,'marking_size')) next.marking_size=payload.marking_size||'';
    if(Object.prototype.hasOwnProperty.call(payload,'komplektaciya')) next.komplektaciya=payload.komplektaciya||'';
    if(Object.prototype.hasOwnProperty.call(payload,'unit')) next.unit=payload.unit||'';
    if(Object.prototype.hasOwnProperty.call(payload,'purchase_price')) next.purchase_price=payload.purchase_price;
    if(Object.prototype.hasOwnProperty.call(payload,'minimal_price')) next.minimal_price=payload.minimal_price;
    if(Object.prototype.hasOwnProperty.call(payload,'retail_price')) next.retail_price=payload.retail_price;
    if(Object.prototype.hasOwnProperty.call(payload,'price_type')) next.price_type=payload.price_type||'fixed';
    if(Object.prototype.hasOwnProperty.call(payload,'linked_service_ids')){
      next.linked_services=(payload.linked_services||[]).slice();
      next.linked_service_id=parseInt((payload.linked_service_ids||[])[0]||'0',10)||0;
    }else if(Object.prototype.hasOwnProperty.call(payload,'linked_service_id')) next.linked_service_id=parseInt(payload.linked_service_id||'0',10)||0;
    if(Object.prototype.hasOwnProperty.call(payload,'section_id')){
      var sec=(allSecs||[]).find(function(s){ return String(s.id)===String(payload.section_id); })||null;
      if(sec){
        next.section_id=sec.id;
        next.section_name=sec.name||'';
        next.category_id=sec.category_id||next.category_id;
        var cat=(allCats||[]).find(function(c){ return String(c.id)===String(sec.category_id||''); })||null;
        if(cat){
          next.category_code=cat.code||next.category_code;
          next.category_name=cat.name||next.category_name;
        }
      }
    }
    if(Object.prototype.hasOwnProperty.call(payload,'linked_service_ids')){
      var first=(next.linked_services||[])[0]||null;
      next.linked_service_name=first ? (first.name||'') : '';
      next.linked_service_marking_size=first ? (first.marking_size||'') : '';
      next.linked_service_cost=first ? (first.retail_price||0) : 0;
    }else if(Object.prototype.hasOwnProperty.call(payload,'linked_service_id')){
      var svc=(workServices||kpCatalogServices||[]).find(function(s){ return String(s.id)===String(next.linked_service_id||''); })||null;
      next.linked_service_name=svc ? (svc.name||'') : '';
      next.linked_service_marking_size=svc ? (svc.marking_size||'') : '';
      next.linked_service_cost=svc ? ((svc.retail_price!=null?svc.retail_price:svc.cost)||0) : 0;
    }
    return next;
  }
  if(Array.isArray(catalogNames)) catalogNames=catalogNames.map(patchRow);
  if(Array.isArray(allNamesCache)) allNamesCache=allNamesCache.map(patchRow);
}

function rebuildVisibleCatalogNamesFromCache(){
  var ui=getCatalogUi();
  var catId=ui.cat ? ui.cat.value : '', secId=ui.sec.value;
  if(!catId && activePage==='catalog' && !isGeneralCatalogServiceMode(generalCatalogMode)){
    var activeCat=getCategoryByCode(generalCatalogMode);
    catId=activeCat ? String(activeCat.id) : '';
  }
  var st=ui.st.value, s=ui.search.value.trim();
  var names=Array.isArray(allNamesCache) ? allNamesCache.slice() : [];
  if(activePage==='catalog' && !isGeneralCatalogServiceMode(generalCatalogMode)){
    names=names.filter(function(n){return n.category_code===generalCatalogMode;});
  }
  if(catId) names=names.filter(function(n){return n.category_id==catId;});
  if(secId) names=names.filter(function(n){return n.section_id==secId;});
  if(activePage==='catalog' && isAutoApprovedCatalogCategoryCode(generalCatalogMode)) st='';
  if(st) names=names.filter(function(n){return n.status===st;});
  if(s){
    var sl=s.toLowerCase();
    names=names.filter(function(n){
      return n.name.toLowerCase().indexOf(sl)>=0 || n.section_name.toLowerCase().indexOf(sl)>=0;
    });
  }
  catalogNames=names;
}

function catalogNameVisibleNow(row){
  if(!row || activePage!=='catalog' || isGeneralCatalogServiceMode(generalCatalogMode)) return true;
  var ui=getCatalogUi();
  var catId=ui.cat ? ui.cat.value : '';
  if(!catId){
    var activeCat=getCategoryByCode(generalCatalogMode);
    catId=activeCat ? String(activeCat.id) : '';
  }
  var secId=ui.sec ? ui.sec.value : '';
  var st=ui.st ? ui.st.value : '';
  var s=ui.search ? ui.search.value.trim().toLowerCase() : '';
  if(String(row.category_code||'')!==String(generalCatalogMode||'')) return false;
  if(catId && String(row.category_id||'')!==String(catId)) return false;
  if(secId && String(row.section_id||'')!==String(secId)) return false;
  if(isAutoApprovedCatalogCategoryCode(generalCatalogMode)) st='';
  if(st && String(row.status||'')!==String(st)) return false;
  if(s){
    var hay=[row.name,row.marking_size,row.section_name,row.group_name,row.supplier,row.note].join(' ').toLowerCase();
    if(hay.indexOf(s)<0) return false;
  }
  return true;
}

function patchCatalogNameCard(id){
  var card=document.querySelector('[data-catalog-name-id="'+id+'"]');
  var row=(catalogNames||[]).find(function(n){return String(n.id)===String(id);})||null;
  if(row && !catalogNameVisibleNow(row)){
    catalogNames=(catalogNames||[]).filter(function(n){return String(n.id)!==String(id);});
    row=null;
  }
  if(!row){
    if(card) card.remove();
    if(!document.querySelector('#gc-grid .ccard.fi2')) renderCatalog();
    return true;
  }
  if(!card) return false;
  var tmp=document.createElement('div');
  tmp.innerHTML=catalogNameCardHtml(row);
  var next=tmp.firstElementChild;
  if(!next) return false;
  card.replaceWith(next);
  enhanceCatalogCardSelection('name');
  return true;
}

function catalogLinkedServicesFromProduct(product){
  var services=Array.isArray(product&&product.linked_services) ? product.linked_services.slice() : [];
  if(!services.length && product && product.linked_service_id){
    services=[{
      id:product.linked_service_id,
      name:product.linked_service_name||'',
      marking_size:product.linked_service_marking_size||'',
      retail_price:product.linked_service_cost||0,
      purchase_price:product.linked_service_purchase_price,
      unit:product.linked_service_unit||''
    }];
  }
  var seen={};
  return services.filter(function(service){
    var id=parseInt(service&&service.id||0,10)||0;
    if(!id || seen[id]) return false;
    seen[id]=true;
    return true;
  });
}

function catalogServiceLabel(service){
  if(!service) return '';
  return (service.name||'')+
    (service.marking_size?' / '+service.marking_size:'')+
    (service.retail_price!=null&&service.retail_price!==''?' / '+service.retail_price:'');
}

function catalogGetNameEditLinkedServices(){
  var hidden=document.getElementById('ne-linked-service-id');
  if(!hidden) return [];
  try{
    var parsed=JSON.parse(hidden.dataset.services||'[]');
    return Array.isArray(parsed)?parsed:[];
  }catch(e){return [];}
}

function catalogSetNameEditLinkedServices(services){
  var hidden=document.getElementById('ne-linked-service-id');
  var list=document.getElementById('ne-linked-services-list');
  if(!hidden) return;
  var seen={}, normalized=[];
  (services||[]).forEach(function(service){
    var id=parseInt(service&&service.id||0,10)||0;
    if(!id || seen[id]) return;
    seen[id]=true;
    normalized.push({
      id:id,
      name:service.name||'',
      marking_size:service.marking_size||'',
      retail_price:service.retail_price!=null?service.retail_price:(service.cost!=null?service.cost:''),
      purchase_price:service.purchase_price!=null?service.purchase_price:null,
      unit:service.unit||''
    });
  });
  hidden.value=normalized.map(function(service){return service.id;}).join(',');
  hidden.dataset.services=JSON.stringify(normalized);
  if(list){
    list.innerHTML=normalized.length ? normalized.map(function(service){
      return '<div class="linked-service-chip"><span>'+esc(catalogServiceLabel(service))+'</span><button type="button" onclick="catalogRemoveNameEditLinkedService('+service.id+')">×</button></div>';
    }).join('') : '<div class="muted">Работы не выбраны</div>';
  }
}

function catalogGetNameEditLinkedServiceIds(){
  return catalogGetNameEditLinkedServices().map(function(service){return parseInt(service.id||0,10)||0;}).filter(Boolean);
}

function catalogAddNameEditLinkedService(service){
  var list=catalogGetNameEditLinkedServices();
  list.push(service);
  catalogSetNameEditLinkedServices(list);
  var input=document.getElementById('ne-linked-service-name');
  if(input){input.value='';input.dataset.selectedLabel='';}
}

function catalogRemoveNameEditLinkedService(id){
  id=parseInt(id||0,10)||0;
  catalogSetNameEditLinkedServices(catalogGetNameEditLinkedServices().filter(function(service){return parseInt(service.id||0,10)!==id;}));
}

function gcCatChange(){
  var ui=getCatalogUi();
  var catId=ui.cat ? ui.cat.value : '', sel=ui.sec;
  if(!catId && activePage==='catalog' && !isGeneralCatalogServiceMode(generalCatalogMode)){
    var activeCat=getCategoryByCode(generalCatalogMode);
    catId=activeCat ? String(activeCat.id) : '';
  }
  ensureCatalogSectionsOptions(ui, catId);
  if(sel) sel.value='';
  loadCatalog();
  persistNavigationState();
}

function gcSearchFocus(){
  if(activePage==='catalog' && isGeneralCatalogServiceMode(generalCatalogMode)) return;
  gcShowDrop(getCatalogUi().search.value);
}

function gcSearchInput(){
  debounce('gc',loadCatalog);
  debounce('gc-nav',persistNavigationState);
  if(activePage==='catalog' && isGeneralCatalogServiceMode(generalCatalogMode)) return;
  gcShowDrop(getCatalogUi().search.value);
}

function gcShowDrop(val){
  var ui=getCatalogUi();
  var catId=ui.cat ? ui.cat.value : '';
  if(!catId && activePage==='catalog' && !isGeneralCatalogServiceMode(generalCatalogMode)){
    var activeCat=getCategoryByCode(generalCatalogMode);
    catId=activeCat ? String(activeCat.id) : '';
  }
  var secId=ui.sec.value;
  var inp=ui.search;
  var drop=ui.drop;
  if(!drop||!inp) return;

  // Filter names based on category/section and search text
  var filtered=catalogNames.length?catalogNames:[];
  // If catalog not yet loaded or empty, use all names from any prior load
  if(!filtered.length && allNamesCache){
    filtered=allNamesCache;
    if(catId) filtered=filtered.filter(function(n){return n.category_id==catId;});
    if(secId) filtered=filtered.filter(function(n){return n.section_id==secId;});
  }
  filtered=filtered.filter(function(n){return n.status==='Согласовано';});
  var vl=val.toLowerCase();
  if(vl){
    api('catalog.php?action=names_search&q='+encodeURIComponent(val)+(catId?'&category_id='+catId:'')+(secId?'&section_id='+secId:'')).then(function(names){
      gcFillDrop(names, drop, inp, val);
    }).catch(function(){});
    return;
  }

  // Also try server-side if filtered is empty
  if(!filtered.length){
    api('catalog.php?action=names_search&q='+encodeURIComponent(val)+(catId?'&category_id='+catId:'')+(secId?'&section_id='+secId:'')).then(function(names){
      gcFillDrop(names, drop, inp, val);
    }).catch(function(){});
    return;
  }
  gcFillDrop(filtered, drop, inp, val);
}

function gcFillDrop(names, drop, inp, val){
  drop.innerHTML='';
  // Deduplicate by name
  var seen={}, unique=[];
  names.forEach(function(n){if(!seen[n.name]){seen[n.name]=true;unique.push(n);}});
  if(!unique.length){drop.style.display='none';return;}
  unique.slice(0,60).forEach(function(n){
    var div=document.createElement('div');
    div.className='ac-item';
    div.textContent=n.name;
    div.onmousedown=function(e){
      e.preventDefault();
      inp.value=n.name;
      drop.style.display='none';
      loadCatalog();
    };
    drop.appendChild(div);
  });
  var rect=inp.getBoundingClientRect();
  drop.style.top=(rect.bottom+2)+'px';
  drop.style.left=rect.left+'px';
  drop.style.width=Math.max(rect.width,260)+'px';
  drop.style.display='block';
}

var selectedCatalogNameIds={};
var selectedCatalogServiceIds={};

function getCatalogSelectionStore(kind){
  return kind==='service' ? selectedCatalogServiceIds : selectedCatalogNameIds;
}

function getCurrentCatalogSelectionKind(){
  return (activePage==='catalog' && isGeneralCatalogServiceMode(generalCatalogMode)) ? 'service' : 'name';
}

function getCurrentCatalogRows(){
  return getCurrentCatalogSelectionKind()==='service' ? (workServices||[]) : (catalogNames||[]);
}

function getCurrentCatalogSelectedIds(){
  var store=getCatalogSelectionStore(getCurrentCatalogSelectionKind());
  return Object.keys(store).filter(function(id){return !!store[id];});
}

function isCatalogCardSelected(kind,id){
  return !!getCatalogSelectionStore(kind)[String(id)];
}

function toggleCatalogCardSelection(kind,id,checked){
  var store=getCatalogSelectionStore(kind);
  if(checked) store[String(id)]=true;
  else delete store[String(id)];
  updateCatalogBulkDeleteUi();
}

function clearCurrentCatalogSelection(){
  var store=getCatalogSelectionStore(getCurrentCatalogSelectionKind());
  Object.keys(store).forEach(function(id){delete store[id];});
  updateCatalogBulkDeleteUi();
}

function ensureCatalogBulkButtons(){
  var page=document.getElementById('page-catalog');
  if(!page) return;
  var host=page.querySelector('.ph .pa');
  if(!host) return;
  if(!document.getElementById('gc-select-visible-btn')){
    var selectBtn=document.createElement('button');
    selectBtn.className='btn btn-g';
    selectBtn.id='gc-select-visible-btn';
    selectBtn.style.display='none';
    selectBtn.onclick=toggleSelectVisibleCatalogCards;
    host.appendChild(selectBtn);
  }
  if(!document.getElementById('gc-bulk-delete-btn')){
    var deleteBtn=document.createElement('button');
    deleteBtn.className='btn btn-rd';
    deleteBtn.id='gc-bulk-delete-btn';
    deleteBtn.style.display='none';
    deleteBtn.onclick=deleteSelectedCatalogCards;
    host.appendChild(deleteBtn);
  }
}

function updateCatalogBulkDeleteUi(){
  ensureCatalogBulkButtons();
  var selectBtn=document.getElementById('gc-select-visible-btn');
  var deleteBtn=document.getElementById('gc-bulk-delete-btn');
  if(!selectBtn || !deleteBtn) return;
  var canShow=(activePage==='catalog' && canDeleteByRole());
  if(!canShow){
    selectBtn.style.display='none';
    deleteBtn.style.display='none';
    return;
  }
  var rows=getCurrentCatalogRows();
  var selectedIds=getCurrentCatalogSelectedIds();
  var kind=getCurrentCatalogSelectionKind();
  var store=getCatalogSelectionStore(kind);
  var allSelected=!!rows.length && rows.every(function(row){return !!store[String(row.id)];});
  selectBtn.style.display='';
  deleteBtn.style.display='';
  selectBtn.textContent=allSelected ? '☑️ Снять выделение' : '☐ Выделить все';
  deleteBtn.textContent=selectedIds.length ? ('🗑 Удалить выбранные ('+selectedIds.length+')') : '🗑 Удалить выбранные';
  deleteBtn.disabled=!selectedIds.length;
}

function toggleSelectVisibleCatalogCards(){
  if(!canDeleteByRole()) return;
  var rows=getCurrentCatalogRows();
  var kind=getCurrentCatalogSelectionKind();
  var store=getCatalogSelectionStore(kind);
  var allSelected=!!rows.length && rows.every(function(row){return !!store[String(row.id)];});
  rows.forEach(function(row){
    if(allSelected) delete store[String(row.id)];
    else store[String(row.id)]=true;
  });
  if(kind==='service') renderWorkServices();
  else renderCatalog();
}

function enhanceCatalogCardSelection(kind){
  var grid=document.getElementById('gc-grid');
  if(!grid){updateCatalogBulkDeleteUi();return;}
  var rows=kind==='service' ? (workServices||[]) : (catalogNames||[]);
  var cards=grid.querySelectorAll('.ccard');
  Array.prototype.forEach.call(cards,function(card,idx){
    var row=rows[idx];
    if(!row || !canDeleteByRole()) return;
    var header=card.querySelector('.ch');
    if(!header || header.querySelector('.bulk-card-check')) return;
    var first=header.firstElementChild;
    if(!first) return;
    first.style.display='flex';
    first.style.alignItems='flex-start';
    first.style.gap='10px';
    var contentWrap=document.createElement('div');
    contentWrap.style.display='flex';
    contentWrap.style.flexDirection='column';
    contentWrap.style.alignItems='flex-start';
    contentWrap.style.minWidth='0';
    while(first.firstChild){
      contentWrap.appendChild(first.firstChild);
    }
    var label=document.createElement('label');
    label.className='bulk-card-check';
    label.style.display='inline-flex';
    label.style.alignItems='center';
    label.style.justifyContent='center';
    label.style.flex='0 0 auto';
    label.style.marginTop='2px';
    var input=document.createElement('input');
    input.type='checkbox';
    input.checked=isCatalogCardSelected(kind,row.id);
    input.onchange=function(){ toggleCatalogCardSelection(kind,row.id,this.checked); };
    label.appendChild(input);
    first.appendChild(label);
    first.appendChild(contentWrap);
  });
  updateCatalogBulkDeleteUi();
}

async function deleteSelectedCatalogCards(){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  var kind=getCurrentCatalogSelectionKind();
  var ids=getCurrentCatalogSelectedIds();
  if(!ids.length){toast('Ничего не выбрано','err');return;}
  var ok=await showConfirmDialog({
    title: kind==='service' ? 'Удалить выбранные работы' : 'Удалить выбранные товары',
    message: 'Удалить '+ids.length+' карточ'+(ids.length===1?'ку':'ки')+'?',
    icon:'🗑',
    confirmText:'Удалить',
    confirmClass:'btn-rd'
  });
  if(!ok) return;
  try{
    for(var i=0;i<ids.length;i++){
      await api('catalog.php',{action:kind==='service'?'delete_service':'delete_name',id:parseInt(ids[i],10)});
    }
    clearCurrentCatalogSelection();
    if(typeof serviceOptionsCache!=='undefined') serviceOptionsCache=[];
    if(typeof serviceOptionsCacheCategory!=='undefined') serviceOptionsCacheCategory='';
    if(typeof linkableCatalogItems!=='undefined') linkableCatalogItems=[];
    toast('Удалено: '+ids.length+' ✓');
    if(kind==='service'){
      workServices=(workServices||[]).filter(function(row){ return ids.indexOf(String(row.id))<0; });
      ids.forEach(function(id){
        var card=document.querySelector('[data-catalog-service-id="'+id+'"]');
        if(card) card.remove();
      });
      if(!document.querySelector('#gc-grid .ccard.fi2')) renderWorkServices();
    }else{
      catalogNames=(catalogNames||[]).filter(function(row){ return ids.indexOf(String(row.id))<0; });
      if(Array.isArray(allNamesCache)){
        allNamesCache=allNamesCache.filter(function(row){ return ids.indexOf(String(row.id))<0; });
      }
      ids.forEach(function(id){
        var card=document.querySelector('[data-catalog-name-id="'+id+'"]');
        if(card) card.remove();
      });
      if(!document.querySelector('#gc-grid .ccard.fi2')) renderCatalog();
    }
  }catch(e){
    toast((e&&e.message)||'Ошибка удаления','err');
  }
}

function csvEscape(val){
  var s=val==null?'':String(val);
  if(/[;"\r\n,]/.test(s)) return '"'+s.replace(/"/g,'""')+'"';
  return s;
}

function sanitizeFilePart(val){
  return String(val||'')
    .trim()
    .replace(/[\\/:*?"<>|]+/g,' ')
    .replace(/\s+/g,' ')
    .trim() || 'all';
}

function triggerCsvDownload(filename, rows){
  var csv='\uFEFF'+rows.map(function(row){return row.map(csvEscape).join(';');}).join('\r\n');
  var blob=new Blob([csv],{type:'text/csv;charset=utf-8;'});
  var url=URL.createObjectURL(blob);
  var a=document.createElement('a');
  a.href=url;
  a.download=filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(function(){URL.revokeObjectURL(url);},1000);
}

function catalogWorkSectionLabel(code){
  code=String(code||'installation');
  if(code==='construction') return 'Строительные работы';
  if(code==='dismantling') return 'Демонтажные работы';
  return 'Монтажные работы';
}

function catalogExportSectionLabel(ui){
  var sectionLabel='Все разделы';
  if(ui.sec && ui.sec.value && ui.sec.selectedIndex>=0){
    sectionLabel=(ui.sec.options[ui.sec.selectedIndex]||{}).text||sectionLabel;
  }
  return sectionLabel;
}

function catalogExportProductsUrl(ui){
  var secId=ui.sec ? ui.sec.value : '';
  var st=ui.st ? ui.st.value : '';
  var s=ui.search ? ui.search.value.trim() : '';
  if(activePage==='catalog' && isAutoApprovedCatalogCategoryCode(generalCatalogMode)) st='';
  var url='catalog.php?action=all_names&category_code='+encodeURIComponent(generalCatalogMode);
  if(secId) url+='&section_id='+encodeURIComponent(secId);
  if(st) url+='&status='+encodeURIComponent(st);
  if(s) url+='&search='+encodeURIComponent(s);
  return url;
}

function catalogExportServicesUrl(ui){
  var secId=ui.sec ? ui.sec.value : '';
  var s=ui.search ? ui.search.value.trim() : '';
  var workSectionCode='';
  var serviceCategory=generalCatalogMode==='construction_works' ? 'construction_works' : '';
  if(generalCatalogMode!=='construction_works' && secId){
    var workSection=(allSecs||[]).find(function(sec){ return String(sec.id)===String(secId); })||null;
    workSectionCode=workSection ? String(workSection.code||'').trim() : '';
  }
  if(generalCatalogMode==='work' && !workSectionCode) serviceCategory='work';
  return 'catalog.php?action=services&search='+encodeURIComponent(s)+
    (workSectionCode?'&work_section_code='+encodeURIComponent(workSectionCode):'')+
    (serviceCategory?'&service_category='+encodeURIComponent(serviceCategory):'');
}

async function exportGeneralCatalog(){
  if(!accessCanUi('catalog','export')){toast('Нет прав','err');return;}
  var ui=getCatalogUi();
  var sectionLabel=catalogExportSectionLabel(ui);

  if(activePage==='catalog' && isGeneralCatalogServiceMode(generalCatalogMode)){
    var serviceResponse=await api(catalogExportServicesUrl(ui));
    var exportServices=apiItems(serviceResponse);
    if(!exportServices.length){toast('Нет данных для экспорта','err');return;}
    var workRows=[['ID','sort_order','Тип','Раздел','Наименование','Маркировка/Размер','Ед. изм.','Закупочная цена','Минимальная цена','Розничная цена']];
    exportServices.forEach(function(s){
      var workSectionCode=String(s.work_section_code||'installation');
      workRows.push([
        s.id!=null?s.id:'',
        s.sort_order!=null?s.sort_order:'',
        'Работа',
        catalogWorkSectionLabel(workSectionCode),
        s.name||'',
        s.marking_size||'',
        s.unit||'',
        s.purchase_price!=null?s.purchase_price:'',
        s.minimal_price!=null?s.minimal_price:'',
        s.retail_price!=null?s.retail_price:(s.cost!=null?s.cost:'')
      ]);
    });
    triggerCsvDownload('catalog_works_'+sanitizeFilePart(sectionLabel)+'.csv', workRows);
    toast('Экспорт выполнен ✓');
    return;
  }

  var response=await api(catalogExportProductsUrl(ui));
  var exportNames=apiItems(response);
  if(!exportNames.length){toast('Нет данных для экспорта','err');return;}
  var linkedServicesByProduct=exportNames.map(catalogLinkedServicesFromProduct);
  var maxLinkedServices=linkedServicesByProduct.reduce(function(max,services){
    return Math.max(max,services.length);
  },0);
  var header=['ID','sort_order','Тип','Категория','Раздел','Группа','Наименование','Маркировка/Размер','Примечание','Ед. изм.','Закупочная цена','Минимальная цена','Розничная цена','Техничка','Статус','Поставщик'];
  for(var serviceNumber=1;serviceNumber<=maxLinkedServices;serviceNumber++){
    header.push('Работа '+serviceNumber,'Маркировка работы '+serviceNumber);
  }
  var rows=[header];
  exportNames.forEach(function(n){
    var linkedServices=catalogLinkedServicesFromProduct(n);
    var row=[
      n.id!=null?n.id:'',
      n.sort_order!=null?n.sort_order:'',
      'Товар',
      n.category_name||'',
      n.section_name||'',
      n.group_name||'',
      n.name||'',
      n.marking_size||'',
      n.note||'',
      n.unit||'',
      n.purchase_price!=null?n.purchase_price:'',
      n.minimal_price!=null?n.minimal_price:'',
      n.retail_price!=null?n.retail_price:'',
      n.technical_note||'',
      n.status||'',
      n.supplier||''
    ];
    for(var serviceIndex=0;serviceIndex<maxLinkedServices;serviceIndex++){
      var service=linkedServices[serviceIndex]||null;
      row.push(service?(service.name||''):'',service?(service.marking_size||''):'');
    }
    rows.push(row);
  });
  triggerCsvDownload('catalog_'+sanitizeFilePart(generalCatalogMode)+'_'+sanitizeFilePart(sectionLabel)+'.csv', rows);
  toast('Экспорт выполнен ✓');
}

function normalizeCatalogSectionTitle(value){
  return String(value||'')
    .toLowerCase()
    .replace(/ё/g,'е')
    .replace(/\s+/g,' ')
    .trim();
}

function catalogSectionSupportsTechnicalNote(sectionCode){
  sectionCode=String(sectionCode||'').trim().toLowerCase();
  return sectionCode==='grilles'
    || sectionCode==='ventilation'
    || sectionCode==='ventilation_dop'
    || sectionCode==='conditioning'
    || sectionCode==='conditioning_dop'
    || sectionCode==='automation';
}

function catalogBuildWorkServiceCardHtml(s){
  var linkedCount=parseInt(s.linked_products_count||'0',10);
  var isConstruction=String(s.work_section_code||'')==='construction';
  var categoryName=isConstruction?'Строительные работы':'Работы';
  return '<div class="ccard cs-yes fi2" data-catalog-service-id="'+esc(s.id)+'">'+
    '<div class="ch"><div><div class="ctitle">'+esc(s.name)+'</div>'+
    (s.marking_size?'<div class="cmark">'+esc(s.marking_size)+'</div>':'')+
    '</div></div>'+
    '<div class="cmeta">'+
      '<div><div class="mlb">Категория</div><div class="mvl">'+esc(categoryName)+'</div></div>'+
      (isConstruction?'':'<div><div class="mlb">Раздел</div><div class="mvl">'+esc(catalogWorkSectionLabel(s.work_section_code))+'</div></div>')+
      '<div><div class="mlb">Закупочная цена</div><div class="mvl">'+esc(s.purchase_price!=null?s.purchase_price:'—')+'</div></div>'+
      '<div><div class="mlb">Минимальная цена</div><div class="mvl">'+esc(s.minimal_price!=null?s.minimal_price:'—')+'</div></div>'+
      '<div><div class="mlb">Розничная цена</div><div class="mvl">'+esc(s.retail_price!=null?s.retail_price:(s.cost||'—'))+'</div></div>'+
      '<div><div class="mlb">Ед. изм.</div><div class="mvl">'+esc(s.unit||'—')+'</div></div>'+
      (isConstruction?'':'<div><div class="mlb">Привязано товаров</div><div class="mvl">'+esc(linkedCount)+'</div></div>')+
    '</div>'+
    '<div class="cft">'+
      (accessCanUi('catalog','edit')?'<button class="btn btn-g btn-sm" onclick="openCatalogServiceEdit('+s.id+')">\u270f\ufe0f \u0420\u0435\u0434\u0430\u043a\u0442\u0438\u0440\u043e\u0432\u0430\u0442\u044c</button>':'')+
      (accessCanUi('catalog','delete')?'<button class="btn btn-rd btn-sm" onclick="deleteService('+s.id+')">\ud83d\udde1 \u0423\u0434\u0430\u043b\u0438\u0442\u044c</button>':'')+
    '</div></div>';
}

function renderWorkServices(){
  var grid=document.getElementById('gc-grid');
  if(!workServices.length){
    grid.innerHTML='<div class="es"><div class="ei">📭</div><div class="et">Ничего не найдено</div></div>';
    return;
  }
  grid.innerHTML=workServices.map(catalogBuildWorkServiceCardHtml).join('');
  enhanceCatalogCardSelection('service');
}

function catalogBuildServiceFromPayload(id,payload,existing){
  var next=Object.assign({}, existing||{});
  next.id=id;
  next.name=payload.name||next.name||'';
  next.marking_size=payload.marking_size||'';
  next.purchase_price=payload.purchase_price!=='' ? payload.purchase_price : null;
  next.minimal_price=payload.minimal_price!=='' ? payload.minimal_price : null;
  next.retail_price=payload.retail_price!=='' ? payload.retail_price : 0;
  next.cost=next.retail_price;
  next.unit=payload.unit||next.unit||'';
  next.work_section_code=payload.work_section_code||next.work_section_code||'installation';
  next.linked_products_count=next.linked_products_count||0;
  return next;
}

function catalogServiceVisibleNow(service){
  if(!service || activePage!=='catalog' || !isGeneralCatalogServiceMode(generalCatalogMode)) return false;
  var ui=getCatalogUi();
  var search=(ui.search&&ui.search.value||'').trim().toLowerCase();
  var workSectionCode='';
  if(generalCatalogMode!=='construction_works' && ui.sec && ui.sec.value){
    var workSection=(allSecs||[]).find(function(sec){ return String(sec.id)===String(ui.sec.value); })||null;
    workSectionCode=workSection ? String(workSection.code||'').trim() : '';
  }
  if(generalCatalogMode==='work' && !workSectionCode){
    var code=String(service.work_section_code||'installation');
    return code==='installation' || code==='dismantling';
  }
  if(generalCatalogMode==='construction_works') return String(service.work_section_code||'')==='construction';
  if(workSectionCode && String(service.work_section_code||'installation')!==workSectionCode) return false;
  if(search && [service.name,service.marking_size,service.unit].join(' ').toLowerCase().indexOf(search)<0) return false;
  return true;
}

function catalogUpsertWorkServiceCard(id,payload){
  id=parseInt(id||0,10)||0;
  if(!id) return;
  var oldIndex=(workServices||[]).findIndex(function(s){ return String(s.id)===String(id); });
  var service=catalogBuildServiceFromPayload(id,payload,oldIndex>=0?workServices[oldIndex]:null);
  if(oldIndex>=0) workServices[oldIndex]=service;
  else workServices.push(service);
  var grid=document.getElementById('gc-grid');
  if(!grid) return;
  var card=grid.querySelector('[data-catalog-service-id="'+String(id).replace(/"/g,'\\"')+'"]');
  if(!catalogServiceVisibleNow(service)){
    if(card) card.remove();
    return;
  }
  var wrap=document.createElement('div');
  wrap.innerHTML=catalogBuildWorkServiceCardHtml(service);
  var nextCard=wrap.firstElementChild;
  if(card) card.replaceWith(nextCard);
  else{
    if(!grid.querySelector('.ccard')) grid.innerHTML='';
    grid.appendChild(nextCard);
  }
  enhanceCatalogCardSelection('service');
}

function openNameEdit(id){
  var n=catalogNames.find(function(x){return x.id==id;});if(!n)return;
  var isAdmin=true, isRop=true;
  document.getElementById('m-name-edit-title').textContent='✏️ Редактировать товар';
  document.getElementById('ne-id').value=n.id;
  document.getElementById('ne-name').value=n.name;
  document.getElementById('ne-status').value=n.status||'Не согласовано';
  document.getElementById('ne-marking-size').value=n.marking_size||'';
  document.getElementById('ne-komplektaciya').value=n.komplektaciya||'';
  document.getElementById('ne-note').value=n.note||'';
  setSelVal2('ne-unit',n.unit||getDefaultUnit());
  var fcc=document.getElementById('ne-cat');
  fcc.innerHTML=allCats.map(function(c){return '<option value="'+c.id+'"'+(c.id==n.category_id?' selected':'')+'>'+esc(c.name)+'</option>';}).join('');
  neCatChange(n.section_id);
  refreshNameEditGroups(n.group_name||'');
  neUpdateSuppliers(n.supplier||'');
  document.getElementById('ne-purchase-price').value=n.purchase_price||'';
  document.getElementById('ne-retail-price').value=n.retail_price||'';
  document.getElementById('ne-minimal-price').value=n.minimal_price||'';
  document.getElementById('ne-simple-cost').value=n.retail_price||'';
  var priceType=document.getElementById('ne-price-type');
  if(priceType) priceType.value=n.price_type==='percent'?'percent':'fixed';
  catalogSetNameEditLinkedServices(catalogLinkedServicesFromProduct(n));
  document.getElementById('ne-linked-service-name').value='';
  document.getElementById('ne-linked-service-name').dataset.selectedLabel='';
  document.getElementById('ne-status-field').style.display='';
  updateCatalogNoteField();
  updateNameEditModeUi();
  om('m-name-edit');
}

function setSelVal2(id,val){
  var sel=document.getElementById(id);
  for(var i=0;i<sel.options.length;i++){if(sel.options[i].value===val){sel.value=val;return;}}
  if(val){var o=document.createElement('option');o.value=val;o.text=val;sel.appendChild(o);sel.value=val;}
}

function openNameCreate(){
  document.getElementById('m-name-edit-title').textContent='➕ Добавить товар';
  document.getElementById('ne-id').value='';
  document.getElementById('ne-name').value='';
  document.getElementById('ne-marking-size').value='';
  document.getElementById('ne-komplektaciya').value='';
  document.getElementById('ne-note').value='';
  document.getElementById('ne-status').value='Не согласовано';
  document.getElementById('ne-status-field').style.display='';
  var fcc=document.getElementById('ne-cat');
  fcc.innerHTML=allCats.map(function(c){return '<option value="'+c.id+'">'+esc(c.name)+'</option>';}).join('');
  if(activePage==='catalog' && !isGeneralCatalogServiceMode(generalCatalogMode)){
    var cat=getCategoryByCode(generalCatalogMode);
    if(cat) fcc.value=String(cat.id);
  }
  neCatChange();
  refreshNameEditGroups('');
  setSelVal2('ne-unit',getDefaultUnit());
  neUpdateSuppliers('');
  document.getElementById('ne-group').value='';
  document.getElementById('ne-supplier').value='';
  document.getElementById('ne-purchase-price').value='';
  document.getElementById('ne-retail-price').value='';
  document.getElementById('ne-minimal-price').value='';
  document.getElementById('ne-simple-cost').value='';
  var priceType=document.getElementById('ne-price-type');
  if(priceType) priceType.value='fixed';
  catalogSetNameEditLinkedServices([]);
  document.getElementById('ne-linked-service-name').value='';
  document.getElementById('ne-linked-service-name').dataset.selectedLabel='';
  updateCatalogNoteField();
  updateNameEditModeUi();
  om('m-name-edit');
}

function openGeneralCatalogCreate(){
  if(isGeneralCatalogServiceMode(generalCatalogMode)) openCatalogServiceCreate();
  else openNameCreate();
}

function neCatChange(preselect){
  var catId=document.getElementById('ne-cat').value;
  var sel=document.getElementById('ne-sec');
  sel.innerHTML=allSecs.filter(function(s){return s.category_id==catId;}).map(function(s){
    return '<option value="'+s.id+'"'+(preselect&&s.id==preselect?' selected':'')+'>'+esc(s.name)+'</option>';
  }).join('');
  var lbl=document.getElementById('ne-marking-size-label');
  var inp=document.getElementById('ne-marking-size');
  if(lbl){lbl.textContent='Маркировка/Размер';}
  if(inp){inp.placeholder='Например: 100x200 или DN50';}
  // Обновляем кэш привязки работ для нового раздела
  serviceOptionsCache=[];
  serviceOptionsCacheCategory='';
  neUpdateSuppliers();
  refreshNameEditGroups();
  updateCatalogNoteField();
  updateNameEditModeUi();
}

function neUpdateSuppliers(currentVal){
  var secId = parseInt(document.getElementById('ne-sec').value) || 0;
  var neSup = document.getElementById('ne-supplier');
  if (!neSup) return;
  var savedVal = currentVal !== undefined ? currentVal : neSup.value;
  // Показываем поставщиков с учётом привязки к разделу
  var list = allSuppliers.filter(function(sup){
    if (!sup.name) return false;
    if (!secId) return true;
    if (!sup.section_ids) return false;
    var ids = String(sup.section_ids).split(',').map(Number);
    return ids.indexOf(secId) >= 0;
  });
  var options=['<option value="">— не указан —</option>'].concat(list.map(function(s){
    return '<option value="'+esc(s.name)+'"'+(s.name===savedVal?' selected':'')+'>'+esc(s.name)+'</option>';
  }));
  // Если сохранённый поставщик не входит в список, оставляем его отдельной опцией
  if (savedVal && !list.find(function(s){return s.name===savedVal;})) {
    options.push('<option value="'+esc(savedVal)+'" selected>'+esc(savedVal)+' ⚠️</option>');
  }
  neSup.innerHTML=options.join('');
}

async function saveNameEdit(){
  var id=parseInt(document.getElementById('ne-id').value);
  var isAdmin=CU.role==='admin', isRop=CU.role==='rop';
  var catCode=getSelectedNameEditCategoryCode();
  var isSimple=isSimpleCatalogCategoryCode(catCode);
  var isKit=catCode==='kits';
  var isIncidental=catCode==='incidental_expenses';
  var isConsumables=catCode==='consumables';
  var supplier=document.getElementById('ne-supplier').value;
  var markingSize=document.getElementById('ne-marking-size').value.trim();
  var unit=document.getElementById('ne-unit').value;
  var payload={action:id?'update_name':'create_name',id:id,supplier:supplier,marking_size:markingSize,komplektaciya:document.getElementById('ne-komplektaciya').value.trim(),unit:unit,group_name:document.getElementById('ne-group').value.trim(),note:document.getElementById('ne-note-field').style.display==='none'?'':document.getElementById('ne-note').value.trim()};
  if(true){
    var name=document.getElementById('ne-name').value.trim();
    if(!name){toast('Название обязательно','err');return;}
    payload.name=name;
    payload.status=isAutoApprovedCatalogCategoryCode(catCode)?'Согласовано':document.getElementById('ne-status').value;
    payload.section_id=parseInt(document.getElementById('ne-sec').value);
  } else if(false){
    payload.status=isAutoApprovedCatalogCategoryCode(catCode)?'Согласовано':document.getElementById('ne-status').value;
  }
  if(activePage==='catalog'){
    if(isKit){
      payload.supplier='';
      payload.group_name=payload.group_name||'комплекты';
      payload.note='';
      payload.purchase_price='';
      payload.minimal_price='';
      payload.retail_price=document.getElementById('ne-simple-cost').value;
      payload.linked_service_ids=[];
      payload.linked_services=[];
    }else if(isSimple){
      payload.supplier='';
      payload.marking_size='';
      payload.unit='';
      payload.note='';
      payload.purchase_price='';
      payload.minimal_price='';
      payload.retail_price=document.getElementById('ne-simple-cost').value;
      payload.linked_service_id=0;
      payload.price_type='fixed';
    }else if(isConsumables){
      payload.note='';
      payload.purchase_price='';
      payload.minimal_price='';
      payload.retail_price='';
      payload.price_type='fixed';
      payload.linked_service_ids=[];
      payload.linked_services=[];
    }else if(isIncidental){
      payload.supplier='';
      payload.price_type=(document.getElementById('ne-price-type')||{}).value==='percent'?'percent':'fixed';
      payload.purchase_price=payload.price_type==='percent'?'':document.getElementById('ne-purchase-price').value;
      payload.retail_price=document.getElementById('ne-retail-price').value;
      payload.minimal_price=payload.price_type==='percent'?'':document.getElementById('ne-minimal-price').value;
      payload.linked_service_ids=[];
      payload.linked_services=[];
    }else{
      payload.purchase_price=document.getElementById('ne-purchase-price').value;
      payload.retail_price=document.getElementById('ne-retail-price').value;
      payload.minimal_price=document.getElementById('ne-minimal-price').value;
      payload.price_type='fixed';
      payload.linked_service_ids=catalogGetNameEditLinkedServiceIds();
      payload.linked_services=catalogGetNameEditLinkedServices();
    }
  }
  try{
    var saved=await api('catalog.php',payload);
    serviceOptionsCache=[];
    serviceOptionsCacheCategory='';
    if(id){
      applyCatalogNamePayloadLocally(id,payload);
      if(!patchCatalogNameCard(id)) await reloadCatalogPreserveScroll();
    }else{
      await reloadCatalogPreserveScroll();
    }
    toast('Сохранено ✓');cm('m-name-edit');
  }catch(e){toast(e.message,'err');}
}

function openCatalogTechnicalModal(id){
  var n=catalogNames.find(function(x){return x.id==id;});
  if(!n) return;
  document.getElementById('tn-id').value=n.id;
  document.getElementById('tn-text').value=n.technical_note||'';
  document.getElementById('m-tech-note-title').textContent='Техничка: '+(n.name||'');
  om('m-tech-note');
}

async function saveCatalogTechnicalNote(){
  var id=parseInt(document.getElementById('tn-id').value||'0',10);
  if(!id) return;
  try{
    await api('catalog.php',{action:'update_name',id:id,technical_note:document.getElementById('tn-text').value});
    toast('Сохранено ✓');
    cm('m-tech-note');
    applyCatalogNamePayloadLocally(id,{technical_note:document.getElementById('tn-text').value});
  }catch(e){toast(e.message,'err');}
}

function updateCatalogNoteField(){
  var field=document.getElementById('ne-note-field');
  if(!field) return;
  var categoryCode=getSelectedNameEditCategoryCode();
  field.style.display=(categoryCode==='equipment' || categoryCode==='materials')?'':'none';
}


function catalogNameCardHtml(n){
  var isNo=n.status==='Не согласовано';
  var needsService=(n.category_code==='equipment' || n.category_code==='materials');
  var linkedServices=catalogLinkedServicesFromProduct(n);
  var isLinked=linkedServices.length>0;
  var linkedServicesText=linkedServices.length?linkedServices.map(catalogServiceLabel).join(', '):'—';
  var isPend=!isNo && needsService && !isLinked;
  var cc=isNo?'cs-no':(isPend?'cs-pend':'cs-yes');
  var bc=isNo?'b-no':'b-yes';
  var badge=n.status||'Не согласовано';
  var canManage=true;
  var supportsTech=catalogSectionSupportsTechnicalNote(n.section_code||'');
  var noteHtml=(n.category_code==='equipment' || n.category_code==='materials')
    ? '<div><div class="mlb">Примечание</div><div class="mvl">'+esc(n.note||'—')+'</div></div>'
    : '';
  var isGeneralCatalog=activePage==='catalog';
  var isSimple=isSimpleCatalogCategoryCode(n.category_code);
  var isKit=n.category_code==='kits';
  var isIncidental=n.category_code==='incidental_expenses';
  var isConsumables=n.category_code==='consumables';
  var isAutoApproved=isAutoApprovedCatalogCategoryCode(n.category_code);
  if(isAutoApproved){
    isNo=false; isPend=false; cc='cs-yes'; bc='b-yes'; badge='Согласовано';
  }
  var statusHtml=isAutoApproved ? '' : (canManage
    ? '<select class="sbadge '+bc+' status-pill-select" onchange="updateCatalogStatus('+n.id+',this.value,this)"><option class="status-opt-no" style="background:rgba(239,68,68,.18);color:#f87171" value="Не согласовано"'+(badge==='Не согласовано'?' selected':'')+'>Не согласовано</option><option class="status-opt-yes" style="background:rgba(34,197,94,.18);color:#4ade80" value="Согласовано"'+(badge==='Согласовано'?' selected':'')+'>Согласовано</option></select>'
    : '<span class="sbadge '+bc+'">'+esc(badge)+'</span>');
  return '<div class="ccard '+cc+' fi2" data-catalog-name-id="'+esc(n.id)+'">'+
    '<div class="ch"><div><div class="ctitle">'+esc(n.name)+'</div>'+(n.marking_size?'<div class="cmark">'+esc(n.marking_size)+'</div>':'')+'</div>'+statusHtml+'</div>'+
    '<div class="cmeta">'+
      '<div><div class="mlb">Категория</div><div class="mvl">'+esc(n.category_name)+'</div></div>'+
      (isKit?'':'<div><div class="mlb">Раздел</div><div class="mvl">'+esc(n.section_name)+'</div></div>')+
      '<div><div class="mlb">Группа</div><div class="mvl">'+esc(n.group_name||'—')+'</div></div>'+
      noteHtml+
      (isConsumables
        ? '<div><div class="mlb">Маркировка/Размер</div><div class="mvl">'+esc(n.marking_size||'—')+'</div></div>'+ 
          '<div><div class="mlb">Комплектация</div><div class="mvl">'+esc(n.komplektaciya||'—')+'</div></div>'+ 
          '<div><div class="mlb">Ед. изм.</div><div class="mvl">'+esc(n.unit||'—')+'</div></div>'+ 
          '<div><div class="mlb">Поставщик</div><div class="mvl">'+esc(n.supplier||'—')+'</div></div>'
        : isKit
        ? '<div><div class="mlb">Маркировка</div><div class="mvl">'+esc(n.marking_size||'—')+'</div></div>'+
          '<div><div class="mlb">Ед. изм.</div><div class="mvl">'+esc(n.unit||'—')+'</div></div>'+
          '<div><div class="mlb">Цена</div><div class="mvl">'+esc(n.retail_price||'—')+'</div></div>'
        : isIncidental
        ? '<div><div class="mlb">Ед. изм.</div><div class="mvl">'+esc(n.unit||'—')+'</div></div>'+
          (isGeneralCatalog&&n.price_type!=='percent'?'<div><div class="mlb">Закупочная цена</div><div class="mvl">'+esc(n.purchase_price||'—')+'</div></div>':'')+
          (isGeneralCatalog&&n.price_type!=='percent'?'<div><div class="mlb">Минимальная цена</div><div class="mvl">'+esc(n.minimal_price||'—')+'</div></div>':'')+
          (isGeneralCatalog?'<div><div class="mlb">'+(n.price_type==='percent'?'Процент от суммы':'Цена')+'</div><div class="mvl">'+esc(n.retail_price||'—')+(n.price_type==='percent'?'%':'')+'</div></div>':'')
        : isSimple
        ? '<div><div class="mlb">Стоимость</div><div class="mvl">'+esc(n.retail_price||'—')+'</div></div>'
        : '<div><div class="mlb">Ед. изм.</div><div class="mvl">'+esc(n.unit||'—')+'</div></div>'+
          '<div><div class="mlb">Поставщик</div><div class="mvl">'+esc(n.supplier||'—')+'</div></div>'+
          (isGeneralCatalog?'<div><div class="mlb">Закупочная цена</div><div class="mvl">'+esc(n.purchase_price||'—')+'</div></div>':'')+
          (isGeneralCatalog?'<div><div class="mlb">Минимальная цена</div><div class="mvl">'+esc(n.minimal_price||'—')+'</div></div>':'')+
          (isGeneralCatalog?'<div><div class="mlb">Розничная цена</div><div class="mvl">'+esc(n.retail_price||'—')+'</div></div>':'')+
          (isGeneralCatalog?'<div><div class="mlb">Работы</div><div class="mvl">'+esc(linkedServicesText)+'</div></div>':'')
      )+
    '</div>'+
    '<div class="cft">'+
      (supportsTech&&accessCanUi('catalog','edit')?'<button class="btn btn-cy btn-sm" onclick="openCatalogTechnicalModal('+n.id+')">Техничка</button>':'')+
      (accessCanUi('catalog','edit')?'<button class="btn btn-g btn-sm" onclick="openNameEdit('+n.id+')">✏️ Редактировать</button>':'')+
      (accessCanUi('catalog','delete')?'<button class="btn btn-rd btn-sm" onclick="deleteCatalogName('+n.id+')">🗑 Удалить</button>':'')+
    '</div></div>';
}

function renderCatalog(){
  var grid=getCatalogUi().grid;
  if(!catalogNames.length){grid.innerHTML='<div class="es"><div class="ei">📭</div><div class="et">Ничего не найдено</div></div>';return;}
  grid.innerHTML=catalogNames.map(catalogNameCardHtml).join('');
  enhanceCatalogCardSelection('name');
}

async function loadLinkableCatalogItems(q){
  var query=(q||'').trim();
  if(!query && linkableCatalogItems.length) return linkableCatalogItems;
  var items=await api('catalog.php?action=linkable_catalog_items'+(query?'&q='+encodeURIComponent(query):''));
  if(!query) linkableCatalogItems=items;
  return items;
}

async function loadServiceOptions(q){
  var query=(q||'').trim();
  var catCode='';
  if(!query && serviceOptionsCache.length && serviceOptionsCacheCategory===catCode) return serviceOptionsCache;
  var items=await api('catalog.php?action=services'+(query?'&search='+encodeURIComponent(query):''));
  if(!query){
    serviceOptionsCache=items;
    serviceOptionsCacheCategory=catCode;
  }
  return items;
}

function fillAutocompleteList(drop, items, selectedId, onPick, toLabel){
  drop.innerHTML='';
  drop.onmousedown=function(e){e.stopPropagation();};
  drop.onclick=function(e){e.stopPropagation();};
  var empty=document.createElement('div');
  empty.className='ac-item';
  empty.textContent='— не указано —';
  empty.onmousedown=function(e){e.preventDefault();e.stopPropagation();markAutocompleteTransition(220);onPick(0,'');drop.style.display='none';};
  drop.appendChild(empty);
  items.forEach(function(item){
    var div=document.createElement('div');
    div.className='ac-item'+(String(item.id)===String(selectedId||'')?' sel':'');
    div.textContent=toLabel(item);
    div.onmousedown=function(e){
      e.preventDefault();
      e.stopPropagation();
      markAutocompleteTransition(220);
      onPick(item.id, toLabel(item));
      drop.style.display='none';
    };
    drop.appendChild(div);
  });
}

function showDropNearInput(input, drop){
  var rect=input.getBoundingClientRect();
  drop.style.top=(rect.bottom+2)+'px';
  drop.style.left=rect.left+'px';
  drop.style.width=Math.max(rect.width,260)+'px';
  drop.style.display='block';
}

async function serviceSearchInput(val){
  var input=document.getElementById('ne-linked-service-name');
  var drop=document.getElementById('ne-linked-service-drop');
  var items=await loadServiceOptions(val);
  var selectedIds=catalogGetNameEditLinkedServiceIds().map(String);
  items=(items||[]).filter(function(item){ return selectedIds.indexOf(String(item.id||''))<0; });
  fillAutocompleteList(drop, items, '', function(id,label){
    var service=(items||[]).find(function(item){ return String(item.id||'')===String(id||''); })||null;
    if(service) catalogAddNameEditLinkedService(service);
    input.value='';
    input.dataset.selectedLabel='';
  }, function(item){
    return catalogServiceLabel(item);
  });
  showDropNearInput(input, drop);
}

function serviceSearchFocus(){
  var input=document.getElementById('ne-linked-service-name');
  if(input && input.value && catalogGetNameEditLinkedServiceIds().length) input.value='';
  serviceSearchInput(input ? input.value : '');
}

function openCatalogServiceCreate(){
  window.catalogServiceEditContext='catalog';
  document.getElementById('m-service-edit-title').textContent='➕ Добавить работу';
  document.getElementById('se-id').value='';
  document.getElementById('se-name').value='';
  document.getElementById('se-marking').value='';
  document.getElementById('se-purchase').value='';
  document.getElementById('se-minimal').value='';
  document.getElementById('se-retail').value='';
  var seUnit=document.getElementById('se-unit');
  if(seUnit && !seUnit.options.length){
    seUnit.innerHTML=(UNITS||[]).map(function(u){return '<option value="'+esc(u)+'">'+esc(u)+'</option>';}).join('');
  }
  if(document.getElementById('se-unit').options.length) document.getElementById('se-unit').value=getDefaultUnit();
  syncServiceWorkSectionOptions(generalCatalogMode==='construction_works'?'construction':'installation');
  om('m-service-edit');
}

function syncServiceWorkSectionOptions(selected){
  var sel=document.getElementById('se-work-section');
  if(!sel) return;
  var isConstruction=generalCatalogMode==='construction_works' || String(selected||'')==='construction';
  var field=sel.closest ? sel.closest('.field') : null;
  if(field) field.style.display=isConstruction?'none':'';
  var options=isConstruction
    ? [{code:'construction',name:'Строительные работы'}]
    : [{code:'installation',name:'Монтажные работы'},{code:'dismantling',name:'Демонтажные работы'}];
  sel.innerHTML=options.map(function(opt){
    return '<option value="'+opt.code+'">'+esc(opt.name)+'</option>';
  }).join('');
  var desired=String(selected||options[0].code);
  sel.value=options.some(function(opt){return opt.code===desired;}) ? desired : options[0].code;
}

function openCatalogServiceEdit(id){
  window.catalogServiceEditContext='catalog';
  var seUnit=document.getElementById('se-unit');
  if(seUnit && !seUnit.options.length){
    seUnit.innerHTML=(UNITS||[]).map(function(u){return '<option value="'+esc(u)+'">'+esc(u)+'</option>';}).join('');
  }
  var service=workServices.find(function(s){return s.id==id;});
  if(!service) return;
  document.getElementById('m-service-edit-title').textContent='✏️ Редактировать работу';
  document.getElementById('se-id').value=service.id;
  document.getElementById('se-name').value=service.name||'';
  document.getElementById('se-marking').value=service.marking_size||'';
  document.getElementById('se-purchase').value=service.purchase_price!=null?service.purchase_price:'';
  document.getElementById('se-minimal').value=service.minimal_price!=null?service.minimal_price:'';
  document.getElementById('se-retail').value=service.retail_price!=null?service.retail_price:(service.cost||'');
  document.getElementById('se-unit').value=service.unit||getDefaultUnit();
  syncServiceWorkSectionOptions(service.work_section_code||'installation');
  om('m-service-edit');
}

async function saveCatalogServiceEdit(){
  var id=parseInt(document.getElementById('se-id').value||'0',10);
  var isConstruction=generalCatalogMode==='construction_works' || document.getElementById('se-work-section').value==='construction';
  var payload={
    action:id?'update_service':'create_service',
    id:id,
    name:document.getElementById('se-name').value.trim(),
    marking_size:document.getElementById('se-marking').value.trim(),
    purchase_price:document.getElementById('se-purchase').value,
    minimal_price:document.getElementById('se-minimal').value,
    retail_price:document.getElementById('se-retail').value,
    unit:document.getElementById('se-unit').value,
    work_section_code:isConstruction?'construction':document.getElementById('se-work-section').value
  };
  if(!payload.name){toast('Название обязательно','err');return;}
  try{
    var saved=await api('catalog.php',payload);
    serviceOptionsCache=[];
    serviceOptionsCacheCategory='';
    linkableCatalogItems=[];
    toast('Сохранено ✓');
    cm('m-service-edit');
    catalogUpsertWorkServiceCard(id || (saved&&saved.id), payload);
  }catch(e){toast(e.message,'err');}
}


function applyStatusSelectColor(el,status){
  if(!el) return;
  el.classList.remove('b-no','b-yes');
  el.classList.add(status==='\u0421\u043e\u0433\u043b\u0430\u0441\u043e\u0432\u0430\u043d\u043e'?'b-yes':'b-no');
}

function patchCatalogNameCardStatus(id,status){
  var card=document.querySelector('[data-catalog-name-id="'+id+'"]');
  if(!card) return false;
  var row=(catalogNames||[]).find(function(n){return String(n.id)===String(id);})||null;
  if(!row){
    card.remove();
    if(!document.querySelector('#gc-grid .ccard.fi2')) renderCatalog();
    return true;
  }
  var isNo=status!=='\u0421\u043e\u0433\u043b\u0430\u0441\u043e\u0432\u0430\u043d\u043e';
  var needsService=(row.category_code==='equipment' || row.category_code==='materials');
  var isPend=!isNo && needsService && !catalogLinkedServicesFromProduct(row).length;
  card.classList.remove('cs-no','cs-pend','cs-yes');
  card.classList.add(isNo?'cs-no':(isPend?'cs-pend':'cs-yes'));
  var select=card.querySelector('.status-pill-select');
  if(select){
    select.value=status;
    applyStatusSelectColor(select,status);
  }
  return true;
}

async function updateCatalogStatus(id,status,el){
  applyStatusSelectColor(el,status);
  try{
    await api('catalog.php',{action:'update_name',id:id,status:status});
    applyCatalogNamePayloadLocally(id,{status:status});
    if(!patchCatalogNameCardStatus(id,status)) await reloadCatalogPreserveScroll();
  }catch(e){
    toast(e.message,'err');
    await reloadCatalogPreserveScroll();
  }
}


async function saveServiceEdit(){
  return saveCatalogServiceEdit();
}

function openServiceCreate(){
  return openCatalogServiceCreate();
}

function openServiceEdit(id){
  return openCatalogServiceEdit(id);
}


function ensureCatalogSectionsOptions(ui, catId){
  var sel=ui && ui.sec ? ui.sec : null;
  if(!sel) return;
  var prevValue=sel.value||'';
  var options=['<option value="">\u0412\u0441\u0435 \u0440\u0430\u0437\u0434\u0435\u043b\u044b</option>'];
  if(catId) options=options.concat((allSecs||[])
    .filter(function(s){
      if(!(s.category_id==catId && s.name)) return false;
      if(activePage==='catalog' && generalCatalogMode==='work') return String(s.code||'')!=='construction';
      if(activePage==='catalog' && generalCatalogMode==='construction_works') return String(s.code||'')==='construction';
      return true;
    })
    .map(function(s){return '<option value="'+s.id+'">'+esc(s.name)+'</option>';}));
  sel.innerHTML=options.join('');
  if(prevValue){
    var hasPrev=Array.prototype.some.call(sel.options,function(opt){
      return String(opt.value)===String(prevValue);
    });
    sel.value=hasPrev ? prevValue : '';
  }
}
