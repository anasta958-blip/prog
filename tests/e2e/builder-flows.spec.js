const { test, expect } = require('@playwright/test');
const { login, openKpWorkspace } = require('./helpers');

async function openFreshKpBuilder(page) {
  await openKpWorkspace(page);
  await page.evaluate(() => { window.openNewKpQuote(); });
  await expect(page.locator('#page-kp-builder')).toBeVisible();
  await page.waitForFunction(() =>
    Array.isArray(window.kpCatalogProducts) &&
    window.kpCatalogProducts.some((p) => String(p && p.name || '') === 'E2E FLOW ITEM') &&
    Array.isArray(window.kpCatalogServices) &&
    window.kpCatalogServices.some((s) => String(s && s.name || '') === 'E2E AUTO WORK') &&
    Array.isArray(window.kpCatalogSections) &&
    window.kpCatalogSections.length > 0 &&
    Array.isArray(window.allCats) &&
    window.allCats.length > 0
  );
}

function countWorkItems() {
  const variant = window.kpBuilder && Array.isArray(window.kpBuilder.variants) ? window.kpBuilder.variants[0] : null;
  if (!variant || !Array.isArray(variant.cats)) return 0;
  const workCat = variant.cats.find((cat) => String(cat.catCode || '') === 'work');
  if (!workCat) return 0;
  return (workCat.sections || []).reduce((sum, sec) => sum + ((sec.items || []).length), 0);
}

