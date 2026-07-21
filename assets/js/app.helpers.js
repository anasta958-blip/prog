// ===================== HELPERS =====================
function toast(msg,type){
  type=type||'ok';var el=document.createElement('div');
  el.className='toast '+(type==='err'?'err':'ok');
  el.innerHTML='<span>'+(type==='ok'?'✓':'⚠️')+'</span> '+esc(msg);
  document.getElementById('tc').appendChild(el);
  setTimeout(function(){el.remove();},10000);
}
function debounce(k,fn){clearTimeout(debTimers[k]);debTimers[k]=setTimeout(fn,350);}
function esc(s){
  if(s==null) return '';
  return String(s)
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;')
    .replace(/'/g,'&#39;');
}
function fmtDate(s){
  if(!s)return '—';
  try{
    var raw=String(s);
    var d=new Date(raw.indexOf(' ')>0?raw.replace(' ','T'):raw);
    if(isNaN(d.getTime())) return raw;
    return d.toLocaleString('ru-RU',{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'});
  }catch(e){return s;}
}

function initKanbanDragScroll(root){
  root=root||document;
  var wraps=root.querySelectorAll ? root.querySelectorAll('.kanban-wrap, .kanban-grid') : [];
  wraps.forEach(function(wrap){
    if(wrap.dataset.dragScrollReady==='1') return;
    wrap.dataset.dragScrollReady='1';
    var active=false, startX=0, startLeft=0;
    wrap.addEventListener('mousedown',function(e){
      if(e.button!==0) return;
      if(e.target.closest('button,input,select,textarea,label,a,.btn,.kanban-card')) return;
      active=true;
      startX=e.clientX;
      startLeft=wrap.scrollLeft;
      wrap.classList.add('drag-scroll-active');
      e.preventDefault();
    });
    window.addEventListener('mousemove',function(e){
      if(!active) return;
      wrap.scrollLeft=startLeft-(e.clientX-startX);
    });
    window.addEventListener('mouseup',function(){
      if(!active) return;
      active=false;
      wrap.classList.remove('drag-scroll-active');
    });
  });
}

function getRoleMark(role,text){
  if(!text) return '';
  return '<span class="role-mark r-'+esc(role||'manager')+'">'+esc(text)+'</span>';
}

function getRoleColor(role){
  if(role==='admin') return 'rgba(239,68,68,.9)';
  if(role==='rop') return 'rgba(79,140,255,.9)';
  if(role==='logist') return 'rgba(6,182,212,.9)';
  if(role==='prorab') return 'rgba(168,85,247,.9)';
  return 'rgba(79,140,255,.9)';
}

function getKpWorkflowColor(status, mode){
  var workspaceMode=kpNormalizeQuoteMode(mode||quoteWorkspaceMode);
  var map=workspaceMode==='pkp'
    ? {
        'Составить ПКП':'#4f8cff',
        'Согласовать ПКП':'#06b6d4',
        'Согласовать с клиентом':'#f59e0b',
        'Составить КП':'#f97316',
        'КП составлено':'#22c55e'
      }
    : {
        'Составить КП':'#4f8cff',
        'Согласовать КП':'#06b6d4',
        'Согласовать с клиентом':'#f59e0b',
        'Составить договор':'#a855f7',
        'Получить оплату':'#f97316',
        'Закупить материал':'#ef4444',
        'Выполненные монтажи':'#8b5cf6',
        'Вторые этапы':'#ec4899',
        'Получить финальную оплату':'#22c55e',
        'Оплата получена':'#64748b'
      };
  return map[status]||'var(--ac)';
}


function enhanceKanbanVariantBadges(root){
  root=root||document;
  (root.querySelectorAll?root.querySelectorAll('.kanban-card-meta'):[]).forEach(function(meta){
    var html=meta.innerHTML||'';
    html=html.replace(/Вариант:\s*([^<]+)(<br>|$)/, function(_, label, tail){
      return getKanbanVariantMarkup(String(label||'').trim()) + (tail||'');
    });
    meta.innerHTML=html;
  });
}

function getAppBasePath(){
  var path=String(location.pathname||'/');
  if(/\/index\.php$/i.test(path)) return path.replace(/\/index\.php$/i,'/');
  if(path.slice(-1)==='/') return path;
  return path.replace(/\/[^\/]*$/,'/') || '/';
}

function buildPublicQuoteUrl(path){
  var raw=String(path||'').trim();
  if(!raw) return '';
  if(/^https?:\/\//i.test(raw)) return raw;
  var base=location.origin + getAppBasePath();
  if(raw.indexOf('/quote.php?')===0){
    return location.origin + getAppBasePath().replace(/\/$/,'') + raw;
  }
  return new URL(raw.replace(/^\//,''), base).toString();
}

async function copyKpQuoteLink(url){
  var finalUrl=buildPublicQuoteUrl(url);
  try{
    if(navigator.clipboard && window.isSecureContext){
      await navigator.clipboard.writeText(finalUrl);
    }else{
      var ta=document.createElement('textarea');
      ta.value=finalUrl;
      ta.setAttribute('readonly','readonly');
      ta.style.position='fixed';
      ta.style.opacity='0';
      ta.style.pointerEvents='none';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      ta.setSelectionRange(0, ta.value.length);
      var ok=document.execCommand('copy');
      document.body.removeChild(ta);
      if(!ok) throw new Error('copy failed');
    }
    toast('\u0421\u0441\u044b\u043b\u043a\u0430 \u0441\u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u043d\u0430 \u2713');
  }catch(e){
    toast(finalUrl);
  }
}

setTimeout(function(){
  ensureCatalogBulkButtons();
  updateCatalogBulkDeleteUi();
},0);

var kanbanArchiveOpenState={};
function setKanbanArchiveOpen(board,status,isOpen){
  kanbanArchiveOpenState[board+'::'+status]=!!isOpen;
}
function getKanbanArchiveOpen(board,status){
  return !!kanbanArchiveOpenState[board+'::'+status];
}
function ensureKanbanArchiveSection(col, board, status){
  var details=col.querySelector('.kanban-archive');
  if(!details){
    details=document.createElement('details');
    details.className='kanban-archive';
    details.setAttribute('data-status', status);
    if(getKanbanArchiveOpen(board,status)) details.open=true;
    details.innerHTML='<summary><span>\u0410\u0440\u0445\u0438\u0432</span> <span class="badge-cnt">0</span></summary><div class="kanban-archive-body"></div>';
    details.addEventListener('toggle', function(){
      setKanbanArchiveOpen(board,status,details.open);
    });
    col.appendChild(details);
  }
  return details;
}
function updateKanbanArchiveEmptyState(body){
  var empty=body.querySelector('.kanban-archive-empty');
  if(body.children.length){
    if(empty) empty.remove();
    return;
  }
  if(!empty){
    empty=document.createElement('div');
    empty.className='kanban-archive-empty';
    empty.style.color='var(--tx3)';
    empty.style.fontSize='.8rem';
    empty.style.padding='4px 0';
    empty.textContent='\u041f\u0443\u0441\u0442\u043e';
    body.appendChild(empty);
  }
}
function ensureOrderArchiveButton(card, orderId, archived){
  var body=card.querySelector('.kanban-card-body');
  if(!body) return;
  var actions=body.querySelector('.kanban-card-actions');
  if(!actions){
    actions=document.createElement('div');
    actions.className='kanban-card-actions';
    body.appendChild(actions);
  }
  var btn=actions.querySelector('.kanban-archive-toggle');
  if(!btn){
    btn=document.createElement('button');
    btn.className='btn btn-xs kanban-archive-toggle';
    btn.addEventListener('click', function(e){
      e.stopPropagation();
      setOrderArchiveState(orderId, !archived);
    });
    actions.appendChild(btn);
  }
  btn.className='btn btn-xs kanban-archive-toggle '+(archived?'btn-g':'btn-cy');
  btn.textContent=archived?'\u0418\u0437 \u0430\u0440\u0445\u0438\u0432\u0430':'\u0412 \u0430\u0440\u0445\u0438\u0432';
  btn.onclick=function(e){
    e.stopPropagation();
    setOrderArchiveState(orderId, !archived);
  };
}
function ensureQuoteArchiveButton(card, quoteId, archived, mode){
  var body=card.querySelector('.kanban-card-body');
  if(!body) return;
  var actions=body.querySelector('.pa');
  if(!actions){
    actions=document.createElement('div');
    actions.className='pa';
    actions.style.marginTop='10px';
    body.appendChild(actions);
  }
  var btn=actions.querySelector('.kanban-archive-toggle');
  if(!btn){
    btn=document.createElement('button');
    btn.className='btn btn-xs kanban-archive-toggle';
    actions.appendChild(btn);
  }
  btn.className='btn btn-xs kanban-archive-toggle '+(archived?'btn-g':'btn-cy');
  btn.textContent=archived?'\u0418\u0437 \u0430\u0440\u0445\u0438\u0432\u0430':'\u0412 \u0430\u0440\u0445\u0438\u0432';
  btn.onclick=function(e){
    e.stopPropagation();
    setQuoteArchiveState(quoteId, !archived, mode);
  };
}
async function setOrderArchiveState(id, archived){
  try{
    await api('orders.php',{action:'set_archive_state',id:id,archived:archived?1:0});
    var row=(orderList||[]).find(function(o){return String(o.id)===String(id);});
    if(row){
      row.is_archived=archived?1:0;
      row.archived_at=archived?new Date().toISOString():null;
    }
    if(typeof renderOrdersKanban==='function') renderOrdersKanban();
    toast(archived?'\u041a\u0430\u0440\u0442\u043e\u0447\u043a\u0430 \u043f\u0435\u0440\u0435\u043d\u0435\u0441\u0435\u043d\u0430 \u0432 \u0430\u0440\u0445\u0438\u0432':'\u041a\u0430\u0440\u0442\u043e\u0447\u043a\u0430 \u0432\u043e\u0437\u0432\u0440\u0430\u0449\u0435\u043d\u0430 \u0438\u0437 \u0430\u0440\u0445\u0438\u0432\u0430');
  }catch(e){
    toast((e&&e.message)||'\u041e\u0448\u0438\u0431\u043a\u0430 \u0430\u0440\u0445\u0438\u0432\u0430','err');
  }
}
async function setQuoteArchiveState(id, archived, mode){
  try{
    mode=kpNormalizeQuoteMode(mode||'kp');
    await api(getQuoteApiFileByMode(mode),{action:'set_quote_archive',id:id,archived:archived?1:0});
    var row=kpFindQuoteRow(id, mode);
    if(row){
      row.is_archived=archived?1:0;
      row.archived_at=archived?new Date().toISOString():null;
    }
    loadKpQuotes({preserveScroll:true,silent:true});
    toast(archived?'\u041a\u0430\u0440\u0442\u043e\u0447\u043a\u0430 \u043f\u0435\u0440\u0435\u043d\u0435\u0441\u0435\u043d\u0430 \u0432 \u0430\u0440\u0445\u0438\u0432':'\u041a\u0430\u0440\u0442\u043e\u0447\u043a\u0430 \u0432\u043e\u0437\u0432\u0440\u0430\u0449\u0435\u043d\u0430 \u0438\u0437 \u0430\u0440\u0445\u0438\u0432\u0430');
  }catch(e){
    toast((e&&e.message)||'\u041e\u0448\u0438\u0431\u043a\u0430 \u0430\u0440\u0445\u0438\u0432\u0430','err');
  }
}
function ensureKanbanCardsEmptyState(cardsWrap){
  var hasCard=!!cardsWrap.querySelector('.kanban-card:not(.archived-card)');
  var empty=cardsWrap.querySelector('.kanban-empty-state');
  if(hasCard){
    if(empty) empty.remove();
    return;
  }
  if(!empty){
    empty=document.createElement('div');
    empty.className='kanban-empty-state';
    empty.style.color='var(--tx3)';
    empty.style.fontSize='.8rem';
    empty.style.padding='8px';
    empty.textContent='\u041f\u0443\u0441\u0442\u043e';
    cardsWrap.appendChild(empty);
  }
}
function enhanceOrdersKanbanArchive(){
  var root=document.getElementById('or-kanban');
  if(!root) return;
  (root.querySelectorAll ? root.querySelectorAll('.kanban-col[data-status]') : []).forEach(function(col){
    var status=col.getAttribute('data-status')||'';
    var cardsWrap=col.querySelector('.kanban-cards');
    var headerBadge=col.querySelector('.kanban-col-h .badge-cnt');
    var details=ensureKanbanArchiveSection(col,'orders',status);
    var archiveBody=details.querySelector('.kanban-archive-body');
    var archivedRows=(orderList||[]).filter(function(o){
      return String(o.status_order||'')===String(status) && !!parseInt(o.is_archived||0,10);
    });
    archivedRows.forEach(function(o){
      var card=root.querySelector('.kanban-card[data-id="'+o.id+'"]');
      if(!card) return;
      card.classList.add('archived-card');
      card.removeAttribute('draggable');
      card.removeAttribute('data-status');
      archiveBody.appendChild(card);
      ensureOrderArchiveButton(card,o.id,true);
    });
    Array.prototype.forEach.call(cardsWrap.querySelectorAll('.kanban-card[data-id]'), function(card){
      ensureOrderArchiveButton(card,card.getAttribute('data-id'),false);
    });
    if(headerBadge){
      var activeCount=(orderList||[]).filter(function(o){
        return String(o.status_order||'')===String(status) && !parseInt(o.is_archived||0,10);
      }).length;
      headerBadge.textContent=String(activeCount);
    }
    var archiveBadge=details.querySelector('.badge-cnt');
    if(archiveBadge) archiveBadge.textContent=String(archivedRows.length);
    updateKanbanArchiveEmptyState(archiveBody);
    ensureKanbanCardsEmptyState(cardsWrap);
  });
}
function normalizeDisplayedNumberText(text){
  var src=String(text||'');
  return src.replace(/-?\d+(?:[\.,]\d+)?/g, function(num){
    var normalized=num.replace(',', '.');
    var value=parseFloat(normalized);
    if(!isFinite(value)) return num;
    return String(Math.round(value));
  });
}

function stripNumericFieldDecimals(root){
  root=root||document;
  (root.querySelectorAll ? root.querySelectorAll('input[type="number"], input[id^="kp-price-"], input[id^="kp-purchase-"], input[id^="kp-sum-"]') : []).forEach(function(inp){
    if(inp.type==='number') inp.step='1';
    var val=String(inp.value||'').trim();
    if(!val) return;
    var parsed=parseFloat(val.replace(/\s+/g,'').replace(',','.'));
    if(!isFinite(parsed)) return;
    inp.value=String(Math.round(parsed));
  });
  (root.querySelectorAll ? root.querySelectorAll('[id^="kp-category-"], [id^="kp-summary-"]') : []).forEach(function(node){
    node.textContent=normalizeDisplayedNumberText(node.textContent);
  });
}

function reorderTableColumn(table, fromIndex, toIndex){
  if(!table || fromIndex===toIndex || fromIndex<0 || toIndex<0) return;
  Array.prototype.forEach.call(table.querySelectorAll('tr'), function(tr){
    var cells=tr.children;
    if(!cells || !cells.length || !cells[fromIndex]) return;
    var moving=cells[fromIndex];
    var targetIndex=toIndex;
    if(fromIndex<toIndex) targetIndex=toIndex+1;
    var beforeCell=cells[targetIndex]||null;
    tr.insertBefore(moving, beforeCell);
  });
  var cg=table.querySelector('colgroup');
  if(cg){
    var cols=cg.children;
    if(cols && cols[fromIndex]){
      var movingCol=cols[fromIndex];
      var targetIndex=toIndex;
      if(fromIndex<toIndex) targetIndex=toIndex+1;
      var beforeCol=cols[targetIndex]||null;
      cg.insertBefore(movingCol, beforeCol);
    }
  }
}


function enhanceKpCategoryBulkUi(root,t){
  if(!root || !isKpTarget(t)) return;
  Array.prototype.forEach.call(root.querySelectorAll('.secblk table.itbl'), function(tbl){
    var heads=tbl.querySelectorAll('thead');
    if(heads.length>1) heads[1].remove();
  });
  var body=root.querySelector('.kp-variant-body');
  var catEls=body ? Array.prototype.filter.call(body.children, function(el){
    return !!(el && el.classList && el.classList.contains('catblk'));
  }) : [];
  catEls.forEach(function(catEl,ci){
    var head=catEl.querySelector('.catblk-h');
    if(!head) return;
    var main=head.firstElementChild;
    if(!main) return;
    main.style.display='flex';
    main.style.alignItems='center';
    main.style.flexWrap='wrap';
  });
}

async function deleteService(id){
  if(!canDeleteByRole()){toast('\u041d\u0435\u0434\u043e\u0441\u0442\u0430\u0442\u043e\u0447\u043d\u043e \u043f\u0440\u0430\u0432','err');return;}
  var service=workServices.find(function(s){return s.id==id;});
  var name=service&&service.name?service.name:'\u044d\u0442\u0443 \u0440\u0430\u0431\u043e\u0442\u0443';
  var ok=await showConfirmDialog({title:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0440\u0430\u0431\u043e\u0442\u0443',message:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0440\u0430\u0431\u043e\u0442\u0443 \u00ab'+name+'\u00bb?',icon:'\uD83D\uDDD1\uFE0F',confirmText:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c',confirmClass:'btn-rd'});
  if(!ok) return;
  try{
    await api('catalog.php',{action:'delete_service',id:id});
    serviceOptionsCache=[];
    serviceOptionsCacheCategory='';
    linkableCatalogItems=[];
    workServices=(workServices||[]).filter(function(s){ return String(s.id)!==String(id); });
    var grid=getCatalogUi().grid;
    var card=grid ? grid.querySelector('[data-catalog-service-id="'+id+'"]') : null;
    if(card) card.remove();
    if(grid && !grid.querySelector('.ccard.fi2')) renderWorkServices();
    toast('\u0423\u0434\u0430\u043b\u0435\u043d\u043e \u2713');
  }catch(e){toast(e.message,'err');}
}

async function deleteCatalogName(id){
  if(!canDeleteByRole()){toast('\u041d\u0435\u0434\u043e\u0441\u0442\u0430\u0442\u043e\u0447\u043d\u043e \u043f\u0440\u0430\u0432','err');return;}
  var row=catalogNames.find(function(n){return n.id==id;});
  var name=row&&row.name?row.name:'\u044d\u0442\u0443 \u043a\u0430\u0440\u0442\u043e\u0447\u043a\u0443';
  var ok=await showConfirmDialog({title:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u0442\u043e\u0432\u0430\u0440',message:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u043a\u0430\u0440\u0442\u043e\u0447\u043a\u0443 \u0442\u043e\u0432\u0430\u0440\u0430 \u00ab'+name+'\u00bb \u0438\u0437 \u043a\u0430\u0442\u0430\u043b\u043e\u0433\u0430?',icon:'\uD83D\uDDD1\uFE0F',confirmText:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c',confirmClass:'btn-rd'});
  if(!ok) return;
  try{
    await api('catalog.php',{action:'delete_name',id:id});
    catalogNames=(catalogNames||[]).filter(function(n){ return String(n.id)!==String(id); });
    if(Array.isArray(allNamesCache)){
      allNamesCache=allNamesCache.filter(function(n){ return String(n.id)!==String(id); });
    }
    var grid=getCatalogUi().grid;
    var card=grid ? grid.querySelector('[data-catalog-name-id="'+id+'"]') : null;
    if(card) card.remove();
    if(grid && !grid.querySelector('.ccard.fi2')) renderCatalog();
    toast('\u041a\u0430\u0440\u0442\u043e\u0447\u043a\u0430 \u0443\u0434\u0430\u043b\u0435\u043d\u0430 \u2713');
  }catch(e){toast(e.message,'err');}
}

async function deleteKpQuote(id){
  if(!canDeleteByRole()){toast('\u041d\u0435\u0434\u043e\u0441\u0442\u0430\u0442\u043e\u0447\u043d\u043e \u043f\u0440\u0430\u0432','err');return;}
  var title=getQuoteWorkspaceTitle();
  var ok=await showConfirmDialog({title:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c '+title,message:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c '+title+'?',icon:'\uD83D\uDDD1\uFE0F',confirmText:'\u0423\u0434\u0430\u043b\u0438\u0442\u044c',confirmClass:'btn-rd'});
  if(!ok) return;
  try{
    await api(quoteApiFile(),{action:'delete_quote',id:id});
    toast(title+' \u0443\u0434\u0430\u043b\u0435\u043d\u043e');
    kpQuotes=(kpQuotes||[]).filter(function(q){ return String(q.id)!==String(id); });
    var root=document.getElementById('kp-quotes-kanban');
    var card=root ? root.querySelector('.kanban-card[data-kp-id="'+id+'"]') : null;
    if(!root || !card){
      loadKpQuotes({preserveScroll:true,silent:true});
      return;
    }
    var cardsWrap=card.closest('.kanban-cards');
    card.remove();
    if(cardsWrap) ensureKanbanCardsEmptyState(cardsWrap);
    enhanceQuotesKanbanArchive();
    enhanceQuotesKanbanLayout();
  }catch(e){toast(e.message,'err');}
}

function enforceIntegerInputValue(inp){
  if(!inp || inp.type!=='number') return;
  inp.step='1';
  var val=String(inp.value||'').trim();
  if(!val) return;
  var parsed=parseFloat(val.replace(/\s+/g,'').replace(',','.'));
  if(!isFinite(parsed)) return;
  var rounded=String(Math.round(parsed));
  if(inp.value!==rounded) inp.value=rounded;
}

function applyIntegerMode(root){
  (root&&root.querySelectorAll?root.querySelectorAll('input[type="number"]'):[]).forEach(function(inp){
    enforceIntegerInputValue(inp);
  });
}

document.addEventListener('input',function(e){
  var t=e.target;
  if(t && t.matches && t.matches('input[type="number"]')) enforceIntegerInputValue(t);
},true);

document.addEventListener('change',function(e){
  var t=e.target;
  if(t && t.matches && t.matches('input[type="number"]')) enforceIntegerInputValue(t);
},true);

document.addEventListener('blur',function(e){
  var t=e.target;
  if(t && t.matches && t.matches('input[type="number"]')) enforceIntegerInputValue(t);
},true);

applyIntegerMode(document);
new MutationObserver(function(mutations){
  mutations.forEach(function(m){
    (m.addedNodes||[]).forEach(function(node){
      if(node && node.nodeType===1){
        if(node.matches && node.matches('input[type="number"]')) enforceIntegerInputValue(node);
        applyIntegerMode(node);
      }
    });
  });
}).observe(document.body,{childList:true,subtree:true});

init();
