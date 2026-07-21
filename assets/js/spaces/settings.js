function getSettingsSectionName(id){
  var sec=(allSecs||[]).find(function(x){return String(x.id)===String(id);});
  return sec&&sec.name ? sec.name : ('#'+id);
}

function renderSettingsSupplierSections(selectedIds){
  var wrap=document.getElementById('settings-supplier-sections');
  if(!wrap) return;
  selectedIds=(selectedIds||[]).map(String);
  wrap.innerHTML=(allSecs||[]).map(function(sec){
    var checked=selectedIds.indexOf(String(sec.id))>=0 ? ' checked' : '';
    return '<label class="kp-check-item"><input type="checkbox" value="'+sec.id+'"'+checked+'> <span>'+esc((sec.name||'Без названия')+' / '+(sec.category_name||'—'))+'</span></label>';
  }).join('');
}

var settingsGroupsOpenCategories={};
var settingsGroupsOpenSections={};
var settingsGroupsQuery='';
var settingsSuppliersOpenCategories={};
var settingsSuppliersOpenSections={};
var settingsSuppliersQuery='';

function settingsGroupsWord(value,one,few,many){
  var number=Math.abs(parseInt(value,10)||0)%100;
  var last=number%10;
  if(number>10 && number<20) return many;
  if(last===1) return one;
  if(last>=2 && last<=4) return few;
  return many;
}

function getSettingsGroupCategories(){
  return (allCats||[]).filter(function(category){
    return category && category.code;
  });
}

function getSettingsGroupsForSection(sectionId){
  return (allGroups||[]).filter(function(group){
    return String(group.section_id)===String(sectionId);
  }).sort(function(a,b){
    var sortDiff=(parseInt(a.sort_order,10)||0)-(parseInt(b.sort_order,10)||0);
    return sortDiff || String(a.name||'').localeCompare(String(b.name||''),'ru');
  });
}

function toggleSettingsGroupCategory(categoryId){
  settingsGroupsOpenCategories[categoryId]=!settingsGroupsOpenCategories[categoryId];
  renderSettingsGroups();
}

function toggleSettingsGroupSection(sectionId){
  settingsGroupsOpenSections[sectionId]=!settingsGroupsOpenSections[sectionId];
  renderSettingsGroups();
}

function filterSettingsGroups(value){
  settingsGroupsQuery=String(value||'').trim().toLocaleLowerCase('ru');
  renderSettingsGroups();
}

function collapseAllSettingsGroups(){
  settingsGroupsOpenCategories={};
  settingsGroupsOpenSections={};
  var search=document.getElementById('settings-groups-search');
  if(search) search.value='';
  settingsGroupsQuery='';
  renderSettingsGroups();
}

function renderSettingsGroupRow(group,sectionId){
  var canEdit=accessCanUi('settings','edit');
  var canDelete=accessCanUi('settings','delete');
  return '<div class="settings-group-row" data-group-id="'+group.id+'">'+
    '<div class="settings-group-main">'+
      (canEdit
        ? '<input id="settings-group-name-'+group.id+'" class="finp" value="'+esc(group.name||'')+'" aria-label="Название группы">'
        : '<div class="settings-group-name">'+esc(group.name||'Без названия')+'</div>')+
    '</div>'+
    '<div class="settings-group-sort">'+
      (canEdit
        ? '<input id="settings-group-sort-'+group.id+'" class="finp" type="number" min="0" step="1" value="'+(parseInt(group.sort_order,10)||0)+'" aria-label="Сортировка">'
        : '<span>№ '+(parseInt(group.sort_order,10)||0)+'</span>')+
    '</div>'+
    '<div class="settings-group-actions">'+
      (canEdit?'<button class="btn btn-gr btn-sm" type="button" onclick="saveSettingsGroup('+group.id+','+sectionId+')" title="Сохранить">✓</button>':'')+
      (canDelete?'<button class="btn btn-rd btn-sm" type="button" onclick="deleteSettingsGroup('+group.id+')" title="Удалить">Удалить</button>':'')+
    '</div>'+
  '</div>';
}

function renderSettingsGroupSection(section,query,forceOpen){
  var groups=getSettingsGroupsForSection(section.id);
  var sectionText=String(section.name||'').toLocaleLowerCase('ru');
  var sectionMatches=!query || sectionText.indexOf(query)>=0;
  var visibleGroups=query ? groups.filter(function(group){
    return String(group.name||'').toLocaleLowerCase('ru').indexOf(query)>=0;
  }) : groups;
  if(query && !sectionMatches && !visibleGroups.length) return '';
  if(query && sectionMatches) visibleGroups=groups;

  var isOpen=forceOpen || !!settingsGroupsOpenSections[section.id];
  var canCreate=accessCanUi('settings','create');
  var body='';
  if(isOpen){
    if(canCreate){
      body+='<div class="settings-group-add-row">'+
        '<input id="settings-group-new-name-'+section.id+'" class="finp" placeholder="Название новой группы" aria-label="Название новой группы">'+
        '<input id="settings-group-new-sort-'+section.id+'" class="finp" type="number" min="0" step="1" value="'+getNextSettingsGroupSortOrder(section.id)+'" aria-label="Сортировка новой группы">'+
        '<button class="btn btn-p" type="button" onclick="saveSettingsGroup(0,'+section.id+')">Добавить</button>'+
      '</div>';
    }
    body+=visibleGroups.length
      ? visibleGroups.map(function(group){return renderSettingsGroupRow(group,section.id);}).join('')
      : '<div class="settings-groups-empty">В этом разделе пока нет групп</div>';
  }

  return '<div class="settings-groups-section'+(isOpen?' open':'')+'" data-section-id="'+section.id+'">'+
    '<button class="settings-groups-section-toggle" type="button" onclick="toggleSettingsGroupSection('+section.id+')" aria-expanded="'+(isOpen?'true':'false')+'">'+
      '<span class="settings-groups-chevron">›</span>'+
      '<span class="settings-groups-section-name">'+esc(section.name||'Без названия')+'</span>'+
      '<span class="settings-groups-count">'+groups.length+' '+settingsGroupsWord(groups.length,'группа','группы','групп')+'</span>'+
    '</button>'+
    (isOpen?'<div class="settings-groups-section-body">'+body+'</div>':'')+
  '</div>';
}

