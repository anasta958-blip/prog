// ===================== СОТРУДНИКИ: ОБЩЕЕ ДЕРЕВО =====================
async function loadEmployees(){
  try{
    var users=await loadUsersDirectory();
    var tree=document.getElementById('emp-tree');
    if(!tree) return;
    if(!users.length){
      tree.className='emp-tree';
      tree.innerHTML='<div class="emp-empty"><div class="ei">👥</div><div class="et">Нет сотрудников</div><div class="es2">Добавьте пользователей в настройках, чтобы увидеть структуру компании.</div></div>';
      renderEmployeeDetails(null,'emp-details','employees');
      return;
    }
    tree.className='emp-tree';
    tree.innerHTML=buildEmployeesTree(users,{detailsId:'emp-details',mode:'employees'});
    selectEmployeeNode(empDefaultUserId(users),'emp-details','employees');
  }catch(e){toast(e.message,'err');}
}

var employeeTreeState={};

function empSortUsers(users){
  return (users||[]).slice().sort(function(a,b){
    return String(a.full_name||a.username||'').localeCompare(String(b.full_name||b.username||''),'ru',{sensitivity:'base'});
  });
}

function empText(value,fallback){
  var text=String(value||'').trim();
  return text||fallback||'—';
}

function empContactLine(icon,value,label){
  if(!value) return '';
  return '<span class="emp-contact"><span>'+icon+'</span><span>'+esc(value)+'</span></span>';
}

function empInitials(name){
  return String(name||'Сотрудник').split(/\s+/).filter(Boolean).slice(0,2).map(function(part){return part.charAt(0).toUpperCase();}).join('')||'С';
}

function empUserName(u){
  return String((u&&u.full_name)||(u&&u.username)||'Сотрудник').trim();
}

function empRoleTitle(role,user){
  if(user && user._tree_director) return 'Директор';
  if(role==='admin') return 'Администратор';
  if(role==='rop') return 'Руководитель отдела продаж';
  if(role==='manager') return 'Менеджер по продажам';
  if(role==='logist') return 'Логистика';
  if(role==='prorab') return 'Прораб';
  return ROLE_LABELS[role]||'Сотрудник';
}

function empIsDirector(user){
  return parseInt(user&&user.is_director,10)===1;
}

function closeEmployeeCardMenus(exceptMenu){
  document.querySelectorAll('.emp-card-actions-menu').forEach(function(menu){
    if(menu!==exceptMenu) menu.hidden=true;
  });
  document.querySelectorAll('.emp-card-menu-trigger').forEach(function(button){
    var menu=button.nextElementSibling;
    button.setAttribute('aria-expanded',menu && !menu.hidden ? 'true' : 'false');
  });
}

function toggleEmployeeCardMenu(event,button){
  event.preventDefault();
  event.stopPropagation();
  var menu=button.nextElementSibling;
  if(!menu) return;
  var shouldOpen=menu.hidden;
  closeEmployeeCardMenus(menu);
  menu.hidden=!shouldOpen;
  button.setAttribute('aria-expanded',shouldOpen?'true':'false');
}

document.addEventListener('click',function(){
  closeEmployeeCardMenus();
});
document.addEventListener('keydown',function(event){
  if(event.key==='Escape') closeEmployeeCardMenus();
});

function empCardActions(user,mode){
  if(mode!=='users') return '';
  var id=parseInt(user.id||0,10);
  var canEdit=accessCanUi('users','edit');
  var canDelete=accessCanUi('users','delete');
  if(!canEdit && !canDelete) return '';
  var items='';
  if(canEdit){
    items+='<button type="button" class="emp-card-action" onclick="event.stopPropagation();closeEmployeeCardMenus();openUserModalById('+id+')">Редактировать</button>';
    items+=empIsDirector(user)
      ? '<button type="button" class="emp-card-action" disabled>Директор назначен</button>'
      : '<button type="button" class="emp-card-action" onclick="event.stopPropagation();closeEmployeeCardMenus();setDirectorById('+id+')">Назначить директором</button>';
  }
  if(canDelete){
    items+='<button type="button" class="emp-card-action emp-card-action-danger" onclick="event.stopPropagation();closeEmployeeCardMenus();deleteUserById('+id+')">Удалить</button>';
  }
  return '<div class="emp-card-menu-wrap">'+
    '<button type="button" class="emp-card-menu-trigger" aria-label="Действия с пользователем" aria-haspopup="menu" aria-expanded="false" onclick="toggleEmployeeCardMenu(event,this)">⋮</button>'+
    '<div class="emp-card-actions-menu" role="menu" hidden onclick="event.stopPropagation()">'+items+'</div>'+
  '</div>';
}

