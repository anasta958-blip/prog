async function loadKpBuilder(){
  var loadToken=++kpBuilderLoadToken;
  var titleEl=document.getElementById('kp-quote-title');
  if(titleEl) titleEl.value=(kpBuilder&&kpBuilder.title)||'';
  try{
    var refLoads=[];
    if(!kpCompany) refLoads.push(loadKpCompany());
    if(!kpClients.length) refLoads.push(loadKpClients());
    if(!kpContractors.length) refLoads.push(loadKpContractors());
    if(refLoads.length) await Promise.all(refLoads);
    if(CU && CU.role==='admin' && !kpBuilderUsers.length) await loadKpBuilderUsers();
    if(quoteWorkspaceMode==='pkp' && !pkpPresets.length) await loadPkpPresets();
  }catch(e){}
  if(loadToken!==kpBuilderLoadToken) return;
  ensureKpVariants();
  kpBuilder.variants.forEach(function(v){
    if(!v.cats){
      v.cats=(v.snapshot&&Array.isArray(v.snapshot))?v.snapshot:kpItemsToCats(v.items||[]);
    }
  });
  document.getElementById('kp-quote-title').value=kpBuilder.title||'';
  kpBuilder.status=kpBuilder.status||'created';
  renderKpBuilderFields();
  if(kpBuilder.__payloadLoading){
    var loadingWrap=document.getElementById('kp-variants-wrap');
    if(loadingWrap){
      loadingWrap.innerHTML='<div class="catblk"><div class="es">'+
        '<div class="ei">...</div><div class="et">\u0417\u0430\u0433\u0440\u0443\u0437\u043a\u0430 \u043f\u043e\u0437\u0438\u0446\u0438\u0439</div>'+
      '</div></div>';
    }
    ensureKpBuilderDocButtons();
    syncKpBuilderAccessUi();
    kpSetBuilderPayloadLoadingUi(true);
    return;
  }
  renderKpVariants();
  ensureKpBuilderDocButtons();
  syncKpBuilderAccessUi();
  kpSetBuilderPayloadLoadingUi(false);
}

function kpSetBuilderPayloadLoadingUi(isLoading){
  var saveBtn=document.getElementById('kp-builder-save-btn');
  if(saveBtn) saveBtn.disabled=!!isLoading;
}

async function loadKpBuilderUsers(){
  var users=await loadUsersDirectory();
  kpBuilderUsers=Array.isArray(users) ? users : [];
}

function kpUserDisplayName(user){
  return ((user&&user.full_name)||'').trim() || ((user&&user.username)||'').trim() || '';
}

function kpFindRopForManager(managerId){
  managerId=parseInt(managerId||0,10)||0;
  if(!managerId) return null;
  return (kpBuilderUsers||[]).find(function(user){
    return user.role==='rop' && Array.isArray(user.manager_ids) && user.manager_ids.map(function(id){return parseInt(id||0,10)||0;}).indexOf(managerId)>=0;
  })||null;
}

function kpSelectOptionsByRole(role, selectedId, selectedName){
  selectedId=parseInt(selectedId||0,10)||0;
  selectedName=String(selectedName||'').trim();
  var list=(kpBuilderUsers||[]).filter(function(user){ return user.role===role; });
  var hasSelected=selectedId && list.some(function(user){ return parseInt(user.id||0,10)===selectedId; });
  var html=role==='rop' ? '<option value="">— не указан —</option>' : '';
  if(selectedId && selectedName && !hasSelected){
    html+='<option value="'+selectedId+'">'+esc(selectedName)+'</option>';
  }
  if(!selectedId && selectedName && !list.some(function(user){ return kpUserDisplayName(user)===selectedName; })){
    html+='<option value="">'+esc(selectedName)+'</option>';
  }
  html+=list.map(function(user){
    return '<option value="'+parseInt(user.id||0,10)+'">'+esc(kpUserDisplayName(user))+'</option>';
  }).join('');
  return html;
}

function kpFillManagerRopControls(meta){
  meta=meta||{};
  var managerEl=document.getElementById('kp-quote-manager');
  var ropEl=document.getElementById('kp-quote-rop');
  if(!managerEl || !ropEl) return;
  var isAdmin=!!(CU && CU.role==='admin');
  var hasExistingManager=parseInt((kpBuilder&&kpBuilder.id)||0,10)>0 && parseInt(meta.manager_id||0,10)>0;
  var managerId=(isAdmin || hasExistingManager) ? parseInt(meta.manager_id||0,10)||0 : parseInt((CU&&CU.id)||0,10)||0;
  var ropId=(isAdmin || hasExistingManager) ? parseInt(meta.rop_id||0,10)||0 : parseInt((CU&&CU.rop_id)||0,10)||0;
  var managerName=(isAdmin || hasExistingManager) ? (meta.manager_name||getKpCurrentManagerName()) : getKpCurrentManagerName();
  var ropName=(isAdmin || hasExistingManager) ? (meta.rop_name||getKpCurrentRopName()) : getKpCurrentRopName();
  if(isAdmin && !managerId && !kpBuilder.id && managerName===getKpCurrentManagerName()){
    managerId=parseInt((CU&&CU.id)||0,10)||0;
  }
  managerEl.innerHTML=isAdmin ? kpSelectOptionsByRole('manager', managerId, managerName) : '<option value="'+managerId+'">'+esc(managerName)+'</option>';
  ropEl.innerHTML=isAdmin ? kpSelectOptionsByRole('rop', ropId, ropName) : '<option value="'+ropId+'">'+esc(ropName)+'</option>';
  managerEl.value=managerId ? String(managerId) : '';
  ropEl.value=ropId ? String(ropId) : '';
  managerEl.disabled=!isAdmin;
  ropEl.disabled=!isAdmin;
}

function kpBuilderManagerChanged(){
  if(!(CU && CU.role==='admin')) return;
  var managerEl=document.getElementById('kp-quote-manager');
  var ropEl=document.getElementById('kp-quote-rop');
  if(!managerEl || !ropEl || ropEl.value) return;
  var rop=kpFindRopForManager(managerEl.value);
  if(rop) ropEl.value=String(rop.id);
}

function renderKpBuilderFields(){
  fillKpClientSelect();
  fillKpContractorSelect();
  document.getElementById('kp-quote-client').value=kpBuilder.client_id||'';
  if(typeof syncKpPartyInput==='function') syncKpPartyInput('client');
  if(!kpBuilder.client_snapshot) kpBuilder.client_snapshot={};
  var meta=(kpBuilder.payload&&kpBuilder.payload.quote_meta)||{};
  var contractorEl=document.getElementById('kp-quote-contractor');
  if(contractorEl){
    var defaultCompany=(typeof kpDefaultCompany==='function') ? kpDefaultCompany() : null;
    contractorEl.value=meta.contractor_id ? String(meta.contractor_id) : (!kpBuilder.id && defaultCompany ? String(defaultCompany.id) : '');
    if(contractorEl.value && !meta.contractor_id && !kpBuilder.id && typeof applyKpCompanyPreset==='function') applyKpCompanyPreset(contractorEl.value);
  }
  if(typeof syncKpPartyInput==='function') syncKpPartyInput('contractor');
  var companyEl=document.getElementById('kp-quote-client-company');
  var recipientEl=document.getElementById('kp-quote-recipient');
  if(companyEl) companyEl.value=kpBuilder.client_snapshot.company_name||'';
  if(recipientEl) recipientEl.value=kpBuilder.client_snapshot.recipient_name||'';
  kpFillManagerRopControls(meta);
  var additionalEl=document.getElementById('kp-quote-additional');
  if(additionalEl){
    var payload=kpBuilder.payload&&typeof kpBuilder.payload==='object'?kpBuilder.payload:{};
    var hasAdditional=Object.prototype.hasOwnProperty.call(payload,'additional_info');
    additionalEl.value=hasAdditional ? String(payload.additional_info||'') : (!kpBuilder.id ? (getKpCompanyField('footer_default')||'') : '');
  }
}

