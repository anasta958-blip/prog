var builderFoldState={cats:{},secs:{}};
function builderCatFoldKey(t,ci){return String(t)+'::'+String(ci);}
function builderSecFoldKey(t,ci,si){return String(t)+'::'+String(ci)+'::'+String(si);}
function isCatCollapsed(t,ci){return !!builderFoldState.cats[builderCatFoldKey(t,ci)];}
function isSecCollapsed(t,ci,si){return !!builderFoldState.secs[builderSecFoldKey(t,ci,si)];}
function getBuilderFoldRoot(t){
  if(t==='oe') return document.getElementById('oe-docbuilder');
  if(isKpTarget(t)) return document.getElementById('kp-variants-wrap');
  return document.getElementById('doc-builder');
}
function builderFindCatDom(root, ci, cat){
  if(!root) return null;
  var code=cat && cat.catCode!=null ? String(cat.catCode) : '';
  if(code){
    var byCode=root.querySelector('.catblk.fi2[data-cat-code="'+code.replace(/"/g,'\\"')+'"]');
    if(byCode) return byCode;
  }
  var byIndex=(root.querySelectorAll('.catblk.fi2')||[])[ci] || null;
  if(code && byIndex && byIndex.getAttribute && byIndex.getAttribute('data-cat-code') && byIndex.getAttribute('data-cat-code')!==code) return null;
  return byIndex;
}
function builderFindSecDom(catEl, si, sec){
  if(!catEl) return null;
  var id=sec && sec.secId!=null ? String(sec.secId) : '';
  var code=sec && sec.secCode!=null ? String(sec.secCode) : '';
  if(id){
    var byId=catEl.querySelector('.secblk[data-sec-id="'+id.replace(/"/g,'\\"')+'"]');
    if(byId) return byId;
  }
  if(code){
    var byCode=catEl.querySelector('.secblk[data-sec-code="'+code.replace(/"/g,'\\"')+'"]');
    if(byCode) return byCode;
  }
  var byIndex=(catEl.querySelectorAll('.secblk')||[])[si] || null;
  if(id && byIndex && byIndex.getAttribute && byIndex.getAttribute('data-sec-id') && byIndex.getAttribute('data-sec-id')!==id) return null;
  if(code && byIndex && byIndex.getAttribute && byIndex.getAttribute('data-sec-code') && byIndex.getAttribute('data-sec-code')!==code) return null;
  return byIndex;
}
function rerenderBuilderSection(t,ci,si){
  var root=getBuilderFoldRoot(t);
  if(!root) return false;
  var cat=getCats(t)[ci];
  var catEl=builderFindCatDom(root,ci,cat);
  if(!catEl || !cat || !cat.sections || !cat.sections[si]) return false;
  var oldSecEl=builderFindSecDom(catEl,si,cat.sections[si]);
  var tmp=document.createElement('div');
  tmp.innerHTML=buildSecHTML(t,cat,ci,cat.sections[si],si);
  var newSecEl=tmp.firstElementChild;
  if(!newSecEl) return false;
  if(oldSecEl){
    oldSecEl.replaceWith(newSecEl);
  }else{
    var catBody=Array.prototype.slice.call(catEl.children||[]).filter(function(child){
      return child && !(child.classList && child.classList.contains('catblk-h'));
    })[0] || null;
    if(catBody) catBody.appendChild(newSecEl);
    else catEl.appendChild(newSecEl);
  }
  if(isKpTarget(t)){
    enhanceKpCategoryBulkUi(root, t);
  }
  enhanceBuilderFolding(root, t);
  kpNormalizeBuilderSelects(root);
  stripNumericFieldDecimals(root);
  return true;
}
function addBuilderItemData(t,ci,si,groupName){
  var isOE=t==='oe';
  var isKP=isKpTarget(t);
  var ii=getCats(t)[ci].sections[si].items.length;
  var montageStatuses=['Монтаж','Монтаж завершён','Выполнено'];
  var curStatus=isOE&&document.getElementById('oe-status')?document.getElementById('oe-status').value:'';
  var dozakazFlag=isOE&&montageStatuses.indexOf(curStatus)>=0?1:0;
  var cat=getCats(t)[ci], sec=getCats(t)[ci].sections[si];
  var itemType=builderIsWorkCategoryCode(cat.catCode)?'work':'product';
  getCats(t)[ci].sections[si].items.push(
    isKP
      ? kpNormalizeBuilderItem({quantity:1,note:'',supplier:'',group_name:groupName||'',base_price:0,markup_value:0,discount_value:0},cat.catCode,cat.catName,sec.secId,sec.secName,sec.secCode)
      : {nameId:null,product_name_id:0,service_id:0,item_type:itemType,category_id:cat.catId||0,category_code:cat.catCode||'',category_name:cat.catName||'',section_id:sec.secId,section_name:sec.secName||'',section_code:sec.secCode||'',nameTxt:'',name:'',isCustom:false,group_name:groupName||'',marking_size:'',quantity:cat.catCode==='consumables'?1:'',unit:getDefaultUnit(),note:'',supplier:itemType==='work'?'':'\u043d\u0435 \u0443\u043a\u0430\u0437\u0430\u043d',komplektaciya:'',dozakaz:dozakazFlag,invoice_check:'',shipment_status:'',purchase_price:null,minimal_price:null,retail_price:null,base_price:0,markingSizeOptions:[],komplektaciyaOptions:[]}
  );
  getCats(t)[ci].sections[si].items[ii].unit=getDefaultUnit();
  return ii;
}
function appendBuilderRowDom(t,ci,si){
  var root=getBuilderFoldRoot(t);
  if(!root) return false;
  var cat=getCats(t)[ci];
  var catEl=builderFindCatDom(root,ci,cat);
  if(!catEl || !cat || !cat.sections || !cat.sections[si]) return false;
  var secEl=builderFindSecDom(catEl,si,cat.sections[si]);
  if(!secEl) return false;
  var tbody=secEl.querySelector('tbody');
  if(!tbody) return false;
  var tmp=document.createElement('div');
  tmp.innerHTML=buildSecHTML(t,cat,ci,cat.sections[si],si);
  var nextSecEl=tmp.firstElementChild;
  var nextBody=nextSecEl ? nextSecEl.querySelector('tbody') : null;
  var nextInputId='ac-'+t+'-'+ci+'-'+si+'-'+(cat.sections[si].items.length-1)+'-inp';
  var nextInput=nextBody ? nextBody.querySelector('input[id="'+nextInputId.replace(/"/g,'&quot;')+'"]') : null;
  var nextRow=nextInput && nextInput.closest ? nextInput.closest('tr') : null;
  if(!nextRow) return false;
  var rowClone=nextRow.cloneNode(true);
  tbody.appendChild(rowClone);
  if(isKpTarget(t)){
    enhanceKpCategoryBulkUi(root, t);
    kpRefreshSectionTotal(t,ci,si);
    kpRefreshVariantSummaryByTarget(t);
  }
  enhanceBuilderFolding(root, t);
  kpNormalizeBuilderSelects(root);
  stripNumericFieldDecimals(root);
  return true;
}
function appendBuilderCategoryDom(t,ci){
  var root=getBuilderFoldRoot(t);
  if(!root) return false;
  var cats=getCats(t)||[];
  var cat=cats[ci];
  if(!cat) return false;
  var tmp=document.createElement('div');
  tmp.innerHTML=buildCatsHTML(t,cats);
  var newCatEl=(tmp.querySelectorAll('.catblk.fi2')||[])[ci] || null;
  if(!newCatEl) return false;
  var body=root.querySelector('.kp-variant-body') || root;
  var catEls=body.querySelectorAll('.catblk.fi2');
  var beforeEl=catEls[ci] || null;
  if(beforeEl) body.insertBefore(newCatEl, beforeEl);
  else{
    var summaryEl=Array.prototype.slice.call(body.children||[]).find(function(child){
      if(!child) return false;
      if(child.id==='kp-all-variants-summary-wrap') return true;
      return !!(child.classList && child.classList.contains('kp-summary'));
    }) || null;
    if(summaryEl) summaryEl.insertAdjacentElement('beforebegin', newCatEl);
    else body.appendChild(newCatEl);
  }
  if(isKpTarget(t)){
    enhanceKpCategoryBulkUi(root, t);
  }
  enhanceBuilderFolding(root, t);
  kpNormalizeBuilderSelects(root);
  stripNumericFieldDecimals(root);
  return true;
}
function rerenderBuilderCategory(t,ci){
  var root=getBuilderFoldRoot(t);
  if(!root) return false;
  var cats=getCats(t)||[];
  var cat=cats[ci];
  if(!cat) return false;
  var tmp=document.createElement('div');
  tmp.innerHTML=buildCatsHTML(t,cats);
  var newCatEl=(tmp.querySelectorAll('.catblk.fi2')||[])[ci] || null;
  if(!newCatEl) return false;
  var body=root.querySelector('.kp-variant-body') || root;
  var oldCatEl=builderFindCatDom(body,ci,cat);
  if(oldCatEl) oldCatEl.replaceWith(newCatEl);
  else{
    var catEls=body.querySelectorAll('.catblk.fi2');
    var beforeEl=catEls[ci] || null;
    if(beforeEl) body.insertBefore(newCatEl, beforeEl);
    else{
      var summaryEl=Array.prototype.slice.call(body.children||[]).find(function(child){
        if(!child) return false;
        if(child.id==='kp-all-variants-summary-wrap') return true;
        return !!(child.classList && child.classList.contains('kp-summary'));
      }) || null;
      if(summaryEl) summaryEl.insertAdjacentElement('beforebegin', newCatEl);
      else body.appendChild(newCatEl);
    }
  }
  if(isKpTarget(t)){
    enhanceKpCategoryBulkUi(root, t);
  }
  enhanceBuilderFolding(root, t);
  kpNormalizeBuilderSelects(root);
  stripNumericFieldDecimals(root);
  return true;
}
function appendBuilderSectionDom(t,ci,si){
  var root=getBuilderFoldRoot(t);
  if(!root) return false;
  var catsData=getCats(t)||[];
  var cat=catsData[ci];
  if(!cat || !cat.sections || !cat.sections[si]) return false;
  if(builderIsWorkCategoryCode(cat.catCode) && typeof kpSortSections==='function'){
    kpSortSections(cat);
    return rerenderBuilderCategory(t,ci);
  }
  var catEl=builderFindCatDom(root,ci,cat);
  if(!catEl) return false;
  var catBody=Array.prototype.slice.call(catEl.children||[]).filter(function(child){
    return child && !(child.classList && child.classList.contains('catblk-h'));
  })[0] || null;
  if(!catBody) return false;
  var tmp=document.createElement('div');
  tmp.innerHTML=buildSecHTML(t,cat,ci,cat.sections[si],si);
  var newSecEl=tmp.firstElementChild;
  if(!newSecEl) return false;
  var summaryEl=Array.prototype.slice.call(catBody.children||[]).filter(function(child){
    return child && child.classList && child.classList.contains('kp-summary');
  })[0] || null;
  if(summaryEl) summaryEl.insertAdjacentElement('beforebegin', newSecEl);
  else catBody.appendChild(newSecEl);
  if(isKpTarget(t)){
    enhanceKpCategoryBulkUi(root, t);
  }
  enhanceBuilderFolding(root, t);
  stripNumericFieldDecimals(root);
  return true;
}
function toggleCatCollapse(t,ci){
  var key=builderCatFoldKey(t,ci);
  builderFoldState.cats[key]=!builderFoldState.cats[key];
  enhanceBuilderFolding(getBuilderFoldRoot(t), t);
}
function toggleSecCollapse(t,ci,si){
  var key=builderSecFoldKey(t,ci,si);
  builderFoldState.secs[key]=!builderFoldState.secs[key];
  enhanceBuilderFolding(getBuilderFoldRoot(t), t);
}
function builderHideFoldBody(block){
  Array.prototype.forEach.call(block.children||[], function(child, idx){
    if(idx===0) return;
    child.style.display='none';
  });
}
function builderShowFoldBody(block){
  Array.prototype.forEach.call(block.children||[], function(child, idx){
    if(idx===0) return;
    child.style.display='';
  });
}
function ensureFoldButton(head, collapsed, onClick, summaryText){
  if(!head) return;
  var titleWrap=head.firstElementChild;
  if(!titleWrap) return;
  if(!titleWrap.dataset || titleWrap.dataset.foldEnhanced!=='1'){
    titleWrap.style.display='flex';
    titleWrap.style.alignItems='center';
    titleWrap.style.minWidth='0';
    titleWrap.style.gap='8px';
    var btn=document.createElement('button');
    btn.type='button';
    btn.className='btn btn-g btn-xs fold-toggle';
    btn.textContent='▾';
    btn.onclick=function(e){ e.preventDefault(); e.stopPropagation(); onClick(); };
    titleWrap.insertBefore(btn, titleWrap.firstChild);
    var summary=document.createElement('div');
    summary.className='fold-summary';
    summary.style.display='none';
    titleWrap.appendChild(summary);
    titleWrap.dataset.foldEnhanced='1';
  }
  var foldBtn=titleWrap.querySelector('.fold-toggle');
  var foldSummary=titleWrap.querySelector('.fold-summary');
  if(foldBtn) foldBtn.classList.toggle('is-collapsed', !!collapsed);
  if(foldSummary){
    foldSummary.textContent=summaryText||'';
    foldSummary.style.display=collapsed && summaryText ? '' : 'none';
  }
}
function enhanceBuilderFolding(root,t){
  if(!root) return;
  var cats=root.querySelectorAll('.catblk.fi2');
  Array.prototype.forEach.call(cats, function(catEl, ci){
    var catCollapsed=isCatCollapsed(t,ci);
    var catHead=catEl.querySelector(':scope > .catblk-h');
    var secCount=catEl.querySelectorAll(':scope .secblk').length;
    ensureFoldButton(catHead, catCollapsed, function(){ toggleCatCollapse(t,ci); }, 'Разделов: '+secCount);
    if(catCollapsed) builderHideFoldBody(catEl); else builderShowFoldBody(catEl);
    Array.prototype.forEach.call(catEl.querySelectorAll(':scope .secblk'), function(secEl, si){
      var secCollapsed=isSecCollapsed(t,ci,si);
      var secHead=secEl.querySelector(':scope > .secblk-h');
      var itemCount=secEl.querySelectorAll('tbody tr').length;
      ensureFoldButton(secHead, secCollapsed, function(){ toggleSecCollapse(t,ci,si); }, 'Позиций: '+itemCount);
      if(secCollapsed) builderHideFoldBody(secEl); else builderShowFoldBody(secEl);
    });
  });
}
