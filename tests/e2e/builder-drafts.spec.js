const { test, expect } = require('@playwright/test');
const { login, apiGetJson, openKpWorkspace, openOrdersNewRequest } = require('./helpers');

test.describe('local builder drafts', () => {
  test('new order draft can be kept and then discarded on exit', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    await openOrdersNewRequest(page);

    await page.fill('#doc-addr', 'Черновик комплектации');
    await page.locator('#page-doc button', { hasText: 'Назад' }).click();
    await expect(page.locator('#m-confirm-delete')).toHaveClass(/open/);
    await expect(page.locator('#cd-msg')).toHaveText('Внесённые изменения не сохранены, сохранить локально для дальнейшей работы?');
    await page.click('#cd-confirm-btn');
    await expect(page.locator('#page-orders')).toBeVisible();

    await openOrdersNewRequest(page);
    await expect(page.locator('#doc-addr')).toHaveValue('Черновик комплектации');
    await page.locator('#page-doc button', { hasText: 'Назад' }).click();
    await page.click('#cd-cancel-btn');
    await expect(page.locator('#page-orders')).toBeVisible();

    await openOrdersNewRequest(page);
    await expect(page.locator('#doc-addr')).toHaveValue('');
  });

  test('new KP draft is restored only when the user keeps it', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    await openKpWorkspace(page);
    await page.evaluate(() => window.openNewKpQuote());
    await expect(page.locator('#page-kp-builder')).toBeVisible();

    await page.fill('#kp-quote-title', 'Локальный черновик КП');
    await page.evaluate(() => window.backFromKpBuilder());
    await expect(page.locator('#m-confirm-delete')).toHaveClass(/open/);
    await page.click('#cd-confirm-btn');
    await expect(page.locator('#page-kp-list')).toBeVisible();

    await page.evaluate(() => window.openNewKpQuote());
    await expect(page.locator('#kp-quote-title')).toHaveValue('Локальный черновик КП');
    await page.evaluate(() => window.backFromKpBuilder());
    await page.click('#cd-cancel-btn');
    await expect(page.locator('#page-kp-list')).toBeVisible();

    await page.evaluate(() => window.openNewKpQuote());
    await expect(page.locator('#page-kp-builder')).toBeVisible();
    await expect(page.locator('#kp-quote-title')).toHaveValue('');
  });

  test('existing order draft is isolated by order id', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    const orders = await apiGetJson(page, '/api/orders.php?action=orders');
    expect(Array.isArray(orders) && orders.length).toBeTruthy();
    const order = orders[0];

    await page.evaluate(() => window.ensurePageScripts('order-edit'));
    await page.evaluate((id) => window.openOrderEdit(id), order.id);
    await expect(page.locator('#page-order-edit')).toBeVisible();
    const originalAddress = await page.locator('#oe-addr').inputValue();
    await page.fill('#oe-addr', `${originalAddress} черновик`);
    await page.locator('#page-order-edit button', { hasText: 'Назад' }).click();
    await page.click('#cd-confirm-btn');
    await expect(page.locator('#page-orders')).toBeVisible();

    await page.evaluate((id) => window.openOrderEdit(id), order.id);
    await expect(page.locator('#oe-addr')).toHaveValue(`${originalAddress} черновик`);
    await page.locator('#page-order-edit button', { hasText: 'Назад' }).click();
    await page.click('#cd-cancel-btn');

    await page.evaluate((id) => window.openOrderEdit(id), order.id);
    await expect(page.locator('#oe-addr')).toHaveValue(originalAddress);
  });
});
