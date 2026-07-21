async function saveKpProduct(){
  try{
    await api(quoteApiFile(),{
      action:'save_catalog_product',
      id:parseInt(document.getElementById('kpp-id').value||'0',10),
      name:document.getElementById('kpp-name').value.trim(),
      section_id:parseInt(document.getElementById('kpp-section').value||'0',10),
      group_name:document.getElementById('kpp-group').value.trim(),
      marking_size:document.getElementById('kpp-marking').value.trim(),
      note:document.getElementById('kpp-note-field').style.display==='none'?'':document.getElementById('kpp-note').value.trim(),
      unit:document.getElementById('kpp-unit').value,
      supplier:document.getElementById('kpp-supplier').value.trim(),
      purchase_price:document.getElementById('kpp-purchase').value,
      minimal_price:document.getElementById('kpp-minimal').value,
      retail_price:document.getElementById('kpp-retail').value,
      linked_service_id:parseInt(document.getElementById('kpp-service').value||'0',10)
    });
    cm('m-kp-product');
    toast('Товар сохранён ');
    await refreshKpCatalogItems();
  }catch(e){toast(e.message,'err');}
}

async function deleteKpProduct(id){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  if(!confirm('Удалить товар из каталога?')) return;
  try{
    await api(quoteApiFile(),{action:'delete_catalog_product',id:id});
    toast('Товар удалён');
    await refreshKpCatalogItems();
  }catch(e){toast(e.message,'err');}
}

async function deleteKpService(id){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  if(!confirm('Удалить работу из каталога?')) return;
  try{
    await api(quoteApiFile(),{action:'delete_catalog_service',id:id});
    toast('Работа удалена');
    await refreshKpCatalogItems();
  }catch(e){toast(e.message,'err');}
}

async function saveKpService(){
  try{
    await api(quoteApiFile(),{
      action:'save_catalog_service',
      id:parseInt(document.getElementById('kps-id').value||'0',10),
      name:document.getElementById('kps-name').value.trim(),
      marking_size:document.getElementById('kps-marking').value.trim(),
      purchase_price:document.getElementById('kps-purchase').value,
      minimal_price:document.getElementById('kps-minimal').value,
      retail_price:document.getElementById('kps-retail').value,
      unit:document.getElementById('kps-unit').value
    });
    cm('m-kp-service');
    toast('Работа сохранена');
    await refreshKpCatalogItems();
  }catch(e){toast(e.message,'err');}
}

function openKpServiceCreate(){
  window.catalogServiceEditContext='kp';
  var seUnit=document.getElementById('se-unit');
  if(seUnit && !seUnit.options.length){
    seUnit.innerHTML=(UNITS||[]).map(function(u){return '<option value="'+esc(u)+'">'+esc(u)+'</option>';}).join('');
  }
  document.getElementById('m-service-edit-title').textContent='➕ Добавить работу';
  document.getElementById('se-id').value='';
  document.getElementById('se-name').value='';
  document.getElementById('se-marking').value='';
  document.getElementById('se-purchase').value='';
  document.getElementById('se-minimal').value='';
  document.getElementById('se-retail').value='';
  if(document.getElementById('se-unit').options.length) document.getElementById('se-unit').value=getDefaultUnit();
  om('m-service-edit');
}

function openKpServiceEdit(id){
  window.catalogServiceEditContext='kp';
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
  document.getElementById('se-retail').value=service.retail_price!=null?service.retail_price:(service.cost!=null?service.cost:'');
  document.getElementById('se-unit').value=service.unit||getDefaultUnit();
  om('m-service-edit');
}

async function saveKpServiceEdit(){
  var id=parseInt(document.getElementById('se-id').value||'0',10);
  var payload={
    action:id?'update_service':'create_service',
    id:id,
    name:document.getElementById('se-name').value.trim(),
    marking_size:document.getElementById('se-marking').value.trim(),
    purchase_price:document.getElementById('se-purchase').value,
    minimal_price:document.getElementById('se-minimal').value,
    retail_price:document.getElementById('se-retail').value,
    unit:document.getElementById('se-unit').value
  };
  if(!payload.name){toast('Введите название','err');return;}
  try{
    var saved=await api('catalog.php',payload);
    serviceOptionsCache=[];
    serviceOptionsCacheCategory='';
    linkableCatalogItems=[];
    toast('Сохранено ✓');
    cm('m-service-edit');
    if(activePage==='catalog' && typeof catalogUpsertWorkServiceCard==='function'){
      catalogUpsertWorkServiceCard(id || (saved&&saved.id), payload);
    }else{
      loadCatalog();
    }
  }catch(e){toast(e.message,'err');}
}

function renderKpCatalogWorkServices(){
  var grid=document.getElementById('gc-grid');
  if(!workServices.length){grid.innerHTML='<div class="es"><div class="ei">📭</div><div class="et">Ничего не найдено</div></div>';return;}
  var canManage=true;
  function workSectionLabel(service){
    var code=String(service.work_section_code||'installation');
    if(code==='construction') return 'Строительные работы';
    if(code==='dismantling') return 'Демонтажные работы';
    return 'Монтажные работы';
  }
  grid.innerHTML=workServices.map(function(s){
    var linkedCount=parseInt(s.linked_products_count||'0',10);
    return '<div class="ccard fi2">'+
      '<div class="ch"><div><div class="ctitle">'+esc(s.name)+'</div><div class="cmark">'+esc(workSectionLabel(s))+(s.marking_size?' · '+esc(s.marking_size):'')+'</div></div></div>'+
      '<div class="cmeta">'+
        '<div><div class="mlb">Закупочная цена</div><div class="mvl">'+(s.purchase_price!=null?esc(s.purchase_price):'—')+'</div></div>'+
        '<div><div class="mlb">Минимальная цена</div><div class="mvl">'+(s.minimal_price!=null?esc(s.minimal_price):'—')+'</div></div>'+
        '<div><div class="mlb">Розничная цена</div><div class="mvl">'+(s.retail_price!=null?esc(s.retail_price):(s.cost!=null?esc(s.cost):'—'))+'</div></div>'+
        '<div><div class="mlb">Ед. изм.</div><div class="mvl">'+esc(s.unit||'—')+'</div></div>'+
        '<div><div class="mlb">Раздел работ</div><div class="mvl">'+esc(workSectionLabel(s))+'</div></div>'+
        '<div><div class="mlb">Привязано товаров</div><div class="mvl">'+esc(linkedCount)+'</div></div>'+
      '</div>'+
      '<div class="cft">'+
        (accessCanUi('catalog','edit')?'<button class="btn btn-g btn-sm" onclick="openKpServiceEdit('+s.id+')">✏️ Редактировать</button>':'')+
        (accessCanUi('catalog','delete')?'<button class="btn btn-rd btn-sm" onclick="deleteService('+s.id+')">🗑 Удалить</button>':'')+
      '</div></div>';
  }).join('');
}