function renderSettingsGroups(){
  var wrap=document.getElementById('settings-groups-list');
  if(!wrap) return;
  var query=settingsGroupsQuery;
  var categories=getSettingsGroupCategories();
  if(!categories.length){
    wrap.innerHTML='<div class="es">Категории «Оборудование» и «Материалы» не найдены</div>';
    return;
  }
  wrap.innerHTML=categories.map(function(category){
    var sections=(allSecs||[]).filter(function(section){
      return String(section.category_id)===String(category.id);
    });
    var categoryMatches=!query || String(category.name||'').toLocaleLowerCase('ru').indexOf(query)>=0;
    var renderedSections=sections.map(function(section){
      return renderSettingsGroupSection(section,query,!!query);
    }).filter(Boolean);
    if(query && !categoryMatches && !renderedSections.length) return '';
    if(query && categoryMatches){
      renderedSections=sections.map(function(section){
        return renderSettingsGroupSection(section,'',true);
      });
    }
    var groupCount=sections.reduce(function(total,section){
      return total+getSettingsGroupsForSection(section.id).length;
    },0);
    var isOpen=!!query || !!settingsGroupsOpenCategories[category.id];
    return '<section class="settings-groups-category'+(isOpen?' open':'')+'" data-category-id="'+category.id+'">'+
      '<button class="settings-groups-category-toggle" type="button" onclick="toggleSettingsGroupCategory('+category.id+')" aria-expanded="'+(isOpen?'true':'false')+'">'+
        '<span class="settings-groups-chevron">›</span>'+
        '<span class="settings-groups-category-title">'+esc(category.name||'Без названия')+'</span>'+
        '<span class="settings-groups-category-meta">'+sections.length+' '+settingsGroupsWord(sections.length,'раздел','раздела','разделов')+' · '+groupCount+' '+settingsGroupsWord(groupCount,'группа','группы','групп')+'</span>'+
      '</button>'+
      (isOpen?'<div class="settings-groups-category-body">'+(renderedSections.length?renderedSections.join(''):'<div class="settings-groups-empty">Разделы или группы не найдены</div>')+'</div>':'')+
    '</section>';
  }).filter(Boolean).join('') || '<div class="es">Ничего не найдено</div>';
}

async function loadSettingsGroups(){
  try{
    if(!allCats.length || !allSecs.length) await loadMeta();
    renderSettingsGroups();
  }catch(e){toast(e.message,'err');}
}

async function saveSettingsGroup(id,sectionId){
  id=parseInt(id||'0',10)||0;
  sectionId=parseInt(sectionId||'0',10)||0;
  var prefix=id?'settings-group-':'settings-group-new-';
  var nameEl=document.getElementById(prefix+'name-'+(id||sectionId));
  var sortEl=document.getElementById(prefix+'sort-'+(id||sectionId));
  var name=String(nameEl&&nameEl.value||'').trim();
  var sortOrder=parseInt(sortEl&&sortEl.value||'0',10)||0;
  if(!name){toast('Укажите название группы','err');return;}
  try{
    await api('catalog.php',{action:'save_group',id:id,name:name,section_id:sectionId,sort_order:sortOrder});
    await loadMeta();
    settingsGroupsOpenCategories[((allSecs||[]).find(function(section){return String(section.id)===String(sectionId);})||{}).category_id]=true;
    settingsGroupsOpenSections[sectionId]=true;
    renderSettingsGroups();
    toast('Группа сохранена');
  }catch(e){toast(e.message,'err');}
}

function deleteSettingsGroup(id){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  showConfirmDialog({title:'Удалить группу',message:'Удалить группу?',icon:'🗑️',confirmText:'Удалить',confirmClass:'btn-rd'}).then(async function(ok){
    if(!ok) return;
    try{
      await api('catalog.php',{action:'delete_group',id:id});
      await loadMeta();
      renderSettingsGroups();
      toast('Группа удалена');
    }catch(e){toast(e.message,'err');}
  });
}

function collectSettingsSupplierSectionIds(){
  return Array.prototype.map.call(document.querySelectorAll('#settings-supplier-sections input[type="checkbox"]:checked'), function(inp){
    return parseInt(inp.value,10)||0;
  }).filter(Boolean);
}

