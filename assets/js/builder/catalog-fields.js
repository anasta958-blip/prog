function kpHandleBuilderManualCatalogField(t,ci,si,ii,field,val){
  if(!isKpTarget(t)){
    updItem(t,ci,si,ii,field,val);
    return;
  }
  var cats=getCats(t)||[];
  var cat=cats[ci];
  var sec=cat && cat.sections ? cat.sections[si] : null;
  var item=sec && sec.items ? sec.items[ii] : null;
  if(!item) return;
  updKpItem(t,ci,si,ii,field,val);
  if(item.item_type!=='work' && !item.is_auto && (field==='nameTxt' || field==='marking_size' || field==='group_name')){
    kpDetachProductCatalogIdentity(item, cat, sec);
    kpRefreshSelectedBuilderRow(t,ci,si,ii);
  }
}

function mkUnitSel(t,ci,si,ii,v){
  var changeJs=isKpTarget(t)
    ? 'kpHandleBuilderManualCatalogField(\''+t+'\','+ci+','+si+','+ii+',\'unit\',this.value)'
    : 'updItem(\''+t+'\','+ci+','+si+','+ii+',\'unit\',this.value)';
  var s='<select onchange="'+changeJs+'">';
  var options=UNITS.slice();
  if(v && options.indexOf(v)<0) options.push(v);
  if(!options.length) options.push('');
  options.forEach(function(u){s+='<option'+(u===v?' selected':'')+'>'+u+'</option>';});return s+'</select>';
}
function mkSupSel(t,ci,si,ii,v){
  var changeJs=isKpTarget(t)
    ? 'kpHandleBuilderManualCatalogField(\''+t+'\','+ci+','+si+','+ii+',\'supplier\',this.value)'
    : 'updItem(\''+t+'\','+ci+','+si+','+ii+',\'supplier\',this.value)';
  var s='<select onchange="'+changeJs+'">';
  // Получаем secId текущего раздела для фильтрации поставщиков
  var secId = (getCats(t)[ci] && getCats(t)[ci].sections[si]) ? getCats(t)[ci].sections[si].secId : 0;
  // Строгая фильтрация: только поставщики, привязанные к данному разделу в БД.
  // Поставщик без привязок к разделу не показывается.
  var list = allSuppliers.filter(function(sup){
    if (!sup.name) return false;
    if (!secId) return true; // раздел неизвестен — показываем всех
    if (!sup.section_ids) return false; // нет привязок — не показываем
    var ids = String(sup.section_ids).split(',').map(Number);
    return ids.indexOf(secId) >= 0;
  });
  s += '<option value="не указан"'+((!v || v==='не указан')?' selected':'')+'>не указан</option>';
  list.forEach(function(u){
    s += '<option value="'+esc(u.name)+'"'+(u.name===v?' selected':'')+'>'+esc(u.name)+'</option>';
  });
  // Если сохранённый поставщик не входит в список раздела — показать с пометкой
  if (v && !list.find(function(u){return u.name===v;})) {
    s += '<option value="'+esc(v)+'" selected>'+esc(v)+' ⚠️</option>';
  }
  return s+'</select>';
}
function mkEnumSel(opts,t,ci,si,ii,field,v){
  var s='<select onchange="updItem(\''+t+'\','+ci+','+si+','+ii+',\''+field+'\',this.value)">';
  opts.forEach(function(u){s+='<option value="'+esc(u)+'"'+(u===v?' selected':'')+'>'+(u||'—')+'</option>';});
  return s+'</select>';
}

function kpSyncSelectValue(selectEl, value, fallbackLabel){
  if(!selectEl) return;
  var next=String(value==null?'':value);
  var hasOption=Array.prototype.some.call(selectEl.options||[], function(opt){
    return String(opt.value||opt.text||'')===next;
  });
  if(!hasOption){
    var opt=document.createElement('option');
    opt.value=next;
    opt.textContent=next || (fallbackLabel||'');
    selectEl.appendChild(opt);
  }
  selectEl.value=next;
}
function kpDeduplicateSelectOptions(selectEl){
  if(!selectEl || !selectEl.options) return;
  var selected=String(selectEl.value||'');
  var seen={};
  var unique=[];
  Array.prototype.forEach.call(selectEl.options, function(opt){
    var value=String(opt.value||opt.text||'');
    if(seen[value]) return;
    seen[value]=true;
    unique.push({value:value,text:opt.text});
  });
  if(unique.length===selectEl.options.length) return;
  selectEl.innerHTML='';
  unique.forEach(function(opt){
    var next=document.createElement('option');
    next.value=opt.value;
    next.textContent=opt.text;
    if(opt.value===selected) next.selected=true;
    selectEl.appendChild(next);
  });
  selectEl.value=selected;
}
function kpNormalizeBuilderSelects(root){
  root=root||document;
  Array.prototype.forEach.call(root.querySelectorAll('select[id^="kp-supplier-"], select[id^="kp-unit-"]'), function(selectEl){
    kpDeduplicateSelectOptions(selectEl);
  });
}