function openKpServiceModal(id){
  document.getElementById('kps-id').value=id||'';
  fillKpCatalogSelects();
  var title=document.getElementById('m-kp-service-title');
  if(!id){
    title.textContent='➕ Работа';
    document.getElementById('kps-id').value='';
    document.getElementById('kps-name').value='';
    document.getElementById('kps-marking').value='';
    document.getElementById('kps-purchase').value='';
    document.getElementById('kps-minimal').value='';
    document.getElementById('kps-retail').value='';
    if(document.getElementById('kps-unit').options.length) document.getElementById('kps-unit').value=getDefaultUnit();
    om('m-kp-service');
    return;
  }
  var s=kpCatalogServices.find(function(x){return x.id==id;}); if(!s) return;
  title.textContent='✏️ Работа';
  document.getElementById('kps-id').value=s.id;
  document.getElementById('kps-name').value=s.name||'';
  document.getElementById('kps-marking').value=s.marking_size||'';
  document.getElementById('kps-purchase').value=s.purchase_price!=null?s.purchase_price:'';
  document.getElementById('kps-minimal').value=s.minimal_price!=null?s.minimal_price:'';
  document.getElementById('kps-retail').value=s.retail_price!=null?s.retail_price:(s.cost!=null?s.cost:'');
  document.getElementById('kps-unit').value=s.unit||getDefaultUnit();
  om('m-kp-service');
}

function renderKpCatalog(){
  var productsWrap=document.getElementById('kp-catalog-products-view');
  var servicesWrap=document.getElementById('kp-catalog-services-view');
  syncKpSectionFilter();
  var catFilter=document.getElementById('kp-cat-filter')?document.getElementById('kp-cat-filter').value:'';
  var secFilter=document.getElementById('kp-sec-filter')?document.getElementById('kp-sec-filter').value:'';
  var q=(document.getElementById('kp-search')?document.getElementById('kp-search').value:'').trim().toLowerCase();
  if(productsWrap){
    var filteredProducts=kpCatalogProducts.filter(function(p){
      if(catFilter && p.category_code!==catFilter) return false;
      if(secFilter && String(p.section_id)!==String(secFilter)) return false;
      if(q && [p.name,p.marking_size,p.section_name,p.category_name,p.supplier].join(' ').toLowerCase().indexOf(q)<0) return false;
      return true;
    });
    if(!filteredProducts.length){productsWrap.innerHTML='<div class="es">Нет товаров</div>';}
    else{
      productsWrap.innerHTML='<div class="pgrid">'+filteredProducts.map(function(p){
        var linked=!!p.linked_service_id;
        return '<div class="ccard fi2 '+(linked?'cs-yes':'cs-pend')+'">'+
          '<div class="ch"><div><div class="ctitle">'+esc(p.name)+'</div><div class="cmark">'+esc(p.category_name)+' → '+esc(p.section_name)+(p.marking_size?' · '+esc(p.marking_size):'')+'</div></div>'+
          '<span class="kp-link-state '+(linked?'linked':'unlinked')+'">'+(linked?'Привязана работа':'Без работы')+'</span></div>'+
          '<div class="cmeta">'+
            '<div><div class="mlb">Ед. изм.</div><div class="mvl">'+esc(p.unit||'—')+'</div></div>'+
            '<div><div class="mlb">Поставщик</div><div class="mvl">'+esc(p.supplier||'—')+'</div></div>'+
            '<div><div class="mlb">Примечание</div><div class="mvl">'+esc(p.note||'—')+'</div></div>'+
            '<div><div class="mlb">Закупочная цена</div><div class="mvl">'+(p.purchase_price!=null?esc(p.purchase_price):'—')+'</div></div>'+
            '<div><div class="mlb">Минимальная цена</div><div class="mvl">'+(p.minimal_price!=null?esc(p.minimal_price):'—')+'</div></div>'+
            '<div><div class="mlb">Розничная цена</div><div class="mvl">'+(p.retail_price!=null?esc(p.retail_price):'—')+'</div></div>'+
            '<div><div class="mlb">Работа</div><div class="mvl">'+esc(p.linked_service_name||'—')+'</div></div>'+
          '</div>'+
          '<div class="cft">'+(accessCanUi('catalog','edit')?'<button class="btn btn-g btn-sm" onclick="openKpProductModal('+p.id+')">✏️ Редактировать</button>':'')+(accessCanUi('catalog','delete')?'<button class="btn btn-rd btn-sm" onclick="deleteKpProduct('+p.id+')">🗑 Удалить</button>':'')+'</div>'+
        '</div>';
      }).join('')+'</div>';
    }
  }
  if(servicesWrap){
    var filteredServices=kpCatalogServices.filter(function(s){
      if(q && [s.name,s.marking_size,s.unit].join(' ').toLowerCase().indexOf(q)<0) return false;
      return true;
    });
    if(!filteredServices.length){servicesWrap.innerHTML='<div class="es">Нет работ</div>';}
    else{
      function workSectionLabel(service){
        var code=String(service.work_section_code||'installation');
        if(code==='construction') return 'Строительные работы';
        if(code==='dismantling') return 'Демонтажные работы';
        return 'Монтажные работы';
      }
      servicesWrap.innerHTML='<div class="pgrid">'+filteredServices.map(function(s){
        var linked=parseInt(s.linked_products_count||'0',10)>0;
        return '<div class="ccard fi2 '+(linked?'cs-yes':'cs-pend')+'">'+
          '<div class="ch"><div><div class="ctitle">'+esc(s.name)+'</div><div class="cmark">'+esc(workSectionLabel(s))+(s.marking_size?' · '+esc(s.marking_size):'')+'</div></div>'+
          '<span class="kp-link-state '+(linked?'linked':'unlinked')+'">'+(linked?'Товаров: '+esc(s.linked_products_count):'Без товаров')+'</span></div>'+
          '<div class="cmeta">'+
            '<div><div class="mlb">Закупочная цена</div><div class="mvl">'+(s.purchase_price!=null?esc(s.purchase_price):'—')+'</div></div>'+
            '<div><div class="mlb">Минимальная цена</div><div class="mvl">'+(s.minimal_price!=null?esc(s.minimal_price):'—')+'</div></div>'+
            '<div><div class="mlb">Розничная цена</div><div class="mvl">'+(s.retail_price!=null?esc(s.retail_price):(s.cost!=null?esc(s.cost):'—'))+'</div></div>'+
            '<div><div class="mlb">Ед. изм.</div><div class="mvl">'+esc(s.unit||'—')+'</div></div>'+
            '<div><div class="mlb">Раздел работ</div><div class="mvl">'+esc(workSectionLabel(s))+'</div></div>'+
            '<div><div class="mlb">Привязок</div><div class="mvl">'+esc(s.linked_products_count||'0')+'</div></div>'+
          '</div>'+
          '<div class="cft">'+(accessCanUi('catalog','edit')?'<button class="btn btn-g btn-sm" onclick="openKpServiceModal('+s.id+')">✏️ Редактировать</button>':'')+(accessCanUi('catalog','delete')?'<button class="btn btn-rd btn-sm" onclick="deleteKpService('+s.id+')">🗑 Удалить</button>':'')+'</div>'+
        '</div>';
      }).join('')+'</div>';
    }
  }
  setKpCatalogMode(kpCatalogMode);
}

