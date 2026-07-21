var documentsStorageKey = 'documents_builder_draft_v4';
var documentsPaletteStorageKey = 'documents_builder_palette_groups_v1';
var documentsState = null;
var documentsTemplatesCache = [];
var documentsVersionsCache = [];
var documentsQuotesCache = [];
var documentsCompaniesCache = [];
var documentsClientsCache = [];
var documentsSourceQuoteDetail = null;
var documentsPreviewMode = 'editor';
var documentsDragBlockId = '';
var documentsPointerDrag = null;
var documentsResizeDrag = null;
var documentsResizeStoreBlockedUntil = 0;
var documentsResizeCaptureBound = false;
var documentsContextMenuBlockId = '';
var documentsContextMenuBound = false;
var documentsCurrentVersionId = 0;
var documentsCurrentVersionName = '';
var documentsTokenDefs = [
  { key: 'quote_title', label: 'Название КП' },
  { key: 'quote_number', label: 'Номер КП' },
  { key: 'client_name', label: 'Клиент' },
  { key: 'client_company', label: 'Компания клиента' },
  { key: 'manager_name', label: 'Менеджер' },
  { key: 'workflow_status', label: 'Этап' },
  { key: 'selected_variant', label: 'Выбранный вариант' },
  { key: 'total_sum', label: 'Сумма' },
  { key: 'created_at', label: 'Дата создания' }
];

function documentsDefaultState() {
  return {
    id: 0,
    title: 'Новый отчет',
    document_type: 'kp',
    source_quote_id: '',
    source_variant_label: '',
    page_format: 'a4',
    page_format_scope: 'all',
    page_formats: {},
    selected_page_index: 0,
    theme: '',
    page_header_text: '',
    page_header_align: 'left',
    page_footer_text: '',
    page_footer_align: 'left',
    page_margin_top: 30,
    page_margin_right: 30,
    page_margin_bottom: 30,
    page_margin_left: 30,
    font_family: 'Arial, sans-serif',
    font_size: 12,
    line_height: 1.35,
    blocks: [
      { id: documentsMakeId(), type: 'title', title: '', text: 'Отчет по коммерческому предложению', align: 'left' },
      { id: documentsMakeId(), type: 'field', title: '', field_key: 'client_name', prefix: 'Клиент: ' },
      { id: documentsMakeId(), type: 'text', title: '', text: 'Краткое резюме проекта, выводы, замечания и статус согласования.' },
      { id: documentsMakeId(), type: 'table', title: '', data_source: 'items', columns: '№, Наименование, Марк./Размер, Ед. изм., Кол-во, Цена, Скидка, Сумма', note: '' },
      { id: documentsMakeId(), type: 'signature', title: '', left_label: 'Подготовил', right_label: 'Согласовал' }
    ],
    selected_block_id: ''
  };
}

function documentsClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

function documentsMakeId() {
  return 'docblk-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
}

function documentsInt(value, fallback, min, max) {
  var n = parseInt(value, 10);
  if (!isFinite(n)) n = fallback;
  if (min != null) n = Math.max(min, n);
  if (max != null) n = Math.min(max, n);
  return n;
}

function documentsFloat(value, fallback, min, max) {
  var n = parseFloat(String(value).replace(',', '.'));
  if (!isFinite(n)) n = fallback;
  if (min != null) n = Math.max(min, n);
  if (max != null) n = Math.min(max, n);
  return n;
}

function documentsNormalizeState(raw) {
  var base = documentsDefaultState();
  var state = raw && typeof raw === 'object' ? documentsClone(raw) : documentsClone(base);
  if (!Array.isArray(state.blocks)) state.blocks = documentsClone(base.blocks);
  state.id = parseInt(state.id || 0, 10) || 0;
  state.title = String(state.title || base.title);
  state.document_type = ['kp', 'pkp'].indexOf(String(state.document_type || 'kp')) >= 0 ? String(state.document_type || 'kp') : 'kp';
  state.source_quote_id = String(state.source_quote_id || '');
  state.source_variant_label = String(state.source_variant_label || '');
  state.page_format = documentsNormalizePageFormat(state.page_format || base.page_format);
  state.page_format_scope = state.page_format_scope === 'page' ? 'page' : 'all';
  if (!state.page_formats || typeof state.page_formats !== 'object' || Array.isArray(state.page_formats)) state.page_formats = {};
  Object.keys(state.page_formats).forEach(function (key) {
    var pageNo = parseInt(key, 10);
    if (!(pageNo > 0)) delete state.page_formats[key];
    else state.page_formats[String(pageNo)] = documentsNormalizePageFormat(state.page_formats[key]);
  });
  state.selected_page_index = Math.max(0, parseInt(state.selected_page_index || 0, 10) || 0);
  state.theme = '';
  state.page_header_text = String(state.page_header_text || '');
  state.page_header_align = String(state.page_header_align || 'left');
  state.page_footer_text = String(state.page_footer_text || '');
  state.page_footer_align = String(state.page_footer_align || 'left');
  state.page_margin_top = documentsInt(state.page_margin_top, base.page_margin_top, 0, 180);
  state.page_margin_right = documentsInt(state.page_margin_right, base.page_margin_right, 0, 180);
  state.page_margin_bottom = documentsInt(state.page_margin_bottom, base.page_margin_bottom, 0, 180);
  state.page_margin_left = documentsInt(state.page_margin_left, base.page_margin_left, 0, 180);
  state.font_family = String(state.font_family || base.font_family);
  state.font_size = documentsInt(state.font_size, base.font_size, 7, 48);
  state.line_height = documentsFloat(state.line_height, base.line_height, 1, 2.5);
  state.blocks = state.blocks.map(function (block, index) {
    var next = block && typeof block === 'object' ? block : {};
    if (!next.id) next.id = documentsMakeId();
    if (!next.type) next.type = 'text';
    if (next.title == null) next.title = '';
    if ((next.type === 'table' || next.type === 'category_table' || next.type === 'section_table' || next.type === 'variants_summary') && !next.data_source) next.data_source = 'items';
    if (next.type === 'company_info') {
      if (!Array.isArray(next.meta_field_keys)) next.meta_field_keys = documentsDefaultMetaFieldKeys(next);
      if (!next.company_id) next.company_id = '';
    }
    if (next.type === 'client_info') {
      if (!Array.isArray(next.meta_field_keys)) next.meta_field_keys = documentsDefaultMetaFieldKeys(next);
      if (!next.client_source) next.client_source = 'quote';
      if (!next.client_id) next.client_id = '';
    }
    if (next.type === 'payment_qr') {
      if (!next.company_id) next.company_id = '';
      next.qr_size = documentsInt(next.qr_size, 180, 80, 420);
      next.caption = String(next.caption || '');
    }
    if (next.type === 'layout') {
      next.layout_mode = ['manual', 'row', 'column'].indexOf(next.layout_mode) >= 0 ? next.layout_mode : 'row';
      next.layout_align = ['start', 'center', 'space-between'].indexOf(next.layout_align) >= 0 ? next.layout_align : 'space-between';
      next.equal_child_size = next.equal_child_size !== false;
      next.layout_gap = documentsInt(next.layout_gap, 16, 0, 80);
      if (!next.h) next.h = 260;
    }
    if (next.parent_layout_id) next.parent_layout_id = String(next.parent_layout_id || '');
    if (next.font_size !== undefined && next.font_size !== '') next.font_size = documentsInt(next.font_size, state.font_size, 7, 72);
    if (next.padding_top !== undefined && next.padding_top !== '') next.padding_top = documentsInt(next.padding_top, 0, 0, 120);
    if (next.padding_right !== undefined && next.padding_right !== '') next.padding_right = documentsInt(next.padding_right, 0, 0, 120);
    if (next.padding_bottom !== undefined && next.padding_bottom !== '') next.padding_bottom = documentsInt(next.padding_bottom, 0, 0, 120);
    if (next.padding_left !== undefined && next.padding_left !== '') next.padding_left = documentsInt(next.padding_left, 0, 0, 120);
    if (!next.column_labels || typeof next.column_labels !== 'object' || Array.isArray(next.column_labels)) next.column_labels = {};
    next.locked = next.locked === true;
    next.z_index = parseInt(next.z_index, 10);
    if (!isFinite(next.z_index)) next.z_index = index + 3;
    return next;
  });
  state.selected_block_id = String(state.selected_block_id || '');
  return state;
}

function documentsLoadLocalDraft() {
  try {
    var raw = localStorage.getItem(documentsStorageKey);
    if (!raw) return documentsDefaultState();
    return documentsNormalizeState(JSON.parse(raw));
  } catch (_e) {
    return documentsDefaultState();
  }
}

function documentsPersistLocalDraft() {
  if (!documentsState) return;
  try {
    localStorage.setItem(documentsStorageKey, JSON.stringify(documentsState));
  } catch (_e) {}
}

function documentsEnsureState() {
  if (!documentsState) documentsState = documentsLoadLocalDraft();
  documentsState = documentsNormalizeState(documentsState);
}

function documentsResetVersionMeta() {
  documentsVersionsCache = [];
  documentsCurrentVersionId = 0;
  documentsCurrentVersionName = '';
}

async function loadDocumentsBuilder() {
  if (!accessTabVisibleUi('documents_builder')) return showPage('home');
  documentsEnsureState();
  await Promise.all([documentsLoadTemplates(), documentsLoadQuotes(), documentsLoadCompanies(), documentsLoadClients()]);
  if (documentsState.source_quote_id) {
    await documentsLoadSourceQuoteDetail(documentsState.source_quote_id);
  } else {
    documentsSourceQuoteDetail = null;
  }
  documentsEnsureVariantSelection();
  documentsRenderWorkspace();
}

async function documentsLoadCompanies() {
  try {
    var data = await api('kp.php?action=company_get');
    documentsCompaniesCache = Array.isArray(data && data.profiles) ? data.profiles : (data && data.id ? [data] : []);
  } catch (_e) {
    documentsCompaniesCache = [];
  }
}

async function documentsLoadClients() {
  try {
    var data = await api('kp.php?action=clients');
    documentsClientsCache = apiItems(data).map(documentsNormalizeClientMetaSnapshot);
  } catch (_e) {
    documentsClientsCache = [];
  }
}

async function documentsLoadTemplates() {
  try {
    documentsTemplatesCache = await api('documents.php?action=list');
  } catch (_e) {
    documentsTemplatesCache = [];
  }
}

async function documentsLoadQuotes() {
  try {
    documentsQuotesCache = await api(documentsQuoteApiFile() + '?action=quotes');
  } catch (_e) {
    documentsQuotesCache = [];
  }
}

function documentsQuoteApiFile() {
  return (documentsState && documentsState.document_type === 'pkp') ? 'pkp.php' : 'kp.php';
}

async function documentsLoadSourceQuoteDetail(id) {
  var quoteId = parseInt(id || 0, 10) || 0;
  if (!quoteId) {
    documentsSourceQuoteDetail = null;
    return;
  }
  try {
    documentsSourceQuoteDetail = await api(documentsQuoteApiFile() + '?action=quote_detail&id=' + quoteId);
  } catch (_e) {
    documentsSourceQuoteDetail = null;
  }
}

