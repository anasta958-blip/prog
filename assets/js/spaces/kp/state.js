// ===================== КП =====================
if(!kpBuilder.workflow_status) kpBuilder.workflow_status=getDefaultQuoteWorkflowStatus();
var kpBuilderLoadToken=0;
function getKpBuilderDraftStorageKey(mode){
  var normalizedMode=mode==='pkp'?'pkp':'kp';
  var id=arguments.length>1 ? (parseInt(arguments[1]||0,10)||0) : (parseInt((kpBuilder&&kpBuilder.id)||0,10)||0);
  var userId=parseInt((CU&&CU.id)||0,10)||0;
  return 'kp_builder_draft_v2_'+userId+'_'+normalizedMode+'_'+id;
}
function getKpBuilderDraftPointerKey(mode){
  var userId=parseInt((CU&&CU.id)||0,10)||0;
  return 'kp_builder_draft_active_v2_'+userId+'_'+(mode==='pkp'?'pkp':'kp');
}
function cloneKpBuilderState(state){
  try{return JSON.parse(JSON.stringify(state||{}));}catch(e){return null;}
}
function normalizeKpBuilderState(state){
  state=state&&typeof state==='object'?state:{};
  var normalized={
    id:parseInt(state.id||0,10)||0,
    title:state.title||'',
    status:state.status||'created',
    workflow_status:kpCanonicalWorkflowStatus(state.workflow_status||getDefaultQuoteWorkflowStatus(), quoteWorkspaceMode)||getDefaultQuoteWorkflowStatus(),
    selected_variant_label:state.selected_variant_label||'',
    client_id:state.client_id||'',
    owner_user_id:parseInt(state.owner_user_id||0,10)||0,
    client_snapshot:(state.client_snapshot&&typeof state.client_snapshot==='object')?state.client_snapshot:{},
    payload:(state.payload&&typeof state.payload==='object')?state.payload:{},
    active_type_index:parseInt(state.active_type_index||0,10)||0,
    active_variant_index:parseInt(state.active_variant_index||0,10)||0,
    proposal_types:Array.isArray(state.proposal_types)?state.proposal_types:[],
    variants:Array.isArray(state.variants)&&state.variants.length?state.variants:[]
  };
  kpEnsureProposalTypesOnState(normalized);
  return normalized;
}
function syncKpBuilderFromForm(){
  if(activePage!=='kp-builder') return;
  var titleEl=document.getElementById('kp-quote-title');
  var clientEl=document.getElementById('kp-quote-client');
  var contractorEl=document.getElementById('kp-quote-contractor');
  var companyEl=document.getElementById('kp-quote-client-company');
  var recipientEl=document.getElementById('kp-quote-recipient');
  if(titleEl) kpBuilder.title=titleEl.value.trim();
  if(clientEl) kpBuilder.client_id=clientEl.value||'';
  if(!kpBuilder.client_snapshot || typeof kpBuilder.client_snapshot!=='object') kpBuilder.client_snapshot={};
  if(companyEl) kpBuilder.client_snapshot.company_name=companyEl.value.trim();
  if(recipientEl) kpBuilder.client_snapshot.recipient_name=recipientEl.value.trim();
  kpBuilder.payload=collectKpBuilderPayload();
  if(contractorEl && kpBuilder.payload && kpBuilder.payload.quote_meta){
    kpBuilder.payload.quote_meta.contractor_id=parseInt(contractorEl.value||'0',10)||0;
  }
}
function kpBuilderDraftSnapshot(){
  syncKpBuilderFromForm();
  var snapshot=cloneKpBuilderState(kpBuilder)||{};
  Object.keys(snapshot).forEach(function(key){
    if(key.indexOf('__')===0) delete snapshot[key];
  });
  return JSON.stringify(snapshot);
}
function kpInitializeDraftTracking(signature){
  if(!kpBuilder) return;
  kpBuilder.__draftBaselineSignature=typeof signature==='string' ? signature : kpBuilderDraftSnapshot();
}
function kpHasUnsavedChanges(){
  if(activePage!=='kp-builder' || !kpBuilder || kpBuilder.__payloadLoading) return false;
  if(typeof kpBuilder.__draftBaselineSignature!=='string') return false;
  return kpBuilderDraftSnapshot()!==kpBuilder.__draftBaselineSignature;
}
var kpDraftSaveTimer=0;
function scheduleKpBuilderDraftSave(){
  if(activePage!=='kp-builder') return;
  clearTimeout(kpDraftSaveTimer);
  kpDraftSaveTimer=setTimeout(function(){
    if(kpHasUnsavedChanges()) saveKpBuilderDraft(quoteWorkspaceMode);
  },120);
}
function saveKpBuilderDraft(mode){
  try{
    var normalizedMode=mode||quoteWorkspaceMode;
    var builderId=parseInt((kpBuilder&&kpBuilder.id)||0,10)||0;
    var snapshot=kpBuilderDraftSnapshot();
    localStorage.setItem(getKpBuilderDraftStorageKey(normalizedMode,builderId), JSON.stringify({
      workspace:normalizedMode,
      entity_id:builderId,
      saved_at:Date.now(),
      base_signature:kpBuilder.__draftBaselineSignature||'',
      builder:cloneKpBuilderState(kpBuilder)
    }));
    localStorage.setItem(getKpBuilderDraftPointerKey(normalizedMode),String(builderId));
  }catch(e){}
}
function loadKpBuilderDraft(mode,id){
  try{
    var normalizedMode=mode||quoteWorkspaceMode;
    var requestedId=arguments.length>1 ? (parseInt(id||0,10)||0) : parseInt(localStorage.getItem(getKpBuilderDraftPointerKey(normalizedMode))||'0',10)||0;
    var raw=localStorage.getItem(getKpBuilderDraftStorageKey(normalizedMode,requestedId));
    if(!raw && arguments.length<2){
      raw=localStorage.getItem('kp_builder_draft_'+(normalizedMode==='pkp'?'pkp':'kp'));
    }
    if(!raw) return null;
    var parsed=JSON.parse(raw);
    if(!parsed || !parsed.builder) return null;
    var restored=normalizeKpBuilderState(parsed.builder);
    restored.__draftBaselineSignature=typeof parsed.base_signature==='string' ? parsed.base_signature : '';
    restored.__draftRestored=true;
    return restored;
  }catch(e){
    return null;
  }
}
function clearKpBuilderDraft(mode,id){
  try{
    var normalizedMode=mode||quoteWorkspaceMode;
    var builderId=arguments.length>1 ? (parseInt(id||0,10)||0) : (parseInt((kpBuilder&&kpBuilder.id)||0,10)||0);
    localStorage.removeItem(getKpBuilderDraftStorageKey(normalizedMode,builderId));
    localStorage.removeItem('kp_builder_draft_'+(normalizedMode==='pkp'?'pkp':'kp'));
    if(String(localStorage.getItem(getKpBuilderDraftPointerKey(normalizedMode))||'')===String(builderId)){
      localStorage.removeItem(getKpBuilderDraftPointerKey(normalizedMode));
    }
  }catch(e){}
}
function restoreKpBuilderDraftIfAny(mode){
  var draft=loadKpBuilderDraft(mode||quoteWorkspaceMode);
  if(!draft) return false;
  kpBuilder=draft;
  return true;
}
async function confirmKpBuilderLeave(){
  if(!kpHasUnsavedChanges()) return true;
  saveKpBuilderDraft(quoteWorkspaceMode);
  var keep=await showConfirmDialog({
    title:'Несохранённые изменения',
    message:'Внесённые изменения не сохранены, сохранить локально для дальнейшей работы?',
    icon:'💾',
    confirmText:'Сохранить',
    confirmClass:'btn-p',
    cancelText:'Нет',
    dismissible:false
  });
  if(!keep) clearKpBuilderDraft(quoteWorkspaceMode,kpBuilder.id||0);
  return true;
}
document.addEventListener('input',function(e){
  if(activePage==='kp-builder' && e.target && e.target.closest && e.target.closest('#page-kp-builder')) scheduleKpBuilderDraftSave();
});
document.addEventListener('change',function(e){
  if(activePage==='kp-builder' && e.target && e.target.closest && e.target.closest('#page-kp-builder')) scheduleKpBuilderDraftSave();
});
document.addEventListener('click',function(e){
  if(activePage==='kp-builder' && e.target && e.target.closest && e.target.closest('#page-kp-builder')) scheduleKpBuilderDraftSave();
});
var KP_WORKFLOW_STATUSES=['Составить КП','Согласовать КП','Согласовать с клиентом','Составить договор','Получить оплату','Закупить материал','Получить финальную оплату','Оплата получена','Выполненные монтажи','Вторые этапы'];
var PKP_WORKFLOW_STATUSES=['Составить ПКП','Согласовать ПКП','Согласовать с клиентом','ПКП согласовано'];
var KP_COMPANY_AUTOFILL_FIELDS=[
  {key:'company_type',label:'Тип компании'},
  {key:'company_name',label:'Название компании'},
  {key:'legal_name',label:'Юридическое название'},
  {key:'inn',label:'ИНН'},
  {key:'ogrn',label:'ОГРН'},
  {key:'kpp',label:'КПП'},
  {key:'address',label:'Адрес'},
  {key:'phone',label:'Телефон'},
  {key:'email',label:'Email'},
  {key:'website',label:'Сайт'},
  {key:'director_name',label:'Директор'},
  {key:'signatory_name',label:'Подписант'},
  {key:'signatory_title',label:'Должность подписанта'},
  {key:'bank_name',label:'Банк'},
  {key:'bank_bik',label:'БИК'},
  {key:'bank_account',label:'Расчётный счёт'},
  {key:'corr_account',label:'Корр. счёт'}
];