function ensureCatalogImportProgress(){
  var box=document.getElementById('catalog-import-progress');
  if(box) return box;
  box=document.createElement('div');
  box.id='catalog-import-progress';
  box.style.cssText='position:fixed;right:20px;bottom:20px;width:320px;max-width:calc(100vw - 40px);background:var(--sf);border:1px solid var(--bd);border-radius:14px;box-shadow:var(--shl);padding:14px 16px;z-index:4000;display:none';
  box.innerHTML=
    '<div id="catalog-import-progress-title" style="font-weight:700;margin-bottom:8px">Импорт каталога</div>'+
    '<div id="catalog-import-progress-text" style="color:var(--tx2);font-size:.86rem;margin-bottom:10px">Подготовка...</div>'+
    '<div style="height:8px;background:var(--sf2);border-radius:999px;overflow:hidden">'+
      '<div id="catalog-import-progress-bar" style="height:100%;width:0%;background:var(--ac);transition:width .2s ease"></div>'+
    '</div>';
  document.body.appendChild(box);
  return box;
}

function setCatalogImportProgress(percent,text){
  ensureCatalogImportProgress().style.display='block';
  var bar=document.getElementById('catalog-import-progress-bar');
  var label=document.getElementById('catalog-import-progress-text');
  if(bar) bar.style.width=Math.max(0,Math.min(100,percent||0))+'%';
  if(label) label.textContent=text||'Импорт...';
}

function hideCatalogImportProgress(){
  var box=document.getElementById('catalog-import-progress');
  if(box) box.style.display='none';
}

async function importGeneralCatalogFile(input){
  if(!input.files||!input.files[0]) return;
  var fd=new FormData();
  fd.append('file',input.files[0]);
  setCatalogImportProgress(0,'Загрузка файла...');
  try{
    var data=await new Promise(function(resolve,reject){
      var xhr=new XMLHttpRequest();
      xhr.open('POST','api/catalog.php?action=import_catalog_excel',true);
      xhr.withCredentials=true;
      if(CSRF_TOKEN) xhr.setRequestHeader('X-CSRF-Token',CSRF_TOKEN);
      xhr.upload.onprogress=function(e){
        if(e.lengthComputable){
          var percent=Math.round((e.loaded/e.total)*100);
          setCatalogImportProgress(percent,'Загрузка файла: '+percent+'%');
        }
      };
      xhr.upload.onload=function(){
        setCatalogImportProgress(100,'Файл загружен, идёт импорт...');
      };
      xhr.onerror=function(){reject(new Error('Ошибка импорта'));};
      xhr.onload=function(){
        var raw=xhr.responseText||'';
        var parsed=null;
        try{parsed=raw?JSON.parse(raw):{};}catch(err){reject(new Error('Ошибка ответа сервера'));return;}
        if(xhr.status<200||xhr.status>=300){reject(new Error((parsed&&parsed.error)||'Ошибка импорта'));return;}
        resolve(parsed||{});
      };
      xhr.send(fd);
    });
    setCatalogImportProgress(100,'Импорт завершён');
    toast('Импорт: товаров '+data.products+', работ '+data.services+' ✓');
    if(data.errors&&data.errors.length) toast(data.errors.slice(0,2).join(' | '),'err');
    loadCatalog();
  }catch(e){
    toast(e.message,'err');
  }finally{
    input.value='';
    setTimeout(hideCatalogImportProgress,1200);
  }
}