function resetSettingsSupplierForm(){
  document.getElementById('settings-supplier-id').value='0';
  document.getElementById('settings-supplier-name').value='';
  renderSettingsSupplierSections([]);
}

function fillSettingsSupplierForm(supplier){
  document.getElementById('settings-supplier-id').value=supplier.id||0;
  document.getElementById('settings-supplier-name').value=supplier.name||'';
  var sectionIds=String(supplier.section_ids||'').split(',').map(function(v){return v.trim();}).filter(Boolean);
  renderSettingsSupplierSections(sectionIds);
}

var settingsUnitsCache=[];

async function loadSettingsUnitsData(){
  settingsUnitsCache=await api('catalog.php?action=units').catch(function(){return [];});
  return settingsUnitsCache;
}

function renderSettingsUnits(){
  var wrap=document.getElementById('settings-units-list');
  if(!wrap) return;
  if(!settingsUnitsCache.length){
    wrap.innerHTML='<div class="es">Единицы измерения не найдены</div>';
    return;
  }
  wrap.innerHTML=settingsUnitsCache.map(function(unit){
    var isDefault=parseInt(unit.is_default,10)===1;
    return '<div class="ccard">'+
      '<div class="ch">'+
        '<div><div class="ctitle">'+esc(unit.name)+'</div><div class="cmark">Сортировка: '+esc(unit.sort_order||0)+'</div></div>'+
        (isDefault?'<span class="sbadge b-yes">По умолчанию</span>':'')+
      '</div>'+
      '<div class="cmeta"><div><div class="mlb">Статус</div><div class="mvl">'+(isDefault?'Основная':'Обычная')+'</div></div></div>'+
      '<div class="cft">'+
        (accessCanUi('settings','delete')?'<button class="btn btn-rd btn-sm" onclick="deleteSettingsUnit('+unit.id+')">🗑 Удалить</button>':'')+
      '</div>'+
    '</div>';
  }).join('');
}

async function loadSettingsUnits(){
  try{
    if(!settingsUnitsCache.length) await loadSettingsUnitsData();
    renderSettingsUnits();
  }catch(e){toast(e.message,'err');}
}

async function saveSettingsUnit(){
  var name=(document.getElementById('settings-unit-name').value||'').trim();
  var sortOrder=parseInt((document.getElementById('settings-unit-sort').value||'0'),10)||0;
  var isDefault=!!(document.getElementById('settings-unit-default')||{}).checked;
  if(!name){toast('Укажите название единицы','err');return;}
  try{
    await api('catalog.php',{action:'save_unit',name:name,sort_order:sortOrder,is_default:isDefault?1:0});
    await loadMeta();
    await loadSettingsUnitsData();
    renderSettingsUnits();
    document.getElementById('settings-unit-name').value='';
    document.getElementById('settings-unit-sort').value='0';
    document.getElementById('settings-unit-default').checked=false;
    toast('Единица сохранена');
  }catch(e){toast(e.message,'err');}
}

function deleteSettingsUnit(id){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  showConfirmDialog({title:'Удалить единицу',message:'Удалить единицу измерения?',icon:'🗑️',confirmText:'Удалить',confirmClass:'btn-rd'}).then(async function(ok){
    if(!ok) return;
    try{
      await api('catalog.php',{action:'delete_unit',id:id});
      await loadMeta();
      await loadSettingsUnitsData();
      renderSettingsUnits();
      toast('Единица удалена');
    }catch(e){toast(e.message,'err');}
  });
}

function accessGetSelectedRole(){
  var sel=document.getElementById('settings-access-role');
  return sel ? sel.value : '';
}

function accessRenderSpecificUsers(workspaceKey, selectedIds){
  var list=(ACCESS_POLICY_USERS||[]).map(function(u){
    var checked=(selectedIds||[]).map(String).indexOf(String(u.id))>=0 ? ' checked' : '';
    return '<label class="kp-check-item"><input type="checkbox" data-access-users="'+workspaceKey+'" value="'+u.id+'"'+checked+'> <span>'+esc((u.full_name||u.username||('ID '+u.id))+' ['+(ROLE_LABELS[u.role]||u.role)+']')+'</span></label>';
  }).join('');
  return '<div id="access-users-'+workspaceKey+'" class="kp-check-grid" style="display:none;margin-top:10px">'+(list||'<div class="es">Нет пользователей</div>')+'</div>';
}

function accessKanbanScopeChanged(workspaceKey){
  var sel=document.querySelector('[data-access-scope="'+workspaceKey+'"]');
  var box=document.getElementById('access-users-'+workspaceKey);
  if(!sel || !box) return;
  box.style.display=sel.value==='specific' ? '' : 'none';
}

function toggleAccessSettingsBlock(spaceKey){
  var body=document.getElementById('access-space-body-'+spaceKey);
  var marker=document.getElementById('access-space-toggle-'+spaceKey);
  if(!body || !marker) return;
  var collapsed=body.style.display==='none';
  body.style.display=collapsed ? '' : 'none';
  marker.textContent=collapsed ? '▾' : '▸';
  ACCESS_BLOCK_COLLAPSE_STATE[spaceKey]=collapsed;
}

