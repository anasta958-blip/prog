<!-- MODAL: Каталог - редактировать название -->
<div class="overlay" id="m-name-edit">
  <div class="modal">
    <div class="mh"><h3 id="m-name-edit-title">✏️ Редактировать название</h3><button class="mcl" onclick="cm('m-name-edit')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="ne-id">
      <div class="frow">
        <div class="field"><label>Категория</label><select id="ne-cat" onchange="neCatChange()"></select></div>
        <div class="field"><label>Раздел</label><select id="ne-sec" onchange="neUpdateSuppliers();refreshNameEditGroups()"></select></div>
      </div>
      <div class="field" id="ne-group-field"><label>Группа</label><select id="ne-group"><option value="">— без группы —</option></select></div>
      <div class="field" id="ne-name-field"><label id="ne-name-label">Название</label><input type="text" id="ne-name"></div>
      <div class="field" id="ne-marking-field"><label id="ne-marking-size-label">Маркировка/Размер</label><input type="text" id="ne-marking-size" placeholder="Например: 100x200 или DN50"></div>
      <div class="field" id="ne-komplektaciya-field" style="display:none"><label>Комплектация</label><input type="text" id="ne-komplektaciya" placeholder="Введите комплектацию"></div>
      <div class="field" id="ne-note-field" style="display:none"><label>Примечание</label><input type="text" id="ne-note" placeholder="Введите примечание"></div>
      <div class="field" id="ne-unit-field"><label>Единица измерения</label><select id="ne-unit"></select></div>
      <div class="field" id="ne-supplier-field"><label>Поставщик</label>
        <select id="ne-supplier">
          <option value="">— не указан —</option>
        </select>
      </div>
      <div class="field" id="ne-simple-cost-field" style="display:none"><label id="ne-simple-cost-label">Стоимость</label><input type="number" step="1" min="0" id="ne-simple-cost"></div>
      <div id="ne-general-fields" style="display:none">
        <div class="frow">
          <div class="field" id="ne-purchase-price-field"><label>Закупочная цена</label><input type="number" step="1" min="0" id="ne-purchase-price"></div>
          <div class="field" id="ne-minimal-price-field"><label>Минимальная цена</label><input type="number" step="1" min="0" id="ne-minimal-price"></div>
        </div>
        <div class="frow">
          <div class="field"><label id="ne-retail-price-label">Розничная цена</label><input type="number" step="1" min="0" id="ne-retail-price"></div>
          <div class="field" id="ne-price-type-field" style="display:none">
            <label>Тип цены</label>
            <select id="ne-price-type" onchange="updateNameEditModeUi()">
              <option value="fixed">Фиксированная</option>
              <option value="percent">Процент от суммы варианта</option>
            </select>
          </div>
          <div class="field" id="ne-linked-services-field">
            <label>Работа</label>
            <input type="hidden" id="ne-linked-service-id">
            <div id="ne-linked-services-list" class="linked-services-list"></div>
            <div class="ac-wrap" style="position:relative">
              <input type="text" id="ne-linked-service-name" class="finp ac-inp" placeholder="Найти работу..." autocomplete="off" oninput="serviceSearchInput(this.value)" onfocus="serviceSearchFocus()">
              <div class="ac-drop" id="ne-linked-service-drop" style="min-width:260px"></div>
            </div>
          </div>
        </div>
      </div>
      <div class="field" id="ne-status-field"><label>Статус</label>
        <select id="ne-status"><option value="Не согласовано">Не согласовано</option><option value="Согласовано">Согласовано</option></select>
      </div>
      <button class="btn btn-p btn-fw" onclick="saveNameEdit()" style="margin-top:6px">Сохранить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-tech-note">
  <div class="modal" style="max-width:760px">
    <div class="mh"><h3 id="m-tech-note-title">Техничка</h3><button class="mcl" onclick="cm('m-tech-note')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="tn-id">
      <div class="field">
        <label>Техничка</label>
        <textarea id="tn-text" class="finp" rows="12" style="min-height:260px;resize:vertical" placeholder="Введите техническую информацию"></textarea>
      </div>
      <button class="btn btn-p btn-fw" onclick="saveCatalogTechnicalNote()">Сохранить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-service-edit">
  <div class="modal">
    <div class="mh"><h3 id="m-service-edit-title">➕ Добавить работу</h3><button class="mcl" onclick="cm('m-service-edit')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="se-id">
      <div class="field"><label>Название</label><input type="text" id="se-name"></div>
      <div class="field"><label>Маркировка</label><input type="text" id="se-marking"></div>
      <div class="frow3">
        <div class="field"><label>Закупочная цена</label><input type="number" step="1" min="0" id="se-purchase"></div>
        <div class="field"><label>Минимальная цена</label><input type="number" step="1" min="0" id="se-minimal"></div>
        <div class="field"><label>Розничная цена</label><input type="number" step="1" min="0" id="se-retail"></div>
      </div>
      <div class="frow2">
        <div class="field"><label>Ед. изм.</label><select id="se-unit"></select></div>
      </div>
      <div class="field"><label>Раздел работ</label><select id="se-work-section"><option value="installation">Монтажные работы</option><option value="construction">Строительные работы</option><option value="dismantling">Демонтажные работы</option></select></div>
      <button class="btn btn-p btn-fw" onclick="saveServiceEdit()" style="margin-top:6px">Сохранить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-kp-product">
  <div class="modal">
    <div class="mh"><h3 id="m-kp-product-title">➕ Товар</h3><button class="mcl" onclick="cm('m-kp-product')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="kpp-id">
      <div class="frow">
        <div class="field"><label>Название</label><input id="kpp-name" class="finp"></div>
        <div class="field"><label>Раздел</label><select id="kpp-section" onchange="fillKpCatalogSelects()"></select></div>
      </div>
      <div class="field"><label>Группа</label><input id="kpp-group" class="finp" list="kpp-group-list"><datalist id="kpp-group-list"></datalist></div>
      <div class="frow3">
        <div class="field"><label>Маркировка</label><input id="kpp-marking" class="finp"></div>
        <div class="field"><label>Ед. изм.</label><select id="kpp-unit"></select></div>
        <div class="field"><label>Поставщик</label><input id="kpp-supplier" class="finp" readonly></div>
      </div>
      <div class="field" id="kpp-note-field" style="display:none"><label>Примечание</label><input id="kpp-note" class="finp" placeholder="Введите примечание"></div>
      <div class="frow3">
        <div class="field"><label>Закупочная цена</label><input id="kpp-purchase" type="number" step="1" class="finp"></div>
        <div class="field"><label>Минимальная цена</label><input id="kpp-minimal" type="number" step="1" class="finp"></div>
        <div class="field"><label>Розничная цена</label><input id="kpp-retail" type="number" step="1" class="finp"></div>
      </div>
      <div class="field"><label>Работа</label><select id="kpp-service"><option value="">— не привязана —</option></select></div>
      <button class="btn btn-p btn-fw" onclick="saveKpProduct()">Сохранить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-kp-service">
  <div class="modal">
    <div class="mh"><h3 id="m-kp-service-title">➕ Работа</h3><button class="mcl" onclick="cm('m-kp-service')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="kps-id">
      <div class="field"><label>Название</label><input id="kps-name" class="finp"></div>
      <div class="field"><label>Маркировка</label><input id="kps-marking" class="finp"></div>
      <div class="frow3">
        <div class="field"><label>Закупочная цена</label><input id="kps-purchase" type="number" step="1" class="finp"></div>
        <div class="field"><label>Минимальная цена</label><input id="kps-minimal" type="number" step="1" class="finp"></div>
        <div class="field"><label>Розничная цена</label><input id="kps-retail" type="number" step="1" class="finp"></div>
      </div>
      <div class="frow2">
        <div class="field"><label>Ед. изм.</label><select id="kps-unit"></select></div>
      </div>
      <button class="btn btn-p btn-fw" onclick="saveKpService()">Сохранить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-kp-client">
  <div class="modal">
    <div class="mh"><h3 id="m-kp-client-title">➕ Клиент</h3><button class="mcl" onclick="cm('m-kp-client')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="kpc-id">
      <input type="hidden" id="kpc-note-legacy">
      <div class="frow">
        <div class="field"><label>Тип компании</label><select id="kpc-company-type" class="finp" onchange="updateKpClientTypeUi()"><option value="person">Физ лицо</option><option value="ip">ИП</option><option value="ooo">ООО</option></select></div>
        <div class="field"><label id="kpc-company-label">Название компании</label><input id="kpc-company" class="finp"></div>
      </div>
      <div class="frow">
        <div class="field"><label id="kpc-legal-label">ФИО физ лица</label><input id="kpc-legal" class="finp"></div>
        <div class="field"><label>ИНН</label><div class="pa" style="display:flex;gap:8px"><input id="kpc-inn" class="finp"><button class="btn btn-p" type="button" onclick="lookupKpClientInn()">Подтянуть по ИНН</button></div></div>
      </div>
      <div class="frow3">
        <div class="field"><label id="kpc-ogrn-label">ОГРН</label><input id="kpc-ogrn" class="finp"></div>
        <div class="field"><label>КПП</label><input id="kpc-kpp" class="finp"></div>
        <div class="field"><label>Телефон</label><input id="kpc-phone" class="finp"></div>
      </div>
      <div class="frow">
        <div class="field"><label>Email</label><input id="kpc-email" class="finp"></div>
        <div class="field"><label>Банк</label><input id="kpc-bank-name" class="finp"></div>
      </div>
      <div class="field"><label>БИК</label><input id="kpc-bank-bik" class="finp"></div>
      <div class="frow3" id="kpc-passport-row">
        <div class="field"><label>Серия паспорта</label><input id="kpc-passport-series" class="finp"></div>
        <div class="field"><label>Номер паспорта</label><input id="kpc-passport-number" class="finp"></div>
        <div class="field"><label>Кем выдан</label><input id="kpc-passport-issued" class="finp"></div>
      </div>
      <div class="field" id="kpc-address-field"><label id="kpc-address-label">Адрес регистрации</label><textarea id="kpc-address" class="finp" rows="3"></textarea></div>
      <div class="frow3" id="kpc-bank-extra-row">
        <div class="field" id="kpc-bank-account-field"><label id="kpc-bank-account-label">Р/с</label><input id="kpc-bank-account" class="finp"></div>
        <div class="field" id="kpc-corr-account-field"><label id="kpc-corr-account-label">К/с</label><input id="kpc-corr-account" class="finp"></div>
        <div class="field"></div>
      </div>
      <button class="btn btn-p btn-fw" onclick="saveKpClient()">Сохранить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-pkp-preset">
  <div class="modal">
    <div class="mh"><h3 id="m-pkp-preset-title">➕ Комплект</h3><button class="mcl" onclick="cm('m-pkp-preset')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="pkpp-id">
      <div class="field"><label>Название комплекта</label><input id="pkpp-name" class="finp"></div>
      <div id="pkp-preset-items"></div>
      <button class="btn btn-p btn-fw" style="margin-top:14px" onclick="savePkpPreset()">Сохранить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-pkp-apply-preset">
  <div class="modal">
    <div class="mh"><h3>🧩 Применить комплект</h3><button class="mcl" onclick="cm('m-pkp-apply-preset')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="pkp-apply-variant-id">
      <div class="field">
        <label>Комплект</label>
        <div class="ac-wrap" style="position:relative">
          <input id="pkp-apply-preset-input" class="finp ac-inp" placeholder="Начните вводить название комплекта" autocomplete="off" oninput="pkpPresetApplyInput(this.value)" onfocus="pkpPresetApplyFocus()" onmousedown="pkpPresetApplyMouseDown(event)">
          <div class="ac-drop" id="pkp-apply-preset-drop" style="min-width:260px;z-index:3500"></div>
        </div>
      </div>
      <button class="btn btn-p btn-fw" onclick="confirmApplyPkpPreset()">Применить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-kp-transfer">
  <div class="modal">
    <div class="mh"><h3>📦 Перенос в комплектацию</h3><button class="mcl" onclick="cm('m-kp-transfer')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="kpt-quote-id">
      <div class="field"><label>Адрес объекта</label><input id="kpt-address" class="finp" placeholder="Введите адрес объекта"></div>
      <div class="frow">
        <div class="field"><label>Менеджер</label><select id="kpt-manager"></select></div>
        <div class="field"><label>Тип объекта</label>
          <select id="kpt-order-type">
            <option value="">— выберите тип —</option>
            <option value="Квартира">Квартира</option>
            <option value="Дом">Дом</option>
            <option value="Ресторан">Ресторан</option>
            <option value="Кафе">Кафе</option>
            <option value="Бассейн">Бассейн</option>
            <option value="Офис">Офис</option>
            <option value="Производство">Производство</option>
          </select>
        </div>
      </div>
      <div class="field"><label>Тип клиента</label><input id="kpt-client-type" class="finp" placeholder="Например, название компании"></div>
      <button class="btn btn-p btn-fw" onclick="confirmKpTransferToComplectation()">Перенести в комплектацию</button>
    </div>
  </div>