function empCard(u,compact,detailsId,mode,extraClass){
  var name=String(u.full_name||u.username||'Сотрудник').trim();
  var initials=empInitials(name);
  var role=u.role||'manager';
  var contacts=[
    empContactLine('✉',u.email,'Почта'),
    empContactLine('☎',u.phone,'Телефон'),
    empContactLine('◇',u.telegram,'Телеграм')
  ].filter(Boolean).join('');
  return '<article class="emp-card '+(compact?'emp-card-compact':'')+' '+esc(extraClass||'')+'" data-emp-detail="'+esc(detailsId||'emp-details')+'" data-user-id="'+esc(u.id)+'" data-is-director="'+(empIsDirector(u)?'1':'0')+'" onclick="selectEmployeeNode('+parseInt(u.id||0,10)+',\''+esc(detailsId||'emp-details')+'\',\''+esc(mode||'employees')+'\')">'+
    empCardActions(u,mode)+
    '<div class="emp-avatar-wrap"><div class="emp-avatar r-'+esc(role)+'">'+esc(initials)+'</div><span class="emp-status-dot"></span></div>'+
    '<div class="emp-card-body">'+
      '<div class="emp-name">'+esc(name)+'</div>'+
      '<div class="emp-position">'+esc(empRoleTitle(role,u))+'</div>'+
      (contacts?'<div class="emp-contacts">'+contacts+'</div>':'<div class="emp-muted">Контакты не заполнены</div>')+
    '</div>'+
  '</article>';
}

function empColumn(icon,title,count,users,emptyText,opts){
  opts=opts||{};
  var items=empSortUsers(users).map(function(u){
    return empCard(u,true,opts.detailsId,opts.mode,'');
  }).join('');
  if(!items) items='<div class="emp-empty-branch">'+esc(emptyText||'Нет сотрудников')+'</div>';
  var addButton=(opts.mode==='users' && accessCanUi('users','create'))
    ? '<button class="emp-add-inline" onclick="openUserModal(null,null,\''+esc(opts.role||'manager')+'\')">＋ Добавить сотрудника</button>'
    : '';
  return '<section class="emp-role-column">'+
    '<div class="emp-role-head"><div><span class="emp-role-icon">'+icon+'</span><span>'+esc(title)+'</span></div><b>'+parseInt(count||0,10)+'</b></div>'+
    '<div class="emp-role-list">'+items+'</div>'+
    addButton+
  '</section>';
}

function empPickTopUser(byRole,users){
  var director=empSortUsers(users||[]).find(empIsDirector);
  if(director) return director;
  var admins=empSortUsers(byRole.admin||[]);
  return admins.find(function(u){return String(u.username||'').toLowerCase()==='admin';})||admins[0]||empSortUsers(byRole.rop||[])[0]||null;
}

function empDefaultUserId(users){
  var data=buildEmployeeTreeData(users||[]);
  var user=empPickTopUser(data.byRole,users||[]);
  return user ? user.id : 0;
}

function buildEmployeeTreeData(users){
  var byRole={admin:[],rop:[],manager:[],logist:[],prorab:[],other:[]};
  var byId={};
  (users||[]).forEach(function(u){
    byId[parseInt(u.id,10)||0]=u;
    if(byRole[u.role]) byRole[u.role].push(u); else byRole.other.push(u);
  });
  return {byRole:byRole,byId:byId};
}