async function loadKpCompany(force){
  if(!force && kpReferenceCache && kpReferenceCache.company){
    return kpReferenceCache.company;
  }
  if(!force && kpCompany && ((kpCompanies||[]).length || kpCompany.id)){
    renderKpCompany();
    fillKpCompanySelect();
    return Promise.resolve(kpCompany);
  }
  if(kpReferenceCache) kpReferenceCache.company=(async function(){
    var row=await api('kp.php?action=company_get');
    kpCompanies=Array.isArray(row&&row.profiles) ? row.profiles : (row&&row.id ? [row] : []);
    kpCompany=(kpCompanies.find(function(x){return String(x.is_default||'0')==='1';})||kpCompanies[0]||row||{});
    renderKpCompany();
    fillKpCompanySelect();
    return kpCompany;
  })();
  try{
    return await kpReferenceCache.company;
  }catch(e){
    if(kpReferenceCache) kpReferenceCache.company=null;
    toast(e.message,'err');
  }
}

function kpCompanyAutofillValues(){
  try{return JSON.parse((kpCompany&&kpCompany.autofill_fields_json)||'[]')||[];}catch(e){return [];}
}

function kpFindCompanyById(id){
  return (kpCompanies||[]).find(function(row){return String(row.id||'')===String(id||'');})||null;
}

function kpDefaultCompany(){
  return (kpCompanies||[]).find(function(row){return String(row.is_default||'0')==='1';}) || (kpCompanies||[])[0] || null;
}

function selectKpCompanyProfile(id){
  var row=kpFindCompanyById(id);
  if(!row) return;
  kpCompany=row;
  renderKpCompany();
  fillKpCompanySelect();
}

function newKpCompanyProfile(){
  kpCompany={company_type:'ooo',autofill_fields_json:'[]'};
  renderKpCompany();
}

function renderKpCompanyProfilesList(){
  var wrap=document.getElementById('kp-company-profiles-list');
  if(!wrap) return;
  var rows=kpCompanies||[];
  if(!rows.length){
    wrap.innerHTML='<div class="es">Компании ещё не созданы</div>';
    return;
  }
  var typeMap={ip:'ИП',ooo:'ООО'};
  wrap.innerHTML=rows.map(function(row){
    var active=String(row.id||'')===String((kpCompany&&kpCompany.id)||'');
    var name=row.company_name||row.legal_name||'Без названия';
    var meta=[typeMap[row.company_type]||'ООО',row.inn?('ИНН '+row.inn):'',row.is_default?'Основная':''].filter(Boolean).join(' · ');
    return '<button type="button" class="kp-company-profile-card '+(active?'active':'')+'" onclick="selectKpCompanyProfile('+parseInt(row.id||0,10)+')">'+
      '<span><b>'+esc(name)+'</b><small>'+esc(meta)+'</small></span>'+
      (row.is_default?'<em>★</em>':'')+
    '</button>';
  }).join('');
}

function updateKpCompanyTypeUi(){
  var type=(document.getElementById('kp-company-type') ? document.getElementById('kp-company-type').value : 'ooo') || 'ooo';
  var ogrnLabel=document.getElementById('kp-company-ogrn-label');
  var legalLabel=document.getElementById('kp-company-legal-label');
  if(ogrnLabel) ogrnLabel.textContent=type==='ip' ? 'ОГРНИП' : 'ОГРН';
  if(legalLabel) legalLabel.textContent=type==='ip' ? 'ФИО ИП' : 'Юридическое название';
}

function renderKpCompany(){
  var idEl=document.getElementById('kp-company-id');
  if(idEl) idEl.value=kpCompany&&kpCompany.id?String(kpCompany.id):'';
  var map={
    'kp-company-type':'company_type','kp-company-name':'company_name','kp-company-legal':'legal_name','kp-company-inn':'inn','kp-company-ogrn':'ogrn','kp-company-kpp':'kpp',
    'kp-company-address':'address','kp-company-phone':'phone','kp-company-email':'email','kp-company-website':'website',
    'kp-company-director':'director_name','kp-company-signatory':'signatory_name','kp-company-signatory-title':'signatory_title',
    'kp-company-bank-name':'bank_name','kp-company-bank-bik':'bank_bik','kp-company-bank-account':'bank_account','kp-company-corr-account':'corr_account',
    'kp-company-intro':'intro_default','kp-company-footer':'footer_default'
  };
  Object.keys(map).forEach(function(id){ if(document.getElementById(id)) document.getElementById(id).value=kpCompany&&kpCompany[map[id]]?kpCompany[map[id]]:''; });
  if(document.getElementById('kp-company-type') && !document.getElementById('kp-company-type').value){
    document.getElementById('kp-company-type').value='ooo';
  }
  updateKpCompanyTypeUi();
  var selected=kpCompanyAutofillValues();
  var wrap=document.getElementById('kp-company-autofill');
  if(wrap){
    wrap.innerHTML=KP_COMPANY_AUTOFILL_FIELDS.map(function(f){
      return '<label class="kp-check-item"><input type="checkbox" value="'+f.key+'" '+(selected.indexOf(f.key)>=0?'checked':'')+'> <span>'+esc(f.label)+'</span></label>';
    }).join('');
  }
  renderKpCompanyProfilesList();
}

async function saveKpCompany(){
  var selected=[];
  document.querySelectorAll('#kp-company-autofill input[type=checkbox]:checked').forEach(function(cb){selected.push(cb.value);});
  try{
    var saved=await api('kp.php',{
      action:'company_save',
      id:document.getElementById('kp-company-id').value||0,
      company_type:document.getElementById('kp-company-type').value,
      company_name:document.getElementById('kp-company-name').value.trim(),
      legal_name:document.getElementById('kp-company-legal').value.trim(),
      inn:document.getElementById('kp-company-inn').value.trim(),
      ogrn:document.getElementById('kp-company-ogrn').value.trim(),
      kpp:document.getElementById('kp-company-kpp').value.trim(),
      address:document.getElementById('kp-company-address').value.trim(),
      phone:document.getElementById('kp-company-phone').value.trim(),
      email:document.getElementById('kp-company-email').value.trim(),
      website:document.getElementById('kp-company-website').value.trim(),
      director_name:document.getElementById('kp-company-director').value.trim(),
      signatory_name:document.getElementById('kp-company-signatory').value.trim(),
      signatory_title:document.getElementById('kp-company-signatory-title').value.trim(),
      bank_name:document.getElementById('kp-company-bank-name').value.trim(),
      bank_bik:document.getElementById('kp-company-bank-bik').value.trim(),
      bank_account:document.getElementById('kp-company-bank-account').value.trim(),
      corr_account:document.getElementById('kp-company-corr-account').value.trim(),
      intro_default:document.getElementById('kp-company-intro').value.trim(),
      footer_default:document.getElementById('kp-company-footer').value.trim(),
      autofill_fields:selected
    });
    toast('Данные компании сохранены ✓');
    loadKpCompany(true);
  }catch(e){toast(e.message,'err');}
}

