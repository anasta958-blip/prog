<div id="page-settings-access" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">🔐</span>Права доступа ролей</div>
  </div>
  <div class="ca">
    <div class="kp-section-card">
      <div class="frow" style="align-items:end;margin-bottom:18px">
        <div class="field" style="max-width:320px;margin-bottom:0">
          <label>Роль</label>
          <select id="settings-access-role" class="finp" onchange="renderSettingsAccess()"></select>
        </div>
        <div class="pa" style="margin-left:auto">
          <button class="btn btn-p" onclick="saveSettingsAccess()">Сохранить права</button>
        </div>
      </div>
      <div id="settings-access-editor"></div>
    </div>
  </div>
</div>