function kpFindCat(cats, code){
  return (cats||[]).find(function(x){return x.catCode===code;})||null;
}
function kpSortBuilderCats(cats){
  if(!Array.isArray(cats)) return;
  var order={equipment:0,materials:1,work:2,construction_works:3,incidental_expenses:4,maintenance:5,kits:6};
  cats.sort(function(a,b){
    var aOrder=Object.prototype.hasOwnProperty.call(order,(a&&a.catCode)||'') ? order[a.catCode] : 999;
    var bOrder=Object.prototype.hasOwnProperty.call(order,(b&&b.catCode)||'') ? order[b.catCode] : 999;
    if(aOrder!==bOrder) return aOrder-bOrder;
    return String((a&&a.catName)||'').localeCompare(String((b&&b.catName)||''),'ru');
  });
}
function kpIsWorkCategoryCode(code){
  return code==='work' || code==='construction_works';
}
function kpGetWorkCategoryCode(sectionCode){
  return String(sectionCode||'').trim().toLowerCase()==='construction' ? 'construction_works' : 'work';
}
function kpGetWorkSectionMeta(sectionCode){
  var code=String(sectionCode||'').trim().toLowerCase() || 'installation';
  if(code==='construction') return {id:'construction',name:'Строительные работы',code:'construction'};
  if(code==='dismantling') return {id:'dismantling',name:'Демонтажные работы',code:'dismantling'};
  return {id:'installation',name:'Монтажные работы',code:'installation'};
}
function kpFindOrCreateCat(cats, code){
  var cat=kpFindCat(cats,code);
  if(cat) return cat;
  cat={catId:0,catName:kpBuilderCategoryLabel(code),catCode:code,sections:[]};
  cats.push(cat);
  kpSortBuilderCats(cats);
  return cat;
}
function kpFindOrCreateSection(cat, secId, secName, secCode, isAuto){
  var wantedCode=String(secCode||secId||'').trim().toLowerCase();
  var wantedName=String(secName||'').trim().toLocaleLowerCase('ru');
  var sec=(cat.sections||[]).find(function(x){
    if(String(x.secId)===String(secId)) return true;
    if(kpIsWorkCategoryCode(cat.catCode)){
      var existingCode=kpGetWorkScopeCode(x);
      if(wantedCode && existingCode && existingCode===wantedCode) return true;
      if(wantedName && String(x.secName||'').trim().toLocaleLowerCase('ru')===wantedName) return true;
    }
    return false;
  });
  if(sec){
    if(kpIsWorkCategoryCode(cat.catCode)){
      sec.secId=secId;
      sec.secName=secName;
      sec.secCode=secCode||String(secId||'');
    }
    if(isAuto===false) sec.is_auto=false;
    return sec;
  }
  sec={secId:secId,secName:secName,secCode:secCode||String(secId||''),isDozakaz:false,is_auto:!!isAuto,items:[]};
  cat.sections.push(sec);
  return sec;
}
function kpMergeDuplicateWorkSections(cat){
  if(!cat || !kpIsWorkCategoryCode(cat.catCode) || !Array.isArray(cat.sections)) return;
  var byKey={};
  var merged=[];
  cat.sections.forEach(function(sec){
    var scope=kpGetWorkScopeCode(sec);
    var key=scope || String(sec.secId||sec.secName||'').trim().toLocaleLowerCase('ru');
    if(!key){
      merged.push(sec);
      return;
    }
    var meta=scope ? kpGetWorkSectionMeta(scope) : null;
    if(!byKey[key]){
      if(meta){
        sec.secId=meta.id;
        sec.secName=meta.name;
        sec.secCode=meta.code;
      }
      byKey[key]=sec;
      merged.push(sec);
      return;
    }
    var target=byKey[key];
    target.items=(target.items||[]).concat(sec.items||[]);
    target.is_auto=!!(target.is_auto && sec.is_auto);
  });
  cat.sections=merged;
}
function kpSortSections(cat){
  if(!cat || !Array.isArray(cat.sections)) return;
  kpMergeDuplicateWorkSections(cat);
  cat.sections.sort(function(a,b){
    var aScope=kpGetWorkScopeCode(a);
    var bScope=kpGetWorkScopeCode(b);
    var order={installation:10,dismantling:20,construction:30};
    var aOrder=order[aScope]||100;
    var bOrder=order[bScope]||100;
    if(aOrder!==bOrder) return aOrder-bOrder;
    var aAuto=a && a.is_auto ? 1 : 0;
    var bAuto=b && b.is_auto ? 1 : 0;
    if(aAuto!==bAuto) return aAuto-bAuto;
    return 0;
  });
}
function kpRemoveAutoWorksBySource(vi, sourceUid){
  var cats=kpEnsureVariantCats(vi);
  cats.filter(function(cat){return cat && kpIsWorkCategoryCode(cat.catCode);}).forEach(function(workCat){
    (workCat.sections||[]).forEach(function(sec){
    sec.items=(sec.items||[]).filter(function(item){
      if(!item || !item.is_auto) return true;
      var links=kpAutoSourceLinks(item);
      if(!links.length){
        return item.auto_from_uid!==sourceUid;
      }
      var nextLinks=links.filter(function(link){ return String(link.uid)!==String(sourceUid); });
      if(!nextLinks.length) return false;
      var oldTotal=links.reduce(function(sum, link){return sum+(parseFloat(link.quantity||0)||0);},0);
      var newTotal=nextLinks.reduce(function(sum, link){return sum+(parseFloat(link.quantity||0)||0);},0);
      var currentQty=Math.max(parseFloat(item.quantity||0)||0,0);
      var hasManualQty=Math.abs(currentQty-oldTotal)>0.0001;
      kpSetAutoSourceLinks(item, nextLinks);
      item.quantity=hasManualQty ? Math.max(currentQty+(newTotal-oldTotal),0) : Math.max(newTotal,0);
      return true;
    });
  });
    workCat.sections=(workCat.sections||[]).filter(function(sec){return (sec.items||[]).length || !sec.is_auto;});
    kpSortSections(workCat);
  });
}
function kpRemoveObsoleteAutoWorksBySource(vi, sourceUid, keepKeys){
  var cats=kpEnsureVariantCats(vi);
  keepKeys=keepKeys||{};
  cats.filter(function(cat){return cat && kpIsWorkCategoryCode(cat.catCode);}).forEach(function(workCat){
    (workCat.sections||[]).forEach(function(sec){
      sec.items=(sec.items||[]).filter(function(item){
        if(!item || !item.is_auto) return true;
        var links=kpAutoSourceLinks(item);
        if(!links.some(function(link){ return String(link.uid)===String(sourceUid); })) return true;
        var itemKey=[
          String(item.service_id||''),
          String(item.name||item.nameTxt||''),
          String(item.marking_size||''),
          String(item.unit||'')
        ].join('|');
        if(keepKeys[itemKey]) return true;
        var nextLinks=links.filter(function(link){ return String(link.uid)!==String(sourceUid); });
        if(!nextLinks.length) return false;
        var oldTotal=links.reduce(function(sum, link){return sum+(parseFloat(link.quantity||0)||0);},0);
        var newTotal=nextLinks.reduce(function(sum, link){return sum+(parseFloat(link.quantity||0)||0);},0);
        var currentQty=Math.max(parseFloat(item.quantity||0)||0,0);
        var hasManualQty=Math.abs(currentQty-oldTotal)>0.0001;
        kpSetAutoSourceLinks(item, nextLinks);
        item.quantity=hasManualQty ? Math.max(currentQty+(newTotal-oldTotal),0) : Math.max(newTotal,0);
        return true;
      });
    });
    workCat.sections=(workCat.sections||[]).filter(function(sec){return (sec.items||[]).length || !sec.is_auto;});
    kpSortSections(workCat);
  });
}
function kpUpsertAutoWorkFromItem(vi, item){
  if(!item || !item.uid) return false;
  if(item.suppress_auto_work){
    kpRemoveAutoWorksBySource(vi, item.uid);
    return false;
  }
  var linkedServices=kpGetItemLinkedServices(item);
  if(!linkedServices.length){
    kpRemoveAutoWorksBySource(vi, item.uid);
    return false;
  }
  var keepKeys={};
  var added=false;
  linkedServices.forEach(function(service){
    var key=kpGetAutoWorkServiceKey(item,service);
    if(key) keepKeys[key]=true;
    if(kpUpsertAutoWorkServiceFromItem(vi,item,service)) added=true;
  });
  kpRemoveObsoleteAutoWorksBySource(vi, item.uid, keepKeys);
  return added;
}

