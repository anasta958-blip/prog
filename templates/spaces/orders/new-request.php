<div id="page-doc" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">📋</span>Новая заявка</div>
    <div class="pa">
      <button class="btn btn-g" onclick="showPage('orders')">← Назад</button>
      <button class="btn btn-gr" onclick="saveDocument()">💾 Сохранить</button>
    </div>
  </div>
  <div class="ca">
    <div class="dmbar">
      <div class="field" style="margin:0"><label>Адрес объекта</label><input type="text" id="doc-addr" placeholder="Введите адрес"></div>
      <div class="field" style="margin:0"><label>Тип объекта</label>
        <select id="doc-type" onchange="docTypeChange()">
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
      <div class="field" style="margin:0"><label>Тип клиента</label><input type="text" id="doc-num" placeholder="Введите тип клиента"></div>
      <div class="field" style="margin:0"><label>РОП</label><input type="text" id="doc-rop" disabled></div>
    </div>
    <div id="doc-builder"></div>
    <button class="btn btn-p" id="doc-add-cat-btn" onclick="docAddCat()" style="margin-top:14px">➕ Добавить категорию</button>
  </div>
</div>