function accessSpaceVisibilityChanged(spaceKey){
  var inp=document.querySelector('[data-access-space-visible="'+spaceKey+'"]');
  var body=document.getElementById('access-space-body-'+spaceKey);
  if(!body) return;
  body.style.display=(inp && inp.checked)?'':'none';
}

function accessSpaceVisibleByPolicy(spaceKey, policy){
  var tabs=ACCESS_SPACE_TABS[spaceKey]||[];
  if(!tabs.length) return true;
  return tabs.some(function(tabKey){
    return !!(policy.tabs&&policy.tabs[tabKey]);
  });
}

function accessRenderSpaceTabs(spaceKey, policy, role){
  var tabs=ACCESS_SPACE_TABS[spaceKey]||[];
  return tabs.map(function(key){
    var checked=policy.tabs&&policy.tabs[key] ? ' checked' : '';
    var disabled=(role==='admin' || key==='settings_access') ? ' disabled' : '';
    return '<label class="kp-check-item"><input type="checkbox" data-access-tab="'+key+'"'+checked+disabled+'> <span>'+esc(ACCESS_TAB_LABELS[key])+'</span></label>';
  }).join('');
}

function accessKanbanColumnOptions(spaceKey){
  if(spaceKey==='orders'){
    return Object.keys(STATUS_BADGE||{}).map(function(status){
      return {value:status,label:status};
    });
  }
  if(spaceKey==='kp'){
    return getUnifiedQuoteKanbanColumns().map(function(column){
      var mode=kpNormalizeQuoteMode(column.mode);
      return {
        value:mode+'::'+column.status,
        label:(mode==='pkp' ? 'ПКП · ' : 'КП · ')+column.status
      };
    });
  }
  return [];
}

function accessRenderKanbanColumns(spaceKey, selectedColumns, role){
  var options=accessKanbanColumnOptions(spaceKey);
  if(!options.length) return '';
  selectedColumns=Array.isArray(selectedColumns) ? selectedColumns.map(String) : [];
  var allSelected=!selectedColumns.length;
  return '<div class="field"><label>Видимость столбцов канбана</label>'+
    '<div class="kp-check-grid">'+
      '<label class="kp-check-item"><input type="checkbox" data-access-columns-all="'+spaceKey+'" onchange="accessKanbanColumnsAllChanged(\''+spaceKey+'\')"'+(allSelected?' checked':'')+(role==='admin'?' disabled':'')+'> <span>Все столбцы</span></label>'+
      options.map(function(opt){
        var checked=allSelected || selectedColumns.indexOf(String(opt.value))>=0;
        return '<label class="kp-check-item"><input type="checkbox" data-access-column="'+spaceKey+'" value="'+esc(opt.value)+'"'+(checked?' checked':'')+(allSelected?' disabled':'')+(role==='admin'?' disabled':'')+'> <span>'+esc(opt.label)+'</span></label>';
      }).join('')+
    '</div></div>';
}

function accessKanbanColumnsAllChanged(spaceKey){
  var all=document.querySelector('[data-access-columns-all="'+spaceKey+'"]');
  var checked=!!(all&&all.checked);
  document.querySelectorAll('[data-access-column="'+spaceKey+'"]').forEach(function(inp){
    inp.disabled=checked;
    inp.checked=checked ? true : inp.checked;
  });
}