async function documentsHydrateTemplate(id, versionId) {
  var query = 'documents.php?action=detail&id=' + parseInt(id || 0, 10);
  if (versionId) query += '&version_id=' + parseInt(versionId, 10);
  var row = await api(query);
  documentsState = documentsNormalizeState(row.payload || documentsDefaultState());
  documentsState.id = parseInt(row.id || 0, 10) || 0;
  documentsVersionsCache = Array.isArray(row.versions) ? row.versions : [];
  documentsCurrentVersionId = parseInt(row.selected_version_id || row.current_version_id || 0, 10) || 0;
  documentsCurrentVersionName = String(row.selected_version_name || '');
  if (row.source_quote_id != null) documentsState.source_quote_id = String(row.source_quote_id);
  if (row.document_type) documentsState.document_type = row.document_type === 'pkp' ? 'pkp' : 'kp';
  if (row.page_format) documentsState.page_format = String(row.page_format);
  documentsState.theme = '';
  await documentsLoadQuotes();
  await documentsLoadSourceQuoteDetail(documentsState.source_quote_id);
  documentsEnsureVariantSelection();
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsGetVariantsFromProposalTypes(payload) {
  var proposalTypes = payload && Array.isArray(payload.proposal_types) ? payload.proposal_types : [];
  if (!proposalTypes.length) return [];
  var selectedItems = [];
  var selectedLabels = [];
  proposalTypes.forEach(function (type) {
    var variants = Array.isArray(type.variants) ? type.variants : [];
    if (!variants.length) return;
    var selectedId = String(type.selected_variant_id || '');
    var variant = variants.find(function (item) { return selectedId && String(item.id || '') === selectedId; }) || variants[0];
    selectedLabels.push(String(type.label || '') + (variant.label ? ': ' + String(variant.label) : ''));
    selectedItems = selectedItems.concat(Array.isArray(variant.items) ? variant.items : []);
  });
  if (!selectedItems.length) return [];
  return [{
    id: 'selected-proposal-variants',
    label: selectedLabels.length > 1 ? 'Выбранные варианты' : (selectedLabels[0] || 'Выбранный вариант'),
    vat_mode: payload.vat_mode || 'none',
    items: selectedItems
  }];
}

function documentsGetVariants() {
  var row = documentsSourceQuoteDetail || null;
  var payload = row && row.payload ? row.payload : null;
  if (payload && Array.isArray(payload.variants) && payload.variants.length) return payload.variants;
  return documentsGetVariantsFromProposalTypes(payload);
}

function documentsEnsureVariantSelection() {
  documentsEnsureState();
  var variants = documentsGetVariants();
  if (!variants.length) {
    documentsState.source_variant_label = '';
    return;
  }
  var current = String(documentsState.source_variant_label || '').trim();
  var exists = variants.some(function (variant) {
    return String(variant.label || '').trim() === current;
  });
  if (exists) return;
  var selectedByQuote = String((documentsSourceQuoteDetail && documentsSourceQuoteDetail.selected_variant_label) || '').trim();
  if (selectedByQuote && variants.some(function (variant) { return String(variant.label || '').trim() === selectedByQuote; })) {
    documentsState.source_variant_label = selectedByQuote;
    return;
  }
  documentsState.source_variant_label = String(variants[0].label || '');
}

function documentsRenderWorkspace() {
  documentsEnsureState();
  documentsPreviewMode = 'preview';
  var titleEl = document.getElementById('documents-title');
  var templateEl = document.getElementById('documents-template-select');
  var versionEl = document.getElementById('documents-version-select');
  var versionNameEl = document.getElementById('documents-version-name');
  var sourceEl = document.getElementById('documents-source-quote');
  var sourceTypeEl = document.getElementById('documents-source-type');
  var variantEl = document.getElementById('documents-source-variant');
  var previewLabel = document.getElementById('documents-preview-toggle-label');
  var canWrite = accessCanUi('documents', 'create') || accessCanUi('documents', 'edit');
  var canDelete = accessCanUi('documents', 'delete');

  if (titleEl) titleEl.value = documentsState.title || '';
  if (sourceTypeEl) sourceTypeEl.value = documentsState.document_type || 'kp';
  if (previewLabel) previewLabel.textContent = 'Режим preview';

  if (templateEl) {
    templateEl.innerHTML = '<option value="">— новый шаблон —</option>' + documentsTemplatesCache.map(function (row) {
      var label = row.title || ('Шаблон #' + row.id);
      if (row.current_version_name) label += ' · ' + row.current_version_name;
      return '<option value="' + row.id + '">' + esc(label) + '</option>';
    }).join('');
    templateEl.value = documentsState.id ? String(documentsState.id) : '';
  }

  if (versionEl) {
    versionEl.disabled = !documentsVersionsCache.length;
    versionEl.innerHTML = '<option value="">— текущая версия —</option>' + documentsVersionsCache.map(function (row) {
      var label = row.version_name || ('Версия ' + row.version_no);
      return '<option value="' + row.id + '">' + esc(label) + '</option>';
    }).join('');
    versionEl.value = documentsCurrentVersionId ? String(documentsCurrentVersionId) : '';
  }

  if (versionNameEl && canWrite) {
    if (!versionNameEl.value) {
      var nextVersionNo = documentsVersionsCache.length ? (parseInt(documentsVersionsCache[0].version_no || 0, 10) + 1) : 1;
      versionNameEl.value = documentsState.id ? ('Версия ' + nextVersionNo) : 'Версия 1';
    }
  }

  if (sourceEl) {
    var currentQuote = String(documentsState.source_quote_id || '');
    sourceEl.innerHTML = '<option value="">— без привязки —</option>' + documentsQuotesCache.map(function (row) {
      var title = row.title || ('КП #' + row.id);
      var client = row.client_name || row.client_company_name || '—';
      return '<option value="' + row.id + '">' + esc(title + ' · ' + client) + '</option>';
    }).join('');
    sourceEl.value = currentQuote;
  }

  if (variantEl) {
    var variants = documentsGetVariants();
    variantEl.disabled = !variants.length;
    variantEl.innerHTML = '<option value="">— выбранный в КП —</option>' + variants.map(function (variant) {
      var label = String(variant.label || 'Без названия');
      var items = Array.isArray(variant.items) ? variant.items.length : 0;
      return '<option value="' + esc(label) + '">' + esc(label + ' · позиций: ' + items) + '</option>';
    }).join('');
    variantEl.value = String(documentsState.source_variant_label || '');
  }

  var saveBtn = document.getElementById('documents-save-btn');
  var resetBtn = document.getElementById('documents-reset-btn');
  var duplicateBtn = document.getElementById('documents-duplicate-btn');
  var deleteBtn = document.getElementById('documents-delete-btn');
  if (saveBtn) saveBtn.style.display = canWrite ? '' : 'none';
  if (resetBtn) resetBtn.style.display = canWrite ? '' : 'none';
  if (duplicateBtn) duplicateBtn.style.display = canWrite ? '' : 'none';
  if (deleteBtn) deleteBtn.style.display = canDelete ? '' : 'none';

  documentsRenderTokens();
  documentsRenderCanvas();
  documentsRenderProperties();
  var toggleBtn = previewLabel && previewLabel.closest ? previewLabel.closest('button') : null;
  if (toggleBtn) toggleBtn.style.display = 'none';
  documentsEnsureExtendedPalette();
  documentsEnhancePaletteDrag();
}

function documentsRenderTokens() {
  var el = document.getElementById('documents-token-list');
  if (!el) return;
  el.innerHTML = documentsTokenDefs.map(function (token) {
    return '<button type="button" class="docs-token docs-token-copy" title="Скопировать код" onclick="documentsCopyToken(\'' + esc(token.key) + '\')">' + esc(token.label) + '</button>';
  }).join('');
}

function documentsGetSelectedBlock() {
  documentsEnsureState();
  return (documentsState.blocks || []).find(function (block) {
    return block.id === documentsState.selected_block_id;
  }) || null;
}

function documentsGetSignatureBlock() {
  documentsEnsureState();
  return (documentsState.blocks || []).find(function (block) {
    return block && block.type === 'signature';
  }) || null;
}

function documentsSignatureFooterHeight(block) {
  if (!block) return 0;
  var paddingY = documentsInt(block.padding_top, 0, 0, 120) + documentsInt(block.padding_bottom, 0, 0, 120);
  var fontSize = block.font_size ? documentsInt(block.font_size, documentsState.font_size || 12, 7, 72) : documentsInt(documentsState.font_size, 12, 7, 48);
  var fontDelta = Math.max(0, fontSize - 12) * 2;
  return Math.max(72, 72 + paddingY + fontDelta);
}

function documentsReservedFooterHeight() {
  var signature = documentsGetSignatureBlock();
  return signature ? documentsSignatureFooterHeight(signature) + 18 : 0;
}

function documentsNormalizePageFormat(format) {
  return String(format || '') === 'a4-landscape' ? 'a4-landscape' : 'a4';
}

function documentsPageFormatForPage(pageIndex) {
  documentsEnsureState();
  pageIndex = Math.max(0, parseInt(pageIndex || 0, 10) || 0);
  return documentsNormalizePageFormat(documentsState.page_formats[String(pageIndex + 1)] || documentsState.page_format || 'a4');
}

function documentsActivePageIndex() {
  documentsEnsureState();
  var selected = (documentsState.blocks || []).find(function (block) { return block.id === documentsState.selected_block_id; });
  if (selected && selected.type !== 'signature') {
    return documentsPageIndexForY(parseInt(selected.y || 0, 10) || 0);
  }
  return Math.max(0, parseInt(documentsState.selected_page_index || 0, 10) || 0);
}

function documentsSelectedPageFormatValue() {
  documentsEnsureState();
  return documentsState.page_format_scope === 'page'
    ? documentsPageFormatForPage(documentsActivePageIndex())
    : documentsNormalizePageFormat(documentsState.page_format || 'a4');
}

function documentsPreviewPageClass(format) {
  var formatClass = documentsNormalizePageFormat(format || documentsState.page_format) === 'a4-landscape' ? 'docs-format-a4-landscape' : 'docs-format-a4';
  return 'docs-preview-page ' + formatClass;
}

function documentsGetMeasureRoot() {
  return document.getElementById('documents-measure-root');
}

function documentsPagePixelSize(format) {
  return documentsNormalizePageFormat(format || documentsState.page_format) === 'a4-landscape'
    ? { width: 1123, height: 794 }
    : { width: 794, height: 1123 };
}

function documentsMaxPagePixelWidth() {
  documentsEnsureState();
  var width = documentsPagePixelSize(documentsState.page_format).width;
  Object.keys(documentsState.page_formats || {}).forEach(function (key) {
    width = Math.max(width, documentsPagePixelSize(documentsState.page_formats[key]).width);
  });
  return width;
}

function documentsGetPreviewScale() {
  var canvas = document.getElementById('documents-canvas');
  var width = documentsMaxPagePixelWidth();
  if (!canvas || !width) return 1;
  var available = Math.max(320, canvas.clientWidth - 36);
  return Math.min(1, available / width);
}

function documentsCreateMeasurePage(format) {
  var root = documentsGetMeasureRoot();
  if (!root) return null;
  var size = documentsPagePixelSize(format);
  root.innerHTML = '';
  var page = document.createElement('div');
  page.className = documentsPreviewPageClass(format);
  page.style.width = size.width + 'px';
  page.style.height = size.height + 'px';
  page.style.minHeight = size.height + 'px';
  var content = document.createElement('div');
  content.className = 'docs-preview-page-content';
  var footer = document.createElement('div');
  footer.className = 'docs-preview-page-num';
  footer.textContent = 'Страница 999';
  page.appendChild(content);
  page.appendChild(footer);
  root.appendChild(page);
  return { root: root, page: page, content: content, footer: footer };
}

function documentsCreateMeasureBlockNode(block) {
  var holder = document.createElement('div');
  holder.innerHTML = documentsRenderBlockPreviewHtml(block);
  return holder;
}

function documentsPaginateBlocks() {
  var blocks = documentsState.blocks || [];
  if (!blocks.length) return [[]];
  var measure = documentsCreateMeasurePage();
  if (!measure) return [blocks.slice()];
  var pages = [];
  var current = [];
  blocks.forEach(function (block) {
    var node = documentsCreateMeasureBlockNode(block);
    measure.content.appendChild(node);
    var contentHeight = Math.ceil(measure.content.scrollHeight);
    var contentLimit = Math.floor(measure.content.clientHeight);
    if (current.length && contentHeight > contentLimit) {
      measure.content.removeChild(node);
      pages.push(current.slice());
      current = [block];
      measure.content.innerHTML = '';
      measure.content.appendChild(documentsCreateMeasureBlockNode(block));
    } else {
      current.push(block);
    }
  });
  if (current.length || !pages.length) pages.push(current.slice());
  measure.root.innerHTML = '';
  return pages;
}

function documentsBlockTypeLabel(type) {
  return ({
    title: 'Титул',
    text: 'Текст',
    field: 'Поле',
    table: 'Таблица',
    category_table: 'Таблица категорий',
    section_table: 'Таблица разделов',
    variants_summary: 'Сводка всех вариантов',
    company_info: 'Компания',
    client_info: 'Клиент',
    payment_qr: 'QR код',
    layout: 'Компоновка',
    image: 'Изображение',
    signature: 'Подпись',
    spacer: 'Разделитель'
  })[type] || type;
}

function documentsBlockSummary(block) {
  if (block.type === 'category_table') return 'Сводка по категориям выбранного варианта';
  if (block.type === 'section_table') return 'Сводка по разделам выбранного варианта';
  if (block.type === 'variants_summary') return 'Сравнение всех вариантов КП';
  if (block.type === 'company_info') return 'Данные компании из справочника в виде таблицы';
  if (block.type === 'client_info') return 'Данные клиента из справочника или выбранного КП';
  if (block.type === 'payment_qr') return 'QR код по расчётному счёту компании';
  if (block.type === 'layout') {
    var childCount = documentsGetLayoutChildren(block.id).length;
    return 'Контейнер для связанных блоков · внутри: ' + childCount;
  }
  if (block.type === 'title') return esc(block.text || '—');
  if (block.type === 'text') return esc(block.text || '—');
  if (block.type === 'field') return esc((block.prefix || '') + '{{' + (block.field_key || 'quote_title') + '}}');
  if (block.type === 'table') {
    var modeLabel = block.data_source === 'summary' ? 'сводка варианта' : 'позиции варианта';
    return esc(modeLabel + ' · ' + (block.columns || '№, Наименование, Марк./Размер, Ед. изм., Кол-во, Цена, Сумма'));
  }
  if (block.type === 'image') {
    return block.image_src ? 'Изображение загружено' : 'Изображение пока не задано';
  }
  if (block.type === 'signature') return esc((block.left_label || 'Подготовил') + ' / ' + (block.right_label || 'Согласовал'));
  if (block.type === 'spacer') return 'Пустой отступ между блоками';
  return '—';
}

function documentsRenderProperties() {
  var wrap = document.getElementById('documents-properties');
  if (!wrap) return;
  var block = documentsGetSelectedBlock();
  if (!block) {
    wrap.innerHTML = documentsBuildDocumentSettingsHtml();
    return;
  }
  if (block.type === 'table' || block.type === 'category_table' || block.type === 'section_table' || block.type === 'variants_summary') {
    var sourceSelect = block.type === 'table'
      ? '<div class="field" style="margin:0"><label>Источник данных</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'data_source\',this.value)">' +
          '<option value="items"' + ((block.data_source || 'items') === 'items' ? ' selected' : '') + '>Позиции варианта</option>' +
          '<option value="summary"' + ((block.data_source || 'items') === 'summary' ? ' selected' : '') + '>Сводка / итоги / маржа</option>' +
        '</select></div>'
      : '';
    var totalsOptions = documentsIsPositionsTable(block)
      ? '<div class="field" style="margin:0"><label>Итоги под таблицей</label>' + documentsBuildPositionsTableOptionsHtml(block) + '</div>'
      : '';
    wrap.innerHTML =
      documentsPropsSectionHtml('Основное', 
      '<div class="field" style="margin:0"><label>Название блока</label><input class="finp" value="' + esc(block.title || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'title\',this.value)"></div>' +
      sourceSelect +
      '<div class="field" style="margin:0"><label>Колонки таблицы</label>' + documentsBuildColumnsPickerHtml(block) + '</div>' +
      totalsOptions +
      '<div class="field" style="margin:0"><label>Примечание</label><textarea class="finp" rows="5" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'note\',this.value)">' + esc(block.note || '') + '</textarea></div>', true) +
      documentsBuildLayoutFieldsHtml(block);
    return;
  }
  if (block.type === 'company_info' || block.type === 'client_info') {
    var sourceHtml = block.type === 'company_info'
      ? '<div class="field" style="margin:0"><label>Компания</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'company_id\',this.value)">' + documentsCompanyOptionsHtml(block.company_id || '') + '</select></div>'
      : '<div class="field" style="margin:0"><label>Источник клиента</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'client_source\',this.value)">' +
          '<option value="quote"' + (block.client_source !== 'catalog' ? ' selected' : '') + '>Клиент выбранного КП</option>' +
          '<option value="catalog"' + (block.client_source === 'catalog' ? ' selected' : '') + '>Клиент из справочника</option>' +
        '</select></div>' +
        (block.client_source === 'catalog'
          ? '<div class="field" style="margin:0"><label>Клиент</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'client_id\',this.value)">' + documentsClientOptionsHtml(block.client_id || '') + '</select></div>'
          : '');
    wrap.innerHTML =
      documentsPropsSectionHtml('Основное',
      '<div class="field" style="margin:0"><label>Название блока</label><input class="finp" value="' + esc(block.title || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'title\',this.value)"></div>' +
      sourceHtml +
      '<div class="field" style="margin:0"><label>Поля таблицы</label>' + documentsBuildMetaFieldsPickerHtml(block) + '</div>', true) +
      documentsBuildLayoutFieldsHtml(block);
    return;
  }
  if (block.type === 'payment_qr') {
    wrap.innerHTML =
      documentsPropsSectionHtml('Основное',
      '<div class="field" style="margin:0"><label>Название блока</label><input class="finp" value="' + esc(block.title || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'title\',this.value)"></div>' +
      '<div class="field" style="margin:0"><label>Компания</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'company_id\',this.value)">' + documentsCompanyOptionsHtml(block.company_id || '') + '</select></div>' +
      '<div class="field" style="margin:0"><label>Размер QR, px</label><input type="number" min="80" max="420" step="10" class="finp" value="' + esc(block.qr_size || 180) + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'qr_size\',this.value)"></div>' +
      '<div class="field" style="margin:0"><label>Подпись</label><input class="finp" value="' + esc(block.caption || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'caption\',this.value)"></div>', true) +
      documentsBuildLayoutFieldsHtml(block);
    return;
  }
  if (block.type === 'layout') {
    wrap.innerHTML =
      documentsPropsSectionHtml('Основное',
      '<div class="field" style="margin:0"><label>Название блока</label><input class="finp" value="' + esc(block.title || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'title\',this.value)"></div>' +
      '<div class="field" style="margin:0"><label>Расположение внутри</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'layout_mode\',this.value)">' +
        '<option value="row"' + ((block.layout_mode || 'row') === 'row' ? ' selected' : '') + '>В строку</option>' +
        '<option value="column"' + ((block.layout_mode || 'row') === 'column' ? ' selected' : '') + '>В колонку</option>' +
        '<option value="manual"' + ((block.layout_mode || 'row') === 'manual' ? ' selected' : '') + '>Свободно</option>' +
      '</select></div>' +
      '<div class="field" style="margin:0"><label>Выравнивание</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'layout_align\',this.value)">' +
        '<option value="space-between"' + ((block.layout_align || 'space-between') === 'space-between' ? ' selected' : '') + '>По краям</option>' +
        '<option value="center"' + ((block.layout_align || 'space-between') === 'center' ? ' selected' : '') + '>По центру</option>' +
        '<option value="start"' + ((block.layout_align || 'space-between') === 'start' ? ' selected' : '') + '>С начала</option>' +
      '</select></div>' +
      '<div class="field" style="margin:0"><label>Отступ между блоками, px</label><input type="number" min="0" max="80" step="2" class="finp" value="' + esc(block.layout_gap || 16) + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'layout_gap\',this.value)"></div>' +
      '<label class="docs-check-row"><input type="checkbox"' + (block.equal_child_size !== false ? ' checked' : '') + ' onchange="documentsUpdateBlockField(\'' + block.id + '\',\'equal_child_size\',this.checked)"> <span>При выравнивании делать внутренние блоки одинаковыми</span></label>' +
      '<button type="button" class="btn btn-g" onclick="documentsArrangeLayoutAction(\'' + block.id + '\')">Выровнять блоки внутри</button>' +
      '<div class="docs-layout-help">Перетащите блок внутрь контейнера или используйте правую кнопку по блоку. Внутренние блоки можно двигать и менять по размеру отдельно. Кнопка “Выровнять блоки внутри” раскладывает их заново по выбранным настройкам.</div>', true) +
      documentsBuildLayoutFieldsHtml(block);
    return;
  }
  var html = '<div class="field" style="margin:0"><label>Название блока</label><input class="finp" value="' + esc(block.title || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'title\',this.value)"></div>';

  if (block.type === 'title' || block.type === 'text') {
    html += '<div class="field" style="margin:0"><label>Текст</label><textarea class="finp" rows="6" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'text\',this.value)">' + esc(block.text || '') + '</textarea></div>';
  }
  if (block.type === 'title') {
    html += '<div class="field" style="margin:0"><label>Выравнивание</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'align\',this.value)">' +
      '<option value="left"' + ((block.align || 'left') === 'left' ? ' selected' : '') + '>Слева</option>' +
      '<option value="center"' + ((block.align || 'left') === 'center' ? ' selected' : '') + '>По центру</option>' +
      '<option value="right"' + ((block.align || 'left') === 'right' ? ' selected' : '') + '>Справа</option>' +
      '</select></div>';
  }
  if (block.type === 'field') {
    html += '<div class="field" style="margin:0"><label>Поле КП</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'field_key\',this.value)">' +
      documentsTokenDefs.map(function (token) {
        return '<option value="' + token.key + '"' + ((block.field_key || 'quote_title') === token.key ? ' selected' : '') + '>' + esc(token.label) + '</option>';
      }).join('') +
      '</select></div>';
    html += '<div class="field" style="margin:0"><label>Префикс</label><input class="finp" value="' + esc(block.prefix || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'prefix\',this.value)"></div>';
  }
  if (block.type === 'table') {
    html += '<div class="field" style="margin:0"><label>Источник данных</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'data_source\',this.value)">' +
      '<option value="items"' + ((block.data_source || 'items') === 'items' ? ' selected' : '') + '>Позиции варианта</option>' +
      '<option value="summary"' + ((block.data_source || 'items') === 'summary' ? ' selected' : '') + '>Сводка / итоги / маржа</option>' +
      '</select></div>';
    html += '<div class="field" style="margin:0"><label>Колонки</label><input class="finp" value="' + esc(block.columns || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'columns\',this.value)"></div>';
    html += '<div class="field" style="margin:0"><label>Примечание</label><textarea class="finp" rows="5" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'note\',this.value)">' + esc(block.note || '') + '</textarea></div>';
  }
  if (block.type === 'image') {
    html += '<div class="field" style="margin:0"><label>Загрузить файл</label><input class="finp" type="file" accept="image/*" onchange="documentsUploadImage(\'' + block.id + '\',this)"></div>';
    html += '<div class="field" style="margin:0"><label>Или вставить URL / data URI</label><input class="finp" value="' + esc(block.image_src || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'image_src\',this.value)"></div>';
    html += '<div class="field" style="margin:0"><label>Подпись</label><input class="finp" value="' + esc(block.caption || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'caption\',this.value)"></div>';
    html += '<div class="field" style="margin:0"><label>Высота, px</label><input type="number" min="40" step="10" class="finp" value="' + esc(block.height || 140) + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'height\',this.value)"></div>';
    html += '<div class="field" style="margin:0"><label>Выравнивание</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'align\',this.value)">' +
      '<option value="left"' + ((block.align || 'left') === 'left' ? ' selected' : '') + '>Слева</option>' +
      '<option value="center"' + ((block.align || 'left') === 'center' ? ' selected' : '') + '>По центру</option>' +
      '<option value="right"' + ((block.align || 'left') === 'right' ? ' selected' : '') + '>Справа</option>' +
      '</select></div>';
    if (block.image_src) {
      html += '<div class="field" style="margin:0"><img class="docs-image-preview" src="' + esc(block.image_src) + '" alt=""></div>';
    }
  }
  if (block.type === 'signature') {
    html += '<div class="field" style="margin:0"><label>Левая подпись</label><input class="finp" value="' + esc(block.left_label || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'left_label\',this.value)"></div>';
    html += '<div class="field" style="margin:0"><label>Правая подпись</label><input class="finp" value="' + esc(block.right_label || '') + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'right_label\',this.value)"></div>';
    wrap.innerHTML = documentsPropsSectionHtml('Основное', html, true);
    return;
  }
  if (block.type === 'spacer') {
    html += '<div class="field" style="margin:0"><label>Высота, px</label><input type="number" min="8" step="4" class="finp" value="' + esc(block.height || 28) + '" oninput="documentsUpdateBlockField(\'' + block.id + '\',\'height\',this.value)"></div>';
  }
  wrap.innerHTML = documentsPropsSectionHtml('Основное', html, true) + documentsBuildLayoutFieldsHtml(block);
}

function documentsNum(value, fallback) {
  var n = parseFloat(value);
  return isFinite(n) ? n : (fallback != null ? fallback : 0);
}

function documentsMoney(value) {
  return documentsNum(value, 0).toFixed(2) + ' ₽';
}

function documentsPluralRu(number, one, few, many) {
  var n = Math.abs(parseInt(number, 10) || 0);
  var n10 = n % 10;
  var n100 = n % 100;
  if (n10 === 1 && n100 !== 11) return one;
  if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few;
  return many;
}

function documentsNumberToWordsRu(value, feminine) {
  var unitsMale = ['', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  var unitsFemale = ['', 'одна', 'две', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'];
  var teens = ['десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать', 'пятнадцать', 'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать'];
  var tens = ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят', 'восемьдесят', 'девяносто'];
  var hundreds = ['', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 'шестьсот', 'семьсот', 'восемьсот', 'девятьсот'];
  var n = Math.max(0, Math.min(999, parseInt(value, 10) || 0));
  var words = [];
  var h = Math.floor(n / 100);
  var rest = n % 100;
  var t = Math.floor(rest / 10);
  var u = rest % 10;
  if (h) words.push(hundreds[h]);
  if (rest >= 10 && rest < 20) {
    words.push(teens[rest - 10]);
  } else {
    if (t) words.push(tens[t]);
    if (u) words.push((feminine ? unitsFemale : unitsMale)[u]);
  }
  return words.join(' ');
}

function documentsMoneyToWordsRu(value) {
  var amount = Math.max(0, Math.round(documentsNum(value, 0) * 100));
  var rubles = Math.floor(amount / 100);
  var kopecks = amount % 100;
  if (!rubles) {
    return 'ноль рублей ' + String(kopecks).padStart(2, '0') + ' ' + documentsPluralRu(kopecks, 'копейка', 'копейки', 'копеек');
  }
  var groups = [
    { forms: ['рубль', 'рубля', 'рублей'], feminine: false },
    { forms: ['тысяча', 'тысячи', 'тысяч'], feminine: true },
    { forms: ['миллион', 'миллиона', 'миллионов'], feminine: false },
    { forms: ['миллиард', 'миллиарда', 'миллиардов'], feminine: false }
  ];
  var parts = [];
  var groupIndex = 0;
  while (rubles > 0 && groupIndex < groups.length) {
    var chunk = rubles % 1000;
    if (chunk) {
      var group = groups[groupIndex];
      var chunkWords = documentsNumberToWordsRu(chunk, group.feminine);
      parts.unshift((chunkWords ? chunkWords + ' ' : '') + documentsPluralRu(chunk, group.forms[0], group.forms[1], group.forms[2]));
    }
    rubles = Math.floor(rubles / 1000);
    groupIndex += 1;
  }
  return parts.join(' ') + ' ' + String(kopecks).padStart(2, '0') + ' ' + documentsPluralRu(kopecks, 'копейка', 'копейки', 'копеек');
}

function documentsGetSelectedVariant() {
  var variants = documentsGetVariants();
  if (!variants.length) return null;
  var selected = String(documentsState.source_variant_label || '').trim();
  return variants.find(function (variant) {
    return String(variant.label || '').trim() === selected;
  }) || variants[0];
}

function documentsGetSelectedVariantLabel() {
  var variant = documentsGetSelectedVariant();
  return variant ? String(variant.label || '') : '';
}

function documentsGetSourceVariantItems() {
  var variant = documentsGetSelectedVariant();
  return variant && Array.isArray(variant.items) ? variant.items : [];
}

function documentsGetSummaryMetricsForVariant(variant) {
  variant = variant || {};
  var items = Array.isArray(variant.items) ? variant.items : [];
  var quantityTotal = 0;
  var computedTotal = 0;
  var computedPurchaseTotal = 0;

  items.forEach(function (item) {
    var qty = documentsNum(item.quantity, 0);
    var lineTotal = item.line_sum != null && item.line_sum !== '' ? documentsNum(item.line_sum, 0) : documentsNum(item.final_price, 0) * qty;
    var purchase = documentsNum(item.purchase_price, 0) * qty;
    quantityTotal += qty;
    computedTotal += lineTotal;
    computedPurchaseTotal += purchase;
  });

  var vatRateRaw = variant.vat_mode != null ? variant.vat_mode : variant.vat_rate;
  var vatRate = typeof vatRateRaw === 'string' && vatRateRaw.toLowerCase().indexOf('без') >= 0 ? 0 : documentsNum(vatRateRaw, 0);
  var total = documentsNum(variant.total, computedTotal);
  var purchaseTotal = documentsNum(variant.purchase_total, computedPurchaseTotal);
  var vatSum = variant.vat_sum != null ? documentsNum(variant.vat_sum, 0) : total * vatRate / 100;
  var totalWithVat = variant.total_with_vat != null ? documentsNum(variant.total_with_vat, 0) : total + vatSum;
  var marginValue = variant.margin_value != null ? documentsNum(variant.margin_value, 0) : total - purchaseTotal;
  var marginPercent = variant.margin_percent != null ? documentsNum(variant.margin_percent, 0) : (purchaseTotal > 0 ? (marginValue / purchaseTotal * 100) : 0);

  return {
    positions_count: items.length,
    quantity_total: quantityTotal,
    total: total,
    vat_rate: vatRate,
    vat_sum: vatSum,
    total_with_vat: totalWithVat,
    purchase_total: purchaseTotal,
    margin_value: marginValue,
    margin_percent: marginPercent
  };
}

function documentsGetSummaryMetrics() {
  return documentsGetSummaryMetricsForVariant(documentsGetSelectedVariant() || {});
}

function documentsGetSummaryRows() {
  var totals = documentsGetSummaryMetrics();
  return [
    ['Вариант', documentsGetSelectedVariantLabel() || '—'],
    ['Количество позиций', String(totals.positions_count)],
    ['Общее количество', String(totals.quantity_total)],
    ['Сумма для клиента', documentsMoney(totals.total)],
    ['Ставка НДС', totals.vat_rate ? String(totals.vat_rate) + '%' : 'Без НДС'],
    ['Сумма НДС', documentsMoney(totals.vat_sum)],
    ['Сумма с НДС', documentsMoney(totals.total_with_vat)],
    ['Итог закупка', documentsMoney(totals.purchase_total)],
    ['Маржа', documentsMoney(totals.margin_value)],
    ['Маржа %', totals.margin_percent ? totals.margin_percent.toFixed(0) + '%' : '0%']
  ];
}

function documentsResolveSource() {
  var row = documentsSourceQuoteDetail || null;
  var payload = row && row.payload ? row.payload : {};
  var client = row && row.client_snapshot ? row.client_snapshot : {};
  var meta = payload && payload.quote_meta ? payload.quote_meta : {};
  var totals = documentsGetSummaryMetrics();
  return {
    quote_title: row ? (row.title || ('КП #' + row.id)) : 'Черновой документ',
    quote_number: row ? ('#' + row.id) : '—',
    client_name: row ? (client.recipient_name || client.company_name || '—') : '—',
    client_company: row ? (client.company_name || '—') : '—',
    manager_name: meta.manager_name || (CU && CU.full_name ? CU.full_name : '—'),
    workflow_status: row ? (row.workflow_status || row.status || '—') : 'Черновик',
    selected_variant: documentsGetSelectedVariantLabel() || '—',
    total_sum: documentsMoney(totals.total),
    created_at: row ? fmtDate(row.created_at) : fmtDate(new Date().toISOString())
  };
}

var documentsCompanyInfoFieldDefs = [
  { key: 'company_type', label: 'Тип компании' },
  { key: 'company_name', label: 'Название компании' },
  { key: 'legal_name', label: 'Юридическое название' },
  { key: 'inn', label: 'ИНН' },
  { key: 'ogrn', label: 'ОГРН' },
  { key: 'kpp', label: 'КПП' },
  { key: 'address', label: 'Адрес' },
  { key: 'phone', label: 'Телефон' },
  { key: 'email', label: 'Email' },
  { key: 'website', label: 'Сайт' },
  { key: 'director_name', label: 'Директор' },
  { key: 'signatory_name', label: 'Подписант' },
  { key: 'signatory_title', label: 'Должность подписанта' },
  { key: 'bank_name', label: 'Банк' },
  { key: 'bank_bik', label: 'БИК' },
  { key: 'bank_account', label: 'Расчётный счёт' },
  { key: 'corr_account', label: 'Корр. счёт' }
];

var documentsClientInfoFieldDefs = [
  { key: 'company_type', label: 'Тип клиента' },
  { key: 'company_name', label: 'Компания' },
  { key: 'legal_name', label: 'Юридическое название' },
  { key: 'recipient_name', label: 'Получатель' },
  { key: 'salutation', label: 'Обращение' },
  { key: 'proposal_title', label: 'Название предложения' },
  { key: 'intro_text', label: 'Вводный текст' },
  { key: 'inn', label: 'ИНН' },
  { key: 'ogrn', label: 'ОГРН' },
  { key: 'kpp', label: 'КПП' },
  { key: 'object_type', label: 'Тип объекта' },
  { key: 'object_address', label: 'Адрес объекта' },
  { key: 'phone', label: 'Телефон' },
  { key: 'email', label: 'Email' },
  { key: 'bank_name', label: 'Банк' },
  { key: 'bank_bik', label: 'БИК' },
  { key: 'bank_account', label: 'Расчётный счёт' },
  { key: 'corr_account', label: 'Корр. счёт' },
  { key: 'passport_series', label: 'Серия паспорта' },
  { key: 'passport_number', label: 'Номер паспорта' },
  { key: 'passport_issued_by', label: 'Кем выдан паспорт' },
  { key: 'note', label: 'Примечание' }
];

function documentsMetaFieldDefsForBlock(block) {
  return block && block.type === 'client_info' ? documentsClientInfoFieldDefs : documentsCompanyInfoFieldDefs;
}

function documentsDefaultMetaFieldKeys(block) {
  return documentsMetaFieldDefsForBlock(block).slice(0, 8).map(function (field) { return field.key; });
}

function documentsCompanyOptionsHtml(selectedId) {
  var rows = Array.isArray(documentsCompaniesCache) ? documentsCompaniesCache : [];
  if (!rows.length) return '<option value="">— компаний нет —</option>';
  var defaultCompany = rows.find(function (row) { return parseInt(row.is_default || 0, 10) === 1; }) || rows[0];
  var effectiveId = selectedId || (defaultCompany ? defaultCompany.id : '');
  return rows.map(function (row) {
    var label = row.company_name || row.legal_name || ('Компания #' + row.id);
    if (parseInt(row.is_default || 0, 10)) label += ' · по умолчанию';
    return '<option value="' + esc(row.id) + '"' + (String(effectiveId || '') === String(row.id) ? ' selected' : '') + '>' + esc(label) + '</option>';
  }).join('');
}

function documentsClientOptionsHtml(selectedId) {
  var rows = Array.isArray(documentsClientsCache) ? documentsClientsCache : [];
  if (!rows.length) return '<option value="">— клиентов нет —</option>';
  var effectiveId = selectedId || (rows[0] ? rows[0].id : '');
  return rows.map(function (row) {
    var label = row.company_name || row.legal_name || row.recipient_name || ('Клиент #' + row.id);
    return '<option value="' + esc(row.id) + '"' + (String(effectiveId || '') === String(row.id) ? ' selected' : '') + '>' + esc(label) + '</option>';
  }).join('');
}

function documentsGetMetaFieldKeys(block) {
  var defs = documentsMetaFieldDefsForBlock(block);
  var allowed = {};
  defs.forEach(function (field) { allowed[field.key] = true; });
  var keys = Array.isArray(block.meta_field_keys) ? block.meta_field_keys.slice() : [];
  keys = keys.filter(function (key, index) { return allowed[key] && keys.indexOf(key) === index; });
  return keys.length ? keys : documentsDefaultMetaFieldKeys(block);
}

function documentsMergeObjects() {
  var result = {};
  Array.prototype.slice.call(arguments).forEach(function (source) {
    if (!source || typeof source !== 'object') return;
    Object.keys(source).forEach(function (key) {
      var value = source[key];
      if (value === null || value === undefined || value === '') return;
      if (result[key] === null || result[key] === undefined || result[key] === '') result[key] = value;
    });
  });
  return result;
}

var DOCUMENTS_CLIENT_META_PREFIX = '__kp_client_meta__:';
function documentsParseClientMetaNote(note) {
  var meta = { legacy_note: '' };
  var raw = String(note || '').trim();
  if (!raw) return meta;
  if (raw.indexOf(DOCUMENTS_CLIENT_META_PREFIX) !== 0) {
    meta.legacy_note = raw;
    return meta;
  }
  try {
    meta = JSON.parse(raw.slice(DOCUMENTS_CLIENT_META_PREFIX.length)) || {};
  } catch (_e) {
    meta = { legacy_note: raw };
  }
  if (!meta || typeof meta !== 'object') meta = { legacy_note: '' };
  if (typeof meta.legacy_note !== 'string') meta.legacy_note = '';
  return meta;
}

function documentsNormalizeClientMetaSnapshot(source) {
  var row = source && typeof source === 'object' ? documentsClone(source) : {};
  var meta = documentsParseClientMetaNote(row.note || '');
  ['passport_series', 'passport_number', 'passport_issued_by', 'bank_account', 'corr_account'].forEach(function (key) {
    if ((row[key] === null || row[key] === undefined || row[key] === '') && meta[key]) row[key] = meta[key];
  });
  if (String(row.note || '').indexOf(DOCUMENTS_CLIENT_META_PREFIX) === 0) row.note = meta.legacy_note || '';
  if (!row.legacy_note && meta.legacy_note) row.legacy_note = meta.legacy_note;
  return row;
}

function documentsGetMetaSnapshot(block) {
  var row = documentsSourceQuoteDetail || null;
  var payload = row && row.payload && typeof row.payload === 'object' ? row.payload : {};
  var meta = payload.quote_meta && typeof payload.quote_meta === 'object' ? payload.quote_meta : {};
  if (block && block.type === 'company_info') {
    var companies = Array.isArray(documentsCompaniesCache) ? documentsCompaniesCache : [];
    var selectedCompany = block.company_id
      ? companies.find(function (company) { return String(company.id) === String(block.company_id); })
      : companies.find(function (company) { return parseInt(company.is_default || 0, 10) === 1; });
    return selectedCompany || companies[0] || {};
  }
  if (block && block.type === 'client_info') {
    var clients = Array.isArray(documentsClientsCache) ? documentsClientsCache : [];
    var clientFromCatalog = null;
    if (block.client_source === 'catalog') {
      clientFromCatalog = block.client_id
        ? clients.find(function (client) { return String(client.id) === String(block.client_id); })
        : clients[0] || null;
      return documentsNormalizeClientMetaSnapshot(clientFromCatalog || {});
    }
    var quoteClientId = row ? (row.client_id || '') : '';
    var clientFromCache = quoteClientId
      ? clients.find(function (client) { return String(client.id) === String(quoteClientId); })
      : null;
    return documentsNormalizeClientMetaSnapshot(documentsMergeObjects(
      clientFromCache || {},
      row && row.client_snapshot && typeof row.client_snapshot === 'object' ? row.client_snapshot : {},
      payload.client_snapshot && typeof payload.client_snapshot === 'object' ? payload.client_snapshot : {}
    ));
  }
  if (!row) return {};
  var contractorId = meta.contractor_id || 0;
  var contractorFromCache = (contractorId && typeof kpContractors !== 'undefined' && Array.isArray(kpContractors))
    ? kpContractors.find(function (contractor) { return String(contractor.id) === String(contractorId); })
    : null;
  return documentsMergeObjects(
    row.company_snapshot && typeof row.company_snapshot === 'object' ? row.company_snapshot : {},
    payload.company_snapshot && typeof payload.company_snapshot === 'object' ? payload.company_snapshot : {},
    meta.contractor_snapshot && typeof meta.contractor_snapshot === 'object' ? meta.contractor_snapshot : {},
    meta.company_snapshot && typeof meta.company_snapshot === 'object' ? meta.company_snapshot : {},
    contractorFromCache || {}
  );
}

function documentsGetCompanyForBlock(block) {
  var companies = Array.isArray(documentsCompaniesCache) ? documentsCompaniesCache : [];
  if (!companies.length) return {};
  if (block && block.company_id) {
    var selected = companies.find(function (company) { return String(company.id) === String(block.company_id); });
    if (selected) return selected;
  }
  return companies.find(function (company) { return parseInt(company.is_default || 0, 10) === 1; }) || companies[0] || {};
}

function documentsQrGfMul(a, b) {
  var p = 0;
  for (var i = 0; i < 8; i += 1) {
    if (b & 1) p ^= a;
    var hi = a & 0x80;
    a = (a << 1) & 0xff;
    if (hi) a ^= 0x1d;
    b >>= 1;
  }
  return p;
}

function documentsQrGfPow(x, power) {
  var y = 1;
  while (power > 0) {
    y = documentsQrGfMul(y, x);
    power -= 1;
  }
  return y;
}

function documentsQrRsGenerator(degree) {
  var poly = [1];
  for (var i = 0; i < degree; i += 1) {
    var root = documentsQrGfPow(2, i);
    var next = new Array(poly.length + 1).fill(0);
    for (var j = 0; j < poly.length; j += 1) {
      next[j] ^= documentsQrGfMul(poly[j], root);
      next[j + 1] ^= poly[j];
    }
    poly = next;
  }
  return poly.slice(0, degree);
}

function documentsQrRsEncode(data, eccLen) {
  var gen = documentsQrRsGenerator(eccLen);
  var res = new Array(eccLen).fill(0);
  data.forEach(function (byte) {
    var factor = byte ^ res.shift();
    res.push(0);
    for (var i = 0; i < eccLen; i += 1) res[i] ^= documentsQrGfMul(gen[i], factor);
  });
  return res;
}

function documentsQrPushBits(bits, value, length) {
  for (var i = length - 1; i >= 0; i -= 1) bits.push((value >>> i) & 1);
}

function documentsQrMakeCodewords(text) {
  var bytes = [];
  String(text || '').slice(0, 32).split('').forEach(function (ch) {
    bytes.push(ch.charCodeAt(0) & 0xff);
  });
  var bits = [];
  documentsQrPushBits(bits, 4, 4);
  documentsQrPushBits(bits, bytes.length, 8);
  bytes.forEach(function (byte) { documentsQrPushBits(bits, byte, 8); });
  var dataCodewords = 34;
  var capacityBits = dataCodewords * 8;
  documentsQrPushBits(bits, 0, Math.min(4, Math.max(0, capacityBits - bits.length)));
  while (bits.length % 8) bits.push(0);
  var data = [];
  for (var i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(''), 2));
  var pads = [0xec, 0x11];
  var padIndex = 0;
  while (data.length < dataCodewords) {
    data.push(pads[padIndex % 2]);
    padIndex += 1;
  }
  return data.concat(documentsQrRsEncode(data, 10));
}

function documentsQrMatrix(text) {
  var size = 25;
  var modules = Array.from({ length: size }, function () { return new Array(size).fill(null); });
  var reserved = Array.from({ length: size }, function () { return new Array(size).fill(false); });
  function set(x, y, dark, reserve) {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    modules[y][x] = !!dark;
    if (reserve) reserved[y][x] = true;
  }
  function finder(x, y) {
    for (var dy = -1; dy <= 7; dy += 1) {
      for (var dx = -1; dx <= 7; dx += 1) {
        var xx = x + dx, yy = y + dy;
        var dark = dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6 && (dx === 0 || dx === 6 || dy === 0 || dy === 6 || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4));
        set(xx, yy, dark, true);
      }
    }
  }
  finder(0, 0); finder(size - 7, 0); finder(0, size - 7);
  for (var i = 8; i < size - 8; i += 1) {
    set(i, 6, i % 2 === 0, true);
    set(6, i, i % 2 === 0, true);
  }
  for (var ay = -2; ay <= 2; ay += 1) {
    for (var ax = -2; ax <= 2; ax += 1) {
      var ad = Math.max(Math.abs(ax), Math.abs(ay)) !== 1;
      set(18 + ax, 18 + ay, ad, true);
    }
  }
  set(8, 17, true, true);
  for (i = 0; i < 9; i += 1) {
    if (i !== 6) { reserved[8][i] = true; reserved[i][8] = true; }
  }
  for (i = 0; i < 8; i += 1) {
    reserved[8][size - 1 - i] = true;
    reserved[size - 1 - i][8] = true;
  }
  var bits = [];
  documentsQrMakeCodewords(text).forEach(function (byte) { documentsQrPushBits(bits, byte, 8); });
  var bitIndex = 0;
  var upward = true;
  for (var x = size - 1; x > 0; x -= 2) {
    if (x === 6) x -= 1;
    for (var yy = 0; yy < size; yy += 1) {
      var y = upward ? size - 1 - yy : yy;
      for (var xx = 0; xx < 2; xx += 1) {
        var cx = x - xx;
        if (reserved[y][cx]) continue;
        var bit = bitIndex < bits.length ? bits[bitIndex] : 0;
        bitIndex += 1;
        var mask = (cx + y) % 2 === 0;
        set(cx, y, !!(bit ^ (mask ? 1 : 0)), false);
      }
    }
    upward = !upward;
  }
  function formatBits(ecl, mask) {
    var data = (ecl << 3) | mask;
    var rem = data << 10;
    var poly = 0x537;
    for (var b = 14; b >= 10; b -= 1) {
      if ((rem >>> b) & 1) rem ^= poly << (b - 10);
    }
    return (((data << 10) | rem) ^ 0x5412) & 0x7fff;
  }
  var fmt = formatBits(1, 0);
  var coords1 = [[8,0],[8,1],[8,2],[8,3],[8,4],[8,5],[8,7],[8,8],[7,8],[5,8],[4,8],[3,8],[2,8],[1,8],[0,8]];
  var coords2 = [[size-1,8],[size-2,8],[size-3,8],[size-4,8],[size-5,8],[size-6,8],[size-7,8],[8,size-8],[8,size-7],[8,size-6],[8,size-5],[8,size-4],[8,size-3],[8,size-2],[8,size-1]];
  for (i = 0; i < 15; i += 1) {
    var dark = ((fmt >>> i) & 1) === 1;
    set(coords1[i][0], coords1[i][1], dark, true);
    set(coords2[i][0], coords2[i][1], dark, true);
  }
  return modules;
}

function documentsQrSvg(text, pixelSize) {
  var matrix = documentsQrMatrix(text);
  var count = matrix.length;
  var border = 4;
  var view = count + border * 2;
  var rects = [];
  for (var y = 0; y < count; y += 1) {
    for (var x = 0; x < count; x += 1) {
      if (matrix[y][x]) rects.push('<rect x="' + (x + border) + '" y="' + (y + border) + '" width="1" height="1"/>');
    }
  }
  return '<svg class="docs-payment-qr-svg" width="' + esc(pixelSize) + '" height="' + esc(pixelSize) + '" viewBox="0 0 ' + view + ' ' + view + '" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="QR код"><rect width="100%" height="100%" fill="#fff"/><g fill="#111827">' + rects.join('') + '</g></svg>';
}

function documentsRenderPaymentQrPreview(block) {
  var company = documentsGetCompanyForBlock(block);
  var account = String(company.bank_account || '').trim();
  var size = documentsInt(block.qr_size, 180, 80, 420);
  if (!account) return '<div class="docs-preview-muted" style="margin-bottom:14px">У выбранной компании не заполнен расчётный счёт</div>';
  var title = block.title ? '<div class="docs-preview-table-title">' + esc(block.title) + '</div>' : '';
  var caption = block.caption || ('Расчётный счёт: ' + account);
  return '<div class="docs-payment-qr-block">' + title + documentsQrSvg(account, size) + '<div class="docs-preview-muted" style="margin-top:8px">' + esc(caption) + '</div></div>';
}

function documentsSnapshotValue(snapshot, keys) {
  for (var i = 0; i < keys.length; i += 1) {
    var key = keys[i];
    var value = snapshot && snapshot[key] != null ? String(snapshot[key]).trim() : '';
    if (value) return value;
  }
  return '';
}

function documentsMetaValue(snapshot, key) {
  var aliases = {
    address: ['address', 'object_address'],
    object_address: ['object_address', 'address'],
    recipient_name: ['recipient_name', 'signatory_name', 'legal_name', 'company_name'],
    director_name: ['director_name', 'director'],
    signatory_name: ['signatory_name', 'recipient_name'],
    signatory_title: ['signatory_title', 'signatory_position'],
    website: ['website', 'site'],
    bank_account: ['bank_account', 'payment_account', 'account'],
    corr_account: ['corr_account', 'correspondent_account']
  };
  var value = documentsSnapshotValue(snapshot, aliases[key] || [key]);
  if (key === 'company_type' && value) {
    var labels = { person: 'Физ. лицо', ip: 'ИП', ooo: 'ООО' };
    return labels[value] || value.toUpperCase();
  }
  return value || '—';
}

function documentsBuildMetaRows(block) {
  var defs = documentsMetaFieldDefsForBlock(block);
  var defsByKey = {};
  defs.forEach(function (field) { defsByKey[field.key] = field; });
  var snapshot = documentsGetMetaSnapshot(block);
  return documentsGetMetaFieldKeys(block).map(function (key) {
    var def = defsByKey[key] || { key: key, label: key };
    return [def.label, documentsMetaValue(snapshot, key)];
  });
}

function documentsRenderMetaTablePreview(block) {
  var rows = documentsBuildMetaRows(block);
  var body = rows.length
    ? rows.map(function (row) {
        return '<tr><th>' + esc(row[0]) + '</th><td>' + esc(row[1]).replace(/\n/g, '<br>') + '</td></tr>';
      }).join('')
    : '<tr><td colspan="2" class="docs-preview-muted">Поля не выбраны</td></tr>';
  return '<div class="docs-preview-table-block docs-meta-table-block">' +
    (block.title ? '<div class="docs-preview-table-title">' + esc(block.title) + '</div>' : '') +
    '<table class="docs-preview-table docs-meta-table"><tbody>' + body + '</tbody></table>' +
  '</div>';
}

function documentsBuildMetaFieldsPickerHtml(block) {
  var keys = documentsGetMetaFieldKeys(block);
  var defsByKey = {};
  documentsMetaFieldDefsForBlock(block).forEach(function (field) { defsByKey[field.key] = field; });
  var ordered = keys.map(function (key) { return defsByKey[key]; }).filter(Boolean);
  documentsMetaFieldDefsForBlock(block).forEach(function (field) {
    if (keys.indexOf(field.key) < 0) ordered.push(field);
  });
  return '<div class="docs-meta-field-picker">' + ordered.map(function (field) {
    var checked = keys.indexOf(field.key) >= 0;
    return '<div class="docs-meta-field-option' + (checked ? '' : ' is-disabled') + '"' +
      (checked ? ' ondragover="documentsMetaFieldDragOver(event)" ondragleave="documentsMetaFieldDragLeave(event)" ondrop="documentsMetaFieldDrop(\'' + block.id + '\',\'' + field.key + '\',event)"' : '') + '>' +
      (checked ? '<button type="button" class="docs-column-drag-handle" draggable="true" title="Перетащить поле" ondragstart="documentsMetaFieldDragStart(\'' + block.id + '\',\'' + field.key + '\',event)" ondragend="documentsMetaFieldDragEnd()">&#8942;&#8942;</button>' : '') +
      '<label>' +
        '<input type="checkbox" value="' + esc(field.key) + '"' + (checked ? ' checked' : '') +
        ' onchange="documentsToggleMetaField(\'' + block.id + '\',\'' + field.key + '\',this.checked)">' +
        '<span>' + esc(field.label) + '</span>' +
      '</label>' +
    '</div>';
  }).join('') + '</div>';
}

function documentsResolveTemplateString(text) {
  var source = documentsResolveSource();
  return String(text || '').replace(/\{\{\s*([a-z0-9_]+)\s*\}\}/gi, function (_m, key) {
    var value = source[key];
    return value == null || value === '' ? '—' : String(value);
  });
}

function documentsResolveDocumentMetaText(text, pageNumber, pageCount) {
  var page = parseInt(pageNumber || 0, 10) || 0;
  var total = parseInt(pageCount || 0, 10) || 0;
  var withPageMeta = String(text || '')
    .replace(/\{\{\s*page_number\s*\}\}/gi, page ? String(page) : '—')
    .replace(/\{\{\s*page_count\s*\}\}/gi, total ? String(total) : '—');
  return documentsResolveTemplateString(withPageMeta);
}

function documentsRenderPageMetaInnerHtml(kind, text, align, pageNumber, pageCount) {
  var value = documentsResolveDocumentMetaText(text, pageNumber, pageCount).trim();
  if (!value) return '';
  var safeAlign = align === 'center' || align === 'right' ? align : 'left';
  return '<div class="docs-page-' + kind + '" style="text-align:' + safeAlign + '">' + esc(value) + '</div>';
}

function documentsRenderPageHeaderInnerHtml(pageNumber, pageCount) {
  return documentsRenderPageMetaInnerHtml(
    'header',
    documentsState.page_header_text || '',
    documentsState.page_header_align || 'left',
    pageNumber,
    pageCount
  );
}

function documentsRenderPageFooterInnerHtml(pageNumber, pageCount) {
  return documentsRenderPageMetaInnerHtml(
    'footer',
    documentsState.page_footer_text || '',
    documentsState.page_footer_align || 'left',
    pageNumber,
    pageCount
  );
}

function documentsGetCategoryLabel(item) {
  return String(item && (item.category_name || item.catName || item.category || '') || '').trim() || '—';
}

function documentsGetSectionLabel(item) {
  return String(item && (item.section_name || item.secName || item.section || '') || '').trim() || '—';
}

function documentsBuildCategoryRows() {
  var map = {};
  documentsGetSourceVariantItems().forEach(function (item) {
    var cat = documentsGetCategoryLabel(item);
    if (!map[cat]) map[cat] = { category: cat, positions: 0, quantity: 0, total: 0 };
    map[cat].positions += 1;
    map[cat].quantity += documentsNum(item.quantity, 0);
    map[cat].total += item.line_sum != null && item.line_sum !== '' ? documentsNum(item.line_sum, 0) : documentsNum(item.final_price, 0) * documentsNum(item.quantity, 0);
  });
  return Object.keys(map).sort().map(function (key) { return map[key]; });
}

function documentsBuildSectionRows() {
  var map = {};
  documentsGetSourceVariantItems().forEach(function (item) {
    var cat = documentsGetCategoryLabel(item);
    var sec = documentsGetSectionLabel(item);
    var key = cat + '||' + sec;
    if (!map[key]) map[key] = { category: cat, section: sec, positions: 0, quantity: 0, total: 0 };
    map[key].positions += 1;
    map[key].quantity += documentsNum(item.quantity, 0);
    map[key].total += item.line_sum != null && item.line_sum !== '' ? documentsNum(item.line_sum, 0) : documentsNum(item.final_price, 0) * documentsNum(item.quantity, 0);
  });
  return Object.keys(map).sort().map(function (key) { return map[key]; });
}

function documentsBuildVariantsSummaryRows() {
  return documentsGetVariants().map(function (variant) {
    var totals = documentsGetSummaryMetricsForVariant(variant);
    return {
      variant: String(variant.label || '—'),
      positions: totals.positions_count,
      quantity: totals.quantity_total,
      total: totals.total,
      purchase: totals.purchase_total,
      margin: totals.margin_value,
      margin_percent: totals.margin_percent
    };
  });
}

function documentsMapTableColumn(label, item, index) {
  var key = String(label || '').trim().toLowerCase();
  if (key.indexOf('наимен') === 0) return item.name || '—';
  if (key.indexOf('марк') === 0) return item.marking_size || '—';
  if (key.indexOf('ед') === 0) return item.unit || '—';
  if (key.indexOf('кол') === 0) return item.quantity != null ? String(item.quantity) : '—';
  if (key.indexOf('закуп') === 0) return item.purchase_price != null ? String(item.purchase_price) : '—';
  if (key.indexOf('цена') === 0) return item.final_price != null ? String(item.final_price) : '—';
  if (key.indexOf('сумм') === 0) return item.line_sum != null ? String(item.line_sum) : '—';
  if (key.indexOf('постав') === 0) return item.supplier || '—';
  if (key.indexOf('примеч') === 0) return item.note || '—';
  if (key.indexOf('№') === 0 || key === 'n' || key === '#') return String(index + 1);
  return '—';
}

function documentsRenderTablePreview(block) {
  return documentsRenderExtendedTablePreview(block);
}

function documentsRenderLayoutChildHtml(block, parent, pageStart) {
  var active = block.id === documentsState.selected_block_id ? ' active' : '';
  var locked = block.locked ? ' locked' : '';
  return '<div class="docs-preview-edit-block positioned docs-layout-child-block' + active + locked + '" data-doc-block-id="' + esc(block.id) + '" draggable="false" style="' + documentsLocalBlockLayoutStyle(block, parent, pageStart) + '"' +
    ' onclick="event.stopPropagation();documentsSelectBlock(\'' + block.id + '\')"' +
    ' oncontextmenu="documentsOpenBlockContextMenu(event,\'' + block.id + '\')"' +
    ' onpointerdown="documentsPreviewPointerDown(event,\'' + block.id + '\')"' +
    ' onmouseup="documentsMaybeStoreResize(this,\'' + block.id + '\')">' +
      '<div class="docs-preview-edit-toolbar">' +
        '<span>' + (block.locked ? '<b class="docs-block-lock-mark" title="Блок закреплён">🔒</b>' : '') + esc(block.title || documentsBlockTypeLabel(block.type)) + '</span>' +
        '<button type="button" onclick="event.stopPropagation();documentsDuplicateSelected()">⧉</button>' +
        '<button type="button" onpointerdown="event.preventDefault();event.stopPropagation()" onclick="event.preventDefault();event.stopPropagation();documentsDeleteBlockFromButton(this,\'' + block.id + '\');return false">×</button>' +
      '</div>' +
      '<div class="docs-preview-edit-content" style="' + documentsBlockContentStyle(block) + '">' + documentsRenderBlockPreviewHtml(block) + '</div>' +
      documentsResizeHandlesHtml(block.id) +
    '</div>';
}

function documentsRenderLayoutPreview(block, pageStart) {
  var children = documentsGetLayoutChildren(block.id).sort(function (a, b) {
    return (parseInt(a.z_index || 0, 10) || 0) - (parseInt(b.z_index || 0, 10) || 0);
  });
  var empty = children.length ? '' : '<div class="docs-layout-empty">Перетащите сюда блоки или выберите “Поместить в компоновку” по правой кнопке.</div>';
  return '<div class="docs-layout-box">' +
    '<div class="docs-layout-stage">' + empty + children.map(function (child) {
      return documentsRenderLayoutChildHtml(child, block, pageStart);
    }).join('') + '</div>' +
  '</div>';
}

function documentsRenderBlockPreviewHtml(block) {
  var source = documentsResolveSource();
  if (block.type === 'category_table' || block.type === 'section_table' || block.type === 'variants_summary') {
    return documentsRenderExtendedTablePreview(block);
  }
  if (block.type === 'title') {
    return '<div style="text-align:' + (block.align || 'left') + ';margin-bottom:18px"><h1>' + esc(documentsResolveDocumentMetaText(block.text || 'Новый отчет')) + '</h1></div>';
  }
  if (block.type === 'text') {
    return '<div style="margin-bottom:16px;white-space:pre-wrap">' + esc(documentsResolveDocumentMetaText(block.text || '')) + '</div>';
  }
  if (block.type === 'field') {
    var value = source[block.field_key || 'quote_title'];
    return '<div style="margin-bottom:12px"><strong>' + esc(block.prefix || '') + '</strong><span class="docs-preview-muted">' + esc(value == null ? '—' : value) + '</span></div>';
  }
  if (block.type === 'table') {
    return documentsRenderTablePreview(block);
  }
  if (block.type === 'company_info' || block.type === 'client_info') {
    return documentsRenderMetaTablePreview(block);
  }
  if (block.type === 'payment_qr') {
    return documentsRenderPaymentQrPreview(block);
  }
  if (block.type === 'layout') {
    return documentsRenderLayoutPreview(block, 0);
  }
  if (block.type === 'image') {
    if (!block.image_src) return '<div class="docs-preview-muted" style="margin-bottom:14px">Изображение не задано</div>';
    var align = block.align || 'left';
    return '<div style="margin-bottom:18px;text-align:' + esc(align) + '"><img src="' + esc(block.image_src) + '" alt="" style="max-width:100%;height:' + (parseInt(block.height || 140, 10) || 140) + 'px;object-fit:contain">' +
      (block.caption ? '<div class="docs-preview-muted" style="margin-top:8px">' + esc(block.caption) + '</div>' : '') + '</div>';
  }
  if (block.type === 'signature') {
    return '<div class="docs-preview-sign"><div><div class="docs-preview-muted">' + esc(block.left_label || 'Подготовил') + '</div><div class="docs-signature-line">__________________</div></div><div><div class="docs-preview-muted">' + esc(block.right_label || 'Согласовал') + '</div><div class="docs-signature-line">__________________</div></div></div>';
  }
  if (block.type === 'spacer') {
    return '<div class="docs-preview-spacer" style="height:' + ((parseInt(block.height || 28, 10) || 28)) + 'px"></div>';
  }
  return '';
}

function documentsRenderPreviewHtml() {
  return (documentsState.blocks || []).map(documentsRenderBlockPreviewHtml).join('');
}

function documentsSelectBlock(id) {
  documentsEnsureState();
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (block && block.type !== 'signature') documentsState.selected_page_index = documentsPageIndexForY(parseInt(block.y || 0, 10) || 0);
  documentsBringBlockForward(id);
}

function documentsSelectCanvasEmpty(event) {
  if (event && event.target && event.target.closest && event.target.closest('.docs-preview-edit-block')) return;
  documentsEnsureState();
  var content = event && event.target && event.target.closest ? event.target.closest('.docs-preview-page-content') : null;
  if (content && content.getAttribute) {
    documentsState.selected_page_index = Math.max(0, parseInt(content.getAttribute('data-page-index') || 0, 10) || 0);
  }
  documentsState.selected_block_id = '';
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsNextBlockLayer() {
  return (documentsState && documentsState.blocks || []).reduce(function (max, block) {
    return Math.max(max, parseInt(block.z_index || 0, 10) || 0);
  }, 2) + 1;
}

function documentsGetLayoutChildren(layoutId) {
  documentsEnsureState();
  return (documentsState.blocks || []).filter(function (block) {
    return block && block.parent_layout_id && String(block.parent_layout_id) === String(layoutId);
  });
}

function documentsGetParentLayout(block) {
  if (!block || !block.parent_layout_id) return null;
  return (documentsState.blocks || []).find(function (item) {
    return item && item.type === 'layout' && String(item.id) === String(block.parent_layout_id);
  }) || null;
}

function documentsIsLayoutChild(block) {
  return !!documentsGetParentLayout(block);
}

function documentsLayoutInnerRect(layout) {
  var pad = 12;
  var x = parseInt(layout.x || 0, 10) || 0;
  var y = parseInt(layout.y || 0, 10) || 0;
  var w = parseInt(layout.w || documentsContentSize().width, 10) || documentsContentSize().width;
  var h = parseInt(layout.h || 260, 10) || 260;
  return { left: x + pad, top: y + 28, right: x + w - pad, bottom: y + h - pad, width: Math.max(20, w - pad * 2), height: Math.max(20, h - 40), pad: pad };
}

function documentsBlockFitsLayout(block, layout) {
  if (!block || !layout || block.id === layout.id || block.type === 'signature' || block.type === 'layout') return false;
  var inner = documentsLayoutInnerRect(layout);
  var rect = documentsBlockRect(block);
  return rect.left >= inner.left && rect.right <= inner.right && rect.top >= inner.top && rect.bottom <= inner.bottom;
}

function documentsBlockCenterInsideLayout(block, layout) {
  if (!block || !layout || block.id === layout.id || block.type === 'signature' || block.type === 'layout') return false;
  var inner = documentsLayoutInnerRect(layout);
  var rect = documentsBlockRect(block);
  var cx = rect.left + rect.width / 2;
  var cy = rect.top + rect.height / 2;
  return cx >= inner.left && cx <= inner.right && cy >= inner.top && cy <= inner.bottom;
}

function documentsClampBlockInsideLayout(block, layout) {
  if (!block || !layout) return;
  var inner = documentsLayoutInnerRect(layout);
  var w = Math.max(80, Math.min(parseInt(block.w || 0, 10) || 220, inner.width));
  var h = Math.max(54, Math.min(parseInt(block.h || 0, 10) || documentsEstimateBlockHeight(block), inner.height));
  block.w = w;
  block.h = h;
  block.x = Math.max(inner.left, Math.min(parseInt(block.x || 0, 10) || inner.left, inner.right - w));
  block.y = Math.max(inner.top, Math.min(parseInt(block.y || 0, 10) || inner.top, inner.bottom - h));
}

function documentsFindLayoutForBlock(block) {
  if (!block || block.type === 'layout' || block.type === 'signature') return null;
  return (documentsState.blocks || []).filter(function (item) {
    return item && item.type === 'layout' && item.id !== block.id;
  }).sort(function (a, b) {
    return (parseInt(b.z_index || 0, 10) || 0) - (parseInt(a.z_index || 0, 10) || 0);
  }).find(function (layout) {
    return documentsBlockFitsLayout(block, layout) || documentsBlockCenterInsideLayout(block, layout);
  }) || null;
}

function documentsAttachBlockToLayout(blockId, layoutId, skipArrange) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === blockId; });
  var layout = (documentsState.blocks || []).find(function (item) { return item.id === layoutId && item.type === 'layout'; });
  if (!block || !layout || block.id === layout.id || block.type === 'layout' || block.type === 'signature') return false;
  if (!documentsBlockFitsLayout(block, layout)) {
    documentsClampBlockInsideLayout(block, layout);
  }
  block.parent_layout_id = layout.id;
  block.locked = false;
  if (!skipArrange && layout.layout_mode !== 'manual') documentsApplyLayoutArrangement(layout.id, true);
  return true;
}

function documentsDetachBlockFromLayout(blockId) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === blockId; });
  if (!block) return false;
  block.parent_layout_id = '';
  return true;
}

function documentsSyncBlockLayoutMembership(blockId) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === blockId; });
  if (!block || block.type === 'layout' || block.type === 'signature') return;
  var current = documentsGetParentLayout(block);
  if (current && documentsBlockFitsLayout(block, current)) return;
  if (current && documentsBlockCenterInsideLayout(block, current)) {
    documentsClampBlockInsideLayout(block, current);
    return;
  }
  if (current && !documentsBlockCenterInsideLayout(block, current)) block.parent_layout_id = '';
  var target = documentsFindLayoutForBlock(block);
  if (target) documentsAttachBlockToLayout(block.id, target.id);
}

function documentsApplyLayoutArrangement(layoutId, silent) {
  var layout = (documentsState.blocks || []).find(function (item) { return item.id === layoutId && item.type === 'layout'; });
  if (!layout) return;
  (documentsState.blocks || []).forEach(function (candidate) {
    if (!candidate || candidate.id === layout.id || candidate.type === 'layout' || candidate.type === 'signature') return;
    if (String(candidate.parent_layout_id || '') === String(layout.id)) return;
    if (documentsBlockCenterInsideLayout(candidate, layout)) documentsAttachBlockToLayout(candidate.id, layout.id, true);
  });
  var children = documentsGetLayoutChildren(layout.id).filter(function (child) { return child.type !== 'signature' && child.type !== 'layout'; });
  if (!children.length) {
    if (!silent) {
      documentsPersistLocalDraft();
      documentsRenderWorkspace();
    }
    return;
  }
  var inner = documentsLayoutInnerRect(layout);
  var gap = documentsInt(layout.layout_gap, 16, 0, 80);
  var mode = layout.layout_mode || 'row';
  var align = layout.layout_align || 'space-between';
  if (mode === 'manual') {
    if (!silent) {
      documentsPersistLocalDraft();
      documentsRenderWorkspace();
    }
    return;
  }
  if (mode === 'column') {
    var childH = layout.equal_child_size !== false
      ? Math.max(50, Math.floor((inner.height - gap * (children.length - 1)) / children.length))
      : null;
    var totalH = children.reduce(function (sum, child) {
      return sum + (childH || (parseInt(child.h || 0, 10) || documentsEstimateBlockHeight(child)));
    }, 0) + gap * (children.length - 1);
    var startY = align === 'center' ? inner.top + Math.max(0, Math.floor((inner.height - totalH) / 2)) : inner.top;
    var cursorY = startY;
    children.forEach(function (child) {
      child.x = inner.left;
      child.y = cursorY;
      child.w = inner.width;
      if (childH) child.h = childH;
      else if (!child.h) child.h = documentsEstimateBlockHeight(child);
      cursorY += (parseInt(child.h || 0, 10) || documentsEstimateBlockHeight(child)) + gap;
    });
  } else {
    var childW = layout.equal_child_size !== false
      ? Math.max(80, Math.floor((inner.width - gap * (children.length - 1)) / children.length))
      : null;
    var maxH = Math.max(50, Math.min(inner.height, Math.floor(inner.height * 0.82)));
    var widths = children.map(function (child) { return childW || Math.min(parseInt(child.w || 0, 10) || 220, inner.width); });
    var totalW = widths.reduce(function (sum, value) { return sum + value; }, 0) + gap * (children.length - 1);
    var actualGap = gap;
    var startX = inner.left;
    if (align === 'center') startX = inner.left + Math.max(0, Math.floor((inner.width - totalW) / 2));
    if (align === 'space-between' && children.length > 1) actualGap = Math.max(gap, Math.floor((inner.width - widths.reduce(function (sum, value) { return sum + value; }, 0)) / (children.length - 1)));
    var cursorX = startX;
    children.forEach(function (child, index) {
      child.x = cursorX;
      child.y = inner.top + Math.max(0, Math.floor((inner.height - (layout.equal_child_size !== false ? maxH : (parseInt(child.h || 0, 10) || documentsEstimateBlockHeight(child)))) / 2));
      child.w = widths[index];
      if (layout.equal_child_size !== false) child.h = maxH;
      else if (!child.h) child.h = documentsEstimateBlockHeight(child);
      cursorX += widths[index] + actualGap;
    });
  }
  if (!silent) {
    documentsPersistLocalDraft();
    documentsRenderWorkspace();
  }
}

function documentsArrangeLayoutAction(layoutId) {
  documentsApplyLayoutArrangement(layoutId, false);
}

function documentsLocalBlockLayoutStyle(block, parent, pageStart) {
  var parentX = parseInt(parent.x || 0, 10) || 0;
  var parentY = parseInt(parent.y || 0, 10) || 0;
  var rawTop = (parseInt(block.y || 0, 10) || 0) - parentY;
  var left = (parseInt(block.x || 0, 10) || 0) - parentX;
  var style = 'position:absolute;left:' + left + 'px;top:' + rawTop + 'px;';
  style += 'width:' + (parseInt(block.w || 220, 10) || 220) + 'px;';
  if (block.h) style += 'height:' + (parseInt(block.h || 0, 10) || 0) + 'px;';
  style += 'z-index:' + (parseInt(block.z_index || 3, 10) || 3) + ';';
  return style;
}

function documentsToggleBlockLock(id) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  block.locked = !block.locked;
  documentsCloseBlockContextMenu();
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsSetBlockLayer(id, direction) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  var layers = (documentsState.blocks || []).filter(function (item) {
    return item.id !== id;
  }).map(function (item) {
    return parseInt(item.z_index || 3, 10) || 3;
  });
  if (direction === 'front') {
    block.z_index = (layers.length ? Math.max.apply(Math, layers) : 2) + 1;
  } else if (direction === 'back') {
    block.z_index = (layers.length ? Math.min.apply(Math, layers) : 3) - 1;
  }
  documentsCloseBlockContextMenu();
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsAttachBlockToNearestLayout(id) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  var layout = documentsFindLayoutForBlock(block);
  if (!layout) {
    toast('Блок должен полностью помещаться внутри компоновки', 'err');
    documentsCloseBlockContextMenu();
    return;
  }
  documentsAttachBlockToLayout(id, layout.id);
  documentsCloseBlockContextMenu();
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsDetachBlockFromLayoutAction(id) {
  if (!documentsDetachBlockFromLayout(id)) return;
  documentsCloseBlockContextMenu();
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsBuildBlockContextMenuHtml(block) {
  if (!block) return '';
  var layoutAction = '';
  if (block.type !== 'layout' && block.type !== 'signature') {
    layoutAction = block.parent_layout_id
      ? '<button type="button" onclick="documentsDetachBlockFromLayoutAction(\'' + block.id + '\')"><span>⤴</span>Убрать из компоновки</button>'
      : '<button type="button" onclick="documentsAttachBlockToNearestLayout(\'' + block.id + '\')"><span>▣</span>Поместить в компоновку</button>';
  }
  return '<button type="button" onclick="documentsToggleBlockLock(\'' + block.id + '\')">' +
      '<span>' + (block.locked ? '🔓' : '🔒') + '</span>' + (block.locked ? 'Открепить блок' : 'Закрепить блок') +
    '</button>' +
    layoutAction +
    '<div class="docs-block-context-separator"></div>' +
    '<button type="button" onclick="documentsSetBlockLayer(\'' + block.id + '\',\'front\')"><span>⬆</span>На передний план</button>' +
    '<button type="button" onclick="documentsSetBlockLayer(\'' + block.id + '\',\'back\')"><span>⬇</span>На задний план</button>';
}

function documentsCloseBlockContextMenu() {
  documentsContextMenuBlockId = '';
  var menu = document.getElementById('documents-block-context-menu');
  if (menu) menu.classList.remove('open');
}

function documentsEnsureBlockContextMenu() {
  var menu = document.getElementById('documents-block-context-menu');
  if (!menu) {
    menu = document.createElement('div');
    menu.id = 'documents-block-context-menu';
    menu.className = 'docs-block-context-menu';
    document.body.appendChild(menu);
  }
  if (!documentsContextMenuBound) {
    documentsContextMenuBound = true;
    document.addEventListener('pointerdown', function (event) {
      if (!event.target.closest || !event.target.closest('#documents-block-context-menu')) documentsCloseBlockContextMenu();
    });
    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') documentsCloseBlockContextMenu();
    });
    window.addEventListener('scroll', documentsCloseBlockContextMenu, true);
    window.addEventListener('resize', documentsCloseBlockContextMenu);
  }
  return menu;
}

function documentsOpenBlockContextMenu(event, id) {
  if (event) {
    event.preventDefault();
    event.stopPropagation();
  }
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  documentsState.selected_block_id = id;
  documentsContextMenuBlockId = id;
  var menu = documentsEnsureBlockContextMenu();
  menu.innerHTML = documentsBuildBlockContextMenuHtml(block);
  menu.classList.add('open');
  var menuWidth = 210;
  var menuHeight = 168;
  var x = Math.min((event && event.clientX) || 0, Math.max(8, window.innerWidth - menuWidth - 8));
  var y = Math.min((event && event.clientY) || 0, Math.max(8, window.innerHeight - menuHeight - 8));
  menu.style.left = Math.max(8, x) + 'px';
  menu.style.top = Math.max(8, y) + 'px';
  documentsPersistLocalDraft();
  documentsRenderProperties();
}

function documentsUpdateBlockField(id, key, value) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  block[key] = value;
  if (key === 'client_source' && value !== 'catalog') block.client_id = '';
  documentsPersistLocalDraft();
  documentsRenderCanvas();
  if (key === 'image_src' || key === 'client_source') documentsRenderProperties();
}


function documentsMoveBlock(index, delta) {
  var blocks = documentsState.blocks || [];
  var target = index + delta;
  if (target < 0 || target >= blocks.length) return;
  var tmp = blocks[index];
  blocks[index] = blocks[target];
  blocks[target] = tmp;
  documentsPersistLocalDraft();
  documentsRenderCanvas();
}

function documentsDeleteBlock(eventOrId, maybeId) {
  if (eventOrId && eventOrId.preventDefault) {
    eventOrId.preventDefault();
    eventOrId.stopPropagation();
  }
  var id = maybeId || eventOrId;
  var deleting = (documentsState.blocks || []).find(function (block) { return block.id === id; });
  if (deleting && deleting.type === 'layout') {
    (documentsState.blocks || []).forEach(function (block) {
      if (block.parent_layout_id === id) block.parent_layout_id = '';
    });
  }
  documentsState.blocks = (documentsState.blocks || []).filter(function (block) { return block.id !== id; });
  if (documentsState.selected_block_id === id) documentsState.selected_block_id = '';
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsDeleteBlockFromButton(button, id) {
  documentsDeleteBlock(id);
}

function documentsUpdateMeta() {
  documentsEnsureState();
  documentsState.title = (document.getElementById('documents-title') || {}).value || '';
  documentsState.document_type = (document.getElementById('documents-source-type') || {}).value || 'kp';
  var pageFormatScopeEl = document.getElementById('documents-page-format-scope');
  if (pageFormatScopeEl) documentsState.page_format_scope = pageFormatScopeEl.value === 'page' ? 'page' : 'all';
  documentsState.theme = '';
  documentsPersistLocalDraft();
  documentsRenderCanvas();
}

function documentsSetPageFormatScope(value) {
  documentsEnsureState();
  documentsState.page_format_scope = value === 'page' ? 'page' : 'all';
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsSetPageFormat(value) {
  documentsEnsureState();
  var format = documentsNormalizePageFormat(value);
  var scope = (document.getElementById('documents-page-format-scope') || {}).value === 'page' ? 'page' : 'all';
  documentsState.page_format_scope = scope;
  if (scope === 'page') {
    var pageNo = documentsActivePageIndex() + 1;
    if (!documentsState.page_formats || typeof documentsState.page_formats !== 'object') documentsState.page_formats = {};
    documentsState.page_formats[String(pageNo)] = format;
  } else {
    documentsState.page_format = format;
    documentsState.page_formats = {};
  }
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

async function documentsSelectSourceType(value) {
  documentsEnsureState();
  var nextType = value === 'pkp' ? 'pkp' : 'kp';
  if (documentsState.document_type === nextType) return;
  documentsState.document_type = nextType;
  documentsState.source_quote_id = '';
  documentsState.source_variant_label = '';
  documentsSourceQuoteDetail = null;
  documentsPersistLocalDraft();
  await documentsLoadQuotes();
  documentsRenderWorkspace();
}

async function documentsSelectSource(value) {
  documentsEnsureState();
  documentsState.source_quote_id = String(value || '');
  documentsState.source_variant_label = '';
  documentsPersistLocalDraft();
  await documentsLoadSourceQuoteDetail(value);
  documentsEnsureVariantSelection();
  documentsRenderWorkspace();
}

function documentsSelectVariant(value) {
  documentsEnsureState();
  documentsState.source_variant_label = String(value || '');
  documentsPersistLocalDraft();
  documentsRenderCanvas();
}

async function documentsOpenTemplate(id) {
  var templateId = parseInt(id || 0, 10) || 0;
  if (!templateId) {
    documentsResetDraft();
    return;
  }
  try {
    await documentsHydrateTemplate(templateId, 0);
  } catch (e) {
    toast(e.message, 'err');
  }
}

async function documentsOpenTemplateVersion(versionId) {
  var templateId = parseInt(documentsState && documentsState.id || 0, 10) || 0;
  var targetVersionId = parseInt(versionId || 0, 10) || 0;
  if (!templateId || !targetVersionId) return;
  try {
    await documentsHydrateTemplate(templateId, targetVersionId);
  } catch (e) {
    toast(e.message, 'err');
  }
}

async function documentsSaveDraft() {
  documentsUpdateMeta();
  var versionNameEl = document.getElementById('documents-version-name');
  var versionName = versionNameEl ? String(versionNameEl.value || '').trim() : '';
  try {
    var res = await api('documents.php', {
      action: 'save',
      id: documentsState.id || 0,
      title: documentsState.title || 'Новый отчет',
      document_type: documentsState.document_type || 'kp',
      version_name: versionName,
      source_quote_id: documentsState.source_quote_id ? parseInt(documentsState.source_quote_id, 10) : 0,
      page_format: documentsState.page_format || 'a4',
      theme: '',
      payload: documentsState
    });
    await documentsLoadTemplates();
    await documentsHydrateTemplate(parseInt(res.id || 0, 10), parseInt(res.version_id || 0, 10));
    if (versionNameEl) versionNameEl.value = '';
    toast('Шаблон документа сохранен');
  } catch (e) {
    toast(e.message, 'err');
  }
}

async function documentsDeleteTemplate() {
  if (!(parseInt(documentsState.id || 0, 10) > 0)) {
    toast('Шаблон еще не сохранен', 'err');
    return;
  }
  if (!confirm('Удалить текущий шаблон документа?')) return;
  try {
    await api('documents.php', { action: 'delete', id: parseInt(documentsState.id, 10) });
    documentsResetDraft();
    await documentsLoadTemplates();
    documentsRenderWorkspace();
    toast('Шаблон удален');
  } catch (e) {
    toast(e.message, 'err');
  }
}

function documentsResetDraft() {
  documentsState = documentsDefaultState();
  documentsSourceQuoteDetail = null;
  documentsPreviewMode = 'editor';
  documentsResetVersionMeta();
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsClearBlocks() {
  documentsEnsureState();
  documentsState.blocks = [];
  documentsState.selected_block_id = '';
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsDuplicateSelected() {
  var block = documentsGetSelectedBlock();
  if (!block) {
    toast('Выберите блок', 'err');
    return;
  }
  var clone = documentsClone(block);
  clone.id = documentsMakeId();
  clone.title = (clone.title || documentsBlockTypeLabel(clone.type)) + ' copy';
  clone.locked = false;
  clone.z_index = documentsNextBlockLayer();
  clone.x = (parseInt(clone.x || 0, 10) || 0) + 16;
  clone.y = (parseInt(clone.y || 0, 10) || 0) + 16;
  var idx = (documentsState.blocks || []).findIndex(function (item) { return item.id === block.id; });
  if (idx < 0) idx = (documentsState.blocks || []).length - 1;
  documentsState.blocks.splice(idx + 1, 0, clone);
  documentsState.selected_block_id = clone.id;
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsTogglePreviewMode() {
  documentsPreviewMode = 'preview';
  documentsRenderCanvas();
}

function documentsHandleDragStart(event, id) {
  documentsDragBlockId = id;
  if (event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', id);
  }
}

function documentsHandleDragOver(event, id) {
  if (!documentsDragBlockId || documentsDragBlockId === id) return;
  event.preventDefault();
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
}

function documentsHandleDrop(event, targetId) {
  event.preventDefault();
  var dragId = documentsDragBlockId || (event.dataTransfer ? event.dataTransfer.getData('text/plain') : '');
  if (!dragId || dragId === targetId) return;
  var blocks = documentsState.blocks || [];
  var from = blocks.findIndex(function (block) { return block.id === dragId; });
  var to = blocks.findIndex(function (block) { return block.id === targetId; });
  if (from < 0 || to < 0) return;
  var moved = blocks.splice(from, 1)[0];
  blocks.splice(to, 0, moved);
  documentsDragBlockId = '';
  documentsPersistLocalDraft();
  documentsRenderCanvas();
}

function documentsHandleDragEnd() {
  documentsDragBlockId = '';
}

function documentsPdfEnsureSpace(doc, y, neededHeight) {
  var pageHeight = doc.internal.pageSize.getHeight();
  if (y + neededHeight <= pageHeight - 40) return y;
  doc.addPage();
  return 40;
}

function documentsPdfImageFormat(src) {
  if (!src) return 'PNG';
  var lower = String(src).toLowerCase();
  if (lower.indexOf('data:image/jpeg') === 0 || lower.indexOf('data:image/jpg') === 0) return 'JPEG';
  if (lower.indexOf('data:image/webp') === 0) return 'WEBP';
  return 'PNG';
}

function documentsUpdateStateField(key, value) {
  documentsEnsureState();
  documentsState[key] = value;
  documentsPersistLocalDraft();
  documentsRenderCanvas();
}

function documentsUpdateStateNumberField(key, value) {
  documentsEnsureState();
  if (key === 'line_height') {
    var normalizedValue = String(value || '').replace(',', '.');
    if (normalizedValue === '' || /^\d+[.]?$/.test(normalizedValue)) {
      documentsState[key] = normalizedValue;
      documentsPersistLocalDraft();
      if (normalizedValue !== '' && normalizedValue.slice(-1) !== '.') documentsRenderCanvas();
      return;
    }
    documentsState[key] = normalizedValue;
    documentsState = documentsNormalizeState(documentsState);
    documentsPersistLocalDraft();
    documentsRenderCanvas();
    return;
  }
  documentsState[key] = value === '' ? '' : value;
  documentsState = documentsNormalizeState(documentsState);
  documentsPersistLocalDraft();
  documentsRenderCanvas();
}

function documentsInsertPaletteButton(type, label) {
  return '<button class="btn btn-g" type="button" data-doc-btn="' + esc(type) + '" onclick="documentsAddBlock(\'' + esc(type) + '\')">' + esc(label) + '</button>';
}

function documentsLoadPaletteGroupState() {
  try {
    var raw = localStorage.getItem(documentsPaletteStorageKey);
    return raw ? JSON.parse(raw) : {};
  } catch (_e) {
    return {};
  }
}

function documentsSavePaletteGroupState() {
  var state = {};
  document.querySelectorAll('#page-documents-builder .docs-palette-group').forEach(function (group) {
    var key = group.getAttribute('data-doc-palette-group') || '';
    if (key) state[key] = group.open === true;
  });
  try {
    localStorage.setItem(documentsPaletteStorageKey, JSON.stringify(state));
  } catch (_e) {}
}

function documentsEnsureExtendedPalette() {
  var palette = document.querySelector('#page-documents-builder .docs-palette');
  if (!palette) return;
  if (palette.querySelector('.docs-palette-group')) return;
  var groupState = documentsLoadPaletteGroupState();
  var groups = [
    {
      key: 'common',
      title: 'Общее',
      blocks: [
        ['title', '＋ Титул'],
        ['text', '＋ Текстовый блок'],
        ['image', '＋ Изображение / логотип'],
        ['layout', '＋ Компоновка'],
        ['signature', '＋ Подпись'],
        ['spacer', '＋ Разделитель']
      ]
    },
    {
      key: 'quote',
      title: 'КП/ПКП',
      blocks: [
        ['field', '＋ Поле из КП/ПКП'],
        ['table', '＋ Таблица позиций'],
        ['category_table', '＋ Таблица категорий'],
        ['section_table', '＋ Таблица разделов'],
        ['variants_summary', '＋ Сводка всех вариантов']
      ]
    },
    {
      key: 'documents',
      title: 'Документы',
      blocks: [
        ['company_info', '＋ Компания'],
        ['client_info', '＋ Клиент'],
        ['payment_qr', '＋ QR код']
      ]
    }
  ];
  palette.innerHTML = groups.map(function (group) {
    var isOpen = groupState[group.key] === true;
    return '<details class="docs-palette-group" data-doc-palette-group="' + esc(group.key) + '"' + (isOpen ? ' open' : '') + '>' +
      '<summary>' + esc(group.title) + '<b>⌄</b></summary>' +
      '<div class="docs-palette-group-body">' + group.blocks.map(function (item) {
        return documentsInsertPaletteButton(item[0], item[1]);
      }).join('') + '</div>' +
    '</details>';
  }).join('');
  palette.querySelectorAll('.docs-palette-group').forEach(function (group) {
    group.addEventListener('toggle', documentsSavePaletteGroupState);
  });
}

async function documentsUploadImage(id, input) {
  var file = input && input.files && input.files[0];
  if (!file) return;
  var form = new FormData();
  form.append('action', 'upload_image');
  form.append('file', file);
  try {
    var data = await apiUpload('documents.php?action=upload_image', form);
    documentsUpdateBlockField(id, 'image_src', String(data.url || data.path || ''));
    toast('Изображение загружено');
  } catch (e) {
    toast(e.message || 'Ошибка загрузки изображения', 'err');
  } finally {
    if (input) input.value = '';
  }
}

function documentsPdfResolveImageSource(src) {
  if (!src || String(src).indexOf('data:image/') === 0) return Promise.resolve(src || '');
  return fetch(src, { credentials: 'same-origin' }).then(function (res) {
    if (!res.ok) throw new Error('image fetch failed');
    return res.blob();
  }).then(function (blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () { resolve(String(reader.result || '')); };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }).catch(function () { return ''; });
}

async function documentsExportPdf() {
  if (!window.jspdf || !window.jspdf.jsPDF) {
    toast('PDF библиотека не загружена', 'err');
    return;
  }
  var jsPDF = window.jspdf.jsPDF;
  var landscape = documentsState.page_format === 'a4-landscape';
  var doc = new jsPDF({ orientation: landscape ? 'landscape' : 'portrait', unit: 'pt', format: 'a4', compress: true });
  var pageWidth = doc.internal.pageSize.getWidth();
  var pageHeight = doc.internal.pageSize.getHeight();
  var left = 40;
  var right = pageWidth - 40;
  var maxWidth = right - left;
  var y = 46;
  var addNewPage = function () { doc.addPage(); y = 46; };
  var ensureSpace = function (need) { if (y + need > pageHeight - 40) addNewPage(); };

  for (var i = 0; i < (documentsState.blocks || []).length; i += 1) {
    var block = documentsState.blocks[i];
    if (block.type === 'title') {
      ensureSpace(48);
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(20);
      var titleText = documentsResolveDocumentMetaText(block.text || 'Новый отчет');
      var tx = block.align === 'center' ? pageWidth / 2 : (block.align === 'right' ? right : left);
      doc.text(titleText, tx, y, { align: block.align || 'left', maxWidth: maxWidth });
      y += 30;
      continue;
    }
    if (block.type === 'text') {
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(11);
      var textLines = doc.splitTextToSize(documentsResolveDocumentMetaText(block.text || ''), maxWidth);
      ensureSpace(textLines.length * 14 + 12);
      doc.text(textLines, left, y);
      y += textLines.length * 14 + 8;
      continue;
    }
    if (block.type === 'field') {
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(11);
      var source = documentsResolveSource();
      var fieldValue = source[block.field_key || 'quote_title'];
      var fieldLines = doc.splitTextToSize(String(block.prefix || '') + String(fieldValue == null ? '—' : fieldValue), maxWidth);
      ensureSpace(fieldLines.length * 14 + 10);
      doc.text(fieldLines, left, y);
      y += fieldLines.length * 14 + 6;
      continue;
    }
    if (block.type === 'table' || block.type === 'category_table' || block.type === 'section_table' || block.type === 'variants_summary') {
      var cols = documentsGetExtendedTableColumns(block);
      var rows = documentsGetExtendedTableRows(block);
      if (!rows.length) rows = [cols.map(function () { return '—'; })];
      ensureSpace(80);
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(12);
      doc.text(String(block.title || documentsBlockTypeLabel(block.type)), left, y);
      y += 10;
      doc.autoTable({
        startY: y,
        head: [cols],
        body: rows,
        styles: { font: 'helvetica', fontSize: 9, cellPadding: 5, overflow: 'linebreak' },
        headStyles: { fillColor: [31, 41, 55], textColor: 255 },
        margin: { left: left, right: 40 },
        theme: 'grid'
      });
      y = doc.lastAutoTable.finalY + 10;
      var totalLines = documentsBuildPositionsTotalLines(block);
      if (totalLines.length) {
        ensureSpace(totalLines.length * 14 + 6);
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(10);
        totalLines.forEach(function (line) {
          if (line.strong) doc.setFont('helvetica', 'bold');
          else doc.setFont('helvetica', 'normal');
          doc.text(String(line.label) + ': ' + String(line.value), left, y);
          y += 14;
        });
        y += 4;
      }
      if (block.note) {
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(10);
        var noteLines = doc.splitTextToSize(String(block.note), maxWidth);
        ensureSpace(noteLines.length * 12 + 8);
        doc.text(noteLines, left, y);
        y += noteLines.length * 12 + 6;
      }
      continue;
    }
    if (block.type === 'company_info' || block.type === 'client_info') {
      var metaRows = documentsBuildMetaRows(block);
      if (!metaRows.length) metaRows = [['—', '—']];
      ensureSpace(80);
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(12);
      doc.text(String(block.title || documentsBlockTypeLabel(block.type)), left, y);
      y += 10;
      doc.autoTable({
        startY: y,
        body: metaRows,
        styles: { font: 'helvetica', fontSize: 9, cellPadding: 5, overflow: 'linebreak' },
        columnStyles: { 0: { fontStyle: 'bold', cellWidth: Math.min(170, maxWidth * 0.36) } },
        margin: { left: left, right: 40 },
        theme: 'grid'
      });
      y = doc.lastAutoTable.finalY + 10;
      continue;
    }
    if (block.type === 'payment_qr') {
      var qrCompany = documentsGetCompanyForBlock(block);
      var qrAccount = String(qrCompany.bank_account || '').trim();
      var qrSize = documentsInt(block.qr_size, 180, 80, 420);
      ensureSpace(qrSize + 48);
      doc.setFont('helvetica', 'bold');
      doc.setFontSize(12);
      if (block.title) {
        doc.text(String(block.title), left, y);
        y += 12;
      }
      if (qrAccount) {
        var matrix = documentsQrMatrix(qrAccount);
        var border = 4;
        var moduleSize = qrSize / (matrix.length + border * 2);
        doc.setFillColor(255, 255, 255);
        doc.rect(left, y, qrSize, qrSize, 'F');
        doc.setFillColor(17, 24, 39);
        matrix.forEach(function (row, rowIndex) {
          row.forEach(function (dark, colIndex) {
            if (dark) doc.rect(left + (colIndex + border) * moduleSize, y + (rowIndex + border) * moduleSize, moduleSize, moduleSize, 'F');
          });
        });
        y += qrSize + 12;
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(10);
        var qrCaption = block.caption || ('Расчётный счёт: ' + qrAccount);
        doc.text(doc.splitTextToSize(String(qrCaption), maxWidth), left, y);
        y += 18;
      } else {
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(10);
        doc.text('У выбранной компании не заполнен расчётный счёт', left, y);
        y += 18;
      }
      continue;
    }
    if (block.type === 'image') {
      var imgSrc = await documentsPdfResolveImageSource(block.image_src || '');
      ensureSpace((parseInt(block.height || 140, 10) || 140) + 30);
      if (imgSrc) {
        var imgHeight = parseInt(block.height || 140, 10) || 140;
        var imgWidth = Math.min(maxWidth, imgHeight * 3);
        var imgX = left;
        if ((block.align || 'left') === 'center') imgX = left + (maxWidth - imgWidth) / 2;
        if ((block.align || 'left') === 'right') imgX = right - imgWidth;
        try {
          doc.addImage(imgSrc, documentsPdfImageFormat(imgSrc), imgX, y, imgWidth, imgHeight);
          y += imgHeight + 8;
        } catch (_e) {}
      }
      if (block.caption) {
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(10);
        doc.text(String(block.caption), left, y);
        y += 12;
      }
      continue;
    }
    if (block.type === 'signature') {
      ensureSpace(80);
      var mid = left + maxWidth / 2;
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(10);
      doc.text(String(block.left_label || 'Подготовил'), left, y);
      doc.text(String(block.right_label || 'Согласовал'), mid, y);
      y += 26;
      doc.line(left, y, left + 180, y);
      doc.line(mid, y, mid + 180, y);
      y += 20;
      continue;
    }
    if (block.type === 'spacer') {
      y += parseInt(block.height || 28, 10) || 28;
    }
  }

  var pageCount = doc.internal.getNumberOfPages();
  for (var p = 1; p <= pageCount; p += 1) {
    doc.setPage(p);
    var headerText = documentsResolveDocumentMetaText(documentsState.page_header_text || '', p, pageCount).trim();
    var footerText = documentsResolveDocumentMetaText(documentsState.page_footer_text || '', p, pageCount).trim();
    if (headerText) {
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(9);
      var hx = documentsState.page_header_align === 'center' ? pageWidth / 2 : (documentsState.page_header_align === 'right' ? pageWidth - 40 : 40);
      doc.text(headerText, hx, 24, { align: documentsState.page_header_align || 'left', maxWidth: maxWidth });
    }
    if (footerText) {
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(9);
      var fx = documentsState.page_footer_align === 'center' ? pageWidth / 2 : (documentsState.page_footer_align === 'right' ? pageWidth - 40 : 40);
      doc.text(footerText, fx, pageHeight - 24, { align: documentsState.page_footer_align || 'left', maxWidth: maxWidth });
    }
  }
  doc.save((documentsState.title || 'document').replace(/[\\/:*?"<>|]+/g, '_') + '.pdf');
};

var documentsTableColumnDefs = [
  { key: 'number', label: '№' },
  { key: 'group_name', label: 'Группа', default: false },
  { key: 'name', label: 'Наименование' },
  { key: 'marking_size', label: 'Марк./Размер' },
  { key: 'unit', label: 'Ед. изм.' },
  { key: 'quantity', label: 'Кол-во' },
  { key: 'supplier', label: 'Поставщик' },
  { key: 'purchase_price', label: 'Закупка' },
  { key: 'final_price', label: 'Цена' },
  { key: 'discount_value', label: 'Скидка' },
  { key: 'line_sum', label: 'Сумма' },
  { key: 'note', label: 'Примечание' }
];
var documentsSummaryColumnDefs = [
  { key: 'metric', label: 'Показатель' },
  { key: 'value', label: 'Значение' }
];
var documentsCategoryColumnDefs = [
  { key: 'category', label: 'Категория' },
  { key: 'positions', label: 'Позиций' },
  { key: 'quantity', label: 'Кол-во' },
  { key: 'total', label: 'Сумма' }
];
var documentsSectionColumnDefs = [
  { key: 'category', label: 'Категория' },
  { key: 'section', label: 'Раздел' },
  { key: 'positions', label: 'Позиций' },
  { key: 'quantity', label: 'Кол-во' },
  { key: 'total', label: 'Сумма' }
];
var documentsVariantsColumnDefs = [
  { key: 'variant', label: 'Вариант' },
  { key: 'positions', label: 'Позиций' },
  { key: 'quantity', label: 'Кол-во' },
  { key: 'total', label: 'Сумма' },
  { key: 'purchase', label: 'Закупка' },
  { key: 'margin', label: 'Маржа' },
  { key: 'margin_percent', label: 'Маржа %' }
];

function documentsColumnDefsForBlock(block) {
  if (block.type === 'category_table') return documentsCategoryColumnDefs;
  if (block.type === 'section_table') return documentsSectionColumnDefs;
  if (block.type === 'variants_summary') return documentsVariantsColumnDefs;
  if (block.data_source === 'summary') return documentsSummaryColumnDefs;
  return documentsTableColumnDefs;
}

function documentsDefaultColumnKeys(block) {
  return documentsColumnDefsForBlock(block).filter(function (col) {
    return col.default !== false;
  }).map(function (col) { return col.key; });
}

function documentsLegacyColumnKey(label) {
  var key = String(label || '').trim().toLowerCase();
  if (key.indexOf('№') === 0 || key === 'n' || key === '#') return 'number';
  if (key.indexOf('наимен') === 0) return 'name';
  if (key.indexOf('марк') === 0) return 'marking_size';
  if (key.indexOf('ед') === 0) return 'unit';
  if (key.indexOf('кол') === 0) return 'quantity';
  if (key.indexOf('постав') === 0) return 'supplier';
  if (key.indexOf('закуп') === 0) return 'purchase_price';
  if (key.indexOf('цена') === 0) return 'final_price';
  if (key.indexOf('скид') === 0) return 'discount_value';
  if (key.indexOf('сумм') === 0) return 'line_sum';
  if (key.indexOf('примеч') === 0) return 'note';
  if (key.indexOf('показ') === 0) return 'metric';
  if (key.indexOf('знач') === 0) return 'value';
  if (key.indexOf('катег') === 0) return 'category';
  if (key.indexOf('раздел') === 0) return 'section';
  if (key.indexOf('позиц') === 0) return 'positions';
  if (key.indexOf('вариант') === 0) return 'variant';
  if (key.indexOf('маржа %') === 0) return 'margin_percent';
  if (key.indexOf('маржа') === 0) return 'margin';
  return '';
}

function documentsGetBlockColumnKeys(block) {
  var defs = documentsColumnDefsForBlock(block);
  var allowed = {};
  defs.forEach(function (col) { allowed[col.key] = true; });
  var keys = Array.isArray(block.column_keys) ? block.column_keys.slice() : [];
  if (!keys.length && block.columns) {
    keys = String(block.columns || '').split(',').map(documentsLegacyColumnKey).filter(Boolean);
  }
  keys = keys.filter(function (key, idx) { return allowed[key] && keys.indexOf(key) === idx; });
  return keys.length ? keys : documentsDefaultColumnKeys(block);
}

function documentsGetExtendedTableColumns(block) {
  return documentsGetBlockColumnKeys(block).map(function (key) {
    return documentsGetBlockColumnLabel(block,key);
  });
}

function documentsGetBlockColumnLabel(block,key) {
  var customLabels=block && block.column_labels && typeof block.column_labels==='object' ? block.column_labels : {};
  var custom=String(customLabels[key]||'').trim();
  if(custom) return custom;
  var definition=documentsColumnDefsForBlock(block).find(function(column){return column.key===key;});
  return definition && definition.label ? definition.label : key;
}

function documentsGetBlockColumnWidth(block, key) {
  var widths = block && block.column_widths && typeof block.column_widths === 'object' ? block.column_widths : {};
  var raw = widths[key];
  if (raw == null || raw === '') return '';
  var value = String(raw).trim().replace(',', '.');
  var num = parseFloat(value);
  if (!isFinite(num) || num <= 0) return '';
  if (value.indexOf('%') >= 0) return Math.max(4, Math.min(100, num)) + '%';
  return Math.max(24, Math.min(1200, num)) + 'px';
}

function documentsSetBlockColumnWidth(block, key, value) {
  if (!block.column_widths || typeof block.column_widths !== 'object') block.column_widths = {};
  var normalized = String(value || '').trim().replace(',', '.');
  if (!normalized) {
    delete block.column_widths[key];
    return;
  }
  var num = parseFloat(normalized);
  if (!isFinite(num) || num <= 0) {
    delete block.column_widths[key];
    return;
  }
  block.column_widths[key] = normalized.indexOf('%') >= 0
    ? Math.max(4, Math.min(100, num)) + '%'
    : Math.max(24, Math.min(1200, num)) + 'px';
}

function documentsBuildTableColgroupHtml(block) {
  return '<colgroup>' + documentsGetBlockColumnKeys(block).map(function (key) {
    var width = documentsGetBlockColumnWidth(block, key);
    return '<col data-column-key="' + esc(key) + '"' + (width ? ' style="width:' + esc(width) + '"' : '') + '>';
  }).join('') + '</colgroup>';
}

function documentsTableCellByKey(key, row, index) {
  if (key === 'number') return String(index + 1);
  if (key === 'group_name') return row.group_name || '—';
  if (key === 'name') return row.name || '—';
  if (key === 'marking_size') return row.marking_size || '—';
  if (key === 'unit') return row.unit || '—';
  if (key === 'quantity') return row.quantity != null ? String(row.quantity) : '—';
  if (key === 'supplier') return row.supplier || '—';
  if (key === 'purchase_price') return row.purchase_price != null ? String(row.purchase_price) : '—';
  if (key === 'final_price') return row.final_price != null ? String(row.final_price) : '—';
  if (key === 'discount_value') return row.discount_value != null && row.discount_value !== '' ? String(row.discount_value) + '%' : '—';
  if (key === 'line_sum') return row.line_sum != null ? String(row.line_sum) : '—';
  if (key === 'note') return row.note || '—';
  return '—';
}

function documentsObjectCellByKey(key, row) {
  if (key === 'total' || key === 'purchase' || key === 'margin') return documentsMoney(row[key]);
  if (key === 'margin_percent') return row[key] ? documentsNum(row[key], 0).toFixed(0) + '%' : '0%';
  return row[key] != null && row[key] !== '' ? String(row[key]) : '—';
}

function documentsGetExtendedTableRows(block) {
  var keys = documentsGetBlockColumnKeys(block);
  if (block.type === 'category_table') return documentsBuildCategoryRows().map(function (row) { return keys.map(function (key) { return documentsObjectCellByKey(key, row); }); });
  if (block.type === 'section_table') return documentsBuildSectionRows().map(function (row) { return keys.map(function (key) { return documentsObjectCellByKey(key, row); }); });
  if (block.type === 'variants_summary') return documentsBuildVariantsSummaryRows().map(function (row) { return keys.map(function (key) { return documentsObjectCellByKey(key, row); }); });
  if (block.data_source === 'summary') {
    return documentsGetSummaryRows().map(function (row) {
      return keys.map(function (key) { return key === 'metric' ? row[0] : row[1]; });
    });
  }
  return documentsGetSourceVariantItems().map(function (item, idx) {
    return keys.map(function (key) { return documentsTableCellByKey(key, item, idx); });
  });
}

function documentsIsPositionsTable(block) {
  return block && block.type === 'table' && (block.data_source || 'items') === 'items';
}

function documentsPositionsTableTotals() {
  var totals = documentsGetSummaryMetrics();
  var totalAmount = totals.vat_rate ? totals.total_with_vat : totals.total;
  return {
    label: totals.vat_rate ? 'Итого с НДС' : 'Итого без НДС',
    amount: totalAmount,
    amount_text: documentsMoneyToWordsRu(totalAmount),
    positions_count: totals.positions_count
  };
}

function documentsPositionTotalOptionEnabled(block, key) {
  var options = block && block.position_totals && typeof block.position_totals === 'object' ? block.position_totals : {};
  return options[key] !== false;
}

function documentsPositionTotalDefs() {
  return [
    { key: 'total', label: 'Итог с/без НДС' },
    { key: 'words', label: 'Итог прописью' },
    { key: 'count', label: 'Всего наименований' }
  ];
}

function documentsGetPositionTotalOrder(block) {
  var defs = documentsPositionTotalDefs();
  var allowed = {};
  defs.forEach(function (def) { allowed[def.key] = true; });
  var order = Array.isArray(block.position_total_order) ? block.position_total_order.slice() : [];
  order = order.filter(function (key, index) { return allowed[key] && order.indexOf(key) === index; });
  defs.forEach(function (def) {
    if (order.indexOf(def.key) < 0) order.push(def.key);
  });
  return order;
}

function documentsBuildPositionsTableOptionsHtml(block) {
  var defsByKey = {};
  documentsPositionTotalDefs().forEach(function (def) { defsByKey[def.key] = def; });
  return '<div class="docs-position-total-options">' + documentsGetPositionTotalOrder(block).map(function (key) {
    var def = defsByKey[key];
    if (!def) return '';
    var enabled = documentsPositionTotalOptionEnabled(block, key);
    return '<div class="docs-position-total-option' + (enabled ? '' : ' is-disabled') + '"' +
      (enabled ? ' ondragover="documentsPositionTotalDragOver(event)" ondragleave="documentsPositionTotalDragLeave(event)" ondrop="documentsPositionTotalDrop(\'' + block.id + '\',\'' + key + '\',event)"' : '') + '>' +
      (enabled ? '<button type="button" class="docs-column-drag-handle" draggable="true" title="Перетащить строку" ondragstart="documentsPositionTotalDragStart(\'' + block.id + '\',\'' + key + '\',event)" ondragend="documentsPositionTotalDragEnd()">&#8942;&#8942;</button>' : '') +
      '<label>' +
        '<input type="checkbox"' + (enabled ? ' checked' : '') +
        ' onchange="documentsTogglePositionTotalLine(\'' + block.id + '\',\'' + key + '\',this.checked)">' +
        '<span>' + esc(def.label) + '</span>' +
      '</label>' +
    '</div>';
  }).join('') + '</div>';
}

function documentsBuildPositionsTotalLines(block) {
  if (!documentsIsPositionsTable(block)) return [];
  var totals = documentsPositionsTableTotals();
  var rows = {
    total: { label: totals.label, value: documentsMoney(totals.amount), strong: true },
    words: { label: 'Итого прописью', value: totals.amount_text },
    count: { label: 'Всего наименований', value: totals.positions_count + ' на сумму ' + documentsMoney(totals.amount) }
  };
  var lines = [];
  documentsGetPositionTotalOrder(block).forEach(function (key) {
    if (documentsPositionTotalOptionEnabled(block, key) && rows[key]) lines.push(rows[key]);
  });
  return lines;
}

function documentsRenderPositionsTableTotalsHtml(block) {
  if (!documentsIsPositionsTable(block)) return '';
  var lines = documentsBuildPositionsTotalLines(block);
  if (!lines.length) return '';
  return '<div class="docs-table-totals-under">' + lines.map(function (line) {
    return '<div class="docs-table-total-line' + (line.strong ? ' strong' : '') + '">' +
      '<span>' + esc(line.label) + '</span><b>' + esc(line.value) + '</b>' +
    '</div>';
  }).join('') + '</div>';
}

function documentsEstimatedTableRowHeight(block) {
  var fontSize = block && block.font_size ? documentsInt(block.font_size, documentsState.font_size || 12, 7, 72) : documentsInt(documentsState.font_size, 12, 7, 48);
  return Math.max(28, Math.ceil(fontSize * documentsFloat(documentsState.line_height, 1.35, 1, 2.5) + 14));
}

function documentsTableColumnPixelWidths(block, tableWidth) {
  var keys = documentsGetBlockColumnKeys(block);
  var fixedTotal = 0;
  var flexible = [];
  var widths = keys.map(function (key) {
    var raw = documentsGetBlockColumnWidth(block, key);
    if (!raw) {
      flexible.push(key);
      return 0;
    }
    var num = parseFloat(String(raw).replace(',', '.')) || 0;
    var width = String(raw).indexOf('%') >= 0 ? tableWidth * num / 100 : num;
    width = Math.max(24, width);
    fixedTotal += width;
    return width;
  });
  var flexibleWidth = Math.max(24, (tableWidth - fixedTotal) / Math.max(1, flexible.length || keys.length));
  return widths.map(function (width) { return width > 0 ? width : flexibleWidth; });
}

function documentsEstimateTableRowHeight(block, row, tableWidth) {
  var base = documentsEstimatedTableRowHeight(block);
  var fontSize = block && block.font_size ? documentsInt(block.font_size, documentsState.font_size || 12, 7, 72) : documentsInt(documentsState.font_size, 12, 7, 48);
  var lineHeight = Math.max(fontSize + 2, fontSize * documentsFloat(documentsState.line_height, 1.35, 1, 2.5));
  var columnWidths = documentsTableColumnPixelWidths(block, Math.max(120, tableWidth || documentsContentSize().width));
  var maxLines = 1;
  (row || []).forEach(function (value, index) {
    var text = String(value == null ? '' : value);
    var columnWidth = Math.max(24, columnWidths[index] || 80);
    var approxCharsPerLine = Math.max(3, Math.floor((columnWidth - 16) / Math.max(5, fontSize * 0.56)));
    var longestToken = text.split(/\s+/).reduce(function (max, token) { return Math.max(max, token.length); }, 0);
    var wrappedLines = Math.ceil(Math.max(text.length, longestToken) / approxCharsPerLine);
    maxLines = Math.max(maxLines, wrappedLines);
  });
  return Math.max(base, Math.ceil(maxLines * lineHeight + 14));
}

function documentsEstimatePositionsTablePagedHeight(block, rows, tableWidth, titleHeight, headerHeight, paddingY, totalLines, baseRowHeight) {
  var content = documentsContentSize();
  var pageHeight = Math.max(1, parseInt(content.height || 0, 10) || 1);
  var blockY = parseInt(block.y || 0, 10) || 0;
  var footerReserve = documentsReservedFooterHeight();
  var firstPageTop = Math.floor(Math.max(0, blockY) / pageHeight) * pageHeight;
  var scanTop = firstPageTop;
  var rowsDone = 0;
  var lastPageTop = firstPageTop;
  var lastUsed = 0;
  var guard = 0;

  function takeRowsForPage(startIndex, currentPageTop) {
    var pageBottom = currentPageTop + pageHeight;
    var visibleTop = Math.max(blockY, currentPageTop);
    var available = Math.max(0, pageBottom - visibleTop - footerReserve);
    var availableForRows = Math.max(0, available - titleHeight - headerHeight);
    var count = 0;
    var used = 0;
    while (startIndex + count < rows.length) {
      var rowHeight = documentsEstimateTableRowHeight(block, rows[startIndex + count], tableWidth) + 8;
      if (count > 0 && used + rowHeight > availableForRows) break;
      if (count === 0 && rowHeight > availableForRows) break;
      used += rowHeight;
      count += 1;
      if (used >= availableForRows) break;
    }
    return { count: count, used: used };
  }

  if (!rows.length) {
    return Math.max(110, titleHeight + headerHeight + paddingY + 18);
  }

  while (rowsDone < rows.length && guard < rows.length + 64) {
    var pageTake = takeRowsForPage(rowsDone, scanTop);
    if (pageTake.count > 0) {
      rowsDone += pageTake.count;
      lastPageTop = scanTop;
      lastUsed = pageTake.used;
    }
    scanTop += pageHeight;
    guard += 1;
  }

  var totalsHeight = (totalLines || []).length * Math.max(22, baseRowHeight) + (block.note ? 34 : 0);
  var lastPageContentHeight = titleHeight + headerHeight + lastUsed + totalsHeight + paddingY + 18;
  return Math.max(110, (lastPageTop - blockY) + lastPageContentHeight);
}

function documentsPositionsTablePageSlice(block, pageStart) {
  var rows = documentsGetExtendedTableRows(block);
  var content = documentsContentSize();
  var blockY = parseInt(block.y || 0, 10) || 0;
  var pageTop = parseInt(pageStart || 0, 10) || 0;
  var titleHeight = block.title ? 28 : 0;
  var headerHeight = 34;
  var footerReserve = documentsReservedFooterHeight();
  var pageHeight = Math.max(1, parseInt(content.height || 0, 10) || 1);
  function takeRowsForPage(startIndex, currentPageTop) {
    var pageBottom = currentPageTop + pageHeight;
    var visibleTop = Math.max(blockY, currentPageTop);
    var available = Math.max(0, pageBottom - visibleTop - footerReserve);
    var availableForRows = Math.max(0, available - titleHeight - headerHeight);
    var count = 0;
    var used = 0;
    while (startIndex + count < rows.length) {
      var rowHeight = documentsEstimateTableRowHeight(block, rows[startIndex + count], content.width);
      if (count > 0 && used + rowHeight > availableForRows) break;
      if (count === 0 && rowHeight > availableForRows) break;
      used += rowHeight;
      count += 1;
      if (used >= availableForRows) break;
    }
    return count;
  }
  var rowsBefore = 0;
  var firstPageTop = Math.floor(Math.max(0, blockY) / pageHeight) * pageHeight;
  for (var scanTop = firstPageTop; scanTop < pageTop && rowsBefore < rows.length; scanTop += pageHeight) {
    var previousTake = takeRowsForPage(rowsBefore, scanTop);
    if (previousTake <= 0) continue;
    rowsBefore += previousTake;
  }
  var take = 0;
  var currentTake = takeRowsForPage(rowsBefore, pageTop);
  take = currentTake;
  var pageRows = rows.slice(rowsBefore, rowsBefore + take);
  var isLast = rowsBefore + pageRows.length >= rows.length;
  return {
    rows: pageRows,
    is_last: isLast,
    is_continued: rowsBefore > 0,
    has_more: rowsBefore + pageRows.length < rows.length
  };
}

function documentsRenderPositionsTablePagePreview(block, pageStart) {
  var keys = documentsGetBlockColumnKeys(block);
  var columns = documentsGetExtendedTableColumns(block);
  var slice = documentsPositionsTablePageSlice(block, pageStart);
  if (!slice.rows.length && !slice.is_last) return '';
  var header = columns.map(function (label, index) {
    var key = keys[index] || '';
    return '<th>' + esc(label) +
      '<span class="docs-table-column-resizer" onpointerdown="documentsStartTableColumnResize(\'' + block.id + '\',\'' + esc(key) + '\',event)" aria-hidden="true"></span>' +
    '</th>';
  }).join('');
  var body = slice.rows.length
    ? slice.rows.map(function (row) {
        return '<tr>' + row.map(function (value) { return '<td>' + esc(value) + '</td>'; }).join('') + '</tr>';
      }).join('')
    : '<tr><td colspan="' + Math.max(1, columns.length) + '" class="docs-preview-muted">Нет данных</td></tr>';
  return '<div class="docs-preview-table-block">' +
    (block.title ? '<div class="docs-preview-table-title">' + esc(block.title) + (slice.is_continued ? ' · продолжение' : '') + '</div>' : '') +
    '<div class="docs-preview-table-scroll"><table class="docs-preview-table">' +
      documentsBuildTableColgroupHtml(block) +
      '<thead><tr>' + header + '</tr></thead><tbody>' + body + '</tbody>' +
    '</table></div>' +
    (slice.has_more ? '<div class="docs-preview-muted docs-table-continued-note">Продолжение на следующем листе</div>' : '') +
    (slice.is_last ? documentsRenderPositionsTableTotalsHtml(block) : '') +
    (slice.is_last && block.note ? '<div class="docs-preview-muted" style="margin-top:8px">' + esc(documentsResolveDocumentMetaText(block.note)) + '</div>' : '') +
  '</div>';
}

function documentsRenderExtendedTablePreview(block) {
  var keys = documentsGetBlockColumnKeys(block);
  var columns = documentsGetExtendedTableColumns(block);
  var rows = documentsGetExtendedTableRows(block);
  var header = columns.map(function (label, index) {
    var key = keys[index] || '';
    return '<th>' + esc(label) +
      '<span class="docs-table-column-resizer" onpointerdown="documentsStartTableColumnResize(\'' + block.id + '\',\'' + esc(key) + '\',event)" aria-hidden="true"></span>' +
    '</th>';
  }).join('');
  var body = rows.length
    ? rows.map(function (row) {
        return '<tr>' + row.map(function (value) { return '<td>' + esc(value) + '</td>'; }).join('') + '</tr>';
      }).join('')
    : '<tr><td colspan="' + Math.max(1, columns.length) + '" class="docs-preview-muted">Нет данных</td></tr>';
  return '<div class="docs-preview-table-block">' +
    (block.title ? '<div class="docs-preview-table-title">' + esc(block.title) + '</div>' : '') +
    '<div class="docs-preview-table-scroll"><table class="docs-preview-table">' +
      documentsBuildTableColgroupHtml(block) +
      '<thead><tr>' + header + '</tr></thead><tbody>' + body + '</tbody>' +
    '</table></div>' +
    documentsRenderPositionsTableTotalsHtml(block) +
    (block.note ? '<div class="docs-preview-muted" style="margin-top:8px">' + esc(documentsResolveDocumentMetaText(block.note)) + '</div>' : '') +
  '</div>';
}

function documentsBuildColumnsPickerHtml(block) {
  var defs = documentsColumnDefsForBlock(block);
  var defsByKey = {};
  var keys = documentsGetBlockColumnKeys(block);
  defs.forEach(function (col) { defsByKey[col.key] = col; });
  var ordered = keys.map(function (key) { return defsByKey[key]; }).filter(Boolean);
  defs.forEach(function (col) {
    if (keys.indexOf(col.key) < 0) ordered.push(col);
  });
  return '<div class="docs-column-picker docs-column-manager">' + ordered.map(function (col) {
    var index = keys.indexOf(col.key);
    var enabled = index >= 0;
    return '<div class="docs-column-option docs-column-row' + (enabled ? '' : ' is-disabled') + '"' +
      (enabled ? ' ondragover="documentsColumnDragOver(event)" ondragleave="documentsColumnDragLeave(event)" ondrop="documentsColumnDrop(\'' + block.id + '\',\'' + col.key + '\',event)"' : '') + '>' +
      '<div class="docs-column-row-top">' +
        (enabled ? '<button type="button" class="docs-column-drag-handle" draggable="true" title="Перетащить колонку" ondragstart="documentsColumnDragStart(\'' + block.id + '\',\'' + col.key + '\',event)" ondragend="documentsColumnDragEnd(event)">&#8942;&#8942;</button>' : '') +
        '<label class="docs-column-check"><input type="checkbox" value="' + esc(col.key) + '"' + (enabled ? ' checked' : '') +
        ' onchange="documentsToggleTableColumn(\'' + block.id + '\',\'' + col.key + '\',this.checked)"><span>' + esc(col.label) + '</span></label>' +
        (enabled ? '' : '<span class="docs-column-muted">скрыта</span>') +
      '</div>' +
      (enabled ? '<div class="docs-column-row-fields">' +
        '<label class="docs-column-field"><span>Название</span><input class="finp docs-column-label" value="' + esc(documentsGetBlockColumnLabel(block,col.key)) + '" placeholder="' + esc(col.label) + '" ' +
        'oninput="documentsUpdateTableColumnLabel(\'' + block.id + '\',\'' + col.key + '\',this.value)" aria-label="Название колонки ' + esc(col.label) + '"></label>' +
        '<label class="docs-column-field docs-column-field-width"><span>Ширина</span><input class="finp docs-column-width" value="' + esc(documentsGetBlockColumnWidth(block, col.key)) + '" placeholder="авто" ' +
        'oninput="documentsUpdateTableColumnWidth(\'' + block.id + '\',\'' + col.key + '\',this.value)" title="Ширина: 80, 80px или 20%"></label>' +
      '</div>' : '') +
      '</div>';
  }).join('') + '</div>';
}

function documentsUpdateTableColumnLabel(id,key,value) {
  var block=(documentsState.blocks||[]).find(function(item){return item.id===id;});
  if(!block) return;
  if(!block.column_labels || typeof block.column_labels!=='object' || Array.isArray(block.column_labels)) block.column_labels={};
  var label=String(value||'').trim();
  if(label) block.column_labels[key]=label;
  else delete block.column_labels[key];
  block.columns=documentsGetExtendedTableColumns(block).join(', ');
  documentsPersistLocalDraft();
  documentsRenderCanvas();
}

function documentsToggleMetaField(id, key, checked) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  var keys = documentsGetMetaFieldKeys(block);
  if (checked && keys.indexOf(key) < 0) keys.push(key);
  if (!checked) keys = keys.filter(function (item) { return item !== key; });
  if (!keys.length) {
    toast('Нужно оставить хотя бы одно поле', 'err');
    documentsRenderPropertiesPreservePickerScroll();
    return;
  }
  block.meta_field_keys = keys;
  documentsPersistLocalDraft();
  documentsRenderCanvas();
  documentsRenderPropertiesPreservePickerScroll();
}

function documentsRenderPropertiesPreservePickerScroll() {
  var wrap = document.getElementById('documents-properties');
  var panel = wrap ? wrap.closest('.docs-panel') : null;
  var picker = wrap ? wrap.querySelector('.docs-meta-field-picker') : null;
  var scrollTop = picker ? picker.scrollTop : 0;
  var panelScrollTop = panel ? panel.scrollTop : 0;
  documentsRenderProperties();
  requestAnimationFrame(function () {
    var next = document.querySelector('#documents-properties .docs-meta-field-picker');
    if (next) next.scrollTop = scrollTop;
    var nextWrap = document.getElementById('documents-properties');
    var nextPanel = nextWrap ? nextWrap.closest('.docs-panel') : null;
    if (nextPanel) nextPanel.scrollTop = panelScrollTop;
  });
}

var documentsMetaFieldDragState = null;

function documentsClearMetaFieldDropMarks() {
  document.querySelectorAll('.docs-meta-field-option.is-drop-before,.docs-meta-field-option.is-drop-after').forEach(function (row) {
    row.classList.remove('is-drop-before', 'is-drop-after');
  });
}

function documentsMetaFieldDragStart(id, key, event) {
  documentsMetaFieldDragState = { block_id: id, key: key };
  if (event && event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', key);
  }
}

function documentsMetaFieldDragOver(event) {
  if (!documentsMetaFieldDragState || !event || !event.currentTarget) return;
  event.preventDefault();
  documentsClearMetaFieldDropMarks();
  var rect = event.currentTarget.getBoundingClientRect();
  var isAfter = event.clientY > rect.top + rect.height / 2;
  event.currentTarget.classList.add(isAfter ? 'is-drop-after' : 'is-drop-before');
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
}

function documentsMetaFieldDragLeave(event) {
  if (!event || !event.currentTarget) return;
  event.currentTarget.classList.remove('is-drop-before', 'is-drop-after');
}

function documentsMetaFieldDragEnd() {
  documentsMetaFieldDragState = null;
  documentsClearMetaFieldDropMarks();
}

function documentsMetaFieldDrop(id, targetKey, event) {
  if (!documentsMetaFieldDragState || documentsMetaFieldDragState.block_id !== id) return;
  if (event) event.preventDefault();
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) {
    documentsMetaFieldDragEnd();
    return;
  }
  var keys = documentsGetMetaFieldKeys(block);
  var from = keys.indexOf(documentsMetaFieldDragState.key);
  var to = keys.indexOf(targetKey);
  if (from < 0 || to < 0) {
    documentsMetaFieldDragEnd();
    return;
  }
  var rect = event && event.currentTarget ? event.currentTarget.getBoundingClientRect() : null;
  var insertAfter = rect ? event.clientY > rect.top + rect.height / 2 : false;
  var moved = keys.splice(from, 1)[0];
  if (from < to) to -= 1;
  keys.splice(to + (insertAfter ? 1 : 0), 0, moved);
  block.meta_field_keys = keys;
  documentsPersistLocalDraft();
  documentsRenderCanvas();
  documentsMetaFieldDragEnd();
  documentsRenderPropertiesPreservePickerScroll();
}

function documentsToggleTableColumn(id, key, checked) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  var keys = documentsGetBlockColumnKeys(block);
  if (checked && keys.indexOf(key) < 0) keys.push(key);
  if (!checked) keys = keys.filter(function (item) { return item !== key; });
  if (!keys.length) {
    toast('Нужно оставить хотя бы одну колонку', 'err');
    documentsRenderProperties();
    return;
  }
  block.column_keys = keys;
  block.columns = documentsGetExtendedTableColumns(block).join(', ');
  documentsPersistLocalDraft();
  documentsRenderCanvas();
  documentsRenderProperties();
}

function documentsTogglePositionTotalLine(id, key, checked) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  if (!block.position_totals || typeof block.position_totals !== 'object' || Array.isArray(block.position_totals)) block.position_totals = {};
  block.position_totals[key] = checked !== false;
  block.position_total_order = documentsGetPositionTotalOrder(block);
  documentsPersistLocalDraft();
  documentsRenderCanvas();
  documentsRenderPropertiesPreservePickerScroll();
}

var documentsPositionTotalDragState = null;

function documentsClearPositionTotalDropMarks() {
  document.querySelectorAll('.docs-position-total-option.is-drop-before,.docs-position-total-option.is-drop-after').forEach(function (row) {
    row.classList.remove('is-drop-before', 'is-drop-after');
  });
}

function documentsPositionTotalDragStart(id, key, event) {
  documentsPositionTotalDragState = { block_id: id, key: key };
  if (event && event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', key);
  }
}

function documentsPositionTotalDragOver(event) {
  if (!documentsPositionTotalDragState || !event || !event.currentTarget) return;
  event.preventDefault();
  documentsClearPositionTotalDropMarks();
  var rect = event.currentTarget.getBoundingClientRect();
  var isAfter = event.clientY > rect.top + rect.height / 2;
  event.currentTarget.classList.add(isAfter ? 'is-drop-after' : 'is-drop-before');
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
}

function documentsPositionTotalDragLeave(event) {
  if (!event || !event.currentTarget) return;
  event.currentTarget.classList.remove('is-drop-before', 'is-drop-after');
}

function documentsPositionTotalDragEnd() {
  documentsPositionTotalDragState = null;
  documentsClearPositionTotalDropMarks();
}

function documentsPositionTotalDrop(id, targetKey, event) {
  if (!documentsPositionTotalDragState || documentsPositionTotalDragState.block_id !== id) return;
  if (event) event.preventDefault();
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) {
    documentsPositionTotalDragEnd();
    return;
  }
  var order = documentsGetPositionTotalOrder(block);
  var from = order.indexOf(documentsPositionTotalDragState.key);
  var to = order.indexOf(targetKey);
  if (from < 0 || to < 0) {
    documentsPositionTotalDragEnd();
    return;
  }
  var rect = event && event.currentTarget ? event.currentTarget.getBoundingClientRect() : null;
  var insertAfter = rect ? event.clientY > rect.top + rect.height / 2 : false;
  var moved = order.splice(from, 1)[0];
  if (from < to) to -= 1;
  order.splice(to + (insertAfter ? 1 : 0), 0, moved);
  block.position_total_order = order;
  documentsPersistLocalDraft();
  documentsRenderCanvas();
  documentsPositionTotalDragEnd();
  documentsRenderPropertiesPreservePickerScroll();
}

var documentsColumnDragState = null;

function documentsClearColumnDropMarks() {
  document.querySelectorAll('.docs-column-row.is-drop-before,.docs-column-row.is-drop-after').forEach(function (row) {
    row.classList.remove('is-drop-before', 'is-drop-after');
  });
}

function documentsColumnDragStart(id, key, event) {
  documentsColumnDragState = { block_id: id, key: key };
  if (event && event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', key);
  }
}

function documentsColumnDragOver(event) {
  if (!documentsColumnDragState || !event || !event.currentTarget) return;
  event.preventDefault();
  var rect = event.currentTarget.getBoundingClientRect();
  var isAfter = event.clientY > rect.top + rect.height / 2;
  documentsClearColumnDropMarks();
  event.currentTarget.classList.add(isAfter ? 'is-drop-after' : 'is-drop-before');
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
}

function documentsColumnDragLeave(event) {
  if (!event || !event.currentTarget) return;
  event.currentTarget.classList.remove('is-drop-before', 'is-drop-after');
}

function documentsColumnDragEnd() {
  documentsColumnDragState = null;
  documentsClearColumnDropMarks();
}

function documentsColumnDrop(id, targetKey, event) {
  if (!documentsColumnDragState || documentsColumnDragState.block_id !== id) return;
  if (event) {
    event.preventDefault();
    event.stopPropagation();
  }
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  var keys = documentsGetBlockColumnKeys(block);
  var sourceIndex = keys.indexOf(documentsColumnDragState.key);
  var targetIndex = keys.indexOf(targetKey);
  if (sourceIndex < 0 || targetIndex < 0) return;
  if (sourceIndex === targetIndex) {
    documentsColumnDragEnd();
    return;
  }
  var targetRow = event && event.currentTarget;
  var isAfter = false;
  if (targetRow) {
    var rect = targetRow.getBoundingClientRect();
    isAfter = event.clientY > rect.top + rect.height / 2;
  }
  var moved = keys.splice(sourceIndex, 1)[0];
  if (sourceIndex < targetIndex) targetIndex -= 1;
  var insertIndex = targetIndex + (isAfter ? 1 : 0);
  keys.splice(Math.max(0, Math.min(keys.length, insertIndex)), 0, moved);
  block.column_keys = keys;
  block.columns = documentsGetExtendedTableColumns(block).join(', ');
  documentsColumnDragEnd();
  documentsPersistLocalDraft();
  documentsRenderCanvas();
  documentsRenderProperties();
}

function documentsUpdateTableColumnWidth(id, key, value) {
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  documentsSetBlockColumnWidth(block, key, value);
  documentsPersistLocalDraft();
  documentsRenderCanvas();
}

var documentsColumnResizeState = null;

function documentsStartTableColumnResize(id, key, event) {
  if (!event || !event.currentTarget) return;
  event.preventDefault();
  event.stopPropagation();
  var th = event.currentTarget.parentElement;
  var table = th && th.closest ? th.closest('table') : null;
  if (!th || !table) return;
  documentsColumnResizeState = {
    block_id: id,
    key: key,
    start_x: event.clientX,
    start_width: th.getBoundingClientRect().width,
    col: table.querySelector('col[data-column-key="' + key + '"]')
  };
  if (event.currentTarget.setPointerCapture && event.pointerId != null) {
    try { event.currentTarget.setPointerCapture(event.pointerId); } catch (err) {}
  }
  document.body.classList.add('docs-column-resizing');
  document.addEventListener('pointermove', documentsHandleTableColumnResize);
  document.addEventListener('pointerup', documentsStopTableColumnResize);
}

function documentsHandleTableColumnResize(event) {
  if (!documentsColumnResizeState || !event) return;
  event.preventDefault();
  var width = Math.max(24, Math.round(documentsColumnResizeState.start_width + event.clientX - documentsColumnResizeState.start_x));
  var block = (documentsState.blocks || []).find(function (item) { return item.id === documentsColumnResizeState.block_id; });
  if (!block) return;
  documentsSetBlockColumnWidth(block, documentsColumnResizeState.key, width + 'px');
  if (documentsColumnResizeState.col) documentsColumnResizeState.col.style.width = width + 'px';
}

function documentsStopTableColumnResize() {
  if (!documentsColumnResizeState) return;
  documentsColumnResizeState = null;
  document.body.classList.remove('docs-column-resizing');
  document.removeEventListener('pointermove', documentsHandleTableColumnResize);
  document.removeEventListener('pointerup', documentsStopTableColumnResize);
  documentsPersistLocalDraft();
  documentsRenderProperties();
}

function documentsCopyText(text) {
  text = String(text || '');
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(function () { toast('Код скопирован'); }).catch(function () { toast(text); });
    return;
  }
  var ta = document.createElement('textarea');
  ta.value = text;
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand('copy'); toast('Код скопирован'); } catch (_e) { toast(text); }
  document.body.removeChild(ta);
}

function documentsCopyToken(key) {
  documentsCopyText('{{' + key + '}}');
}

function documentsRenderTokenHintHtml() {
  return '<div class="docs-token-hint">' + documentsTokenDefs.slice(0, 6).map(function (token) {
    return '<button type="button" class="docs-token docs-token-copy" onclick="documentsCopyToken(\'' + esc(token.key) + '\')">' + esc(token.label) + '</button>';
  }).join('') + '</div>';
}

documentsBuildDocumentSettingsHtml = function () {
  var pageFormatScope = documentsState.page_format_scope || 'all';
  var pageFormatValue = documentsSelectedPageFormatValue();
  var activePageNo = documentsActivePageIndex() + 1;
  return '' +
    '<div class="docs-doc-settings">' +
      '<div class="docs-panel-title" style="margin-bottom:10px">Настройки страницы</div>' +
      '<div class="docs-props-note" style="margin-bottom:8px">Формат листа. Текущий лист: ' + esc(activePageNo) + '</div>' +
      '<div class="field" style="margin:0 0 10px"><label>Формат</label><select id="documents-page-format" class="finp" onchange="documentsSetPageFormat(this.value)">' +
        '<option value="a4"' + (pageFormatValue === 'a4' ? ' selected' : '') + '>A4 portrait</option>' +
        '<option value="a4-landscape"' + (pageFormatValue === 'a4-landscape' ? ' selected' : '') + '>A4 landscape</option>' +
      '</select></div>' +
      '<div class="field" style="margin:0 0 14px"><label>Применить</label><select id="documents-page-format-scope" class="finp" onchange="documentsSetPageFormatScope(this.value)">' +
        '<option value="all"' + (pageFormatScope === 'all' ? ' selected' : '') + '>Весь документ</option>' +
        '<option value="page"' + (pageFormatScope === 'page' ? ' selected' : '') + '>Текущий лист</option>' +
      '</select></div>' +
      '<div class="docs-props-note" style="margin-bottom:8px">Поля документа, px</div>' +
      '<div class="frow" style="margin-bottom:10px">' +
        '<div class="field" style="margin:0"><label>Сверху</label><input class="finp" type="number" min="0" max="180" value="' + esc(documentsState.page_margin_top) + '" oninput="documentsUpdateStateNumberField(\'page_margin_top\',this.value)"></div>' +
        '<div class="field" style="margin:0"><label>Справа</label><input class="finp" type="number" min="0" max="180" value="' + esc(documentsState.page_margin_right) + '" oninput="documentsUpdateStateNumberField(\'page_margin_right\',this.value)"></div>' +
      '</div>' +
      '<div class="frow" style="margin-bottom:10px">' +
        '<div class="field" style="margin:0"><label>Снизу</label><input class="finp" type="number" min="0" max="180" value="' + esc(documentsState.page_margin_bottom) + '" oninput="documentsUpdateStateNumberField(\'page_margin_bottom\',this.value)"></div>' +
        '<div class="field" style="margin:0"><label>Слева</label><input class="finp" type="number" min="0" max="180" value="' + esc(documentsState.page_margin_left) + '" oninput="documentsUpdateStateNumberField(\'page_margin_left\',this.value)"></div>' +
      '</div>' +
      '<div class="field" style="margin:0 0 10px"><label>Шрифт документа</label><select class="finp" onchange="documentsUpdateStateField(\'font_family\',this.value)">' + documentsFontOptionsHtml(documentsState.font_family) + '</select></div>' +
      '<div class="frow" style="margin-bottom:10px">' +
        '<div class="field" style="margin:0"><label>Размер, px</label><input class="finp" type="number" min="7" max="48" value="' + esc(documentsState.font_size) + '" oninput="documentsUpdateStateNumberField(\'font_size\',this.value)"></div>' +
        '<div class="field" style="margin:0"><label>Межстрочный интервал</label><input class="finp" type="text" inputmode="decimal" value="' + esc(documentsState.line_height) + '" title="Множитель высоты строки: 1 - плотно, 1.35 - стандартно, 2 - двойной интервал" oninput="documentsUpdateStateNumberField(\'line_height\',this.value)"></div>' +
      '</div>' +
      '<div class="field" style="margin:0 0 10px"><label>Верхний колонтитул</label><input class="finp" value="' + esc(documentsState.page_header_text || '') + '" oninput="documentsUpdateStateField(\'page_header_text\',this.value)"></div>' +
      '<div class="field" style="margin:0 0 10px"><label>Выравнивание верха</label><select class="finp" onchange="documentsUpdateStateField(\'page_header_align\',this.value)">' +
        '<option value="left"' + ((documentsState.page_header_align || 'left') === 'left' ? ' selected' : '') + '>Слева</option>' +
        '<option value="center"' + ((documentsState.page_header_align || 'left') === 'center' ? ' selected' : '') + '>По центру</option>' +
        '<option value="right"' + ((documentsState.page_header_align || 'left') === 'right' ? ' selected' : '') + '>Справа</option>' +
      '</select></div>' +
      '<div class="field" style="margin:0 0 10px"><label>Нижний колонтитул</label><input class="finp" value="' + esc(documentsState.page_footer_text || '') + '" oninput="documentsUpdateStateField(\'page_footer_text\',this.value)"></div>' +
      '<div class="field" style="margin:0"><label>Выравнивание низа</label><select class="finp" onchange="documentsUpdateStateField(\'page_footer_align\',this.value)">' +
        '<option value="left"' + ((documentsState.page_footer_align || 'left') === 'left' ? ' selected' : '') + '>Слева</option>' +
        '<option value="center"' + ((documentsState.page_footer_align || 'left') === 'center' ? ' selected' : '') + '>По центру</option>' +
        '<option value="right"' + ((documentsState.page_footer_align || 'left') === 'right' ? ' selected' : '') + '>Справа</option>' +
      '</select></div>' +
      '<div class="docs-props-note" style="margin-top:10px">Токены можно копировать по клику:</div>' +
      documentsRenderTokenHintHtml() +
    '</div>';
};

function documentsPropsSectionHtml(title, body, open) {
  return '<details class="docs-props-section"' + (open ? ' open' : '') + '>' +
    '<summary><span>' + esc(title) + '</span><b>⌄</b></summary>' +
    '<div class="docs-props-section-body">' + body + '</div>' +
  '</details>';
}

function documentsBuildLayoutFieldsHtml(block) {
  var layoutHtml =
    '<div class="docs-props-note">Блок можно двигать мышкой прямо на листе. Размер меняется за нижний правый угол.</div>' +
    '<div class="frow" style="margin-top:10px">' +
      '<div class="field" style="margin:0"><label>Ширина, px</label><input class="finp" type="number" min="80" value="' + esc(block.w || '') + '" oninput="documentsUpdateBlockNumberField(\'' + block.id + '\',\'w\',this.value)"></div>' +
      '<div class="field" style="margin:0"><label>Высота, px</label><input class="finp" type="number" min="40" value="' + esc(block.h || '') + '" oninput="documentsUpdateBlockNumberField(\'' + block.id + '\',\'h\',this.value)"></div>' +
    '</div>';
  var textHtml =
    '<div class="field" style="margin:0 0 10px"><label>Шрифт блока</label><select class="finp" onchange="documentsUpdateBlockField(\'' + block.id + '\',\'font_family\',this.value)"><option value="">Как в документе</option>' + documentsFontOptionsHtml(block.font_family || '') + '</select></div>' +
    '<div class="field" style="margin:0 0 10px"><label>Размер шрифта, px</label><input class="finp" type="number" min="7" max="72" value="' + esc(block.font_size || '') + '" placeholder="' + esc(documentsState.font_size || 12) + '" oninput="documentsUpdateBlockNumberField(\'' + block.id + '\',\'font_size\',this.value)"></div>' +
    '<div class="docs-props-note" style="margin-bottom:8px">Внутренние отступы, px</div>' +
    '<div class="frow" style="margin-bottom:10px">' +
      '<div class="field" style="margin:0"><label>Сверху</label><input class="finp" type="number" min="0" max="120" value="' + esc(block.padding_top || '') + '" oninput="documentsUpdateBlockNumberField(\'' + block.id + '\',\'padding_top\',this.value)"></div>' +
      '<div class="field" style="margin:0"><label>Справа</label><input class="finp" type="number" min="0" max="120" value="' + esc(block.padding_right || '') + '" oninput="documentsUpdateBlockNumberField(\'' + block.id + '\',\'padding_right\',this.value)"></div>' +
    '</div>' +
    '<div class="frow" style="margin-bottom:10px">' +
      '<div class="field" style="margin:0"><label>Снизу</label><input class="finp" type="number" min="0" max="120" value="' + esc(block.padding_bottom || '') + '" oninput="documentsUpdateBlockNumberField(\'' + block.id + '\',\'padding_bottom\',this.value)"></div>' +
      '<div class="field" style="margin:0"><label>Слева</label><input class="finp" type="number" min="0" max="120" value="' + esc(block.padding_left || '') + '" oninput="documentsUpdateBlockNumberField(\'' + block.id + '\',\'padding_left\',this.value)"></div>' +
    '</div>';
  return documentsPropsSectionHtml('Положение на листе', layoutHtml, true) +
    documentsPropsSectionHtml('Текст внутри блока', textHtml, false);
}

function documentsUpdateBlockNumberField(id, key, value) {
  var n = parseInt(value || 0, 10) || 0;
  documentsUpdateBlockField(id, key, n || '');
}

function documentsFontOptionsHtml(value) {
  var current = String(value || '');
  var fonts = [
    ['Arial, sans-serif', 'Arial'],
    ['Georgia, serif', 'Georgia'],
    ['Times New Roman, serif', 'Times New Roman'],
    ['Verdana, sans-serif', 'Verdana'],
    ['Tahoma, sans-serif', 'Tahoma'],
    ['Inter, Arial, sans-serif', 'Inter / Arial']
  ];
  return fonts.map(function (font) {
    return '<option value="' + esc(font[0]) + '"' + (current === font[0] ? ' selected' : '') + '>' + esc(font[1]) + '</option>';
  }).join('');
}

function documentsDocumentTextStyle() {
  documentsEnsureState();
  return 'font-family:' + esc(documentsState.font_family || 'Arial, sans-serif') + ';font-size:' + documentsInt(documentsState.font_size, 12, 7, 48) + 'px;line-height:' + documentsFloat(documentsState.line_height, 1.35, 1, 2.5) + ';';
}

function documentsBlockContentStyle(block) {
  var font = block.font_family || documentsState.font_family || 'Arial, sans-serif';
  var fontSize = block.font_size ? documentsInt(block.font_size, documentsState.font_size || 12, 7, 72) : documentsInt(documentsState.font_size, 12, 7, 48);
  var pt = documentsInt(block.padding_top, 0, 0, 120);
  var pr = documentsInt(block.padding_right, 0, 0, 120);
  var pb = documentsInt(block.padding_bottom, 0, 0, 120);
  var pl = documentsInt(block.padding_left, 0, 0, 120);
  return 'box-sizing:border-box;width:100%;height:100%;font-family:' + esc(font) + ';font-size:' + fontSize + 'px;line-height:' + documentsFloat(documentsState.line_height, 1.35, 1, 2.5) + ';padding:' + pt + 'px ' + pr + 'px ' + pb + 'px ' + pl + 'px;';
}

function documentsIsPositionedBlock(block) {
  return true;
}

function documentsBlockLayoutStyle(block, pageStart) {
  documentsEnsureCanvasLayout();
  pageStart = parseInt(pageStart || 0, 10) || 0;
  var rawTop = (parseInt(block.y || 0, 10) || 0) - pageStart;
  var top = rawTop < 0 ? 0 : rawTop;
  var content = documentsContentSize(documentsPageFormatForPage(documentsPageIndexForY(pageStart)));
  var style = 'position:absolute;left:' + (parseInt(block.x || 0, 10) || 0) + 'px;top:' + top + 'px;';
  style += 'width:' + (parseInt(block.w || content.width, 10) || content.width) + 'px;';
  if (block.h) style += 'height:' + (parseInt(block.h || 0, 10) || 0) + 'px;';
  style += 'z-index:' + (parseInt(block.z_index || 3, 10) || 3) + ';';
  return style;
}

function documentsRenderBlockPagePreviewHtml(block, pageStart) {
  if (documentsIsPositionsTable(block)) return documentsRenderPositionsTablePagePreview(block, pageStart);
  if (block.type === 'layout') return documentsRenderLayoutPreview(block, pageStart);
  return documentsRenderBlockPreviewHtml(block);
}

function documentsResizeHandlesHtml(id) {
  var dirs = ['n', 'e', 's', 'w', 'ne', 'se', 'sw', 'nw'];
  return dirs.map(function (dir) {
    return '<div class="docs-block-resize-handle docs-rh-' + dir + '" data-doc-resize-id="' + esc(id) + '" data-doc-resize-dir="' + dir + '" title="Изменить размер" onpointerdown="return documentsStartBlockResize(event,\'' + id + '\',\'' + dir + '\')"></div>';
  }).join('');
}

function documentsRenderEditableBlockHtml(block, pageStart) {
  var active = block.id === documentsState.selected_block_id ? ' active' : '';
  var positioned = documentsIsPositionedBlock(block) ? ' positioned' : '';
  var locked = block.locked ? ' locked' : '';
  return '<div class="docs-preview-edit-block' + active + positioned + locked + '" data-doc-block-id="' + esc(block.id) + '" draggable="false" style="' + documentsBlockLayoutStyle(block, pageStart) + '"' +
    ' onclick="event.stopPropagation();documentsSelectBlock(\'' + block.id + '\')"' +
    ' oncontextmenu="documentsOpenBlockContextMenu(event,\'' + block.id + '\')"' +
    ' onpointerdown="documentsPreviewPointerDown(event,\'' + block.id + '\')"' +
    ' onmouseup="documentsMaybeStoreResize(this,\'' + block.id + '\')">' +
      '<div class="docs-preview-edit-toolbar">' +
        '<span>' + (block.locked ? '<b class="docs-block-lock-mark" title="Блок закреплён">🔒</b>' : '') + esc(block.title || documentsBlockTypeLabel(block.type)) + '</span>' +
        '<button type="button" onclick="event.stopPropagation();documentsDuplicateSelected()">⧉</button>' +
        '<button type="button" onpointerdown="event.preventDefault();event.stopPropagation()" onclick="event.preventDefault();event.stopPropagation();documentsDeleteBlockFromButton(this,\'' + block.id + '\');return false">×</button>' +
      '</div>' +
      '<div class="docs-preview-edit-content" style="' + documentsBlockContentStyle(block) + '">' + documentsRenderBlockPagePreviewHtml(block, pageStart) + '</div>' +
      documentsResizeHandlesHtml(block.id) +
    '</div>';
}

function documentsRenderPageSignatureHtml(contentHeight) {
  var block = documentsGetSignatureBlock();
  if (!block) return '';
  var height = documentsSignatureFooterHeight(block);
  var top = Math.max(0, (parseInt(contentHeight || 0, 10) || 0) - height);
  var active = block.id === documentsState.selected_block_id ? ' active' : '';
  var style = 'position:absolute;left:0;right:0;top:' + top + 'px;width:100%;height:' + height + 'px;z-index:' + (parseInt(block.z_index || 20, 10) || 20) + ';';
  return '<div class="docs-preview-edit-block docs-signature-footer' + active + '" data-doc-block-id="' + esc(block.id) + '" style="' + style + '"' +
    ' onclick="event.stopPropagation();documentsSelectBlock(\'' + block.id + '\')">' +
      '<div class="docs-preview-edit-toolbar">' +
        '<span>' + esc(block.title || documentsBlockTypeLabel(block.type)) + '</span>' +
        '<button type="button" onpointerdown="event.preventDefault();event.stopPropagation()" onclick="event.preventDefault();event.stopPropagation();documentsDeleteBlockFromButton(this,\'' + block.id + '\');return false">×</button>' +
      '</div>' +
      '<div class="docs-preview-edit-content" style="' + documentsBlockContentStyle(block) + '">' + documentsRenderBlockPreviewHtml(block) + '</div>' +
    '</div>';
}

function documentsRenderPreviewContentHtml(pageBlocks, pageStart) {
  return pageBlocks.map(function (block) { return documentsRenderEditableBlockHtml(block, pageStart); }).join('');
}

function documentsBindResizeCapture() {
  if (documentsResizeCaptureBound) return;
  documentsResizeCaptureBound = true;
  document.addEventListener('pointerdown', function (event) {
    var target = event.target && event.target.closest ? event.target.closest('.docs-block-resize-handle') : null;
    if (!target || !target.closest('#documents-canvas')) return;
    var id = target.getAttribute('data-doc-resize-id') || '';
    var dir = target.getAttribute('data-doc-resize-dir') || 'se';
    if (!id) return;
    documentsStartBlockResize(event, id, dir);
  }, true);
}

documentsRenderCanvas = function () {
  var wrap = document.getElementById('documents-canvas');
  if (!wrap) return;
  documentsBindResizeCapture();
  wrap.onclick = documentsSelectCanvasEmpty;
  documentsPreviewMode = 'preview';
  if (!(documentsState.blocks || []).length) {
    wrap.innerHTML = '<div class="docs-empty">Пока нет блоков.<br>Перетащите блок из панели слева или нажмите кнопку добавления.</div>';
    return;
  }
  wrap.innerHTML = documentsRenderPreviewPagesHtml();
};

function documentsPreviewDragStart(event, id) {
  documentsDragBlockId = id;
  documentsState.selected_block_id = id;
  documentsPersistLocalDraft();
  documentsRenderProperties();
  if (event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', id);
  }
}

function documentsPreviewDragEnd() {
  documentsDragBlockId = '';
}

function documentsFindContentUnderPointer(clientX, clientY) {
  var contents = Array.prototype.slice.call(document.querySelectorAll('#documents-canvas .docs-preview-page-content'));
  if (!contents.length) return null;
  var nearest = contents[0];
  var nearestDistance = Infinity;
  contents.forEach(function (content) {
    var rect = content.getBoundingClientRect();
    if (clientX >= rect.left && clientX <= rect.right && clientY >= rect.top && clientY <= rect.bottom) {
      nearest = content;
      nearestDistance = 0;
      return;
    }
    var dx = clientX < rect.left ? rect.left - clientX : (clientX > rect.right ? clientX - rect.right : 0);
    var dy = clientY < rect.top ? rect.top - clientY : (clientY > rect.bottom ? clientY - rect.bottom : 0);
    var distance = dx * dx + dy * dy;
    if (distance < nearestDistance) {
      nearest = content;
      nearestDistance = distance;
    }
  });
  return nearest;
}

function documentsApplyCenterSnap(x, y, blockWidth, blockHeight, bounds, pageStart, threshold) {
  bounds = bounds || { width: 0, height: 0 };
  pageStart = parseInt(pageStart || 0, 10) || 0;
  threshold = Math.max(0, parseInt(threshold || 0, 10) || 0);
  blockWidth = Math.max(0, parseInt(blockWidth || 0, 10) || 0);
  blockHeight = Math.max(0, parseInt(blockHeight || 0, 10) || 0);
  var maxX = Math.max(0, (parseInt(bounds.width || 0, 10) || 0) - blockWidth);
  var pageHeight = parseInt(bounds.height || 0, 10) || 0;
  var documentHeight = parseInt(bounds.documentHeight || 0, 10) || pageHeight;
  var maxLocalY = Math.max(0, pageHeight - blockHeight);
  var maxGlobalY = Math.max(0, documentHeight - blockHeight);
  var localY = y - pageStart;
  var centerX = maxX / 2;
  var centerY = maxLocalY / 2;
  var snapX = Math.abs(x - centerX) <= threshold;
  var snapY = Math.abs(localY - centerY) <= threshold;
  return {
    x: Math.round(Math.max(0, Math.min(snapX ? centerX : x, maxX))),
    y: Math.round(Math.max(0, Math.min(snapY ? pageStart + centerY : y, maxGlobalY))),
    snapX: snapX,
    snapY: snapY
  };
}

function documentsBlockRect(block, position, size) {
  position = position || {};
  size = size || {};
  var x = position.x !== undefined ? position.x : (parseInt(block.x || 0, 10) || 0);
  var y = position.y !== undefined ? position.y : (parseInt(block.y || 0, 10) || 0);
  var width = size.w !== undefined ? size.w : (parseInt(block.w || 0, 10) || 0);
  var height = size.h !== undefined ? size.h : (parseInt(block.h || 0, 10) || documentsEstimateBlockHeight(block));
  return { left: x, top: y, right: x + width, bottom: y + height, width: width, height: height };
}

function documentsRectsOverlap(a, b) {
  return a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
}

function documentsSweptRect(block, position) {
  var from = documentsBlockRect(block);
  var to = documentsBlockRect(block, position);
  return {
    left: Math.min(from.left, to.left),
    top: Math.min(from.top, to.top),
    right: Math.max(from.right, to.right),
    bottom: Math.max(from.bottom, to.bottom)
  };
}

function documentsResolveLockedMove(blocks, sourceId, dx, dy, bounds, ignoredIds) {
  blocks = Array.isArray(blocks) ? blocks : [];
  bounds = bounds || {};
  dx = Math.round(parseFloat(dx) || 0);
  dy = Math.round(parseFloat(dy) || 0);
  var ignored = {};
  (ignoredIds || []).forEach(function (id) { ignored[id] = true; });
  var source = blocks.find(function (block) { return block.id === sourceId; });
  if (!source) return { ok: false, positions: {} };
  var positions = {};
  var moved = {};
  var queue = [source];
  moved[source.id] = true;
  positions[source.id] = {
    x: (parseInt(source.x || 0, 10) || 0) + dx,
    y: (parseInt(source.y || 0, 10) || 0) + dy
  };
  while (queue.length) {
    var current = queue.shift();
    var currentPosition = positions[current.id];
    var path = documentsSweptRect(current, currentPosition);
    blocks.forEach(function (candidate) {
      if (!candidate.locked || moved[candidate.id] || ignored[candidate.id]) return;
      if (!documentsRectsOverlap(path, documentsBlockRect(candidate))) return;
      moved[candidate.id] = true;
      positions[candidate.id] = {
        x: (parseInt(candidate.x || 0, 10) || 0) + dx,
        y: (parseInt(candidate.y || 0, 10) || 0) + dy
      };
      queue.push(candidate);
    });
  }
  var width = parseInt(bounds.width || 0, 10) || 0;
  var valid = Object.keys(positions).every(function (id) {
    var block = blocks.find(function (item) { return item.id === id; });
    var rect = documentsBlockRect(block, positions[id]);
    return rect.left >= 0 && (!width || rect.right <= width) && rect.top >= 0;
  });
  return valid ? { ok: true, positions: positions } : { ok: false, positions: {} };
}

function documentsResolveLockedResize(blocks, sourceId, newWidth, newHeight, bounds) {
  blocks = Array.isArray(blocks) ? blocks : [];
  var source = blocks.find(function (block) { return block.id === sourceId; });
  if (!source) return { ok: false, width: newWidth, height: newHeight, positions: {} };
  newWidth = Math.max(40, Math.round(parseFloat(newWidth) || 0));
  newHeight = Math.max(30, Math.round(parseFloat(newHeight) || 0));
  var oldRect = documentsBlockRect(source);
  var newRect = documentsBlockRect(source, null, { w: newWidth, h: newHeight });
  var widthLimit = parseInt((bounds || {}).width || 0, 10) || 0;
  if (newRect.left < 0 || newRect.top < 0 || (widthLimit && newRect.right > widthLimit)) {
    return { ok: false, width: oldRect.width, height: oldRect.height, positions: {} };
  }
  var virtualBlocks = documentsClone(blocks);
  var positions = {};
  var direct = virtualBlocks.filter(function (candidate) {
    return candidate.id !== sourceId && candidate.locked && documentsRectsOverlap(newRect, documentsBlockRect(candidate));
  });
  for (var i = 0; i < direct.length; i += 1) {
    var candidate = direct[i];
    var candidateRect = documentsBlockRect(candidate);
    var overlapsOldY = candidateRect.top < oldRect.bottom && candidateRect.bottom > oldRect.top;
    var overlapsOldX = candidateRect.left < oldRect.right && candidateRect.right > oldRect.left;
    var extendsRight = candidateRect.right > oldRect.right && candidateRect.left < newRect.right;
    var extendsBelow = candidateRect.bottom > oldRect.bottom && candidateRect.top < newRect.bottom;
    var pushX = overlapsOldY && extendsRight ? Math.max(0, newRect.right - candidateRect.left) : 0;
    var pushY = overlapsOldX && extendsBelow ? Math.max(0, newRect.bottom - candidateRect.top) : 0;
    if (!pushX && !pushY) continue;
    var move = documentsResolveLockedMove(virtualBlocks, candidate.id, pushX, pushY, bounds, [sourceId]);
    if (!move.ok) return { ok: false, width: oldRect.width, height: oldRect.height, positions: {} };
    Object.keys(move.positions).forEach(function (id) {
      positions[id] = move.positions[id];
      var virtual = virtualBlocks.find(function (item) { return item.id === id; });
      if (virtual) {
        virtual.x = move.positions[id].x;
        virtual.y = move.positions[id].y;
      }
    });
  }
  return { ok: true, width: newWidth, height: newHeight, positions: positions };
}

function documentsFindContentForBlockY(y) {
  var contents = Array.prototype.slice.call(document.querySelectorAll('#documents-canvas .docs-preview-page-content'));
  if (!contents.length) return null;
  y = parseInt(y || 0, 10) || 0;
  var target = contents[0];
  contents.forEach(function (content) {
    var start = parseInt(content.getAttribute('data-page-start') || 0, 10) || 0;
    if (start <= y) target = content;
  });
  return target;
}

function documentsApplyBlockPositions(positions) {
  Object.keys(positions || {}).forEach(function (id) {
    var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
    if (!block) return;
    var oldX = parseInt(block.x || 0, 10) || 0;
    var oldY = parseInt(block.y || 0, 10) || 0;
    block.x = positions[id].x;
    block.y = positions[id].y;
    if (block.type === 'layout') {
      var dx = block.x - oldX;
      var dy = block.y - oldY;
      if (dx || dy) {
        documentsGetLayoutChildren(block.id).forEach(function (child) {
          child.x = (parseInt(child.x || 0, 10) || 0) + dx;
          child.y = (parseInt(child.y || 0, 10) || 0) + dy;
        });
      }
    }
    var elements = Array.prototype.slice.call(document.querySelectorAll('#documents-canvas [data-doc-block-id="' + id + '"]'));
    if (!elements.length) return;
    var el = documentsPointerDrag && documentsPointerDrag.id === id && documentsPointerDrag.el
      ? documentsPointerDrag.el
      : elements[0];
    var parentLayout = documentsGetParentLayout(block);
    var content = parentLayout
      ? document.querySelector('#documents-canvas [data-doc-block-id="' + parentLayout.id + '"] .docs-layout-stage')
      : (documentsFindContentForBlockY(block.y) || el.closest('.docs-preview-page-content'));
    if (content && el.parentNode !== content) content.appendChild(el);
    elements.forEach(function (duplicate) {
      if (duplicate !== el) duplicate.remove();
    });
    var pageStart = parseInt((content && content.getAttribute('data-page-start')) || 0, 10) || 0;
    if (parentLayout) {
      el.style.left = ((parseInt(block.x || 0, 10) || 0) - (parseInt(parentLayout.x || 0, 10) || 0)) + 'px';
      el.style.top = ((parseInt(block.y || 0, 10) || 0) - (parseInt(parentLayout.y || 0, 10) || 0)) + 'px';
    } else {
      el.style.left = block.x + 'px';
      el.style.top = Math.max(0, block.y - pageStart) + 'px';
    }
    if (documentsPointerDrag && documentsPointerDrag.id === id) documentsPointerDrag.el = el;
  });
}

function documentsRefreshLivePagedDragBlock(block) {
  if (!documentsPointerDrag || !block || !documentsIsPositionsTable(block)) return null;
  documentsRenderCanvas();
  var content = documentsFindContentForBlockY(block.y);
  var selector = '#documents-canvas [data-doc-block-id="' + block.id + '"]';
  var el = content ? content.querySelector('[data-doc-block-id="' + block.id + '"]') : null;
  if (!el) el = document.querySelector(selector);
  if (el) documentsPointerDrag.el = el;
  return content;
}

function documentsClearCenterSnapGuides() {
  document.querySelectorAll('#documents-canvas .docs-preview-page-content.snap-center-x,#documents-canvas .docs-preview-page-content.snap-center-y').forEach(function (content) {
    content.classList.remove('snap-center-x', 'snap-center-y');
  });
}

function documentsShowCenterSnapGuides(content, snapX, snapY) {
  documentsClearCenterSnapGuides();
  if (!content || !content.classList) return;
  if (snapX) content.classList.add('snap-center-x');
  if (snapY) content.classList.add('snap-center-y');
}

function documentsPreviewPointerDown(event, id) {
  if (event.button !== undefined && event.button !== 0) return;
  documentsCloseBlockContextMenu();
  var el = event.currentTarget;
  if (!el || (event.target && event.target.closest && event.target.closest('button'))) return;
  if (event.target && event.target.closest && event.target.closest('.docs-table-column-resizer')) return;
  if (event.target && event.target.closest && event.target.closest('.docs-block-resize-handle')) return;
  var rect = el.getBoundingClientRect();
  if (event.clientX > rect.right - 18 && event.clientY > rect.bottom - 18) return;
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  var scale = documentsGetPreviewScale() || 1;
  var content = el.closest('.docs-preview-page-content');
  var contentRect = content ? content.getBoundingClientRect() : rect;
  var pageStart = parseInt((content && content.getAttribute && content.getAttribute('data-page-start')) || 0, 10) || 0;
  var pointerDocX = Math.round((event.clientX - contentRect.left) / scale);
  var pointerDocY = pageStart + Math.round((event.clientY - contentRect.top) / scale);
  documentsPointerDrag = {
    id: id,
    el: el,
    offsetX: pointerDocX - (parseInt(block.x || 0, 10) || 0),
    offsetY: pointerDocY - (parseInt(block.y || 0, 10) || 0),
    pending: null,
    raf: 0
  };
  documentsDragBlockId = id;
  documentsState.selected_block_id = id;
  documentsPersistLocalDraft();
  documentsRenderProperties();
  if (el.setPointerCapture && event.pointerId != null) el.setPointerCapture(event.pointerId);
  document.addEventListener('pointermove', documentsPreviewPointerMove);
  document.addEventListener('pointerup', documentsPreviewPointerUp);
  event.preventDefault();
  event.stopPropagation();
}

function documentsStartBlockResize(event, id, direction) {
  if (event.button !== undefined && event.button !== 0) return;
  event.preventDefault();
  event.stopPropagation();
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  var source = event.currentTarget && event.currentTarget.closest ? event.currentTarget : event.target;
  var el = source && source.closest ? source.closest('.docs-preview-edit-block') : null;
  if (!block || !el) return;
  var content = el.closest ? el.closest('.docs-preview-page-content') : null;
  var pageStart = parseInt((content && content.getAttribute && content.getAttribute('data-page-start')) || 0, 10) || 0;
  documentsCloseBlockContextMenu();
  documentsResizeDrag = {
    id: id,
    el: el,
    direction: direction || 'se',
    startX: event.clientX,
    startY: event.clientY,
    startBlockX: parseInt(block.x || 0, 10) || 0,
    startBlockY: parseInt(block.y || 0, 10) || 0,
    startW: Math.max(40, parseInt(block.w || el.offsetWidth || 0, 10) || el.offsetWidth || 180),
    startH: Math.max(40, parseInt(block.h || el.offsetHeight || documentsEstimateBlockHeight(block), 10) || el.offsetHeight || 90),
    pageStart: pageStart
  };
  documentsState.selected_block_id = id;
  documentsPersistLocalDraft();
  documentsRenderProperties();
  if (el.setPointerCapture && event.pointerId != null) el.setPointerCapture(event.pointerId);
  document.addEventListener('pointermove', documentsBlockResizeMove);
  document.addEventListener('pointerup', documentsBlockResizeUp);
  return false;
}

function documentsBlockResizeBounds(block) {
  var minW = 80;
  var minH = 54;
  var parentLayout = documentsGetParentLayout(block);
  if (parentLayout) {
    var inner = documentsLayoutInnerRect(parentLayout);
    return {
      minW: minW,
      minH: minH,
      minLeft: inner.left,
      minTop: inner.top,
      maxRight: inner.right,
      maxBottom: inner.bottom
    };
  }
  var pageStart = documentsResizeDrag && documentsResizeDrag.id === block.id
    ? (parseInt(documentsResizeDrag.pageStart || 0, 10) || 0)
    : (parseInt(block.y || 0, 10) || 0);
  var content = documentsContentSize(documentsPageFormatForPage(documentsPageIndexForY(pageStart)));
  return {
    minW: minW,
    minH: minH,
    minLeft: 0,
    minTop: pageStart,
    maxRight: content.width || 0,
    maxBottom: pageStart + (content.height || 0)
  };
}

function documentsApplyResizeBounds(block, rect) {
  var bounds = documentsBlockResizeBounds(block);
  rect.left = parseInt(rect.left || 0, 10) || 0;
  rect.top = parseInt(rect.top || 0, 10) || 0;
  rect.right = Math.max(rect.left + bounds.minW, Math.min(rect.right, bounds.maxRight));
  rect.bottom = Math.max(rect.top + bounds.minH, Math.min(rect.bottom, bounds.maxBottom));
  return rect;
}

function documentsBlockResizeMove(event) {
  if (!documentsResizeDrag) return;
  var block = (documentsState.blocks || []).find(function (item) { return item.id === documentsResizeDrag.id; });
  if (!block) return;
  var scale = documentsGetPreviewScale() || 1;
  var dx = Math.round((event.clientX - documentsResizeDrag.startX) / scale);
  var dy = Math.round((event.clientY - documentsResizeDrag.startY) / scale);
  var dir = documentsResizeDrag.direction || 'se';
  var rect = {
    left: documentsResizeDrag.startBlockX,
    top: documentsResizeDrag.startBlockY,
    right: documentsResizeDrag.startBlockX + documentsResizeDrag.startW,
    bottom: documentsResizeDrag.startBlockY + documentsResizeDrag.startH
  };
  if (dir.indexOf('e') >= 0) rect.right += dx;
  if (dir.indexOf('s') >= 0) rect.bottom += dy;
  if (dir.indexOf('w') >= 0) rect.left += dx;
  if (dir.indexOf('n') >= 0) rect.top += dy;
  rect = documentsApplyResizeBounds(block, rect);
  block.x = rect.left;
  block.y = rect.top;
  block.w = Math.max(1, rect.right - rect.left);
  block.h = Math.max(1, rect.bottom - rect.top);
  var parentLayout = documentsGetParentLayout(block);
  if (parentLayout) {
    documentsResizeDrag.el.style.left = (block.x - (parseInt(parentLayout.x || 0, 10) || 0)) + 'px';
    documentsResizeDrag.el.style.top = (block.y - (parseInt(parentLayout.y || 0, 10) || 0)) + 'px';
  } else {
    documentsResizeDrag.el.style.left = block.x + 'px';
    documentsResizeDrag.el.style.top = Math.max(0, block.y - documentsResizeDrag.pageStart) + 'px';
  }
  documentsResizeDrag.el.style.width = block.w + 'px';
  documentsResizeDrag.el.style.height = block.h + 'px';
  event.preventDefault();
}

function documentsBlockResizeUp(event) {
  if (!documentsResizeDrag) return;
  var el = documentsResizeDrag.el;
  var id = documentsResizeDrag.id;
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  var oldParentLayoutId = block ? String(block.parent_layout_id || '') : '';
  if (block && el) {
    var finalW = Math.round(parseFloat(el.style.width || '') || el.offsetWidth || 0);
    var finalH = Math.round(parseFloat(el.style.height || '') || el.offsetHeight || 0);
    if (finalW > 0) block.w = finalW;
    if (finalH > 0) block.h = finalH;
    el.style.width = block.w + 'px';
    el.style.height = block.h + 'px';
  }
  documentsResizeStoreBlockedUntil = Date.now() + 350;
  documentsResizeDrag = null;
  document.removeEventListener('pointermove', documentsBlockResizeMove);
  document.removeEventListener('pointerup', documentsBlockResizeUp);
  if (el && el.releasePointerCapture && event && event.pointerId != null) {
    try { el.releasePointerCapture(event.pointerId); } catch (err) {}
  }
  if (block && block.parent_layout_id) {
    var parentLayout = documentsGetParentLayout(block);
    if (parentLayout) documentsClampBlockInsideLayout(block, parentLayout);
    else block.parent_layout_id = '';
  }
  documentsPersistLocalDraft();
  var newParentLayoutId = block ? String(block.parent_layout_id || '') : '';
  if (oldParentLayoutId !== newParentLayoutId) {
    documentsRenderCanvas();
  }
  documentsRenderProperties();
}

function documentsPreviewPointerMove(event) {
  if (!documentsPointerDrag) return;
  documentsPointerDrag.pending = { clientX: event.clientX, clientY: event.clientY };
  if (!documentsPointerDrag.raf) {
    documentsPointerDrag.raf = requestAnimationFrame(documentsPreviewPointerApply);
  }
  event.preventDefault();
}

function documentsPreviewPointerApply() {
  if (!documentsPointerDrag || !documentsPointerDrag.pending) return;
  var point = documentsPointerDrag.pending;
  documentsPointerDrag.pending = null;
  documentsPointerDrag.raf = 0;
  documentsEnsureCanvasLayout();
  var block = (documentsState.blocks || []).find(function (item) { return item.id === documentsPointerDrag.id; });
  var content = documentsFindContentUnderPointer(point.clientX, point.clientY);
  if (!block || !content) return;
  var rect = content.getBoundingClientRect();
  var scale = documentsGetPreviewScale() || 1;
  var pageStart = parseInt((content.getAttribute && content.getAttribute('data-page-start')) || 0, 10) || 0;
  var pageIndex = Math.max(0, parseInt((content.getAttribute && content.getAttribute('data-page-index')) || 0, 10) || 0);
  var bounds = documentsContentSize(documentsPageFormatForPage(pageIndex));
  var pageCount = Math.max(1, documentsCanvasPages().length);
  var lastPageEnd = documentsCanvasPages().reduce(function (max, page) { return Math.max(max, page.end || 0); }, bounds.height);
  bounds.documentHeight = Math.max(documentsCanvasContentHeight(), lastPageEnd + bounds.height);
  var width = parseInt(block.w || documentsPointerDrag.el.offsetWidth || bounds.width, 10) || bounds.width;
  var height = parseInt(block.h || documentsPointerDrag.el.offsetHeight || documentsEstimateBlockHeight(block), 10) || documentsEstimateBlockHeight(block);
  var x = Math.round((point.clientX - rect.left) / scale - documentsPointerDrag.offsetX);
  var y = pageStart + Math.round((point.clientY - rect.top) / scale - documentsPointerDrag.offsetY);
  var snapped = documentsApplyCenterSnap(x, y, Math.min(width, bounds.width), Math.min(height, bounds.height), bounds, pageStart, 10);
  var parentLayout = documentsGetParentLayout(block);
  if (parentLayout) {
    var inner = documentsLayoutInnerRect(parentLayout);
    snapped.x = Math.max(inner.left, Math.min(snapped.x, inner.right - Math.min(width, inner.width)));
    snapped.y = Math.max(inner.top, Math.min(snapped.y, inner.bottom - Math.min(height, inner.height)));
    snapped.snapX = false;
    snapped.snapY = false;
  }
  var dx = snapped.x - (parseInt(block.x || 0, 10) || 0);
  var dy = snapped.y - (parseInt(block.y || 0, 10) || 0);
  var movement = block.locked
    ? documentsResolveLockedMove(documentsState.blocks, block.id, dx, dy, bounds)
    : { ok: true, positions: {} };
  if (!block.locked) movement.positions[block.id] = { x: snapped.x, y: snapped.y };
  if (movement.ok) {
    documentsApplyBlockPositions(movement.positions);
    content = documentsRefreshLivePagedDragBlock(block) || content;
  }
  documentsShowCenterSnapGuides(content, snapped.snapX, snapped.snapY);
}

function documentsPreviewPointerUp(event) {
  if (!documentsPointerDrag) return;
  var el = documentsPointerDrag.el;
  if (documentsPointerDrag.raf) cancelAnimationFrame(documentsPointerDrag.raf);
  documentsClearCenterSnapGuides();
  documentsPointerDrag = null;
  documentsDragBlockId = '';
  document.removeEventListener('pointermove', documentsPreviewPointerMove);
  document.removeEventListener('pointerup', documentsPreviewPointerUp);
  if (el && el.releasePointerCapture && event && event.pointerId != null) {
    try { el.releasePointerCapture(event.pointerId); } catch (err) {}
  }
  if (el && el.getAttribute) documentsSyncBlockLayoutMembership(el.getAttribute('data-doc-block-id') || '');
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsPreviewPageDragOver(event) {
  event.preventDefault();
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
}

function documentsPreviewPageDrop(event, pageEl) {
  event.preventDefault();
  if (documentsPointerDrag) return;
  var id = documentsDragBlockId || (event.dataTransfer ? event.dataTransfer.getData('text/plain') : '');
  if (!id) return;
  documentsEnsureCanvasLayout();
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block) return;
  var content = pageEl.querySelector('.docs-preview-page-content') || pageEl;
  var rect = content.getBoundingClientRect();
  var scale = documentsGetPreviewScale() || 1;
  var pageStart = parseInt((content.getAttribute && content.getAttribute('data-page-start')) || 0, 10) || 0;
  documentsState.selected_page_index = Math.max(0, parseInt((content.getAttribute && content.getAttribute('data-page-index')) || 0, 10) || 0);
  block.x = Math.max(0, Math.round((event.clientX - rect.left) / scale));
  block.y = Math.max(0, pageStart + Math.round((event.clientY - rect.top) / scale));
  if (!block.w) block.w = Math.max(180, Math.round(((event.target.closest && event.target.closest('.docs-preview-edit-block')) || {}).offsetWidth || 260));
  documentsSyncBlockLayoutMembership(id);
  documentsState.selected_block_id = id;
  documentsDragBlockId = '';
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsMaybeStoreResize(el, id) {
  if (Date.now() < documentsResizeStoreBlockedUntil) return;
  var block = (documentsState.blocks || []).find(function (item) { return item.id === id; });
  if (!block || !el || !documentsIsPositionedBlock(block)) return;
  var w = Math.round(el.offsetWidth || 0);
  var h = Math.round(el.offsetHeight || 0);
  var oldWidth = parseInt(block.w || 0, 10) || w;
  var oldHeight = parseInt(block.h || 0, 10) || documentsEstimateBlockHeight(block);
  if (Math.abs(w - oldWidth) < 1 && Math.abs(h - oldHeight) < 1) return;
  if (block.locked) {
    var resize = documentsResolveLockedResize(documentsState.blocks, id, w, h, documentsContentSize());
    if (!resize.ok) {
      el.style.width = oldWidth + 'px';
      el.style.height = oldHeight + 'px';
      toast('Размер нельзя изменить: закреплённые блоки упираются в границу', 'err');
      return;
    }
    block.w = resize.width;
    block.h = resize.height;
    documentsApplyBlockPositions(resize.positions);
  } else {
    if (w > 40) block.w = w;
    if (h > 30) block.h = h;
  }
  if (block.type === 'layout') documentsApplyLayoutArrangement(block.id, true);
  else {
    documentsSyncBlockLayoutMembership(id);
  }
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
}

function documentsEnhancePaletteDrag() {
  document.querySelectorAll('#page-documents-builder .docs-palette .btn').forEach(function (btn) {
    var onclick = String(btn.getAttribute('onclick') || '');
    var match = onclick.match(/documentsAddBlock\('([^']+)'\)/);
    if (!match) return;
    btn.setAttribute('draggable', 'true');
    btn.ondragstart = function (event) {
      var type = match[1];
      documentsAddBlock(type);
      documentsDragBlockId = documentsState.selected_block_id || '';
      if (event.dataTransfer) event.dataTransfer.setData('text/plain', documentsDragBlockId);
    };
  });
}

documentsAddBlock = function (type) {
  documentsEnsureState();
  if (type === 'signature') {
    var existingSignature = documentsGetSignatureBlock();
    if (existingSignature) {
      documentsState.selected_block_id = existingSignature.id;
      documentsPersistLocalDraft();
      documentsRenderWorkspace();
      return;
    }
  }
  var block = {
    id: documentsMakeId(),
    type: type,
    title: '',
    locked: false,
    z_index: documentsNextBlockLayer()
  };
  if (type === 'title') { block.text = 'Новый заголовок'; block.align = 'left'; }
  if (type === 'text') { block.text = 'Новый текстовый блок'; }
  if (type === 'field') { block.field_key = 'quote_title'; block.prefix = ''; }
  if (type === 'table') { block.data_source = 'items'; block.note = ''; }
  if (type === 'category_table' || type === 'section_table' || type === 'variants_summary') { block.note = ''; }
  if (type === 'company_info') {
    block.meta_field_keys = documentsDefaultMetaFieldKeys(block);
    var defaultCompany = (documentsCompaniesCache || []).find(function (row) { return parseInt(row.is_default || 0, 10) === 1; }) || (documentsCompaniesCache || [])[0];
    block.company_id = defaultCompany ? String(defaultCompany.id) : '';
  }
  if (type === 'client_info') {
    block.meta_field_keys = documentsDefaultMetaFieldKeys(block);
    block.client_source = 'quote';
    block.client_id = '';
  }
  if (type === 'payment_qr') {
    var qrCompany = (documentsCompaniesCache || []).find(function (row) { return parseInt(row.is_default || 0, 10) === 1; }) || (documentsCompaniesCache || [])[0];
    block.title = '';
    block.company_id = qrCompany ? String(qrCompany.id) : '';
    block.qr_size = 180;
    block.caption = '';
  }
  if (type === 'layout') {
    block.title = '';
    block.layout_mode = 'row';
    block.layout_align = 'space-between';
    block.equal_child_size = true;
    block.layout_gap = 16;
    block.h = 260;
  }
  if (type === 'image') { block.image_src = ''; block.caption = ''; block.height = 140; block.align = 'left'; }
  if (type === 'signature') { block.left_label = 'Подготовил'; block.right_label = 'Согласовал'; }
  if (type === 'spacer') { block.height = 28; }
  if (block.type === 'table' || block.type === 'category_table' || block.type === 'section_table' || block.type === 'variants_summary') {
    block.column_keys = documentsDefaultColumnKeys(block);
    block.columns = documentsGetExtendedTableColumns(block).join(', ');
  }
  documentsState.blocks.push(block);
  documentsState.selected_block_id = block.id;
  documentsEnsureCanvasLayout();
  documentsPersistLocalDraft();
  documentsRenderWorkspace();
};

documentsExportPageCss = function () {
  var css = 'html,body{margin:0;padding:0;background:#fff;color:#111827;font-family:' + (documentsState.font_family || 'Arial, sans-serif') + ';font-size:' + documentsInt(documentsState.font_size, 12, 7, 48) + 'px;line-height:' + documentsFloat(documentsState.line_height, 1.35, 1, 2.5) + ';-webkit-print-color-adjust:exact;print-color-adjust:exact;}';
  css += '@page docsPortrait{size:A4 portrait;margin:0;}@page docsLandscape{size:A4 landscape;margin:0;}';
  css += 'body{background:#fff;}';
  css += '.page{background:#fff;margin:0 auto;box-sizing:border-box;overflow:hidden;page-break-after:always;break-after:page;}';
  css += '.page-a4{page:docsPortrait;width:210mm;min-height:297mm}.page-a4-landscape{page:docsLandscape;width:297mm;min-height:210mm}';
  css += '.page:last-child{page-break-after:auto;break-after:auto;}';
  css += '.docs-preview-page-content{min-height:0;position:relative;overflow:hidden;}';
  css += '.docs-preview-edit-toolbar,.docs-block-resize-handle{display:none!important}.docs-preview-edit-block{resize:none!important;overflow:visible!important;border:0!important;outline:0!important;box-shadow:none!important;background:transparent!important;padding:0!important;margin:0!important}.docs-preview-edit-block.positioned,.docs-print-block{position:absolute!important}.docs-preview-edit-content{display:block;width:100%;height:100%;box-sizing:border-box}';
  css += '.docs-layout-box{position:relative;width:100%;height:100%;min-height:120px;box-sizing:border-box;border:0;background:transparent;overflow:hidden}.docs-layout-label,.docs-layout-empty{display:none!important}.docs-layout-stage{position:absolute;inset:0;overflow:hidden}.docs-layout-child-block{position:absolute!important;resize:none!important;overflow:hidden!important;background:#fff!important}';
  css += '.docs-preview-table-block{break-inside:auto;page-break-inside:auto;margin-bottom:18px}.docs-preview-table-scroll{overflow:visible!important}';
  css += '.docs-table-column-resizer{display:none!important}';
  css += 'table{width:100%;border-collapse:collapse;table-layout:fixed;page-break-inside:auto;}thead{display:table-header-group;}tr{break-inside:avoid;page-break-inside:avoid;}th,td{border:1px solid #d1d5db;padding:7px 9px;text-align:left;font-size:inherit;vertical-align:top;word-break:break-word;}';
  css += '.docs-meta-table th{width:34%;background:#f8fafc;font-weight:800}.docs-meta-table td{width:66%}';
  css += '.muted,.docs-preview-muted{color:#6b7280}.docs-preview-sign{display:grid;grid-template-columns:1fr 1fr;align-items:end;gap:32px;margin:0;padding-top:10px;border-top:1px solid #d1d5db;text-align:center;}.docs-preview-sign>div{min-width:0}.docs-signature-line{margin-top:10px;white-space:nowrap}.docs-print-signature-footer{box-sizing:border-box;padding:0 12px}.docs-print-signature-footer .docs-preview-edit-content{height:100%;display:flex;align-items:center}.docs-print-signature-footer .docs-preview-sign{width:100%}';
  css += 'th{background:#f8fafc;color:#111827;}img{max-width:100%;display:block;}';
  return css;
};

function documentsContentSize(format) {
  var metrics = documentsPageLayoutMetrics(format);
  return { width: metrics.contentWidth, height: metrics.contentHeight };
}

function documentsPageLayoutMetrics(format) {
  var size = documentsPagePixelSize(format);
  var marginTop = documentsInt(documentsState.page_margin_top, 30, 0, 180);
  var marginRight = documentsInt(documentsState.page_margin_right, 30, 0, 180);
  var marginBottom = documentsInt(documentsState.page_margin_bottom, 30, 0, 180);
  var marginLeft = documentsInt(documentsState.page_margin_left, 30, 0, 180);
  var pageNumberHeight = 52;
  return {
    pageWidth: size.width,
    pageHeight: size.height,
    marginTop: marginTop,
    marginRight: marginRight,
    marginBottom: marginBottom,
    marginLeft: marginLeft,
    pageNumberHeight: pageNumberHeight,
    contentWidth: Math.max(120, size.width - marginLeft - marginRight),
    contentHeight: Math.max(120, size.height - marginTop - marginBottom - pageNumberHeight)
  };
}

function documentsPageRanges(totalHeight) {
  documentsEnsureState();
  totalHeight = Math.max(1, parseInt(totalHeight || 0, 10) || 1);
  var ranges = [];
  var start = 0;
  var guard = 0;
  while ((start < totalHeight || !ranges.length) && guard < 500) {
    var index = ranges.length;
    var format = documentsPageFormatForPage(index);
    var metrics = documentsPageLayoutMetrics(format);
    var height = Math.max(1, metrics.contentHeight);
    ranges.push({
      index: index,
      pageNo: index + 1,
      start: start,
      end: start + height,
      format: format,
      metrics: metrics
    });
    start += height;
    guard += 1;
  }
  return ranges;
}

function documentsPageRangeForY(y) {
  y = Math.max(0, parseInt(y || 0, 10) || 0);
  var totalHeight = y + 1;
  (documentsState.blocks || []).forEach(function (block) {
    if (block.type === 'signature' || block.parent_layout_id) return;
    totalHeight = Math.max(totalHeight, (parseInt(block.y || 0, 10) || 0) + documentsEstimateBlockHeight(block) + 18);
  });
  var ranges = documentsPageRanges(totalHeight);
  return ranges.find(function (range) { return y >= range.start && y < range.end; }) || ranges[ranges.length - 1];
}

function documentsPageIndexForY(y) {
  var range = documentsPageRangeForY(y);
  return range ? range.index : 0;
}

function documentsContentSizeForY(y) {
  var range = documentsPageRangeForY(y);
  var metrics = range ? range.metrics : documentsPageLayoutMetrics();
  return { width: metrics.contentWidth, height: metrics.contentHeight };
}

function documentsPagePaddingStyle(metrics) {
  return 'padding:' + metrics.marginTop + 'px ' + metrics.marginRight + 'px ' + metrics.marginBottom + 'px ' + metrics.marginLeft + 'px;';
}

function documentsEstimateBlockHeight(block) {
  if (!block) return 80;
  var isTableBlock = block.type === 'table' || block.type === 'category_table' || block.type === 'section_table' || block.type === 'variants_summary';
  if (block.h && !isTableBlock) return Math.max(parseInt(block.h || 0, 10) || 0, 40);
  var paddingY = documentsInt(block.padding_top, 0, 0, 120) + documentsInt(block.padding_bottom, 0, 0, 120);
  var fontSize = block.font_size ? documentsInt(block.font_size, documentsState.font_size || 12, 7, 72) : documentsInt(documentsState.font_size, 12, 7, 48);
  var fontDelta = Math.max(0, fontSize - 12) * 2;
  if (block.type === 'title') return 92 + paddingY + fontDelta;
  if (block.type === 'field') return 58 + paddingY + fontDelta;
  if (block.type === 'signature') return 118 + paddingY + fontDelta;
  if (block.type === 'spacer') return Math.max(parseInt(block.height || 28, 10) || 28, 20) + paddingY;
  if (block.type === 'image') return Math.max((parseInt(block.height || 140, 10) || 140) + 48 + paddingY, 80);
  if (block.type === 'company_info' || block.type === 'client_info') {
    var metaRows = documentsBuildMetaRows(block);
    var metaRowHeight = Math.ceil(fontSize * documentsFloat(documentsState.line_height, 1.35, 1, 2.5) + 18);
    return Math.max(96, 42 + Math.max(1, metaRows.length) * metaRowHeight + paddingY);
  }
  if (block.type === 'payment_qr') {
    return Math.max(130, 54 + documentsInt(block.qr_size, 180, 80, 420) + (block.caption ? 26 : 20) + paddingY);
  }
  if (block.type === 'layout') {
    return Math.max(120, parseInt(block.h || 260, 10) || 260);
  }
  if (isTableBlock) {
    var rows = documentsGetExtendedTableRows(block);
    var totalLines = documentsBuildPositionsTotalLines(block);
    var tableWidth = parseInt(block.w || documentsContentSize().width, 10) || documentsContentSize().width;
    var headerHeight = 34;
    var titleHeight = block.title ? 28 : 0;
    var baseRowHeight = documentsEstimatedTableRowHeight(block);
    if (documentsIsPositionsTable(block)) {
      return documentsEstimatePositionsTablePagedHeight(block, rows, tableWidth, titleHeight, headerHeight, paddingY, totalLines, baseRowHeight);
    }
    var rowHeights = rows.reduce(function (sum, row) {
      return sum + documentsEstimateTableRowHeight(block, row, tableWidth) + 8;
    }, 0);
    var content = documentsContentSize();
    var pageHeight = Math.max(1, parseInt(content.height || 0, 10) || 1);
    var rowArea = Math.max(1, pageHeight - titleHeight - headerHeight - documentsReservedFooterHeight());
    var estimatedPages = documentsIsPositionsTable(block) ? Math.max(1, Math.ceil(rowHeights / rowArea)) : 1;
    var repeatedPageChrome = documentsIsPositionsTable(block) ? Math.max(0, estimatedPages - 1) * (titleHeight + headerHeight + 24) : 0;
    var actualHeight = titleHeight + headerHeight + rowHeights + repeatedPageChrome + totalLines.length * Math.max(22, baseRowHeight) + (block.note ? 34 : 0) + paddingY + 18;
    return Math.max(parseInt(block.h || 0, 10) || 0, 110, actualHeight);
  }
  var text = String(block.text || '');
  return Math.max(76, Math.min(520, 54 + Math.ceil(text.length / 90) * Math.max(24, fontSize * 1.8) + paddingY));
}

function documentsBlocksOverlap(a, b) {
  var ax = parseInt(a.x || 0, 10) || 0;
  var ay = parseInt(a.y || 0, 10) || 0;
  var aw = parseInt(a.w || 0, 10) || 0;
  var ah = documentsEstimateBlockHeight(a);
  var bx = parseInt(b.x || 0, 10) || 0;
  var by = parseInt(b.y || 0, 10) || 0;
  var bw = parseInt(b.w || 0, 10) || 0;
  var bh = documentsEstimateBlockHeight(b);
  return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
}

function documentsBlocksOverlapX(a, b) {
  var ax = parseInt(a.x || 0, 10) || 0;
  var aw = parseInt(a.w || 0, 10) || 0;
  var bx = parseInt(b.x || 0, 10) || 0;
  var bw = parseInt(b.w || 0, 10) || 0;
  return ax < bx + bw && ax + aw > bx;
}

function documentsEnsureCanvasLayout() {
  documentsEnsureState();
  var bounds = documentsContentSize();
  var cursorY = 0;
  (documentsState.blocks || []).forEach(function (block, index) {
    if (block.parent_layout_id && !documentsGetParentLayout(block)) block.parent_layout_id = '';
    if (block.type === 'signature') {
      block.x = 0;
      block.y = 0;
      block.w = bounds.width;
      block.locked = true;
      if (!isFinite(parseInt(block.z_index, 10))) block.z_index = index + 3;
      return;
    }
    if (block.x === undefined || block.y === undefined) {
      block.x = 0;
      block.y = cursorY;
      block.w = block.w || bounds.width;
    }
    block.y = Math.max(0, parseInt(block.y || 0, 10) || 0);
    var pageBounds = documentsContentSizeForY(block.y);
    if (!block.w) block.w = pageBounds.width;
    block.x = Math.max(0, Math.min(parseInt(block.x || 0, 10) || 0, Math.max(0, pageBounds.width - 80)));
    block.w = Math.max(100, Math.min(parseInt(block.w || pageBounds.width, 10) || pageBounds.width, pageBounds.width - block.x));
    if (block.h) block.h = Math.max(40, parseInt(block.h || 0, 10) || 0);
    block.locked = block.locked === true;
    if (!isFinite(parseInt(block.z_index, 10))) block.z_index = index + 3;
    if (!block.parent_layout_id) cursorY = Math.max(cursorY, block.y + documentsEstimateBlockHeight(block) + 14);
  });
}

function documentsPushBlocksBelow(anchorId) {
  var blocks = documentsState.blocks || [];
  var anchor = blocks.find(function (block) { return block.id === anchorId; });
  if (!anchor) return;
  var stack = [anchor];
  blocks.slice().filter(function (block) {
    return block.id !== anchorId;
  }).sort(function (a, b) {
    return (parseInt(a.y || 0, 10) || 0) - (parseInt(b.y || 0, 10) || 0);
  }).forEach(function (block) {
    var targetY = parseInt(block.y || 0, 10) || 0;
    stack.forEach(function (other) {
      if (!documentsBlocksOverlapX(block, other)) return;
      if (!documentsBlocksOverlap(block, other)) return;
      targetY = Math.max(targetY, (parseInt(other.y || 0, 10) || 0) + documentsEstimateBlockHeight(other) + 14);
    });
    if (targetY !== (parseInt(block.y || 0, 10) || 0)) {
      block.y = targetY;
      stack.push(block);
    }
  });
}

function documentsCanvasContentHeight() {
  documentsEnsureCanvasLayout();
  var bottom = documentsPageLayoutMetrics(documentsPageFormatForPage(0)).contentHeight;
  (documentsState.blocks || []).forEach(function (block) {
    if (block.type === 'signature' || block.parent_layout_id) return;
    bottom = Math.max(bottom, (parseInt(block.y || 0, 10) || 0) + documentsEstimateBlockHeight(block) + 18);
  });
  return bottom;
}

function documentsCanvasPages() {
  documentsEnsureCanvasLayout();
  var totalHeight = documentsCanvasContentHeight();
  return documentsPageRanges(totalHeight).map(function (range) {
    return {
      index: range.index,
      pageNo: range.pageNo,
      start: range.start,
      end: range.end,
      format: range.format,
      metrics: range.metrics,
      blocks: (documentsState.blocks || []).filter(function (block) {
        if (block.type === 'signature' || block.parent_layout_id) return false;
        var y = parseInt(block.y || 0, 10) || 0;
        var h = documentsEstimateBlockHeight(block);
        return y < range.end && y + h > range.start;
      })
    };
  });
}

documentsRenderPreviewPagesHtml = function () {
  documentsEnsureCanvasLayout();
  var pages = documentsCanvasPages();
  var scale = documentsGetPreviewScale();
  return '<div class="docs-preview-stack">' + pages.map(function (page, idx) {
    var pageNo = idx + 1;
    var metrics = page.metrics || documentsPageLayoutMetrics(page.format);
    var pageHeight = metrics.pageHeight;
    var contentHeight = metrics.contentHeight;
    var minFrameHeight = Math.ceil(pageHeight * scale);
    var basePageStyle = documentsPagePaddingStyle(metrics) + documentsDocumentTextStyle() + 'width:' + metrics.pageWidth + 'px;min-height:' + pageHeight + 'px';
    var pageStyle = scale < 0.999 ? ' style="transform:scale(' + scale.toFixed(4) + ');transform-origin:top center;' + basePageStyle + '"' : ' style="' + basePageStyle + '"';
    var marginGuideStyle = 'top:' + metrics.marginTop + 'px;right:' + metrics.marginRight + 'px;bottom:' + (metrics.marginBottom + metrics.pageNumberHeight) + 'px;left:' + metrics.marginLeft + 'px;';
    return '<div class="docs-preview-page-frame" style="min-height:' + minFrameHeight + 'px"><div class="' + esc(documentsPreviewPageClass(page.format)) + ' docs-editable-page"' + pageStyle +
      ' ondragover="documentsPreviewPageDragOver(event)" ondrop="documentsPreviewPageDrop(event,this)">' +
      documentsRenderPageHeaderInnerHtml(pageNo, pages.length) +
      '<div class="docs-preview-page-content" data-page-index="' + idx + '" data-page-start="' + page.start + '" style="min-height:' + contentHeight + 'px">' + documentsRenderPreviewContentHtml(page.blocks, page.start) + documentsRenderPageSignatureHtml(contentHeight) + '</div>' +
      '<div class="docs-page-margin-guide" style="' + marginGuideStyle + '" aria-hidden="true"></div>' +
      documentsRenderPageFooterInnerHtml(pageNo, pages.length) +
      '<div class="docs-preview-page-num">Страница ' + pageNo + '</div>' +
      '</div></div>';
  }).join('') + '</div>';
};

function documentsBringBlockForward(id) {
  documentsState.selected_block_id = id;
  documentsPersistLocalDraft();
  documentsRenderCanvas();
  documentsRenderProperties();
}

function documentsRenderPrintBlockHtml(block, pageStart) {
  var style = documentsBlockLayoutStyle(block, pageStart);
  style = style.replace(/z-index:-?\d+;/, '');
  return '<div class="docs-print-block" style="' + style + '"><div class="docs-preview-edit-content" style="' + documentsBlockContentStyle(block) + '">' + documentsRenderBlockPagePreviewHtml(block, pageStart) + '</div></div>';
}

function documentsRenderPrintSignatureHtml(contentHeight) {
  var block = documentsGetSignatureBlock();
  if (!block) return '';
  var height = documentsSignatureFooterHeight(block);
  var top = Math.max(0, (parseInt(contentHeight || 0, 10) || 0) - height);
  return '<div class="docs-print-signature-footer" style="position:absolute;left:0;right:0;top:' + top + 'px;width:100%;height:' + height + 'px"><div class="docs-preview-edit-content" style="' + documentsBlockContentStyle(block) + '">' + documentsRenderBlockPreviewHtml(block) + '</div></div>';
}

function documentsPrintableTopBlocks() {
  return (documentsState.blocks || []).filter(function (block) {
    return block.type !== 'signature' && !block.parent_layout_id;
  }).slice().sort(function (a, b) {
    var ay = parseInt(a.y || 0, 10) || 0;
    var by = parseInt(b.y || 0, 10) || 0;
    if (Math.abs(ay - by) > 10) return ay - by;
    return (parseInt(a.x || 0, 10) || 0) - (parseInt(b.x || 0, 10) || 0);
  });
}

function documentsBuildFlowBlocks() {
  documentsEnsureCanvasLayout();
  var blocks = documentsPrintableTopBlocks();
  var flow = [];
  var cursorY = 0;
  var gap = 14;

  for (var i = 0; i < blocks.length; i += 1) {
    var rowSource = [blocks[i]];
    var rowY = parseInt(blocks[i].y || 0, 10) || 0;
    while (i + 1 < blocks.length && Math.abs((parseInt(blocks[i + 1].y || 0, 10) || 0) - rowY) <= 10) {
      i += 1;
      rowSource.push(blocks[i]);
    }

    var page = documentsPageRangeForY(cursorY);
    var pageHeight = page && page.metrics ? page.metrics.contentHeight : documentsContentSizeForY(cursorY).height;
    var pageStart = page ? page.start : Math.floor(cursorY / Math.max(1, pageHeight)) * pageHeight;
    var rowProbe = rowSource.map(function (block) {
      var clone = documentsClone(block);
      clone.y = cursorY;
      return clone;
    });
    var rowHeight = rowProbe.reduce(function (max, block) {
      return Math.max(max, documentsEstimateBlockHeight(block));
    }, 0);
    var usedOnPage = cursorY - pageStart;
    var hasPagedTable = rowProbe.some(function (block) {
      return documentsIsPositionsTable(block);
    });
    if (!hasPagedTable && usedOnPage > 0 && usedOnPage + rowHeight > pageHeight) {
      cursorY = pageStart + pageHeight;
    }

    rowProbe = rowSource.map(function (block) {
      var clone = documentsClone(block);
      clone.y = cursorY;
      return clone;
    });
    rowHeight = rowProbe.reduce(function (max, block) {
      return Math.max(max, documentsEstimateBlockHeight(block));
    }, 0);
    flow = flow.concat(rowProbe);
    cursorY += rowHeight + gap;
  }
  return flow;
}

function documentsFlowCanvasPages(flowBlocks) {
  flowBlocks = flowBlocks || documentsBuildFlowBlocks();
  var firstPageHeight = documentsPageLayoutMetrics(documentsPageFormatForPage(0)).contentHeight;
  var totalHeight = firstPageHeight;
  flowBlocks.forEach(function (block) {
    totalHeight = Math.max(totalHeight, (parseInt(block.y || 0, 10) || 0) + documentsEstimateBlockHeight(block) + 18);
  });
  return documentsPageRanges(totalHeight).map(function (range) {
    return {
      index: range.index,
      pageNo: range.pageNo,
      start: range.start,
      end: range.end,
      format: range.format,
      metrics: range.metrics,
      blocks: flowBlocks.filter(function (block) {
        var y = parseInt(block.y || 0, 10) || 0;
        var h = documentsEstimateBlockHeight(block);
        return y < range.end && y + h > range.start;
      })
    };
  });
}

documentsBuildExportHtml = function (options) {
  options = options || {};
  documentsEnsureCanvasLayout();
  var title = esc(documentsState.title || 'Документ');
  var pages = options.flow ? documentsFlowCanvasPages() : documentsCanvasPages();
  return '<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><title>' + title + '</title><style>' +
    documentsExportPageCss() +
    '</style></head><body>' +
      pages.map(function (page, idx) {
        var pageNo = idx + 1;
        var metrics = page.metrics || documentsPageLayoutMetrics(page.format);
        var pageClass = page.format === 'a4-landscape' ? 'page-a4-landscape' : 'page-a4';
        return '<div class="page ' + pageClass + '" style="' + documentsPagePaddingStyle(metrics) + 'min-height:' + metrics.pageHeight + 'px">' +
          documentsRenderPageHeaderInnerHtml(pageNo, pages.length) +
          '<div class="docs-preview-page-content" style="position:relative;min-height:' + metrics.contentHeight + 'px">' + page.blocks.map(function (block) { return documentsRenderPrintBlockHtml(block, page.start); }).join('') + documentsRenderPrintSignatureHtml(metrics.contentHeight) + '</div>' +
          documentsRenderPageFooterInnerHtml(pageNo, pages.length) +
          '<div style="display:flex;justify-content:flex-end;margin-top:22px;font-size:12px;color:#6b7280">Страница ' + pageNo + '</div>' +
        '</div>';
      }).join('') +
    '</body></html>';
};

function documentsPrint(options) {
  options = options || {};
  var printWindow = window.open('', '_blank');
  if (!printWindow) {
    toast('Не удалось открыть окно печати. Разрешите всплывающие окна.', 'err');
    return;
  }
  printWindow.opener = null;
  printWindow.document.open();
  printWindow.document.write(documentsBuildExportHtml(options));
  printWindow.document.close();
  window.setTimeout(function () {
    printWindow.focus();
    printWindow.print();
  }, 250);
}