function kpGetItemLinkedServices(item){
  var services=Array.isArray(item&&item.linked_services) ? item.linked_services.slice() : [];
  if(!services.length && item && item.linked_service_id){
    services=[{
      id:item.linked_service_id,
      name:item.linked_service_name||'',
      marking_size:'',
      retail_price:item.linked_service_cost||0,
      purchase_price:item.linked_service_purchase_price,
      unit:item.linked_service_unit||''
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

function kpGetAutoWorkServiceKey(item, service){
  var linkedService=(kpCatalogServices||[]).find(function(s){
    return String(s.id||'')===String(service&&service.id||'');
  })||service||null;
  if(!linkedService) return '';
  return [
    String(service&&service.id||''),
    String((linkedService&&linkedService.name)||service.name||item.linked_service_name||'Работа'),
    String(linkedService && linkedService.marking_size ? linkedService.marking_size : ''),
    String((linkedService&&linkedService.unit)||service.unit||item.linked_service_unit||item.unit||getDefaultUnit())
  ].join('|');
}

function kpUpsertAutoWorkServiceFromItem(vi,item,service){
  var linkedService=(kpCatalogServices||[]).find(function(s){
    return String(s.id||'')===String(service.id||'');
  })||service||null;
  var workSection=kpGetWorkSectionMeta(kpGetServiceWorkSectionCode(linkedService));
  var workCatCode=kpGetWorkCategoryCode(workSection.code);
  var cats=kpEnsureVariantCats(vi);
  var workCat=kpFindOrCreateCat(cats,workCatCode);
  var scopeCode=workSection.code, scopeName=workSection.name;
  var sec=kpFindOrCreateSection(workCat, workSection.id, workSection.name, workSection.code, true);
  var autoItem=kpNormalizeBuilderItem({
    uid:'auto-work-'+item.uid+'-'+(service.id||''),
    item_type:'work',
    is_auto:true,
    auto_from_uid:item.uid,
    auto_source_links:[{uid:item.uid, quantity:Math.max(parseFloat(item.quantity||0)||0,0)}],
    service_id:service.id,
    marking_size:linkedService && linkedService.marking_size ? linkedService.marking_size : '',
    name:(linkedService&&linkedService.name)||service.name||item.linked_service_name||'Работа',
    quantity:item.quantity||1,
    unit:(linkedService&&linkedService.unit)||service.unit||item.linked_service_unit||item.unit||getDefaultUnit(),
    note:'',
    purchase_price:(linkedService&&linkedService.purchase_price!=null)?linkedService.purchase_price:(service.purchase_price!=null?service.purchase_price:null),
    base_price:parseFloat((linkedService&&(linkedService.retail_price!=null?linkedService.retail_price:linkedService.cost))||(service.retail_price!=null?service.retail_price:service.cost)||0)||0,
    auto_standard_price:parseFloat((linkedService&&(linkedService.retail_price!=null?linkedService.retail_price:linkedService.cost))||(service.retail_price!=null?service.retail_price:service.cost)||0)||0,
    markup_value:0,
    discount_value:0
  },workCatCode,kpBuilderCategoryLabel(workCatCode),scopeCode,scopeName,scopeCode);
  var existing=null;
  var existingSection=null;
  (workCat.sections||[]).some(function(scanSec){
    return (scanSec.items||[]).some(function(x){
      if(!x) return false;
      var sameService=String(x.service_id||'')!=='' && String(x.service_id||'')===String(autoItem.service_id||'');
      var sameFields=kpCatalogNorm(x.name||x.nameTxt||'')===kpCatalogNorm(autoItem.name||'') &&
        kpCatalogNorm(x.marking_size||'')===kpCatalogNorm(autoItem.marking_size||'');
      var matched=(x.is_auto && sameFields && String(x.service_id||'')===String(autoItem.service_id||'')) ||
        (!x.is_auto && (sameService || sameFields));
      if(matched){
        existing=x;
        existingSection=scanSec;
        return true;
      }
      return false;
    });
  });
  if(existing){
    if(existingSection && existingSection!==sec){
      existingSection.items=(existingSection.items||[]).filter(function(x){return x!==existing;});
      sec.items=sec.items||[];
      sec.items.push(existing);
      if(!(existingSection.items||[]).length){
        workCat.sections=(workCat.sections||[]).filter(function(scanSec){return scanSec!==existingSection;});
      }
    }
    existing.item_type='work';
    existing.is_auto=true;
    existing.service_id=existing.service_id||autoItem.service_id;
    existing.name=existing.name||autoItem.name;
    existing.nameTxt=existing.nameTxt||existing.name;
    existing.marking_size=existing.marking_size||autoItem.marking_size;
    existing.unit=existing.unit||autoItem.unit;
    if(existing.purchase_price==null || existing.purchase_price==='') existing.purchase_price=autoItem.purchase_price;
    if(!(parseFloat(existing.base_price||0)>0)) existing.base_price=autoItem.base_price;
    if(!(parseFloat(existing.auto_standard_price||0)>0)) existing.auto_standard_price=autoItem.auto_standard_price;
    var oldLinks=kpAutoSourceLinks(existing);
    var oldTotal=oldLinks.reduce(function(sum, link){return sum+(parseFloat(link.quantity||0)||0);},0);
    var currentQty=Math.max(parseFloat(existing.quantity||0)||0,0);
    var links=oldLinks.filter(function(link){ return String(link.uid)!==String(item.uid); });
    links.push({uid:String(item.uid), quantity:Math.max(parseFloat(item.quantity||0)||0,0)});
    var newTotal=links.reduce(function(sum, link){return sum+(parseFloat(link.quantity||0)||0);},0);
    var hasManualQty=Math.abs(currentQty-oldTotal)>0.0001;
    kpSetAutoSourceLinks(existing, links);
    if(hasManualQty){
      existing.quantity=Math.max(currentQty+(newTotal-oldTotal),0);
    }else{
      existing.quantity=Math.max(newTotal,0);
    }
    kpMarkExternalTouched(existing);
    kpSortSections(workCat);
    return true;
  }
  kpMarkExternalTouched(autoItem);
  sec.items=sec.items||[];
  sec.items.push(autoItem);
  kpSortSections(workCat);
  return true;
}
function kpSyncVariantFromCats(vi){
  ensureKpVariants();
  kpBuilder.variants[vi].items=kpCatsToItems(kpEnsureVariantCats(vi));
  kpInvalidateVariantSummary(vi);
}
function kpDomKey(t,ci,si,ii){
  var base=String(t).replace(/[^a-zA-Z0-9_-]/g,'_');
  if(isKpTarget(t)){
    var cat=(getCats(t)||[])[ci]||{};
    var sec=((cat.sections||[])[si])||{};
    var catKey=String(cat.catCode||ci).replace(/[^a-zA-Z0-9_-]/g,'_');
    var secKey=String(sec.secCode||sec.secId||si).replace(/[^a-zA-Z0-9_-]/g,'_');
    return base+'-'+catKey+'-'+secKey+'-'+ii;
  }
  return base+'-'+ci+'-'+si+'-'+ii;
}
function kpSectionSelectAllId(t,ci,si){
  return 'kp-section-select-all-'+kpDomKey(t,ci,si,'all');
}
function kpBulkFieldId(t,ci,si,field){
  return 'kp-bulk-'+field+'-'+kpDomKey(t,ci,si,'field');
}
function kpCategoryBulkFieldId(t,ci,field){
  return 'kp-cat-bulk-'+field+'-'+String(t).replace(/[^a-zA-Z0-9_-]/g,'_')+'-'+ci;
}
function kpToggleSectionSelection(t,ci,si,checked){
  var prefix='kp-row-check-'+kpDomKey(t,ci,si,'');
  document.querySelectorAll('input[id^="'+prefix+'"]').forEach(function(cb){
    cb.checked=!!checked;
  });
}
function kpSyncSectionSelectionState(t,ci,si){
  var all=document.getElementById(kpSectionSelectAllId(t,ci,si));
  if(!all) return;
  var prefix='kp-row-check-'+kpDomKey(t,ci,si,'');
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
function kpApplyBulkFieldToSection(t,ci,si,field){
  if(!isKpTarget(t)) return;
  var input=document.getElementById(kpBulkFieldId(t,ci,si,field));
  if(!input) return;
  var raw=String(input.value||'').replace(/\s+/g,'').replace(',','.');
  if(raw===''){
    toast('Введите значение '+(field==='markup_value'?'наценки':'скидки'),'err');
    return;
  }
  var value=field==='markup_value' ? (parseFloat(raw)||0) : Math.max(parseFloat(raw)||0,0);
  var sec=((getCats(t)[ci]||{}).sections||[])[si];
  if(!sec || !Array.isArray(sec.items)) return;
  var targets=[];
  sec.items.forEach(function(item,ii){
    var cb=document.getElementById('kp-row-check-'+kpDomKey(t,ci,si,ii));
    if(cb && cb.checked) targets.push(ii);
  });
  if(!targets.length){
    targets=sec.items.map(function(_item,ii){return ii;});
  }
  var changed=0;
  targets.forEach(function(ii){
    updKpItem(t,ci,si,ii,field,value);
    changed++;
  });
  input.value='';
  kpSyncSectionSelectionState(t,ci,si);
  toast((field==='markup_value'?'Наценка':'Скидка')+' применена к '+changed+' товар(ам)');
}
function kpApplyBulkFieldToCategory(t,ci,field){
  if(!isKpTarget(t)) return;
  var input=document.getElementById(kpCategoryBulkFieldId(t,ci,field));
  if(!input) return;
  var raw=String(input.value||'').replace(/\s+/g,'').replace(',','.');
  if(raw===''){
    toast('Введите значение '+(field==='markup_value'?'наценки':'скидки'),'err');
    return;
  }
  var value=field==='markup_value' ? (parseFloat(raw)||0) : Math.max(parseFloat(raw)||0,0);
  var cat=(getCats(t)||[])[ci];
  if(!cat || !Array.isArray(cat.sections)) return;
  var changed=0;
  var targets=[];
  cat.sections.forEach(function(sec,si){
    if(!sec || !Array.isArray(sec.items)) return;
    sec.items.forEach(function(item,ii){
      var cb=document.getElementById('kp-row-check-'+kpDomKey(t,ci,si,ii));
      if(cb && cb.checked) targets.push({si:si,ii:ii});
    });
  });
  if(!targets.length){
    cat.sections.forEach(function(sec,si){
      if(!sec || !Array.isArray(sec.items)) return;
      sec.items.forEach(function(_item,ii){
        targets.push({si:si,ii:ii});
      });
    });
  }
  var cats=getCats(t);
  targets.forEach(function(pos){
    var item=(((cats[ci]||{}).sections||[])[pos.si]||{}).items ? cats[ci].sections[pos.si].items[pos.ii] : null;
    if(!item) return;
    item[field]=value;
  });
  if(isKpTarget(t)){
    kpSyncVariantFromCats(kpTargetIndex(t));
    targets.forEach(function(pos){
      kpRefreshRowDisplay(t,ci,pos.si,pos.ii);
      kpRefreshSectionTotal(t,ci,pos.si);
    });
    kpRefreshVariantSummaryByTarget(t);
  }
  var nextCat=(getCats(t)||[])[ci];
  ((nextCat&&nextCat.sections)||[]).forEach(function(sec,si){
    kpSyncSectionSelectionState(t,ci,si);
  });
  input.value='';
  toast((field==='markup_value'?'Наценка':'Скидка')+' применена к '+targets.length+' товар(ам)');
}
function kpGetCategoryTotals(cat){
  var retail=0, purchase=0;
  var variant=null;
  var percentBase=0;
  if(kpBuilder && Array.isArray(kpBuilder.variants)){
    variant=kpBuilder.variants[kpBuilder.active_variant_index]||null;
    if(variant){
      kpGetVariantItemsFlat(variant).forEach(function(item){
        if(!kpIsPercentIncidentalItem(item)) percentBase+=kpGetProductSum(item);
      });
    }
  }
  ((cat&&cat.sections)||[]).forEach(function(sec){
    (sec.items||[]).forEach(function(item){
      retail+=kpGetProductSum(item, percentBase);
      purchase+=kpGetProductPurchaseSum(item);
    });
  });
  return {
    retail:retail,
    purchase:purchase,
    margin_percent:kpGetMarginPercent(retail,purchase)
  };
}
function kpFindAutoItemPositions(vi, sourceUid){
  var cats=kpEnsureVariantCats(vi);
  var positions=[];
  for(var ci=0;ci<cats.length;ci++){
    for(var si=0;si<(cats[ci].sections||[]).length;si++){
      for(var ii=0;ii<(cats[ci].sections[si].items||[]).length;ii++){
        var item=cats[ci].sections[si].items[ii];
        if(!item || !item.is_auto) continue;
        if(item.auto_from_uid===sourceUid){
          positions.push({ci:ci,si:si,ii:ii,item:item});
          continue;
        }
        if(kpAutoSourceLinks(item).some(function(link){ return String(link.uid||'')===String(sourceUid); })){
          positions.push({ci:ci,si:si,ii:ii,item:item});
        }
      }
    }
  }
  return positions;
}
function kpFindAutoItemPosition(vi, sourceUid){
  return kpFindAutoItemPositions(vi,sourceUid)[0]||null;
}
function kpFindVariantItemPosition(vi, uid){
  var cats=kpEnsureVariantCats(vi);
  for(var ci=0;ci<cats.length;ci++){
    for(var si=0;si<(cats[ci].sections||[]).length;si++){
      for(var ii=0;ii<(cats[ci].sections[si].items||[]).length;ii++){
        var item=cats[ci].sections[si].items[ii];
        if(item && String(item.uid||'')===String(uid||'')) return {ci:ci,si:si,ii:ii,item:item};
      }
    }
  }
  return null;
}
function kpEnsureAutoWorkRowDom(t,pos){
  var key=kpDomKey(t,pos.ci,pos.si,pos.ii);
  if(document.getElementById('kp-sum-'+key)) return true;
  var root=getBuilderFoldRoot(t);
  if(!root) return false;
  var cat=(((getCats(t)||[])[pos.ci])||null);
  var catCode=cat && cat.catCode ? String(cat.catCode) : '';
  var catEl=catCode ? root.querySelector('.catblk.fi2[data-cat-code="'+catCode.replace(/"/g,'\\"')+'"]') : null;
  if(!catEl) return appendBuilderCategoryDom(t,pos.ci);
  var sec=((cat.sections||[])[pos.si])||null;
  var secId=sec && sec.secId!=null ? String(sec.secId) : '';
  var secCode=sec && sec.secCode!=null ? String(sec.secCode) : '';
  var secEl=secId ? catEl.querySelector('.secblk[data-sec-id="'+secId.replace(/"/g,'\\"')+'"]') : null;
  if(!secEl && secCode) secEl=catEl.querySelector('.secblk[data-sec-code="'+secCode.replace(/"/g,'\\"')+'"]');
  if(!secEl) return appendBuilderSectionDom(t,pos.ci,pos.si);
  if(sec && pos.ii===(sec.items||[]).length-1) return appendBuilderRowDom(t,pos.ci,pos.si);
  return rerenderBuilderSection(t,pos.ci,pos.si);
}
function kpSyncAutoWorkDomForSource(t,sourceUid,sourceCi,sourceSi,sourceIi){
  if(!isKpTarget(t)) return [];
  var vi=kpTargetIndex(t);
  var positions=kpFindAutoItemPositions(vi,sourceUid);
  positions.forEach(function(pos){
    builderFoldState.cats[builderCatFoldKey(t,pos.ci)]=false;
    builderFoldState.secs[builderSecFoldKey(t,pos.ci,pos.si)]=false;
    if(!kpEnsureAutoWorkRowDom(t,pos)) renderTargetBuilder(t);
  });
  var sourcePos=kpFindVariantItemPosition(vi,sourceUid);
  if(sourcePos){
    kpRefreshSelectedBuilderRow(t,sourcePos.ci,sourcePos.si,sourcePos.ii);
  }else if(sourceCi!==undefined && sourceSi!==undefined && sourceIi!==undefined){
    kpRefreshSelectedBuilderRow(t,sourceCi,sourceSi,sourceIi);
  }
  positions.forEach(function(pos){
    kpRefreshSelectedBuilderRow(t,pos.ci,pos.si,pos.ii);
  });
  return positions;
}
function kpRefreshRowDisplay(t,ci,si,ii){
  if(!isKpTarget(t)) return;
  var cat=(getCats(t)||[])[ci]||{};
  var sec=(cat.sections||[])[si]||{};
  var item=sec.items ? sec.items[ii] : null;
  if(!item) return;
  var key=kpDomKey(t,ci,si,ii);
  var msInput=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
  var msDrop=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-drop');
  var row=document.querySelector('#kp-sum-'+key) ? document.querySelector('#kp-sum-'+key).closest('tr') : null;
  var markupEl=document.getElementById('kp-markup-'+key);
  var discountEl=document.getElementById('kp-discount-'+key);
  var purchaseEl=document.getElementById('kp-purchase-'+key);
  var noteEl=document.getElementById('kp-note-'+key);
  var unitEl=document.getElementById('kp-unit-'+key);
  var supplierEl=document.getElementById('kp-supplier-'+key);
  var qtyEl=document.getElementById('kp-qty-'+key);
  var priceEl=document.getElementById('kp-price-'+key);
  var sumEl=document.getElementById('kp-sum-'+key);
  var minimal=Math.max(parseFloat(item.minimal_price||0)||0,0);
  var price=kpGetProductFinalPrice(item);
  var variant=(kpBuilder&&kpBuilder.variants)?kpBuilder.variants[kpTargetIndex(t)]:null;
  var percentBase=0;
  if(variant){
    kpGetVariantItemsFlat(variant).forEach(function(rowItem){
      if(!kpIsPercentIncidentalItem(rowItem)) percentBase+=kpGetProductSum(rowItem);
    });
  }
  var pendingCatalog=kpIsPendingCatalogItem(item);
  if(markupEl) markupEl.value=parseFloat(item.markup_value||0)||0;
  if(discountEl) discountEl.value=Math.max(parseFloat(item.discount_value||0)||0,0);
  if(purchaseEl) purchaseEl.value=(Math.max(parseFloat(item.purchase_price||0)||0,0)).toFixed(0);
  if(noteEl) noteEl.value=item.note||'';
  if(msInput && document.activeElement!==msInput) msInput.value=item.marking_size||'';
  if(msDrop){
    var opts=item.markingSizeOptions||[];
    msDrop.innerHTML=opts.length ? opts.map(function(o){
      return '<div class="ac-item" data-value="'+esc(String(o))+'" onmousedown="event.preventDefault();applyBuilderMarkingOption(\''+t+'\','+ci+','+si+','+ii+','+JSON.stringify(String(o))+');this.parentNode.style.display=\'none\';var inp=document.getElementById(\'acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp\');if(inp) inp.value='+JSON.stringify(String(o))+';">' + esc(o) + '</div>';
    }).join('') : '';
    if(!opts.length) msDrop.style.display='none';
  }
  if(unitEl) kpSyncSelectValue(unitEl, item.unit||'', item.unit||getDefaultUnit());
  if(supplierEl) kpSyncSelectValue(supplierEl, item.supplier||'', item.supplier||'— не указан —');
  if(unitEl) kpDeduplicateSelectOptions(unitEl);
  if(supplierEl) kpDeduplicateSelectOptions(supplierEl);
  if(qtyEl) qtyEl.value=item.quantity||1;
  if(purchaseEl) purchaseEl.disabled=!pendingCatalog;
  if(row){
    var manualWork=builderIsWorkCategoryCode(cat.catCode) && !item.is_auto;
    var externalTouched=!!(item.external_touched||item.rop_external_touched);
    row.classList.toggle('row-dozakaz', manualWork);
    row.classList.toggle('row-catalog-pending', pendingCatalog);
    row.classList.toggle('row-external-touched', externalTouched && !pendingCatalog);
    row.classList.toggle('row-excluded', !!item.excluded_from_calc);
  }
  if(priceEl){
    priceEl.value=price.toFixed(0);
    priceEl.classList.toggle('price-low', minimal>0 && price<minimal);
  }
  if(sumEl) sumEl.value=kpGetProductSum(item, percentBase).toFixed(0);
  if(item.uid){
    kpFindAutoItemPositions(kpTargetIndex(t),item.uid).forEach(function(autoPos){
      kpRefreshRowDisplay(t,autoPos.ci,autoPos.si,autoPos.ii);
    });
  }
}
function kpRefreshSectionTotal(t,ci,si){
  if(!isKpTarget(t)) return;
  kpRefreshCategorySummary(t,ci);
}
function kpRefreshPercentIncidentalRows(t){
  if(!isKpTarget(t)) return;
  var touchedCats={};
  (getCats(t)||[]).forEach(function(cat,ci){
    (cat.sections||[]).forEach(function(sec,si){
      (sec.items||[]).forEach(function(item,ii){
        if(kpIsPercentIncidentalItem(item)){
          kpRefreshRowDisplay(t,ci,si,ii);
          touchedCats[ci]=true;
        }
      });
    });
  });
  Object.keys(touchedCats).forEach(function(ci){
    kpRefreshCategorySummary(t,parseInt(ci,10));
  });
}
function kpRefreshCategorySummary(t,ci){
  if(!isKpTarget(t)) return;
  var cat=(getCats(t)||[])[ci];
  if(!cat) return;
  var totals=kpGetCategoryTotals(cat);
  var retailEl=document.getElementById('kp-category-retail-'+kpDomKey(t,ci,'summary','retail'));
  var purchaseEl=document.getElementById('kp-category-purchase-'+kpDomKey(t,ci,'summary','purchase'));
  var marginEl=document.getElementById('kp-category-margin-'+kpDomKey(t,ci,'summary','margin'));
  if(retailEl) retailEl.textContent=totals.retail.toFixed(0)+' ₽';
  if(purchaseEl) purchaseEl.textContent=totals.purchase.toFixed(0)+' ₽';
  if(marginEl) marginEl.textContent=totals.margin_percent!=null ? totals.margin_percent.toFixed(0)+'%' : '—';
  stripNumericFieldDecimals(document);
}
function kpRefreshVariantSummary(vi){
  var variant=kpBuilder.variants[vi];
  if(!variant) return;
  variant.items=kpCatsToItems(kpEnsureVariantCats(vi));
  kpInvalidateVariantSummary(vi);
  var totals=kpGetVariantTotals(variant);
  kpSetVariantSummaryCache(vi, {
    items_count:kpCountVariantItems(variant),
    totals:totals
  });
  var purchaseEl=document.getElementById('kp-summary-purchase-'+vi);
  var marginEl=document.getElementById('kp-summary-margin-'+vi);
  var totalEl=document.getElementById('kp-summary-total-'+vi);
  var vatEl=document.getElementById('kp-summary-vat-'+vi);
  var withVatEl=document.getElementById('kp-summary-with-vat-'+vi);
  var rateEl=document.getElementById('kp-summary-rate-'+vi);
  if(purchaseEl) purchaseEl.textContent=totals.purchase_total.toFixed(0)+' ₽';
  if(marginEl) marginEl.textContent=totals.margin_value.toFixed(0)+' ₽'+(totals.margin_percent!=null?' ('+totals.margin_percent.toFixed(0)+'%)':'');
  if(totalEl) totalEl.textContent=totals.total.toFixed(0)+' ₽';
  if(vatEl) vatEl.textContent=totals.vat_sum.toFixed(0)+' ₽';
  if(withVatEl) withVatEl.textContent=totals.total_with_vat.toFixed(0)+' ₽';
  if(rateEl) rateEl.textContent=totals.vat_rate ? String(totals.vat_rate)+'%' : 'Без НДС';
  kpRefreshAllVariantsSummary(kpBuilder.active_variant_index);
  stripNumericFieldDecimals(document);
}
function kpRefreshVariantSummaryByTarget(t){
  if(!isKpTarget(t)) return;
  kpRefreshPercentIncidentalRows(t);
  kpRefreshVariantSummary(kpTargetIndex(t));
}
function kpBlurActiveBuilderField(){
  var active=document.activeElement;
  if(!active || active===document.body) return;
  if(typeof active.blur!=='function') return;
  active.blur();
}
function kpResetBuilderRowItem(cat, sec, item){
  var next=kpNormalizeBuilderItem({
    quantity:1,
    note:'',
    supplier:'',
    base_price:0,
    markup_value:0,
    discount_value:0,
    purchase_price:null,
    minimal_price:null,
    retail_price:null,
    price_type:'fixed',
    linked_service_id:0,
    linked_service_name:'',
    linked_service_cost:0,
    linked_service_purchase_price:null,
    linked_service_unit:'',
    suppress_auto_work:false,
    excluded_from_calc:false,
    external_touched:false
  }, cat.catCode, cat.catName, sec.secId, sec.secName, sec.secCode);
  next.uid=item && item.uid ? item.uid : next.uid;
  return next;
}
function kpSetTargetItemFinalPrice(t,ci,si,ii,val){
  if(!isKpTarget(t)) return;
  var item=((getCats(t)[ci]||{}).sections||[])[si];
  item=item && item.items ? item.items[ii] : null;
  if(!item) return;
  var purchase=Math.max(parseFloat(item.purchase_price||0)||0,0);
  var desired=Math.max(parseFloat(val||0)||0,0);
  if(desired<purchase) desired=purchase;
  var markup=parseFloat(item.markup_value||0)||0;
  var discount=Math.max(parseFloat(item.discount_value||0)||0,0);
  var factor=1 + (markup/100) - (discount/100);
  if(factor<=0) factor=1;
  item.base_price=desired/factor;
  item.final_price=null;
  item.manual_price_override=true;
  kpMarkExternalTouched(item);
  kpSyncVariantFromCats(kpTargetIndex(t));
  kpRefreshRowDisplay(t,ci,si,ii);
  kpRefreshSectionTotal(t,ci,si);
  kpRefreshVariantSummaryByTarget(t);
}
function kpPreviewTargetItemFinalPrice(t,ci,si,ii,val){
  if(!isKpTarget(t)) return;
  var item=((getCats(t)[ci]||{}).sections||[])[si];
  item=item && item.items ? item.items[ii] : null;
  if(!item) return;
  var raw=String(val==null?'':val).trim();
  if(!raw) return;
  var desired=Math.max(parseFloat(raw)||0,0);
  var markup=parseFloat(item.markup_value||0)||0;
  var discount=Math.max(parseFloat(item.discount_value||0)||0,0);
  var factor=1 + (markup/100) - (discount/100);
  if(factor<=0) factor=1;
  item.base_price=desired/factor;
  item.final_price=null;
  item.manual_price_override=true;
  kpMarkExternalTouched(item);
  kpSyncVariantFromCats(kpTargetIndex(t));
  kpRefreshRowDisplay(t,ci,si,ii);
  kpRefreshSectionTotal(t,ci,si);
  kpRefreshVariantSummaryByTarget(t);
}
function kpPrepareVariant(vi){
  var cats=kpEnsureVariantCats(vi);
  cats.forEach(function(cat){
    if(kpIsWorkCategoryCode(cat.catCode)) kpSortSections(cat);
  });
  kpSyncVariantFromCats(vi);
}
async function kpSyncItemCatalogData(t,ci,si,ii){
  var vi=kpTargetIndex(t);
  var cats=getCats(t), cat=cats[ci], sec=cat.sections[si], item=sec.items[ii];
  if(!item || !item.nameTxt) return;
  if(kpIsWorkCategoryCode(cat.catCode)){
    await builderEnsureCatalogServicesLoaded();
    var workScopeCode=kpGetWorkScopeCode(sec);
    var serviceVariants=kpCatalogServices.filter(function(s){
      var matchesSection=!workScopeCode ||
        ((workScopeCode==='installation' || workScopeCode==='construction' || workScopeCode==='dismantling')
          ? kpGetServiceWorkSectionCode(s)===String(workScopeCode)
          : true);
      return s.name===item.nameTxt && matchesSection;
    });
    item.markingSizeOptions=[...new Set(serviceVariants.map(function(s){return s.marking_size||'';}).filter(Boolean))];
    var service=null;
    var hasWorkMarking=kpCatalogNorm(item.marking_size||'')!=='';
    var workMarkingVariants=serviceVariants.filter(function(s){
      return kpCatalogNorm(s.marking_size||'')===kpCatalogNorm(item.marking_size||'');
    });
    if(hasWorkMarking && workMarkingVariants.length===1){
      service=workMarkingVariants[0];
    }else if(hasWorkMarking && workMarkingVariants.length>1){
      service=workMarkingVariants.find(function(s){
        return kpCatalogNorm(s.unit||'')===kpCatalogNorm(item.unit||'');
      })||workMarkingVariants[0]||null;
    }
    if(!service && serviceVariants.length===1 && item.markingSizeOptions.length<=1){
      service=serviceVariants[0];
      item.marking_size=service.marking_size||'';
      var workMsInp=document.getElementById('acms-'+t+'-'+ci+'-'+si+'-'+ii+'-inp');
      if(workMsInp) workMsInp.value=item.marking_size||'';
    }
    if(!service) return;
    item.service_id=parseInt(service.id,10)||0;
    item.item_type='work';
    item.name=service.name||item.nameTxt;
    item.nameTxt=item.name;
    item.unit=service.unit||item.unit||getDefaultUnit();
    item.purchase_price=service.purchase_price!=null?service.purchase_price:null;
    item.minimal_price=service.minimal_price!=null?service.minimal_price:null;
    item.retail_price=(service.retail_price!=null && service.retail_price!=='') ? service.retail_price : (service.cost!=null ? service.cost : null);
    item.base_price=parseFloat(item.retail_price||0)||0;
    item.final_price=null;
    item.manual_price_override=false;
    kpSyncVariantFromCats(vi);
    kpRefreshRowDisplay(t,ci,si,ii);
    kpRefreshSectionTotal(t,ci,si);
    kpRefreshVariantSummaryByTarget(t);
    return;
  }
  if(!Array.isArray(kpCatalogProducts) || !kpCatalogProducts.length){
    try{ await loadKpCatalogProducts(); }catch(e){}
  }
  await syncItemCatalogDataDocLike(t,ci,si,ii);
  var enriched=kpFindCatalogProductExact(sec.secId, item, kpCatalogProducts||[]);
  if(!enriched && parseInt(item.nameId||item.product_name_id||0,10)>0){
    enriched=(kpCatalogProducts||[]).find(function(p){
      return String(p.id)===String(item.nameId||item.product_name_id||'');
    })||null;
  }
  if((!allNamesCache || !allNamesCache.length) && item.nameId){
    try{
      allNamesCache=await api('catalog.php?action=all_names');
    }catch(e){}
  }
  if(!enriched){
    enriched=kpFindCatalogProductExact(sec.secId, item, allNamesCache||[]);
  }
  if(!enriched && parseInt(item.nameId||item.product_name_id||0,10)>0){
    enriched=(allNamesCache||[]).find(function(p){return String(p.id)===String(item.nameId||item.product_name_id||'');})||null;
  }
  enriched=await kpEnsureFullCatalogProduct(enriched, sec.secId, item);
  if(enriched && !kpFindCatalogProductExact(sec.secId, item, [enriched])){
    enriched=null;
  }
  if(enriched){
    var isKit=String(enriched.category_code||cat.catCode||'')==='kits';
    var kitRetail=(enriched.retail_price!=null && enriched.retail_price!=='') ? enriched.retail_price : (enriched.price!=null ? enriched.price : item.retail_price);
    item.item_type='product';
    item.product_name_id=parseInt(enriched.id,10)||0;
    item.nameId=item.product_name_id;
    item.category_id=enriched.category_id||0;
    item.category_code=enriched.category_code||cat.catCode;
    item.category_name=enriched.category_name||cat.catName;
    item.catalog_status=enriched.status||'';
    item.section_id=enriched.section_id||sec.secId;
    item.section_name=enriched.section_name||sec.secName;
    item.section_code=enriched.section_code||sec.secCode;
    item.name=enriched.name||item.nameTxt;
    item.nameTxt=item.name;
    item.unit=enriched.unit||item.unit||getDefaultUnit();
    item.supplier=enriched.supplier||item.supplier||'не указан';
    item.note=enriched.note||'';
    item.purchase_price=enriched.purchase_price;
    item.minimal_price=enriched.minimal_price;
    item.retail_price=enriched.retail_price;
    item.price_type=enriched.price_type==='percent'?'percent':'fixed';
    item.base_price=parseFloat(enriched.retail_price||0)||0;
    item.final_price=null;
    item.manual_price_override=false;
    item.linked_service_id=enriched.linked_service_id||0;
    item.linked_service_name=enriched.linked_service_name||'';
    item.linked_service_cost=enriched.linked_service_cost||0;
    item.linked_service_purchase_price=enriched.linked_service_purchase_price!=null?enriched.linked_service_purchase_price:null;
    item.linked_service_unit=enriched.linked_service_unit||'';
    item.linked_services=Array.isArray(enriched.linked_services)?enriched.linked_services.slice():[];
    if(isKit){
      item.group_name='комплекты';
      item.supplier='';
      item.note='';
      item.purchase_price=0;
      item.retail_price=kitRetail;
      item.base_price=parseFloat(kitRetail||0)||0;
      item.linked_service_id=0;
      item.linked_service_name='';
      item.linked_service_cost=0;
      item.linked_service_purchase_price=null;
      item.linked_service_unit='';
      item.linked_services=[];
    }
    kpMarkExternalTouched(item);
    var autoAdded=isKit ? false : kpUpsertAutoWorkFromItem(vi,item);
    kpSyncVariantFromCats(vi);
    if(autoAdded){
      var autoPositions=kpSyncAutoWorkDomForSource(t,item.uid,ci,si,ii);
      if(!autoPositions.length){
        renderTargetBuilder(t);
      }
      return;
    }
    kpRefreshRowDisplay(t,ci,si,ii);
    kpRefreshSectionTotal(t,ci,si);
    kpRefreshVariantSummaryByTarget(t);
    kpRefreshAllVariantsSummary(vi);
  }else{
    kpResetProductCatalogLink(item, cat, sec);
    kpSyncVariantFromCats(vi);
    return;
  }
  kpSyncVariantFromCats(vi);
}

async function kpEnsureFullCatalogProduct(product, secId, item){
  var productId=parseInt((product&&product.id)||(item&&item.nameId)||(item&&item.product_name_id)||0,10)||0;
  var hasZeroPrice=!!product && (
    (parseFloat(product.purchase_price||0)||0)<=0 ||
    (parseFloat(product.retail_price||0)||0)<=0
  );
  var needsFull=!product ||
    product.purchase_price===undefined ||
    product.retail_price===undefined ||
    hasZeroPrice ||
    product.category_id===undefined ||
    product.section_name===undefined;
  if(!needsFull) return product;
  try{
    allNamesCache=await api('catalog.php?action=all_names');
  }catch(e){}
  var full=null;
  if(hasZeroPrice){
    full=kpFindCatalogProductExact(secId, item, allNamesCache||[]);
  }
  if(!full && productId){
    full=(allNamesCache||[]).find(function(p){return String(p.id)===String(productId);})||null;
  }
  if(!full){
    full=kpFindCatalogProductExact(secId, item, allNamesCache||[]);
  }
  return full||product||null;
}
function updKpItem(t,ci,si,ii,field,val){
  if(field==='markup_value'){
    val=parseFloat(val||0)||0;
  }else if(field==='quantity' || field==='base_price' || field==='discount_value' || field==='purchase_price'){
    val=Math.max(parseFloat(val||0)||0,0);
  }
  var vi=kpTargetIndex(t);
  var cats=getCats(t)||[];
  var cat=cats[ci];
  var sec=cat && cat.sections ? cat.sections[si] : null;
  var item=getCats(t)[ci].sections[si].items[ii];
  if(field==='nameTxt' && !String(val||'').trim()){
    var autoPosBeforeEmpty=item && item.uid ? kpFindAutoItemPosition(vi,item.uid) : null;
    if(item && item.uid) kpRemoveAutoWorksBySource(vi,item.uid);
    getCats(t)[ci].sections[si].items[ii]=kpResetBuilderRowItem(cat, sec, item);
    kpMarkExternalTouched(getCats(t)[ci].sections[si].items[ii]);
    kpSyncVariantFromCats(vi);
    if(autoPosBeforeEmpty && autoPosBeforeEmpty.ci!==ci){
      if(!rerenderBuilderCategory(t,autoPosBeforeEmpty.ci)) renderTargetBuilder(t);
      else kpRefreshCategorySummary(t,autoPosBeforeEmpty.ci);
    }
    if(!rerenderBuilderSection(t,ci,si)) renderTargetBuilder(t);
    else{
      kpRefreshSectionTotal(t,ci,si);
      kpRefreshVariantSummaryByTarget(t);
    }
    return;
  }
  updItem(t,ci,si,ii,field,val);
  item=getCats(t)[ci].sections[si].items[ii];
  kpMarkExternalTouched(item);
  if(field==='nameTxt'){
    item.name=val;
  }
  if((field==='markup_value' || field==='discount_value') && item && item.item_type!=='work' && parseInt(item.product_name_id||item.nameId||0,10)>0 && !item.manual_price_override){
    item.base_price=parseFloat(item.retail_price||item.base_price||0)||0;
  }
  if((field==='nameTxt' || field==='marking_size') && item && item.item_type!=='work' && !item.is_auto){
    var autoPosBefore=item.uid ? kpFindAutoItemPosition(vi,item.uid) : null;
    if(item.uid){
      kpRemoveAutoWorksBySource(vi,item.uid);
    }
    kpDetachProductCatalogIdentity(item, cat, sec);
    if(autoPosBefore && autoPosBefore.ci!==ci){
      if(!rerenderBuilderCategory(t,autoPosBefore.ci)) renderTargetBuilder(t);
      else kpRefreshCategorySummary(t,autoPosBefore.ci);
    }
  }
  if(field==='quantity' && item && item.uid && !item.is_auto && item.category_code!=='kits'){
    if(kpUpsertAutoWorkFromItem(vi,item)){
      kpSyncAutoWorkDomForSource(t,item.uid,ci,si,ii);
    }
  }
  if(field==='base_price' || field==='markup_value' || field==='discount_value' || field==='purchase_price' || field==='quantity' || field==='unit' || field==='marking_size' || field==='note' || field==='nameTxt' || field==='supplier' || field==='excluded_from_calc'){
    kpSyncVariantFromCats(vi);
  }
  if(field==='base_price' || field==='markup_value' || field==='discount_value' || field==='purchase_price' || field==='quantity' || field==='unit' || field==='marking_size' || field==='nameTxt' || field==='supplier' || field==='excluded_from_calc'){
    kpRefreshRowDisplay(t,ci,si,ii);
  }
  if(field==='base_price' || field==='markup_value' || field==='discount_value' || field==='purchase_price' || field==='quantity' || field==='unit' || field==='marking_size' || field==='nameTxt' || field==='supplier' || field==='excluded_from_calc'){
    kpRefreshSectionTotal(t,ci,si);
  }
  kpRefreshVariantSummaryByTarget(t);
}
function kpNonNegativeInput(el){
  var raw=String((el&&el.value)!=null?el.value:'').trim();
  if(raw==='') return;
  var val=parseFloat(raw);
  if(!isFinite(val)) return;
  if(val<0) el.value='0';
}

function setKpItemField(vi,ii,field,val){
  kpBuilder.variants[vi].items[ii][field]=val;
  if(field==='product_name_id'){
    var p=kpCatalogProducts.find(function(x){return x.id==val;});
    if(p){
      var item=kpBuilder.variants[vi].items[ii];
      item.category_id=p.category_id; item.category_code=p.category_code; item.category_name=p.category_name;
      item.section_id=p.section_id; item.section_name=p.section_name; item.name=p.name; item.marking_size=p.marking_size||'';
      item.unit=p.unit||''; item.note=p.note||''; item.purchase_price=p.purchase_price; item.minimal_price=p.minimal_price; item.retail_price=p.retail_price;
      item.linked_service_id=p.linked_service_id||0; item.linked_service_name=p.linked_service_name||''; item.linked_service_cost=p.linked_service_cost||0; item.linked_service_purchase_price=p.linked_service_purchase_price!=null?p.linked_service_purchase_price:null; item.linked_service_unit=p.linked_service_unit||''; item.linked_services=Array.isArray(p.linked_services)?p.linked_services.slice():[];
    }
  }
  renderKpVariants();
}

function addKpVariantItem(vi,categoryCode){
  kpBuilder.variants[vi].items.push({
    product_name_id:'',category_code:categoryCode,quantity:1,unit:getDefaultUnit(),name:'',marking_size:'',
    purchase_price:null,minimal_price:null,retail_price:null,linked_service_id:0,linked_service_name:'',linked_service_cost:0,linked_service_purchase_price:null,linked_service_unit:''
  });
  renderKpVariants();
}

function getKpVariantItems(variant,categoryCode){
  return (variant.items||[]).filter(function(it){return (it.category_code||'')===categoryCode;});
}

function kpGetVariantAddState(vi){
  var variant=kpBuilder.variants[vi];
  if(!variant.add_state) variant.add_state={category_code:'equipment',section_id:'',group_name:'',object_id:''};
  return variant.add_state;
}

function kpGetBuilderSections(categoryCode){
  if(categoryCode==='work'){
    var workSections=kpCatalogSections.filter(function(s){
      return s.category_code==='work' && String(s.code||'')!=='construction';
    });
    if(workSections.length) return workSections;
    return [
      {id:'installation',name:'Монтажные работы',code:'installation'},
      {id:'dismantling',name:'Демонтажные работы',code:'dismantling'}
    ];
  }
  if(categoryCode==='construction_works'){
    var constructionSections=kpCatalogSections.filter(function(s){
      return (s.category_code==='construction_works' || s.category_code==='work') && String(s.code||'')==='construction';
    });
    if(constructionSections.length) return constructionSections;
    return [{id:'construction',name:'Строительные работы',code:'construction'}];
  }
  if(categoryCode==='maintenance'){
    var maintenanceSections=kpCatalogSections.filter(function(s){return s.category_code==='maintenance';});
    if(maintenanceSections.length) return maintenanceSections;
    return [{id:'maintenance_main',name:'Обслуживание',code:'maintenance_main'}];
  }
  if(categoryCode==='kits'){
    var kitSections=kpCatalogSections.filter(function(s){return s.category_code==='kits';});
    if(kitSections.length) return kitSections;
    return [{id:'kits_main',name:'Комплекты',code:'kits_main'}];
  }
  return kpCatalogSections.filter(function(s){return s.category_code===categoryCode;});
}

function kpGetBuilderObjects(categoryCode, sectionId, groupName){
  if(kpIsWorkCategoryCode(categoryCode)){
    var sectionMeta=kpGetBuilderSections(categoryCode).find(function(section){
      return String(section.id)===String(sectionId);
    })||null;
    var workScopeCode=sectionMeta ? (sectionMeta.code||sectionMeta.id||'') : sectionId;
    return kpCatalogServices.filter(function(s){
      return !workScopeCode || kpGetServiceWorkSectionCode(s)===String(workScopeCode);
    });
  }
  if(categoryCode==='kits'){
    return kpCatalogProducts.filter(function(p){
      return p.category_code==='kits' &&
        (!sectionId || String(p.section_id)===String(sectionId)) &&
        (!groupName || catalogGroupNorm(p.group_name||'')===catalogGroupNorm(groupName));
    });
  }
  return kpCatalogProducts.filter(function(p){
    return p.category_code===categoryCode &&
      (!sectionId || String(p.section_id)===String(sectionId)) &&
      (!groupName || catalogGroupNorm(p.group_name||'')===catalogGroupNorm(groupName));
  });
}
function kpGetBuilderGroups(categoryCode, sectionId){
  if(kpIsWorkCategoryCode(categoryCode)) return [];
  return getSectionGroupOptions(sectionId);
}

function kpGetProductFinalPrice(item){
  var rawBase=(item&&item.base_price!==undefined && item.base_price!==null && item.base_price!=='') ? item.base_price : (item ? (item.retail_price||0) : 0);
  var base=parseFloat(rawBase)||0;
  var markup=parseFloat(item.markup_value||0)||0;
  var discount=Math.max(parseFloat(item.discount_value||0)||0,0);
  var factor=1 + (markup/100) - (discount/100);
  if(factor<0) factor=0;
  return Math.max(base * factor,0);
}

function kpIsPercentIncidentalItem(item){
  return !!(item && item.category_code==='incidental_expenses' && item.price_type==='percent');
}

function kpIsExcludedFromCalc(item){
  return !!(item && item.excluded_from_calc);
}

function kpGetProductSum(item, percentBase){
  if(kpIsExcludedFromCalc(item)) return 0;
  var price=kpGetProductFinalPrice(item);
  var qty=Math.max(parseFloat(item.quantity||0)||0,0);
  if(kpIsPercentIncidentalItem(item)){
    var base=Math.max(parseFloat(percentBase||0)||0,0);
    return base * (price/100) * qty;
  }
  return price * qty;
}
function kpGetProductPurchaseSum(item){
  if(kpIsExcludedFromCalc(item)) return 0;
  var purchase=Math.max(parseFloat(item.purchase_price||0)||0,0);
  var qty=Math.max(parseFloat(item.quantity||0)||0,0);
  return purchase * qty;
}
function kpGetMarginPercent(retail, purchase){
  retail=Math.max(parseFloat(retail||0)||0,0);
  purchase=Math.max(parseFloat(purchase||0)||0,0);
  if(purchase<=0) return null;
  return ((retail-purchase)/purchase)*100;
}
function kpGetVariantVatMode(variant){
  if(variant && variant.vat_mode) return variant.vat_mode;
  return (kpBuilder.payload&&kpBuilder.payload.vat_mode)||'none';
}
function kpGetVatRateValue(mode){
  if(mode==='5') return 5;
  if(mode==='22') return 22;
  return 0;
}
function kpGetVariantItemsFlat(variant){
  if(variant && Array.isArray(variant.items) && variant.items.length) return variant.items;
  return kpCatsToItems((variant&&variant.cats)||[]);
}
function kpGetVariantTotals(variant){
  var items=kpGetVariantItemsFlat(variant);
  var total=0, vatBase=0, purchaseTotal=0;
  var vatRate=kpGetVatRateValue(kpGetVariantVatMode(variant));
  var percentBase=0;
  items.forEach(function(item){
    if(!kpIsPercentIncidentalItem(item)) percentBase+=kpGetProductSum(item);
  });
  items.forEach(function(item){
    var line=kpGetProductSum(item, percentBase);
    var purchaseLine=kpGetProductPurchaseSum(item);
    total+=line;
    purchaseTotal+=purchaseLine;
    vatBase+=line;
  });
  var vatSum=vatBase*(vatRate/100);
  var marginValue=total-purchaseTotal;
  return {
    total:total,
    vat_sum:vatSum,
    total_with_vat:total+vatSum,
    vat_rate:vatRate,
    purchase_total:purchaseTotal,
    margin_value:marginValue,
    margin_percent:kpGetMarginPercent(total,purchaseTotal)
  };
}
function kpCountVariantItems(variant){
  return kpGetVariantItemsFlat(variant).filter(function(item){
    return item && !item.excluded_from_calc;
  }).length;
}
function kpSummaryMoney(value){
  return esc((Number(value)||0).toFixed(0))+' ₽';
}
function kpGetProposalTypeTotals(type){
  type=type&&typeof type==='object'?type:{};
  var variants=Array.isArray(type.variants)?type.variants:[];
  var totals={
    variants_count:variants.length,
    items_count:0,
    total:0,
    vat_sum:0,
    total_with_vat:0,
    purchase_total:0,
    margin_value:0,
    margin_percent:null
  };
  variants.forEach(function(variant){
    var variantTotals=kpGetVariantTotals(variant);
    totals.items_count+=kpCountVariantItems(variant);
    totals.total+=variantTotals.total;
    totals.vat_sum+=variantTotals.vat_sum;
    totals.total_with_vat+=variantTotals.total_with_vat;
    totals.purchase_total+=variantTotals.purchase_total;
  });
  totals.margin_value=totals.total-totals.purchase_total;
  totals.margin_percent=kpGetMarginPercent(totals.total,totals.purchase_total);
  return totals;
}
function kpBuildProposalTypeSummaryHtml(type){
  var totals=kpGetProposalTypeTotals(type);
  var marginText=kpSummaryMoney(totals.margin_value)+(totals.margin_percent!=null?' ('+esc(totals.margin_percent.toFixed(0))+'%)':'');
  return '<div class="kp-summary kp-proposal-type-summary" id="kp-proposal-type-summary-wrap">'+
    '<div class="ctitle" style="margin-bottom:10px">Сводка типа</div>'+
    '<div class="kp-summary-row">'+
      '<div><div class="mlb">Вариантов</div><div class="mvl">'+esc(String(totals.variants_count))+'</div></div>'+
      '<div><div class="mlb">Позиций</div><div class="mvl">'+esc(String(totals.items_count))+'</div></div>'+
      '<div><div class="mlb">Итог розница</div><div class="mvl">'+kpSummaryMoney(totals.total)+'</div></div>'+
      '<div><div class="mlb">Итог закупка</div><div class="mvl">'+kpSummaryMoney(totals.purchase_total)+'</div></div>'+
      '<div><div class="mlb">Маржа</div><div class="mvl">'+marginText+'</div></div>'+
    '</div>'+
  '</div>';
}
function kpVariantSummaryCacheKey(vi){
  var type=kpCurrentProposalType ? kpCurrentProposalType() : null;
  var variant=(kpBuilder&&kpBuilder.variants&&kpBuilder.variants[vi])||null;
  return String((type&&type.id)||kpBuilder.active_type_index||0)+'::'+String((variant&&variant.id)||vi);
}
function kpInvalidateVariantSummary(vi){
  if(!kpVariantSummaryCache || typeof kpVariantSummaryCache!=='object') kpVariantSummaryCache={};
  if(typeof vi==='number'){
    delete kpVariantSummaryCache[kpVariantSummaryCacheKey(vi)];
  }else{
    kpVariantSummaryCache={};
  }
}
function kpSetVariantSummaryCache(vi, data){
  if(!kpVariantSummaryCache || typeof kpVariantSummaryCache!=='object') kpVariantSummaryCache={};
  kpVariantSummaryCache[kpVariantSummaryCacheKey(vi)]=data||null;
}
function kpGetVariantSummaryData(variant, vi){
  if(!kpVariantSummaryCache || typeof kpVariantSummaryCache!=='object') kpVariantSummaryCache={};
  var key=kpVariantSummaryCacheKey(vi);
  if(kpVariantSummaryCache[key]) return kpVariantSummaryCache[key];
  var data={
    items_count:kpCountVariantItems(variant),
    totals:kpGetVariantTotals(variant)
  };
  kpVariantSummaryCache[key]=data;
  return data;
}
function kpBuildAllVariantsSummaryHtml(activeIndex){
  ensureKpVariants();
  var variants=(kpBuilder&&kpBuilder.variants)||[];
  if(!variants.length) return '';
  var rows=variants.map(function(variant,vi){
    var summary=kpGetVariantSummaryData(variant,vi);
    return {
      index:vi,
      label:(variant.label||kpVariantDefaultLabel(vi)),
      note:(variant.note||'').trim(),
      items_count:summary.items_count,
      totals:summary.totals
    };
  });
  var minTotalRow=rows[0];
  var maxTotalRow=rows[0];
  var bestMarginRow=rows[0];
  rows.forEach(function(row){
    if(row.totals.total<minTotalRow.totals.total) minTotalRow=row;
    if(row.totals.total>maxTotalRow.totals.total) maxTotalRow=row;
    if(row.totals.margin_value>bestMarginRow.totals.margin_value) bestMarginRow=row;
  });
  var spread=maxTotalRow.totals.total-minTotalRow.totals.total;
  return '<div class="kp-summary kp-all-variants-summary">'+
    '<div class="ctitle" style="margin-bottom:10px">Общая сводка по вариантам</div>'+
    '<div class="kp-summary-row">'+
      '<div><div class="mlb">Вариантов</div><div class="mvl">'+esc(String(rows.length))+'</div></div>'+
      '<div><div class="mlb">Минимум для клиента</div><div class="mvl">'+kpSummaryMoney(minTotalRow.totals.total)+'</div><div class="kp-all-variants-meta">'+esc(minTotalRow.label)+'</div></div>'+
      '<div><div class="mlb">Максимум для клиента</div><div class="mvl">'+kpSummaryMoney(maxTotalRow.totals.total)+'</div><div class="kp-all-variants-meta">'+esc(maxTotalRow.label)+'</div></div>'+
      '<div><div class="mlb">Разница</div><div class="mvl">'+kpSummaryMoney(spread)+'</div><div class="kp-all-variants-meta">между минимумом и максимумом</div></div>'+
      '<div><div class="mlb">Лучшая маржа</div><div class="mvl">'+kpSummaryMoney(bestMarginRow.totals.margin_value)+'</div><div class="kp-all-variants-meta">'+esc(bestMarginRow.label)+(bestMarginRow.totals.margin_percent!=null?' · '+esc(bestMarginRow.totals.margin_percent.toFixed(0))+'%':'')+'</div></div>'+
    '</div>'+
    '<div class="kp-all-variants-grid">'+
      '<div class="kp-all-variants-row kp-all-variants-head">'+
        '<div class="mlb">Вариант</div>'+
        '<div class="mlb">Позиций</div>'+
        '<div class="mlb">Клиент</div>'+
        '<div class="mlb">С НДС</div>'+
        '<div class="mlb">Закупка</div>'+
        '<div class="mlb">Маржа</div>'+
      '</div>'+
      rows.map(function(row){
        var totals=row.totals;
        var marginText=kpSummaryMoney(totals.margin_value)+(totals.margin_percent!=null?' ('+esc(totals.margin_percent.toFixed(0))+'%)':'');
        return '<div class="kp-all-variants-row'+(row.index===activeIndex?' active':'')+'">'+
          '<div><div class="kp-all-variants-name">'+esc(row.label)+'</div>'+(row.note?'<div class="kp-all-variants-note">'+esc(row.note)+'</div>':'')+'</div>'+
          '<div><div class="kp-all-variants-value">'+esc(String(row.items_count))+'</div><div class="kp-all-variants-meta">в расчёте</div></div>'+
          '<div><div class="kp-all-variants-value">'+kpSummaryMoney(totals.total)+'</div><div class="kp-all-variants-meta">'+(totals.vat_rate?esc(String(totals.vat_rate))+'% НДС':'Без НДС')+'</div></div>'+
          '<div><div class="kp-all-variants-value">'+kpSummaryMoney(totals.total_with_vat)+'</div><div class="kp-all-variants-meta">для клиента</div></div>'+
          '<div><div class="kp-all-variants-value">'+kpSummaryMoney(totals.purchase_total)+'</div><div class="kp-all-variants-meta">себестоимость</div></div>'+
          '<div><div class="kp-all-variants-value">'+marginText+'</div><div class="kp-all-variants-meta">по варианту</div></div>'+
        '</div>';
      }).join('')+
    '</div>'+
  '</div>';
}
function kpRefreshAllVariantsSummary(activeIndex){
  var typeHost=document.getElementById('kp-proposal-type-summary-wrap');
  if(typeHost && typeof kpCurrentProposalType==='function'){
    typeHost.outerHTML=kpBuildProposalTypeSummaryHtml(kpCurrentProposalType());
  }
  var host=document.getElementById('kp-all-variants-summary-wrap');
  if(!host) return;
  host.innerHTML=kpBuildAllVariantsSummaryHtml(typeof activeIndex==='number'?activeIndex:(kpBuilder.active_variant_index||0));
}

function kpMakeAutoWorkItem(item){
  if(!item.linked_service_id) return null;
  var linkedService=(kpCatalogServices||[]).find(function(s){
    return String(s.id||'')===String(item.linked_service_id||'');
  })||null;
  var workSection=kpGetWorkSectionMeta(kpGetServiceWorkSectionCode(linkedService));
  var workCatCode=kpGetWorkCategoryCode(workSection.code);
  return {
    uid:'auto-work-'+item.uid,
    item_type:'work',
    is_auto:true,
    auto_from_uid:item.uid,
    category_code:workCatCode,
    category_name:kpBuilderCategoryLabel(workCatCode),
    section_id:workSection.id,
    section_name:workSection.name,
    service_id:item.linked_service_id,
    name:item.linked_service_name||'Работа',
    marking_size:linkedService && linkedService.marking_size ? linkedService.marking_size : '',
    quantity:item.quantity||1,
    unit:item.linked_service_unit||item.unit||getDefaultUnit(),
    note:'',
    purchase_price:item.linked_service_purchase_price!=null?item.linked_service_purchase_price:null,
    base_price:parseFloat(item.linked_service_cost||0)||0,
    markup_value:0,
    discount_value:0
  };
}

function kpSyncVariantAutoWorks(vi){
  var variant=kpBuilder.variants[vi];
  if(!variant) return;
  variant.items=(variant.items||[]).filter(function(item){
    if(!item.is_auto) return true;
    return (variant.items||[]).some(function(src){return src.uid===item.auto_from_uid && src.category_code!=='kits' && kpGetItemLinkedServices(src).length && !src.suppress_auto_work;});
  });
  (variant.items||[]).forEach(function(item){
    if(item.item_type!=='product' || item.category_code==='kits' || !kpGetItemLinkedServices(item).length || item.suppress_auto_work) return;
    kpUpsertAutoWorkFromItem(vi,item);
  });
}

function kpSetVariantAddField(vi,field,val){
  var st=kpGetVariantAddState(vi);
  st[field]=val;
  if(field==='category_code'){
    st.section_id='';
    st.group_name='';
    st.object_id='';
    var sections=kpGetBuilderSections(val);
    if(sections.length===1) st.section_id=String(sections[0].id);
  }
  if(field==='section_id'){
    st.group_name='';
    st.object_id='';
  }
  if(field==='group_name') st.object_id='';
  renderKpVariants();
}

function kpCreateBuilderProductItem(product){
  var isKit=String(product.category_code||'')==='kits';
  var retail=(product.retail_price!=null && product.retail_price!=='') ? product.retail_price : (product.price!=null ? product.price : 0);
  return {
    uid:'p-'+Date.now()+'-'+Math.random().toString(36).slice(2,8),
    item_type:'product',
    product_name_id:parseInt(product.id,10)||0,
    category_id:product.category_id||0,
    category_code:product.category_code||'',
    category_name:product.category_name||'',
    section_id:product.section_id||0,
    section_name:product.section_name||'',
    group_name:isKit?(product.group_name||'комплекты'):(product.group_name||''),
    name:product.name||'',
    marking_size:product.marking_size||'',
    quantity:1,
    unit:product.unit||getDefaultUnit(),
    note:product.note||'',
    supplier:isKit?'':(product.supplier||''),
    purchase_price:isKit?0:product.purchase_price,
    minimal_price:product.minimal_price,
    retail_price:retail,
    price_type:product.price_type==='percent'?'percent':'fixed',
    base_price:parseFloat(retail||0)||0,
    markup_value:0,
    discount_value:0,
    suppress_auto_work:false,
    linked_service_id:isKit?0:(product.linked_service_id||0),
    linked_service_name:isKit?'':(product.linked_service_name||''),
    linked_service_cost:isKit?0:(product.linked_service_cost||0),
    linked_service_purchase_price:isKit?null:(product.linked_service_purchase_price!=null?product.linked_service_purchase_price:null),
    linked_service_unit:isKit?'':(product.linked_service_unit||''),
    linked_services:isKit?[]:(Array.isArray(product.linked_services)?product.linked_services.slice():[])
  };
}

function kpCreateBuilderWorkItem(service){
  var workSection=kpGetWorkSectionMeta(kpGetServiceWorkSectionCode(service));
  var workCatCode=kpGetWorkCategoryCode(workSection.code);
  var retail=(service.retail_price!=null && service.retail_price!=='') ? service.retail_price : (service.cost!=null ? service.cost : null);
  return {
    uid:'w-'+Date.now()+'-'+Math.random().toString(36).slice(2,8),
    item_type:'work',
    category_code:workCatCode,
    category_name:kpBuilderCategoryLabel(workCatCode),
    section_id:workSection.id,
    section_name:workSection.name,
    service_id:parseInt(service.id,10)||0,
    name:service.name||'',
    marking_size:'',
    quantity:1,
    unit:service.unit||getDefaultUnit(),
    note:'',
    purchase_price:service.purchase_price!=null?service.purchase_price:null,
    minimal_price:service.minimal_price!=null?service.minimal_price:null,
    retail_price:retail,
    base_price:parseFloat(retail||0)||0,
    markup_value:0,
    discount_value:0
  };
}

function kpFindVariantCatItemByUid(vi,uid){
  var cats=kpEnsureVariantCats(vi);
  for(var ci=0;ci<cats.length;ci++){
    for(var si=0;si<(cats[ci].sections||[]).length;si++){
      for(var ii=0;ii<(cats[ci].sections[si].items||[]).length;ii++){
        var item=cats[ci].sections[si].items[ii];
        if(item && item.uid===uid) return item;
      }
    }
  }
  return null;
}

function kpSetVariantItemFinalPrice(vi,uid,val){
  var item=(kpBuilder.variants[vi].items||[]).find(function(x){return x.uid===uid;});
  if(!item) return;
  var finalPrice=Math.max(parseFloat(val||0)||0,0);
  var discount=Math.max(parseFloat(item.discount_value||0)||0,0);
  var markup=parseFloat(item.markup_value||0)||0;
  item.base_price=Math.max(finalPrice + discount - markup,0);
  var catItem=kpFindVariantCatItemByUid(vi,uid);
  if(catItem) catItem.base_price=item.base_price;
  kpSyncVariantAutoWorks(vi);
  renderKpVariants();
}

function setKpVariantItemField(vi,uid,field,val){
  var item=(kpBuilder.variants[vi].items||[]).find(function(x){return x.uid===uid;});
  if(!item) return;
  if(field==='markup_value'){
    val=parseFloat(val||0)||0;
  }else if(field==='quantity' || field==='discount_value' || field==='base_price'){
    val=Math.max(parseFloat(val||0)||0,0);
  }
  item[field]=val;
  var catItem=kpFindVariantCatItemByUid(vi,uid);
  if(catItem) catItem[field]=val;
  kpSyncVariantAutoWorks(vi);
  renderKpVariants();
}

function addKpVariantSelectedItem(vi){
  var st=kpGetVariantAddState(vi);
  if(!st.category_code){toast('Выберите категорию','err');return;}
  if(!st.section_id){toast('Выберите раздел','err');return;}
  if(!kpIsWorkCategoryCode(st.category_code) && st.category_code!=='kits' && !catalogGroupNorm(st.group_name||'')){toast('Выберите группу','err');return;}
  if(!st.object_id){toast('Выберите объект','err');return;}
  var cats=kpEnsureVariantCats(vi);
  var cat=kpFindOrCreateCat(cats,st.category_code);
  var secList=kpGetBuilderSections(st.category_code||'equipment');
  var secMeta=secList.find(function(s){return String(s.id)===String(st.section_id);})||null;
  var sec=kpFindOrCreateSection(cat,st.section_id,secMeta?secMeta.name:'',secMeta?secMeta.code:String(st.section_id),false);
  var newItem=null;
  if(kpIsWorkCategoryCode(st.category_code)){
    var service=kpCatalogServices.find(function(x){return String(x.id)===String(st.object_id);});
    if(!service) return;
    newItem=kpCreateBuilderWorkItem(service);
    newItem.section_id=st.section_id;
    newItem.section_name=secMeta?secMeta.name:newItem.section_name;
  }else{
    var product=kpCatalogProducts.find(function(x){return String(x.id)===String(st.object_id);});
    if(!product) return;
    newItem=kpCreateBuilderProductItem(product);
    newItem.group_name=st.group_name||newItem.group_name||'';
    if(!Array.isArray(sec.groups)) sec.groups=[];
    if(newItem.group_name && sec.groups.indexOf(newItem.group_name)<0) sec.groups.push(newItem.group_name);
  }
  var normalizedItem=kpNormalizeBuilderItem(newItem,cat.catCode,cat.catName,sec.secId,sec.secName,sec.secCode);
  kpMarkExternalTouched(normalizedItem);
  sec.items.push(normalizedItem);
  if(!kpIsWorkCategoryCode(st.category_code) && st.category_code!=='kits'){
    kpUpsertAutoWorkFromItem(vi, normalizedItem);
  }
  kpSyncVariantFromCats(vi);
  st.object_id='';
  renderKpVariants();
}

function removeKpVariantItem(vi,iiOrUid){
  var variant=kpBuilder.variants[vi];
  var uid=typeof iiOrUid==='string' ? iiOrUid : ((variant.items||[])[iiOrUid] ? variant.items[iiOrUid].uid : '');
  var removed=(variant.items||[]).find(function(item){return item.uid===uid;})||null;
  if(removed && removed.is_auto){
    kpSuppressAutoWorkForAutoItem(vi, removed);
  }
  variant.items=(variant.items||[]).filter(function(item){
    if(item.uid===uid) return false;
    if(item.is_auto){
      return !kpAutoSourceLinks(item).some(function(link){ return String(link.uid||'')===String(uid); });
    }
    return true;
  });
  var cats=kpEnsureVariantCats(vi);
  cats.forEach(function(cat){
    (cat.sections||[]).forEach(function(sec){
      sec.items=(sec.items||[]).filter(function(item){
        if(item.uid===uid) return false;
        if(item.is_auto){
          return !kpAutoSourceLinks(item).some(function(link){ return String(link.uid||'')===String(uid); });
        }
        return true;
      });
    });
    cat.sections=(cat.sections||[]).filter(function(sec){return (sec.items||[]).length;});
  });
  kpBuilder.variants[vi].cats=cats.filter(function(cat){return (cat.sections||[]).length;});
  renderKpVariants();
}

function buildKpCategorySum(items){
  var sum=0;
  var percentBase=0;
  items.forEach(function(item){if(!kpIsPercentIncidentalItem(item)) percentBase+=kpGetProductSum(item);});
  items.forEach(function(item){sum+=kpGetProductSum(item, percentBase);});
  return sum;
}

function renderKpVariantAddBar(vi){
  var st=kpGetVariantAddState(vi);
  var sections=kpGetBuilderSections(st.category_code||'equipment');
  if(!st.section_id && sections.length===1) st.section_id=String(sections[0].id);
  var hideSectionField=st.category_code==='construction_works' || st.category_code==='kits';
  var groups=kpGetBuilderGroups(st.category_code||'equipment', st.section_id||'');
  var objects=(kpIsWorkCategoryCode(st.category_code) || st.category_code==='kits' || catalogGroupNorm(st.group_name||'')) ? kpGetBuilderObjects(st.category_code||'equipment', st.section_id||'', st.group_name||'') : [];
  return '<div class="kp-addbar">'+
    '<div class="field"><label>Категория</label><select class="finp" onchange="kpSetVariantAddField('+vi+',\'category_code\',this.value)">'+kpVisibleBuilderCategories().map(function(code){
      return '<option value="'+code+'"'+(code===(st.category_code||'equipment')?' selected':'')+'>'+kpBuilderCategoryLabel(code)+'</option>';
    }).join('')+'</select></div>'+
    (hideSectionField?'':'<div class="field"><label>Раздел</label><select class="finp" onchange="kpSetVariantAddField('+vi+',\'section_id\',this.value)"><option value="">— выберите —</option>'+sections.map(function(sec){
      return '<option value="'+sec.id+'"'+(String(sec.id)===String(st.section_id||'')?' selected':'')+'>'+esc(sec.name)+'</option>';
    }).join('')+'</select></div>')+
    (kpIsWorkCategoryCode(st.category_code) ? '' : '<div class="field"><label>Группа</label><select class="finp" onchange="kpSetVariantAddField('+vi+',\'group_name\',this.value)"><option value="">— выберите —</option>'+groups.map(function(groupName){var label=groupName||'— без группы —';return '<option value=\"'+esc(groupName)+'\"'+(String(groupName)===String(st.group_name||'')?' selected':'')+'>'+esc(label)+'</option>';}).join('')+'</select></div>')+
    '<div class="field" style="flex:1"><label>Объект</label><select class="finp" onchange="kpSetVariantAddField('+vi+',\'object_id\',this.value)"><option value="">— выберите —</option>'+objects.map(function(obj){
      var label=kpIsWorkCategoryCode(st.category_code) ? esc(obj.name)+(obj.cost!=null?' · '+esc(obj.cost):'') : esc(obj.name)+(obj.marking_size?' · '+esc(obj.marking_size):'');
      return '<option value="'+obj.id+'"'+(String(obj.id)===String(st.object_id||'')?' selected':'')+'>'+label+'</option>';
    }).join('')+'</select></div>'+
    '<div class="field"><label>&nbsp;</label><button class="btn btn-p" onclick="addKpVariantSelectedItem('+vi+')">Добавить</button></div>'+
  '</div>';
}

function renderKpVariantRows(vi,categoryCode){
  var variant=kpBuilder.variants[vi];
  var items=getKpVariantItems(variant,categoryCode);
  if(!items.length) return '<div class="es">Позиции не добавлены</div>';
return '<table class="itbl"><thead><tr><th>Наименование</th><th>Маркировка / размер</th><th>Кол-во</th><th>Ед. изм.</th><th>Примечание</th><th>Наценка</th><th>Цена</th><th>Скидка</th><th>Сумма</th><th></th></tr></thead><tbody>'+items.map(function(item){
    var price=kpGetProductFinalPrice(item);
    var sum=kpGetProductSum(item);
    return '<tr>'+
      '<td><input class="finp" value="'+esc(item.name||'')+'" oninput="setKpVariantItemField('+vi+',\''+item.uid+'\',\'name\',this.value)"></td>'+
      '<td><input class="finp" value="'+esc(item.marking_size||'')+'" oninput="setKpVariantItemField('+vi+',\''+item.uid+'\',\'marking_size\',this.value)"></td>'+
      '<td><input type="number" min="0" step="1" class="finp" value="'+esc(item.quantity||1)+'" oninput="setKpVariantItemField('+vi+',\''+item.uid+'\',\'quantity\',this.value)"></td>'+
      '<td><input class="finp" value="'+esc(item.unit||'')+'" oninput="setKpVariantItemField('+vi+',\''+item.uid+'\',\'unit\',this.value)"></td>'+
      '<td><input class="finp" value="'+esc(item.note||'')+'" oninput="setKpVariantItemField('+vi+',\''+item.uid+'\',\'note\',this.value)"></td>'+
    '<td><input type="number" step="1" class="finp" value="'+esc(item.markup_value||0)+'" oninput="setKpVariantItemField('+vi+',\''+item.uid+'\',\'markup_value\',this.value)"></td>'+
    '<td><input type="number" step="1" class="finp" value="'+esc(price.toFixed(0))+'" oninput="kpSetVariantItemFinalPrice('+vi+',\''+item.uid+'\',this.value)"></td>'+
    '<td><input type="number" step="1" class="finp" value="'+esc(item.discount_value||0)+'" oninput="setKpVariantItemField('+vi+',\''+item.uid+'\',\'discount_value\',this.value)"></td>'+
    '<td><strong>'+esc(sum.toFixed(0))+'</strong></td>'+
      '<td><button class="btn btn-rd btn-xs" onclick="removeKpVariantItem('+vi+',\''+item.uid+'\')">✕</button></td>'+
    '</tr>';
  }).join('')+'</tbody></table>';
}