function renderSettingsAccess(){
  var role=accessGetSelectedRole();
  var wrap=document.getElementById('settings-access-editor');
  if(!wrap) return;
  var policy=ACCESS_ROLE_POLICIES[role];
  if(!policy){
    wrap.innerHTML='<div class="es">Нет данных для роли</div>';
    return;
  }
  var spacesHtml=['catalog','orders','kp','company','documents','settings'].map(function(space){
    var cfg=(policy.spaces&&policy.spaces[space])||{};
    var visible=accessSpaceVisibleByPolicy(space, policy);
    var hasKanban=!!ACCESS_KANBAN_LABELS[space];
    var kanbanCfg=(policy.kanban&&policy.kanban[space])||{scope:'own',user_ids:[]};
    var expanded=ACCESS_BLOCK_COLLAPSE_STATE.hasOwnProperty(space) ? !!ACCESS_BLOCK_COLLAPSE_STATE[space] : true;
    return '<div class="kp-section-card" style="padding:16px;margin-bottom:14px">'+
      '<div class="frow" style="align-items:center;flex-wrap:nowrap;gap:10px;margin-bottom:12px">'+
        '<div style="display:flex;align-items:center;gap:10px;min-width:0;cursor:pointer;flex:1 1 auto" onclick="toggleAccessSettingsBlock(\''+space+'\')">'+
          '<div id="access-space-toggle-'+space+'" style="width:18px;flex:0 0 18px;color:var(--tx2);font-size:.9rem;text-align:center">'+(expanded?'▾':'▸')+'</div>'+
          '<div class="kp-section-title" style="margin:0;min-width:0">'+esc(ACCESS_SPACE_LABELS[space])+'</div>'+
        '</div>'+
        '<label class="kp-check-item" style="white-space:nowrap;flex:0 0 auto"><input type="checkbox" data-access-space-visible="'+space+'" onchange="accessSpaceVisibilityChanged(\''+space+'\')"'+(visible?' checked':'')+(role==='admin'?' disabled':'')+'> <span>Видимость пространства</span></label>'+
      '</div>'+
      '<div id="access-space-body-'+space+'" style="'+((visible&&expanded)?'':'display:none')+'">'+
        '<div class="field"><label>Видимость вкладок пространства</label><div class="kp-check-grid">'+accessRenderSpaceTabs(space, policy, role)+'</div></div>'+
        '<div class="field"><label>Действия в пространстве</label><div class="kp-check-grid">'+
          '<label class="kp-check-item"><input type="checkbox" data-access-space="'+space+'" data-access-action="create"'+(cfg.create?' checked':'')+(role==='admin'?' disabled':'')+'> <span>Добавление</span></label>'+
          '<label class="kp-check-item"><input type="checkbox" data-access-space="'+space+'" data-access-action="edit"'+(cfg.edit?' checked':'')+(role==='admin'?' disabled':'')+'> <span>Редактирование</span></label>'+
          '<label class="kp-check-item"><input type="checkbox" data-access-space="'+space+'" data-access-action="delete"'+(cfg.delete?' checked':'')+(role==='admin'?' disabled':'')+'> <span>Удаление</span></label>'+
          (space==='catalog' ? '<label class="kp-check-item"><input type="checkbox" data-access-space="'+space+'" data-access-action="export"'+(cfg.export?' checked':'')+(role==='admin'?' disabled':'')+'> <span>Экспорт каталога</span></label>' : '')+
        '</div></div>'+
        (hasKanban
          ? '<div class="field"><label>Видимость карточек канбана</label>'+
              '<select class="finp" data-access-scope="'+space+'" onchange="accessKanbanScopeChanged(\''+space+'\')"'+(role==='admin'?' disabled':'')+'>'+
                '<option value="own"'+(kanbanCfg.scope==='own'?' selected':'')+'>Только свои</option>'+
                '<option value="all"'+(kanbanCfg.scope==='all'?' selected':'')+'>Все</option>'+
                '<option value="managed"'+(kanbanCfg.scope==='managed'?' selected':'')+'>Подчинённые</option>'+
                '<option value="specific"'+(kanbanCfg.scope==='specific'?' selected':'')+'>Конкретные пользователи</option>'+
              '</select>'+
              accessRenderSpecificUsers(space, kanbanCfg.user_ids||[])+
            '</div>'+
            accessRenderKanbanColumns(space, kanbanCfg.columns||[], role)
          : '')+
      '</div>'+
    '</div>';
  }).join('');
  wrap.innerHTML=spacesHtml;
  Object.keys(ACCESS_KANBAN_LABELS).forEach(function(space){ accessKanbanScopeChanged(space); });
}

function collectSettingsAccessPolicy(){
  var role=accessGetSelectedRole();
  var base=JSON.parse(JSON.stringify(ACCESS_ROLE_POLICIES[role]||{}));
  if(!base.tabs) base.tabs={};
  if(!base.spaces) base.spaces={};
  if(!base.kanban) base.kanban={};
  document.querySelectorAll('[data-access-tab]').forEach(function(inp){
    base.tabs[inp.getAttribute('data-access-tab')]=!!inp.checked;
  });
  Object.keys(ACCESS_SPACE_TABS).forEach(function(space){
    var visible=document.querySelector('[data-access-space-visible="'+space+'"]');
    if(!visible || visible.checked) return;
    (ACCESS_SPACE_TABS[space]||[]).forEach(function(tabKey){
      base.tabs[tabKey]=false;
    });
  });
  document.querySelectorAll('[data-access-space]').forEach(function(inp){
    var space=inp.getAttribute('data-access-space');
    var action=inp.getAttribute('data-access-action');
    if(!base.spaces[space]) base.spaces[space]={create:false,edit:false,delete:false};
    base.spaces[space][action]=!!inp.checked;
  });
  document.querySelectorAll('[data-access-scope]').forEach(function(sel){
    var space=sel.getAttribute('data-access-scope');
    if(!base.kanban[space]) base.kanban[space]={scope:'own',user_ids:[],columns:[]};
    base.kanban[space].scope=sel.value||'own';
    var ids=[];
    document.querySelectorAll('[data-access-users="'+space+'"]:checked').forEach(function(inp){
      ids.push(parseInt(inp.value,10)||0);
    });
    base.kanban[space].user_ids=ids.filter(Boolean);
    var allColumns=document.querySelector('[data-access-columns-all="'+space+'"]');
    if(allColumns && allColumns.checked){
      base.kanban[space].columns=[];
    }else{
      var cols=[];
      document.querySelectorAll('[data-access-column="'+space+'"]:checked').forEach(function(inp){
        cols.push(String(inp.value||''));
      });
      base.kanban[space].columns=cols.filter(Boolean);
    }
  });
  delete base.spaces.pkp;
  delete base.kanban.pkp;
  delete base.tabs.pkp_company;
  delete base.tabs.pkp_clients;
  delete base.tabs.pkp_list;
  return base;
}

