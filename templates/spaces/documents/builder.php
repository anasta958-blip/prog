<div id="page-documents-builder" style="display:none">
  <div class="ph">
    <div class="pt"><span class="ic">📝</span>Документы</div>
    <div class="pa">
      <button class="btn btn-g" id="documents-pdf-btn" onclick="documentsExportPdf()">PDF</button>
      <button class="btn btn-g" id="documents-print-btn" onclick="documentsPrint()">Печать</button>
      <button class="btn btn-g" id="documents-reset-btn" onclick="documentsResetDraft()">↺ Новый черновик</button>
      <button class="btn btn-g" id="documents-duplicate-btn" onclick="documentsDuplicateSelected()">⧉ Дублировать блок</button>
      <button class="btn btn-rd" id="documents-delete-btn" onclick="documentsDeleteTemplate()">🗑 Удалить шаблон</button>
      <button class="btn btn-p" id="documents-save-btn" onclick="documentsSaveDraft()">💾 Сохранить шаблон</button>
    </div>
  </div>
  <div class="ca">
    <div class="docs-builder-top">
      <div class="docs-builder-top-row docs-builder-top-row-main">
        <div class="field" style="margin:0">
          <label>Шаблон</label>
          <select id="documents-template-select" class="finp" onchange="documentsOpenTemplate(this.value)">
            <option value="">— новый шаблон —</option>
          </select>
        </div>
        <div class="field" style="margin:0">
          <label>Версия</label>
          <select id="documents-version-select" class="finp" onchange="documentsOpenTemplateVersion(this.value)">
            <option value="">— текущая версия —</option>
          </select>
        </div>
        <div class="field" style="margin:0">
          <label>Название шаблона</label>
          <input id="documents-title" class="finp" placeholder="Например: Отчет по согласованию КП" oninput="documentsUpdateMeta()">
        </div>
        <div class="field" style="margin:0">
          <label>Имя новой версии</label>
          <input id="documents-version-name" class="finp" placeholder="Например: Клиентская версия 1">
        </div>
        <div class="field" style="margin:0">
          <label>Тип документа</label>
          <select id="documents-source-type" class="finp" onchange="documentsSelectSourceType(this.value)">
            <option value="kp">КП</option>
            <option value="pkp">ПКП</option>
          </select>
        </div>
      </div>
      <div class="docs-builder-top-row docs-builder-top-row-source">
        <div class="field" style="margin:0">
          <label>Источник КП</label>
          <select id="documents-source-quote" class="finp" onchange="documentsSelectSource(this.value)">
            <option value="">— без привязки —</option>
          </select>
        </div>
        <div class="field" style="margin:0">
          <label>Вариант КП</label>
          <select id="documents-source-variant" class="finp" onchange="documentsSelectVariant(this.value)">
            <option value="">— выбранный в КП —</option>
          </select>
        </div>
        <div class="docs-toolbar-actions docs-builder-row-actions">
          <button class="btn btn-g" type="button" onclick="documentsClearBlocks()">Сброс</button>
          <button class="btn btn-g" onclick="documentsTogglePreviewMode()"><span id="documents-preview-toggle-label">Режим preview</span></button>
        </div>
      </div>
    </div>
    <div class="docs-shell">
      <div class="docs-panel">
        <div class="docs-panel-title">Блоки отчета</div>
        <div class="docs-palette">
          <button class="btn btn-g" onclick="documentsAddBlock('title')">＋ Титул</button>
          <button class="btn btn-g" onclick="documentsAddBlock('text')">＋ Текстовый блок</button>
          <button class="btn btn-g" onclick="documentsAddBlock('field')">＋ Поле из КП</button>
          <button class="btn btn-g" onclick="documentsAddBlock('table')">＋ Таблица позиций</button>
          <button class="btn btn-g" onclick="documentsAddBlock('image')">＋ Изображение / логотип</button>
          <button class="btn btn-g" onclick="documentsAddBlock('signature')">＋ Подпись</button>
          <button class="btn btn-g" onclick="documentsAddBlock('spacer')">＋ Разделитель</button>
        </div>
        <div class="docs-panel-title" style="margin-top:18px">Данные из КП</div>
        <div class="docs-token-list" id="documents-token-list"></div>
      </div>
      <div class="docs-panel">
        <div class="docs-panel-title">Холст документа</div>
        <div id="documents-canvas" class="docs-canvas"></div>
      </div>
      <div class="docs-panel">
        <div class="docs-panel-title">Свойства блока</div>
        <div id="documents-properties" class="docs-props-grid"></div>
      </div>
    </div>
    <div id="documents-measure-root" class="docs-measure-root" aria-hidden="true"></div>
  </div>
</div>