function quoteApiFile(){
  return getQuoteApiFileByMode(quoteWorkspaceMode);
}
function kpCanonicalWorkflowStatus(status, mode){
  status=String(status||'').trim();
  if(!status) return '';
  if(/^Выполнен/i.test(status) && /монтажи$/i.test(status)) return 'Выполненные монтажи';
  if(/^ПКП согласован/i.test(status)) return 'ПКП согласовано';
  return status;
}
function kpNormalizeQuoteMode(mode){
  return mode==='pkp' ? 'pkp' : 'kp';
}
function getQuoteApiFileByMode(mode){
  return kpNormalizeQuoteMode(mode)==='pkp' ? 'pkp.php' : 'kp.php';
}
function kpApiGet(action, mode){
  return api(getQuoteApiFileByMode(mode||quoteWorkspaceMode)+'?action='+action);
}
function getQuoteModeTitle(mode){
  return kpNormalizeQuoteMode(mode)==='pkp' ? 'ПКП' : 'КП';
}
function getQuoteWorkspaceTitle(){
  return getQuoteModeTitle(quoteWorkspaceMode);
}
function getQuoteWorkflowStatusesForMode(mode){
  return kpNormalizeQuoteMode(mode)==='pkp' ? PKP_WORKFLOW_STATUSES : KP_WORKFLOW_STATUSES;
}
function getQuoteWorkflowStatuses(){
  return getQuoteWorkflowStatusesForMode(quoteWorkspaceMode);
}
function getDefaultQuoteWorkflowStatus(){
  return quoteWorkspaceMode==='pkp' ? 'Составить ПКП' : 'Составить КП';
}
function getUnifiedQuoteKanbanColumns(){
  return getQuoteWorkflowStatusesForMode('pkp').map(function(status){
    return {mode:'pkp', status:status};
  }).concat(getQuoteWorkflowStatusesForMode('kp').map(function(status){
    return {mode:'kp', status:status};
  }));
}
function getQuoteKanbanColumnKey(mode,status){
  return kpNormalizeQuoteMode(mode)+'::'+kpCanonicalWorkflowStatus(status, mode);
}
function kpFindQuoteRow(id, mode){
  mode=kpNormalizeQuoteMode(mode);
  return (kpQuotes||[]).find(function(q){
    return String(q.id)===String(id) && kpNormalizeQuoteMode(q.quote_mode||'kp')===mode;
  })||null;
}
function updateQuoteWorkspaceUi(){
  var listTitle=document.querySelector('#page-kp-list .pt');
  if(listTitle) listTitle.innerHTML='<span class="ic">📑</span>'+(quoteWorkspaceMode==='pkp'?'ПКП':'Коммерческие предложения');
  var builderTitle=document.querySelector('#page-kp-builder .pt');
  if(builderTitle) builderTitle.innerHTML='<span class="ic">🧾</span>Составление '+getQuoteWorkspaceTitle();
  var saveBtn=document.querySelector('#page-kp-builder .btn.btn-gr[onclick=\"saveKpQuote()\"]');
  if(saveBtn) saveBtn.textContent='💾 Сохранить '+getQuoteWorkspaceTitle();
  ensureKpBuilderDocButtons();
  syncKpBuilderAccessUi();
}
function ensureKpBuilderDocButtons(){
  var actions=document.querySelector('#page-kp-builder .ph .pa');
  if(!actions) return;
  if(!document.getElementById('kp-builder-preview-btn')){
    var previewBtn=document.createElement('button');
    previewBtn.id='kp-builder-preview-btn';
    previewBtn.className='btn btn-cy';
    previewBtn.type='button';
    previewBtn.textContent='👁 Предпросмотр';
    previewBtn.onclick=previewKpQuoteDoc;
    var saveBtn=actions.querySelector('.btn.btn-gr[onclick="saveKpQuote()"]');
    actions.insertBefore(previewBtn, saveBtn||null);
  }
  if(!document.getElementById('kp-client-choice-mode-wrap')){
    var choiceWrap=document.createElement('label');
    choiceWrap.id='kp-client-choice-mode-wrap';
    choiceWrap.className='btn btn-cy kp-client-choice-mode';
    var choiceLabel=document.createElement('span');
    choiceLabel.textContent='Выбор клиента';
    var choiceSelect=document.createElement('select');
    choiceSelect.id='kp-client-choice-mode-select';
    choiceSelect.className='finp';
    choiceSelect.innerHTML='<option value="variant">По одному варианту</option><option value="type">Целый тип</option>';
    choiceSelect.onchange=function(){kpSetClientSelectionMode(this.value);};
    choiceWrap.appendChild(choiceLabel);
    choiceWrap.appendChild(choiceSelect);
    var printAnchor=document.getElementById('kp-builder-print-wrap');
    if(printAnchor) actions.insertBefore(choiceWrap, printAnchor);
    else {
      var saveBtnChoice=actions.querySelector('.btn.btn-gr[onclick="saveKpQuote()"]');
      actions.insertBefore(choiceWrap, saveBtnChoice||null);
    }
  }
  kpSyncClientChoiceModeControl();
  if(!document.getElementById('kp-builder-print-wrap')){
    var printWrap=document.createElement('div');
    printWrap.id='kp-builder-print-wrap';
    printWrap.className='kp-print-menu-wrap';
    var printBtn=document.createElement('button');
    printBtn.id='kp-builder-print-btn';
    printBtn.className='btn btn-cy';
    printBtn.type='button';
    printBtn.textContent='🖨️ Печать';
    printBtn.onclick=printKpQuoteDoc;
    var menu=document.createElement('div');
    menu.id='kp-builder-print-menu';
    menu.className='kp-print-menu';
    menu.style.display='none';
    printWrap.appendChild(printBtn);
    printWrap.appendChild(menu);
    var saveBtn2=actions.querySelector('.btn.btn-gr[onclick="saveKpQuote()"]');
    actions.insertBefore(printWrap, saveBtn2||null);
  }
}
function kpSyncClientChoiceModeControl(){
  var select=document.getElementById('kp-client-choice-mode-select');
  if(!select || typeof kpGetClientSelectionMode!=='function') return;
  select.value=kpGetClientSelectionMode();
}
function canWriteCurrentQuoteBuilder(){
  var existingId=parseInt((kpBuilder&&kpBuilder.id)||0,10)||0;
  return existingId ? accessCanUi('kp','edit') : accessCanUi('kp','create');
}
function syncKpBuilderAccessUi(){
  var canWrite=canWriteCurrentQuoteBuilder();
  var saveBtn=document.getElementById('kp-builder-save-btn');
  if(saveBtn) saveBtn.style.display=canWrite?'':'none';
  var addClientBtn=document.getElementById('kp-builder-add-client-btn');
  if(addClientBtn) addClientBtn.style.display=canWrite?'':'none';
  var addVariantBtn=document.getElementById('kp-builder-add-variant-btn');
  if(addVariantBtn) addVariantBtn.style.display=canWrite?'':'none';
  var addTypeBtn=document.getElementById('kp-builder-add-type-btn');
  if(addTypeBtn) addTypeBtn.style.display=canWrite?'':'none';
  (document.querySelectorAll ? document.querySelectorAll('[data-kp-add-cat-btn]') : []).forEach(function(btn){
    btn.style.display=canWrite?'':'none';
  });
}
function openQuoteWorkspace(mode, section){
  var nextMode=mode==='pkp' ? 'pkp' : 'kp';
  if(quoteWorkspaceMode!==nextMode){
    kpCatalogProducts=[]; kpCatalogServices=[]; kpCatalogSections=[]; kpQuotes=[];
  }
  quoteWorkspaceMode=nextMode;
  updateQuoteWorkspaceUi();
  if(!accessSpaceVisibleUi('kp')) return showPage('home');
  showSpace('doc');
  if(section==='builder') section='list';
  return showPage(getFirstVisibleQuoteWorkspacePage(quoteWorkspaceMode, section||'list'));
}
function showPkpPresets(){
  if(quoteWorkspaceMode!=='pkp'){
    kpCatalogProducts=[]; kpCatalogServices=[]; kpCatalogSections=[]; kpQuotes=[];
  }
  quoteWorkspaceMode='pkp';
  updateQuoteWorkspaceUi();
  if(!accessSpaceVisibleUi('kp')) return showPage('home');
  showSpace('doc');
  showPage(getFirstVisibleQuoteWorkspacePage('pkp','presets'));
}