async function loadSettingsAccess(){
  if(!CU || CU.role!=='admin'){
    var wrap=document.getElementById('settings-access-editor');
    if(wrap) wrap.innerHTML='<div class="es">Недостаточно прав</div>';
    return;
  }
  try{
    var res=await Promise.all([
      api('permissions.php?action=policies'),
      api('permissions.php?action=users')
    ]);
    ACCESS_POLICY_ROLES=(res[0]&&res[0].roles)||ACCESS_POLICY_ROLES||[];
    ACCESS_ROLE_POLICIES=(res[0]&&res[0].policies)||{};
    ACCESS_POLICY_USERS=res[1]||[];
    var sel=document.getElementById('settings-access-role');
    if(sel){
      var prev=sel.value||'manager';
      sel.innerHTML=(ACCESS_POLICY_ROLES||[]).map(function(role){
        return '<option value="'+role+'">'+esc(ROLE_LABELS[role]||role)+'</option>';
      }).join('');
      sel.value=(ACCESS_ROLE_POLICIES[prev] ? prev : ((ACCESS_POLICY_ROLES||[])[0]||'manager'));
    }
    if(!Object.keys(ACCESS_BLOCK_COLLAPSE_STATE).length){
      ['catalog','orders','kp','company','documents','settings'].forEach(function(space){ ACCESS_BLOCK_COLLAPSE_STATE[space]=true; });
    }
    renderSettingsAccess();
  }catch(e){toast(e.message,'err');}
}

async function saveSettingsAccess(){
  var role=accessGetSelectedRole();
  if(!role){toast('Выберите роль','err');return;}
  try{
    await api('permissions.php',{action:'save_policy',role:role,policy:collectSettingsAccessPolicy()});
    toast('Права доступа сохранены');
    await loadSettingsAccess();
    await loadMeta();
    renderUI();
  }catch(e){toast(e.message,'err');}
}

async function loadSettingsSuppliers(){
  try{
    if(!allSecs.length) await loadMeta();
    if(!allSuppliers.length) await loadMeta();
    renderSettingsSuppliers();
  }catch(e){toast(e.message,'err');}
}

function editSettingsSupplier(id){
  var supplier=(allSuppliers||[]).find(function(x){return String(x.id)===String(id);});
  if(!supplier) return;
  fillSettingsSupplierForm(supplier);
}

function getSettingsSupplierSectionIds(supplier){
  return String((supplier&&supplier.section_ids)||'').split(',').map(function(v){
    return parseInt(String(v).trim(),10)||0;
  }).filter(Boolean);
}

function getSettingsSuppliersForSection(sectionId){
  sectionId=parseInt(sectionId||'0',10)||0;
  return (allSuppliers||[]).filter(function(supplier){
    return getSettingsSupplierSectionIds(supplier).indexOf(sectionId)>=0;
  }).sort(function(a,b){
    var sortDiff=(parseInt(a.sort_order,10)||0)-(parseInt(b.sort_order,10)||0);
    return sortDiff || String(a.name||'').localeCompare(String(b.name||''),'ru');
  });
}

function getSettingsUnlinkedSuppliers(){
  return (allSuppliers||[]).filter(function(supplier){
    return !getSettingsSupplierSectionIds(supplier).length;
  }).sort(function(a,b){
    var sortDiff=(parseInt(a.sort_order,10)||0)-(parseInt(b.sort_order,10)||0);
    return sortDiff || String(a.name||'').localeCompare(String(b.name||''),'ru');
  });
}

function toggleSettingsSupplierCategory(categoryId){
  settingsSuppliersOpenCategories[categoryId]=!settingsSuppliersOpenCategories[categoryId];
  renderSettingsSuppliers();
}

function toggleSettingsSupplierSection(sectionId){
  settingsSuppliersOpenSections[sectionId]=!settingsSuppliersOpenSections[sectionId];
  renderSettingsSuppliers();
}

function filterSettingsSuppliers(value){
  settingsSuppliersQuery=String(value||'').trim().toLocaleLowerCase('ru');
  renderSettingsSuppliers();
}

function collapseAllSettingsSuppliers(){
  settingsSuppliersOpenCategories={};
  settingsSuppliersOpenSections={};
  var search=document.getElementById('settings-suppliers-search');
  if(search) search.value='';
  settingsSuppliersQuery='';
  renderSettingsSuppliers();
}

function getNextSettingsSupplierSortOrder(sectionId){
  var maxSort=0;
  getSettingsSuppliersForSection(sectionId).forEach(function(supplier){
    var sortVal=parseInt(supplier && supplier.sort_order!=null ? supplier.sort_order : '0',10);
    if(!isNaN(sortVal) && sortVal>maxSort) maxSort=sortVal;
  });
  return maxSort+1;
}

