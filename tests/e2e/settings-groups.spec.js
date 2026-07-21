const { test, expect } = require('@playwright/test');
const { login } = require('./helpers');

test('groups settings renders equipment and materials as nested category accordions', async ({ page }) => {
  await login(page, 'admin_new', 'password');
  await page.click('#space-tab-settings');
  await page.click('#nav-settings-groups');
  await expect(page.locator('#page-settings-groups')).toBeVisible();

  await page.evaluate(() => {
    window.allCats = [
      { id: 1, code: 'equipment', name: 'Оборудование' },
      { id: 2, code: 'materials', name: 'Материалы' },
      { id: 3, code: 'work', name: 'Работы' },
    ];
    window.allSecs = [
      { id: 11, category_id: 1, name: 'Вентиляция' },
      { id: 12, category_id: 1, name: 'Кондиционирование' },
      { id: 21, category_id: 2, name: 'Расходные материалы' },
      { id: 31, category_id: 3, name: 'Монтажные работы' },
    ];
    window.allGroups = [
      { id: 101, section_id: 11, name: 'Вентиляторы', sort_order: 1 },
      { id: 102, section_id: 21, name: 'Крепёж', sort_order: 2 },
      { id: 103, section_id: 31, name: 'Скрытая группа работ', sort_order: 3 },
    ];
    window.renderSettingsGroups();
  });

  const categories = page.locator('.settings-groups-category');
  await expect(categories).toHaveCount(2);
  await expect(categories.nth(0)).toContainText('Оборудование');
  await expect(categories.nth(1)).toContainText('Материалы');
  await expect(page.locator('#settings-groups-list')).not.toContainText('Работы');
  await expect(page.locator('#settings-groups-list')).not.toContainText('Скрытая группа работ');
  const shellWidth = await page.locator('#settings-groups-list').evaluate((element) => element.getBoundingClientRect().width);
  expect(shellWidth).toBeLessThanOrEqual(980);

  const equipment = categories.filter({ hasText: 'Оборудование' });
  await equipment.locator('.settings-groups-category-toggle').click();
  await expect(equipment.locator('.settings-groups-section')).toHaveCount(2);
  await expect(equipment).toContainText('Вентиляция');
  await expect(equipment).toContainText('Кондиционирование');

  const ventilation = equipment.locator('.settings-groups-section').filter({ hasText: 'Вентиляция' });
  await ventilation.locator('.settings-groups-section-toggle').click();
  await expect(ventilation.locator('#settings-group-name-101')).toHaveValue('Вентиляторы');
  await expect(ventilation).not.toContainText('Крепёж');
  const sortWidth = await ventilation.locator('#settings-group-sort-101').evaluate((element) => element.getBoundingClientRect().width);
  expect(sortWidth).toBeLessThanOrEqual(72);
});
