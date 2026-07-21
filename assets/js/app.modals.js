// ===================== MODALS =====================
function om(id){document.getElementById(id).classList.add('open');}
function cm(id){document.getElementById(id).classList.remove('open');}
var _nativeSelectOverlayLockUntil=0;
window.addEventListener('click',function(e){
  if(e.target.closest && e.target.closest('.ac-drop')) return;
  if(isAutocompleteTransitionActive()) return;
  if(Date.now()<_nativeSelectOverlayLockUntil) return;
  if(e.target.classList.contains('overlay')){
    if(e.target.id==='m-confirm-delete'){
      if(e.target.dataset.preventBackdropClose==='1') return;
      closeConfirmDialog(false);
    }
    else cm(e.target.id);
  }
});
// Close autocomplete dropdowns on outside click
document.addEventListener('click',function(e){
  if(isAutocompleteTransitionActive()) return;
  if((e.target.closest && (e.target.closest('.ac-drop') || e.target.closest('.ac-wrap'))) || e.target.classList.contains('ac-inp')){
    return;
  }
  if(!e.target.classList.contains('ac-inp')){
    closeAllAutocompleteDrops();
  }
});
document.addEventListener('focusin',function(e){
  if(isAutocompleteTransitionActive()) return;
  if(e.target.closest && (e.target.closest('.ac-drop') || e.target.closest('.ac-wrap'))) return;
  closeAllAutocompleteDrops();
});
document.addEventListener('mousedown',function(e){
  if(e.target && e.target.tagName==='SELECT') _nativeSelectOverlayLockUntil=Date.now()+600;
  if(e.target.closest && e.target.closest('.ac-item')) markAutocompleteTransition(220);
},true);

