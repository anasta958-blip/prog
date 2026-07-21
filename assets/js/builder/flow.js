function builderFlowIsNavKey(key){
  return key==='ArrowDown' || key==='ArrowUp';
}

function builderFlowMoveDropSelection(drop,key){
  var delta=(key==='ArrowUp') ? -1 : 1;
  moveAutocompleteSelection(drop,delta);
}

function builderQtyFieldId(t,ci,si,ii){
  return isKpTarget(t) ? ('kp-qty-'+kpDomKey(t,ci,si,ii)) : ('qty-'+t+'-'+ci+'-'+si+'-'+ii);
}

function builderFlowFocusQty(t,ci,si,ii){
  setTimeout(function(){
    var qty=document.getElementById(builderQtyFieldId(t,ci,si,ii));
    if(!qty) return;
    qty.focus();
    if(qty.select) qty.select();
  },0);
}

function builderFlowHandleNameKeydown(e,t,ci,si,ii){
  var inp=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
  var drop=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
  if(!inp) return true;
  if(builderFlowIsNavKey(e.key)){
    e.preventDefault();
    e.stopPropagation();
    if(!drop || drop.style.display==='none'){
      showNameDrop(t,ci,si,ii,inp.value||'');
      setTimeout(function(){
        var nextDrop=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
        if(nextDrop) builderFlowMoveDropSelection(nextDrop,e.key);
      },0);
      return false;
    }
    builderFlowMoveDropSelection(drop,e.key);
    return false;
  }
  if(e.key==='Enter'){
    if(drop && drop.style.display!=='none' && getAutocompleteItems(drop).length){
      e.preventDefault();
      e.stopPropagation();
      chooseAutocompleteSelection(drop);
      return false;
    }
    var item=((getCats(t)[ci]||{}).sections||[])[si];
    item=item && item.items ? item.items[ii] : null;
    if(item && String(inp.value||'').trim()){
      e.preventDefault();
      e.stopPropagation();
      item.nameTxt=String(inp.value||'').trim();
      item.name=item.nameTxt;
      item.markingSizeOptions=[];
      if(isKpTarget(t)){
        var cat=(getCats(t)||[])[ci];
        var sec=cat && cat.sections ? cat.sections[si] : null;
        if(cat && sec) kpResetProductCatalogLink(item, cat, sec);
        kpSyncVariantFromCats(kpTargetIndex(t));
      }
      var msInp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
      if(msInp) msInp.disabled=false;
      builderFlowFocusMarking(t,ci,si,ii);
      return false;
    }
  }
  return true;
}

function builderFlowApplyMarkingAndFocusQty(t,ci,si,ii,val){
  if(isKpTarget(t)) updKpItem(t,ci,si,ii,'marking_size',val);
  else updItem(t,ci,si,ii,'marking_size',val);
  syncItemCatalogData(t,ci,si,ii).then(function(){
    if(isKpTarget(t)){
      kpRefreshSelectedBuilderRow(t,ci,si,ii);
    }
    builderFlowFocusQty(t,ci,si,ii);
  });
}

