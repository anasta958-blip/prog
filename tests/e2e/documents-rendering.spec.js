const { test, expect } = require('@playwright/test');
const { login } = require('./helpers');

test('document page header and footer renderers are available', async ({ page }) => {
  await login(page, 'admin_new', 'password');

  const result = await page.evaluate(() => {
    window.documentsState = window.documentsDefaultState();
    window.documentsState.page_header_text = 'Лист {{page_number}} из {{page_count}}';
    window.documentsState.page_footer_text = 'Нижний колонтитул';
    return {
      headerType: typeof window.documentsRenderPageHeaderInnerHtml,
      footerType: typeof window.documentsRenderPageFooterInnerHtml,
      header: window.documentsRenderPageHeaderInnerHtml(2, 4),
      footer: window.documentsRenderPageFooterInnerHtml(2, 4),
      preview: window.documentsRenderPreviewPagesHtml(),
    };
  });

  expect(result.headerType).toBe('function');
  expect(result.footerType).toBe('function');
  expect(result.header).toContain('Лист 2 из 4');
  expect(result.footer).toContain('Нижний колонтитул');
  expect(result.preview).toContain('docs-preview-page-content');
});

test('document blocks snap to the page center only within the threshold', async ({ page }) => {
  await login(page, 'admin_new', 'password');

  const result = await page.evaluate(() => {
    window.documentsState = window.documentsDefaultState();
    const preview = window.documentsRenderPreviewPagesHtml();
    return {
      helperType: typeof window.documentsApplyCenterSnap,
      both: window.documentsApplyCenterSnap(203, 297, 200, 100, { width: 600, height: 700 }, 0, 10),
      horizontalOnly: window.documentsApplyCenterSnap(205, 120, 200, 100, { width: 600, height: 700 }, 0, 10),
      outside: window.documentsApplyCenterSnap(188, 280, 200, 100, { width: 600, height: 700 }, 0, 10),
      hasPermanentRuler: preview.includes('docs-page-center-ruler'),
      hasPermanentLabel: preview.includes('docs-page-center-label'),
    };
  });

  expect(result.helperType).toBe('function');
  expect(result.both).toEqual({ x: 200, y: 300, snapX: true, snapY: true });
  expect(result.horizontalOnly).toEqual({ x: 200, y: 120, snapX: true, snapY: false });
  expect(result.outside).toEqual({ x: 188, y: 280, snapX: false, snapY: false });
  expect(result.hasPermanentRuler).toBe(false);
  expect(result.hasPermanentLabel).toBe(false);
});