function acGroupFocus(t,ci,si,ii){
  showGroupDrop(t,ci,si,ii,(document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-inp')||{}).value||'');
}

function showGroupDrop(t,ci,si,ii,val){
  var inp=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
  var drop=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
  if(!drop || !inp) return;
  var filter=String(val||'').trim().toLowerCase();
  var values=getBuilderGroupOptions(t,ci,si).slice();
  var current=((document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-inp')||{}).value||'').trim();
  if(current && values.indexOf(current)<0) values.push(current);
  values=values.filter(function(groupName){
    if(!filter) return true;
    return String(groupName||'').toLowerCase().indexOf(filter)>=0;
  });
  values.sort(function(a,b){ return String(a).localeCompare(String(b),'ru'); });
  drop.innerHTML=values.map(function(groupName){
    var label=groupName||'— без группы —';
    return '<div class="ac-item" data-value="'+esc(groupName)+'" onmousedown="event.preventDefault();event.stopPropagation();applyBuilderGroupOption(\''+t+'\','+ci+','+si+','+ii+',this.dataset.value||\'\')">'+esc(label)+'</div>';
  }).join('');
  if(!values.length){
    drop.innerHTML='<div class="ac-item" data-value="" style="opacity:.7;pointer-events:none">Нет групп</div>';
    openAutocompleteDrop(inp, drop);
    return;
  }
  openAutocompleteDrop(inp, drop);
}

function applyBuilderGroupOption(t,ci,si,ii,val){
  var inp=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
  var drop=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
  if(inp) inp.value=String(val||'');
  if(drop) drop.style.display='none';
  setBuilderItemGroup(t,ci,si,ii,String(val||''));
}

function builderFlowHandleGroupKeydown(e,t,ci,si,ii){
  var inp=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
  var drop=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
  if(!inp) return true;
  if(builderFlowIsNavKey(e.key)){
    e.preventDefault();
    e.stopPropagation();
    if(!drop || drop.style.display==='none'){
      showGroupDrop(t,ci,si,ii,inp.value||'');
      setTimeout(function(){
        var nextDrop=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
        if(nextDrop) builderFlowMoveDropSelection(nextDrop,e.key);
      },0);
      return false;
    }
    builderFlowMoveDropSelection(drop,e.key);
    return false;
  }
  if(e.key==='Enter'){
    e.preventDefault();
    e.stopPropagation();
    var items=(drop && drop.style.display!=='none') ? getAutocompleteItems(drop) : [];
    if(items.length){
      var currentIndex=parseInt(drop.dataset.activeIndex||'0',10);
      if(!isFinite(currentIndex) || currentIndex<0 || currentIndex>=items.length) currentIndex=0;
      var active=items[currentIndex];
      var value=active ? String((active.dataset && active.dataset.value!=null) ? active.dataset.value : active.textContent || '') : '';
      applyBuilderGroupOption(t,ci,si,ii,value);
    }
    return false;
  }
  return true;
}

function builderIsWorkRow(t,ci){
  var cat=(getCats(t)||[])[ci]||null;
  return !!(cat && builderIsWorkCategoryCode(cat.catCode));
}

function builderEnsureCatalogServicesLoaded(){
  if(Array.isArray(kpCatalogServices) && kpCatalogServices.length) return Promise.resolve(kpCatalogServices);
  if(typeof loadKpCatalogServices==='function'){
    return loadKpCatalogServices().catch(function(){
      kpCatalogServices=[];
      return kpCatalogServices;
    });
  }
  return api('catalog.php?action=services').then(function(rows){
    kpCatalogServices=Array.isArray(rows)?rows:[];
    return kpCatalogServices;
  }).catch(function(){
    kpCatalogServices=[];
    return kpCatalogServices;
  });
}

function builderServiceMatchesSection(service, sec){
  var workScopeCode=kpGetWorkScopeCode(sec);
  if(!workScopeCode) return true;
  if(workScopeCode==='installation' || workScopeCode==='construction' || workScopeCode==='dismantling'){
    return kpGetServiceWorkSectionCode(service)===String(workScopeCode);
  }
  return true;
}

function builderApplyServiceToItem(t,ci,si,ii,service){
  var cats=getCats(t);
  var cat=cats[ci];
  var sec=cat.sections[si];
  var item=sec.items[ii];
  if(!item || !service) return;
  var serviceName=service.name||'';
  var variants=(kpCatalogServices||[]).filter(function(s){
    return builderServiceMatchesSection(s,sec) &&
      kpCatalogNorm(s.name||'')===kpCatalogNorm(serviceName);
  });
  var markingOptions=[...new Set(variants.map(function(s){return s.marking_size||'';}).filter(Boolean).map(String))];
  var hasMarking=kpCatalogNorm(item.marking_size||'')!=='';
  if(variants.length){
    item.markingSizeOptions=markingOptions;
    if(markingOptions.length>1 && !hasMarking){
      item.item_type='work';
      item.service_id=0;
      item.product_name_id=0;
      item.nameId=null;
      item.nameTxt=serviceName;
      item.name=serviceName;
      item.supplier='';
      item.purchase_price=null;
      item.minimal_price=null;
      item.retail_price=null;
      item.base_price=0;
      item.final_price=null;
      item.manual_price_override=false;
      builderMarkExternalTouched(t,item);
      return;
    }
    if(hasMarking){
      var matchedService=variants.find(function(s){
        return kpCatalogNorm(s.marking_size||'')===kpCatalogNorm(item.marking_size||'') &&
          kpCatalogNorm(s.unit||'')===kpCatalogNorm(item.unit||'');
      })||variants.find(function(s){
        return kpCatalogNorm(s.marking_size||'')===kpCatalogNorm(item.marking_size||'');
      })||null;
      if(!matchedService && markingOptions.length>1){
        item.item_type='work';
        item.service_id=0;
        item.product_name_id=0;
        item.nameId=null;
        item.nameTxt=serviceName;
        item.name=serviceName;
        item.supplier='';
        item.purchase_price=null;
        item.minimal_price=null;
        item.retail_price=null;
        item.base_price=0;
        item.final_price=null;
        item.manual_price_override=false;
        builderMarkExternalTouched(t,item);
        return;
      }
      service=matchedService||service;
    }else{
      service=variants[0]||service;
    }
  }
  var retail=(service.retail_price!=null && service.retail_price!=='') ? service.retail_price : (service.cost!=null ? service.cost : null);
  item.item_type='work';
  item.service_id=parseInt(service.id,10)||0;
  item.product_name_id=0;
  item.nameId=null;
  item.nameTxt=service.name||'';
  item.name=service.name||'';
  item.marking_size=service.marking_size||item.marking_size||'';
  item.markingSizeOptions=markingOptions.length?markingOptions:[];
  item.unit=service.unit||item.unit||getDefaultUnit();
  item.supplier='';
  item.purchase_price=service.purchase_price!=null?service.purchase_price:null;
  item.minimal_price=service.minimal_price!=null?service.minimal_price:null;
  item.retail_price=retail;
  item.base_price=parseFloat(retail||0)||0;
  item.final_price=null;
  item.manual_price_override=false;
  builderMarkExternalTouched(t,item);
}

// Autocomplete for name field
function acNameInput(t,ci,si,ii,val){
  updItem(t,ci,si,ii,'nameTxt',val);
  showNameDrop(t,ci,si,ii,val);
}
function acNameFocus(t,ci,si,ii){
  var val=getCats(t)[ci].sections[si].items[ii].nameTxt||'';
  showNameDrop(t,ci,si,ii,val);
}
function showNameDrop(t,ci,si,ii,val){
  var key='ac-'+t+'-'+ci+'-'+si+'-'+ii;
  var inp=document.getElementById(key+'-inp');
  var drop=document.getElementById(key+'-drop');
  if(!drop||!inp)return;
  if(builderIsWorkRow(t,ci)){
    var cat=getCats(t)[ci], sec=getCats(t)[ci].sections[si];
    if(!Array.isArray(kpCatalogServices) || !kpCatalogServices.length){
      builderEnsureCatalogServicesLoaded().then(function(){showNameDrop(t,ci,si,ii,val);});
      drop.style.display='none';
      return;
    }
    var lv=(val||'').toLowerCase();
    var seenWorkNames={};
    var list=kpCatalogServices.filter(function(s){
      return builderServiceMatchesSection(s,sec) && (!lv || String(s.name||'').toLowerCase().indexOf(lv)>=0);
    }).filter(function(s){
      var nameKey=String(s.name||'').trim().toLowerCase();
      if(!nameKey || seenWorkNames[nameKey]) return false;
      seenWorkNames[nameKey]=true;
      return true;
    });
    drop.innerHTML='';
    if(!list.length){drop.style.display='none';return;}
    list.forEach(function(s){
      var div=document.createElement('div');div.className='ac-item';div.textContent=s.name;
      div.onmousedown=function(e){e.preventDefault();
        builderApplyServiceToItem(t,ci,si,ii,s);
        drop.style.display='none';
        var inp2=document.getElementById(key+'-inp');
        if(inp2) inp2.value=s.name||'';
        syncItemCatalogData(t,ci,si,ii).then(function(){
          if(isKpTarget(t)){
            kpFocusMarkingAutocomplete(t,ci,si,ii);
          }else{
            var msInp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
            if(msInp) msInp.focus();
          }
        });
      };
      drop.appendChild(div);
    });
    openAutocompleteDrop(inp, drop);
    return;
  }
  if(isKpTarget(t)){
    var cat=getCats(t)[ci], sec=getCats(t)[ci].sections[si];
    if(cat && builderIsWorkCategoryCode(cat.catCode)){
      var lv=(val||'').toLowerCase();
      var workScopeCode=kpGetWorkScopeCode(sec);
      var seenWorkNames={};
      var list=kpCatalogServices.filter(function(s){
        var matchesSection=!workScopeCode ||
          ((workScopeCode==='installation' || workScopeCode==='construction' || workScopeCode==='dismantling')
            ? kpGetServiceWorkSectionCode(s)===String(workScopeCode)
            : true);
        return matchesSection && (!lv || String(s.name||'').toLowerCase().indexOf(lv)>=0);
      }).filter(function(s){
        var nameKey=String(s.name||'').trim().toLowerCase();
        if(!nameKey || seenWorkNames[nameKey]) return false;
        seenWorkNames[nameKey]=true;
        return true;
      });
      drop.innerHTML='';
      if(!list.length){drop.style.display='none';return;}
      list.forEach(function(s){
        var div=document.createElement('div');div.className='ac-item';div.textContent=s.name;
        div.onmousedown=function(e){e.preventDefault();
          var rowItem=getCats(t)[ci].sections[si].items[ii];
          if(rowItem){
            rowItem.nameTxt=s.name;
            rowItem.name=s.name;
          }
          drop.style.display='none';
          var inp2=document.getElementById(key+'-inp');
          if(inp2) inp2.value=s.name;
          var msInp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
          if(msInp && msInp.disabled) msInp.disabled=false;
          syncItemCatalogData(t,ci,si,ii).then(function(){
            kpFocusMarkingAutocomplete(t,ci,si,ii);
          });
        };
        drop.appendChild(div);
      });
      openAutocompleteDrop(inp, drop);
      return;
    }
  }
  // Get section id for this row
  var rowItem=getCats(t)[ci].sections[si].items[ii];
  var isConsumablesRow=cat && cat.catCode==='consumables';
  if(!isConsumablesRow && String((rowItem&&rowItem.item_type)||'product')!=='work' && !catalogGroupNorm((rowItem&&rowItem.group_name)||'')){
    drop.innerHTML='';
    drop.style.display='none';
    return;
  }
  var secId=getCats(t)[ci].sections[si].secId;
  var groupParam=isConsumablesRow ? '' : '&group_name='+encodeURIComponent(catalogGroupToken((rowItem&&rowItem.group_name)||''));
  api('catalog.php?action=names_search&q='+encodeURIComponent(val)+'&section_id='+secId+groupParam).then(function(names){
    drop.innerHTML='';
    if(!names.length){
      if(isKpTarget(t) && rowItem){
        rowItem.nameTxt=String(val||'').trim();
        rowItem.name=rowItem.nameTxt;
        rowItem.markingSizeOptions=[];
        if(cat && sec) kpResetProductCatalogLink(rowItem, cat, sec);
        rowItem.nameId=null;
        rowItem.product_name_id=0;
        var msInpEmpty=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
        if(msInpEmpty) msInpEmpty.disabled=!rowItem.nameTxt;
      }
      drop.style.display='none';
      return;
    }
    // Deduplicate by name
    var seen={}, unique=[];
    names.forEach(function(n){if(!seen[n.name]){seen[n.name]=true;unique.push(n);}});
    if(!unique.length){drop.style.display='none';return;}
    unique.forEach(function(n){
      var div=document.createElement('div');div.className='ac-item';
      div.textContent=n.name;
      div.onmousedown=function(e){e.preventDefault();
        var rowItem=getCats(t)[ci].sections[si].items[ii];
        if(rowItem){
          rowItem.nameTxt=n.name;
          rowItem.name=n.name;
          rowItem.nameId=n.id;
          rowItem.product_name_id=n.id;
          rowItem.isCustom=false;
        }
        drop.style.display='none';
        // Update only the input value without full re-render
        var inp2=document.getElementById(key+'-inp');
        if(inp2) inp2.value=n.name;
        var msInp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
        if(msInp && msInp.disabled) msInp.disabled=false;
        // Load marking size opts and update only that cell
        loadMarkingSizeOpts(t,ci,si,ii,n.id,n.name).then(function(){
          builderFlowFocusMarking(t,ci,si,ii);
        });
      };
      drop.appendChild(div);
    });
    // Position dropdown using fixed coords of input
    openAutocompleteDrop(inp, drop);
  });
}

async function loadMarkingSizeOpts(t,ci,si,ii,nameId,nameTxt){
  if(isKpTarget(t)){
    var item=((getCats(t)[ci]||{}).sections||[])[si];
    item=item && item.items ? item.items[ii] : null;
    if(item){
      item.nameId=nameId;
      item.product_name_id=nameId;
      item.nameTxt=nameTxt;
      item.name=nameTxt;
      kpSyncVariantFromCats(kpTargetIndex(t));
    }
  }else{
    updItem(t,ci,si,ii,'nameId',nameId);
    updItem(t,ci,si,ii,'nameTxt',nameTxt);
  }
  await syncItemCatalogData(t,ci,si,ii);
  if(isKpTarget(t)) kpRefreshRowDisplay(t,ci,si,ii);
}

function acKkInput(t,ci,si,ii,val){
  updItem(t,ci,si,ii,'komplektaciya',val);
  showKkDrop(t,ci,si,ii,val);
}
function acKkFocus(t,ci,si,ii){
  var val=getCats(t)[ci].sections[si].items[ii].komplektaciya||'';
  showKkDrop(t,ci,si,ii,val);
}
function showKkDrop(t,ci,si,ii,val){
  var key='ackk-'+t+'-'+ci+'-'+si+'-'+ii;
  var drop=document.getElementById(key+'-drop');
  if(!drop)return;
  var opts=getCats(t)[ci].sections[si].items[ii].komplektaciyaOptions||[];
  if(!opts.length){drop.style.display='none';return;}
  var lv=val.toLowerCase();
  var filtered=lv?opts.filter(function(o){return o.toLowerCase().indexOf(lv)>=0;}):opts;
  drop.innerHTML='';
  filtered.forEach(function(o){
    var div=document.createElement('div');div.className='ac-item';div.textContent=o;
    div.onmousedown=function(e){e.preventDefault();
      updItem(t,ci,si,ii,'komplektaciya',o);
      drop.style.display='none';
      var inp2=document.getElementById(key+'-inp');
      if(inp2) inp2.value=o;
    };
    drop.appendChild(div);
  });
  if(filtered.length){
    var kkinp=document.getElementById(key+'-inp');
    if(kkinp) openAutocompleteDrop(kkinp, drop);
  } else { drop.style.display='none'; }
}

function acMsInput(t,ci,si,ii,val){
  updItem(t,ci,si,ii,'marking_size',val);
  showMsDrop(t,ci,si,ii,val);
}
function acMsFocus(t,ci,si,ii){
  var val=getCats(t)[ci].sections[si].items[ii].marking_size||'';
  showMsDrop(t,ci,si,ii,val);
}
function applyBuilderMarkingOption(t,ci,si,ii,val){
  if(isKpTarget(t)) updKpItem(t,ci,si,ii,'marking_size',val);
  else updItem(t,ci,si,ii,'marking_size',val);
  syncItemCatalogData(t,ci,si,ii).then(function(){
    if(isKpTarget(t)){
      kpRefreshSelectedBuilderRow(t,ci,si,ii);
      var msInp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
      if(msInp){
        msInp.focus();
        kpArmFastNextMarkingInput(msInp);
      }
      return;
    }
    builderFlowFocusQty(t,ci,si,ii);
  });
}
function showMsDrop(t,ci,si,ii,val){
  var key='acms-'+t+'-'+ci+'-'+si+'-'+ii;
  var drop=document.getElementById(key+'-drop');
  if(!drop)return;
  var item=getCats(t)[ci].sections[si].items[ii];
  var opts=[...new Set((item.markingSizeOptions||[]).filter(Boolean).map(function(o){ return String(o); }))];
  if(!opts.length){drop.style.display='none';return;}
  var lv=String(val||'').toLowerCase();
  var filtered=lv?opts.filter(function(o){return o.toLowerCase().indexOf(lv)>=0;}):opts;
  if(opts.length===1){
    var only=filtered[0]||'';
    if(!only) only=opts[0]||'';
    var typed=String(val||'').trim();
    var shouldAutoApply=!typed || kpCatalogNorm(typed)===kpCatalogNorm(only);
    if(shouldAutoApply && only && String(item.marking_size||'')!==String(only)){
      if(isKpTarget(t)) applyBuilderMarkingOption(t,ci,si,ii,only);
      else updItem(t,ci,si,ii,'marking_size',only);
      var onlyInp=document.getElementById(key+'-inp');
      if(onlyInp) onlyInp.value=only;
    }
    drop.style.display='none';
    return;
  }
  drop.innerHTML='';
  filtered.forEach(function(o){
    var div=document.createElement('div');div.className='ac-item';div.textContent=o;
    div.dataset.value=o;
    div.onmousedown=function(e){e.preventDefault();
      applyBuilderMarkingOption(t,ci,si,ii,o);
      drop.style.display='none';
      var inp2=document.getElementById(key+'-inp');
      if(inp2) inp2.value=o;
    };
    drop.appendChild(div);
  });
  if(filtered.length){
    var msinp=document.getElementById(key+'-inp');
    if(msinp) openAutocompleteDrop(msinp, drop);
  } else { drop.style.display='none'; }
}

function openAutocompleteDrop(inp, drop){
  if(!inp || !drop) return;
  closeAllAutocompleteDrops(drop);
  var wrap=inp.closest ? inp.closest('.ac-wrap') : null;
  var row=inp.closest ? inp.closest('tr') : null;
  if(wrap) wrap.classList.add('ac-open');
  if(row) row.classList.add('ac-row-open');
  var rect=inp.getBoundingClientRect();
  drop.style.display='block';
  drop.style.left=rect.left+'px';
  drop.style.width=rect.width+'px';
  drop.style.maxHeight='220px';
  var dropHeight=Math.max(drop.offsetHeight||0, 0);
  var viewportHeight=window.innerHeight||document.documentElement.clientHeight||0;
  var spaceBelow=Math.max(viewportHeight-rect.bottom-6,0);
  var spaceAbove=Math.max(rect.top-6,0);
  if(spaceBelow<dropHeight && spaceAbove>spaceBelow){
    var openUpHeight=Math.max(Math.min(dropHeight, spaceAbove), 0);
    drop.style.maxHeight=openUpHeight+'px';
    drop.style.top=Math.max(rect.top-openUpHeight-2, 6)+'px';
  }else{
    var openDownHeight=Math.max(Math.min(dropHeight, spaceBelow||220), 0);
    drop.style.maxHeight=openDownHeight+'px';
    drop.style.top=(rect.bottom+2)+'px';
  }
  if(getAutocompleteItems(drop).length) setAutocompleteActive(drop,0);
}

function closeAllAutocompleteDrops(){
  document.querySelectorAll('.ac-drop').forEach(function(drop){
    var wrap=drop.closest ? drop.closest('.ac-wrap') : null;
    var row=drop.closest ? drop.closest('tr') : null;
    if(wrap) wrap.classList.remove('ac-open');
    if(row) row.classList.remove('ac-row-open');
    drop.dataset.activeIndex='';
    drop.style.display='none';
  });
}
var _acTransitionUntil=0;
function markAutocompleteTransition(ms){
  _acTransitionUntil=Date.now()+(ms||180);
}
function isAutocompleteTransitionActive(){
  return Date.now()<_acTransitionUntil;
}

function parseAutocompleteInputMeta(id){
  if(!id || typeof id!=='string') return null;
  var prefix='';
  if(id.indexOf('acms-')===0 && id.slice(-4)==='-inp') prefix='acms-';
  else if(id.indexOf('ac-')===0 && id.slice(-4)==='-inp') prefix='ac-';
  else return null;
  var body=id.slice(prefix.length,-4);
  var parts=body.split('-');
  if(parts.length<4) return null;
  var ii=parseInt(parts.pop(),10);
  var si=parseInt(parts.pop(),10);
  var ci=parseInt(parts.pop(),10);
  if(!isFinite(ci) || !isFinite(si) || !isFinite(ii)) return null;
  return {
    kind:prefix==='acms-'?'marking':'name',
    t:parts.join('-'),
    ci:ci,
    si:si,
    ii:ii,
    key:(prefix==='acms-'?'acms-':'ac-')+body
  };
}

function getAutocompleteDropByMeta(meta){
  return meta ? document.getElementById(meta.key+'-drop') : null;
}

function getAutocompleteInputByMeta(meta){
  return meta ? document.getElementById(meta.key+'-inp') : null;
}

function getAutocompleteItems(drop){
  return drop ? Array.prototype.slice.call(drop.querySelectorAll('.ac-item')) : [];
}

function setAutocompleteActive(drop,index){
  var items=getAutocompleteItems(drop);
  if(!items.length) return;
  var next=Math.max(0,Math.min(index,items.length-1));
  items.forEach(function(item,ii){item.classList.toggle('sel', ii===next);});
  drop.dataset.activeIndex=String(next);
  if(items[next] && items[next].scrollIntoView) items[next].scrollIntoView({block:'nearest'});
}

function moveAutocompleteSelection(drop,delta){
  var items=getAutocompleteItems(drop);
  if(!items.length) return;
  var current=parseInt(drop.dataset.activeIndex||'-1',10);
  if(!isFinite(current) || current<0 || current>=items.length) current=(delta>0?-1:0);
  var next=current+delta;
  if(next<0) next=items.length-1;
  if(next>=items.length) next=0;
  setAutocompleteActive(drop,next);
}

function chooseAutocompleteSelection(drop){
  var items=getAutocompleteItems(drop);
  if(!items.length) return false;
  var current=parseInt(drop.dataset.activeIndex||'0',10);
  if(!isFinite(current) || current<0 || current>=items.length) current=0;
  var item=items[current];
  if(!item) return false;
  var inputId=(drop.id||'').slice(0,-5)+'-inp';
  var meta=parseAutocompleteInputMeta(inputId);
  if(meta && meta.kind==='marking' && isKpTarget(meta.t)){
    var value=item.dataset && item.dataset.value!=null ? item.dataset.value : item.textContent;
    applyBuilderMarkingOption(meta.t,meta.ci,meta.si,meta.ii,String(value||''));
    drop.style.display='none';
    var inp=document.getElementById(inputId);
    if(inp) inp.value=String(value||'');
    return true;
  }
  item.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,view:window}));
  return true;
}

function ensureAutocompleteShown(meta){
  if(!meta) return;
  if(meta.kind==='name'){
    var nameInp=getAutocompleteInputByMeta(meta);
    showNameDrop(meta.t,meta.ci,meta.si,meta.ii,nameInp?nameInp.value:'');
  }else{
    var msInp=getAutocompleteInputByMeta(meta);
    showMsDrop(meta.t,meta.ci,meta.si,meta.ii,msInp?msInp.value:'');
  }
}