function kpStatusLabel(status){
  var map={created:'Создано',sent:'Отправлено',viewed:'Просмотрено',chosen:'Выбран вариант',rejected:'Отказ',completed:'Выполнено'};
  return map[status]||status;
}

function kpVariantDefaultLabel(idx){
  var defs=['Бюджетный','Оптимальный','Премиальный','Вариант 4','Вариант 5','Вариант 6'];
  return defs[idx]||('Вариант '+(idx+1));
}

function kpProposalTypeDefaultLabel(idx){
  return idx===0 ? 'Основное предложение' : ('Тип предложения '+(idx+1));
}

function kpMakeProposalNodeId(prefix, fallback){
  return prefix+'-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,8)+'-'+String(fallback||0);
}

function kpEmptyVariant(idx){
  return {id:kpMakeProposalNodeId('var',idx),label:kpVariantDefaultLabel(idx),vat_mode:'none',items:[],cats:[],add_state:{category_code:'equipment',section_id:'',object_id:''}};
}

function kpEmptyProposalType(idx){
  return {
    id:kpMakeProposalNodeId('ptype',idx),
    label:kpProposalTypeDefaultLabel(idx),
    selected_variant_id:'',
    variants:[kpEmptyVariant(0)]
  };
}
function kpNormalizeClientSelectionMode(mode){
  return String(mode||'').trim()==='type' ? 'type' : 'variant';
}
function kpGetClientSelectionMode(){
  var payload=kpBuilder&&kpBuilder.payload&&typeof kpBuilder.payload==='object'?kpBuilder.payload:{};
  return kpNormalizeClientSelectionMode(payload.selection_mode||payload.client_selection_mode);
}
function kpSetClientSelectionMode(mode){
  if(!kpBuilder.payload || typeof kpBuilder.payload!=='object') kpBuilder.payload={};
  kpBuilder.payload.selection_mode=kpNormalizeClientSelectionMode(mode);
  renderKpVariants();
}
function kpShouldMarkExternalTouched(){
  return !!(CU && parseInt(kpBuilder.owner_user_id||0,10)>0 && parseInt(kpBuilder.owner_user_id||0,10)!==parseInt(CU.id||0,10));
}
function kpMarkExternalTouched(item){
  if(item && kpShouldMarkExternalTouched() && !kpIsPendingCatalogItem(item)) item.external_touched=true;
}