test('locked document blocks move as a chain and preserve free overlaps', async ({ page }) => {
  await login(page, 'admin_new', 'password');

  const result = await page.evaluate(() => {
    const lockedChain = [
      { id: 'a', x: 0, y: 0, w: 100, h: 80, locked: true },
      { id: 'b', x: 100, y: 0, w: 100, h: 80, locked: true },
      { id: 'c', x: 200, y: 0, w: 100, h: 80, locked: true },
    ];
    const withFreeBlock = [
      { id: 'a', x: 0, y: 0, w: 100, h: 80, locked: true },
      { id: 'free', x: 100, y: 0, w: 100, h: 80, locked: false },
    ];
    const diagonal = [
      { id: 'a', x: 0, y: 0, w: 100, h: 100, locked: true },
      { id: 'b', x: 100, y: 100, w: 100, h: 100, locked: true },
    ];
    return {
      helperType: typeof window.documentsResolveLockedMove,
      chain: window.documentsResolveLockedMove(lockedChain, 'a', 20, 0, { width: 500 }),
      free: window.documentsResolveLockedMove(withFreeBlock, 'a', 20, 0, { width: 500 }),
      diagonal: window.documentsResolveLockedMove(diagonal, 'a', 20, 20, { width: 500 }),
      leftBoundary: window.documentsResolveLockedMove(lockedChain, 'a', -20, 0, { width: 500 }),
      rightBoundary: window.documentsResolveLockedMove(
        [{ id: 'a', x: 390, y: 0, w: 100, h: 80, locked: true }],
        'a',
        20,
        0,
        { width: 500 }
      ),
      topBoundary: window.documentsResolveLockedMove(
        [{ id: 'a', x: 0, y: 5, w: 100, h: 80, locked: true }],
        'a',
        0,
        -10,
        { width: 500 }
      ),
      nextPage: window.documentsResolveLockedMove(
        [{ id: 'a', x: 0, y: 690, w: 100, h: 80, locked: true }],
        'a',
        0,
        40,
        { width: 500 }
      ),
    };
  });

  expect(result.helperType).toBe('function');
  expect(result.chain).toEqual({
    ok: true,
    positions: { a: { x: 20, y: 0 }, b: { x: 120, y: 0 }, c: { x: 220, y: 0 } },
  });
  expect(result.free).toEqual({ ok: true, positions: { a: { x: 20, y: 0 } } });
  expect(result.diagonal).toEqual({
    ok: true,
    positions: { a: { x: 20, y: 20 }, b: { x: 120, y: 120 } },
  });
  expect(result.leftBoundary.ok).toBe(false);
  expect(result.rightBoundary.ok).toBe(false);
  expect(result.topBoundary.ok).toBe(false);
  expect(result.nextPage).toEqual({ ok: true, positions: { a: { x: 0, y: 730 } } });
});

test('locked document block resize pushes locked neighbours and state persists', async ({ page }) => {
  await login(page, 'admin_new', 'password');

  const result = await page.evaluate(() => {
    const blocks = [
      { id: 'a', x: 0, y: 0, w: 100, h: 100, locked: true, z_index: 2 },
      { id: 'right', x: 100, y: 0, w: 100, h: 100, locked: true, z_index: 3 },
      { id: 'below', x: 0, y: 100, w: 100, h: 100, locked: true, z_index: 4 },
      { id: 'free', x: 100, y: 100, w: 100, h: 100, locked: false, z_index: 5 },
    ];
    const normalized = window.documentsNormalizeState({
      title: 'Старый документ',
      blocks: [{ id: 'legacy', type: 'text', title: 'Текст' }],
    });
    window.documentsState = window.documentsNormalizeState({
      title: 'Слои',
      blocks: JSON.parse(JSON.stringify(blocks)),
      selected_block_id: 'a',
    });
    window.documentsToggleBlockLock('a');
    const unlocked = window.documentsState.blocks.find((block) => block.id === 'a').locked;
    window.documentsToggleBlockLock('a');
    window.documentsSetBlockLayer('a', 'front');
    const frontLayer = window.documentsState.blocks.find((block) => block.id === 'a').z_index;
    window.documentsSetBlockLayer('a', 'back');
    const backLayer = window.documentsState.blocks.find((block) => block.id === 'a').z_index;

    return {
      resizeType: typeof window.documentsResolveLockedResize,
      resize: window.documentsResolveLockedResize(blocks, 'a', 120, 130, { width: 500 }),
      legacyLocked: normalized.blocks[0].locked,
      legacyLayer: normalized.blocks[0].z_index,
      unlocked,
      relocked: window.documentsState.blocks.find((block) => block.id === 'a').locked,
      frontLayer,
      backLayer,
      menu: window.documentsBuildBlockContextMenuHtml(window.documentsState.blocks[0]),
    };
  });

  expect(result.resizeType).toBe('function');
  expect(result.resize).toEqual({
    ok: true,
    width: 120,
    height: 130,
    positions: {
      right: { x: 120, y: 0 },
      below: { x: 0, y: 130 },
    },
  });
  expect(result.legacyLocked).toBe(false);
  expect(result.legacyLayer).toBeGreaterThan(0);
  expect(result.unlocked).toBe(false);
  expect(result.relocked).toBe(true);
  expect(result.frontLayer).toBeGreaterThan(5);
  expect(result.backLayer).toBeLessThan(3);
  expect(result.menu).toContain('Открепить блок');
  expect(result.menu).toContain('На передний план');
  expect(result.menu).toContain('На задний план');
});