function buildEmployeesTree(users,opts){
  opts=opts||{};
  var detailsId=opts.detailsId||'emp-details';
  var mode=opts.mode||'employees';
  var data=buildEmployeeTreeData(users);
  var byRole=data.byRole;
  var byId=data.byId;
  employeeTreeState[detailsId]={users:users||[],byId:byId,byRole:byRole,mode:mode};
  var topUser=empPickTopUser(byRole,users||[]);
  (users||[]).forEach(function(user){user._tree_director=false;});
  if(topUser) topUser._tree_director=true;
  var topHtml=topUser
    ? empCard(topUser,false,detailsId,mode,'emp-lead-card')
    : '<div class="emp-empty-branch">Руководитель не выбран</div>';
  var topUserId=parseInt(topUser&&topUser.id,10)||0;
  function withoutTopUser(list){
    return topUserId ? list.filter(function(u){return parseInt(u.id,10)!==topUserId;}) : list;
  }
  var managerList=withoutTopUser(byRole.manager);
  var ropList=withoutTopUser(byRole.rop);
  var logistList=withoutTopUser(byRole.logist);
  var prorabList=withoutTopUser(byRole.prorab);
  var adminList=withoutTopUser(byRole.admin);
  var columns=[
    empColumn('🛒','Продажи',byRole.manager.length,managerList,'Менеджеры не добавлены',{detailsId:detailsId,mode:mode,role:'manager'}),
    empColumn('◎','РОП',byRole.rop.length,ropList,'РОП не добавлены',{detailsId:detailsId,mode:mode,role:'rop'}),
    empColumn('▣','Логистика',byRole.logist.length,logistList,'Логисты не добавлены',{detailsId:detailsId,mode:mode,role:'logist'}),
    empColumn('⚒','Прорабы',byRole.prorab.length,prorabList,'Прорабы не добавлены',{detailsId:detailsId,mode:mode,role:'prorab'}),
    empColumn('◇','Администраторы',byRole.admin.length,adminList,'Администраторы не добавлены',{detailsId:detailsId,mode:mode,role:'admin'})
  ];
  if(byRole.other.length){
    columns.push(empColumn('•','Другие',byRole.other.length,byRole.other,'Нет сотрудников',{detailsId:detailsId,mode:mode,role:'manager'}));
  }
  return '<div class="emp-board">'+
    '<div class="emp-lead-row">'+topHtml+'</div>'+
    '<div class="emp-connector"><span></span></div>'+
    '<div class="emp-role-columns">'+columns.join('')+'</div>'+
  '</div>';
}

function selectEmployeeNode(id,detailsId,mode){
  detailsId=detailsId||'emp-details';
  var state=employeeTreeState[detailsId]||{};
  var user=(state.byId||{})[parseInt(id,10)||0]||null;
  document.querySelectorAll('.emp-card[data-emp-detail="'+detailsId+'"]').forEach(function(card){
    card.classList.toggle('active',parseInt(card.getAttribute('data-user-id'),10)===(parseInt(id,10)||0));
  });
  renderEmployeeDetails(user,detailsId,mode||state.mode||'employees');
}

function empManagersForUser(user,state){
  if(!user || !state || !state.byId) return [];
  if(user.role==='rop'){
    return (Array.isArray(user.manager_ids)?user.manager_ids:[]).map(function(id){return state.byId[parseInt(id,10)||0];}).filter(Boolean);
  }
  if(user.role==='manager'){
    return (state.byRole.rop||[]).filter(function(rop){
      return Array.isArray(rop.manager_ids) && rop.manager_ids.map(function(id){return parseInt(id,10)||0;}).indexOf(parseInt(user.id,10)||0)>=0;
    });
  }
  return [];
}

function empDetailRow(label,value){
  return '<div class="emp-detail-row"><span>'+esc(label)+'</span><strong>'+esc(empText(value))+'</strong></div>';
}

function empActionLabel(action){
  if(action==='create') return 'добавление';
  if(action==='edit') return 'редактирование';
  if(action==='delete') return 'удаление';
  if(action==='export') return 'экспорт';
  return action;
}

function empKanbanScopeLabel(scope){
  if(scope==='all') return 'все карточки';
  if(scope==='managed') return 'карточки команды';
  if(scope==='specific') return 'выбранные пользователи';
  return 'только свои карточки';
}

function empAccessDetails(user){
  var summary=user&&user.access_summary;
  if(!summary) return '<span class="emp-muted">Права не загружены</span>';
  var tabs=summary.tabs||[];
  var spaceKeys=Object.keys(typeof ACCESS_SPACE_LABELS!=='undefined' ? ACCESS_SPACE_LABELS : {});
  Object.keys(summary.spaces||{}).forEach(function(space){if(spaceKeys.indexOf(space)<0) spaceKeys.push(space);});
  Object.keys(summary.kanban||{}).forEach(function(space){if(spaceKeys.indexOf(space)<0) spaceKeys.push(space);});
  var blocks=spaceKeys.map(function(space){
    var spaceLabel=(typeof ACCESS_SPACE_LABELS!=='undefined' && ACCESS_SPACE_LABELS[space]) ? ACCESS_SPACE_LABELS[space] : space;
    var relatedTabs=(typeof ACCESS_SPACE_TABS!=='undefined' && ACCESS_SPACE_TABS[space]) ? ACCESS_SPACE_TABS[space] : [];
    var visibleTabs=relatedTabs.filter(function(tab){return tabs.indexOf(tab)>=0;});
    var actions=(summary.spaces&&summary.spaces[space]) ? summary.spaces[space] : [];
    var cfg=summary.kanban[space]||{};
    if(!visibleTabs.length && !actions.length && !cfg.scope) return '';
    var rows=[];
    if(visibleTabs.length){
      rows.push('<div class="emp-access-row"><span>Разделы</span><strong>'+visibleTabs.map(function(tab){
        return esc((typeof ACCESS_TAB_LABELS!=='undefined' && ACCESS_TAB_LABELS[tab]) ? ACCESS_TAB_LABELS[tab] : tab);
      }).join(', ')+'</strong></div>');
    }
    if(actions.length){
      rows.push('<div class="emp-access-row"><span>Действия</span><strong>'+esc(actions.map(empActionLabel).join(', '))+'</strong></div>');
    }
    if(cfg.scope){
      rows.push('<div class="emp-access-row"><span>Канбан</span><strong>'+esc(empKanbanScopeLabel(cfg.scope))+'</strong></div>');
    }
    return '<details class="emp-access-block"><summary><span>'+esc(spaceLabel)+'</span><b>'+rows.length+'</b></summary><div class="emp-access-body">'+rows.join('')+'</div></details>';
  }).filter(Boolean);
  return blocks.length ? blocks.join('') : '<span class="emp-muted">Права не назначены</span>';
}