function kpNormalizeProposalVariant(variant, idx, legacyVatMode){
  variant=variant&&typeof variant==='object'?variant:{};
  return {
    id:String(variant.id||('var-'+idx)),
    label:variant.label||kpVariantDefaultLabel(idx),
    vat_mode:variant.vat_mode||legacyVatMode||'none',
    items:Array.isArray(variant.items)?variant.items:[],
    cats:Array.isArray(variant.cats)?variant.cats:(Array.isArray(variant.snapshot)?variant.snapshot:[]),
    add_state:(variant.add_state&&typeof variant.add_state==='object')?variant.add_state:{category_code:'equipment',section_id:'',object_id:''}
  };
}

function kpNormalizeProposalType(type, idx, legacyVatMode){
  type=type&&typeof type==='object'?type:{};
  var rawVariants=Array.isArray(type.variants)&&type.variants.length ? type.variants : [kpEmptyVariant(0)];
  var variants=rawVariants.map(function(variant, vi){
    return kpNormalizeProposalVariant(variant, vi, legacyVatMode);
  });
  var selectedVariantId=String(type.selected_variant_id||'').trim();
  if(selectedVariantId && !variants.some(function(variant){ return String(variant.id||'')===selectedVariantId; })){
    selectedVariantId='';
  }
  return {
    id:String(type.id||('ptype-'+idx)),
    label:type.label||kpProposalTypeDefaultLabel(idx),
    selected_variant_id:selectedVariantId,
    variants:variants
  };
}