test('locked document blocks stay visible while crossing pages and resize pushes partial overlaps', async ({ page }) => {
  await login(page, 'admin_new', 'password');

  const result = await page.evaluate(() => {
    document.body.insertAdjacentHTML('beforeend', [
      '<div id="documents-canvas">',
      '<div class="docs-preview-page-content" data-page-start="0">',
      '<div data-doc-block-id="moving"></div>',
      '</div>',
      '<div class="docs-preview-page-content" data-page-start="700"></div>',
      '</div>',
    ].join(''));
    window.documentsState = window.documentsNormalizeState({
      blocks: [{ id: 'moving', type: 'text', x: 10, y: 100, w: 100, h: 80, locked: true }],
    });
    window.documentsApplyBlockPositions({ moving: { x: 15, y: 730 } });
    const moving = document.querySelector('[data-doc-block-id="moving"]');
    const resizeRight = window.documentsResolveLockedResize([
      { id: 'source', x: 0, y: 0, w: 100, h: 100, locked: true },
      { id: 'partial-right', x: 90, y: 0, w: 100, h: 100, locked: true },
    ], 'source', 120, 130, { width: 500 });
    const resizeBelow = window.documentsResolveLockedResize([
      { id: 'source', x: 0, y: 0, w: 100, h: 100, locked: true },
      { id: 'partial-below', x: 0, y: 90, w: 100, h: 100, locked: true },
    ], 'source', 120, 130, { width: 500 });

    return {
      pageStart: moving.closest('.docs-preview-page-content').getAttribute('data-page-start'),
      top: moving.style.top,
      resizeRight,
      resizeBelow,
    };
  });

  expect(result.pageStart).toBe('700');
  expect(result.top).toBe('30px');
  expect(result.resizeRight).toEqual({
    ok: true,
    width: 120,
    height: 130,
    positions: {
      'partial-right': { x: 120, y: 0 },
    },
  });
  expect(result.resizeBelow).toEqual({
    ok: true,
    width: 120,
    height: 130,
    positions: {
      'partial-below': { x: 0, y: 130 },
    },
  });
});

