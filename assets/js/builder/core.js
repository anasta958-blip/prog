// ===================== DOC BUILDER =====================
function isKpTarget(t){return typeof t==='string' && t.indexOf('kp:')===0;}
function kpTargetIndex(t){return parseInt(String(t).split(':')[1]||'0',10)||0;}
function kpTargetName(vi){return 'kp:'+vi;}
function builderIsWorkCategoryCode(code){return code==='work' || code==='construction_works';}
function kpGetWorkScopeCode(sec){
  var code=String((sec && sec.secCode) || '').trim().toLowerCase();
  var id=String((sec && sec.secId) || '').trim().toLowerCase();
  if(code==='installation' || code==='construction' || code==='dismantling') return code;
  if(id==='installation' || id==='construction' || id==='dismantling') return id;
  if(code==='materials' || code==='equipment') return code;
  if(id==='materials' || id==='equipment') return id;
  return '';
}
function kpGetServiceWorkSectionCode(service){
  var code=String((service && service.work_section_code) || '').trim().toLowerCase();
  return code || 'installation';
}
function renderTargetBuilder(t){
  var result;
  if(t==='oe'){
    result=renderOEBuilder();
    enhanceBuilderFolding(document.getElementById('oe-docbuilder'), t);
  }else if(isKpTarget(t)){
    result=renderKpVariantCats(kpTargetIndex(t));
    enhanceBuilderFolding(document.getElementById('kp-variants-wrap'), t);
  }else{
    result=renderDocBuilder();
    enhanceBuilderFolding(document.getElementById('doc-builder'), t);
  }
  stripNumericFieldDecimals(document);
  if(t==='oe' && typeof scheduleOrderBuilderDraftSave==='function') scheduleOrderBuilderDraftSave('edit');
  if(t==='doc' && typeof scheduleOrderBuilderDraftSave==='function') scheduleOrderBuilderDraftSave('create');
  if(isKpTarget(t) && typeof scheduleKpBuilderDraftSave==='function') scheduleKpBuilderDraftSave();
  return result;
}
function kpNormalizeBuilderItem(item, catCode, catName, secId, secName, secCode){
  item=item||{};
  var normalizedCatCode=item.category_code||catCode||'';
  var isKit=normalizedCatCode==='kits';
  var qty = (item.quantity===undefined || item.quantity===null || item.quantity==='') ? 1 : item.quantity;
  var hasBasePrice=item.base_price!==undefined && item.base_price!==null && item.base_price!=='';
  var fallbackRetail=item.retail_price!=null && item.retail_price!=='' ? item.retail_price : ((item.final_price!=null && item.final_price!=='') ? item.final_price : 0);
  if(isKit && !hasBasePrice && fallbackRetail===0 && item.price!=null && item.price!=='') fallbackRetail=item.price;
  return {
    uid:item.uid||('kp-'+Date.now()+'-'+Math.random().toString(36).slice(2,8)),
    item_type:item.item_type||(builderIsWorkCategoryCode(catCode)?'work':'product'),
    is_auto:!!item.is_auto,
    manual_price_override:!!item.manual_price_override,
    auto_from_uid:item.auto_from_uid||'',
    auto_source_links:Array.isArray(item.auto_source_links)?item.auto_source_links.map(function(link){
      return {uid:link&&link.uid?String(link.uid):'', quantity:Math.max(parseFloat((link&&link.quantity)!=null?link.quantity:0)||0,0)};
    }).filter(function(link){return !!link.uid;}):[],
    suppress_auto_work:!!item.suppress_auto_work,
    product_name_id:item.product_name_id||item.nameId||0,
    service_id:item.service_id||0,
    category_id:item.category_id||0,
    category_code:normalizedCatCode,
    category_name:item.category_name||catName||kpBuilderCategoryLabel(catCode||''),
    catalog_status:item.catalog_status||item.status||'',
    section_id:item.section_id!=null?item.section_id:secId,
    section_name:item.section_name||secName||'',
    section_code:item.section_code||secCode||'',
    group_name:isKit?'комплекты':(item.group_name||''),
    nameId:item.product_name_id||item.nameId||0,
    nameTxt:item.name||item.nameTxt||'',
    isCustom:!!item.isCustom,
    name:item.name||item.nameTxt||'',
    marking_size:item.marking_size||'',
    quantity:qty,
    unit:item.unit||getDefaultUnit(),
    note:item.note||'',
    supplier:isKit?'':(item.supplier||((item.item_type||(builderIsWorkCategoryCode(catCode)?'work':'product'))==='work'?'':'не указан')),
    purchase_price:isKit?0:(item.purchase_price!=null?item.purchase_price:null),
    minimal_price:item.minimal_price!=null?item.minimal_price:null,
    retail_price:item.retail_price!=null?item.retail_price:null,
    price_type:item.price_type==='percent'?'percent':'fixed',
    base_price:hasBasePrice?item.base_price:fallbackRetail,
    markup_value:item.markup_value||0,
    discount_value:item.discount_value||0,
    excluded_from_calc:!!item.excluded_from_calc,
    external_touched:!!(item.external_touched||item.rop_external_touched),
    linked_service_id:isKit?0:(item.linked_service_id||0),
    linked_service_name:isKit?'':(item.linked_service_name||''),
    linked_service_cost:isKit?0:(item.linked_service_cost||0),
    linked_services:isKit?[]:(Array.isArray(item.linked_services)?item.linked_services.slice():[]),
    auto_standard_price:item.auto_standard_price!=null?item.auto_standard_price:null,
    linked_service_purchase_price:isKit?null:(item.linked_service_purchase_price!=null?item.linked_service_purchase_price:null),
    linked_service_unit:isKit?'':(item.linked_service_unit||''),
    markingSizeOptions:item.markingSizeOptions||[],
    komplektaciyaOptions:item.komplektaciyaOptions||[]
  };
}
function kpItemsToCats(items){
  var cats=[];
  (items||[]).forEach(function(raw){
    var catCode=raw.category_code||((raw.item_type==='work')?(String(raw.section_code||raw.section_id||'')==='construction'?'construction_works':'work'):'equipment');
    var catName=raw.category_name||kpBuilderCategoryLabel(catCode);
    var secId=(raw.section_id!=null && raw.section_id!=='')?raw.section_id:(catCode==='kits'?'kits_main':'');
    var secCode=raw.section_code||String(secId||'');
    var secName=raw.section_name||(
      builderIsWorkCategoryCode(catCode)
        ? (String(secId)==='installation'?'Монтажные работы'
          :(String(secId)==='construction'?'Строительные работы'
            :(String(secId)==='dismantling'?'Демонтажные работы'
              :(String(secId)==='materials'?'Материалы':'Оборудование'))))
        : (catCode==='maintenance'?'Обслуживание':(catCode==='kits'?'Комплекты':''))
    );
    var cat=cats.find(function(x){return x.catCode===catCode;});
    if(!cat){
      cat={catId:raw.category_id||0,catName:catName,catCode:catCode,sections:[]};
      cats.push(cat);
    }
    var sec=cat.sections.find(function(x){return String(x.secId)===String(secId);});
    if(!sec){
      sec={secId:secId,secName:secName,secCode:secCode,isDozakaz:false,groups:[],items:[]};
      cat.sections.push(sec);
    }
    if(!Array.isArray(sec.groups)) sec.groups=[];
    sec.items.push(kpNormalizeBuilderItem(raw,catCode,catName,secId,secName,secCode));
  });
  kpSortBuilderCats(cats);
  return cats;
}
function kpCatsToItems(cats){
  var items=[];
  (cats||[]).forEach(function(cat){
    (cat.sections||[]).forEach(function(sec){
      (sec.items||[]).forEach(function(item){
        items.push(kpNormalizeBuilderItem(item,cat.catCode,cat.catName,sec.secId,sec.secName,sec.secCode));
      });
    });
  });
  return items;
}
function kpEnsureVariantCats(vi){
  ensureKpVariants();
  var v=kpBuilder.variants[vi];
  if(!v.cats){
    v.cats=(v.items&&v.items.length)?kpItemsToCats(v.items):[];
  }
  return v.cats;
}
function getCats(t){
  if(t==='oe') return oeCats;
  if(isKpTarget(t)) return kpEnsureVariantCats(kpTargetIndex(t));
  return docCats;
}
function setCats(t,v){
  if(t==='oe'){oeCats=v;return;}
  if(isKpTarget(t)){
    var vi=kpTargetIndex(t);
    ensureKpVariants();
    kpBuilder.variants[vi].cats=v;
    kpBuilder.variants[vi].items=kpCatsToItems(v);
    return;
  }
  docCats=v;
}

