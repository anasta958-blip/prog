</head>
<body>

<div id="login-screen">
  <div id="login-loader"><div class="spin" style="width:32px;height:32px;border-width:3px"></div>Загрузка...</div>
  <div id="login-form" class="lw">
    <div class="ll">Склад <span>Комфорта</span></div>
    <div class="ls">Система управления складом и документами</div>
    <div class="field"><label>Логин</label><input type="text" id="li-u" placeholder="Введите логин" autocomplete="username"></div>
    <div class="field"><label>Пароль</label><input type="password" id="li-p" placeholder="••••••••" autocomplete="current-password"></div>
    <button class="btn btn-p btn-fw" onclick="doLogin()">Войти</button>
  </div>
</div>

<div id="app">
<div class="layout">
<aside class="sidebar" id="app-sidebar">
  <div class="slogo">Склад <span>Комфорта</span></div>
  <div class="nlabel">Пространства</div>
  <button class="btn btn-g btn-xs sidebar-toggle" id="sidebar-toggle-btn" type="button" onclick="toggleSidebarCollapsed()" aria-label="Toggle sidebar">◂</button>
  <div class="space-tabs">
    <div class="space-tab" id="space-tab-doc" onclick="openQuoteWorkspace('kp','list')">
      <div>
        <div class="space-tab-name">Коммерческие предложения</div> 
      </div>
      <span>📋</span>
    </div>
    <div class="space-tab" id="space-tab-company" onclick="showSpace('company')">
      <div>
        <div class="space-tab-name">Компания</div>
      </div>
      <span>🏢</span>
    </div>
    <div class="space-tab" id="space-tab-documents" onclick="showSpace('documents')">
      <div>
        <div class="space-tab-name">Документы</div>
      </div>
      <span>📝</span>
    </div>
    <div class="space-tab" id="space-tab-orders" onclick="showSpace('orders')">
      <div>
        <div class="space-tab-name">Комплектация объекта</div>
      </div>
      <span>📦</span>
    </div>
    <div class="space-tab active" id="space-tab-catalog" onclick="showSpace('catalog')">
      <div>
        <div class="space-tab-name">Каталог товаров</div>
      </div>
      <span>🗂️</span>
    </div>
    <div class="space-tab" id="space-tab-settings" onclick="showSpace('settings')">
      <div>
        <div class="space-tab-name">Настройки</div>
      </div>
      <span>⚙️</span>
    </div>
  </div>
  <div class="nlabel">Разделы пространства</div>
  <div class="space-nav active" data-space="catalog">
    <div class="nitem active" onclick="showPage('catalog')" id="nav-catalog"><span>🗂️</span> Каталог товаров</div>
  </div>
  <div class="space-nav" data-space="orders">
    <div class="nitem" onclick="showPage('doc')" id="nav-doc" style="display:none"><span>📋</span> Новая заявка</div>
    <div class="nitem" onclick="showPage('orders')" id="nav-orders" style="display:none"><span>📦</span> Комплектация объекта</div>
  </div>
  <div class="space-nav" data-space="doc"></div>
  <div class="space-nav" data-space="company">
    <div class="nitem" onclick="showPage('kp-company')" id="nav-kp-company"><span>🏢</span> О компании</div>
    <div class="nitem" onclick="showPage('kp-clients')" id="nav-kp-clients"><span>🤝</span> Клиенты</div>
    <div class="nitem" onclick="showPage('kp-contractors')" id="nav-kp-contractors"><span>🧰</span> Подрядчики</div>
    <div class="nitem" onclick="showPage('employees')" id="nav-employees" style="display:none"><span>👤</span> Сотрудники</div>
  </div>
  <div class="space-nav" data-space="documents">
    <div class="nitem" onclick="showPage('documents-builder')" id="nav-documents-builder"><span>📝</span> Конструктор документа</div>
  </div>
  <div class="space-nav" data-space="settings">
    <div class="nitem" onclick="showPage('settings-units')" id="nav-settings-units"><span>📏</span> Единицы измерения</div>
    <div class="nitem" onclick="showPage('settings-suppliers')" id="nav-settings-suppliers"><span>🏷️</span> Поставщики</div>
    <div class="nitem" onclick="showPage('settings-groups')" id="nav-settings-groups"><span>🗂️</span> Группы</div>
    <div class="nitem" onclick="showPage('settings-users')" id="nav-settings-users"><span>👥</span> Пользователи</div>
    <div class="nitem" onclick="showPage('settings-access')" id="nav-settings-access"><span>🔐</span> Права доступа</div>
  </div>
  <div class="sfooter">
    <div class="ucard"><div class="uname" id="ui-un">—</div><span class="urole" id="ui-r">—</span></div>
    <button class="btn btn-g btn-fw" style="margin-top:11px" onclick="doLogout()">🚪 Выйти</button>
  </div>
</aside>

<main class="main">
  <button class="btn btn-g btn-xs sidebar-flyout-toggle" id="sidebar-flyout-toggle-btn" type="button" onclick="toggleSidebarCollapsed(false)" aria-label="Open sidebar">▸</button>
