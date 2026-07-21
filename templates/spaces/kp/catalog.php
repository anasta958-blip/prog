<div id="page-kp-catalog" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">🗂️</span>Каталог товаров</div>
    <div class="pa">
      <label class="btn btn-g" for="kp-catalog-import">⬆️ Импорт .xlsx/.csv</label>
      <input type="file" id="kp-catalog-import" accept=".xlsx,.csv" style="display:none" onchange="importGeneralCatalogFile(this)">
      <button class="btn btn-p" id="kp-catalog-add-product-btn" onclick="openKpProductModal()">➕ Добавить товар</button>
<button class="btn btn-cy" id="kp-catalog-add-service-btn" onclick="openKpServiceModal()">🛠 Добавить работу</button>
    </div>
  </div>
  <div class="ca">
    <div class="fbar">
      <div class="kp-mini-tabs" style="margin-bottom:0">
        <button class="kp-mini-tab active" id="kp-cat-tab-products" onclick="setKpCatalogMode('products')">Оборудование / Материал</button>
        <button class="kp-mini-tab" id="kp-cat-tab-services" onclick="setKpCatalogMode('services')">Работы</button>
      </div>
      <div style="margin-left:auto;color:var(--tx2);font-size:.84rem">
        Импорт: `Тип`, `Категория`, `Раздел`, `Наименование`, `Маркировка`, `Единица измерения`, `Закупочная цена`, `Минимальная цена`, `Розничная цена`, `Работа`, `Стоимость`
      </div>
    </div>
    <div class="fbar">
      <div class="fi"><div class="fl">Категория</div><select class="fsel" id="kp-cat-filter" onchange="renderKpCatalog()"><option value="">Все категории</option><option value="equipment">Оборудование</option><option value="materials">Материалы</option></select></div>
      <div class="fi"><div class="fl">Раздел</div><select class="fsel" id="kp-sec-filter" onchange="renderKpCatalog()"><option value="">Все разделы</option></select></div>
      <div class="fi" style="flex:1;min-width:190px"><div class="fl">Поиск</div><input class="finp" id="kp-search" placeholder="Название..." oninput="renderKpCatalog()"></div>
    </div>
    <div id="kp-catalog-products-view"></div>
    <div id="kp-catalog-services-view" style="display:none"></div>
  </div>
</div>
