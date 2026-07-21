// ===================== INIT =====================
var APP_VERSION_CHECK_INTERVAL_MS=5*60*60*1000;
var APP_VERSION_FOCUS_CHECK_MIN_INTERVAL_MS=60*1000;
var appVersionCheckTimer=null;
var appVersionCheckPending=false;
var appVersionCheckInFlight=false;
var appVersionSnoozedUntil=0;
var appVersionLastCheckAt=0;
var metaLoadInFlight=null;

function applyApplicationUpdateDialogText(info){
  var dialog=document.getElementById('m-app-update');
  if(!dialog||!info) return;
  var title=document.getElementById('app-update-title');
  var message=dialog.querySelector('.mb p');
  var later=document.getElementById('app-update-later-btn');
  var refresh=document.getElementById('app-update-refresh-btn');
  if(title&&info.title) title.textContent=String(info.title);
  if(message&&info.message) message.textContent=String(info.message);
  if(later&&info.later_label) later.textContent=String(info.later_label);
  if(refresh&&info.refresh_label) refresh.textContent=String(info.refresh_label);
}

function showApplicationUpdateDialog(version, info){
  var dialog=document.getElementById('m-app-update');
  if(!dialog) return;
  dialog.dataset.version=version||'';
  applyApplicationUpdateDialogText(info);
  dialog.classList.add('open');
}

function deferApplicationUpdate(){
  appVersionSnoozedUntil=Date.now()+APP_VERSION_CHECK_INTERVAL_MS;
  var dialog=document.getElementById('m-app-update');
  if(dialog) dialog.classList.remove('open');
}

function reloadApplicationForUpdate(){
  location.reload();
}

async function checkApplicationVersion(opts){
  opts=opts||{};
  if(document.hidden && !opts.forceHidden){
    appVersionCheckPending=true;
    return false;
  }
  if(appVersionCheckInFlight) return false;
  appVersionCheckPending=false;
  appVersionCheckInFlight=true;
  appVersionLastCheckAt=Date.now();
  try{
    var response=await fetch('api/version.php?_='+Date.now(),{
      cache:'no-store',
      credentials:'same-origin',
      headers:{
        'Accept':'application/json',
        'Cache-Control':'no-cache',
        'Pragma':'no-cache'
      }
    });
    if(!response.ok) return false;
    var data=await response.json();
    if(data && typeof data==='object' && typeof data.ok==='boolean' && Object.prototype.hasOwnProperty.call(data,'data') && Object.prototype.hasOwnProperty.call(data,'error')){
      data=data.data;
    }
    var version=String((data&&data.version)||'');
    if(version && window.APP_VERSION && version!==String(window.APP_VERSION) && Date.now()>=appVersionSnoozedUntil){
      showApplicationUpdateDialog(version, data.update_dialog);
    }
    return true;
  }catch(e){
    return false;
  }finally{
    appVersionCheckInFlight=false;
  }
}

function startApplicationVersionChecks(){
  if(appVersionCheckTimer) return;
  appVersionCheckTimer=setInterval(checkApplicationVersion,APP_VERSION_CHECK_INTERVAL_MS);
  setTimeout(function(){checkApplicationVersion();},3000);
  function checkAfterBrowserResume(){
    if(document.hidden) return;
    if(appVersionCheckPending || Date.now()-appVersionLastCheckAt>=APP_VERSION_FOCUS_CHECK_MIN_INTERVAL_MS){
      checkApplicationVersion();
    }
  }
  document.addEventListener('visibilitychange',function(){
    if(!document.hidden) checkAfterBrowserResume();
  });
  window.addEventListener('focus',checkAfterBrowserResume);
  window.addEventListener('pageshow',function(event){
    if(event.persisted) checkAfterBrowserResume();
  });
}

async function init(){
  try{
    var r=await api('auth.php?action=me');
    setCsrfToken(r.csrf_token||'');
    CU=r.user; nextOrderNum=r.next_order;
    await bootstrapAuthenticatedSession();
  }catch(e){
    document.getElementById('login-loader').style.display='none';
    document.getElementById('login-form').style.display='block';
  }
}

