<div id="page-kp-builder" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">📋</span>Составление КП</div>
    <div class="pa">
      <button class="btn btn-g" onclick="backFromKpBuilder()">← Назад</button>
      <button class="btn btn-g" onclick="resetKpBuilder()">↻ Очистить</button>
      <button class="btn btn-p" id="kp-builder-add-client-btn" onclick="openKpClientModal()">＋ Клиент</button>
      <button class="btn btn-gr" id="kp-builder-save-btn" onclick="saveKpQuote()">💾 Сохранить КП</button>
    </div>
  </div>
  <div class="ca">
    <div class="dmbar kp-builder-top">
      <div class="field kp-builder-title-field" style="margin:0">
        <label>Название КП</label>
        <input id="kp-quote-title" placeholder="Например: КП для ЖК Вектор">
      </div>
      <div class="field" style="margin:0">
        <label>Менеджер</label>
        <select id="kp-quote-manager" disabled onchange="kpBuilderManagerChanged()"></select>
      </div>
      <div class="field" style="margin:0">
        <label>РОП</label>
        <select id="kp-quote-rop" disabled></select>
      </div>
      <div class="field" style="margin:0">
        <label>Заказчик</label>
        <div class="ac-wrap">
          <input type="hidden" id="kp-quote-client">
          <input class="ac-inp" id="kp-quote-client-search" placeholder="Найти заказчика..." oninput="showKpPartyDrop('client',this.value)" onfocus="showKpPartyDrop('client',this.value)" onblur="validateKpPartyInput('client')" onkeydown="return handleKpPartyKeydown(event,'client')" autocomplete="off">
          <div class="ac-drop" id="kp-quote-client-drop"></div>
        </div>
      </div>
      <div class="field" style="margin:0">
        <label>Исполнитель</label>
        <div class="ac-wrap">
          <input type="hidden" id="kp-quote-contractor">
          <input class="ac-inp" id="kp-quote-contractor-search" placeholder="Найти исполнителя..." oninput="showKpPartyDrop('contractor',this.value)" onfocus="showKpPartyDrop('contractor',this.value)" onblur="validateKpPartyInput('contractor')" onkeydown="return handleKpPartyKeydown(event,'contractor')" autocomplete="off">
          <div class="ac-drop" id="kp-quote-contractor-drop"></div>
        </div>
      </div>
    </div>
    <div class="kp-builder-grid">
      <div class="kp-builder-card">
        <div class="field" style="margin-bottom:0">
          <label>Дополнительная информация</label>
          <textarea id="kp-quote-additional" class="finp" rows="5"></textarea>
        </div>
      </div>
    </div>
    <div id="kp-variants-wrap" style="margin-top:18px"></div>
  </div>
</div>
