<div id="page-catalog-orders" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">🗂️</span>Каталог товаров</div>
    <div class="pa"><button class="btn btn-p" id="gco-add-btn" onclick="openNameCreate()" style="display:none">➕ Добавить товар</button></div>
  </div>
  <div class="ca">
    <div class="fbar">
      <div class="fi"><div class="fl">Категория</div><select class="fsel" id="gco-cat" onchange="gcCatChange()"><option value="">Все категории</option></select></div>
      <div class="fi"><div class="fl">Раздел</div><select class="fsel" id="gco-sec" onchange="loadCatalog()"><option value="">Все разделы</option></select></div>
      <div class="fi"><div class="fl">Статус</div>
        <select class="fsel" id="gco-st" onchange="loadCatalog()">
          <option value="">Все</option><option value="Не согласовано">Не согласовано</option><option value="Согласовано">Согласовано</option>
        </select>
      </div>
      <div class="fi" style="flex:1;min-width:190px"><div class="fl">Поиск</div>
        <div class="ac-wrap" style="position:relative">
          <input class="finp ac-inp" id="gco-s" placeholder="Название..." oninput="gcSearchInput()" onfocus="gcSearchFocus()" autocomplete="off" style="width:100%">
          <div class="ac-drop" id="gco-s-drop" style="min-width:260px"></div>
        </div>
      </div>
    </div>
    <div class="pgrid" id="gco-grid"><div class="es"><div class="spin" style="margin:0 auto 14px"></div>Загрузка...</div></div>
  </div>
</div>