function docAddCat(){_addCatModal('doc');}
function oeAddCat(){_addCatModal('oe');}
function openActiveKpCategoryModal(){
  _addCatModal(kpTargetName(kpBuilder.active_variant_index||0));
}
function _addCatModal(t){
  pCatTarget=t;
  var sel=document.getElementById('dc-cat');
  var options=['<option value="">Выберите...</option>'];
  var cats=getCats(t);
  if(isKpTarget(t)){
    kpVisibleBuilderCategories().forEach(function(code){
      if(!cats.find(function(x){return x.catCode===code;})){
        options.push('<option value="'+code+'" data-code="'+code+'">'+esc(kpBuilderCategoryLabel(code))+'</option>');
      }
    });
  }else{
    allCats.forEach(function(c){
      if((t==='doc' || t==='oe') && (c.code==='construction_works' || c.code==='incidental_expenses')) return;
      if((t==='doc' || t==='oe') && c.code==='work') return;
      if(!cats.find(function(x){return x.catId==c.id;}))
        options.push('<option value="'+c.id+'" data-code="'+c.code+'">'+esc(c.name)+'</option>');
    });
  }
  sel.innerHTML=options.join('');
  om('m-add-cat');
}
async function confirmDocCat(){
  var sel=document.getElementById('dc-cat'),v=sel.value;if(!v){toast('Выберите категорию','err');return;}
  var opt=sel.options[sel.selectedIndex];
  var cats=getCats(pCatTarget);
  var newCat={catId:isKpTarget(pCatTarget)?0:parseInt(v),catName:opt.text,catCode:opt.getAttribute('data-code'),sections:[]};
  cats.push(newCat);
  if(isKpTarget(pCatTarget) && !kpCatalogSections.length){
    try{ await loadKpCatalogSections(); }catch(e){}
  }
  if(isKpTarget(pCatTarget)) kpSortBuilderCats(cats);
  var nextCi=cats.indexOf(newCat);
  var autoSections=isKpTarget(pCatTarget)
    ? ((newCat.catCode==='maintenance' && !kpCatalogSections.some(function(s){return s.category_code==='maintenance';}))
      ? [{id:'maintenance_main',name:'Обслуживание',code:'maintenance_main'}]
      : (typeof kpGetBuilderSections==='function'
        ? kpGetBuilderSections(newCat.catCode)
        : kpCatalogSections.filter(function(s){return s.category_code===newCat.catCode && s.name;}).map(function(s){return {id:s.id,name:s.name,code:s.code};})))
    : allSecs.filter(function(s){return s.category_id==newCat.catId && s.name;}).map(function(s){return {id:s.id,name:s.name,code:s.code||''};});
  if(autoSections.length===1){
    var secMeta=autoSections[0];
    newCat.sections.push({
      secId:isKpTarget(pCatTarget)&&isNaN(parseInt(secMeta.id,10))?secMeta.id:parseInt(secMeta.id,10),
      secName:secMeta.name,
      secCode:secMeta.code||'',
      isDozakaz:secMeta.name==='Дозаказ расходного материала',
      groups:[],
      items:[]
    });
    addBuilderItemData(pCatTarget,nextCi,0,'');
  }
  cm('m-add-cat');
  if(!appendBuilderCategoryDom(pCatTarget,nextCi) && !rerenderBuilderCategory(pCatTarget,nextCi)) renderTargetBuilder(pCatTarget);
}