async function lookupKpInn(){
  var inn=document.getElementById('kp-company-inn').value.trim();
  if(!inn){toast('Введите ИНН','err');return;}
  try{
    var row=await api('kp.php',{action:'company_lookup_inn',inn:inn});
    if(row.company_type) document.getElementById('kp-company-type').value=row.company_type;
    updateKpCompanyTypeUi();
    if(row.company_name) document.getElementById('kp-company-name').value=row.company_name;
    if(row.legal_name) document.getElementById('kp-company-legal').value=row.legal_name;
    if(row.inn) document.getElementById('kp-company-inn').value=row.inn;
    if(row.ogrn) document.getElementById('kp-company-ogrn').value=row.ogrn;
    if(row.kpp) document.getElementById('kp-company-kpp').value=row.kpp;
    if(row.bank_name) document.getElementById('kp-company-bank-name').value=row.bank_name;
    if(row.bank_bik) document.getElementById('kp-company-bank-bik').value=row.bank_bik;
    if(row.bank_account) document.getElementById('kp-company-bank-account').value=row.bank_account;
    if(row.corr_account) document.getElementById('kp-company-corr-account').value=row.corr_account;
    if(row.email) document.getElementById('kp-company-email').value=row.email;
    if(row.address) document.getElementById('kp-company-address').value=row.address;
    if(row.director_name) document.getElementById('kp-company-director').value=row.director_name;
    toast('Данные по ИНН загружены ✓');
  }catch(e){toast(e.message,'err');}
}

async function loadKpClients(force){
  if(!force && kpReferenceCache && kpReferenceCache.clients){
    return kpReferenceCache.clients;
  }
  if(!force && kpClients.length){
    renderKpClients();
    fillKpClientSelect();
    return Promise.resolve(kpClients);
  }
  if(kpReferenceCache) kpReferenceCache.clients=(async function(){
    var rows=await api('kp.php?action=clients');
    kpClients=Array.isArray(rows)?rows:[];
    renderKpClients();
    fillKpClientSelect();
    return kpClients;
  })();
  try{
    return await kpReferenceCache.clients;
  }catch(e){
    if(kpReferenceCache) kpReferenceCache.clients=null;
    toast(e.message,'err');
  }
}

async function setDefaultKpCompany(){
  var id=(document.getElementById('kp-company-id')||{}).value||'';
  if(!id){toast('Сначала сохраните компанию','err');return;}
  try{
    await api('kp.php',{action:'company_set_default',id:id});
    toast('Основная компания выбрана ✓');
    await loadKpCompany(true);
    selectKpCompanyProfile(id);
  }catch(e){toast(e.message,'err');}
}

async function deleteKpCompany(){
  var id=(document.getElementById('kp-company-id')||{}).value||'';
  if(!id){toast('Компания не выбрана','err');return;}
  showConfirm('Удалить компанию','Удалить выбранную компанию исполнителя?',async function(){
    try{
      await api('kp.php',{action:'company_delete',id:id});
      toast('Компания удалена ✓');
      loadKpCompany(true);
    }catch(e){toast(e.message,'err');}
  });
}

async function loadKpContractors(force){
  if(!force && kpReferenceCache && kpReferenceCache.contractors){
    return kpReferenceCache.contractors;
  }
  if(!force && kpContractors.length){
    renderKpContractors();
    fillKpContractorSelect();
    return Promise.resolve(kpContractors);
  }
  if(kpReferenceCache) kpReferenceCache.contractors=(async function(){
    var rows=await api('kp.php?action=contractors');
    kpContractors=Array.isArray(rows)?rows:[];
    renderKpContractors();
    fillKpContractorSelect();
    return kpContractors;
  })();
  try{
    return await kpReferenceCache.contractors;
  }catch(e){
    if(kpReferenceCache) kpReferenceCache.contractors=null;
    toast(e.message,'err');
  }
}

function fillKpClientSelect(){
  var sel=document.getElementById('kp-quote-client');
  if(!sel) return;
  var cur=sel.value||kpBuilder.client_id||'';
  sel.value=cur||'';
  syncKpPartyInput('client');
}

function fillKpContractorSelect(){
  var sel=document.getElementById('kp-quote-contractor');
  if(!sel) return;
  var meta=(kpBuilder.payload&&kpBuilder.payload.quote_meta)||{};
  var defaultCompany=kpDefaultCompany();
  var cur=sel.value||(meta.contractor_id?String(meta.contractor_id):'')||(!kpBuilder.id&&defaultCompany?String(defaultCompany.id):'');
  sel.value=cur||'';
  syncKpPartyInput('contractor');
  if(cur && !meta.contractor_id && !kpBuilder.id && typeof applyKpCompanyPreset==='function') applyKpCompanyPreset(cur);
}

function fillKpCompanySelect(){
  fillKpContractorSelect();
}

function kpPartyConfig(kind){
  if(kind==='contractor'){
    return {
      hiddenId:'kp-quote-contractor',
      inputId:'kp-quote-contractor-search',
      dropId:'kp-quote-contractor-drop',
      rows:kpCompanies||[],
      emptyLabel:'',
      onPick:applyKpCompanyPreset
    };
  }
  return {
    hiddenId:'kp-quote-client',
    inputId:'kp-quote-client-search',
    dropId:'kp-quote-client-drop',
    rows:kpClients||[],
    emptyLabel:'',
    onPick:applyKpClientPreset
  };
}

