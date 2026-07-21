// ===================== NAVIGATION =====================
var ALL_PAGES=['home','catalog','catalog-orders','orders','order-edit','doc','employees','settings-users','kp-catalog','kp-company','kp-clients','kp-contractors','kp-builder','kp-list','documents-builder','settings-units','settings-suppliers','settings-groups','settings-access'];
var PAGE_SPACES={home:'home',catalog:'catalog','catalog-orders':'orders',orders:'orders','order-edit':'orders',employees:'company','settings-users':'settings',doc:'orders','kp-catalog':'doc','kp-company':'company','kp-clients':'company','kp-contractors':'company','documents-builder':'documents','settings-units':'settings','settings-suppliers':'settings','settings-groups':'settings','settings-access':'settings'};
var SPACE_DEFAULT_PAGES={catalog:'catalog',orders:'orders',doc:'kp-list',company:'kp-company',documents:'documents-builder',settings:'settings-units'};
var activePage='home';
var activeSpace='home';
var SIDEBAR_COLLAPSE_KEY='app_sidebar_collapsed_v1';
var NAV_STATE_KEY='app_navigation_state_v1';
var NAV_PERSIST_ENABLED=false;
var NAV_SUPPRESS_CATALOG_AUTOLOAD=false;
function getNavigationStateKey(){
  return NAV_STATE_KEY+'_'+(CU&&CU.id?CU.id:'guest');
}
function getCatalogNavigationFilters(){
  var filters={section_id:'',status:'',search:''};
  try{
    var sec=document.getElementById('gc-sec');
    var st=document.getElementById('gc-st');
    var s=document.getElementById('gc-s');
    filters.section_id=sec ? (sec.value||'') : '';
    filters.status=st ? (st.value||'') : '';
    filters.search=s ? (s.value||'') : '';
  }catch(e){}
  return filters;
}
function applyCatalogNavigationFilters(filters){
  filters=filters||{};
  var sec=document.getElementById('gc-sec');
  var st=document.getElementById('gc-st');
  var s=document.getElementById('gc-s');
  if(sec && typeof filters.section_id!=='undefined') sec.value=filters.section_id||'';
  if(st && typeof filters.status!=='undefined') st.value=filters.status||'';
  if(s && typeof filters.search!=='undefined') s.value=filters.search||'';
}
function getNavigationScrollState(){
  var main=document.querySelector('.main') || document.scrollingElement || document.documentElement;
  var kanban=null;
  if(activePage==='kp-list') kanban=document.querySelector('#kp-quotes-kanban .kanban-grid');
  if(activePage==='orders') kanban=document.querySelector('#or-kanban .kanban-grid');
  return {
    main:main?main.scrollTop:0,
    kanban:kanban?kanban.scrollLeft:0
  };
}
function persistNavigationState(){
  if(!NAV_PERSIST_ENABLED || !CU) return;
  try{
    var state={
      user_id:CU.id||0,
      page:activePage||'home',
      space:activeSpace||'home',
      quote_mode:(typeof quoteWorkspaceMode==='undefined')?'kp':quoteWorkspaceMode,
      catalog_mode:(typeof generalCatalogMode==='undefined')?'':generalCatalogMode,
      catalog_filters:getCatalogNavigationFilters(),
      scroll:getNavigationScrollState(),
      saved_at:Date.now()
    };
    var orderIdEl=document.getElementById('oe-id');
    if(state.page==='order-edit' && orderIdEl){
      state.order_id=parseInt(orderIdEl.value||'0',10)||0;
    }
    localStorage.setItem(getNavigationStateKey(), JSON.stringify(state));
  }catch(e){}
}
function readNavigationState(){
  try{
    var raw=localStorage.getItem(getNavigationStateKey());
    if(!raw) return null;
    var state=JSON.parse(raw);
    if(!state || !state.page) return null;
    if(state.user_id && CU && String(state.user_id)!==String(CU.id||'')) return null;
    return state;
  }catch(e){
    return null;
  }
}
var navigationScrollRestoreToken=0;
function restoreNavigationScroll(scroll){
  if(!scroll) return;
  var token=++navigationScrollRestoreToken;
  var expectedMain=null;
  var expectedKanban=null;
  [0,80,220,500,900,1500].forEach(function(delay){
    setTimeout(function(){
      if(token!==navigationScrollRestoreToken) return;
      var main=document.querySelector('.main') || document.scrollingElement || document.documentElement;
      var kanban=null;
      if(activePage==='kp-list') kanban=document.querySelector('#kp-quotes-kanban .kanban-grid');
      if(activePage==='orders') kanban=document.querySelector('#or-kanban .kanban-grid');
      if(expectedMain!==null && main && Math.abs(main.scrollTop-expectedMain)>1){
        navigationScrollRestoreToken++;
        return;
      }
      if(expectedKanban!==null && kanban && Math.abs(kanban.scrollLeft-expectedKanban)>1){
        navigationScrollRestoreToken++;
        return;
      }
      if(main && typeof scroll.main!=='undefined'){
        main.scrollTop=parseInt(scroll.main||0,10)||0;
        expectedMain=main.scrollTop;
      }
      if(kanban && typeof scroll.kanban!=='undefined'){
        kanban.scrollLeft=parseInt(scroll.kanban||0,10)||0;
        expectedKanban=kanban.scrollLeft;
      }
    }, delay);
  });
}
function setNavigationQuoteMode(mode){
  quoteWorkspaceMode=(typeof kpNormalizeQuoteMode==='function') ? kpNormalizeQuoteMode(mode) : (mode==='pkp'?'pkp':'kp');
  if(typeof updateQuoteWorkspaceUi==='function') updateQuoteWorkspaceUi();
}
function isQuoteBoardVisible(){
  return accessTabVisibleUi('kp_list');
}
function getQuoteWorkspaceNavId(page){
  if(page==='settings-units') return 'nav-settings-units';
  if(page==='settings-suppliers') return 'nav-settings-suppliers';
  if(page==='settings-groups') return 'nav-settings-groups';
  if(page==='settings-users') return 'nav-settings-users';
  if(page==='settings-access') return 'nav-settings-access';
  if(page==='kp-company') return 'nav-kp-company';
  if(page==='kp-clients') return 'nav-kp-clients';
  if(page==='kp-contractors') return 'nav-kp-contractors';
  if(page==='kp-list') return 'nav-kp-list';
  return 'nav-'+page;
}
function accessKanbanColumnVisibleUi(spaceKey, mode, status){
  if(!CU) return false;
  if(CU.role==='admin') return true;
  var columns=ACCESS_POLICY && ACCESS_POLICY.kanban && ACCESS_POLICY.kanban[spaceKey] && ACCESS_POLICY.kanban[spaceKey].columns;
  if(!Array.isArray(columns) || !columns.length) return true;
  if(spaceKey==='orders') return columns.indexOf(String(mode||status||''))>=0;
  if(typeof getQuoteKanbanColumnKey==='function') return columns.indexOf(getQuoteKanbanColumnKey(mode,status))>=0;
  return true;
}
async function openQuoteWorkspace(mode, section){
  if(typeof ensurePageScripts==='function') await ensurePageScripts('kp-list');
  var loadedFn=window.openQuoteWorkspace;
  if(typeof loadedFn==='function' && !loadedFn.__lazyShim){
    return loadedFn(mode, section);
  }
  quoteWorkspaceMode=mode==='pkp'?'pkp':'kp';
  return showPage('kp-list');
}
openQuoteWorkspace.__lazyShim=true;
async function showPkpPresets(){
  if(typeof ensurePageScripts==='function') await ensurePageScripts('kp-list');
  var loadedFn=window.showPkpPresets;
  if(typeof loadedFn==='function' && !loadedFn.__lazyShim){
    return loadedFn();
  }
  quoteWorkspaceMode='pkp';
  return showPage('kp-list');
}
showPkpPresets.__lazyShim=true;
async function restoreInitialPage(){
  var state=readNavigationState();
  var restored=false;
  if(state && state.page && state.page!=='home'){
    var isKpRestorePage=state.page==='kp-list' || state.page==='kp-builder' || state.page==='kp-company' || state.page==='kp-clients' || state.page==='kp-contractors';
    if(isKpRestorePage && typeof ensurePageScripts==='function') await ensurePageScripts(state.page);
    if(state.quote_mode) setNavigationQuoteMode(state.quote_mode);
    if(state.page==='kp-builder' && typeof restoreKpBuilderDraftIfAny==='function'){
      restoreKpBuilderDraftIfAny(state.quote_mode||((typeof quoteWorkspaceMode==='undefined')?'kp':quoteWorkspaceMode));
    }
    if(state.page==='order-edit'){
      if(typeof ensurePageScripts==='function') await ensurePageScripts('order-edit');
      if(state.order_id && typeof openOrderEdit==='function'){
        try{
          await openOrderEdit(state.order_id);
          restored=activePage==='order-edit';
        }catch(e){
          restored=false;
        }
      }
      if(!restored) await showPage('home');
    }else{
      if(state.page==='catalog'){
        if(state.catalog_mode) generalCatalogMode=state.catalog_mode;
        NAV_SUPPRESS_CATALOG_AUTOLOAD=true;
        await showPage(state.page);
        NAV_SUPPRESS_CATALOG_AUTOLOAD=false;
        if(typeof syncGeneralCatalogModeUI==='function') syncGeneralCatalogModeUI();
        if(typeof getCategoryByCode==='function' && typeof ensureCatalogSectionsOptions==='function'){
          var cat=getCategoryByCode(generalCatalogMode);
          var ui=getCatalogUi();
          if(cat) ensureCatalogSectionsOptions(ui, String(cat.id));
        }
        applyCatalogNavigationFilters(state.catalog_filters);
        if(typeof loadCatalog==='function') loadCatalog();
      }else{
        await showPage(state.page);
      }
      restored=activePage===state.page;
    }
    if(restored) restoreNavigationScroll(state.scroll);
  }
  if(!restored){
    await showPage('home');
  }
  NAV_PERSIST_ENABLED=true;
  persistNavigationState();
}
function applySidebarCollapsedState(collapsed){
  var layout=document.querySelector('.layout');
  var btn=document.getElementById('sidebar-toggle-btn');
  var flyoutBtn=document.getElementById('sidebar-flyout-toggle-btn');
  if(layout) layout.classList.toggle('sidebar-collapsed',!!collapsed);
  if(btn) btn.textContent=collapsed?'▸':'◂';
  if(flyoutBtn){
    flyoutBtn.textContent='▸';
    flyoutBtn.style.display=collapsed?'inline-flex':'none';
  }
}
function toggleSidebarCollapsed(forceValue){
  var next=typeof forceValue==='boolean' ? forceValue : !document.querySelector('.layout.sidebar-collapsed');
  try{ localStorage.setItem(SIDEBAR_COLLAPSE_KEY,next?'1':'0'); }catch(_e){}
  applySidebarCollapsedState(next);
}
function restoreSidebarCollapsed(){
  var collapsed=false;
  try{ collapsed=localStorage.getItem(SIDEBAR_COLLAPSE_KEY)==='1'; }catch(_e){}
  applySidebarCollapsedState(collapsed);
}
function syncSpaceNavigation(){
  document.querySelectorAll('.space-tab').forEach(function(tab){
    tab.classList.toggle('active',tab.id==='space-tab-'+activeSpace);
  });
  document.querySelectorAll('.space-nav').forEach(function(group){
    group.classList.toggle('active',group.getAttribute('data-space')===activeSpace);
  });
}
function showSpace(space){
  if(!accessSpaceVisibleUi(space==='doc' ? 'kp' : space)) return;
  if(activeSpace===space){
    if(space==='doc' && activePage==='kp-list'){
      persistNavigationState();
      return;
    }
    if(space==='orders' && activePage==='orders'){
      persistNavigationState();
      return;
    }
  }
  activeSpace=space;
  syncSpaceNavigation();
  if(space==='settings'){
    return showPage(getFirstVisibleSpacePage('settings'));
  }
  if(space==='orders'){
    if(accessTabVisibleUi('orders')){
      ordersView='kanban';
      return showPage('orders');
    }
    return showPage(getFirstVisibleSpacePage('orders'));
  }
  if(space==='catalog'){
    if(accessTabVisibleUi('catalog')) return showPage('catalog');
    return showPage(getFirstVisibleSpacePage('catalog'));
  }
  if(space==='company') return showPage(getFirstVisibleSpacePage('company'));
  if(space==='documents') return showPage(getFirstVisibleSpacePage('documents'));
  showPage(SPACE_DEFAULT_PAGES[space]||'home');
}
function getCategoryByCode(code){
  return allCats.find(function(c){return c.code===code;})||null;
}
function isSimpleCatalogCategoryCode(code){
  return false;
}
function isAutoApprovedCatalogCategoryCode(code){
  return code==='incidental_expenses' || code==='maintenance' || code==='kits';
}
function isGeneralCatalogServiceMode(mode){
  return mode==='work' || mode==='construction_works';
}
function getSelectedNameEditCategoryCode(){
  var cat=document.getElementById('ne-cat');
  if(!cat) return '';
  var catObj=allCats.find(function(x){return String(x.id)===String(cat.value||'');});
  return catObj?catObj.code:'';
}
function updateNameEditModeUi(){
  var catCode=getSelectedNameEditCategoryCode();
  var isSimple=isSimpleCatalogCategoryCode(catCode);
  var isKit=catCode==='kits';
  var isIncidental=catCode==='incidental_expenses';
  var isConsumables=catCode==='consumables';
  var isAutoApproved=isAutoApprovedCatalogCategoryCode(catCode);
  var generalFields=document.getElementById('ne-general-fields');
  var markingField=document.getElementById('ne-marking-field');
  var unitField=document.getElementById('ne-unit-field');
  var groupField=document.getElementById('ne-group-field');
  var supplierField=document.getElementById('ne-supplier-field');
  var statusField=document.getElementById('ne-status-field');
  var simpleCostField=document.getElementById('ne-simple-cost-field');
  var simpleCostLabel=document.getElementById('ne-simple-cost-label');
  var priceTypeField=document.getElementById('ne-price-type-field');
  var priceType=document.getElementById('ne-price-type');
  var purchasePriceField=document.getElementById('ne-purchase-price-field');
  var minimalPriceField=document.getElementById('ne-minimal-price-field');
  var retailPriceLabel=document.getElementById('ne-retail-price-label');
  var linkedServicesField=document.getElementById('ne-linked-services-field');
  var nameLabel=document.getElementById('ne-name-label');
  var markingLabel=document.getElementById('ne-marking-size-label');
  var noteField=document.getElementById('ne-note-field');
  var komplektaciyaField=document.getElementById('ne-komplektaciya-field');
  var isPercentIncidental=isIncidental && priceType && priceType.value==='percent';
  if(generalFields) generalFields.style.display=(activePage==='catalog' && !isSimple && !isKit && !isConsumables)?'':'none';
  if(komplektaciyaField) komplektaciyaField.style.display=isConsumables?'':'none';
  if(markingField) markingField.style.display=isSimple?'none':'';
  if(unitField) unitField.style.display=isSimple?'none':'';
  if(groupField) groupField.style.display=isSimple?'none':'';
  if(supplierField) supplierField.style.display=(isSimple || isKit || isIncidental)?'none':'';
  if(statusField) statusField.style.display=(isSimple || isAutoApproved)?'none':'';
  if(simpleCostField) simpleCostField.style.display=(activePage==='catalog' && (isSimple || isKit))?'':'none';
  if(priceTypeField) priceTypeField.style.display=(activePage==='catalog' && isIncidental)?'':'none';
  if(purchasePriceField) purchasePriceField.style.display=isPercentIncidental?'none':'';
  if(minimalPriceField) minimalPriceField.style.display=isPercentIncidental?'none':'';
  if(retailPriceLabel) retailPriceLabel.textContent=isPercentIncidental?'Процент от суммы':'Розничная цена';
  if(linkedServicesField) linkedServicesField.style.display=isIncidental?'none':'';
  if(simpleCostLabel) simpleCostLabel.textContent=isKit?'Цена':'Стоимость';
  if(nameLabel) nameLabel.textContent=isKit?'Наименование':'Название';
  if(markingLabel) markingLabel.textContent=isKit?'Маркировка':'Маркировка/Размер';
  if(noteField && (isSimple || isKit || isConsumables)) noteField.style.display='none';
}
function syncGeneralCatalogModeUI(){
  document.querySelectorAll('#gc-mode-tabs .ftab').forEach(function(tab){
    tab.classList.toggle('active',tab.getAttribute('data-mode')===generalCatalogMode);
  });
  var isWork=isGeneralCatalogServiceMode(generalCatalogMode);
  var isSimple=isSimpleCatalogCategoryCode(generalCatalogMode);
  var isAutoApproved=isAutoApprovedCatalogCategoryCode(generalCatalogMode);
  ['gc-fi-sec','gc-fi-st'].forEach(function(id){
    var el=document.getElementById(id);
    if(!el) return;
    if(id==='gc-fi-sec' && (generalCatalogMode==='construction_works' || generalCatalogMode==='kits')){
      el.style.display='none';
      return;
    }
    if(isWork){
      el.style.display=id==='gc-fi-st'?'none':'';
      return;
    }
    if(id==='gc-fi-st' && (isSimple || isAutoApproved)){
      el.style.display='none';
      return;
    }
    el.style.display='';
  });
  var addBtn=document.getElementById('gc-add-btn');
  var importBtn=document.getElementById('gc-import-btn');
  var templateProductsBtn=document.getElementById('gc-template-products-btn');
  var templateServicesBtn=document.getElementById('gc-template-services-btn');
  var exportBtn=document.getElementById('gc-export-btn');
  var canManage=accessCanUi('catalog','create') || accessCanUi('catalog','edit');
  if(addBtn){
    addBtn.style.display=canManage?'':'none';
    addBtn.textContent=isWork?'➕ Добавить работу':(generalCatalogMode==='kits'?'➕ Добавить комплект':(isSimple?'➕ Добавить позицию':'➕ Добавить товар'));
  }
  if(importBtn) importBtn.style.display=canManage?'':'none';
  if(templateProductsBtn) templateProductsBtn.style.display=canManage?'':'none';
  if(templateServicesBtn) templateServicesBtn.style.display=canManage?'':'none';
  if(exportBtn) exportBtn.style.display=accessCanUi('catalog','export')?'':'none';
}
function setGeneralCatalogMode(mode){
  generalCatalogMode=mode;
  syncGeneralCatalogModeUI();
  if(!isGeneralCatalogServiceMode(mode)){
    gcCatChange();
    persistNavigationState();
    return;
  }
  document.getElementById('gc-sec').value='';
  document.getElementById('gc-st').value='Не согласовано';
  var workCat=getCategoryByCode(mode);
  if(workCat){
    var ui=getCatalogUi();
    ensureCatalogSectionsOptions(ui, String(workCat.id));
  }
  loadCatalog();
  persistNavigationState();
}
function getCatalogUi(){
  var prefix=activePage==='catalog-orders'?'gco':'gc';
  return {
    prefix:prefix,
    cat:document.getElementById(prefix+'-cat'),
    sec:document.getElementById(prefix+'-sec'),
    st:document.getElementById(prefix+'-st'),
    search:document.getElementById(prefix+'-s'),
    drop:document.getElementById(prefix+'-s-drop'),
    grid:document.getElementById(prefix+'-grid')
  };
}
var kpQuotesLiveTimer=0;
async function showPage(pg){
  var prevPage=activePage;
  var prevWorkspace=(typeof quoteWorkspaceMode==='undefined')?'kp':quoteWorkspaceMode;
  if(prevPage!==pg){
    if(prevPage==='kp-builder' && typeof confirmKpBuilderLeave==='function') await confirmKpBuilderLeave();
    if(prevPage==='order-edit' && typeof confirmOrderBuilderLeave==='function') await confirmOrderBuilderLeave('edit');
    if(prevPage==='doc' && typeof confirmOrderBuilderLeave==='function') await confirmOrderBuilderLeave('create');
  }
  if(pg==='catalog-orders' || pg==='kp-catalog') pg='catalog';
  if(ALL_PAGES.indexOf(pg)<0) pg='home';
  var pageTabMap={
    home:'home',
    catalog:'catalog',
    orders:'orders',
    doc:'doc',
    employees:'employees',
    'settings-users':'users',
    'kp-company':'kp_company',
    'kp-clients':'kp_clients',
    'kp-contractors':'kp_contractors',
    'kp-list':'kp_list',
    'kp-builder':'kp_list',
    'documents-builder':'documents_builder',
    'settings-units':'settings_units',
    'settings-suppliers':'settings_suppliers',
    'settings-groups':'settings_groups',
    'settings-access':'settings_access'
  };
  if(pg==='kp-list' || pg==='kp-builder'){
    if(!isQuoteBoardVisible()) pg='home';
  }else if(pg!=='home' && pageTabMap[pg] && !accessTabVisibleUi(pageTabMap[pg])){
    pg='home';
  }
  if(pg==='home'){
    activePage='home';
    activeSpace='home';
    syncSpaceNavigation();
    ALL_PAGES.forEach(function(p){
      var el=document.getElementById('page-'+p);if(el)el.style.display=p==='home'?'block':'none';
      var nv=document.getElementById('nav-'+p);if(nv)nv.classList.toggle('active',false);
    });
    ['nav-kp-company','nav-kp-clients','nav-kp-contractors','nav-kp-list','nav-documents-builder','nav-settings-units','nav-settings-suppliers','nav-settings-groups','nav-settings-users','nav-settings-access'].forEach(function(id){
      var el=document.getElementById(id);
      if(el) el.classList.toggle('active', false);
    });
    if(typeof stopAutosave==='function') stopAutosave();
    if(typeof stopKpQuotesLiveRefresh==='function') stopKpQuotesLiveRefresh();
    persistNavigationState();
    return;
  }
  activePage=pg;
  if(pg==='kp-company' || pg==='kp-clients' || pg==='kp-contractors' || pg==='employees'){
    activeSpace='company';
  }else if(pg==='kp-builder' || pg==='kp-list'){
    activeSpace='doc';
  }else{
    activeSpace=PAGE_SPACES[pg]||'catalog';
  }
  syncSpaceNavigation();
  var navPage=pg==='order-edit'?'orders':pg;
  ALL_PAGES.forEach(function(p){
    var el=document.getElementById('page-'+p);if(el)el.style.display=p===pg?'block':'none';
    var nv=document.getElementById('nav-'+p);if(nv)nv.classList.toggle('active',false);
  });
  var genericNav=document.getElementById('nav-'+navPage);
  if(genericNav && !/^nav-(kp|pkp)-/.test(genericNav.id||'')){
    genericNav.classList.toggle('active',true);
  }
  ['nav-kp-company','nav-kp-clients','nav-kp-contractors','nav-kp-list','nav-documents-builder','nav-settings-units','nav-settings-suppliers','nav-settings-groups','nav-settings-users','nav-settings-access'].forEach(function(id){
    var el=document.getElementById(id);
    if(el) el.classList.toggle('active', id===getQuoteWorkspaceNavId(navPage));
  });
  var catalogOrdersNav=document.getElementById('nav-catalog-orders');
  if(catalogOrdersNav) catalogOrdersNav.classList.toggle('active',navPage==='catalog-orders');
  if(pg!=='order-edit' && typeof stopAutosave==='function') stopAutosave();
  try{
    if(typeof ensurePageScripts==='function') await ensurePageScripts(pg);
  }catch(e){
    toast(e.message||'Не удалось загрузить раздел','err');
    return;
  }
  if(pg==='orders')loadOrders();
  if(pg==='doc' && typeof prepareNewOrderBuilder==='function') prepareNewOrderBuilder();
  if(pg==='catalog' && !NAV_SUPPRESS_CATALOG_AUTOLOAD)loadCatalog();
  if(pg==='employees')loadEmployees();
  if(pg==='kp-company')loadKpCompany();
  if(pg==='kp-clients')loadKpClients();
  if(pg==='kp-contractors')loadKpContractors();
  if(pg==='kp-builder')loadKpBuilder();
  if(pg==='kp-list'){
    var restoreQuoteBoard=!!(typeof kpBoardScrollMemory!=='undefined' && kpBoardScrollMemory && kpBoardScrollMemory.pendingRestore);
    loadKpQuotes({preserveScroll:restoreQuoteBoard,preservePagination:restoreQuoteBoard});
  }
  if(pg==='settings-units') loadSettingsUnits();
  if(pg==='settings-suppliers') loadSettingsSuppliers();
  if(pg==='settings-groups') loadSettingsGroups();
  if(pg==='settings-users') loadUsers();
  if(pg==='settings-access') loadSettingsAccess();
  if(pg==='documents-builder') loadDocumentsBuilder();
  if(pg==='kp-list') startKpQuotesLiveRefresh();
  else if(typeof stopKpQuotesLiveRefresh==='function') stopKpQuotesLiveRefresh();
  persistNavigationState();
}

window.addEventListener('beforeunload',function(event){
  var hasUnsaved=false;
  if(activePage==='kp-builder' && typeof kpHasUnsavedChanges==='function' && kpHasUnsavedChanges()){
    hasUnsaved=true;
    if(typeof saveKpBuilderDraft==='function') saveKpBuilderDraft((typeof quoteWorkspaceMode==='undefined')?'kp':quoteWorkspaceMode);
  }
  if(activePage==='order-edit' && typeof orderBuilderHasUnsavedChanges==='function' && orderBuilderHasUnsavedChanges('edit')){
    hasUnsaved=true;
    saveOrderBuilderDraft('edit');
  }
  if(activePage==='doc' && typeof orderBuilderHasUnsavedChanges==='function' && orderBuilderHasUnsavedChanges('create')){
    hasUnsaved=true;
    saveOrderBuilderDraft('create');
  }
  persistNavigationState();
  if(hasUnsaved){
    event.preventDefault();
    event.returnValue='';
  }
});