test.describe('CRM builder flows', () => {
  test('admin completes keyboard flow for a new KP product row', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    await openFreshKpBuilder(page);

    const seed = await page.evaluate(() => {
      const products = Array.isArray(window.kpCatalogProducts) ? window.kpCatalogProducts : [];
      const sections = Array.isArray(window.kpCatalogSections) ? window.kpCatalogSections : [];
      const categories = Array.isArray(window.allCats) ? window.allCats : [];
      const product = products.find((p) =>
        String(p && p.name || '') === 'E2E FLOW ITEM' &&
        String(p && p.group_name || '') === 'E2E GROUP'
      );
      if (!product) return null;

      const sec = sections.find((s) => String(s.id) === String(product.section_id));
      if (!sec || String(sec.category_code || '') === 'work') return null;
      const cat = categories.find((c) => String(c.code || '') === String(sec.category_code || ''));
      if (!cat) return null;

      const variant = window.kpBuilder && Array.isArray(window.kpBuilder.variants) ? window.kpBuilder.variants[0] : null;
      if (!variant) return null;

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
            group_name: '',
            nameTxt: '',
            marking_size: '',
            quantity: 1,
            unit: '',
            supplier: '',
            note: '',
            discount: 0,
            markup: 0,
            purchase_price: 0,
            price: 0,
          }],
        }],
      }];
      if (typeof window.renderKpVariants === 'function') window.renderKpVariants();

      return { hasMultipleMarkings: true };
    });

    expect(seed).not.toBeNull();

    const row0 = {
      group: '[id="grp-kp:0-0-0-0-inp"]',
      name: '[id="ac-kp:0-0-0-0-inp"]',
      marking: '[id="acms-kp:0-0-0-0-inp"]',
      qty: '[id="kp-qty-kp_0-0-0-0"]',
    };
    const row1 = {
      group: '[id="grp-kp:0-0-0-1-inp"]',
    };

    const groupInput = page.locator(row0.group);
    await expect(groupInput).toBeVisible();
    await groupInput.click();
    await groupInput.fill('E2E GROUP');
    await groupInput.press('ArrowDown');
    await groupInput.press('Enter');

    await expect.poll(async () => page.evaluate(() => document.activeElement && document.activeElement.id)).toBe('ac-kp:0-0-0-0-inp');
    const nameInput = page.locator(row0.name);
    await expect(nameInput).toBeFocused();
    await nameInput.fill('E2E FLOW ITEM');
    await nameInput.press('ArrowDown');
    await nameInput.press('Enter');

    await expect.poll(async () => page.evaluate(() => document.activeElement && document.activeElement.id)).toBe('acms-kp:0-0-0-0-inp');
    const markingInput = page.locator(row0.marking);
    await expect(markingInput).toBeFocused();
    await markingInput.press('ArrowDown');
    await markingInput.press('Enter');

    await expect.poll(async () => page.evaluate(() => {
      const id = document.activeElement && document.activeElement.id || '';
      return id.indexOf('kp-qty-') === 0;
    })).toBe(true);
    await page.keyboard.press('Control+A');
    await page.keyboard.type('2');
    await page.keyboard.press('Enter');

    const groupInputs = page.locator('input[id^="grp-kp:0-0-0-"][id$="-inp"]');
    await expect(groupInputs).toHaveCount(2);
    await expect.poll(async () => page.evaluate(() => {
      const id = document.activeElement && document.activeElement.id || '';
      return id.indexOf('grp-kp:0-0-0-') === 0;
    })).toBe(true);
    await expect(groupInputs.last()).toHaveValue('');
  });

  test('admin auto-adds linked work in KP builder state', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    await openFreshKpBuilder(page);

    const seeded = await page.evaluate(() => {
      const products = Array.isArray(window.kpCatalogProducts) ? window.kpCatalogProducts : [];
      const sections = Array.isArray(window.kpCatalogSections) ? window.kpCatalogSections : [];
      const categories = Array.isArray(window.allCats) ? window.allCats : [];
      const product = products.find((p) => String(p && p.name || '') === 'E2E AUTO ITEM');
      if (!product) return null;

      const sec = sections.find((s) => String(s.id) === String(product.section_id));
      if (!sec) return null;
      const cat = categories.find((c) => String(c.code || '') === String(sec.category_code || ''));
      if (!cat) return null;

      const variant = window.kpBuilder && Array.isArray(window.kpBuilder.variants) ? window.kpBuilder.variants[0] : null;
      if (!variant) return null;

      const item = {
        uid: 'e2e-auto-work-source',
        product_name_id: product.id,
        nameId: product.id,
        linked_service_id: product.linked_service_id,
        group_name: product.group_name || '',
        nameTxt: product.name || '',
        marking_size: product.marking_size || '',
        quantity: 1,
        unit: product.unit || '',
        supplier: product.supplier || '',
        note: '',
        discount: 0,
        markup: 0,
        purchase_price: Number(product.purchase_price || 0),
        price: Number(product.price || 0),
        retail_price: Number(product.retail_price || 0),
      };

      variant.cats = [{
        catId: cat.id,
        catName: cat.name,
        catCode: cat.code,
        sections: [{
          secId: sec.id,
          secName: sec.name,
          secCode: sec.code || '',
          groups: [],
          items: [item],
        }],
      }];
      window.kpUpsertAutoWorkFromItem(0, item);
      if (typeof window.renderKpVariants === 'function') window.renderKpVariants();
      const workCat = (variant.cats || []).find((catRow) => String(catRow.catCode || '') === 'work');
      const workItems = workCat ? (workCat.sections || []).reduce((sum, secRow) => sum + ((secRow.items || []).length), 0) : 0;
      return { workItems };
    });

    expect(seeded).not.toBeNull();
    expect(seeded.workItems).toBeGreaterThan(0);
    await expect.poll(async () => page.evaluate(countWorkItems)).toBe(1);
    await expect(page.locator('#page-kp-builder')).toContainText('Работы');
  });

  test('admin removes auto-added work when source product row is deleted', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    await openFreshKpBuilder(page);

    const seeded = await page.evaluate(() => {
      const products = Array.isArray(window.kpCatalogProducts) ? window.kpCatalogProducts : [];
      const sections = Array.isArray(window.kpCatalogSections) ? window.kpCatalogSections : [];
      const categories = Array.isArray(window.allCats) ? window.allCats : [];
      const product = products.find((p) => String(p && p.name || '') === 'E2E AUTO ITEM');
      if (!product) return null;

      const sec = sections.find((s) => String(s.id) === String(product.section_id));
      if (!sec) return null;
      const cat = categories.find((c) => String(c.code || '') === String(sec.category_code || ''));
      if (!cat) return null;

      const variant = window.kpBuilder && Array.isArray(window.kpBuilder.variants) ? window.kpBuilder.variants[0] : null;
      if (!variant) return null;

      const item = {
        uid: 'e2e-auto-work-delete-source',
        product_name_id: product.id,
        nameId: product.id,
        linked_service_id: product.linked_service_id,
        group_name: product.group_name || '',
        nameTxt: product.name || '',
        marking_size: product.marking_size || '',
        quantity: 1,
        unit: product.unit || '',
        supplier: product.supplier || '',
        note: '',
        discount: 0,
        markup: 0,
        purchase_price: Number(product.purchase_price || 0),
        price: Number(product.price || 0),
        retail_price: Number(product.retail_price || 0),
      };

      variant.cats = [{
        catId: cat.id,
        catName: cat.name,
        catCode: cat.code,
        sections: [{
          secId: sec.id,
          secName: sec.name,
          secCode: sec.code || '',
          groups: [],
          items: [item],
        }],
      }];
      window.kpUpsertAutoWorkFromItem(0, item);
      if (typeof window.renderKpVariants === 'function') window.renderKpVariants();
      const workCat = (variant.cats || []).find((catRow) => String(catRow.catCode || '') === 'work');
      const workItems = workCat ? (workCat.sections || []).reduce((sum, secRow) => sum + ((secRow.items || []).length), 0) : 0;
      return { workItems };
    });

    expect(seeded).not.toBeNull();
    expect(seeded.workItems).toBeGreaterThan(0);

    await page.evaluate(() => {
      window.removeItem('kp:0', 0, 0, 0);
    });

    await expect.poll(async () => page.evaluate(countWorkItems)).toBe(0);
  });

  test('admin sees all linked works immediately after selecting a product', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    await openFreshKpBuilder(page);

    const result = await page.evaluate(async () => {
      const products = Array.isArray(window.kpCatalogProducts) ? window.kpCatalogProducts : [];
      const services = Array.isArray(window.kpCatalogServices) ? window.kpCatalogServices : [];
      const sections = Array.isArray(window.kpCatalogSections) ? window.kpCatalogSections : [];
      const categories = Array.isArray(window.allCats) ? window.allCats : [];
      const product = products.find((row) => {
        const section = sections.find((item) => String(item.id) === String(row.section_id));
        return section && String(section.category_code || '') !== 'work';
      });
      if (!product || services.length < 2) return null;

      const section = sections.find((row) => String(row.id) === String(product.section_id));
      const category = categories.find((row) => String(row.code || '') === String(section.category_code || ''));
      const variant = window.kpBuilder.variants[0];
      if (!section || !category || !variant) return null;

      const linkedServices = services.slice(0, 2).map((service) => ({
        id: service.id,
        name: service.name,
        marking_size: service.marking_size || '',
        retail_price: service.retail_price != null ? service.retail_price : service.cost,
        purchase_price: service.purchase_price,
        unit: service.unit || '',
        work_section_code: service.work_section_code || 'installation',
      }));
      const sourceItem = {
        uid: 'e2e-multi-work-source',
        item_type: 'product',
        product_name_id: product.id,
        nameId: product.id,
        group_name: product.group_name || '',
        nameTxt: product.name || '',
        name: product.name || '',
        marking_size: product.marking_size || '',
        quantity: 1,
        unit: product.unit || '',
        supplier: product.supplier || '',
        linked_services: linkedServices,
      };
      variant.cats = [{
        catId: category.id,
        catName: category.name,
        catCode: category.code,
        sections: [{
          secId: section.id,
          secName: section.name,
          secCode: section.code || '',
          groups: [],
          items: [sourceItem],
        }],
      }];
      window.renderKpVariants();
      window.kpUpsertAutoWorkFromItem(0, sourceItem);
      window.kpSyncVariantFromCats(0);
      window.kpSyncAutoWorkDomForSource('kp:0', sourceItem.uid, 0, 0, 0);

      const firstStateCount = variant.cats
        .filter((cat) => cat.catCode === 'work' || cat.catCode === 'construction_works')
        .reduce((total, cat) => total + (cat.sections || []).reduce(
          (sectionTotal, row) => sectionTotal + (row.items || []).filter((item) => item.is_auto).length,
          0
        ), 0);
      const firstDomRows = Array.from(document.querySelectorAll('#kp-variants-wrap tbody tr'));
      const firstDomCount = firstDomRows.filter((row) =>
        linkedServices.some((service) => Array.from(row.querySelectorAll('input')).some(
          (input) => input.value === service.name
        ))
      ).length;
      const firstWorkRows = linkedServices.map((service) =>
        firstDomRows.find((row) => Array.from(row.querySelectorAll('input')).some(
          (input) => input.value === service.name
        )) || null
      );

      const secondSourceItem = {
        ...sourceItem,
        uid: 'e2e-multi-work-source-2',
      };
      variant.cats[0].sections[0].items.push(secondSourceItem);
      const changed = window.kpUpsertAutoWorkFromItem(0, secondSourceItem);
      window.kpSyncVariantFromCats(0);
      if (changed) {
        window.kpSyncAutoWorkDomForSource('kp:0', secondSourceItem.uid, 0, 0, 1);
      }

      const stateQuantities = variant.cats
        .filter((cat) => cat.catCode === 'work' || cat.catCode === 'construction_works')
        .flatMap((cat) => (cat.sections || []).flatMap((row) =>
          (row.items || []).filter((item) => item.is_auto).map((item) => Number(item.quantity))
        ));
      const domQuantities = Array.from(document.querySelectorAll('#kp-variants-wrap tbody tr'))
        .filter((row) => linkedServices.some((service) => Array.from(row.querySelectorAll('input')).some(
          (input) => input.value === service.name
        )))
        .map((row) => Number((row.querySelector('input[id^="kp-qty-"]') || {}).value || 0));
      const currentDomRows = Array.from(document.querySelectorAll('#kp-variants-wrap tbody tr'));
      const rowsPreserved = linkedServices.every((service, index) => {
        const currentRow = currentDomRows.find((row) => Array.from(row.querySelectorAll('input')).some(
          (input) => input.value === service.name
        )) || null;
        return !!firstWorkRows[index] && firstWorkRows[index] === currentRow;
      });
      return {
        firstStateCount,
        firstDomCount,
        changed,
        stateQuantities,
        domQuantities,
        rowsPreserved,
      };
    });

    expect(result).not.toBeNull();
    expect(result.firstStateCount).toBe(2);
    expect(result.firstDomCount).toBe(2);
    expect(result.changed).toBe(true);
    expect(result.stateQuantities).toEqual([2, 2]);
    expect(result.domQuantities).toEqual([2, 2]);
    expect(result.rowsPreserved).toBe(true);
  });

  test('admin manages proposal types in KP builder', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    await openFreshKpBuilder(page);

    await expect(page.locator('#kp-builder-add-type-btn')).toBeVisible();
    await page.click('#kp-builder-add-type-btn');
    await expect.poll(async () => page.evaluate(() => (window.kpBuilder.proposal_types || []).length)).toBe(2);

    const typeInput = page.locator('#kp-variants-wrap .kp-proposal-type-editor input.finp').first();
    await typeInput.fill('Кондиционеры');
    await typeInput.blur();
    await expect.poll(async () => page.evaluate(() => {
      const list = window.kpBuilder.proposal_types || [];
      const idx = window.kpBuilder.active_type_index || 0;
      return (list[idx] && list[idx].label) || '';
    })).toBe('Кондиционеры');

    await expect(page.locator('#kp-variants-wrap [data-kp-add-cat-btn]').first()).toBeVisible();
  });
});