function confirmDocSec(){
  var sel=document.getElementById('dc-sec'),v=sel.value;if(!v){toast('Выберите раздел','err');return;}
  var opt=sel.options[sel.selectedIndex];
  var secCode=opt.getAttribute('data-code')||'';
  if(getCats(pSecTarget)[pSecCatIdx].sections.find(function(x){
    return String(x.secId)===String(v) || (secCode && String(x.secCode||'')===String(secCode));
  })){ toast('Раздел уже добавлен','err'); return; }
  getCats(pSecTarget)[pSecCatIdx].sections.push({secId:isKpTarget(pSecTarget)&&isNaN(parseInt(v,10))?v:parseInt(v),secName:opt.text,secCode:secCode,isDozakaz:opt.text==='Дозаказ расходного материала',groups:[],items:[]});
  var nextSi=getCats(pSecTarget)[pSecCatIdx].sections.length-1;
  var nextIi=addBuilderItemData(pSecTarget,pSecCatIdx,nextSi,'');
  cm('m-add-sec');
  builderFoldState.cats[builderCatFoldKey(pSecTarget,pSecCatIdx)]=false;
  if(!appendBuilderSectionDom(pSecTarget,pSecCatIdx,nextSi)) renderTargetBuilder(pSecTarget);
  setTimeout(function(){
    var groupEl=document.getElementById('grp-'+pSecTarget+'-'+pSecCatIdx+'-'+nextSi+'-'+nextIi+'-inp');
    if(groupEl){
      groupEl.focus();
      showGroupDrop(pSecTarget,pSecCatIdx,nextSi,nextIi,groupEl.value||'');
      return;
    }
    var nameEl=document.getElementById('ac-'+pSecTarget+'-'+pSecCatIdx+'-'+nextSi+'-'+nextIi+'-inp');
    if(nameEl){
      nameEl.focus();
      if(nameEl.select) nameEl.select();
      showNameDrop(pSecTarget,pSecCatIdx,nextSi,nextIi,nameEl.value||'');
    }
  },60);
}

function openAddGroupModal(t,ci,si){
  pGroupTarget=t; pGroupCatIdx=ci; pGroupSecIdx=si;
  var sec=((getCats(t)[ci]||{}).sections||[])[si];
  if(!sec) return;
  if(!Array.isArray(sec.groups)) sec.groups=[];
  var sel=document.getElementById('dc-group');
  var options=['<option value="">Выберите...</option>'];
  getSectionGroupOptions(sec.secId).filter(function(name){
    return sec.groups.indexOf(name)<0;
  }).forEach(function(name){
    options.push('<option value="'+esc(name)+'">'+esc(name)+'</option>');
  });
  sel.innerHTML=options.join('');
  om('m-add-group');
}
function confirmDocGroup(){
  var sel=document.getElementById('dc-group'),v=(sel.value||'').trim();
  if(!v){toast('Выберите группу','err');return;}
  var sec=((getCats(pGroupTarget)[pGroupCatIdx]||{}).sections||[])[pGroupSecIdx];
  if(!sec) return;
  if(!Array.isArray(sec.groups)) sec.groups=[];
  if(sec.groups.indexOf(v)<0) sec.groups.push(v);
  cm('m-add-group');
  builderFoldState.secs[builderSecFoldKey(pGroupTarget,pGroupCatIdx,pGroupSecIdx)]=false;
  addFromList(pGroupTarget,pGroupCatIdx,pGroupSecIdx,v);
}
function removeGroup(t,ci,si,groupName){
  var sec=((getCats(t)[ci]||{}).sections||[])[si];
  if(!sec) return;
  showConfirm('Удалить группу','Удалить группу «'+groupName+'» и все её товары?',function(){
    var removedItems=(sec.items||[]).filter(function(item){ return String(item.group_name||'')===String(groupName); });
    var workCatIdx=-1;
    if(isKpTarget(t)){
      workCatIdx=(getCats(t)||[]).findIndex(function(cat){ return cat && builderIsWorkCategoryCode(cat.catCode); });
      removedItems.forEach(function(item){
        if(item && item.uid){
          if(item.is_auto) kpSuppressAutoWorkForAutoItem(kpTargetIndex(t), item);
          kpRemoveAutoWorksBySource(kpTargetIndex(t), item.uid);
        }
      });
    }
    if(!Array.isArray(sec.groups)) sec.groups=[];
    sec.groups=sec.groups.filter(function(name){ return String(name)!==String(groupName); });
    sec.items=(sec.items||[]).filter(function(item){ return String(item.group_name||'')!==String(groupName); });
    var synced=rerenderBuilderSection(t,ci,si);
    if(isKpTarget(t) && workCatIdx>=0){
      synced=rerenderBuilderCategory(t,workCatIdx) || synced;
    }
    if(!synced) renderTargetBuilder(t);
    else if(isKpTarget(t)){
      kpRefreshSectionTotal(t,ci,si);
      kpRefreshVariantSummaryByTarget(t);
      kpRefreshAllVariantsSummary(kpTargetIndex(t));
    }
  });
}
  
// "Из списка" — directly adds empty row with autocomplete
function addFromList(t,ci,si,groupName){
  var ii=addBuilderItemData(t,ci,si,groupName);
  builderFoldState.secs[builderSecFoldKey(t,ci,si)]=false;
  if(!appendBuilderRowDom(t,ci,si) && !rerenderBuilderSection(t,ci,si)) renderTargetBuilder(t);
  setTimeout(function(){
    var groupEl=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
    if(groupEl){
      groupEl.focus();
      showGroupDrop(t,ci,si,ii,groupEl.value||'');
      return;
    }
    var wraps=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
    if(wraps) wraps.focus();
  },50);
  return;
  var isOE=t==='oe';
  var isKP=isKpTarget(t);
  var ii=getCats(t)[ci].sections[si].items.length;
  var montageStatuses=['Монтаж','Монтаж завершён','Выполнено'];
  var curStatus=isOE&&document.getElementById('oe-status')?document.getElementById('oe-status').value:'';
  var dozakazFlag=isOE&&montageStatuses.indexOf(curStatus)>=0?1:0;
  var cat=getCats(t)[ci], sec=getCats(t)[ci].sections[si];
  getCats(t)[ci].sections[si].items.push(
    isKP
      ? kpNormalizeBuilderItem({quantity:1,note:'',supplier:'',base_price:0,markup_value:0,discount_value:0},cat.catCode,cat.catName,sec.secId,sec.secName,sec.secCode)
      : {nameId:null,nameTxt:'',isCustom:false,marking_size:'',quantity:'',unit:getDefaultUnit(),note:'',supplier:'',komplektaciya:'',dozakaz:dozakazFlag,invoice_check:'',shipment_status:'',markingSizeOptions:[],komplektaciyaOptions:[]}
  );
  getCats(t)[ci].sections[si].items[ii].unit=getDefaultUnit();
  builderFoldState.secs[builderSecFoldKey(t,ci,si)]=false;
  if(!rerenderBuilderSection(t,ci,si)) renderTargetBuilder(t);
  // Focus the last name input
  setTimeout(function(){
    var wraps=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
    if(wraps) wraps.focus();
  },50);
}

