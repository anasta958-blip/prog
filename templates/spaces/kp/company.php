<div id="page-kp-company" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">🏢</span>О компании</div>
    <div class="pa kp-head-tools">
      <div class="kp-inline-field">
        <span>Тип компании</span>
        <select id="kp-company-type" class="finp" onchange="updateKpCompanyTypeUi()" style="min-width:132px;height:42px"><option value="ip">ИП</option><option value="ooo">ООО</option></select>
      </div>
      <button class="btn btn-g" id="kp-company-new-btn" onclick="newKpCompanyProfile()" style="min-width:132px;height:42px">＋ Компания</button>
      <button class="btn btn-g" id="kp-company-default-btn" onclick="setDefaultKpCompany()" style="min-width:132px;height:42px">★ Основная</button>
      <button class="btn btn-rd" id="kp-company-delete-btn" onclick="deleteKpCompany()" style="min-width:132px;height:42px">🗑 Удалить</button>
      <button class="btn btn-gr" id="kp-company-save-btn" onclick="saveKpCompany()" style="min-width:132px;height:42px">💾 Сохранить</button>
    </div>
  </div>
  <div class="ca">
    <input type="hidden" id="kp-company-id" value="">
    <div class="kp-section-card" style="margin-bottom:18px">
      <div class="kp-section-title">Компании исполнителя</div>
      <div id="kp-company-profiles-list" class="kp-company-profile-list"></div>
    </div>
    <div class="kp-grid-2">
      <div class="kp-section-card">
      <div class="kp-section-title">Реквизиты компании</div>
      <div class="frow">
        <div class="field"><label>Название компании</label><input id="kp-company-name" class="finp"></div>
        <div class="field"><label id="kp-company-legal-label">Юридическое название</label><input id="kp-company-legal" class="finp"></div>
      </div>
      <div class="frow3">
        <div class="field"><label>ИНН</label><input id="kp-company-inn" class="finp"></div>
        <div class="field"><label id="kp-company-ogrn-label">ОГРН</label><input id="kp-company-ogrn" class="finp"></div>
        <div class="field"><label>КПП</label><input id="kp-company-kpp" class="finp"></div>
      </div>
        <div class="pa" style="margin-bottom:10px"><button class="btn btn-g" onclick="lookupKpInn()">🔎 Подтянуть по ИНН</button></div>
        <div class="field"><label>Адрес</label><textarea id="kp-company-address" class="finp" rows="3"></textarea></div>
        <div class="frow3">
          <div class="field"><label>Телефон</label><input id="kp-company-phone" class="finp"></div>
          <div class="field"><label>Email</label><input id="kp-company-email" class="finp"></div>
          <div class="field"><label>Сайт</label><input id="kp-company-website" class="finp"></div>
        </div>
        <div class="frow3">
          <div class="field"><label>Директор</label><input id="kp-company-director" class="finp"></div>
          <div class="field"><label>Подписант</label><input id="kp-company-signatory" class="finp"></div>
          <div class="field"><label>Должность подписанта</label><input id="kp-company-signatory-title" class="finp"></div>
        </div>
      </div>
      <div class="kp-section-card">
        <div class="kp-section-title">Банк и шаблон КП</div>
        <div class="frow">
          <div class="field"><label>Банк</label><input id="kp-company-bank-name" class="finp"></div>
          <div class="field"><label>БИК</label><input id="kp-company-bank-bik" class="finp"></div>
        </div>
        <div class="frow">
          <div class="field"><label>Расчётный счёт</label><input id="kp-company-bank-account" class="finp"></div>
          <div class="field"><label>Корр. счёт</label><input id="kp-company-corr-account" class="finp"></div>
        </div>
        <div class="field"><label>Вводный текст по умолчанию</label><textarea id="kp-company-intro" class="finp" rows="5"></textarea></div>
        <div class="field"><label>Дополнительный текст по умолчанию</label><textarea id="kp-company-footer" class="finp" rows="5"></textarea></div>
      </div>
    </div>
    <div class="kp-section-card" style="margin-top:18px">
      <div class="kp-section-title">Автоподстановка в КП</div>
      <div class="field" style="margin-bottom:0">
        <label>Какие поля автоматически переносить в коммерческое предложение</label>
        <div id="kp-company-autofill" class="kp-check-grid"></div>
      </div>
    </div>
  </div>
</div>
