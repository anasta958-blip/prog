const { expect } = require('@playwright/test');

async function login(page, username, password) {
  await page.goto('/');
  await expect(page.locator('#li-u')).toBeVisible();
  await page.fill('#li-u', username);
  await page.fill('#li-p', password);
  await page.locator('#login-screen button').click();
  await expect(page.locator('#login-screen')).toBeHidden();
}

async function csrfToken(page) {
  return page.evaluate(() => window.CSRF_TOKEN || '');
}

async function apiPost(page, url, options = {}) {
  const token = await csrfToken(page);
  const headers = { ...(options.headers || {}) };
  if (token) headers['X-CSRF-Token'] = token;
  return page.request.post(url, { ...options, headers });
}

async function apiJson(response) {
  const payload = await response.json();
  if (
    payload &&
    typeof payload === 'object' &&
    typeof payload.ok === 'boolean' &&
    Object.prototype.hasOwnProperty.call(payload, 'data') &&
    Object.prototype.hasOwnProperty.call(payload, 'error')
  ) {
    return payload.data;
  }
  return payload;
}

async function apiGetJson(page, url) {
  return apiJson(await page.request.get(url));
}

async function openKpWorkspace(page) {
  await page.click('#space-tab-doc');
  await expect(page.locator('#page-kp-list')).toBeVisible();
}

async function openPkpWorkspace(page) {
  await page.click('#space-tab-doc');
  await page.evaluate(() => { window.openQuoteWorkspace('pkp', 'list'); });
  await expect(page.locator('#page-kp-list')).toBeVisible();
}

async function openOrdersList(page) {
  await page.click('#space-tab-orders');
  await expect(page.locator('#page-orders')).toBeVisible();
  await expect(page.locator('#or-kanban')).toBeVisible();
}

async function openOrdersNewRequest(page) {
  await page.click('#space-tab-orders');
  await expect(page.locator('#or-kanban')).toBeVisible();
  await page.locator('#or-kanban button[onclick*="showPage"]').first().click();
  await expect(page.locator('#page-doc')).toBeVisible();
}

module.exports = {
  login,
  apiPost,
  apiJson,
  apiGetJson,
  openKpWorkspace,
  openPkpWorkspace,
  openOrdersList,
  openOrdersNewRequest,
};
