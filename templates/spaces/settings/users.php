<div id="page-settings-users" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">👥</span>Пользователи</div>
    <div class="pa"><button class="btn btn-p" id="settings-users-add-btn" onclick="openUserModal()">➕ Добавить пользователя</button></div>
  </div>
  <div class="ca">
    <div class="emp-tree-shell users-tree-shell">
      <div class="emp-tree-head">
        <div>
          <div class="emp-tree-kicker">Права и пользователи</div>
          <div class="emp-tree-title">Дерево пользователей</div>
        </div>
        <div class="emp-tree-hint">Выберите пользователя в дереве, чтобы увидеть данные и действия.</div>
      </div>
      <div class="emp-tree-layout">
        <div id="users-tree" class="emp-tree emp-tree-loading">
          <div class="emp-empty">
            <div class="spin"></div>
            <div>Загрузка пользователей...</div>
          </div>
        </div>
        <aside id="users-details" class="emp-details-panel">
          <div class="emp-details-empty">
            <div class="ei">👤</div>
            <div class="et">Выберите пользователя</div>
            <div class="es2">Здесь будут логин, контакты, роль, привязки и действия.</div>
          </div>
        </aside>
      </div>
    </div>
  </div>
</div>
