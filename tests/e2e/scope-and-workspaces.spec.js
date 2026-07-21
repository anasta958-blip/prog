const { test, expect } = require('@playwright/test');
const { login, openKpWorkspace, openPkpWorkspace, openOrdersList } = require('./helpers');

test.describe('CRM workspace scope scenarios', () => {
  test('manager sees only own KP cards', async ({ page }) => {
    await login(page, 'manager1', 'password');

    await openKpWorkspace(page);

    await expect(page.locator('#kp-quotes-kanban')).toContainText('E2E MANAGER KP');
    await expect(page.locator('#kp-quotes-kanban')).not.toContainText('E2E ADMIN KP');
  });

  test('KP kanban keeps DOM and ignores stale refresh responses', async ({ page }) => {
    await login(page, 'admin_new', 'password');
    await openKpWorkspace(page);
    await expect(page.locator('.kanban-card[data-kp-id]').first()).toBeVisible();

    const result = await page.evaluate(async () => {
      window.stopKpQuotesLiveRefresh();
      const firstCard = document.querySelector('.kanban-card[data-kp-id]');
      const grid = document.querySelector('#kp-quotes-kanban .kanban-grid');
      if (!firstCard || !grid) return null;

      const originalLoader = window.kpLoadBoardQuotes;
      const currentRows = JSON.parse(JSON.stringify(window.kpQuotes || []));
      grid.scrollLeft = Math.min(160, Math.max(0, grid.scrollWidth - grid.clientWidth));
      const scrollBefore = grid.scrollLeft;

      window.kpLoadBoardQuotes = async () => JSON.parse(JSON.stringify(currentRows));
      await window.loadKpQuotes({ preserveScroll: true, silent: true });
      const unchangedCard = document.querySelector('.kanban-card[data-kp-id]');
      const unchangedGrid = document.querySelector('#kp-quotes-kanban .kanban-grid');
      const unchangedScroll = unchangedGrid ? unchangedGrid.scrollLeft : -1;

      const pending = [];
      window.kpLoadBoardQuotes = () => new Promise((resolve) => pending.push(resolve));
      const oldRows = JSON.parse(JSON.stringify(currentRows));
      const newRows = JSON.parse(JSON.stringify(currentRows));
      if (oldRows[0]) oldRows[0].object_address = 'STALE KANBAN VALUE';
      if (newRows[0]) newRows[0].object_address = 'FRESH KANBAN VALUE';
      const oldRequest = window.loadKpQuotes({ preserveScroll: true, silent: true });
      const freshRequest = window.loadKpQuotes({ preserveScroll: true, silent: true });
      pending[1](newRows);
      await freshRequest;
      pending[0](oldRows);
      await oldRequest;

      const textAfterRace = document.getElementById('kp-quotes-kanban').textContent || '';
      window.kpLoadBoardQuotes = originalLoader;
      return {
        cardPreserved: firstCard === unchangedCard,
        scrollBefore,
        scrollAfter: unchangedScroll,
        freshVisible: textAfterRace.includes('FRESH KANBAN VALUE'),
        staleVisible: textAfterRace.includes('STALE KANBAN VALUE'),
      };
    });

    expect(result).not.toBeNull();
    expect(result.cardPreserved).toBe(true);
    expect(result.scrollAfter).toBe(result.scrollBefore);
    expect(result.freshVisible).toBe(true);
    expect(result.staleVisible).toBe(false);
  });

  test('manager sees only own PKP cards', async ({ page }) => {
    await login(page, 'manager1', 'password');

    await openPkpWorkspace(page);

    await expect(page.locator('#kp-quotes-kanban')).toContainText('E2E MANAGER PKP');
    await expect(page.locator('#kp-quotes-kanban')).not.toContainText('E2E ADMIN PKP');
  });

  test('manager sees only own orders in complectation list', async ({ page }) => {
    await login(page, 'manager1', 'password');

    await openOrdersList(page);

    await expect(page.locator('#or-kanban')).toContainText('E2E ORDER MANAGER');
    await expect(page.locator('#or-kanban')).not.toContainText('E2E ORDER ADMIN');
  });
});
