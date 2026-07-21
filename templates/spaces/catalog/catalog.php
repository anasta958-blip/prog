<div id="page-catalog">
  <div class="ph">
    <div class="pt"><span class="ic">🗂️</span>Каталог товаров</div>
    <div class="pa" style="display:flex;gap:10px;flex-wrap:wrap">
      <a class="btn btn-g" id="gc-template-products-btn" href="<?= assetUrl('templates/catalog_import_products_template.csv') ?>" download style="display:none; text-decoration: none;">⬇️ Шаблон товаров</a>
      <a class="btn btn-g" id="gc-template-services-btn" href="<?= assetUrl('templates/catalog_import_services_template.csv') ?>" download style="display:none; text-decoration: none;">⬇️ Шаблон работ</a>
      <label class="btn btn-g" id="gc-import-btn" for="gc-catalog-import" style="display:none">⬆️ Импорт .xlsx/.csv</label>
      <input type="file" id="gc-catalog-import" accept=".xlsx,.csv" style="display:none" onchange="importGeneralCatalogFile(this)">
      <button class="btn btn-g" id="gc-export-btn" onclick="exportGeneralCatalog()">⬇️ Экспорт CSV</button>
      <button class="btn btn-p" id="gc-add-btn" onclick="openGeneralCatalogCreate()" style="display:none">➕ Добавить товар</button>
    </div>
  </div>
  <div class="ca">
    <div class="ftabs" id="gc-mode-tabs" style="margin-bottom:18px">
      <div class="ftab active" data-mode="equipment" onclick="setGeneralCatalogMode('equipment')">Оборудование</div>
      <div class="ftab" data-mode="materials" onclick="setGeneralCatalogMode('materials')">Материалы</div>
      <div class="ftab" data-mode="consumables" onclick="setGeneralCatalogMode('consumables')">Расходный материал</div>
      <div class="ftab" data-mode="work" onclick="setGeneralCatalogMode('work')">Работы</div>
      <div class="ftab" data-mode="construction_works" onclick="setGeneralCatalogMode('construction_works')">Строительные работы</div>
      <div class="ftab" data-mode="incidental_expenses" onclick="setGeneralCatalogMode('incidental_expenses')">Сопутствующие расходы</div>
      <div class="ftab" data-mode="maintenance" onclick="setGeneralCatalogMode('maintenance')">Обслуживание</div>
      <div class="ftab" data-mode="kits" onclick="setGeneralCatalogMode('kits')">Комплекты</div>
    </div>
    <div class="fbar">
      <div class="fi" id="gc-fi-sec"><div class="fl">Раздел</div><select class="fsel" id="gc-sec" onchange="loadCatalog();persistNavigationState()"><option value="">Все разделы</option></select></div>
      <div class="fi" id="gc-fi-st"><div class="fl">Статус</div>
        <select class="fsel" id="gc-st" onchange="loadCatalog();persistNavigationState()">
          <option value="">Все</option><option value="Не согласовано" selected>Не согласовано</option><option value="Согласовано">Согласовано</option>
        </select>
      </div>
      <div class="fi" style="flex:1;min-width:190px"><div class="fl">Поиск</div>
        <div class="ac-wrap" style="position:relative">
          <input class="finp ac-inp" id="gc-s" placeholder="Название..." oninput="gcSearchInput()" onfocus="gcSearchFocus()" autocomplete="off" style="width:100%">
          <div class="ac-drop" id="gc-s-drop" style="min-width:260px"></div>
        </div>
      </div>
    </div>
    <div class="pgrid" id="gc-grid"><div class="es"><div class="spin" style="margin:0 auto 14px"></div>Загрузка...</div></div>
    <div class="catalog-pager" id="gc-pager"></div>
  </div>
</div>