function kpGetLegacyVariantsFromState(state){
  if(Array.isArray(state.variants) && state.variants.length) return state.variants;
  var payload=state.payload&&typeof state.payload==='object'?state.payload:{};
  if(Array.isArray(payload.variants) && payload.variants.length) return payload.variants;
  return [];
}

function kpBuildProposalTypesFallback(state){
  if(Array.isArray(state.proposal_types) && state.proposal_types.length) return state.proposal_types;
  var payload=state.payload&&typeof state.payload==='object'?state.payload:{};
  if(Array.isArray(payload.proposal_types) && payload.proposal_types.length) return payload.proposal_types;
  return [{
    id:'ptype-default',
    label:'Основное предложение',
    selected_variant_id:'',
    variants:kpGetLegacyVariantsFromState(state)
  }];
}

function kpSyncBuilderActiveTypeVariants(state){
  state=state||kpBuilder;
  if(!state || !Array.isArray(state.proposal_types) || !state.proposal_types.length){
    state.proposal_types=[kpEmptyProposalType(0)];
  }
  if(typeof state.active_type_index!=='number' || !isFinite(state.active_type_index)){
    state.active_type_index=0;
  }
  state.active_type_index=Math.max(0, Math.min(state.active_type_index, state.proposal_types.length-1));
  var activeType=state.proposal_types[state.active_type_index]||kpEmptyProposalType(state.active_type_index);
  if(!Array.isArray(activeType.variants) || !activeType.variants.length){
    activeType.variants=[kpEmptyVariant(0)];
  }
  if(typeof state.active_variant_index!=='number' || !isFinite(state.active_variant_index)){
    state.active_variant_index=0;
  }
  state.active_variant_index=Math.max(0, Math.min(state.active_variant_index, activeType.variants.length-1));
  state.proposal_types[state.active_type_index]=activeType;
  state.variants=activeType.variants;
  return activeType;
}

function kpEnsureProposalTypesOnState(state){
  state=state||kpBuilder;
  var payload=state.payload&&typeof state.payload==='object'?state.payload:{};
  var legacyVatMode=payload.vat_mode||'none';
  state.proposal_types=kpBuildProposalTypesFallback(state).map(function(type, idx){
    return kpNormalizeProposalType(type, idx, legacyVatMode);
  });
  if(!state.proposal_types.length) state.proposal_types=[kpEmptyProposalType(0)];
  kpSyncBuilderActiveTypeVariants(state);
}

function kpCurrentProposalType(){
  kpEnsureProposalTypesOnState(kpBuilder);
  return kpBuilder.proposal_types[kpBuilder.active_type_index]||null;
}

function kpGetPayloadProposalTypes(payload){
  payload=payload&&typeof payload==='object'?payload:{};
  var legacyVatMode=payload.vat_mode||'none';
  return kpBuildProposalTypesFallback({payload:payload,variants:[]}).map(function(type, idx){
    return kpNormalizeProposalType(type, idx, legacyVatMode);
  });
}

function kpGetProposalTypeChosenVariant(type){
  type=type&&typeof type==='object'?type:{};
  var variants=Array.isArray(type.variants)?type.variants:[];
  var chosenId=String(type.selected_variant_id||'').trim();
  if(!chosenId) return null;
  return variants.find(function(variant){ return String(variant.id||'')===chosenId; })||null;
}