function kpPartyLabel(kind,row){
  if(!row) return '';
  if(kind==='contractor') return String(row.company_name||row.legal_name||'Исполнитель');
  return String(row.company_name||row.legal_name||row.recipient_name||'Клиент');
}

function kpPartyFindById(kind,id){
  var cfg=kpPartyConfig(kind);
  return (cfg.rows||[]).find(function(row){return String(row.id)===String(id);})||null;
}

function kpPartyFindByLabel(kind,label){
  label=String(label||'').trim().toLocaleLowerCase('ru');
  if(!label) return null;
  var cfg=kpPartyConfig(kind);
  return (cfg.rows||[]).find(function(row){
    return kpPartyLabel(kind,row).trim().toLocaleLowerCase('ru')===label;
  })||null;
}

function syncKpPartyInput(kind){
  var cfg=kpPartyConfig(kind);
  var hidden=document.getElementById(cfg.hiddenId);
  var input=document.getElementById(cfg.inputId);
  if(!hidden || !input) return;
  var row=kpPartyFindById(kind,hidden.value);
  input.value=row ? kpPartyLabel(kind,row) : '';
}

function setKpPartyValue(kind,id){
  var cfg=kpPartyConfig(kind);
  var hidden=document.getElementById(cfg.hiddenId);
  var input=document.getElementById(cfg.inputId);
  var drop=document.getElementById(cfg.dropId);
  var row=kpPartyFindById(kind,id);
  if(hidden) hidden.value=row ? String(row.id) : '';
  if(input) input.value=row ? kpPartyLabel(kind,row) : '';
  if(drop) drop.style.display='none';
  cfg.onPick(row ? String(row.id) : '');
}

function applyKpCompanyPreset(id){
  if(!kpBuilder.payload || typeof kpBuilder.payload!=='object') kpBuilder.payload={};
  if(!kpBuilder.payload.quote_meta || typeof kpBuilder.payload.quote_meta!=='object') kpBuilder.payload.quote_meta={};
  var company=kpFindCompanyById(id)||null;
  kpCompany=company||kpCompany;
  kpBuilder.payload.quote_meta.contractor_id=company ? parseInt(company.id||0,10)||0 : 0;
  kpBuilder.payload.quote_meta.contractor_name=company ? (company.company_name||company.legal_name||'') : '';
  kpBuilder.payload.quote_meta.contractor_snapshot=company ? {
    company_type:company.company_type||'ooo',
    company_name:company.company_name||'',
    legal_name:company.legal_name||'',
    recipient_name:company.signatory_name||company.legal_name||'',
    inn:company.inn||'',
    ogrn:company.ogrn||'',
    kpp:company.kpp||'',
    object_address:company.address||'',
    phone:company.phone||'',
    email:company.email||'',
    bank_name:company.bank_name||'',
    bank_bik:company.bank_bik||'',
    bank_account:company.bank_account||'',
    corr_account:company.corr_account||''
  } : {};
}

function showKpPartyDrop(kind,val){
  var cfg=kpPartyConfig(kind);
  var input=document.getElementById(cfg.inputId);
  var drop=document.getElementById(cfg.dropId);
  if(!input || !drop) return;
  var q=String(val||'').trim().toLocaleLowerCase('ru');
  var rows=(cfg.rows||[]).filter(function(row){
    var label=kpPartyLabel(kind,row);
    return !q || label.toLocaleLowerCase('ru').indexOf(q)>=0;
  });
  drop.innerHTML='';
  if(!rows.length){
    drop.innerHTML='<div class="ac-item" style="opacity:.7;pointer-events:none">Нет совпадений</div>';
    openAutocompleteDrop(input, drop);
    return;
  }
  rows.forEach(function(row){
    var div=document.createElement('div');
    div.className='ac-item';
    div.dataset.value=String(row.id);
    div.textContent=kpPartyLabel(kind,row);
    div.onmousedown=function(e){
      e.preventDefault();
      setKpPartyValue(kind,this.dataset.value||'');
    };
    drop.appendChild(div);
  });
  openAutocompleteDrop(input, drop);
}

function validateKpPartyInput(kind){
  setTimeout(function(){
    var cfg=kpPartyConfig(kind);
    var drop=document.getElementById(cfg.dropId);
    if(drop) drop.style.display='none';
    commitKpPartyInput(kind);
  },120);
}

function commitKpPartyInput(kind){
  var cfg=kpPartyConfig(kind);
  var hidden=document.getElementById(cfg.hiddenId);
  var input=document.getElementById(cfg.inputId);
  if(!hidden || !input) return true;
  var typed=String(input.value||'').trim();
  if(!typed){
    setKpPartyValue(kind,'');
    return true;
  }
  var row=kpPartyFindByLabel(kind,typed);
  if(row){
    setKpPartyValue(kind,row.id);
    return true;
  }
  syncKpPartyInput(kind);
  return !typed;
}

function handleKpPartyKeydown(e,kind){
  var cfg=kpPartyConfig(kind);
  var drop=document.getElementById(cfg.dropId);
  if(e.key==='ArrowDown' || e.key==='ArrowUp'){
    e.preventDefault();
    e.stopPropagation();
    if(!drop || drop.style.display==='none'){
      showKpPartyDrop(kind,(document.getElementById(cfg.inputId)||{}).value||'');
      return false;
    }
    moveAutocompleteSelection(drop,e.key==='ArrowDown'?1:-1);
    return false;
  }
  if(e.key==='Enter'){
    e.preventDefault();
    e.stopPropagation();
    if(drop && drop.style.display!=='none' && getAutocompleteItems(drop).length){
      chooseAutocompleteSelection(drop);
    }else{
      validateKpPartyInput(kind);
    }
    return false;
  }
  if(e.key==='Escape'){
    if(drop) drop.style.display='none';
    syncKpPartyInput(kind);
    return false;
  }
  return true;
}


async function deleteKpClient(id){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  if(!confirm('Удалить клиента?')) return;
  try{await api('kp.php',{action:'delete_client',id:id});toast('Клиент удалён');loadKpClients(true);}catch(e){toast(e.message,'err');}
}