async function loadMeta(){
  if(metaLoadInFlight) return metaLoadInFlight;
  metaLoadInFlight=(async function(){
    var meta=null;
    try{
      meta=await api('meta.php');
    }catch(_e){
      var r=await Promise.all([
        api('catalog.php?action=categories'),
        api('catalog.php?action=sections'),
        api('catalog.php?action=groups').catch(function(){return [];}),
        api('catalog.php?action=all_suppliers').catch(function(){return [];}),
        api('catalog.php?action=units').catch(function(){return [];}),
        api('permissions.php?action=my').catch(function(){return null;})
      ]);
      meta={
        categories:r[0],
        sections:r[1],
        groups:r[2]||[],
        suppliers:r[3]||[],
        units:r[4]||[],
        permissions:r[5]||null
      };
    }
    allCats=meta.categories||[];
    allSecs=meta.sections||[];
    allGroups=meta.groups||[];
    allSuppliers=meta.suppliers||[];
    UNITS=(meta.units||[]).map(function(u){return u.name;}).filter(Boolean);
    DEFAULT_UNIT=((meta.units||[]).find(function(u){return parseInt(u.is_default,10)===1;})||{}).name||UNITS[0]||'';
    ACCESS_POLICY=((meta.permissions||{}).policy)||null;
    ACCESS_POLICY_ROLES=((meta.permissions||{}).roles)||[];
    // Обновляем глобальный массив SUPPLIERS (имена) для совместимости
    SUPPLIERS=[''].concat(allSuppliers.filter(function(s){return s.name;}).map(function(s){return s.name;}));
  })();
  try{
    return await metaLoadInFlight;
  }finally{
    metaLoadInFlight=null;
  }
}

async function bootstrapAuthenticatedSession(){
  await loadMeta();
  renderUI();
  hideLogin();
  await restoreInitialPage();
  startApplicationVersionChecks();
}