test('item tables support group column and independent custom labels', async ({ page }) => {
  await login(page, 'admin_new', 'password');

  const result = await page.evaluate(() => {
    const first = {
      id: 'table-one',
      type: 'table',
      data_source: 'items',
      column_keys: ['group_name', 'name'],
      column_labels: { group_name: 'Товарная группа', name: 'Позиция' },
    };
    const second = {
      id: 'table-two',
      type: 'table',
      data_source: 'items',
      column_keys: ['group_name', 'name'],
      column_labels: { group_name: 'Раздел каталога' },
    };
    const emptyLabel = {
      id: 'table-three',
      type: 'table',
      data_source: 'items',
      column_keys: ['group_name'],
      column_labels: { group_name: '' },
    };

    return {
      availableKeys: window.documentsTableColumnDefs.map((column) => column.key),
      defaultKeys: window.documentsDefaultColumnKeys({ type: 'table', data_source: 'items' }),
      groupCell: window.documentsTableCellByKey('group_name', { group_name: 'Турков' }, 0),
      firstColumns: window.documentsGetExtendedTableColumns(first),
      secondColumns: window.documentsGetExtendedTableColumns(second),
      emptyColumns: window.documentsGetExtendedTableColumns(emptyLabel),
      panel: window.documentsBuildColumnsPickerHtml(first),
      layout: (() => {
        const host = document.createElement('div');
        host.className = 'field';
        host.innerHTML = window.documentsBuildColumnsPickerHtml(first);
        document.body.appendChild(host);
        const label = host.querySelector('.docs-column-check');
        const checkbox = label.querySelector('input[type="checkbox"]');
        const text = label.querySelector('span');
        const checkboxRect = checkbox.getBoundingClientRect();
        const textRect = text.getBoundingClientRect();
        const row = host.querySelector('.docs-column-row');
        const top = host.querySelector('.docs-column-row-top');
        const fields = host.querySelector('.docs-column-row-fields');
        const fieldItems = fields.querySelectorAll('.docs-column-field');
        const rowRect = row.getBoundingClientRect();
        const topRect = top.getBoundingClientRect();
        const firstFieldRect = fieldItems[0].getBoundingClientRect();
        const secondFieldRect = fieldItems[1].getBoundingClientRect();
        const result = {
          labelDisplay: getComputedStyle(label).display,
          checkboxWidth: checkboxRect.width,
          checkboxBeforeText: checkboxRect.right <= textRect.left,
          verticalDifference: Math.abs(
            (checkboxRect.top + checkboxRect.height / 2) -
            (textRect.top + textRect.height / 2)
          ),
          topJustify: getComputedStyle(top).justifyContent,
          fieldsPaddingLeft: parseFloat(getComputedStyle(fields).paddingLeft),
          fieldWidthDifference: Math.abs(firstFieldRect.width - secondFieldRect.width),
          topCenterDifference: Math.abs(
            (topRect.left + topRect.width / 2) -
            (rowRect.left + rowRect.width / 2)
          ),
        };
        host.remove();
        return result;
      })(),
    };
  });

  expect(result.availableKeys).toContain('group_name');
  expect(result.defaultKeys).not.toContain('group_name');
  expect(result.groupCell).toBe('Турков');
  expect(result.firstColumns).toEqual(['Товарная группа', 'Позиция']);
  expect(result.secondColumns).toEqual(['Раздел каталога', 'Наименование']);
  expect(result.emptyColumns).toEqual(['Группа']);
  expect(result.panel).toContain('documentsUpdateTableColumnLabel');
  expect(result.panel).toContain('Товарная группа');
  expect(result.panel).toContain('docs-column-row-top');
  expect(result.panel).toContain('docs-column-row-fields');
  expect(result.layout.labelDisplay).toBe('flex');
  expect(result.layout.checkboxWidth).toBeLessThanOrEqual(20);
  expect(result.layout.checkboxBeforeText).toBe(true);
  expect(result.layout.verticalDifference).toBeLessThanOrEqual(1);
  expect(result.layout.topJustify).toBe('center');
  expect(result.layout.fieldsPaddingLeft).toBe(0);
  expect(result.layout.fieldWidthDifference).toBeLessThanOrEqual(1);
  expect(result.layout.topCenterDifference).toBeLessThanOrEqual(1);
});

test('document printing opens the generated layout', async ({ page }) => {
  await login(page, 'admin_new', 'password');

  const result = await page.evaluate(() => {
    window.documentsState = window.documentsDefaultState();
    window.documentsState.title = 'Проверка печати';
    window.documentsState.blocks = [];

    let writtenHtml = '';
    let printCalled = false;
    const originalOpen = window.open;
    const originalSetTimeout = window.setTimeout;

    window.open = () => ({
      document: {
        open() {},
        write(html) { writtenHtml = html; },
        close() {},
      },
      focus() {},
      print() { printCalled = true; },
      opener: window,
    });
    window.setTimeout = (callback) => {
      callback();
      return 1;
    };

    try {
      window.documentsPrint();
    } finally {
      window.open = originalOpen;
      window.setTimeout = originalSetTimeout;
    }

    return {
      printType: typeof window.documentsPrint,
      writtenHtml,
      printCalled,
    };
  });

  expect(result.printType).toBe('function');
  expect(result.writtenHtml).toContain('<title>Проверка печати</title>');
  expect(result.printCalled).toBe(true);
});
