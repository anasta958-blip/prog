<div id="page-kp-contractors" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">🧰</span>Подрядчики</div>
    <div class="pa">
      <div class="kp-inline-field">
        <span>Тип</span>
        <select id="kp-contractor-type-filter" class="finp" onchange="renderKpContractors()">
          <option value="">Все</option>
          <option value="person">Физ лицо</option>
          <option value="ip">ИП</option>
          <option value="ooo">ООО</option>
        </select>
      </div>
      <button class="btn btn-p" id="kp-contractors-add-btn" onclick="openKpContractorModal()">➕ Добавить подрядчика</button>
    </div>
  </div>
  <div class="ca">
    <div id="kp-contractors-list"></div>
  </div>
</div>
