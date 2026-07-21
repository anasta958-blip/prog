<div id="page-settings-groups" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">🗂️</span>Группы</div>
  </div>
  <div class="ca">
    <div class="settings-groups-shell">
      <div class="settings-groups-toolbar">
        <div class="field settings-groups-search">
          <label for="settings-groups-search">Поиск</label>
          <input id="settings-groups-search" class="finp" placeholder="Категория, раздел или группа" oninput="filterSettingsGroups(this.value)">
        </div>
        <button class="btn btn-g" type="button" onclick="collapseAllSettingsGroups()">Свернуть все</button>
      </div>
      <div id="settings-groups-list" class="settings-groups-list"></div>
    </div>
  </div>
</div>
