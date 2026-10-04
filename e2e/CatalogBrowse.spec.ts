import { test, expect } from '@playwright/test';

// Anonymous catalog regression checks for the WebApp. These only need the WebApp and the
// Catalog API (no Identity/Basket/Ordering), so they can run without the full AppHost stack.
// Selectors and expected values come from the QA browser pass (101 seeded catalog items,
// 9 items per page).

test.describe('Catalog browse (anonymous)', () => {
  test('home page renders header, hero heading and title', async ({ page }) => {
    await page.goto('/');

    await expect(page.getByRole('heading', { name: 'Ready for a new adventure?', level: 1 })).toBeVisible();
    await expect(page).toHaveTitle('AdventureWorks');
    // The brand link also appears in the footer, so scope to the header (banner).
    await expect(page.getByRole('banner').getByRole('link', { name: 'AdventureWorks home' })).toBeVisible();

    // "Shop all" is inside the Primary nav; "Sign in" and "Shopping bag" are sibling links in the header.
    const header = page.getByRole('banner');
    await expect(header.getByRole('navigation', { name: 'Primary' }).getByRole('link', { name: 'Shop all' })).toBeVisible();
    await expect(header.getByRole('link', { name: 'Sign in' })).toBeVisible();
    await expect(header.getByRole('link', { name: 'Shopping bag' })).toBeVisible();
  });

  test('first page lists 9 catalog items, sorted by name', async ({ page }) => {
    await page.goto('/');

    await expect(page.locator('.catalog-item')).toHaveCount(9);
    await expect(page.getByRole('combobox', { name: 'Sort' })).toBeVisible();
    // First sorted item is Adventurer GPS Watch, then AeroLite Cycling Helmet.
    await expect(page.locator('.catalog-item').nth(0)).toContainText('Adventurer GPS Watch');
    await expect(page.locator('.catalog-item').nth(1)).toContainText('AeroLite Cycling Helmet');
  });

  test('brand and type filters show the seeded facet totals', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Ready for a new adventure?' })).toBeVisible();

    await expect(page.getByRole('heading', { name: 'BRAND', level: 3 })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'TYPE', level: 3 })).toBeVisible();
    // "All 101" appears once under BRAND and once under TYPE.
    await expect(page.getByRole('link', { name: 'All 101' })).toHaveCount(2);
    await expect(page.getByRole('link', { name: /^Bags 16$/ })).toBeVisible();
    await expect(page.getByRole('link', { name: /^Footwear 13$/ })).toBeVisible();
  });

  test('item card opens the item details page', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'Ready for a new adventure?' })).toBeVisible();

    await page.getByRole('link', { name: 'Adventurer GPS Watch' }).click();

    await expect(page).toHaveURL(/\/item\/\d+$/);
    await expect(page.getByRole('heading', { name: 'Adventurer GPS Watch' })).toBeVisible();
    await expect(page.getByText('$199.99').first()).toBeVisible();
  });

  test('pagination navigates forward and back', async ({ page }) => {
    await page.goto('/');
    const pagination = page.locator('nav.catalog-pagination[aria-label="Catalog pages"]');
    await expect(pagination).toBeVisible();

    await pagination.locator('a.page-nav[aria-label="Next page"]').click();
    await expect(page).toHaveURL(/\?page=2$/);
    await expect(page.locator('.catalog-product')).toHaveCount(9);

    await pagination.locator('a.page-nav[aria-label="Previous page"]').click();
    await expect(page).not.toHaveURL(/page=2/);
    await expect(page.locator('.catalog-product')).toHaveCount(9);
  });

  test('direct navigation to page 2 shows a different first item', async ({ page }) => {
    await page.goto('/?page=2');

    await expect(page.locator('.catalog-product')).toHaveCount(9);
    await expect(page.locator('.catalog-product').first()).not.toContainText('Adventurer GPS Watch');
  });
});