function ensureKpVariants(){
  kpEnsureProposalTypesOnState(kpBuilder);
  var legacyVatMode=(kpBuilder.payload&&kpBuilder.payload.vat_mode)||'none';
  kpBuilder.variants.forEach(function(variant, idx){
    if(!variant || typeof variant!=='object') return;
    if(!variant.id) variant.id='var-'+idx;
    if(!variant.label) variant.label=kpVariantDefaultLabel(idx);
    if(!variant.vat_mode) variant.vat_mode=legacyVatMode;
    if(!variant.add_state || typeof variant.add_state!=='object'){
      variant.add_state={category_code:'equipment',section_id:'',object_id:''};
    }
  });
  if(typeof kpBuilder.active_variant_index!=='number' || !isFinite(kpBuilder.active_variant_index)){
    kpBuilder.active_variant_index=0;
  }
  kpBuilder.active_variant_index=Math.max(0, Math.min(kpBuilder.active_variant_index, kpBuilder.variants.length-1));
  kpSyncBuilderActiveTypeVariants(kpBuilder);
}

function setActiveKpProposalType(ti){
  kpEnsureProposalTypesOnState(kpBuilder);
  kpBuilder.active_type_index=Math.max(0, Math.min(parseInt(ti,10)||0, kpBuilder.proposal_types.length-1));
  kpBuilder.active_variant_index=0;
  kpSyncBuilderActiveTypeVariants(kpBuilder);
  renderKpVariants();
}

function addKpProposalType(){
  kpEnsureProposalTypesOnState(kpBuilder);
  kpBuilder.proposal_types.push(kpEmptyProposalType(kpBuilder.proposal_types.length));
  kpBuilder.active_type_index=kpBuilder.proposal_types.length-1;
  kpBuilder.active_variant_index=0;
  kpSyncBuilderActiveTypeVariants(kpBuilder);
  renderKpVariants();
}

function removeKpProposalType(ti){
  kpEnsureProposalTypesOnState(kpBuilder);
  if((kpBuilder.proposal_types||[]).length<=1) return;
  kpBuilder.proposal_types.splice(ti,1);
  kpBuilder.active_type_index=Math.max(0, Math.min(kpBuilder.active_type_index, kpBuilder.proposal_types.length-1));
  kpBuilder.active_variant_index=0;
  kpSyncBuilderActiveTypeVariants(kpBuilder);
  renderKpVariants();
}

function setActiveKpVariant(vi){
  ensureKpVariants();
  kpBuilder.active_variant_index=Math.max(0, Math.min(parseInt(vi,10)||0, kpBuilder.variants.length-1));
  renderKpVariants();
}

function kpBuilderCategoryLabel(code){
  var map={equipment:'Оборудование',materials:'Материалы',work:'Работы',construction_works:'Строительные работы',incidental_expenses:(quoteWorkspaceMode==='pkp'?'Накладные расходы':'Сопутствующие расходы'),maintenance:'Обслуживание',kits:'Комплекты'};
  return map[code]||code;
}

function kpVisibleBuilderCategories(){
  var rows=['equipment','materials','work','construction_works','incidental_expenses','maintenance'];
  if(quoteWorkspaceMode==='pkp') rows.push('kits');
  return rows;
}

function addKpVariant(){
  ensureKpVariants();
  kpBuilder.variants.push(kpEmptyVariant(kpBuilder.variants.length));
  kpBuilder.active_variant_index=kpBuilder.variants.length-1;
  kpSyncBuilderActiveTypeVariants(kpBuilder);
  renderKpVariants();
}

function copyKpVariant(vi){
  ensureKpVariants();
  var src=kpBuilder.variants[vi];
  if(!src) return;
  var clone=JSON.parse(JSON.stringify(src));
  clone.id=kpMakeProposalNodeId('var',vi+1);
  clone.label=(src.label||('Вариант '+(vi+1)))+' копия';
  clone.add_state={category_code:'equipment',section_id:'',object_id:''};
  kpBuilder.variants.splice(vi+1,0,clone);
  kpBuilder.active_variant_index=vi+1;
  kpSyncBuilderActiveTypeVariants(kpBuilder);
  renderKpVariants();
}

function removeKpVariant(vi){
  if((kpBuilder.variants||[]).length<=1) return;
  var removed=kpBuilder.variants[vi]||null;
  kpBuilder.variants.splice(vi,1);
  var activeType=kpCurrentProposalType();
  if(activeType && removed && String(activeType.selected_variant_id||'')===String(removed.id||'')){
    activeType.selected_variant_id='';
  }
  kpBuilder.active_variant_index=Math.max(0, Math.min(kpBuilder.active_variant_index, kpBuilder.variants.length-1));
  kpSyncBuilderActiveTypeVariants(kpBuilder);
  renderKpVariants();
}

function setKpCatalogMode(mode){
  kpCatalogMode=mode;
  document.getElementById('kp-cat-tab-products').classList.toggle('active',mode==='products');
  document.getElementById('kp-cat-tab-services').classList.toggle('active',mode==='services');
  document.getElementById('kp-catalog-products-view').style.display=mode==='products'?'block':'none';
  document.getElementById('kp-catalog-services-view').style.display=mode==='services'?'block':'none';
}

