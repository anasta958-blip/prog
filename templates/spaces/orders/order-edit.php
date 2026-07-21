<div id="page-order-edit">
  <div class="ph">
    <div class="pt"><span class="ic">📋</span><span id="oe-page-title">Комплектация объекта</span></div>
    <div class="pa">
      <button class="btn btn-g" onclick="showPage('orders')">← Назад</button>
      <span id="autosave-indicator" style="font-size:.78rem;color:var(--tx3);align-self:center"></span>
      <button class="btn btn-cy" onclick="printOrderDoc()">🖨️ Печать</button>
      <button class="btn" style="background:#229ED9;color:#fff" onclick="exportToTelegram()">✈️ Telegram</button>
      <button class="btn" style="background:#d44638;color:#fff" onclick="exportToEmail()">📧 Email</button>
      <button class="btn btn-gr" id="oe-save-btn" onclick="saveOrderEdit()">💾 Сохранить</button>
      <button class="btn btn-rd" onclick="deleteCurrentOrder()" id="oe-delete-btn" style="display:none">🗑 Удалить</button>
    </div>
  </div>
  <div class="ca">
    <div class="oe-top">
      <div class="oe-addr-bar" id="oe-addr-bar">Адрес объекта</div>
      <div id="oe-status-changed-by" style="display:none;font-size:.78rem;color:var(--tx3);margin-bottom:8px;font-family:var(--mo)"></div>
      <div class="frow3" style="margin-bottom:12px">
        <div class="field" style="margin-bottom:0"><label>Адрес объекта</label><input type="text" id="oe-addr"></div>
        <div class="field" style="margin-bottom:0"><label>Менеджер</label><input type="text" id="oe-mgr"></div>
        <div class="field" style="margin-bottom:0"><label>РОП</label><input type="text" id="oe-rop"></div>
      </div>
      <div class="frow3">
        <div class="field" style="margin-bottom:0"><label>Тип клиента</label><input type="text" id="oe-client-type" placeholder="Введите тип клиента"></div>
        <input type="hidden" id="oe-num">
        <div class="field" style="margin-bottom:0"><label>Тип объекта</label>
          <select id="oe-type">
            <option value="">— выберите —</option>
            <option value="Квартира">Квартира</option>
            <option value="Дом">Дом</option>
            <option value="Ресторан">Ресторан</option>
            <option value="Кафе">Кафе</option>
            <option value="Бассейн">Бассейн</option>
            <option value="Офис">Офис</option>
            <option value="Производство">Производство</option>
          </select>
        </div>
        <div class="field" style="margin-bottom:0"><label>Статус новой комплектации</label>
          <select id="oe-status"></select>
        </div>
      </div>
    </div>
    <!-- Filter tabs for order edit -->
    <div style="display:flex;gap:12px;margin-bottom:14px;flex-wrap:wrap;align-items:center">
      <div>
        <div class="fl" style="margin-bottom:4px">Фильтр по поставщику:</div>
        <div class="ftabs" id="oe-sup-tabs"></div>
      </div>
      <div>
        <div class="fl" style="margin-bottom:4px">Статус отгрузки:</div>
        <div class="ftabs" id="oe-ship-tabs"></div>
      </div>
    </div>
    <input type="hidden" id="oe-id">
    <div class="oe-builder-actions">
      <button class="btn btn-p" onclick="oeAddCat()" id="oe-add-cat-btn">➕ Добавить категорию</button>
      <input type="file" id="oe-invoice-file" accept="application/pdf,.pdf" style="display:none" onchange="uploadOrderInvoice(this)">
      <button class="btn btn-cy" type="button" id="oe-invoice-upload-btn" onclick="pickOrderInvoice()">Загрузить счёт</button>
      <button class="btn btn-g" type="button" id="oe-invoice-view-btn" onclick="openOrderInvoiceViewer()">Просмотр счёта</button>
      <span class="oe-invoice-meta" id="oe-invoice-meta"></span>
    </div>
    <div id="oe-docbuilder"></div>
  </div>
</div>

<div class="order-invoice-viewer" id="order-invoice-viewer" style="display:none">
  <div class="order-invoice-viewer-head" id="order-invoice-viewer-head">
    <div>
      <div class="order-invoice-viewer-title">Счёт PDF</div>
      <div class="order-invoice-viewer-subtitle" id="order-invoice-viewer-name"></div>
    </div>
    <button class="mcl" type="button" onclick="closeOrderInvoiceViewer()">✕</button>
  </div>
  <iframe id="order-invoice-frame" title="Просмотр счёта"></iframe>
</div>

<div class="order-invoice-picker-overlay" id="order-invoice-picker" style="display:none">
  <div class="modal order-invoice-picker-box">
    <div class="mh">
      <h3>Выберите счёт</h3>
      <button class="mcl" type="button" onclick="closeOrderInvoicePicker()">✕</button>
    </div>
    <div class="mb">
      <div class="order-invoice-list" id="order-invoice-list"></div>
    </div>
  </div>
</div>
