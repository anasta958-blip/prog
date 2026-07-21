// ===================== новые комплектации =====================
async function loadOrders(){
  var stEl=document.getElementById('or-st');
  var sEl=document.getElementById('or-s');
  var st=stEl ? stEl.value : '';
  var s=sEl ? sEl.value.trim() : '';
  var grid=document.getElementById('or-grid');
  if(grid) grid.innerHTML='<div class="es"><div class="spin" style="margin:0 auto 14px"></div>Загрузка...</div>';
  var kanban=document.getElementById('or-kanban');
  if(kanban) kanban.innerHTML='<div class="es"><div class="spin" style="margin:0 auto 14px"></div>Загрузка...</div>';
  try{
    var url='orders.php?action=orders';
    if(st) url+='&status='+encodeURIComponent(st);
    if(s)  url+='&search='+encodeURIComponent(s);
    orderList=await api(url);
    renderOrders();
    setOrdersView(ordersView);
  }catch(e){
    var html='<div class="es"><div class="ei">⚠️</div>'+esc(e.message)+'</div>';
    if(grid) grid.innerHTML=html;
    if(kanban) kanban.innerHTML=html;
  }
}

function getOrderTypeColor(t){return 'var(--ac)';}
function getOrderTypeLabel(t){return t||'';}

var oeInvoiceMeta={path:'',name:'',uploaded_at:''};
var oeInvoices=[];
var orderInvoiceViewerDrag=null;
function setOrdersView(v){
  ordersView='kanban';
  var grid=document.getElementById('or-grid');
  var kanban=document.getElementById('or-kanban');
  var fbar=document.getElementById('orders-fbar');
  if(grid) grid.style.display='none';
  if(kanban) kanban.style.display='block';
  if(fbar) fbar.style.display='none';
  renderOrdersKanban();
}

var KANBAN_STATUSES=[
    'Составление комплектации',
    'Проверка комплектации',
    'Проверено',
    'Закупка материала',
    'Монтаж',
    'Монтаж завершён',
    'Выполнено'];
var KANBAN_COLORS={
    'Составление комплектации':'#0000ff',
    'Проверка комплектации':'#ffff00',
    'Проверено':'#008000',
    'Закупка материала':'#0000ff',
    'Монтаж':'#800080',
    'Монтаж завершён':'#008000',
    'Выполнено':'#008000'};
