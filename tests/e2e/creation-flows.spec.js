const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { login, apiPost, apiJson, apiGetJson, openKpWorkspace, openPkpWorkspace, openOrdersList, openOrdersNewRequest } = require('./helpers');

function uniqueTag(prefix) {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
}

async function selectFirstQuoteParties(page) {
  await page.waitForFunction(() =>
    Array.isArray(window.kpClients) &&
    window.kpClients.length > 0 &&
    Array.isArray(window.kpCompanies) &&
    window.kpCompanies.length > 0 &&
    typeof window.setKpPartyValue === 'function'
  );
  await page.evaluate(() => {
    window.setKpPartyValue('client', window.kpClients[0].id);
    window.setKpPartyValue('contractor', window.kpCompanies[0].id);
  });
}

test.describe('CRM creation flows', () => {
  test('catalog import templates are Excel-safe and match current export columns', async () => {
    const products = fs.readFileSync(path.join(process.cwd(), 'templates', 'catalog_import_products_template.csv'));
    const services = fs.readFileSync(path.join(process.cwd(), 'templates', 'catalog_import_services_template.csv'));

    expect(products.subarray(0, 3)).toEqual(Buffer.from([0xEF, 0xBB, 0xBF]));
    expect(services.subarray(0, 3)).toEqual(Buffer.from([0xEF, 0xBB, 0xBF]));

    const productHeader = products.toString('utf8').replace(/^\uFEFF/, '').split(/\r?\n/, 1)[0].split(';');
    expect(productHeader).toEqual([
      'ID',
      'sort_order',
      'Тип',
      'Категория',
      'Раздел',
      'Группа',
      'Наименование',
      'Маркировка/Размер',
      'Примечание',
      'Ед. изм.',
      'Закупочная цена',
      'Минимальная цена',
      'Розничная цена',
      'Техничка',
      'Статус',
      'Поставщик',
      'Работа 1',
      'Маркировка работы 1',
      'Работа 2',
      'Маркировка работы 2',
    ]);

    const serviceHeader = services.toString('utf8').replace(/^\uFEFF/, '').split(/\r?\n/, 1)[0].split(';');
    expect(serviceHeader).toEqual([
      'ID',
      'sort_order',
      'Тип',
      'Раздел',
      'Наименование',
      'Маркировка/Размер',
      'Ед. изм.',
      'Закупочная цена',
      'Минимальная цена',
      'Розничная цена',
    ]);
  });

  test('catalog work import accepts exported marking and section headers', async ({ page }) => {
    const serviceName = uniqueTag('E2E-IMPORT-WORK');
    const marking = uniqueTag('E2E-MARK');

    await login(page, 'admin_new', 'password');
    const csv = [
      'Тип;Раздел;Наименование;Маркировка/Размер;Единица;Закупочная цена;Минимальная цена;Розничная цена',
      `Работа;Демонтажные работы;${serviceName};${marking};шт;10;20;30`,
    ].join('\r\n');
    const importResponse = await apiPost(page, '/api/catalog.php?action=import_catalog_excel', {
      multipart: {
        file: {
          name: 'works.csv',
          mimeType: 'text/csv',
          buffer: Buffer.from(`\uFEFF${csv}`, 'utf8'),
        },
      },
    });
    expect(importResponse.ok()).toBeTruthy();

    const servicesResponse = await page.request.get(`/api/catalog.php?action=services&search=${encodeURIComponent(serviceName)}`);
    expect(servicesResponse.ok()).toBeTruthy();
    const services = await apiJson(servicesResponse);
    const imported = services.find((service) => service.name === serviceName);
    expect(imported).toBeTruthy();
    expect(imported.marking_size).toBe(marking);
    expect(imported.work_section_code).toBe('dismantling');

    await apiPost(page, '/api/catalog.php', {
      data: { action: 'delete_service', id: imported.id },
    });
  });

  test('catalog product export places note after marking', async ({ page }) => {
    await login(page, 'admin_new', 'password');

    const exported = await page.evaluate(() => {
      const originalDownload = window.triggerCsvDownload;
      const originalNames = window.catalogNames;
      const originalPage = window.activePage;
      const originalMode = window.generalCatalogMode;
      let captured = null;
      window.triggerCsvDownload = (filename, rows) => { captured = { filename, rows }; };
      window.catalogNames = [{
        id: 1,
        name: 'Тестовый товар',
        marking_size: 'MARK-1',
        note: 'Тестовое примечание',
      }];
      window.activePage = 'catalog';
      window.generalCatalogMode = 'equipment';
      window.exportGeneralCatalog();
      window.triggerCsvDownload = originalDownload;
      window.catalogNames = originalNames;
      window.activePage = originalPage;
      window.generalCatalogMode = originalMode;
      return captured;
    });

    expect(exported.rows[0].slice(6, 9)).toEqual(['Наименование', 'Маркировка/Размер', 'Примечание']);
    expect(exported.rows[1].slice(6, 9)).toEqual(['Тестовый товар', 'MARK-1', 'Тестовое примечание']);
  });

  test('catalog product export appends separate work name and marking columns', async ({ page }) => {
    await login(page, 'admin_new', 'password');

    const exported = await page.evaluate(() => {
      const originalDownload = window.triggerCsvDownload;
      const originalNames = window.catalogNames;
      const originalPage = window.activePage;
      const originalMode = window.generalCatalogMode;
      let captured = null;
      window.triggerCsvDownload = (filename, rows) => { captured = { filename, rows }; };
      window.catalogNames = [{
        id: 1,
        name: 'Товар с двумя работами',
        linked_services: [
          { id: 10, name: 'Монтаж', marking_size: 'MNT-1' },
          { id: 11, name: 'Демонтаж', marking_size: 'DMT-2' },
        ],
      }, {
        id: 2,
        name: 'Товар с одной работой',
        linked_services: [
          { id: 12, name: 'Пусконаладка', marking_size: 'PNR-3' },
        ],
      }];
      window.activePage = 'catalog';
      window.generalCatalogMode = 'equipment';
      window.exportGeneralCatalog();
      window.triggerCsvDownload = originalDownload;
      window.catalogNames = originalNames;
      window.activePage = originalPage;
      window.generalCatalogMode = originalMode;
      return captured;
    });

    expect(exported.rows[0]).not.toContain('Привязанные работы');
    expect(exported.rows[0].slice(-4)).toEqual([
      'Работа 1',
      'Маркировка работы 1',
      'Работа 2',
      'Маркировка работы 2',
    ]);
    expect(exported.rows[1].slice(-4)).toEqual(['Монтаж', 'MNT-1', 'Демонтаж', 'DMT-2']);
    expect(exported.rows[2].slice(-4)).toEqual(['Пусконаладка', 'PNR-3', '', '']);
  });

  test('catalog product import links every work from separate columns', async ({ page }) => {
    const productName = uniqueTag('E2E-IMPORT-PRODUCT');
    const serviceName1 = uniqueTag('E2E-IMPORT-SERVICE-A');
    const serviceName2 = uniqueTag('E2E-IMPORT-SERVICE-B');
    const marking1 = uniqueTag('E2E-WORK-MARK-A');
    const marking2 = uniqueTag('E2E-WORK-MARK-B');

    await login(page, 'admin_new', 'password');
    const categories = await apiGetJson(page, '/api/catalog.php?action=categories');
    const equipment = categories.find((category) => category.code === 'equipment');
    expect(equipment).toBeTruthy();
    const sections = await apiGetJson(page, `/api/catalog.php?action=sections&category_id=${equipment.id}`);
    const section = sections[0];
    expect(section).toBeTruthy();

    const createService = async (name, marking) => {
      const response = await apiPost(page, '/api/catalog.php', {
        data: {
          action: 'create_service',
          name,
          marking_size: marking,
          work_section_code: 'installation',
          unit: 'шт',
          retail_price: 100,
        },
      });
      expect(response.ok()).toBeTruthy();
      return (await apiJson(response)).id;
    };
    const serviceId1 = await createService(serviceName1, marking1);
    const serviceId2 = await createService(serviceName2, marking2);

    const csv = [
      'Тип;Категория;Раздел;Наименование;Маркировка/Размер;Ед. изм.;Закупочная цена;Минимальная цена;Розничная цена;Статус;Работа 1;Маркировка работы 1;Работа 2;Маркировка работы 2',
      `Товар;${equipment.name};${section.name};${productName};PRODUCT-MARK;компл;50;75;100;Согласовано;${serviceName1};${marking1};${serviceName2};${marking2}`,
    ].join('\r\n');
    const importResponse = await apiPost(page, '/api/catalog.php?action=import_catalog_excel', {
      multipart: {
        file: {
          name: 'products.csv',
          mimeType: 'text/csv',
          buffer: Buffer.from(`\uFEFF${csv}`, 'utf8'),
        },
      },
    });
    expect(importResponse.ok()).toBeTruthy();
    expect((await apiJson(importResponse)).errors).toEqual([]);

    const products = await apiGetJson(page, '/api/catalog.php?action=all_names');
    const imported = products.find((product) => product.name === productName);
    expect(imported).toBeTruthy();
    expect(imported.unit).toBe('компл');
    expect(imported.linked_services.map((service) => [service.name, service.marking_size])).toEqual([
      [serviceName1, marking1],
      [serviceName2, marking2],
    ]);

    await apiPost(page, '/api/catalog.php', { data: { action: 'delete_name', id: imported.id } });
    await apiPost(page, '/api/catalog.php', { data: { action: 'delete_service', id: serviceId1 } });
    await apiPost(page, '/api/catalog.php', { data: { action: 'delete_service', id: serviceId2 } });
  });

  test('catalog work export includes its section', async ({ page }) => {
    await login(page, 'admin_new', 'password');

    const exported = await page.evaluate(() => {
      const originalDownload = window.triggerCsvDownload;
      const originalServices = window.workServices;
      const originalPage = window.activePage;
      const originalMode = window.generalCatalogMode;
      let captured = null;
      window.triggerCsvDownload = (filename, rows) => { captured = { filename, rows }; };
      window.workServices = [{
        id: 1,
        name: 'Демонтаж оборудования',
        marking_size: 'DMT-1',
        work_section_code: 'dismantling',
      }];
      window.activePage = 'catalog';
      window.generalCatalogMode = 'work';
      window.exportGeneralCatalog();
      window.triggerCsvDownload = originalDownload;
      window.workServices = originalServices;
      window.activePage = originalPage;
      window.generalCatalogMode = originalMode;
      return captured;
    });

    expect(exported.rows[0]).toContain('Раздел');
    expect(exported.rows[1][exported.rows[0].indexOf('Раздел')]).toBe('Демонтажные работы');
  });

  test('admin creates a catalog product', async ({ page }) => {
    const productName = uniqueTag('E2E-CATALOG');

    await login(page, 'admin_new', 'password');
    await page.click('#space-tab-catalog');
    await page.evaluate(() => { window.setGeneralCatalogMode('equipment'); });
    await page.evaluate(() => { window.openGeneralCatalogCreate(); });
    await expect(page.locator('#m-name-edit')).toHaveClass(/open/);

    await page.fill('#ne-name', productName);
    await page.fill('#ne-marking-size', 'E2E-MARK');
    await page.selectOption('#ne-group', { label: 'E2E GROUP' });
    await page.fill('#ne-purchase-price', '50');
    await page.fill('#ne-minimal-price', '75');
    await page.fill('#ne-retail-price', '100');

    const saveResponse = page.waitForResponse((res) =>
      res.url().includes('/api/catalog.php') &&
      res.request().method() === 'POST' &&
      (res.request().postData() || '').includes('"action":"create_name"')
    );

    await page.locator('#m-name-edit .btn.btn-p.btn-fw').click();
    const res = await saveResponse;
    expect(res.ok()).toBeTruthy();

    await expect(page.locator('#gc-grid')).toContainText(productName);
  });

  test('admin creates a new order from complectation request builder', async ({ page }) => {
    const orderAddress = uniqueTag('E2E-ORDER');

    await login(page, 'admin_new', 'password');
    await openOrdersNewRequest(page);

    await page.fill('#doc-addr', orderAddress);
    await page.selectOption('#doc-type', { index: 1 });
    await page.fill('#doc-num', 'E2E CLIENT');

    await page.evaluate(() => {
      const firstCat = (window.allCats || [])[0];
      const firstSec = (window.allSecs || []).find((s) => String(s.category_id) === String(firstCat && firstCat.id));
      window.docCats = [{
        catId: firstCat.id,
        catName: firstCat.name,
        catCode: firstCat.code,
        sections: [{
          secId: firstSec.id,
          secName: firstSec.name,
          secCode: firstSec.code || '',
          groups: [],
          items: [{
            group_name: '',
            nameTxt: 'E2E ORDER ITEM',
            quantity: 1,
            unit: 'шт',
            supplier: '',
            note: '',
            marking_size: '',
            dozakaz: 0,
          }],
        }],
      }];
      if (typeof renderDocBuilder === 'function') renderDocBuilder();
    });

    const saveResponse = page.waitForResponse((res) =>
      res.url().includes('/api/orders.php') &&
      res.request().method() === 'POST' &&
      (res.request().postData() || '').includes('"action":"save_order"')
    );

    await page.locator('#page-doc .btn.btn-gr[onclick="saveDocument()"]').click();
    const res = await saveResponse;
    expect(res.ok()).toBeTruthy();

    await openOrdersList(page);
    await expect(page.locator('#or-kanban')).toContainText(orderAddress);
  });

  test('admin creates a new KP quote', async ({ page }) => {
    const quoteTitle = uniqueTag('E2E-KP');

    await login(page, 'admin_new', 'password');
    await openKpWorkspace(page);

    await page.evaluate(() => { window.openNewKpQuote(); });
    await expect(page.locator('#page-kp-builder')).toBeVisible();
    await page.waitForFunction(() =>
      Array.isArray(window.kpCatalogProducts) &&
      window.kpCatalogProducts.some((p) => String((p && p.name) || '') === 'E2E FLOW ITEM') &&
      Array.isArray(window.kpCatalogSections) &&
      window.kpCatalogSections.length > 0 &&
      Array.isArray(window.allCats) &&
      window.allCats.length > 0
    );

    await page.fill('#kp-quote-title', quoteTitle);
    await selectFirstQuoteParties(page);
    await page.evaluate(() => {
      const products = Array.isArray(window.kpCatalogProducts) ? window.kpCatalogProducts : [];
      const sections = Array.isArray(window.kpCatalogSections) ? window.kpCatalogSections : [];
      const categories = Array.isArray(window.allCats) ? window.allCats : [];
      const product = products.find((p) =>
        String((p && p.name) || '') === 'E2E FLOW ITEM' &&
        String((p && p.group_name) || '') === 'E2E GROUP'
      );
      if (!product) return;
      const sec = sections.find((s) => String(s.id) === String(product.section_id));
      if (!sec || String(sec.category_code || '') === 'work') return;
      const cat = categories.find((c) => String(c.code || '') === String(sec.category_code || ''));
      const variant = window.kpBuilder && Array.isArray(window.kpBuilder.variants) ? window.kpBuilder.variants[0] : null;
      if (!cat || !variant) return;
      variant.cats = [{
        catId: cat.id,
        catName: cat.name,
        catCode: cat.code,
        sections: [{
          secId: sec.id,
          secName: sec.name,
          secCode: sec.code || '',
          groups: [],
          items: [{
            group_name: product.group_name || '',
            product_name_id: product.id || 0,
            nameId: product.id || 0,
            nameTxt: product.name || '',
            name: product.name || '',
            marking_size: product.marking_size || '',
            quantity: 1,
            unit: product.unit || '',
            supplier: product.supplier || '',
            note: '',
            purchase_price: product.purchase_price || 0,
            minimal_price: product.minimal_price || 0,
            retail_price: product.retail_price || 0,
            base_price: product.retail_price || 0,
            linked_service_id: product.linked_service_id || 0,
            linked_service_name: product.linked_service_name || '',
            linked_service_cost: product.linked_service_cost || 0,
            linked_service_purchase_price: product.linked_service_purchase_price || 0,
            linked_service_unit: product.linked_service_unit || ''
          }]
        }]
      }];
      if (typeof window.renderKpVariants === 'function') window.renderKpVariants();
    });

    await page.fill('#kp-quote-title', quoteTitle);
    await page.evaluate(() => window.saveKpQuote());
    await expect.poll(() => page.evaluate(() => Number(window.kpBuilder.id || 0))).toBeGreaterThan(0);

    await openKpWorkspace(page);
    await expect(page.locator('#kp-quotes-kanban')).toContainText(quoteTitle);
  });

  test('admin creates a new PKP quote', async ({ page }) => {
    const quoteTitle = uniqueTag('E2E-PKP');

    await login(page, 'admin_new', 'password');
    await openPkpWorkspace(page);

    await page.evaluate(() => { window.openNewKpQuote(); });
    await expect(page.locator('#page-kp-builder')).toBeVisible();

    await page.fill('#kp-quote-title', quoteTitle);
    await selectFirstQuoteParties(page);

    const saveResponse = page.waitForResponse((res) =>
      res.url().includes('/api/pkp.php') &&
      res.request().method() === 'POST' &&
      (res.request().postData() || '').includes('"action":"save_quote"')
    );

    await page.click('#kp-builder-save-btn');
    const res = await saveResponse;
    expect(res.ok()).toBeTruthy();

    await openPkpWorkspace(page);
    await expect(page.locator('#kp-quotes-kanban')).toContainText(quoteTitle);
  });
});