async function loadPkpPresets(){
  pkpPresets=[];
  renderPkpPresets();
  return pkpPresets;
}

function getPkpPresetSections(categoryCode){
  return kpCatalogSections.filter(function(s){return s.category_code===categoryCode;});
}

function getPkpPresetObjects(categoryCode, sectionId){
  return kpCatalogProducts.filter(function(p){
    return p.category_code===categoryCode && (!sectionId || String(p.section_id)===String(sectionId));
  });
}

function setPkpPresetItemField(idx,field,val){
  var item=pkpPresetDraft.items[idx];
  if(!item) return;
  item[field]=field==='quantity' ? Math.max(parseFloat(val||0)||0,1) : val;
  if(field==='category_code'){
    item.section_id='';
    item.object_id='';
  }
  if(field==='section_id'){
    item.object_id='';
  }
  renderPkpPresetItems();
}

function setPkpPresetObjectByName(idx,val){
  var item=pkpPresetDraft.items[idx];
  if(!item) return;
  var objects=getPkpPresetObjects(item.category_code||'equipment', item.section_id||'');
  var match=objects.find(function(obj){
    var label=obj.name+(obj.marking_size?' · '+obj.marking_size:'');
    return label===val;
  });
  item.object_id=match ? String(match.id) : '';
}

function renderPkpPresetObjectDrop(idx, query){
  var item=pkpPresetDraft.items[idx];
  var inp=document.getElementById('pkp-preset-object-'+idx);
  var drop=document.getElementById('pkp-preset-object-drop-'+idx);
  if(!item || !inp || !drop) return;
  var objects=getPkpPresetObjects(item.category_code||'equipment', item.section_id||'');
  var q=(query||'').trim().toLowerCase();
  var filtered=objects.filter(function(obj){
    var label=(obj.name||'')+(obj.marking_size?' · '+obj.marking_size:'');
    return !q || label.toLowerCase().indexOf(q)>=0;
  });
  drop.innerHTML='';
  if(!filtered.length){
    drop.style.display='none';
    return;
  }
  filtered.slice(0,60).forEach(function(obj){
    var label=(obj.name||'')+(obj.marking_size?' · '+obj.marking_size:'');
    var div=document.createElement('div');
    div.className='ac-item';
    div.textContent=label;
    div.onmousedown=function(e){
      e.preventDefault();
      selectPkpPresetObject(idx, label);
    };
    drop.appendChild(div);
  });
  drop.style.display='block';
}

function pkpPresetObjectInput(idx,val){
  setPkpPresetObjectByName(idx,val);
  renderPkpPresetObjectDrop(idx,val);
}

function pkpPresetObjectFocus(idx){
  var inp=document.getElementById('pkp-preset-object-'+idx);
  renderPkpPresetObjectDrop(idx, inp ? inp.value : '');
}

function pkpPresetObjectMouseDown(idx){
  var inp=document.getElementById('pkp-preset-object-'+idx);
  setTimeout(function(){
    renderPkpPresetObjectDrop(idx, inp ? inp.value : '');
  },0);
}

function selectPkpPresetObject(idx,label){
  var inp=document.getElementById('pkp-preset-object-'+idx);
  var drop=document.getElementById('pkp-preset-object-drop-'+idx);
  if(inp) inp.value=label||'';
  setPkpPresetObjectByName(idx,label||'');
  if(drop) drop.style.display='none';
}

function addPkpPresetItem(){
  pkpPresetDraft.items.push(pkpPresetEmptyItem());
  renderPkpPresetItems();
}

function removePkpPresetItem(idx){
  pkpPresetDraft.items.splice(idx,1);
  if(!pkpPresetDraft.items.length) pkpPresetDraft.items=[pkpPresetEmptyItem()];
  renderPkpPresetItems();
}


async function deletePkpPreset(id){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  if(!confirm('Удалить комплект?')) return;
  try{
    throw new Error('Комплекты перенесены в каталог');
    toast('Комплект удалён');
    loadPkpPresets();
  }catch(e){toast(e.message,'err');}
}

async function applyPkpPresetPrompt(vi){
  if(!pkpPresets.length) await loadPkpPresets();
  if(!pkpPresets.length){toast('Сначала создайте комплект','err');return;}
  pkpPresetApplyState.variantIndex=vi;
  document.getElementById('pkp-apply-variant-id').value=String(vi);
  document.getElementById('pkp-apply-preset-input').value='';
  om('m-pkp-apply-preset');
  pkpRenderPresetApplyDrop('');
}

function pkpRenderPresetApplyDrop(query){
  var drop=document.getElementById('pkp-apply-preset-drop');
  var inp=document.getElementById('pkp-apply-preset-input');
  if(!drop || !inp) return;
  var q=(query||'').trim().toLowerCase();
  var list=pkpPresets.filter(function(p){
    var name=(p.name||'').trim();
    return !q || name.toLowerCase().indexOf(q)>=0;
  });
  drop.innerHTML='';
  if(!list.length){
    drop.style.display='none';
    return;
  }
  list.slice(0,50).forEach(function(p){
    var div=document.createElement('div');
    div.className='ac-item';
    div.textContent=p.name||'';
    div.onmousedown=function(e){
      e.preventDefault();
      pkpSelectApplyPreset(p.name||'');
    };
    drop.appendChild(div);
  });
  var rect=inp.getBoundingClientRect();
  drop.style.left=rect.left+'px';
  drop.style.top=(rect.bottom+2)+'px';
  drop.style.width=rect.width+'px';
  drop.style.display='block';
}

function pkpPresetApplyInput(val){
  pkpRenderPresetApplyDrop(val);
}

function pkpPresetApplyFocus(){
  var inp=document.getElementById('pkp-apply-preset-input');
  pkpRenderPresetApplyDrop(inp ? inp.value : '');
}

