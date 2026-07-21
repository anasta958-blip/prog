// ===================== CONSTANTS =====================
var UNITS=[];
var SUPPLIERS=['']; // заполняется из БД при загрузке (catalog.php?action=all_suppliers)
var allSuppliers=[]; // [{id, name, section_ids}] — полный список поставщиков из БД
// (order type labels/colors moved below)
var OBJECT_TYPE_LABELS=['Квартира','Дом','Ресторан','Кафе','Бассейн','Офис','Производство'];
var ORDER_TYPE_LABELS={}; // kept for compatibility
OBJECT_TYPE_LABELS.forEach(function(t){ORDER_TYPE_LABELS[t]=t;});
var ORDER_TYPE_COLORS={}; // no per-type colors anymore
var ROLE_LABELS={'admin':'Администратор','manager':'Менеджер','rop':'РОП','logist':'Логист','prorab':'Прораб'};
var ACCESS_POLICY=null, ACCESS_POLICY_ROLES=[], ACCESS_ROLE_POLICIES={}, ACCESS_POLICY_USERS=[];
var ACCESS_BLOCK_COLLAPSE_STATE={};
var ACCESS_TAB_LABELS={
  catalog:'Каталог товаров',
  orders:'Комплектация объекта',
  doc:'Новая заявка',
  employees:'Сотрудники',
  users:'Пользователи',
  kp_company:'Компания · О компании',
  kp_clients:'Компания · Клиенты',
  kp_contractors:'Компания · Подрядчики',
  kp_list:'КП · Канбан',
  settings_units:'Настройки · Единицы',
  settings_suppliers:'Настройки · Поставщики',
  settings_groups:'Настройки · Группы',
  settings_access:'Настройки · Права доступа'
};
var ACCESS_SPACE_LABELS={
  catalog:'Каталог товаров',
  orders:'Комплектация объекта',
  kp:'Коммерческие предложения',
  company:'Компания',
  settings:'Настройки',
  users:'Пользователи'
};
var ACCESS_KANBAN_LABELS={
  orders:'Комплектация объекта',
  kp:'Коммерческие предложения'
};
var ACCESS_SPACE_TABS={
  catalog:['catalog'],
  orders:['doc','orders'],
  kp:['kp_list'],
  company:['kp_company','kp_clients','kp_contractors','employees'],
  settings:['settings_units','settings_suppliers','settings_groups','users','settings_access']
};
ACCESS_TAB_LABELS.documents_builder='Конструктор документов';
ACCESS_SPACE_LABELS.documents='Документы';
ACCESS_SPACE_TABS.documents=['documents_builder'];
function accessSpaceVisibleUi(spaceKey){
  if(!CU) return false;
  if(CU.role==='admin') return true;
  var tabs=ACCESS_SPACE_TABS[spaceKey]||[];
  if(!tabs.length) return false;
  return tabs.some(function(tabKey){ return accessTabVisibleUi(tabKey); });
}
function getFirstVisibleSpacePage(space){
  if(space==='catalog') return accessTabVisibleUi('catalog') ? 'catalog' : 'home';
  if(space==='orders'){
    if(accessTabVisibleUi('doc')) return 'doc';
    if(accessTabVisibleUi('orders')) return 'orders';
    return 'home';
  }
  if(space==='company'){
    if(accessTabVisibleUi('kp_company')) return 'kp-company';
    if(accessTabVisibleUi('kp_clients')) return 'kp-clients';
    if(accessTabVisibleUi('kp_contractors')) return 'kp-contractors';
    if(accessTabVisibleUi('employees')) return 'employees';
    return 'home';
  }
  if(space==='settings'){
    if(accessTabVisibleUi('settings_units')) return 'settings-units';
    if(accessTabVisibleUi('settings_suppliers')) return 'settings-suppliers';
    if(accessTabVisibleUi('settings_groups')) return 'settings-groups';
    if(accessTabVisibleUi('users')) return 'settings-users';
    if(accessTabVisibleUi('settings_access')) return 'settings-access';
    return 'home';
  }
  if(space==='documents'){
    if(accessTabVisibleUi('documents_builder')) return 'documents-builder';
    return 'home';
  }
  if(space==='kp'){
    if(accessTabVisibleUi('kp_list')) return 'kp-list';
    return 'home';
  }
  return 'home';
}
function getQuoteWorkspaceAccessItems(mode){
  return [
    {section:'list', page:'kp-list', tab:'kp_list'}
  ];
}
function getFirstVisibleQuoteWorkspacePage(mode, preferredSection){
  var items=getQuoteWorkspaceAccessItems(mode);
  var preferred=(items.find(function(item){ return item.section===preferredSection; })||null);
  if(preferred){
    if(preferred.section==='list' && accessTabVisibleUi('kp_list')) return preferred.page;
    if(accessTabVisibleUi(preferred.tab)) return preferred.page;
  }
  for(var i=0;i<items.length;i++){
    var item=items[i];
    if(item.section==='list'){
      if(accessTabVisibleUi('kp_list')) return item.page;
      continue;
    }
    if(accessTabVisibleUi(item.tab)) return item.page;
  }
  return 'home';
}
function currentAccessSpace(){
  if(activePage==='settings-users') return 'users';
  if(activePage==='kp-company' || activePage==='kp-clients' || activePage==='kp-contractors' || activePage==='employees') return 'company';
  if(activeSpace==='doc') return 'kp';
  if(activeSpace==='company') return 'company';
  if(activeSpace==='documents') return 'documents';
  if(activeSpace==='pkp') return 'pkp';
  return activeSpace||'catalog';
}
function accessTabVisibleUi(tabKey){
  if(!CU) return false;
  if(CU.role==='admin') return true;
  return !!(ACCESS_POLICY && ACCESS_POLICY.tabs && ACCESS_POLICY.tabs[tabKey]);
}
function accessCanUi(space, action){
  if(!CU) return false;
  if(CU.role==='admin') return true;
  return !!(ACCESS_POLICY && ACCESS_POLICY.spaces && ACCESS_POLICY.spaces[space] && ACCESS_POLICY.spaces[space][action]);
}
function currentSpaceCan(action){
  return accessCanUi(currentAccessSpace(), action);
}
function canDeleteByRole(){
  return currentSpaceCan('delete');
}
var STATUS_BADGE={
    'Составление комплектации':'b-new',
    'Проверка комплектации':'b-new',
    'Проверено':'b-yes',
    'Закупка материала':'b-work',
    'Монтаж':'b-done',
    'Монтаж завершён':'b-cancel',
    'Выполнено':'b-done'
};
var ROLE_SET_STATUSES={
  'admin':  ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
  'manager':['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
  'rop':    ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
  'logist': ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено'],
  'prorab': ['Составление комплектации','Проверка комплектации','Проверено','Закупка материала','Монтаж','Монтаж завершён','Выполнено']
};

