var orderBuilderDraftBaselines={create:'',edit:''};
var orderBuilderDraftSaveTimer=0;

function orderBuilderDraftStorageKey(kind,id){
  var userId=parseInt((CU&&CU.id)||0,10)||0;
  return 'order_builder_draft_v1_'+userId+'_'+(kind==='edit'?'edit':'create')+'_'+(parseInt(id||0,10)||0);
}

function orderBuilderDraftState(kind){
  var isEdit=kind==='edit';
  return {
    id:isEdit?(parseInt((document.getElementById('oe-id')||{}).value||0,10)||0):0,
    address:String((document.getElementById(isEdit?'oe-addr':'doc-addr')||{}).value||''),
    order_type:String((document.getElementById(isEdit?'oe-type':'doc-type')||{}).value||''),
    client_type:String((document.getElementById(isEdit?'oe-client-type':'doc-num')||{}).value||''),
    status_order:isEdit?String((document.getElementById('oe-status')||{}).value||''):'',
    order_number:isEdit?String((document.getElementById('oe-num')||{}).value||''):'',
    cats:JSON.parse(JSON.stringify(isEdit?oeCats:docCats))
  };
}

function orderBuilderDraftSignature(kind){
  try{return JSON.stringify(orderBuilderDraftState(kind));}catch(e){return '';}
}

function initializeOrderBuilderDraftTracking(kind,signature){
  orderBuilderDraftBaselines[kind]=typeof signature==='string'?signature:orderBuilderDraftSignature(kind);
}

function orderBuilderHasUnsavedChanges(kind){
  var expectedPage=kind==='edit'?'order-edit':'doc';
  return activePage===expectedPage && !!orderBuilderDraftBaselines[kind] && orderBuilderDraftSignature(kind)!==orderBuilderDraftBaselines[kind];
}

function saveOrderBuilderDraft(kind){
  if(!orderBuilderHasUnsavedChanges(kind)) return;
  try{
    var state=orderBuilderDraftState(kind);
    localStorage.setItem(orderBuilderDraftStorageKey(kind,state.id),JSON.stringify({
      saved_at:Date.now(),
      base_signature:orderBuilderDraftBaselines[kind],
      state:state
    }));
  }catch(e){}
}

function clearOrderBuilderDraft(kind,id){
  try{localStorage.removeItem(orderBuilderDraftStorageKey(kind,id||0));}catch(e){}
}

function applyOrderBuilderDraftState(kind,state){
  state=state||{};
  var isEdit=kind==='edit';
  var addr=document.getElementById(isEdit?'oe-addr':'doc-addr');
  var type=document.getElementById(isEdit?'oe-type':'doc-type');
  var client=document.getElementById(isEdit?'oe-client-type':'doc-num');
  if(addr) addr.value=state.address||'';
  if(type) type.value=state.order_type||'';
  if(client) client.value=state.client_type||'';
  if(isEdit){
    var status=document.getElementById('oe-status');
    var number=document.getElementById('oe-num');
    if(status && state.status_order && [].some.call(status.options,function(option){return option.value===state.status_order;})) status.value=state.status_order;
    if(number) number.value=state.order_number||number.value;
    oeCats=Array.isArray(state.cats)?JSON.parse(JSON.stringify(state.cats)):[];
  }else{
    docCats=Array.isArray(state.cats)?JSON.parse(JSON.stringify(state.cats)):[];
  }
}

function restoreOrderBuilderDraft(kind,id){
  try{
    var raw=localStorage.getItem(orderBuilderDraftStorageKey(kind,id||0));
    if(!raw) return false;
    var parsed=JSON.parse(raw);
    if(!parsed || !parsed.state) return false;
    applyOrderBuilderDraftState(kind,parsed.state);
    initializeOrderBuilderDraftTracking(kind,parsed.base_signature||'');
    return true;
  }catch(e){return false;}
}

function prepareNewOrderBuilder(){
  docCats=[];
  ['doc-addr','doc-type','doc-num'].forEach(function(id){
    var el=document.getElementById(id);
    if(el) el.value='';
  });
  initializeOrderBuilderDraftTracking('create');
  restoreOrderBuilderDraft('create',0);
  renderDocBuilder();
}

function scheduleOrderBuilderDraftSave(kind){
  var expectedPage=kind==='edit'?'order-edit':'doc';
  if(activePage!==expectedPage) return;
  clearTimeout(orderBuilderDraftSaveTimer);
  orderBuilderDraftSaveTimer=setTimeout(function(){saveOrderBuilderDraft(kind);},120);
}

async function confirmOrderBuilderLeave(kind){
  if(!orderBuilderHasUnsavedChanges(kind)) return true;
  saveOrderBuilderDraft(kind);
  var keep=await showConfirmDialog({
    title:'Несохранённые изменения',
    message:'Внесённые изменения не сохранены, сохранить локально для дальнейшей работы?',
    icon:'💾',
    confirmText:'Сохранить',
    confirmClass:'btn-p',
    cancelText:'Нет',
    dismissible:false
  });
  if(!keep){
    var state=orderBuilderDraftState(kind);
    clearOrderBuilderDraft(kind,state.id||0);
  }
  return true;
}

function updateOrderBuilderDraftBaselineField(kind,field,value){
  try{
    var baseline=JSON.parse(orderBuilderDraftBaselines[kind]||'{}');
    baseline[field]=value;
    orderBuilderDraftBaselines[kind]=JSON.stringify(baseline);
    saveOrderBuilderDraft(kind);
  }catch(e){}
}

document.addEventListener('input',function(e){
  if(e.target&&e.target.closest&&e.target.closest('#page-doc')) scheduleOrderBuilderDraftSave('create');
  if(e.target&&e.target.closest&&e.target.closest('#page-order-edit')) scheduleOrderBuilderDraftSave('edit');
});
document.addEventListener('change',function(e){
  if(e.target&&e.target.closest&&e.target.closest('#page-doc')) scheduleOrderBuilderDraftSave('create');
  if(e.target&&e.target.closest&&e.target.closest('#page-order-edit')) scheduleOrderBuilderDraftSave('edit');
});
document.addEventListener('click',function(e){
  if(e.target&&e.target.closest&&e.target.closest('#page-doc')) scheduleOrderBuilderDraftSave('create');
  if(e.target&&e.target.closest&&e.target.closest('#page-order-edit')) scheduleOrderBuilderDraftSave('edit');
});