async function loadKpCatalog(){
  var mode=kpNormalizeQuoteMode(quoteWorkspaceMode||'kp');
  if(!kpReferenceCache.catalog || typeof kpReferenceCache.catalog!=='object') kpReferenceCache.catalog={};
  var modeCache=kpReferenceCache.catalog[mode]||null;
  if(modeCache){
    var cached=await modeCache;
    kpCatalogProducts=(cached&&cached.products)||[];
    kpCatalogServices=(cached&&cached.services)||[];
    kpCatalogSections=(cached&&cached.sections)||[];
    renderKpCatalog();
    fillKpCatalogSelects();
    return cached;
  }
  if(kpCatalogProducts.length && kpCatalogServices.length && kpCatalogSections.length){
    renderKpCatalog();
    fillKpCatalogSelects();
    return Promise.resolve({
      products:kpCatalogProducts,
      services:kpCatalogServices,
      sections:kpCatalogSections
    });
  }
  kpReferenceCache.catalog[mode]=(async function(){
    var data=await Promise.all([
      kpApiGet('catalog_products'),
      kpApiGet('catalog_services'),
      kpApiGet('catalog_sections')
    ]);
    kpCatalogProducts=data[0]||[];
    kpCatalogServices=data[1]||[];
    kpCatalogSections=data[2]||[];
    var partCache=getKpCatalogModeCache();
    partCache.products=Promise.resolve(kpCatalogProducts);
    partCache.services=Promise.resolve(kpCatalogServices);
    partCache.sections=Promise.resolve(kpCatalogSections);
    renderKpCatalog();
    fillKpCatalogSelects();
    return {
      products:kpCatalogProducts,
      services:kpCatalogServices,
      sections:kpCatalogSections
    };
  })();
  try{
    return await kpReferenceCache.catalog[mode];
  }catch(e){
    kpReferenceCache.catalog[mode]=null;
    toast(e.message,'err');
  }
}

function getKpCatalogModeCache(){
  var mode=kpNormalizeQuoteMode(quoteWorkspaceMode||'kp');
  if(!kpReferenceCache.catalog || typeof kpReferenceCache.catalog!=='object') kpReferenceCache.catalog={};
  if(!kpReferenceCache.catalog.__parts || typeof kpReferenceCache.catalog.__parts!=='object') kpReferenceCache.catalog.__parts={};
  if(!kpReferenceCache.catalog.__parts[mode]) kpReferenceCache.catalog.__parts[mode]={};
  return kpReferenceCache.catalog.__parts[mode];
}

async function loadKpCatalogSections(){
  if(kpCatalogSections.length) return kpCatalogSections;
  var cache=getKpCatalogModeCache();
  if(!cache.sections){
    cache.sections=kpApiGet('catalog_sections').then(function(rows){
      kpCatalogSections=Array.isArray(rows)?rows:[];
      return kpCatalogSections;
    }).catch(function(e){
      cache.sections=null;
      throw e;
    });
  }
  return cache.sections;
}

async function loadKpCatalogServices(){
  if(kpCatalogServices.length) return kpCatalogServices;
  var cache=getKpCatalogModeCache();
  if(!cache.services){
    cache.services=kpApiGet('catalog_services').then(function(rows){
      kpCatalogServices=Array.isArray(rows)?rows:[];
      return kpCatalogServices;
    }).catch(function(e){
      cache.services=null;
      throw e;
    });
  }
  return cache.services;
}

async function loadKpCatalogProducts(){
  if(kpCatalogProducts.length) return kpCatalogProducts;
  var cache=getKpCatalogModeCache();
  if(!cache.products){
    cache.products=kpApiGet('catalog_products').then(function(rows){
      kpCatalogProducts=Array.isArray(rows)?rows:[];
      return kpCatalogProducts;
    }).catch(function(e){
      cache.products=null;
      throw e;
    });
  }
  return cache.products;
}

function invalidateKpCatalogCache(mode){
  if(!kpReferenceCache) return;
  if(!kpReferenceCache.catalog || typeof kpReferenceCache.catalog!=='object'){
    kpReferenceCache.catalog={};
    return;
  }
  if(mode){
    kpReferenceCache.catalog[kpNormalizeQuoteMode(mode)]=null;
    if(kpReferenceCache.catalog.__parts) kpReferenceCache.catalog.__parts[kpNormalizeQuoteMode(mode)]=null;
  }else{
    kpReferenceCache.catalog={};
  }
}

async function reloadKpCatalog(){
  invalidateKpCatalogCache(quoteWorkspaceMode);
  kpCatalogProducts=[];
  kpCatalogServices=[];
  kpCatalogSections=[];
  return loadKpCatalog();
}

async function refreshKpCatalogItems(){
  var mode=kpNormalizeQuoteMode(quoteWorkspaceMode||'kp');
  var cache=getKpCatalogModeCache();
  if(kpReferenceCache && kpReferenceCache.catalog){
    kpReferenceCache.catalog[mode]=null;
  }
  cache.products=null;
  cache.services=null;
  kpCatalogProducts=[];
  kpCatalogServices=[];
  await Promise.all([
    loadKpCatalogProducts(),
    loadKpCatalogServices()
  ]);
  renderKpCatalog();
  fillKpCatalogSelects();
  return {
    products:kpCatalogProducts,
    services:kpCatalogServices,
    sections:kpCatalogSections
  };
}