function renderEmployeeDetails(user,detailsId,mode){
  var panel=document.getElementById(detailsId||'emp-details');
  if(!panel) return;
  if(!user){
    panel.innerHTML='<div class="emp-panel-title"><span>Информация о сотруднике</span></div><div class="emp-details-empty"><div class="ei">👤</div><div class="et">Выберите сотрудника</div><div class="es2">В боковой панели появится вся информация по выбранному человеку.</div></div>';
    return;
  }
  var state=employeeTreeState[detailsId]||{};
  var topUser=empPickTopUser((state.byRole||{}),(state.users||[]));
  user._tree_director=!!(topUser && parseInt(topUser.id,10)===(parseInt(user.id,10)||0));
  var linked=empManagersForUser(user,state);
  var linkedTitle=user.role==='rop'?'Закреплённые менеджеры':(user.role==='manager'?'Руководитель РОП':'Связи');
  var linkedHtml=linked.length
    ? linked.map(function(u){return '<span class="emp-chip">'+esc(u.full_name||u.username||'Сотрудник')+'</span>';}).join('')
    : '<span class="emp-muted">Нет связей</span>';
  var actions='';
  if(mode==='users'){
    if(accessCanUi('users','edit')) actions+='<button class="btn btn-g btn-sm" onclick="openUserModalById('+parseInt(user.id||0,10)+')">✏️ Редактировать</button>';
    if(accessCanUi('users','delete')) actions+='<button class="btn btn-rd btn-sm" onclick="deleteUserById('+parseInt(user.id||0,10)+')">🗑 Удалить</button>';
  }
  var role=user.role||'manager';
  var supervisor=user.role==='manager' && linked.length ? linked.map(function(u){return u.full_name||u.username;}).join(', ') : '—';
  var accessDetails=empAccessDetails(user);
  panel.innerHTML=
    '<div class="emp-panel-title"><span>Информация о сотруднике</span></div>'+
    '<div class="emp-details-top">'+
      '<div class="emp-details-photo"><div class="emp-avatar emp-details-avatar r-'+esc(role)+'">'+esc(empInitials(user.full_name||user.username))+'</div><span class="emp-status-dot"></span></div>'+
      '<div><div class="emp-details-name">'+esc(user.full_name||user.username||'Сотрудник')+'</div><span class="urole r-'+esc(role)+'">'+esc(ROLE_LABELS[role]||role||'Роль')+'</span></div>'+
    '</div>'+
    '<div class="emp-detail-grid">'+
      empDetailRow('Должность',empRoleTitle(role,user))+
      empDetailRow('Роль',ROLE_LABELS[role]||role)+
      empDetailRow('Руководитель',supervisor)+
      empDetailRow('Логин',user.username)+
      empDetailRow('Телефон',user.phone)+
      empDetailRow('Email',user.email)+
      empDetailRow('Телеграм',user.telegram)+
      empDetailRow('Дата создания',user.created_at?fmtDate(user.created_at):'')+
    '</div>'+
    '<div class="emp-detail-section"><div class="emp-detail-section-title">Права доступа</div><div class="emp-access-list">'+(accessDetails||'<span class="emp-muted">Не назначены</span>')+'</div></div>'+
    '<div class="emp-detail-section"><div class="emp-detail-section-title">'+esc(linkedTitle)+'</div><div class="emp-chip-row">'+linkedHtml+'</div></div>'+
    '<div class="emp-detail-section"><div class="emp-status-line"><span></span><strong>Активен</strong></div></div>'+
    (actions?'<div class="emp-detail-actions">'+actions+'</div>':'');
}


