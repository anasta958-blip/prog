<div id="page-settings-suppliers" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">🏷️</span>Поставщики</div>
  </div>
  <div class="ca">
    <div class="settings-groups-shell settings-suppliers-shell">
      <input type="hidden" id="settings-supplier-id">
      <input type="hidden" id="settings-supplier-name">
      <div id="settings-supplier-sections" style="display:none"></div>
      <div class="settings-groups-toolbar">
        <div class="field settings-groups-search">
          <label for="settings-suppliers-search">Поиск</label>
          <input id="settings-suppliers-search" class="finp" placeholder="Категория, раздел или поставщик" oninput="filterSettingsSuppliers(this.value)">
        </div>
        <button class="btn btn-g" type="button" onclick="collapseAllSettingsSuppliers()">Свернуть все</button>
      </div>
      <div id="settings-suppliers-list" class="settings-groups-list"></div>
    </div>
  </div>
</div>