function pkpPresetApplyMouseDown(e){
  var inp=document.getElementById('pkp-apply-preset-input');
  setTimeout(function(){
    pkpRenderPresetApplyDrop(inp ? inp.value : '');
  },0);
}

function pkpSelectApplyPreset(name){
  var inp=document.getElementById('pkp-apply-preset-input');
  var drop=document.getElementById('pkp-apply-preset-drop');
  if(inp) inp.value=name||'';
  if(drop) drop.style.display='none';
}

function confirmApplyPkpPreset(){
  var vi=parseInt(document.getElementById('pkp-apply-variant-id').value||'0',10)||0;
  var name=(document.getElementById('pkp-apply-preset-input').value||'').trim();
  if(!name){toast('Выберите комплект','err');return;}
  var preset=pkpPresets.find(function(x){return (x.name||'').trim()===name;});
  if(!preset){toast('Комплект не найден','err');return;}
  cm('m-pkp-apply-preset');
  applyPkpPresetToVariant(vi, preset.id);
}

function getKpCompanyField(key){
  var selectedCompany=(typeof kpSelectedCompanyForQuote==='function') ? kpSelectedCompanyForQuote() : null;
  var map={
    company_type:'kp-company-type',company_name:'kp-company-name',legal_name:'kp-company-legal',inn:'kp-company-inn',ogrn:'kp-company-ogrn',kpp:'kp-company-kpp',
    address:'kp-company-address',phone:'kp-company-phone',email:'kp-company-email',website:'kp-company-website',
    director_name:'kp-company-director',signatory_name:'kp-company-signatory',signatory_title:'kp-company-signatory-title',
    bank_name:'kp-company-bank-name',bank_bik:'kp-company-bank-bik',bank_account:'kp-company-bank-account',corr_account:'kp-company-corr-account',
    intro_default:'kp-company-intro',footer_default:'kp-company-footer'
  };
  var el=document.getElementById(map[key]);
  if(el && activePage==='kp-company') return el.value.trim();
  if(selectedCompany && selectedCompany[key]!=null) return String(selectedCompany[key]||'').trim();
  return el ? el.value.trim() : '';
}

function kpSelectedCompanyForQuote(){
  var el=document.getElementById('kp-quote-contractor');
  var id=el ? el.value : '';
  return kpFindCompanyById(id) || kpCompany || kpDefaultCompany() || {};
}

function getKpCompanySnapshotForQuote(){
  var selected=[];
  var company=kpSelectedCompanyForQuote();
  if(activePage==='kp-company'){
    document.querySelectorAll('#kp-company-autofill input[type=checkbox]:checked').forEach(function(cb){
      selected.push(String(cb.value||''));
    });
  }
  if(!selected.length && company&&company.autofill_fields_json){
    try{selected=JSON.parse(company.autofill_fields_json)||[];}catch(e){}
  }
  if(!selected.length){
    selected=KP_COMPANY_AUTOFILL_FIELDS.map(function(f){return f.key;});
  }
  var snapshot={};
  selected.forEach(function(key){snapshot[key]=company&&company[key]!=null?String(company[key]||''):getKpCompanyField(key);});
  snapshot.intro_default=company&&company.intro_default!=null?String(company.intro_default||''):getKpCompanyField('intro_default');
  snapshot.footer_default=company&&company.footer_default!=null?String(company.footer_default||''):getKpCompanyField('footer_default');
  return snapshot;
}

function getKpCurrentManagerName(){
  return (CU&&((CU.full_name||'').trim()||(CU.username||'').trim()))||'';
}

function getKpCurrentRopName(){
  return (CU&&((CU.rop_name||'').trim()||(CU.rop_full_name||'').trim()))||'';
}

function getKpQuoteMeta(){
  var managerEl=document.getElementById('kp-quote-manager');
  var ropEl=document.getElementById('kp-quote-rop');
  var contractorEl=document.getElementById('kp-quote-contractor');
  var managerOpt=managerEl&&managerEl.options ? managerEl.options[managerEl.selectedIndex] : null;
  var ropOpt=ropEl&&ropEl.options ? ropEl.options[ropEl.selectedIndex] : null;
  var contractorId=parseInt((contractorEl&&contractorEl.value)||0,10)||0;
  var contractor=kpFindCompanyById(contractorId)||null;
  var managerId=parseInt((managerEl&&managerEl.value)||0,10)||0;
  var ropId=parseInt((ropEl&&ropEl.value)||0,10)||0;
  var managerName=(managerOpt&&managerOpt.text ? managerOpt.text : getKpCurrentManagerName()).trim();
  var ropName=(ropOpt&&ropOpt.value ? ropOpt.text : '').trim();
  var isAdmin=!!(CU&&CU.role==='admin');
  return {
    object_address:'',
    object_type:'',
    proposal_title:getDefaultProposalTitle(),
    manager_name:managerName,
    manager_id:isAdmin ? managerId : (managerId || (parseInt((CU&&CU.id)||0,10)||0)),
    rop_name:ropName || getKpCurrentRopName(),
    rop_id:isAdmin ? ropId : (ropId || (parseInt((CU&&CU.rop_id)||0,10)||0)),
    contractor_id:contractorId,
    contractor_name:contractor ? (contractor.company_name||contractor.legal_name||'') : '',
    contractor_snapshot:contractor ? {
      company_type:contractor.company_type||'ooo',
      company_name:contractor.company_name||'',
      legal_name:contractor.legal_name||'',
      recipient_name:contractor.signatory_name||contractor.legal_name||'',
      inn:contractor.inn||'',
      ogrn:contractor.ogrn||'',
      kpp:contractor.kpp||'',
      object_address:contractor.address||'',
      phone:contractor.phone||'',
      email:contractor.email||'',
      bank_name:contractor.bank_name||'',
      bank_bik:contractor.bank_bik||'',
      bank_account:contractor.bank_account||'',
      corr_account:contractor.corr_account||''
    } : {}
  };
}

function getDefaultProposalTitle(){
  return quoteWorkspaceMode==='pkp' ? 'Предварительное коммерческое предложение' : 'Коммерческое предложение';
}