function showConfirm(title, msg, cb){
  showConfirmDialog({title:title,message:msg,icon:'🗑️',confirmText:'Удалить',confirmClass:'btn-rd'}).then(function(ok){
    if(ok) cb();
  });
}
var confirmDialogResolver=null;
function closeConfirmDialog(result){
  var overlay=document.getElementById('m-confirm-delete');
  overlay.classList.remove('open');
  delete overlay.dataset.preventBackdropClose;
  if(confirmDialogResolver){
    var resolve=confirmDialogResolver;
    confirmDialogResolver=null;
    resolve(!!result);
  }
}
function showConfirmDialog(opts){
  opts=opts||{};
  var overlay=document.getElementById('m-confirm-delete');
  if(opts.dismissible===false) overlay.dataset.preventBackdropClose='1';
  else delete overlay.dataset.preventBackdropClose;
  document.getElementById('cd-icon').textContent=opts.icon||'⚠️';
  document.getElementById('cd-title').textContent=opts.title||'Подтвердите действие';
  document.getElementById('cd-msg').textContent=opts.message||'Продолжить?';
  var cancelBtn=document.getElementById('cd-cancel-btn');
  var confirmBtn=document.getElementById('cd-confirm-btn');
  cancelBtn.textContent=opts.cancelText||'Отмена';
  confirmBtn.textContent=opts.confirmText||'Подтвердить';
  confirmBtn.className='btn '+(opts.confirmClass||'btn-rd');
  return new Promise(function(resolve){
    confirmDialogResolver=resolve;
    om('m-confirm-delete');
  });
}
function builderSelectDomPart(v){
  return String(v).replace(/[^a-zA-Z0-9_-]/g,'_');
}
function builderSectionSelectAllId(t,ci,si){
  return 'builder-section-select-all-'+builderSelectDomPart(t)+'-'+ci+'-'+si;
}
function builderRowSelectId(t,ci,si,ii){
  return 'builder-row-select-'+builderSelectDomPart(t)+'-'+ci+'-'+si+'-'+ii;
}
function builderToggleSectionSelection(t,ci,si,checked){
  if(isKpTarget(t) && typeof kpToggleSectionSelection==='function'){
    kpToggleSectionSelection(t,ci,si,checked);
    return;
  }
  var prefix='builder-row-select-'+builderSelectDomPart(t)+'-'+ci+'-'+si+'-';
  document.querySelectorAll('input[id^="'+prefix+'"]').forEach(function(cb){
    cb.checked=!!checked;
  });
}
function builderSyncSectionSelectionState(t,ci,si){
  if(isKpTarget(t) && typeof kpSyncSectionSelectionState==='function'){
    kpSyncSectionSelectionState(t,ci,si);
    return;
  }
  var all=document.getElementById(builderSectionSelectAllId(t,ci,si));
  if(!all) return;
  var prefix='builder-row-select-'+builderSelectDomPart(t)+'-'+ci+'-'+si+'-';
  var boxes=[].slice.call(document.querySelectorAll('input[id^="'+prefix+'"]'));
  if(!boxes.length){
    all.checked=false;
    all.indeterminate=false;
    return;
  }
  var checked=boxes.filter(function(cb){return cb.checked;}).length;
  all.checked=checked===boxes.length;
  all.indeterminate=checked>0 && checked<boxes.length;
}
var builderItemDragState=null;
function builderItemDragStart(e,t,ci,si,ii){
  builderItemDragState={t:String(t),ci:parseInt(ci,10),si:parseInt(si,10),ii:parseInt(ii,10)};
  if(e&&e.dataTransfer){
    e.dataTransfer.effectAllowed='move';
    try{e.dataTransfer.setData('text/plain', JSON.stringify(builderItemDragState));}catch(_e){}
  }
  var row=e&&e.target&&e.target.closest ? e.target.closest('tr') : null;
  if(row) row.classList.add('builder-row-dragging');
}
function builderItemDragEnd(){
  document.querySelectorAll('.builder-row-drop-before,.builder-row-drop-after,.builder-row-dragging').forEach(function(row){
    row.classList.remove('builder-row-drop-before','builder-row-drop-after','builder-row-dragging');
  });
  builderItemDragState=null;
}
function builderItemDragOver(e,t,ci,si,ii){
  if(!builderItemDragState) return;
  if(String(builderItemDragState.t)!==String(t) || builderItemDragState.ci!==parseInt(ci,10) || builderItemDragState.si!==parseInt(si,10)) return;
  e.preventDefault();
  if(e.dataTransfer) e.dataTransfer.dropEffect='move';
  var row=e.currentTarget;
  if(!row) return;
  row.classList.remove('builder-row-drop-before','builder-row-drop-after');
  var rect=row.getBoundingClientRect();
  row.classList.add(e.clientY>rect.top+(rect.height/2)?'builder-row-drop-after':'builder-row-drop-before');
}
function builderItemDragLeave(e){
  var row=e&&e.currentTarget;
  if(row) row.classList.remove('builder-row-drop-before','builder-row-drop-after');
}
function builderItemDrop(e,t,ci,si,ii){
  if(!builderItemDragState) return;
  e.preventDefault();
  var row=e.currentTarget;
  var rect=row.getBoundingClientRect();
  var insertIndex=parseInt(ii,10)+(e.clientY>rect.top+(rect.height/2)?1:0);
  var from=builderItemDragState;
  builderItemDragEnd();
  if(String(from.t)!==String(t) || from.ci!==parseInt(ci,10) || from.si!==parseInt(si,10)) return;
  builderMoveItemWithinSection(t,ci,si,from.ii,insertIndex);
}
function builderMoveItemWithinSection(t,ci,si,fromIndex,insertIndex){
  var sec=(((getCats(t)||[])[ci]||{}).sections||[])[si];
  if(!sec || !Array.isArray(sec.items)) return false;
  fromIndex=parseInt(fromIndex,10);
  insertIndex=parseInt(insertIndex,10);
  if(!isFinite(fromIndex) || !isFinite(insertIndex)) return false;
  if(fromIndex<0 || fromIndex>=sec.items.length) return false;
  insertIndex=Math.max(0, Math.min(insertIndex, sec.items.length));
  if(insertIndex===fromIndex || insertIndex===fromIndex+1) return false;
  var moved=sec.items.splice(fromIndex,1)[0];
  if(fromIndex<insertIndex) insertIndex--;
  sec.items.splice(insertIndex,0,moved);
  if(isKpTarget(t)) kpSyncVariantFromCats(kpTargetIndex(t));
  if(!rerenderBuilderSection(t,ci,si)) renderTargetBuilder(t);
  else if(isKpTarget(t)){
    kpRefreshSectionTotal(t,ci,si);
    kpRefreshCategorySummary(t,ci);
    kpRefreshVariantSummaryByTarget(t);
    kpRefreshAllVariantsSummary(kpTargetIndex(t));
  }
  return true;
}
function builderGetSelectedSectionItemIndexes(t,ci,si){
  var sec=(((getCats(t)||[])[ci]||{}).sections||[])[si];
  if(!sec || !Array.isArray(sec.items)) return [];
  var indexes=[];
  sec.items.forEach(function(_item,ii){
    var id=isKpTarget(t) && typeof kpDomKey==='function'
      ? 'kp-row-check-'+kpDomKey(t,ci,si,ii)
      : builderRowSelectId(t,ci,si,ii);
    var cb=document.getElementById(id);
    if(cb && cb.checked) indexes.push(ii);
  });
  return indexes;
}
function removeSelectedItems(t,ci,si){
  if(document.activeElement && typeof document.activeElement.blur==='function'){
    document.activeElement.blur();
  }
  var indexes=builderGetSelectedSectionItemIndexes(t,ci,si);
  if(!indexes.length){
    toast('\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0442\u043e\u0432\u0430\u0440\u044b \u0434\u043b\u044f \u0443\u0434\u0430\u043b\u0435\u043d\u0438\u044f','err');
    return;
  }
  showConfirm('\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0432\u044b\u0431\u0440\u0430\u043d\u043d\u044b\u0435','\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0432\u044b\u0431\u0440\u0430\u043d\u043d\u044b\u0435 \u0442\u043e\u0432\u0430\u0440\u044b: '+indexes.length+'?',function(){
    var sec=(((getCats(t)||[])[ci]||{}).sections||[])[si];
    if(!sec || !Array.isArray(sec.items)) return;
    var selected={};
    indexes.forEach(function(ii){ selected[ii]=true; });
    var removedItems=sec.items.filter(function(_item,ii){ return !!selected[ii]; });
    var workCatIdx=-1;
    if(isKpTarget(t)){
      workCatIdx=(getCats(t)||[]).findIndex(function(cat){ return cat && builderIsWorkCategoryCode(cat.catCode); });
      removedItems.forEach(function(item){
        if(item && item.uid){
          if(item.is_auto) kpSuppressAutoWorkForAutoItem(kpTargetIndex(t), item);
          kpRemoveAutoWorksBySource(kpTargetIndex(t), item.uid);
        }
      });
    }
    sec.items=sec.items.filter(function(_item,ii){ return !selected[ii]; });
    if(isKpTarget(t)) kpSyncVariantFromCats(kpTargetIndex(t));
    var synced=rerenderBuilderSection(t,ci,si);
    if(isKpTarget(t) && workCatIdx>=0){
      synced=rerenderBuilderCategory(t,workCatIdx) || synced;
    }
    if(!synced) renderTargetBuilder(t);
    else if(isKpTarget(t)){
      kpRefreshSectionTotal(t,ci,si);
      kpRefreshCategorySummary(t,ci);
      if(workCatIdx>=0 && workCatIdx!==ci) kpRefreshCategorySummary(t,workCatIdx);
      kpRefreshVariantSummaryByTarget(t);
      kpRefreshAllVariantsSummary(kpTargetIndex(t));
    }
  });
}
function removeCat(t,ci){
  var name=getCats(t)[ci].catName||'категорию';
  showConfirm('Удалить категорию','Удалить категорию «'+name+'» и все её разделы?',function(){
    var removedCat=getCats(t)[ci];
    var removedItems=removedCat && Array.isArray(removedCat.sections)
      ? removedCat.sections.reduce(function(acc, sec){
          return acc.concat((sec && Array.isArray(sec.items)) ? sec.items.slice() : []);
        },[])
      : [];
    if(isKpTarget(t)){
      removedItems.forEach(function(item){
        if(item && item.uid){
          if(item.is_auto) kpSuppressAutoWorkForAutoItem(kpTargetIndex(t), item);
          kpRemoveAutoWorksBySource(kpTargetIndex(t), item.uid);
        }
      });
    }
    getCats(t).splice(ci,1);
      renderTargetBuilder(t);
      if(isKpTarget(t)){
        kpRefreshVariantSummaryByTarget(t);
        kpRefreshAllVariantsSummary(kpTargetIndex(t));
      }
  });
}
function removeSec(t,ci,si){
  var name=getCats(t)[ci].sections[si].secName||'раздел';
  showConfirm('Удалить раздел','Удалить раздел «'+name+'» и все его товары?',function(){
    var sec=((getCats(t)[ci]||{}).sections||[])[si];
    var removedItems=(sec && Array.isArray(sec.items)) ? sec.items.slice() : [];
    var workCatIdx=-1;
    if(isKpTarget(t)){
      workCatIdx=(getCats(t)||[]).findIndex(function(cat){ return cat && builderIsWorkCategoryCode(cat.catCode); });
      removedItems.forEach(function(item){
        if(item && item.uid){
          if(item.is_auto) kpSuppressAutoWorkForAutoItem(kpTargetIndex(t), item);
          kpRemoveAutoWorksBySource(kpTargetIndex(t), item.uid);
        }
      });
    }
    getCats(t)[ci].sections.splice(si,1);
    var synced=rerenderBuilderCategory(t,ci);
    if(isKpTarget(t) && workCatIdx>=0 && workCatIdx!==ci){
      synced=rerenderBuilderCategory(t,workCatIdx) || synced;
    }
    if(!synced) renderTargetBuilder(t);
    else if(isKpTarget(t)){
      kpRefreshCategorySummary(t,ci);
      if(workCatIdx>=0 && workCatIdx!==ci) kpRefreshCategorySummary(t,workCatIdx);
      kpRefreshVariantSummaryByTarget(t);
      kpRefreshAllVariantsSummary(kpTargetIndex(t));
    }
  });
}
function removeItem(t,ci,si,ii,confirmed){
  if(document.activeElement && typeof document.activeElement.blur==='function'){
    document.activeElement.blur();
  }
  if(!confirmed && !(window.navigator && window.navigator.webdriver)){
    var name=getCats(t)[ci].sections[si].items[ii].nameTxt||'\u0442\u043e\u0432\u0430\u0440';
    showConfirm('\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0442\u043e\u0432\u0430\u0440','\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u00ab'+name+'\u00bb \u0438\u0437 \u0441\u043f\u0438\u0441\u043a\u0430?',function(){
      removeItem(t,ci,si,ii,true);
    });
    return;
  }
  var removed=getCats(t)[ci].sections[si].items[ii];
  var autoPosBefore=(isKpTarget(t) && removed && removed.uid) ? kpFindAutoItemPosition(kpTargetIndex(t), removed.uid) : null;
  var workCatIdx=(isKpTarget(t)) ? (getCats(t)||[]).findIndex(function(cat){ return cat && builderIsWorkCategoryCode(cat.catCode); }) : -1;
  if(isKpTarget(t) && removed && removed.is_auto){
    kpSuppressAutoWorkForAutoItem(kpTargetIndex(t), removed);
  }
  getCats(t)[ci].sections[si].items.splice(ii,1);
  if(isKpTarget(t) && removed && removed.uid){
    kpRemoveAutoWorksBySource(kpTargetIndex(t), removed.uid);
    kpSyncVariantFromCats(kpTargetIndex(t));
    var syncedAfterRemove=rerenderBuilderSection(t,ci,si);
    if(autoPosBefore){
      var autoStillExists=(((getCats(t)[autoPosBefore.ci]||{}).sections||[])[autoPosBefore.si]||{}).items;
      if(autoStillExists){
        syncedAfterRemove=rerenderBuilderSection(t,autoPosBefore.ci,autoPosBefore.si) || syncedAfterRemove;
      }else if(workCatIdx>=0){
        syncedAfterRemove=rerenderBuilderCategory(t,workCatIdx) || syncedAfterRemove;
      }
    }
    if(!syncedAfterRemove) renderTargetBuilder(t);
    else{
      kpRefreshSectionTotal(t,ci,si);
      if(workCatIdx>=0) kpRefreshCategorySummary(t,workCatIdx);
      kpRefreshVariantSummaryByTarget(t);
      kpRefreshAllVariantsSummary(kpTargetIndex(t));
    }
    return;
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
function builderItemHasCatalogIdentity(item){
  if(!item) return false;
  if(parseInt(item.product_name_id||item.nameId||item.service_id||0,10)>0) return true;
  return !!(String(item.nameTxt||item.name||'').trim() && String(item.marking_size||'').trim());
}
function builderShouldMarkExternalTouched(t){
  if(isKpTarget(t)) return typeof kpShouldMarkExternalTouched==='function' && kpShouldMarkExternalTouched();
  if(t==='oe') return !!(CU && parseInt(oeOwnerUserId||0,10)>0 && parseInt(oeOwnerUserId||0,10)!==parseInt(CU.id||0,10));
  return false;
}
function builderMarkExternalTouched(t,item){
  if(!item || !builderShouldMarkExternalTouched(t)) return;
  if(isKpTarget(t)){
    if(!kpIsPendingCatalogItem(item)) item.external_touched=true;
    return;
  }
  if(t==='oe' && builderItemHasCatalogIdentity(item)) item.external_touched=true;
}
function updItem(t,ci,si,ii,f,v){
  var item=getCats(t)[ci].sections[si].items[ii];
  item[f]=v;
  builderMarkExternalTouched(t,item);
}

async function syncItemCatalogDataDocLike(t,ci,si,ii){
  var item=getCats(t)[ci].sections[si].items[ii];
  var cat=getCats(t)[ci];
  var sec=getCats(t)[ci].sections[si];
  var secId=sec.secId;
  if(!item||!item.nameTxt||!secId) return;
  if(cat && builderIsWorkCategoryCode(cat.catCode)){
    try{
      await builderEnsureCatalogServicesLoaded();
      var variants=(kpCatalogServices||[]).filter(function(service){
        return builderServiceMatchesSection(service,sec) &&
          kpCatalogNorm(service.name||'')===kpCatalogNorm(item.nameTxt||item.name||'');
      });
      item.markingSizeOptions=[...new Set(variants.map(function(service){return service.marking_size||'';}).filter(Boolean))];
      var selected=null;
      var hasMarking=kpCatalogNorm(item.marking_size||'')!=='';
      var markingVariants=variants.filter(function(service){
        return kpCatalogNorm(service.marking_size||'')===kpCatalogNorm(item.marking_size||'');
      });
      if(hasMarking && markingVariants.length===1) selected=markingVariants[0];
      else if(hasMarking && markingVariants.length>1) selected=markingVariants.find(function(service){
        return kpCatalogNorm(service.unit||'')===kpCatalogNorm(item.unit||'');
      })||markingVariants[0]||null;
      if(!selected && variants.length===1 && item.markingSizeOptions.length<=1){
        selected=variants[0];
        item.marking_size=selected.marking_size||'';
        var msInp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
        if(msInp) msInp.value=item.marking_size||'';
      }
      if(selected){
        builderApplyServiceToItem(t,ci,si,ii,selected);
        var unitEl=document.getElementById('unit-'+t+'-'+ci+'-'+si+'-'+ii);
        if(unitEl){
          kpSyncSelectValue(unitEl, item.unit||'', item.unit||getDefaultUnit());
          kpDeduplicateSelectOptions(unitEl);
        }
      }else{
        item.service_id=0;
      }
    }catch(e){}
    return;
  }
  if(String(item.item_type||'product')!=='work' && !catalogGroupNorm(item.group_name||'')){
    item.markingSizeOptions=[];
    item.nameId=null;
    item.product_name_id=0;
    return;
  }
  try{
    var rows=await api('catalog.php?action=names&section_id='+secId+'&group_name='+encodeURIComponent(catalogGroupToken(item.group_name||'')));
    var variants=rows.filter(function(r){
      return r.name===item.nameTxt && r.status==='Согласовано';
    });
    item.markingSizeOptions=[...new Set(variants.map(function(r){return r.marking_size||'';}).filter(Boolean))];
    item.komplektaciyaOptions=[...new Set(variants.map(function(r){return r.komplektaciya||'';}).filter(Boolean))];
    var selected=null;
    var markingVariants=variants.filter(function(r){return (r.marking_size||'')===(item.marking_size||'');});
    var targetMarkingNorm=kpCatalogNorm(item.marking_size||'');
    if(!markingVariants.length && targetMarkingNorm){
      markingVariants=variants.filter(function(r){
        return kpCatalogNorm(r.marking_size||'')===targetMarkingNorm;
      });
    }
    if(markingVariants.length===1){
      selected=markingVariants[0];
    }else if(markingVariants.length>1){
      selected=markingVariants.find(function(r){
        return kpCatalogNorm(r.unit||'')===kpCatalogNorm(item.unit||'') &&
          kpCatalogNorm(r.supplier||'')===kpCatalogNorm(item.supplier||'');
      })||markingVariants[0]||null;
    }
    if(!selected && variants.length===1 && !targetMarkingNorm){
      selected=variants[0];
      item.marking_size=selected.marking_size||'';
      var msInp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
      if(msInp) msInp.value=item.marking_size||'';
    }
    if(selected){
      item.nameId=selected.id;
      item.product_name_id=selected.id;
      item.unit=selected.unit||item.unit||getDefaultUnit();
      item.supplier=selected.supplier||'не указан';
      item.note=selected.note||'';
      item.komplektaciya=selected.komplektaciya||'';
      builderMarkExternalTouched(t,item);
      if(isKpTarget(t)){
        kpSyncVariantFromCats(kpTargetIndex(t));
        kpRefreshRowDisplay(t,ci,si,ii);
        kpRefreshSectionTotal(t,ci,si);
        kpRefreshVariantSummaryByTarget(t);
      }else{
        var unitEl=document.getElementById('unit-'+t+'-'+ci+'-'+si+'-'+ii);
        if(unitEl){
          kpSyncSelectValue(unitEl, item.unit||'', item.unit||getDefaultUnit());
          kpDeduplicateSelectOptions(unitEl);
        }
        var supplierEl=document.getElementById('sup-'+t+'-'+ci+'-'+si+'-'+ii);
        if(supplierEl){
          kpSyncSelectValue(supplierEl, item.supplier||'', '— не указан —');
          kpDeduplicateSelectOptions(supplierEl);
        }
        var komplektaciyaEl=document.getElementById('ackk-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
        if(komplektaciyaEl) komplektaciyaEl.value=item.komplektaciya||'';
      }
    } else {
      item.nameId=null;
      item.product_name_id=0;
    }
  }catch(e){}
}

async function syncItemCatalogData(t,ci,si,ii){
  if(isKpTarget(t)) return kpSyncItemCatalogData(t,ci,si,ii);
  return syncItemCatalogDataDocLike(t,ci,si,ii);
}

function kpCatalogNorm(v){
  return String(v==null?'':v).trim().toLowerCase();
}
function getBuilderGroupOptions(t,ci,si){
  var cats=getCats(t)||[];
  var cat=cats[ci]||null;
  var sec=cat && cat.sections ? cat.sections[si] : null;
  if(!cat || !sec) return [];
  var source=isKpTarget(t) ? (kpCatalogProducts||[]) : (allNamesCache||catalogNames||[]);
  var values=getSectionGroupOptions(sec.secId);
  if(!values.length){
    var seen={}, fallback=[];
    (source||[]).forEach(function(row){
      if(String(row.section_id||'')!==String(sec.secId||'')) return;
      if(isKpTarget(t) && cat.catCode && String(row.category_code||'')!==String(cat.catCode)) return;
      var key=catalogGroupNorm(row.group_name||'');
      if(!key || seen[key]) return;
      seen[key]=true;
      fallback.push(String(row.group_name||'').trim());
    });
    values=fallback.sort(function(a,b){ return String(a).localeCompare(String(b),'ru'); });
  }
  if(!values.length){
    var seenAll={}, allFallback=[];
    (allGroups||[]).forEach(function(row){
      if(String(row.section_id||'')!==String(sec.secId||'')) return;
      var key=catalogGroupNorm(row.name||'');
      if(!key || seenAll[key]) return;
      seenAll[key]=true;
      allFallback.push(String(row.name||'').trim());
    });
    values=allFallback.sort(function(a,b){ return String(a).localeCompare(String(b),'ru'); });
  }
  return values.filter(function(v){
    if(builderIsWorkCategoryCode(cat.catCode)) return false;
    if(!isKpTarget(t)) return true;
    return !cat.catCode || String((source.find(function(row){
      return String(row.section_id||'')===String(sec.secId||'') && catalogGroupNorm(row.group_name||'')===catalogGroupNorm(v);
    })||{}).category_code||cat.catCode)===String(cat.catCode);
  });
}
function setBuilderItemGroup(t,ci,si,ii,val){
  var cats=getCats(t)||[];
  var cat=cats[ci];
  var sec=cat && cat.sections ? cat.sections[si] : null;
  var item=sec && sec.items ? sec.items[ii] : null;
  if(!item) return;
  item.group_name=String(val||'');
  item.nameTxt='';
  item.name='';
  item.marking_size='';
  item.markingSizeOptions=[];
  item.komplektaciya='';
  item.komplektaciyaOptions=[];
  item.product_name_id=0;
  item.nameId=null;
  item.supplier='не указан';
  item.unit=getDefaultUnit();
  if(isKpTarget(t)){
    kpMarkExternalTouched(item);
    kpDetachProductCatalogIdentity(item, cat, sec);
    item.purchase_price=item.item_type==='work' ? item.purchase_price : 0;
    if(!rerenderBuilderSection(t,ci,si)) renderTargetBuilder(t);
    kpRefreshSectionTotal(t,ci,si);
    kpRefreshVariantSummaryByTarget(t);
    setTimeout(function(){
      var refreshedItem=(((getCats(t)[ci]||{}).sections||[])[si]||{}).items ? getCats(t)[ci].sections[si].items[ii] : null;
      if(refreshedItem && !String(refreshedItem.nameTxt||'').trim()){
        var nameEl=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
        if(nameEl){
          nameEl.focus();
          if(nameEl.select) nameEl.select();
          showNameDrop(t,ci,si,ii,nameEl.value||'');
        }
      }
    },40);
  }else{
    if(!rerenderBuilderSection(t,ci,si)) renderTargetBuilder(t);
    setTimeout(function(){
      var refreshedItem=(((getCats(t)[ci]||{}).sections||[])[si]||{}).items ? getCats(t)[ci].sections[si].items[ii] : null;
      if(refreshedItem && !String(refreshedItem.nameTxt||'').trim()){
        var nameEl=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
        if(nameEl){
          nameEl.focus();
          if(nameEl.select) nameEl.select();
          showNameDrop(t,ci,si,ii,nameEl.value||'');
        }
      }
    },40);
  }
}
function mkGroupSel(t,ci,si,ii,v){
  return '<div class="ac-wrap">'+
    '<input class="ac-inp" id="grp-'+t+'-'+ci+'-'+si+'-'+ii+'-inp" value="'+esc(v||'')+'" placeholder="Группа" oninput="showGroupDrop(\''+t+'\','+ci+','+si+','+ii+',this.value)" onfocus="acGroupFocus(\''+t+'\','+ci+','+si+','+ii+')" onclick="showGroupDrop(\''+t+'\','+ci+','+si+','+ii+',this.value)" onmousedown="showGroupDrop(\''+t+'\','+ci+','+si+','+ii+',this.value)" onkeydown="return builderFlowHandleGroupKeydown(event,\''+t+'\','+ci+','+si+','+ii+')" autocomplete="off">'+
    '<div class="ac-drop" id="grp-'+t+'-'+ci+'-'+si+'-'+ii+'-drop"></div></div>';
}
function kpHasManualCatalogIdentity(item){
  if(!item || item.item_type==='work' || item.is_auto) return false;
  return !!(String(item.nameTxt||item.name||'').trim() &&
    String(item.marking_size||'').trim());
}

function kpIsPendingCatalogItem(item){
  if(!kpHasManualCatalogIdentity(item)) return false;
  if(String(item.catalog_status||item.status||'').trim()==='Не согласовано') return true;
  return !(parseInt(item.product_name_id||item.nameId||0,10)>0);
}

function kpAutoSourceLinks(item){
  if(!item) return [];
  if(Array.isArray(item.auto_source_links) && item.auto_source_links.length){
    return item.auto_source_links.map(function(link){
      return {uid:String(link.uid||''), quantity:Math.max(parseFloat(link.quantity||0)||0,0)};
    }).filter(function(link){return !!link.uid;});
  }
  if(item.auto_from_uid){
    return [{uid:String(item.auto_from_uid), quantity:Math.max(parseFloat(item.quantity||0)||0,0)}];
  }
  return [];
}

function kpSetAutoSourceLinks(item, links){
  if(!item) return;
  var normalized=(links||[]).map(function(link){
    return {uid:String(link.uid||''), quantity:Math.max(parseFloat(link.quantity||0)||0,0)};
  }).filter(function(link){return !!link.uid && link.quantity>0;});
  item.auto_source_links=normalized;
  item.auto_from_uid=normalized.length===1 ? normalized[0].uid : '';
  item.quantity=normalized.reduce(function(sum, link){return sum+link.quantity;},0);
}

function kpSuppressAutoWorkForAutoItem(vi, autoItem){
  if(typeof vi!=='number' || !autoItem || !autoItem.is_auto) return;
  var sourceIds=kpAutoSourceLinks(autoItem).map(function(link){ return String(link.uid||''); });
  if(!sourceIds.length && autoItem.auto_from_uid) sourceIds=[String(autoItem.auto_from_uid)];
  if(!sourceIds.length) return;
  var seen={};
  sourceIds.forEach(function(sourceUid){
    if(!sourceUid || seen[sourceUid]) return;
    seen[sourceUid]=true;
    getCats(kpTargetName(vi)).forEach(function(cat){
      (cat.sections||[]).forEach(function(sec){
        (sec.items||[]).forEach(function(item){
          if(item && String(item.uid||'')===sourceUid){
            item.suppress_auto_work=true;
          }
        });
      });
    });
  });
}

function kpFindCatalogProductExact(secId, item, list){
  var targetSec=String(secId||'');
  var targetGroup=kpCatalogNorm(item.group_name||'');
  var targetName=kpCatalogNorm(item.nameTxt||item.name||'');
  var targetMarking=kpCatalogNorm(item.marking_size||'');
  var matches=(list||[]).filter(function(p){
    return String(p.section_id||'')===targetSec &&
      kpCatalogNorm(p.group_name||'')===targetGroup &&
      kpCatalogNorm(p.name||'')===targetName &&
      kpCatalogNorm(p.marking_size||'')===targetMarking;
  });
  if(!matches.length) return null;
  matches.sort(function(a,b){
    var ap=(parseFloat(a.purchase_price||0)||0)>0 ? 1 : 0;
    var bp=(parseFloat(b.purchase_price||0)||0)>0 ? 1 : 0;
    if(ap!==bp) return bp-ap;
    var ar=(parseFloat(a.retail_price||0)||0)>0 ? 1 : 0;
    var br=(parseFloat(b.retail_price||0)||0)>0 ? 1 : 0;
    if(ar!==br) return br-ar;
    return (parseInt(a.id||0,10)||0) - (parseInt(b.id||0,10)||0);
  });
  return matches[0]||null;
}

function kpResetProductCatalogLink(item, cat, sec){
  if(!item) return;
  item.item_type='product';
  item.product_name_id=0;
  item.nameId=null;
  item.category_id=item.category_id||cat.catId||0;
  item.category_code=cat.catCode||item.category_code||'';
  item.category_name=cat.catName||item.category_name||'';
  item.catalog_status='';
  item.section_id=sec.secId;
  item.section_name=sec.secName||item.section_name||'';
  item.section_code=sec.secCode||item.section_code||'';
  item.minimal_price=null;
  item.retail_price=null;
  item.final_price=null;
  item.manual_price_override=false;
  item.linked_service_id=0;
  item.linked_service_name='';
  item.linked_service_cost=0;
  item.linked_service_purchase_price=null;
  item.linked_service_unit='';
  if(!item.supplier) item.supplier='не указан';
}
function kpDetachProductCatalogIdentity(item, cat, sec){
  if(!item) return;
  item.item_type='product';
  item.product_name_id=0;
  item.nameId=null;
  item.category_id=item.category_id||cat.catId||0;
  item.category_code=cat.catCode||item.category_code||'';
  item.category_name=cat.catName||item.category_name||'';
  item.section_id=sec.secId;
  item.section_name=sec.secName||item.section_name||'';
  item.section_code=sec.secCode||item.section_code||'';
  item.minimal_price=null;
  item.retail_price=null;
  item.final_price=null;
  item.manual_price_override=false;
  item.linked_service_id=0;
  item.linked_service_name='';
  item.linked_service_cost=0;
  item.linked_service_purchase_price=null;
  item.linked_service_unit='';
  item.suppress_auto_work=false;
  if(!item.supplier) item.supplier='не указан';
}
