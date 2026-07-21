const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { login, apiPost, apiJson, apiGetJson, openKpWorkspace, openPkpWorkspace, openOrdersList, openOrdersNewRequest } = require('./helpers');

test.describe('CRM smoke auth and permissions', () => {
  test('local assets use automatic file modification versions', async ({ page }) => {
    await page.goto('/');

    const localAssets = await page.evaluate(() => [
      ...Array.from(document.querySelectorAll('script[src]'), (node) => node.getAttribute('src')),
      ...Array.from(document.querySelectorAll('link[rel="stylesheet"][href]'), (node) => node.getAttribute('href')),
    ].filter((url) => url && !/^(?:https?:)?\/\//i.test(url)));

    expect(localAssets.length).toBeGreaterThan(0);
    for (const url of localAssets) {
      expect(url).toMatch(/[?&]v=\d+$/);
      const parsed = new URL(url, 'http://localhost/');
      const filePath = path.join(process.cwd(), decodeURIComponent(parsed.pathname.replace(/^\/+/, '')));
      expect(Number(parsed.searchParams.get('v'))).toBe(Math.floor(fs.statSync(filePath).mtimeMs / 1000));
    }
  });

  test('application update check opens a refresh dialog for a new version', async ({ page }) => {
    await login(page, 'admin_new', 'password');

    await page.evaluate(() => {
      window.APP_VERSION = 'old-version';
      window.fetch = async () => ({
        ok: true,
        json: async () => ({ version: 'new-version' }),
      });
      return window.checkApplicationVersion();
    });

    await expect(page.locator('#m-app-update')).toHaveClass(/open/);
    await expect(page.locator('#m-app-update')).toContainText('Доступна новая версия');

    await page.click('#app-update-later-btn');
    await expect(page.locator('#m-app-update')).not.toHaveClass(/open/);
    expect(await page.evaluate(() => window.APP_VERSION_CHECK_INTERVAL_MS)).toBe(5 * 60 * 60 * 1000);
  });

  test('admin sees settings access and catalog export', async ({ page }) => {
    await login(page, 'admin_new', 'password');

    await expect(page.locator('#space-tab-settings')).toBeVisible();

    await page.click('#space-tab-settings');
    await expect(page.locator('#nav-settings-access')).toBeVisible();

    await page.click('#space-tab-catalog');
    await expect(page.locator('#gc-export-btn')).toBeVisible();
  });

  test('admin can open the user card menu and appoint a director', async ({ page }) => {
    await login(page, 'admin_new', 'password');

    await page.click('#space-tab-settings');
    await page.click('#nav-settings-users');

    const candidate = page.locator('#users-tree .emp-card[data-is-director="0"]').first();
    await expect(candidate).toBeVisible();
    await candidate.locator('.emp-card-menu-trigger').click();

    const menu = candidate.locator('.emp-card-actions-menu');
    await expect(menu).toBeVisible();
    await expect(menu.getByText('Редактировать', { exact: true })).toBeVisible();
    await expect(menu.getByText('Удалить', { exact: true })).toBeVisible();
    await expect(menu.getByText('Назначить директором', { exact: true })).toBeVisible();

    page.once('dialog', dialog => dialog.accept());
    await menu.getByText('Назначить директором', { exact: true }).click();

    await expect(page.locator('#users-tree .emp-card[data-is-director="1"] .emp-position')).toHaveText('Директор');
  });

  test('admin can delete a user without deleting their orders', async ({ page }) => {
    const suffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    const username = `delete-user-${suffix}`;
    const address = `DELETE USER ORDER ${suffix}`;

    await login(page, 'admin_new', 'password');
    const createUserResponse = await apiPost(page, '/api/users.php', {
      data: {
        action: 'create',
        username,
        password: 'password',
        role: 'manager',
        full_name: `Delete User ${suffix}`,
        email: `${username}@example.test`,
      },
    });
    expect(createUserResponse.ok()).toBeTruthy();
    const userId = Number((await apiJson(createUserResponse)).id);

    await apiPost(page, '/api/auth.php', { data: { action: 'logout' } });
    await login(page, username, 'password');
    const categories = await apiGetJson(page, '/api/catalog.php?action=categories');
    const category = categories.find((item) => item.code === 'equipment');
    const sections = await apiGetJson(page, `/api/catalog.php?action=sections&category_id=${category.id}`);
    const saveOrderResponse = await apiPost(page, '/api/orders.php', {
      data: {
        action: 'save_order',
        address,
        items: [{
          category_id: category.id,
          section_id: sections[0].id,
          custom_name: `Delete test item ${suffix}`,
          quantity: 1,
          unit: 'шт',
        }],
      },
    });
    expect(saveOrderResponse.ok()).toBeTruthy();
    const orderId = Number((await apiJson(saveOrderResponse)).order_id);

    await apiPost(page, '/api/auth.php', { data: { action: 'logout' } });
    await login(page, 'admin_new', 'password');
    const deleteResponse = await apiPost(page, '/api/users.php', {
      data: { action: 'delete', id: userId },
    });
    expect(deleteResponse.ok()).toBeTruthy();

    const users = await apiGetJson(page, '/api/users.php?action=list');
    expect(users.some((item) => Number(item.id) === userId)).toBeFalsy();
    const orderResponse = await page.request.get(`/api/orders.php?action=order_detail&id=${orderId}`);
    expect(orderResponse.ok()).toBeTruthy();
    expect(Number((await apiJson(orderResponse)).manager_id)).not.toBe(userId);

    await apiPost(page, '/api/orders.php', {
      data: { action: 'delete_order', id: orderId },
    });
  });

  test('prorab does not see settings space', async ({ page }) => {
    await login(page, 'engineer1', 'password');

    await expect(page.locator('#space-tab-settings')).toBeHidden();
  });

  test('prorab opens KP card but save is hidden in editor', async ({ page }) => {
    await login(page, 'engineer1', 'password');

    await openKpWorkspace(page);

    const firstCard = page.locator('.kanban-card[data-kp-id]:visible').first();
    await expect(firstCard).toBeVisible();
    await firstCard.click();

    await expect(page.locator('#page-kp-builder')).toBeVisible();
    await expect(page.locator('#kp-builder-save-btn')).toBeHidden();
  });

  test('prorab opens PKP card but save and builder actions are hidden', async ({ page }) => {
    await login(page, 'engineer1', 'password');

    await openPkpWorkspace(page);

    const firstCard = page.locator('.kanban-card[data-kp-id]:visible').first();
    await expect(firstCard).toBeVisible();
    await firstCard.click();

    await expect(page.locator('#page-kp-builder')).toBeVisible();
    await expect(page.locator('#kp-builder-save-btn')).toBeHidden();
    await expect(page.locator('#kp-builder-add-client-btn')).toBeHidden();
    await expect(page.locator('#kp-builder-add-variant-btn')).toBeHidden();
  });

  test('prorab can create and edit orders but cannot delete them', async ({ page }) => {
    await login(page, 'engineer1', 'password');

    await openOrdersNewRequest(page);
    await expect(page.locator('#page-doc .btn.btn-gr[onclick="saveDocument()"]')).toBeVisible();
    await expect(page.locator('#doc-add-cat-btn')).toBeVisible();

    await openOrdersList(page);
    const firstCard = page.locator('#or-kanban .kanban-card[data-id]').first();
    await expect(firstCard).toBeVisible();
    await firstCard.click();

    await expect(page.locator('#page-order-edit')).toBeVisible();
    await expect(page.locator('#oe-save-btn')).toBeVisible();
    await expect(page.locator('#oe-add-cat-btn')).toBeVisible();
    await expect(page.locator('#oe-delete-btn')).toBeHidden();
  });
});
