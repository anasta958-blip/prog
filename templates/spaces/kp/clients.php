<div id="page-kp-clients" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">🤝</span>Клиенты</div>
    <div class="pa">
      <div class="kp-inline-field">
        <span>Тип</span>
        <select id="kp-client-type-filter" class="finp" onchange="renderKpClients()">
          <option value="">Все</option>
          <option value="person">Физ лицо</option>
          <option value="ip">ИП</option>
          <option value="ooo">ООО</option>
        </select>
      </div>
      <div class="kp-inline-field">
        <span>Поиск</span>
        <input id="kp-client-search" class="finp" type="search" placeholder="Название, ИНН, телефон..." oninput="renderKpClients()">
      </div>
      <button class="btn btn-p" id="kp-clients-add-btn" onclick="openKpClientModal()">➕ Добавить клиента</button>
    </div>
  </div>
  <div class="ca">
    <div id="kp-clients-list"></div>
  </div>
</div>