</div>

<!-- MODAL: Add category to doc -->
<div class="overlay" id="m-add-cat">
  <div class="modal" style="max-width:420px">
    <div class="mh"><h3>➕ Добавить категорию</h3><button class="mcl" onclick="cm('m-add-cat')">✕</button></div>
    <div class="mb">
      <div class="field"><label>Категория</label><select id="dc-cat"><option value="">Выберите...</option></select></div>
      <button class="btn btn-p btn-fw" onclick="confirmDocCat()">Добавить</button>
    </div>
  </div>
</div>

<!-- MODAL: Add section to doc -->
<div class="overlay" id="m-add-sec">
  <div class="modal" style="max-width:420px">
    <div class="mh"><h3>➕ Добавить раздел</h3><button class="mcl" onclick="cm('m-add-sec')">✕</button></div>
    <div class="mb">
      <div class="field"><label>Раздел</label><select id="dc-sec"><option value="">Выберите...</option></select></div>
      <button class="btn btn-p btn-fw" onclick="confirmDocSec()">Добавить</button>
    </div>
  </div>
</div>

<!-- MODAL: User create/edit -->
<div class="overlay" id="m-user">
  <div class="modal" style="max-width:520px">
    <div class="mh"><h3 id="um-title">➕ Новый пользователь</h3><button class="mcl" onclick="cm('m-user')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="um-id">
      <div class="frow">
        <div class="field"><label>ФИО</label><input type="text" id="um-fn" placeholder="Полное имя"></div>
        <div class="field"><label>Логин</label><input type="text" id="um-un" placeholder="username"></div>
      </div>
      <div class="frow">
        <div class="field"><label>Телефон</label><input type="text" id="um-phone" placeholder="+7..."></div>
        <div class="field"><label>Телеграм</label><input type="text" id="um-tg" placeholder="@username"></div>
      </div>
      <div class="field"><label>Email</label><input type="email" id="um-email" placeholder="example@mail.com"></div>
      <div class="frow">
        <div class="field"><label>Пароль <span id="um-pwdhint" style="color:var(--tx3);font-weight:400;text-transform:none">(оставьте пустым, чтобы не менять)</span></label><input type="password" id="um-pw" placeholder="Минимум 4 символа"></div>
        <div class="field"><label>Роль</label>
          <select id="um-role" onchange="umRoleChange()">
            <option value="manager">Менеджер</option>
            <option value="rop">РОП</option>
            <option value="logist">Логист</option>
            <option value="prorab">Прораб</option>
            <option value="admin">Администратор</option>
          </select>
        </div>
      </div>
      <div id="um-managers-block" style="display:none">
        <div class="field"><label>Менеджеры РОП-а (выберите одного и более)</label>
          <div id="um-managers-list" style="background:var(--sf2);border:1.5px solid var(--bd);border-radius:var(--rds);padding:10px;max-height:160px;overflow-y:auto"></div>
        </div>
      </div>
      <button class="btn btn-p btn-fw" onclick="saveUser()" style="margin-top:6px">Сохранить</button>
    </div>
  </div>
