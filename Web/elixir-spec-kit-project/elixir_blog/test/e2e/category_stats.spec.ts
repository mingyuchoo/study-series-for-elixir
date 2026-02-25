import { test, expect } from '@playwright/test';

test.describe('Category Statistics Overview Page', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to the category statistics page before each test
    await page.goto('/categories');
  });

  test('displays category statistics overview', async ({ page }) => {
    // Wait for page to load
    await page.waitForLoadState('networkidle');

    // Verify page title
    await expect(page).toHaveTitle(/카테고리/);

    // Verify category grid section exists
    const categoryGrid = page.locator('[data-testid="category-grid"]');
    await expect(categoryGrid).toBeVisible();

    // Verify at least one category card is displayed
    const categoryCards = page.locator('[data-testid="category-card"]');
    const count = await categoryCards.count();
    expect(count).toBeGreaterThan(0);

    // Verify each category card shows post count
    const firstCard = categoryCards.first();
    await expect(firstCard).toBeVisible();

    // Check that category name is displayed
    const cardText = await firstCard.textContent();
    expect(cardText).toBeTruthy();
    expect(cardText!.length).toBeGreaterThan(0);

    // Verify post count is displayed
    expect(cardText).toContain('개의 포스트');
  });

  test('displays post counts for each category', async ({ page }) => {
    // Wait for page to load
    await page.waitForLoadState('networkidle');

    // Get all category cards
    const categoryCards = page.locator('[data-testid="category-card"]').or(
      page.locator('a[href^="/categories/"]')
    );

    // Verify at least one category exists
    const count = await categoryCards.count();
    expect(count).toBeGreaterThan(0);

    // Check the first category card contains a number (post count)
    const firstCard = categoryCards.first();
    const cardText = await firstCard.textContent();

    // Should contain either "N개의 포스트" or just a number
    const hasNumber = /\d+/.test(cardText || '');
    expect(hasNumber).toBeTruthy();
  });

  test('loads page within performance budget', async ({ page }) => {
    const startTime = Date.now();

    await page.goto('/categories');
    await page.waitForLoadState('networkidle');

    const loadTime = Date.now() - startTime;

    // Page should load within 2 seconds (SC-001)
    expect(loadTime).toBeLessThan(2000);
  });

  test('displays category grid on mobile viewport', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });

    await page.goto('/categories');
    await page.waitForLoadState('networkidle');

    // Verify category grid is visible on mobile
    const categoryCards = page.locator('[data-testid="category-card"]').or(
      page.locator('a[href^="/categories/"]')
    );

    const count = await categoryCards.count();
    expect(count).toBeGreaterThan(0);

    // Verify first card is visible (grid should adapt to mobile)
    const firstCard = categoryCards.first();
    await expect(firstCard).toBeVisible();
  });

  test('displays popular posts section', async ({ page }) => {
    // Wait for page to load
    await page.waitForLoadState('networkidle');

    // Check if popular posts section exists
    const popularSection = page.locator('text=인기 포스트').first();
    await expect(popularSection).toBeVisible();

    // Check if popular posts grid or empty state is displayed
    const hasPopularPosts = await page.locator('[data-post-card]').count() > 0;
    const hasEmptyState = await page.locator('text=인기 포스트가 없습니다').isVisible().catch(() => false);

    // Either popular posts or empty state should be displayed
    expect(hasPopularPosts || hasEmptyState).toBeTruthy();
  });

  test('displays empty state when no popular posts exist', async ({ page }) => {
    // This test verifies the empty state UI is properly implemented
    // Note: We need to check if the empty state message is present when no popular posts exist

    await page.waitForLoadState('networkidle');

    // Look for popular posts section
    const popularSection = page.locator('text=인기 포스트');
    await expect(popularSection.first()).toBeVisible();

    // Check if we have popular posts or empty state
    const popularPostsCount = await page.locator('[data-post-card]').count();

    if (popularPostsCount === 0) {
      // Verify empty state message is displayed
      const emptyStateMessage = page.locator('text=인기 포스트가 없습니다');
      await expect(emptyStateMessage).toBeVisible();

      // Verify helpful description is shown
      const emptyStateDescription = page.locator('text=아직 인기 포스트로 표시된 글이 없습니다');
      await expect(emptyStateDescription).toBeVisible();
    } else {
      // If popular posts exist, verify they are displayed correctly
      const firstPost = page.locator('[data-post-card]').first();
      await expect(firstPost).toBeVisible();
    }
  });

  test('category detail page loads within performance budget', async ({ page }) => {
    // Navigate to categories page first
    await page.goto('/categories');
    await page.waitForLoadState('networkidle');

    // Find the first category card with posts
    const categoryCards = page.locator('[data-testid="category-card"]');
    const count = await categoryCards.count();
    expect(count).toBeGreaterThan(0);

    let categorySlug = null;
    for (let i = 0; i < count; i++) {
      const card = categoryCards.nth(i);
      const text = await card.textContent();

      // Find a category with at least one post
      if (text && /[1-9]\d*개의 포스트/.test(text)) {
        const href = await card.getAttribute('href');
        categorySlug = href?.replace('/categories/', '');
        break;
      }
    }

    // If we found a category with posts, test its load time
    if (categorySlug) {
      const startTime = Date.now();

      await page.goto(`/categories/${categorySlug}`);
      await page.waitForLoadState('networkidle');

      const loadTime = Date.now() - startTime;

      // Page should load within 3 seconds (SC-002)
      expect(loadTime).toBeLessThan(3000);
    }
  });
});