function syncKpSectionFilter(){
  var sel=document.getElementById('kp-sec-filter');
  if(!sel) return;
  var current=sel.value||'';
  var cat=document.getElementById('kp-cat-filter')?document.getElementById('kp-cat-filter').value:'';
  var items=kpCatalogSections.filter(function(s){return !cat || s.category_code===cat;});
  sel.innerHTML='<option value="">Все разделы</option>'+items.map(function(s){return '<option value="'+s.id+'">'+esc(s.name)+'</option>';}).join('');
  if(current && items.find(function(s){return String(s.id)===String(current);})){sel.value=current;}
}

function getKpSectionCategoryCode(sectionId){
  var sec=kpCatalogSections.find(function(x){return String(x.id)===String(sectionId||'');});
  return sec ? (sec.category_code||'') : '';
}

function getKpSectionMeta(sectionId){
  return kpCatalogSections.find(function(x){return String(x.id)===String(sectionId||'');})||null;
}

function updateKpProductNoteField(){
  var field=document.getElementById('kpp-note-field');
  if(field) field.style.display='';
}

function refreshKpProductServiceSelect(selectedId){
  var serviceSel=document.getElementById('kpp-service');
  if(!serviceSel) return;
  var categoryCode=getKpSectionCategoryCode(document.getElementById('kpp-section').value||'');
  serviceSel.innerHTML='<option value="">— не привязана —</option>'+kpCatalogServices.filter(function(s){
    return true;
  }).map(function(s){
    return '<option value="'+s.id+'">'+esc(s.name)+(s.marking_size?' / '+esc(s.marking_size):'')+(s.retail_price?' / '+esc(s.retail_price):'')+'</option>';
  }).join('');
  serviceSel.value=selectedId?String(selectedId):'';
  if(selectedId && serviceSel.value!==String(selectedId)){
    serviceSel.value='';
  }
  updateKpProductNoteField();
}

function fillKpCatalogSelects(){
  var secSel=document.getElementById('kpp-section');
  if(secSel){
    secSel.innerHTML=kpCatalogSections.map(function(s){
      return '<option value="'+s.id+'">'+esc(s.category_name)+' → '+esc(s.name)+'</option>';
    }).join('');
  }
  refreshKpProductGroups(document.getElementById('kpp-group') ? document.getElementById('kpp-group').value : '');
  var unitSel=document.getElementById('kpp-unit');
  if(unitSel){
    unitSel.innerHTML=(UNITS||[]).map(function(u){return '<option value="'+esc(u)+'">'+esc(u)+'</option>';}).join('');
  }
  var kpsUnit=document.getElementById('kps-unit');
  if(kpsUnit){
    kpsUnit.innerHTML=(UNITS||[]).map(function(u){return '<option value="'+esc(u)+'">'+esc(u)+'</option>';}).join('');
  }
  var seUnit=document.getElementById('se-unit');
  if(seUnit){
    seUnit.innerHTML=(UNITS||[]).map(function(u){return '<option value="'+esc(u)+'">'+esc(u)+'</option>';}).join('');
  }
  refreshKpProductServiceSelect(document.getElementById('kpp-service') ? document.getElementById('kpp-service').value : '');
}

function openKpProductModal(id){
  document.getElementById('kpp-id').value=id||'';
  fillKpCatalogSelects();
  var title=document.getElementById('m-kp-product-title');
  if(!id){
    title.textContent='➕ Товар';
    ['kpp-id','kpp-name','kpp-marking','kpp-note','kpp-supplier','kpp-purchase','kpp-minimal','kpp-retail'].forEach(function(id){document.getElementById(id).value='';});
    if(document.getElementById('kpp-section').options.length) document.getElementById('kpp-section').selectedIndex=0;
    refreshKpProductGroups('');
    if(document.getElementById('kpp-unit').options.length) document.getElementById('kpp-unit').value=getDefaultUnit();
    document.getElementById('kpp-service').value='';
    om('m-kp-product');
    return;
  }
  var p=kpCatalogProducts.find(function(x){return x.id==id;}); if(!p) return;
  title.textContent='✏️ Товар';
  document.getElementById('kpp-id').value=p.id;
  document.getElementById('kpp-name').value=p.name||'';
  document.getElementById('kpp-section').value=p.section_id||'';
  refreshKpProductGroups(p.group_name||'');
  refreshKpProductServiceSelect(p.linked_service_id||'');
  document.getElementById('kpp-marking').value=p.marking_size||'';
  document.getElementById('kpp-note').value=p.note||'';
  document.getElementById('kpp-unit').value=p.unit||getDefaultUnit();
  document.getElementById('kpp-supplier').value=p.supplier||'';
  document.getElementById('kpp-purchase').value=p.purchase_price!=null?p.purchase_price:'';
  document.getElementById('kpp-minimal').value=p.minimal_price!=null?p.minimal_price:'';
  document.getElementById('kpp-retail').value=p.retail_price!=null?p.retail_price:'';
  om('m-kp-product');
}