// Columns visible per role (all statuses always shown as columns, but only role-allowed columns allow dropping)
var KANBAN_ROLE_COLS={
  'admin':  ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
  'manager':['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
  'rop':    ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
  'logist': ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
  'prorab': ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено']
};

var _kanbanDragging=null;
var _kanbanDropPlaceholder=null;
var _kanbanDropTargetCard=null;
var _kanbanDropTargetSide='';
var _kanbanDropColumn=null;

function getKanbanCols(){
  var role=CU?CU.role:'admin';
  return (KANBAN_ROLE_COLS[role]||KANBAN_STATUSES).filter(function(status){
    return accessKanbanColumnVisibleUi('orders', status);
  });
}

function renderOrdersKanban(){
  var wrap=document.getElementById('or-kanban');
  if(!orderList.length){wrap.innerHTML='<div class="es"><div class="ei">📭</div><div class="et">Заявок нет</div></div>';return;}
  var cols=getKanbanCols();
  var byStatus={};
  cols.forEach(function(s){byStatus[s]=[];});
  orderList.forEach(function(o){var s=o.status_order||'Составление комплектации';if(byStatus[s])byStatus[s].push(o);});

  var html='<div class="kanban-wrap">';
  cols.forEach(function(st){
    var cards=byStatus[st]||[];
    var color=KANBAN_COLORS[st]||'var(--ac)';
    var createBtn=st===cols[0] && accessCanUi('orders','create')
      ? '<button class="btn btn-g btn-xs" style="margin-left:auto" onclick="event.stopPropagation();showPage(\'doc\')">Новая заявка</button>'
      : '';
    var cardsHtml=cards.map(function(o){
      var tc=getOrderTypeColor(o.order_type);
      var tl=getOrderTypeLabel(o.order_type);
      var headerColor=getRoleColor(o.status_changed_by_role||'manager');
      return '<div class="kanban-card" draggable="true" data-id="'+o.id+'" data-status="'+esc(st)+'" onclick="kanbanCardClick(event,'+o.id+')">'+
        '<div class="kanban-card-top" style="background:'+headerColor+'">'+esc(o.address||'—')+'</div>'+
        '<div class="kanban-card-body">'+
          '<div class="kanban-card-addr" style="font-size:.75rem;color:var(--tx2)">№'+esc(o.order_number)+(tl?' · '+esc(tl):'')+'</div>'+
          '<div class="kanban-card-meta">'+esc(o.manager_name)+(o.rop_name?' - '+esc(o.rop_name):'')+'<br>'+fmtDate(o.created_at)+'<br>'+esc(o.status_order||'—')+'</div>'+
          '<div class="kanban-card-actions">'+
            '<button class="btn btn-g btn-xs" onclick="event.stopPropagation();openOrderEdit('+o.id+')">✏️</button>'+
            ((CU.role==='admin'||CU.role==='rop')?'<button class="btn btn-rd btn-xs" onclick="event.stopPropagation();deleteOrder('+o.id+',\''+esc(o.order_number)+'\')">🗑</button>':'')+
          '</div>'+
        '</div></div>';
    }).join('');
    html+='<div class="kanban-col" data-status="'+esc(st)+'">'+
      '<div class="kanban-col-h" style="border-top:3px solid '+color+'">'+
        '<span>'+esc(st)+'</span>'+
        '<span class="badge-cnt">'+cards.length+'</span>'+
        createBtn+
      '</div>'+
      '<div class="kanban-cards" data-col="'+esc(st)+'">'+(cardsHtml||'<div style="color:var(--tx3);font-size:.8rem;padding:8px">Нет заявок</div>')+'</div>'+
    '</div>';
  });
  html+='</div>';
  wrap.innerHTML=html;
  initKanbanDragScroll(wrap);
  initKanbanDnd();
  enhanceOrdersKanbanArchive();
}

function kanbanCardClick(e,id){
  if(_kanbanDragging) return;
  openOrderEdit(id);
}

function clearKanbanDropIndicators(){
  if(_kanbanDropPlaceholder && _kanbanDropPlaceholder.parentNode) _kanbanDropPlaceholder.parentNode.removeChild(_kanbanDropPlaceholder);
  _kanbanDropPlaceholder=null;
  if(_kanbanDropTargetCard){
    _kanbanDropTargetCard.classList.remove('drop-target-top');
    _kanbanDropTargetCard.classList.remove('drop-target-bottom');
  }
  _kanbanDropTargetCard=null;
  _kanbanDropTargetSide='';
  _kanbanDropColumn=null;
  document.querySelectorAll('.kanban-col.drag-over').forEach(function(c){c.classList.remove('drag-over');});
}
function isOrderDragPointInsideCol(col, clientX, clientY){
  if(!col) return false;
  if(typeof clientX!=='number' || typeof clientY!=='number') return false;
  var el=document.elementFromPoint(clientX, clientY);
  return !!(el && col.contains(el));
}
function findOrderDropTarget(col, dragging, clientY){
  var cards=Array.prototype.filter.call(col.querySelectorAll('.kanban-card[data-id]'), function(card){
    return card!==dragging;
  });
  if(!cards.length) return {target:null, side:''};
  for(var i=0;i<cards.length;i++){
    var card=cards[i];
    var rect=card.getBoundingClientRect();
    var mid=rect.top + rect.height/2;
    if(clientY < mid) return {target:card, side:'top'};
  }
  return {target:cards[cards.length-1], side:'bottom'};
}

function ensureKanbanDropPlaceholder(){
  if(_kanbanDropPlaceholder) return _kanbanDropPlaceholder;
  _kanbanDropPlaceholder=document.createElement('div');
  _kanbanDropPlaceholder.className='kanban-drop-placeholder';
  return _kanbanDropPlaceholder;
}

function setKanbanDropIndicator(col, cardsWrap, target, side){
  var ph=ensureKanbanDropPlaceholder();
  if(_kanbanDropColumn && _kanbanDropColumn!==col) _kanbanDropColumn.classList.remove('drag-over');
  col.classList.add('drag-over');
  if(_kanbanDropTargetCard && _kanbanDropTargetCard!==target){
    _kanbanDropTargetCard.classList.remove('drop-target-top');
    _kanbanDropTargetCard.classList.remove('drop-target-bottom');
  }
  if(target){
    if(target!==_kanbanDropTargetCard || side!==_kanbanDropTargetSide){
      target.classList.remove('drop-target-top');
      target.classList.remove('drop-target-bottom');
      target.classList.add(side==='top' ? 'drop-target-top' : 'drop-target-bottom');
    }
    var anchor=side==='top' ? target : target.nextSibling;
    if(ph.parentNode!==cardsWrap || ph.nextSibling!==anchor) cardsWrap.insertBefore(ph, anchor);
  }else{
    if(_kanbanDropTargetCard){
      _kanbanDropTargetCard.classList.remove('drop-target-top');
      _kanbanDropTargetCard.classList.remove('drop-target-bottom');
    }
    if(ph.parentNode!==cardsWrap || ph!==cardsWrap.lastChild) cardsWrap.appendChild(ph);
  }
  _kanbanDropTargetCard=target||null;
  _kanbanDropTargetSide=target ? side : '';
  _kanbanDropColumn=col;
}

function initKanbanDnd(){
  var allowedCols=getKanbanCols();

  document.querySelectorAll('.kanban-card').forEach(function(card){
    card.addEventListener('dragstart',function(e){
      _kanbanDragging=card.dataset.id;
      e.dataTransfer.effectAllowed='move';
      e.dataTransfer.setData('text/plain', card.dataset.id+'|'+card.dataset.status);
      setTimeout(function(){ card.classList.add('dragging'); },0);
    });
    card.addEventListener('dragend',function(){
      card.classList.remove('dragging');
      setTimeout(function(){ _kanbanDragging=null; },0);
      clearKanbanDropIndicators();
    });
  });

  document.querySelectorAll('.kanban-col').forEach(function(col){
    var colStatus=col.dataset.status;
    if(allowedCols.indexOf(colStatus)<0) return;
    var cardsWrap=col.querySelector('.kanban-cards');

    col.addEventListener('dragover',function(e){
      e.preventDefault();
      var dragging=document.querySelector('.kanban-card.dragging');
      if(!dragging || !cardsWrap) return;
      var drop=findOrderDropTarget(cardsWrap, dragging, e.clientY);
      setKanbanDropIndicator(col, cardsWrap, drop.target, drop.side);
    });
    col.addEventListener('dragleave',function(e){
      if(_kanbanDropColumn!==col) return;
      if(e.relatedTarget && col.contains(e.relatedTarget)) return;
      var x=e.clientX, y=e.clientY;
      requestAnimationFrame(function(){
        if(_kanbanDropColumn!==col) return;
        if(isOrderDragPointInsideCol(col, x, y)) return;
        clearKanbanDropIndicators();
      });
    });
    col.addEventListener('drop',function(e){
      e.preventDefault();
      var parts=(e.dataTransfer.getData('text/plain')||'').split('|');
      var id=parseInt(parts[0]);
      var fromStatus=parts[1]||'';
      if(!id) return;
      kanbanMoveCard(id,colStatus,cardsWrap,fromStatus);
    });
  });
}

function reorderOrderListForKanban(id,status,orderedIds){
  if(!orderedIds || !orderedIds.length) return;
  var idSet={};
  orderedIds.forEach(function(x){idSet[String(x)]=true;});
  var movedRows=(orderList||[]).filter(function(o){
    return String(o.status_order||'Составление комплектации')===String(status) && idSet[String(o.id)];
  });
  var movedMap={};
  movedRows.forEach(function(o){movedMap[String(o.id)]=o;});
  var orderedRows=orderedIds.map(function(x){return movedMap[String(x)]||null;}).filter(Boolean);
  var inserted=false;
  orderList=(orderList||[]).filter(function(o){return !idSet[String(o.id)];}).reduce(function(acc,o){
    if(!inserted && String(o.status_order||'Составление комплектации')===String(status)){
      inserted=true;
      return acc.concat(orderedRows,[o]);
    }
    acc.push(o);
    return acc;
  },[]);
  if(!inserted) orderList=orderList.concat(orderedRows);
}

function applyOrderColumnDomOrder(status, orderedIds){
  if(!orderedIds || !orderedIds.length) return false;
  var cols=Array.prototype.slice.call(document.querySelectorAll('.kanban-col[data-status]'));
  var col=cols.find(function(node){return String(node.getAttribute('data-status')||'')===String(status);});
  var cardsWrap=col ? col.querySelector('.kanban-cards') : null;
  if(!cardsWrap) return false;
  var cards={};
  Array.prototype.slice.call(cardsWrap.querySelectorAll('.kanban-card[data-id]')).forEach(function(card){
    cards[String(card.getAttribute('data-id')||'')]=card;
  });
  var fragment=document.createDocumentFragment();
  orderedIds.forEach(function(id){
    var card=cards[String(id)];
    if(card) fragment.appendChild(card);
  });
  Object.keys(cards).forEach(function(id){
    if(orderedIds.map(String).indexOf(String(id))<0) fragment.appendChild(cards[id]);
  });
  cardsWrap.appendChild(fragment);
  return true;
}

async function kanbanMoveCard(id, newStatus, cardsWrap, fromStatus){
  var order=orderList.find(function(o){return o.id==id;});
  if(!order) return;
  var orderedIds=[];
  if(cardsWrap){
    orderedIds=Array.prototype.map.call(cardsWrap.querySelectorAll('.kanban-card[data-id]'), function(card){
      return parseInt(card.getAttribute('data-id')||'0',10)||0;
    }).filter(Boolean).filter(function(cardId){ return cardId!==id; });
    if(_kanbanDropPlaceholder && _kanbanDropPlaceholder.parentNode===cardsWrap){
      var insertIndex=Array.prototype.indexOf.call(cardsWrap.children, _kanbanDropPlaceholder);
      if(insertIndex<0) insertIndex=orderedIds.length;
      orderedIds.splice(insertIndex,0,id);
    }else{
      orderedIds.push(id);
    }
  }
  clearKanbanDropIndicators();
  if(String(fromStatus||'')===String(newStatus)){
    reorderOrderListForKanban(id,newStatus,orderedIds);
    if(!applyOrderColumnDomOrder(newStatus,orderedIds)) renderOrdersKanban();
    return;
  }
  if(!(await confirmOrderBoardTransfer(newStatus))) return;
  var prevStatus=order.status_order;
  var main=document.querySelector('.main');
  var wrap=document.querySelector('.kanban-wrap');
  var scrollTop=main?main.scrollTop:0;
  var scrollLeft=wrap?wrap.scrollLeft:0;
  order.status_order=newStatus;
  reorderOrderListForKanban(id,newStatus,orderedIds);
  renderOrdersKanban();
  var wrap2=document.querySelector('.kanban-wrap');
  if(main) main.scrollTop=scrollTop;
  if(wrap2) wrap2.scrollLeft=scrollLeft;
  try {
    var res=await api('orders.php',{action:'update_order',id:id,status_order:newStatus});
    if(res && res.hidden_in_orders){
      finalizeCompletedOrderLocally(id);
      toast('Монтаж завершён, карточка перенесена в КП: Получить финальную оплату');
      return;
    }
    toast('Статус изменён: '+newStatus);
  } catch(e) {
    order.status_order=prevStatus;
    var scrollTop2=main?main.scrollTop:0;
    var scrollLeft2=wrap2?wrap2.scrollLeft:0;
    renderOrdersKanban();
    var wrap3=document.querySelector('.kanban-wrap');
    if(main) main.scrollTop=scrollTop2;
    if(wrap3) wrap3.scrollLeft=scrollLeft2;
    toast('Ошибка изменения статуса: '+(e.message||e),'err');
  }
}

function finalizeCompletedOrderLocally(id){
  orderList=orderList.filter(function(o){return o.id!=id;});
  if(document.getElementById('page-order-edit').style.display!=='none'){
    showPage('orders');
  }else{
    renderOrders();
    setOrdersView(ordersView);
  }
  if(document.getElementById('page-kp-list').style.display!=='none'){
    loadKpQuotes({preserveScroll:true});
  }
}

function renderOrders(){
  var grid=document.getElementById('or-grid');
  if(!grid){
    if(ordersView==='kanban') renderOrdersKanban();
    return;
  }
  if(!orderList.length){grid.innerHTML=''; if(ordersView==='kanban') renderOrdersKanban(); return;}
  grid.innerHTML='<div class="pgrid">'+orderList.map(function(o){
    var tc=getOrderTypeColor(o.order_type);
    var tl=getOrderTypeLabel(o.order_type);
    var canDelete=(CU.role==='admin'||CU.role==='rop');
    var headerColor=getRoleColor(o.status_changed_by_role||'manager');
    return '<div class="ocard fi2">'+
    '<div class="ocard-addr" style="background:'+headerColor+'">'+
        '<div style="display:flex;align-items:center;justify-content:space-between;gap:8px">'+
          '<span style="font-weight:700;font-size:1rem">'+esc(o.address||'—')+'</span>'+
          '<span style="font-size:.8rem;opacity:.85">№'+esc(o.order_number)+(tl?' &nbsp;<span style=\"opacity:.75;font-weight:400\">'+esc(tl)+'</span>':'')+'</span>'+
        '</div>'+
      '</div>'+
        '<div class="ocard-body">'+
        '<div class="ocard-meta">'+
          '<div><div class="mlb">Менеджер</div><div class="mvl">'+esc(o.manager_name)+'</div></div>'+
          (o.rop_name?'<div><div class="mlb">РОП</div><div class="mvl">'+esc(o.rop_name)+'</div></div>':'')+
          '<div><div class="mlb">Создана</div><div class="mvl">'+fmtDate(o.created_at)+'</div></div>'+
          '<div><div class="mlb">Статус</div><div class="mvl">'+esc(o.status_order||'—')+'</div></div>'+
        '</div>'+
        '<div class="ocard-ft"><button class="btn btn-g btn-sm" onclick="openOrderEdit('+o.id+')">✏️ Открыть</button>'+(canDelete?'<button class="btn btn-rd btn-sm" onclick="deleteOrder('+o.id+',\''+esc(o.order_number)+'\')">🗑 Удалить</button>':'')+'</div>'+
      '</div></div>';
  }).join('')+'</div>';
  if(ordersView==='kanban') renderOrdersKanban();
}

async function updateOrderCardStatus(id,status){
  if(!status) return;
  try{
    await api('orders.php',{action:'update_order',id:id,status_order:status});
    await loadOrders();
  }catch(e){toast(e.message,'err');loadOrders();}
}

async function deleteOrder(id,number){
  if(!confirm('Удалить заявку '+number+'?')) return;
  try{
    await api('orders.php',{action:'delete_order',id:id});
    toast('Заявка удалена ✓');
    if(parseInt(document.getElementById('oe-id').value||'0',10)===id){
      clearOrderBuilderDraft('edit',id);
      initializeOrderBuilderDraftTracking('edit');
      showPage('orders');
    }
    loadOrders();
  }catch(e){toast(e.message,'err');}
}

function deleteCurrentOrder(){
  var id=parseInt(document.getElementById('oe-id').value||'0',10);
  var number=document.getElementById('oe-num').value||id;
  if(id) deleteOrder(id,number);
}

var oeStatusSaveToken=0;
async function saveOrderStatusImmediately(){
  var id=parseInt(document.getElementById('oe-id').value||'0',10);
  var sel=document.getElementById('oe-status');
  var ind=document.getElementById('autosave-indicator');
  if(!id||!sel) return;

  var newStatus=sel.value;
  var order=orderList.find(function(o){return o.id==id;});
  var prevStatus=(sel.dataset.prevStatus|| (order&&order.status_order) || '');
  if(!(await confirmOrderBoardTransfer(newStatus))){
    if(prevStatus) sel.value=prevStatus;
    return;
  }
  var token=++oeStatusSaveToken;
  var wasDisabled=sel.disabled;
  sel.disabled=true;
  if(ind) ind.textContent='Сохранение статуса...';

  try{
    var res=await api('orders.php',{action:'update_order',id:id,status_order:newStatus});
    if(res && res.hidden_in_orders){
      finalizeCompletedOrderLocally(id);
      if(ind) ind.textContent='Монтаж завершён, карточка перенесена в КП: Получить финальную оплату';
      return;
    }
    if(order) order.status_order=newStatus;
    sel.dataset.prevStatus=newStatus;
    if(typeof updateOrderBuilderDraftBaselineField==='function') updateOrderBuilderDraftBaselineField('edit','status_order',newStatus);
    if(ind) ind.textContent='Статус сохранён в '+new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'});
    if(document.getElementById('page-orders').style.display!=='none') loadOrders();
  }catch(e){
    if(prevStatus) sel.value=prevStatus;
    if(ind) ind.textContent='Ошибка сохранения статуса';
    toast(e.message||'Ошибка сохранения статуса','err');
  }finally{
    if(token===oeStatusSaveToken) sel.disabled=wasDisabled;
  }
}

async function openOrderEdit(id){
  try{
    var o=await api('orders.php?action=order_detail&id='+id);
    document.getElementById('oe-id').value=o.id;
    document.getElementById('oe-page-title').textContent='Комплектация объекта №'+o.order_number;
    document.getElementById('oe-addr').value=o.address||'';
    document.getElementById('oe-mgr').value=o.manager_name;
    document.getElementById('oe-rop').value=o.rop_name||'';
    document.getElementById('oe-num').value=o.order_number;
    document.getElementById('oe-client-type').value=o.client_type||'';
    document.getElementById('oe-type').value=o.order_type||'';
    // Show status changed by info
    var scbEl=document.getElementById('oe-status-changed-by');
    if(scbEl){
      if(o.status_changed_by_login){
        scbEl.innerHTML='Статус изменил: '+getRoleMark(o.status_changed_by_role,o.status_changed_by_login)+(o.status_changed_at?' <span style="color:var(--tx3)">('+fmtDate(o.status_changed_at)+')</span>':'');
        scbEl.style.display='';
      } else {
        scbEl.style.display='none';
      }
    }
    // Status selector - only allowed statuses
    var sel=document.getElementById('oe-status');
    sel.innerHTML='';
    var allowed=ROLE_SET_STATUSES[CU.role]||[];
    // Always include current status
    var statuses=allowed.slice();
    if(statuses.indexOf(o.status_order)<0) statuses.unshift(o.status_order);
    sel.innerHTML=statuses.map(function(s){
      return '<option'+(s===o.status_order?' selected':'')+'>'+esc(s)+'</option>';
    }).join('');
    sel.dataset.prevStatus=o.status_order||'';
    sel.onchange=saveOrderStatusImmediately;
    // Color the address bar with neutral color
    document.getElementById('oe-addr-bar').style.background='var(--ac)';
    document.getElementById('oe-addr-bar').textContent=o.address||'';

    syncOrdersAccessUi();

    oeCats=o.doc_snapshot?JSON.parse(JSON.stringify(o.doc_snapshot)):[];
    oeOwnerUserId=parseInt(o.manager_id||0,10)||0;
    // Инициализируем массивы опций для autocomplete (могут отсутствовать в старых снимках)
    oeCats.forEach(function(cat){
      (cat.sections||[]).forEach(function(sec){
        if(typeof sec.isDozakaz==='undefined') sec.isDozakaz=(sec.secName==='Дозаказ расходного материала');
        (sec.items||[]).forEach(function(it){
            if(!it.marking_size && it.komplektaciya) it.marking_size=it.komplektaciya;
            if(!it.markingSizeOptions) it.markingSizeOptions=[];
            if(!it.komplektaciyaOptions) it.komplektaciyaOptions=[];
        });
      });
    });
    initializeOrderBuilderDraftTracking('edit');
    restoreOrderBuilderDraft('edit',o.id);
    oeOrderId=o.id;
    oeInvoices=Array.isArray(o.invoices)?o.invoices:[];
    oeInvoiceMeta={
      path:(oeInvoices[0]&&oeInvoices[0].file_path)||'',
      name:(oeInvoices[0]&&oeInvoices[0].original_name)||'',
      uploaded_at:(oeInvoices[0]&&oeInvoices[0].uploaded_at)||''
    };
    updateOrderInvoiceUi();
    var invoiceViewer=document.getElementById('order-invoice-viewer');
    if(invoiceViewer&&invoiceViewer.style.display!=='none'){
      if(oeInvoiceMeta.path) openOrderInvoiceFile((oeInvoices[0]&&oeInvoices[0].id)||0);
      else closeOrderInvoiceViewer();
    }

    // Build filter tabs from products
    buildOeFilterTabs(o.products||[]);
    oeFilterSup=''; oeFilterShip='';

    renderOEBuilder();
    showPage('order-edit');
  }catch(e){
    console.error('openOrderEdit error:', e);
    toast('Ошибка открытия новой комплектации: '+(e.message||e),'err');
  }
}

function updateOrderInvoiceUi(){
  var uploadBtn=document.getElementById('oe-invoice-upload-btn');
  var viewBtn=document.getElementById('oe-invoice-view-btn');
  var meta=document.getElementById('oe-invoice-meta');
  var hasOrder=!!parseInt(document.getElementById('oe-id') ? document.getElementById('oe-id').value||'0' : '0',10);
  var hasInvoice=oeInvoices.length>0 || !!(oeInvoiceMeta&&oeInvoiceMeta.path);
  if(uploadBtn) uploadBtn.disabled=!hasOrder || !accessCanUi('orders','edit');
  if(viewBtn) viewBtn.disabled=!hasInvoice;
  if(meta){
    meta.textContent=hasInvoice
      ? ((oeInvoiceMeta.name||'Счёт загружен')+(oeInvoiceMeta.uploaded_at?' · '+fmtDate(oeInvoiceMeta.uploaded_at):''))
      : 'Счёт не загружен';
    if(hasInvoice) meta.textContent='Счетов: '+(oeInvoices.length||1);
  }
}

function pickOrderInvoice(){
  var id=parseInt(document.getElementById('oe-id').value||'0',10);
  if(!id){toast('Сначала сохраните комплектацию','err');return;}
  if(!accessCanUi('orders','edit')){toast('Нет прав','err');return;}
  var input=document.getElementById('oe-invoice-file');
  if(input) input.click();
}

async function uploadOrderInvoice(input){
  if(!input||!input.files||!input.files[0]) return;
  var file=input.files[0];
  if(!/\.pdf$/i.test(file.name||'')){
    toast('Можно загрузить только PDF','err');
    input.value='';
    return;
  }
  var id=parseInt(document.getElementById('oe-id').value||'0',10);
  if(!id){toast('Сначала сохраните комплектацию','err');input.value='';return;}
  var fd=new FormData();
  fd.append('id',String(id));
  fd.append('file',file);
  try{
    var data=await apiUpload('orders.php?action=upload_order_invoice',fd);
    oeInvoices=Array.isArray(data.invoices)?data.invoices:[];
    oeInvoiceMeta={
      path:(oeInvoices[0]&&oeInvoices[0].file_path)||'',
      name:(oeInvoices[0]&&oeInvoices[0].original_name)||file.name,
      uploaded_at:(oeInvoices[0]&&oeInvoices[0].uploaded_at)||''
    };
    updateOrderInvoiceUi();
    toast('Счёт загружен ✓');
    var viewer=document.getElementById('order-invoice-viewer');
    if(viewer&&viewer.style.display!=='none') openOrderInvoiceFile((oeInvoices[0]&&oeInvoices[0].id)||0);
  }catch(e){
    toast(e.message||'Ошибка загрузки счёта','err');
  }finally{
    input.value='';
  }
}

function openOrderInvoiceViewer(){
  var id=parseInt(document.getElementById('oe-id').value||'0',10);
  if(!id){toast('Сначала сохраните комплектацию','err');return;}
  if(!(oeInvoices.length>0 || (oeInvoiceMeta&&oeInvoiceMeta.path))){toast('Счёт не загружен','err');return;}
  renderOrderInvoicePicker();
  var modal=document.getElementById('order-invoice-picker');
  if(modal) modal.style.display='flex';
}

function closeOrderInvoicePicker(){
  var modal=document.getElementById('order-invoice-picker');
  if(modal) modal.style.display='none';
}

function renderOrderInvoicePicker(){
  var list=document.getElementById('order-invoice-list');
  if(!list) return;
  var invoices=oeInvoices.length?oeInvoices:[{
    id:0,
    original_name:(oeInvoiceMeta&&oeInvoiceMeta.name)||'Счёт',
    uploaded_at:(oeInvoiceMeta&&oeInvoiceMeta.uploaded_at)||''
  }];
  list.innerHTML='';
  invoices.forEach(function(inv){
    var row=document.createElement('div');
    row.className='order-invoice-row';
    var info=document.createElement('div');
    info.className='order-invoice-row-info';
    info.innerHTML='<b>'+esc(inv.original_name||'Счёт')+'</b><span>'+(inv.uploaded_at?esc(fmtDate(inv.uploaded_at)):'')+'</span>';
    var actions=document.createElement('div');
    actions.className='order-invoice-row-actions';
    var openBtn=document.createElement('button');
    openBtn.type='button';
    openBtn.className='btn btn-g';
    openBtn.textContent='Открыть';
    openBtn.onclick=function(){closeOrderInvoicePicker();openOrderInvoiceFile(inv.id||0);};
    actions.appendChild(openBtn);
    if(inv.id&&accessCanUi('orders','edit')){
      var delBtn=document.createElement('button');
      delBtn.type='button';
      delBtn.className='btn btn-r';
      delBtn.textContent='Удалить';
      delBtn.onclick=function(){deleteOrderInvoice(inv.id);};
      actions.appendChild(delBtn);
    }
    row.appendChild(info);
    row.appendChild(actions);
    list.appendChild(row);
  });
}

async function deleteOrderInvoice(invoiceId){
  var id=parseInt(document.getElementById('oe-id').value||'0',10);
  if(!id||!invoiceId) return;
  if(!confirm('Удалить выбранный счёт?')) return;
  try{
    var data=await apiPost('orders.php?action=delete_order_invoice',{id:id,invoice_id:invoiceId});
    oeInvoices=Array.isArray(data.invoices)?data.invoices:[];
    oeInvoiceMeta={
      path:(oeInvoices[0]&&oeInvoices[0].file_path)||'',
      name:(oeInvoices[0]&&oeInvoices[0].original_name)||'',
      uploaded_at:(oeInvoices[0]&&oeInvoices[0].uploaded_at)||''
    };
    updateOrderInvoiceUi();
    renderOrderInvoicePicker();
    if(!oeInvoices.length){
      closeOrderInvoicePicker();
      closeOrderInvoiceViewer();
    }
    toast('Счёт удалён');
  }catch(e){
    toast(e.message||'Ошибка удаления счёта','err');
  }
}

function openOrderInvoiceFile(invoiceId){
  var id=parseInt(document.getElementById('oe-id').value||'0',10);
  if(!id){toast('Сначала сохраните комплектацию','err');return;}
  if(!oeInvoiceMeta||!oeInvoiceMeta.path){toast('Счёт не загружен','err');return;}
  var viewer=document.getElementById('order-invoice-viewer');
  var frame=document.getElementById('order-invoice-frame');
  var title=document.getElementById('order-invoice-viewer-name');
  if(!viewer||!frame) return;
  if(title) title.textContent=oeInvoiceMeta.name||'Счёт';
  frame.src='api/orders.php?action=order_invoice_pdf&id='+encodeURIComponent(id)+'&v='+Date.now();
  var inv=(oeInvoices||[]).filter(function(item){return parseInt(item.id||0,10)===parseInt(invoiceId||0,10);})[0]||oeInvoices[0]||null;
  if(title&&inv) title.textContent=inv.original_name||'Счёт';
  if(invoiceId) frame.src='api/orders.php?action=order_invoice_pdf&id='+encodeURIComponent(id)+'&invoice_id='+encodeURIComponent(invoiceId)+'&v='+Date.now();
  viewer.style.display='block';
}

function closeOrderInvoiceViewer(){
  var viewer=document.getElementById('order-invoice-viewer');
  var frame=document.getElementById('order-invoice-frame');
  if(frame) frame.src='about:blank';
  if(viewer) viewer.style.display='none';
}

function initOrderInvoiceViewerDrag(){
  var head=document.getElementById('order-invoice-viewer-head');
  var viewer=document.getElementById('order-invoice-viewer');
  if(!head||!viewer||head.dataset.dragReady) return;
  head.dataset.dragReady='1';
  head.addEventListener('pointerdown',function(e){
    if(e.target&&e.target.closest&&e.target.closest('button')) return;
    var rect=viewer.getBoundingClientRect();
    orderInvoiceViewerDrag={
      pointerId:e.pointerId,
      dx:e.clientX-rect.left,
      dy:e.clientY-rect.top
    };
    head.setPointerCapture(e.pointerId);
  });
  head.addEventListener('pointermove',function(e){
    if(!orderInvoiceViewerDrag||orderInvoiceViewerDrag.pointerId!==e.pointerId) return;
    var maxLeft=Math.max(0,window.innerWidth-viewer.offsetWidth-8);
    var maxTop=Math.max(0,window.innerHeight-viewer.offsetHeight-8);
    var left=Math.max(8,Math.min(maxLeft,e.clientX-orderInvoiceViewerDrag.dx));
    var top=Math.max(8,Math.min(maxTop,e.clientY-orderInvoiceViewerDrag.dy));
    viewer.style.left=left+'px';
    viewer.style.top=top+'px';
  });
  head.addEventListener('pointerup',function(e){
    if(orderInvoiceViewerDrag&&orderInvoiceViewerDrag.pointerId===e.pointerId) orderInvoiceViewerDrag=null;
  });
  head.addEventListener('pointercancel',function(){orderInvoiceViewerDrag=null;});
}
initOrderInvoiceViewerDrag();

function buildOeFilterTabs(products){
  var sups=[...new Set(products.map(function(p){return p.supplier||'';}).filter(Boolean))];
  var ships=[...new Set(products.map(function(p){return p.shipment_status||'';}).filter(Boolean))];

  var supTabs=document.getElementById('oe-sup-tabs');
  supTabs.innerHTML=['<div class="ftab active" onclick="setOeFilter(\'sup\',\'\',this)">Все</div>'].concat(sups.map(function(s){
    return '<div class="ftab" onclick="setOeFilter(\'sup\',\''+esc(s)+'\',this)">'+esc(s)+'</div>';
  })).join('');

  var shipTabs=document.getElementById('oe-ship-tabs');
  shipTabs.innerHTML=['<div class="ftab active" onclick="setOeFilter(\'ship\',\'\',this)">Все</div>'].concat(['Купить','На складе','Заказано','На объекте'].map(function(s){
    return '<div class="ftab" onclick="setOeFilter(\'ship\',\''+s+'\',this)">'+s+'</div>';
  })).join('');
}

function setOeFilter(type,val,el){
  if(type==='sup') oeFilterSup=val;
  else oeFilterShip=val;
  // update active tab
  var container=el.parentElement;
  container.querySelectorAll('.ftab').forEach(function(t){t.classList.remove('active');});
  el.classList.add('active');
  renderOEBuilder();
}

async function saveOrderEdit(){
  if(!accessCanUi('orders','edit')){toast('Нет прав','err');return;}
  var id=parseInt(document.getElementById('oe-id').value);
  var addr=document.getElementById('oe-addr').value.trim();
  var status=document.getElementById('oe-status').value;
  var orderNum=document.getElementById('oe-num').value.trim();
  var orderType=document.getElementById('oe-type').value;
  var clientType=document.getElementById('oe-client-type').value.trim();
  if(!addr){toast('Введите адрес','err');return;}
  if(!orderType){toast('Выберите тип объекта','err');return;}
  if(!clientType){toast('Введите тип клиента','err');return;}
  var items=collectItems(oeCats);
  try{
    await api('orders.php',{action:'update_order',id:id,address:addr,status_order:status,order_number:orderNum,order_type:orderType,client_type:clientType,snapshot:oeCats,items:items});
    clearOrderBuilderDraft('edit',id);
    initializeOrderBuilderDraftTracking('edit');
    toast('Комплектация объекта обновлена ✓');
    loadOrders();
  }catch(e){toast(e.message,'err');}
}