function renderSettingsSupplierRow(supplier,sectionId){
  var canEdit=accessCanUi('settings','edit');
  var canDelete=accessCanUi('settings','delete');
  var safeSectionId=parseInt(sectionId||'0',10)||0;
  var suffix=supplier.id+'-'+safeSectionId;
  return '<div class="settings-group-row settings-supplier-row" data-supplier-id="'+supplier.id+'">'+
    '<div class="settings-group-main">'+
      (canEdit
        ? '<input id="settings-supplier-row-name-'+suffix+'" class="finp" value="'+esc(supplier.name||'')+'" aria-label="Название поставщика">'
        : '<div class="settings-group-name">'+esc(supplier.name||'Без названия')+'</div>')+
    '</div>'+
    '<div class="settings-group-sort">'+
      (canEdit
        ? '<input id="settings-supplier-row-sort-'+suffix+'" class="finp" type="number" min="0" step="1" value="'+(parseInt(supplier.sort_order,10)||0)+'" aria-label="Сортировка">'
        : '<span>№ '+(parseInt(supplier.sort_order,10)||0)+'</span>')+
    '</div>'+
    '<div class="settings-group-actions">'+
      (canEdit?'<button class="btn btn-gr btn-sm" type="button" onclick="saveSettingsSupplierInSection('+supplier.id+','+safeSectionId+')" title="Сохранить">✓</button>':'')+
      (canDelete?'<button class="btn btn-rd btn-sm" type="button" onclick="deleteSettingsSupplier('+supplier.id+')" title="Удалить">Удалить</button>':'')+
    '</div>'+
  '</div>';
}

function renderSettingsSupplierSection(section,query,forceOpen){
  var suppliers=getSettingsSuppliersForSection(section.id);
  var sectionText=String(section.name||'').toLocaleLowerCase('ru');
  var sectionMatches=!query || sectionText.indexOf(query)>=0;
  var visibleSuppliers=query ? suppliers.filter(function(supplier){
    return String(supplier.name||'').toLocaleLowerCase('ru').indexOf(query)>=0;
  }) : suppliers;
  if(query && !sectionMatches && !visibleSuppliers.length) return '';
  if(query && sectionMatches) visibleSuppliers=suppliers;

  var isOpen=forceOpen || !!settingsSuppliersOpenSections[section.id];
  var canCreate=accessCanUi('settings','create');
  var body='';
  if(isOpen){
    if(canCreate){
      body+='<div class="settings-group-add-row settings-supplier-add-row">'+
        '<input id="settings-supplier-new-name-'+section.id+'" class="finp" placeholder="Название нового поставщика" aria-label="Название нового поставщика">'+
        '<input id="settings-supplier-new-sort-'+section.id+'" class="finp" type="number" min="0" step="1" value="'+getNextSettingsSupplierSortOrder(section.id)+'" aria-label="Сортировка нового поставщика">'+
        '<button class="btn btn-p" type="button" onclick="saveSettingsSupplierInSection(0,'+section.id+')">Добавить</button>'+
      '</div>';
    }
    body+=visibleSuppliers.length
      ? visibleSuppliers.map(function(supplier){return renderSettingsSupplierRow(supplier,section.id);}).join('')
      : '<div class="settings-groups-empty">В этом разделе пока нет поставщиков</div>';
  }

  return '<div class="settings-groups-section'+(isOpen?' open':'')+'" data-section-id="'+section.id+'">'+
    '<button class="settings-groups-section-toggle" type="button" onclick="toggleSettingsSupplierSection('+section.id+')" aria-expanded="'+(isOpen?'true':'false')+'">'+
      '<span class="settings-groups-chevron">›</span>'+
      '<span class="settings-groups-section-name">'+esc(section.name||'Без названия')+'</span>'+
      '<span class="settings-groups-count">'+suppliers.length+' '+settingsGroupsWord(suppliers.length,'поставщик','поставщика','поставщиков')+'</span>'+
    '</button>'+
    (isOpen?'<div class="settings-groups-section-body">'+body+'</div>':'')+
  '</div>';
}

async function saveSettingsSupplier(){
  var id=parseInt(document.getElementById('settings-supplier-id').value||'0',10)||0;
  var name=(document.getElementById('settings-supplier-name').value||'').trim();
  if(!name){toast('Укажите название поставщика','err');return;}
  try{
    await api('catalog.php',{
      action:'save_supplier',
      id:id,
      name:name,
      section_ids:collectSettingsSupplierSectionIds()
    });
    await loadMeta();
    renderSettingsSuppliers();
    neUpdateSuppliers();
    resetSettingsSupplierForm();
    toast('Поставщик сохранён');
  }catch(e){toast(e.message,'err');}
}

async function saveSettingsSupplierInSection(id,sectionId){
  id=parseInt(id||'0',10)||0;
  sectionId=parseInt(sectionId||'0',10)||0;
  var suffix=id ? (id+'-'+sectionId) : sectionId;
  var nameEl=document.getElementById(id?'settings-supplier-row-name-'+suffix:'settings-supplier-new-name-'+suffix);
  var sortEl=document.getElementById(id?'settings-supplier-row-sort-'+suffix:'settings-supplier-new-sort-'+suffix);
  var name=String(nameEl&&nameEl.value||'').trim();
  var sortOrder=parseInt(sortEl&&sortEl.value||'0',10)||0;
  if(!name){toast('Укажите название поставщика','err');return;}
  if(!id){
    var existingSupplier=(allSuppliers||[]).find(function(supplier){
      return String(supplier.name||'').trim().toLocaleLowerCase('ru')===name.toLocaleLowerCase('ru');
    });
    if(existingSupplier) id=parseInt(existingSupplier.id,10)||0;
  }
  var sectionIds=sectionId ? [sectionId] : [];
  if(id){
    var supplier=(allSuppliers||[]).find(function(x){return String(x.id)===String(id);});
    sectionIds=getSettingsSupplierSectionIds(supplier);
    if(sectionId && sectionIds.indexOf(sectionId)<0) sectionIds.push(sectionId);
  }
  try{
    await api('catalog.php',{
      action:'save_supplier',
      id:id,
      name:name,
      sort_order:sortOrder,
      section_ids:sectionIds
    });
    await loadMeta();
    if(sectionId){
      settingsSuppliersOpenCategories[((allSecs||[]).find(function(section){return String(section.id)===String(sectionId);})||{}).category_id]=true;
      settingsSuppliersOpenSections[sectionId]=true;
    }
    renderSettingsSuppliers();
    neUpdateSuppliers();
    toast('Поставщик сохранён');
  }catch(e){toast(e.message,'err');}
}