function builderFlowHandleMarkingKeydown(e,t,ci,si,ii){
  var inp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
  var drop=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
  if(!inp) return true;
  if(builderFlowIsNavKey(e.key)){
    e.preventDefault();
    e.stopPropagation();
    kpClearFastNextMarkingInput(inp);
    if(!drop || drop.style.display==='none'){
      showMsDrop(t,ci,si,ii,inp.value||'');
      setTimeout(function(){
        var nextDrop=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
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
      var current=parseInt(drop.dataset.activeIndex||'0',10);
      if(!isFinite(current) || current<0 || current>=items.length) current=0;
      var active=items[current];
      var value=active ? String((active.dataset && active.dataset.value!=null) ? active.dataset.value : active.textContent || '') : '';
      if(value){
        if(inp) inp.value=value;
        if(drop) drop.style.display='none';
        builderFlowApplyMarkingAndFocusQty(t,ci,si,ii,value);
        return false;
      }
    }
    builderFlowApplyMarkingAndFocusQty(t,ci,si,ii,String(inp.value||'').trim());
    return false;
  }
  if(e.key.length===1 || e.key==='Backspace' || e.key==='Delete'){
    kpClearFastNextMarkingInput(inp);
  }
  return true;
}

function builderFlowHandleQtyKeydown(e,t,ci,si,ii){
  if(e.key!=='Enter') return true;
  e.preventDefault();
  e.stopPropagation();
  builderValidateQuantityField(t,ci,si,ii);
  builderFlowAddNextRow(t,ci,si,ii);
  return false;
}

function builderNormalizeQuantityValue(value){
  var qty=parseFloat(String(value==null?'':value).replace(',','.'));
  return isFinite(qty) && qty>0 ? qty : 1;
}

function builderValidateQuantityField(t,ci,si,ii){
  var qtyEl=document.getElementById(builderQtyFieldId(t,ci,si,ii));
  var qty=builderNormalizeQuantityValue(qtyEl ? qtyEl.value : '');
  if(qtyEl) qtyEl.value=String(qty);
  if(isKpTarget(t)) updKpItem(t,ci,si,ii,'quantity',qty);
  else updItem(t,ci,si,ii,'quantity',qty);
  return qty;
}

function builderFlowHandleUnitKeydown(e,t,ci,si,ii){
  if(e.key!=='Enter') return true;
  e.preventDefault();
  e.stopPropagation();
  builderFlowAddNextRow(t,ci,si,ii);
  return false;
}

function kpClearFastNextMarkingInput(inp){
  if(inp) delete inp.dataset.fastNextReady;
}

function kpArmFastNextMarkingInput(inp){
  if(inp) inp.dataset.fastNextReady='1';
}

function kpRefreshSelectedBuilderRow(t,ci,si,ii){
  if(!isKpTarget(t)) return;
  kpRefreshRowDisplay(t,ci,si,ii);
  kpRefreshSectionTotal(t,ci,si);
  kpRefreshVariantSummaryByTarget(t);
}

function builderFlowFocusMarking(t,ci,si,ii){
  setTimeout(function(){
    var inp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
    if(!inp) return;
    if(inp.disabled) inp.disabled=false;
    inp.focus();
    if(inp.select) inp.select();
    if(isKpTarget(t)) kpArmFastNextMarkingInput(inp);
    var item=((getCats(t)[ci]||{}).sections||[])[si];
    item=item && item.items ? item.items[ii] : null;
    var opts=(item && item.markingSizeOptions) ? item.markingSizeOptions : [];
    if(opts.length>1){
      showMsDrop(t,ci,si,ii,inp.value||'');
    }else if(opts.length===1){
      var only=String(opts[0]||'');
      if(String(inp.value||'')!==only) inp.value=only;
      if(item && String(item.marking_size||'')!==only) item.marking_size=only;
    }
  },0);
}

function kpFocusMarkingAutocomplete(t,ci,si,ii){
  builderFlowFocusMarking(t,ci,si,ii);
}

function builderFlowAddNextRow(t,ci,si,ii){
  var nextIi=addBuilderItemData(t,ci,si,'');
  builderFoldState.secs[builderSecFoldKey(t,ci,si)]=false;
  if(!appendBuilderRowDom(t,ci,si) && !rerenderBuilderSection(t,ci,si)) renderTargetBuilder(t);
  setTimeout(function(){
    var groupEl=document.getElementById('grp-'+t+'-'+ci+'-'+si+'-'+nextIi+'-inp');
    if(groupEl){
      groupEl.focus();
      showGroupDrop(t,ci,si,nextIi,groupEl.value||'');
      return;
    }
    var inp=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+nextIi+'-inp');
    if(inp){
      inp.focus();
      if(inp.select) inp.select();
      showNameDrop(t,ci,si,nextIi,inp.value||'');
    }
  },90);
  return nextIi;
}

function kpFastAddNextRow(t,ci,si,ii){
  builderFlowAddNextRow(t,ci,si,ii);
  return;
  addFromList(t,ci,si);
  var nextIi=((getCats(t)[ci]||{}).sections||[])[si] && getCats(t)[ci].sections[si].items ? getCats(t)[ci].sections[si].items.length-1 : 0;
  setTimeout(function(){
    var inp=document.getElementById('ac-'+t+'-'+ci+'-'+si+'-'+nextIi+'-inp');
    if(inp){
      inp.focus();
      if(inp.select) inp.select();
      showNameDrop(t,ci,si,nextIi,inp.value||'');
    }
  },90);
}

document.addEventListener('keydown', function(e){
  var target=e.target;
  if(!target || !target.classList || !target.classList.contains('ac-inp')) return;
  if(target.dataset && target.dataset.builderFlow==='1') return;
  var meta=parseAutocompleteInputMeta(target.id||'');
  if(!meta || !isKpTarget(meta.t)) return;
  if(e.key==='ArrowDown' || e.key==='ArrowUp'){
    e.preventDefault();
    kpClearFastNextMarkingInput(meta.kind==='marking'?target:null);
    var delta=e.key==='ArrowDown'?1:-1;
    var drop=getAutocompleteDropByMeta(meta);
    if(!drop || drop.style.display==='none'){
      ensureAutocompleteShown(meta);
      setTimeout(function(){
        var nextDrop=getAutocompleteDropByMeta(meta);
        if(nextDrop) moveAutocompleteSelection(nextDrop,delta);
      },0);
      return;
    }
    moveAutocompleteSelection(drop,delta);
    return;
  }
  if(e.key==='Enter'){
    var enterDrop=getAutocompleteDropByMeta(meta);
    if(enterDrop && enterDrop.style.display!=='none' && getAutocompleteItems(enterDrop).length){
      e.preventDefault();
      chooseAutocompleteSelection(enterDrop);
      return;
    }
    if(meta.kind==='marking' && target.dataset.fastNextReady==='1'){
      e.preventDefault();
      kpClearFastNextMarkingInput(target);
      kpFastAddNextRow(meta.t,meta.ci,meta.si,meta.ii);
      return;
    }
    return;
  }
  if(meta.kind==='marking' && (e.key.length===1 || e.key==='Backspace' || e.key==='Delete')){
    kpClearFastNextMarkingInput(target);
  }
},true);

document.addEventListener('input', function(e){
  var target=e.target;
  if(!target || !target.classList || !target.classList.contains('ac-inp')) return;
  var meta=parseAutocompleteInputMeta(target.id||'');
  if(meta && meta.kind==='marking') kpClearFastNextMarkingInput(target);
},true);

document.addEventListener('focusout', function(e){
  var target=e.target;
  if(!target || !target.classList || !target.classList.contains('ac-inp')) return;
  var meta=parseAutocompleteInputMeta(target.id||'');
  if(meta && meta.kind==='marking'){
    setTimeout(function(){
      if(document.activeElement!==target) kpClearFastNextMarkingInput(target);
    },0);
  }
},true);

function handleAutocompleteScroll(e){
  if(e && e.target && e.target.closest && e.target.closest('.ac-drop')) return;
  closeAllAutocompleteDrops();
}

window.addEventListener('scroll', handleAutocompleteScroll, true);

function mkInvSel(t,ci,si,ii,v){
  var cls=v==='Проверено'?'inv-ok':v==='Ошибка'?'inv-err':'';
  var s='<select class="'+cls+'" onchange="updItem(\''+t+'\','+ci+','+si+','+ii+',\'invoice_check\',this.value);updateInvColor(this)">';
  ['','Проверено','Ошибка'].forEach(function(u){s+='<option value="'+esc(u)+'"'+(u===v?' selected':'')+'>'+(u||'—')+'</option>';});
  return s+'</select>';
}
function updateInvColor(sel){
  sel.className=sel.value==='Проверено'?'inv-ok':sel.value==='Ошибка'?'inv-err':'';
}