function renderUI(){
  document.getElementById('ui-un').textContent=CU.full_name;
  var re=document.getElementById('ui-r');
  var rl=ROLE_LABELS[CU.role]||CU.role;
  re.textContent=rl;
  re.className='urole r-'+CU.role;
  document.getElementById('doc-rop').value=CU.rop_name||'';

  // Doc manager
  var dmgr=document.getElementById('doc-mgr');
  if(dmgr) dmgr.value=CU.full_name;
  // doc-num is now "Тип клиента" - manual entry, clear it
  document.getElementById('doc-num').value='';

  function setNavVisible(id, visible){
    var el=document.getElementById(id);
    if(el) el.style.display=visible?'':'none';
  }
  setNavVisible('space-tab-catalog', accessSpaceVisibleUi('catalog'));
  setNavVisible('space-tab-orders', accessSpaceVisibleUi('orders'));
  setNavVisible('space-tab-doc', accessSpaceVisibleUi('kp'));
  setNavVisible('space-tab-company', accessSpaceVisibleUi('company'));
  setNavVisible('space-tab-documents', accessSpaceVisibleUi('documents'));
  setNavVisible('space-tab-settings', accessSpaceVisibleUi('settings'));
  setNavVisible('nav-catalog', accessTabVisibleUi('catalog'));
  setNavVisible('nav-orders', accessTabVisibleUi('orders'));
  setNavVisible('nav-doc', accessTabVisibleUi('doc'));
  setNavVisible('nav-employees', accessTabVisibleUi('employees'));
  setNavVisible('nav-kp-company', accessTabVisibleUi('kp_company'));
  setNavVisible('nav-kp-clients', accessTabVisibleUi('kp_clients'));
  setNavVisible('nav-kp-contractors', accessTabVisibleUi('kp_contractors'));
  setNavVisible('nav-documents-builder', accessTabVisibleUi('documents_builder'));
  setNavVisible('nav-settings-units', accessTabVisibleUi('settings_units'));
  setNavVisible('nav-settings-suppliers', accessTabVisibleUi('settings_suppliers'));
  setNavVisible('nav-settings-groups', accessTabVisibleUi('settings_groups'));
  setNavVisible('nav-settings-users', accessTabVisibleUi('users'));
  setNavVisible('nav-settings-access', accessTabVisibleUi('settings_access'));
  setNavVisible('nav-catalog', false);
  setNavVisible('nav-orders', false);
  setNavVisible('nav-doc', false);
  setNavVisible('nav-kp-list', false);
  if(document.getElementById('nav-kp-catalog')) document.getElementById('nav-kp-catalog').style.display='none';
  if(document.getElementById('nav-catalog-orders')) document.getElementById('nav-catalog-orders').style.display='none';
  restoreSidebarCollapsed();
  syncSpaceNavigation();

  // fill cat filters
  var fc=document.getElementById('gc-cat'), fco=document.getElementById('gco-cat'), fcc=document.getElementById('ne-cat'), neUnit=document.getElementById('ne-unit');
  var catOptions=allCats.map(function(c){return '<option value="'+c.id+'">'+esc(c.name)+'</option>';}).join('');
  if(fc) fc.innerHTML=fc.innerHTML+catOptions;
  if(fco) fco.innerHTML=fco.innerHTML+catOptions;
  if(fcc) fcc.innerHTML=fcc.innerHTML+catOptions;
  if(neUnit){
    neUnit.innerHTML=(UNITS||[]).map(function(u){return '<option value="'+esc(u)+'">'+esc(u)+'</option>';}).join('');
    if(!neUnit.innerHTML) neUnit.innerHTML='<option value=""></option>';
  }
  syncGeneralCatalogModeUI();
  var gcAddBtn=document.getElementById('gc-add-btn');
  if(gcAddBtn) gcAddBtn.style.display=accessCanUi('catalog','create')?'':'none';
  var exportBtn=document.getElementById('gc-export-btn');
  if(exportBtn) exportBtn.style.display=accessCanUi('catalog','export')?'':'none';
  var kpCatalogAddProductBtn=document.getElementById('kp-catalog-add-product-btn');
  if(kpCatalogAddProductBtn) kpCatalogAddProductBtn.style.display=accessCanUi('catalog','create')?'':'none';
  var kpCatalogAddServiceBtn=document.getElementById('kp-catalog-add-service-btn');
  if(kpCatalogAddServiceBtn) kpCatalogAddServiceBtn.style.display=accessCanUi('catalog','create')?'':'none';
  var addBtn=document.getElementById('gco-add-btn');
  if(addBtn) addBtn.style.display=accessCanUi('orders','create')?'':'none';
  var kpClientsAddBtn=document.getElementById('kp-clients-add-btn');
  if(kpClientsAddBtn) kpClientsAddBtn.style.display=accessCanUi('company','create')?'':'none';
  var kpContractorsAddBtn=document.getElementById('kp-contractors-add-btn');
  if(kpContractorsAddBtn) kpContractorsAddBtn.style.display=accessCanUi('company','create')?'':'none';
  var kpCompanySaveBtn=document.getElementById('kp-company-save-btn');
  if(kpCompanySaveBtn) kpCompanySaveBtn.style.display=(accessCanUi('company','create')||accessCanUi('company','edit'))?'':'none';
  var kpCompanyNewBtn=document.getElementById('kp-company-new-btn');
  if(kpCompanyNewBtn) kpCompanyNewBtn.style.display=accessCanUi('company','create')?'':'none';
  var kpCompanyDefaultBtn=document.getElementById('kp-company-default-btn');
  if(kpCompanyDefaultBtn) kpCompanyDefaultBtn.style.display=accessCanUi('company','edit')?'':'none';
  var kpCompanyDeleteBtn=document.getElementById('kp-company-delete-btn');
  if(kpCompanyDeleteBtn) kpCompanyDeleteBtn.style.display=accessCanUi('company','delete')?'':'none';
  var kpBuilderAddClientBtn=document.getElementById('kp-builder-add-client-btn');
  if(kpBuilderAddClientBtn) kpBuilderAddClientBtn.style.display=accessCanUi('company','create')?'':'none';
  var kpBuilderAddVariantBtn=document.getElementById('kp-builder-add-variant-btn');
  if(kpBuilderAddVariantBtn) kpBuilderAddVariantBtn.style.display=accessCanUi('kp','create')?'':'none';
  var settingsUsersAddBtn=document.getElementById('settings-users-add-btn');
  if(settingsUsersAddBtn) settingsUsersAddBtn.style.display=accessCanUi('users','create')?'':'none';
  var settingsCanWrite=accessCanUi('settings','create')||accessCanUi('settings','edit');
  var settingsUnitSaveBtn=document.getElementById('settings-unit-save-btn');
  if(settingsUnitSaveBtn) settingsUnitSaveBtn.style.display=settingsCanWrite?'':'none';
  var settingsSupplierSaveBtn=document.getElementById('settings-supplier-save-btn');
  if(settingsSupplierSaveBtn) settingsSupplierSaveBtn.style.display=settingsCanWrite?'':'none';
  syncOrdersAccessUi();
}

function hideLogin(){document.getElementById('login-screen').style.display='none';document.getElementById('app').style.display='block';}

