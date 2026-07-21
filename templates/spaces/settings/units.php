<div id="page-settings-units" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">📏</span>Единицы измерения</div>
  </div>
  <div class="ca">
    <div class="kp-grid-2">
      <div class="kp-section-card">
        <div class="kp-section-title">Новая единица</div>
        <div class="field"><label>Название</label><input id="settings-unit-name" class="finp" placeholder="Например: шт"></div>
        <div class="frow">
          <div class="field"><label>Сортировка</label><input id="settings-unit-sort" type="number" step="1" min="0" class="finp" value="0"></div>
          <div class="field"><label>&nbsp;</label><label class="kp-check-item" style="height:42px"><input id="settings-unit-default" type="checkbox"> По умолчанию</label></div>
        </div>
        <button class="btn btn-p" id="settings-unit-save-btn" onclick="saveSettingsUnit()">Сохранить</button>
      </div>
      <div class="kp-section-card">
        <div class="kp-section-title">Список единиц</div>
        <div id="settings-units-list" class="settings-scroll-list"></div>
      </div>
    </div>
  </div>
</div>