function deleteSettingsSupplier(id){
  if(!canDeleteByRole()){toast('Недостаточно прав','err');return;}
  showConfirmDialog({title:'Удалить поставщика',message:'Удалить поставщика?',icon:'🗑️',confirmText:'Удалить',confirmClass:'btn-rd'}).then(async function(ok){
    if(!ok) return;
    try{
      await api('catalog.php',{action:'delete_supplier',id:id});
      await loadMeta();
      renderSettingsSuppliers();
      neUpdateSuppliers();
      resetSettingsSupplierForm();
      toast('Поставщик удалён');
    }catch(e){toast(e.message,'err');}
  });
}

function renderSettingsSuppliers(){
  var wrap=document.getElementById('settings-suppliers-list');
  if(!wrap) return;
  var query=settingsSuppliersQuery;
  var categories=(allCats||[]).filter(function(category){return !!category;});
  if(!categories.length){
    wrap.innerHTML='<div class="es">Категории не найдены</div>';
    return;
  }
  var html=categories.map(function(category){
    var sections=(allSecs||[]).filter(function(section){
      return String(section.category_id)===String(category.id);
    });
    var categoryMatches=!query || String(category.name||'').toLocaleLowerCase('ru').indexOf(query)>=0;
    var renderedSections=sections.map(function(section){
      return renderSettingsSupplierSection(section,query,!!query);
    }).filter(Boolean);
    if(query && !categoryMatches && !renderedSections.length) return '';
    if(query && categoryMatches){
      renderedSections=sections.map(function(section){
        return renderSettingsSupplierSection(section,'',true);
      });
    }
    var supplierCount=sections.reduce(function(total,section){
      return total+getSettingsSuppliersForSection(section.id).length;
    },0);
    var isOpen=!!query || !!settingsSuppliersOpenCategories[category.id];
    return '<section class="settings-groups-category'+(isOpen?' open':'')+'" data-category-id="'+category.id+'">'+
      '<button class="settings-groups-category-toggle" type="button" onclick="toggleSettingsSupplierCategory('+category.id+')" aria-expanded="'+(isOpen?'true':'false')+'">'+
        '<span class="settings-groups-chevron">›</span>'+
        '<span class="settings-groups-category-title">'+esc(category.name||'Без названия')+'</span>'+
        '<span class="settings-groups-category-meta">'+sections.length+' '+settingsGroupsWord(sections.length,'раздел','раздела','разделов')+' · '+supplierCount+' '+settingsGroupsWord(supplierCount,'поставщик','поставщика','поставщиков')+'</span>'+
      '</button>'+
      (isOpen?'<div class="settings-groups-category-body">'+(renderedSections.length?renderedSections.join(''):'<div class="settings-groups-empty">Разделы или поставщики не найдены</div>')+'</div>':'')+
    '</section>';
  }).filter(Boolean).join('');
  var unlinked=getSettingsUnlinkedSuppliers().filter(function(supplier){
    return !query || String(supplier.name||'').toLocaleLowerCase('ru').indexOf(query)>=0 || 'без привязки'.indexOf(query)>=0;
  });
  if(unlinked.length){
    html+='<section class="settings-groups-category open">'+
      '<button class="settings-groups-category-toggle" type="button" aria-expanded="true">'+
        '<span class="settings-groups-chevron">›</span>'+
        '<span class="settings-groups-category-title">Без привязки к разделам</span>'+
        '<span class="settings-groups-category-meta">'+unlinked.length+' '+settingsGroupsWord(unlinked.length,'поставщик','поставщика','поставщиков')+'</span>'+
      '</button>'+
      '<div class="settings-groups-category-body"><div class="settings-groups-section open">'+
        '<div class="settings-groups-section-body">'+unlinked.map(function(supplier){return renderSettingsSupplierRow(supplier,0);}).join('')+'</div>'+
      '</div></div>'+
    '</section>';
  }
  wrap.innerHTML=html || '<div class="es">Ничего не найдено</div>';
}

function getNextSettingsGroupSortOrder(sectionId){
  var maxSort=0;
  (allGroups||[]).forEach(function(group){
    if(String(group.section_id)!==String(sectionId)) return;
    var sortVal=parseInt(group && group.sort_order!=null ? group.sort_order : '0',10);
    if(!isNaN(sortVal) && sortVal>maxSort) maxSort=sortVal;
  });
  return maxSort+1;
}
