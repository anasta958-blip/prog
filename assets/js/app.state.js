// ===================== STATE =====================
var CU=null, CSRF_TOKEN='', allCats=[], allSecs=[], allGroups=[], catalogNames=[];
var nextOrderNum='', debTimers={};
var gcProducts=[], orderList=[];
var ordersView='kanban';
var docCats=[], oeCats=[], oeOrderId=null, oeOwnerUserId=0;
var pCatTarget=null, pSecCatIdx=null, pSecTarget=null, pGroupTarget=null, pGroupCatIdx=null, pGroupSecIdx=null;
var oeFilterSup='', oeFilterShip='';
var allNamesCache=null; // cache for autocomplete
var DEFAULT_UNIT='';
var generalCatalogMode='equipment';
var workServices=[];
var linkableCatalogItems=[];
var serviceOptionsCache=[], serviceOptionsCacheCategory='';
var NOTE_EQUIPMENT_SECTION_CODES=['ventilation','conditioning','avtomatika','uvlazhnenie'];
var quoteWorkspaceMode='kp';
var kpCatalogMode='products';
var kpCatalogProducts=[], kpCatalogServices=[], kpCatalogSections=[];
var kpCompany=null, kpCompanies=[], kpClients=[], kpContractors=[], kpQuotes=[], kpTransferUsers=[], kpBuilderUsers=[];
var kpReferenceCache={catalog:null,company:null,clients:null,contractors:null};
var kpVariantSummaryCache={};
var kpBuilder={id:0,title:'',status:'created',workflow_status:'',client_id:'',owner_user_id:0,active_type_index:0,active_variant_index:0,proposal_types:[],variants:[]};
var kpBoardScrollMemory={mode:'quotes-board',main:0,grid:0,pendingRestore:false};
var pkpPresets=[], pkpPresetDraft={id:0,name:'',items:[]};
var pkpPresetApplyState={variantIndex:0};

function getDefaultUnit(){
  return DEFAULT_UNIT || UNITS[0] || '';
}

function shouldShowEquipmentNoteField(categoryCode, sectionCode){
  return true;
}

function catalogGroupNorm(v){
  return String(v==null?'':v).trim();
}

function catalogGroupToken(v){
  var normalized=catalogGroupNorm(v);
  return normalized==='' ? '__EMPTY__' : normalized;
}

function getSectionGroupOptions(sectionId){
  var seen={}, out=[];
  (allGroups||[]).forEach(function(row){
    if(String(row.section_id||'')!==String(sectionId||'')) return;
    var key=catalogGroupNorm(row.name||'');
    if(seen[key]) return;
    seen[key]=true;
    out.push(key);
  });
  out.sort(function(a,b){ return a.localeCompare(b,'ru'); });
  return out;
}

function fillGroupDatalist(listId, values){
  var list=document.getElementById(listId);
  if(!list) return;
  list.innerHTML=(values||[]).filter(function(v){return catalogGroupNorm(v)!=='';}).map(function(v){
    return '<option value="'+esc(v)+'"></option>';
  }).join('');
}

function fillGroupSelect(selectId, values, selected){
  var select=document.getElementById(selectId);
  if(!select) return;
  var nextSelected=selected!=null ? String(selected) : '';
  var html=['<option value="">— без группы —</option>'];
  (values||[]).filter(function(v){ return catalogGroupNorm(v)!==''; }).forEach(function(v){
    var value=String(v);
    html.push('<option value="'+esc(value)+'"'+(value===nextSelected?' selected':'')+'>'+esc(value)+'</option>');
  });
  select.innerHTML=html.join('');
  select.value=nextSelected;
}

function refreshNameEditGroups(selected){
  var sec=document.getElementById('ne-sec');
  var inp=document.getElementById('ne-group');
  if(!sec || !inp) return;
  var options=getSectionGroupOptions(sec.value||'');
  fillGroupSelect('ne-group', options, selected);
}

function refreshKpProductGroups(selected){
  var sec=document.getElementById('kpp-section');
  var inp=document.getElementById('kpp-group');
  if(!sec || !inp) return;
  var options=getSectionGroupOptions(sec.value||'');
  fillGroupDatalist('kpp-group-list', options);
  inp.value=selected!=null ? String(selected) : '';
}

