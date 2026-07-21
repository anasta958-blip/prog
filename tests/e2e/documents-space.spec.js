const { test, expect } = require('@playwright/test');
const { login } = require('./helpers');

test.describe('Documents space', () => {
  test('admin opens report builder, previews rows, saves and reopens template', async ({ page }) => {
    await login(page, 'admin_new', 'password');

    await page.click('#space-tab-documents');
    await expect(page.locator('#page-documents-builder')).toBeVisible();
    await expect(page.locator('#nav-documents-builder')).toHaveClass(/active/);
    await page.locator('[data-doc-palette-group="quote"] summary').click();
    await expect(page.locator('[data-doc-btn="category_table"]')).toBeVisible();
    await expect(page.locator('[data-doc-btn="section_table"]')).toBeVisible();
    await expect(page.locator('[data-doc-btn="variants_summary"]')).toBeVisible();

    await expect(page.locator('button:has-text("Показать пример")')).toHaveCount(0);
    await expect.poll(() => page.evaluate(() => window.documentsState.blocks.length)).toBeGreaterThan(0);
    await expect(page.locator('.docs-preview-edit-block').first()).toBeVisible();

    await page.evaluate(() => window.documentsSelectBlock(window.documentsState.blocks[0].id));
    await expect(page.locator('#documents-properties')).toContainText('Название блока');

    const quoteOptions = page.locator('#documents-source-quote option');
    expect(await quoteOptions.count()).toBeGreaterThan(1);

    await expect(page.locator('.docs-preview-page').first()).toBeVisible();
    await expect(page.locator('.docs-preview-page').first()).toContainText('Отчет по коммерческому предложению');

    const previewHtml = await page.locator('.docs-preview-page').first().innerHTML();
    expect(previewHtml).toContain('<table');

    const templateTitle = `E2E Документ ${Date.now()}`;
    await page.fill('#documents-title', templateTitle);
    await page.fill('#documents-version-name', 'E2E Версия 1');
    await page.click('#documents-save-btn');

    await expect(page.locator('#documents-template-select')).toContainText(templateTitle);
    await expect(page.locator('#documents-version-select')).toContainText('E2E Версия 1');

    const selectedValue = await page.locator('#documents-template-select').inputValue();
    expect(Number(selectedValue)).toBeGreaterThan(0);

    await page.selectOption('#documents-template-select', selectedValue);
    await expect(page.locator('#documents-title')).toHaveValue(templateTitle);
  });
});