</div>

<!-- MODAL: Email send -->
<div class="overlay" id="m-email">
  <div class="modal" style="max-width:420px">
    <div class="mh"><h3>📧 Отправить на почту</h3><button class="mcl" onclick="cm('m-email')">✕</button></div>
    <div class="mb">
      <div class="field"><label>Email адрес</label><input type="email" id="email-to" placeholder="example@mail.com"></div>
      <button class="btn btn-p btn-fw" onclick="doSendEmail()">Отправить</button>
    </div>
  </div>
</div>

<div id="tc"></div>

<!-- MODAL: Application update -->
<div class="overlay" id="m-app-update" role="dialog" aria-modal="true" aria-labelledby="app-update-title">
  <div class="modal" style="max-width:460px">
    <div class="mh">
      <h3 id="app-update-title">Доступна новая версия</h3>
    </div>
    <div class="mb">
      <p style="color:var(--tx2);line-height:1.55;margin-bottom:18px">На сервер загружено обновление. Обновите страницу, чтобы использовать новую версию. Перед обновлением сохраните несохранённые изменения.</p>
      <div style="display:flex;justify-content:flex-end;gap:10px;flex-wrap:wrap">
        <button class="btn btn-g" id="app-update-later-btn" type="button" onclick="deferApplicationUpdate()">Позже</button>
        <button class="btn btn-p" id="app-update-refresh-btn" type="button" onclick="reloadApplicationForUpdate()">Обновить страницу</button>
      </div>
    </div>
  </div>
</div>

<!-- MODAL: Confirm delete -->
<div class="overlay" id="m-confirm-delete">
  <div class="confirm-modal">
    <h3><span id="cd-icon">🗑️</span> <span id="cd-title">Подтвердить удаление</span></h3>
    <p id="cd-msg">Вы уверены, что хотите удалить этот элемент?</p>
    <div class="confirm-btns">
      <button class="btn btn-g" id="cd-cancel-btn" onclick="closeConfirmDialog(false)">Отмена</button>
      <button class="btn btn-rd" id="cd-confirm-btn" onclick="closeConfirmDialog(true)">Удалить</button>
    </div>
  </div>
</div>

<div class="overlay" id="m-add-group">
  <div class="modal" style="max-width:420px">
    <div class="mh"><h3>➕ Добавить группу</h3><button class="mcl" onclick="cm('m-add-group')">✕</button></div>
    <div class="mb">
      <div class="field"><label>Группа</label><select id="dc-group"><option value="">Выберите...</option></select></div>
      <button class="btn btn-p btn-fw" onclick="confirmDocGroup()">Добавить</button>
    </div>
  </div>
</div>
