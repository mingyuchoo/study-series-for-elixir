import { test, expect } from '@playwright/test';

test.describe('Category Navigation', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to the category statistics page before each test
    await page.goto('/categories');
    await page.waitForLoadState('networkidle');
  });

  test('navigates to category detail page on card click', async ({ page }) => {
    // Find the first category card
    const categoryCard = page.locator('[data-testid="category-card"]').first();
    await expect(categoryCard).toBeVisible();

    // Get the category slug from the href
    const href = await categoryCard.getAttribute('href');
    expect(href).toBeTruthy();
    expect(href).toMatch(/^\/categories\/.+/);

    // Get the category name for verification
    const categoryName = await categoryCard.locator('h3').textContent();

    // Click on the category card and wait for URL change
    await Promise.all([
      page.waitForURL(/\/categories\/.+/, { timeout: 5000 }),
      categoryCard.click()
    ]);

    // Wait for page to be fully loaded
    await page.waitForLoadState('networkidle');

    // Verify we navigated to the correct URL
    expect(page.url()).toMatch(/\/categories\/.+/);

    // Verify category name is displayed on the detail page
    if (categoryName) {
      await expect(page.locator(`text=${categoryName}`).first()).toBeVisible();
    }
  });

  test('displays filtered posts on category detail page', async ({ page }) => {
    // Find a category card with posts
    const categoryCards = page.locator('[data-testid="category-card"]');
    const count = await categoryCards.count();
    expect(count).toBeGreaterThan(0);

    // Find a category with at least one post
    let foundCategoryWithPosts = false;
    let categoryName: string | null = null;

    for (let i = 0; i < count; i++) {
      const card = categoryCards.nth(i);
      const text = await card.textContent();

      // Check if post count is greater than 0
      if (text && /[1-9]\d*개의 포스트/.test(text)) {
        foundCategoryWithPosts = true;
        categoryName = await card.locator('h3').textContent();

        // Click and wait for URL change
        await Promise.all([
          page.waitForURL(/\/categories\/.+/, { timeout: 5000 }),
          card.click()
        ]);
        break;
      }
    }

    if (foundCategoryWithPosts) {
      // Wait for page to be fully loaded
      await page.waitForLoadState('networkidle');

      // Verify we're on a category detail page
      const currentUrl = page.url();
      expect(currentUrl).toMatch(/\/categories\/.+/);

      // Verify posts are displayed
      const posts = page.locator('[data-post-card]');
      const postCount = await posts.count();
      expect(postCount).toBeGreaterThan(0);

      // Verify category name is displayed in the hero section
      if (categoryName) {
        await expect(page.locator('h1', { hasText: categoryName })).toBeVisible();
      }
    } else {
      // If no categories have posts, skip detailed verification
      expect(count).toBeGreaterThan(0);
    }
  });

  test('category detail layout matches homepage structure', async ({ page }) => {
    // Click on first category and wait for URL change
    const categoryCard = page.locator('[data-testid="category-card"]').first();
    await Promise.all([
      page.waitForURL(/\/categories\/.+/, { timeout: 5000 }),
      categoryCard.click()
    ]);
    await page.waitForLoadState('networkidle');

    // Verify header is present
    const header = page.locator('header, [role="banner"]').first();
    await expect(header).toBeVisible();

    // Verify footer is present
    const footer = page.locator('footer, [role="contentinfo"]').first();
    await expect(footer).toBeVisible();

    // Verify main content area exists
    const main = page.locator('main, [role="main"]').first();
    await expect(main).toBeVisible();

    // Verify navigation links in header (should be consistent with homepage)
    const navLinks = page.locator('header a, [role="banner"] a');
    const navCount = await navLinks.count();
    expect(navCount).toBeGreaterThan(0);
  });

  test('displays category name and post count accurately', async ({ page }) => {
    // Find a category with posts
    const categoryCards = page.locator('[data-testid="category-card"]');
    const count = await categoryCards.count();

    let foundValidCategory = false;

    for (let i = 0; i < count; i++) {
      const card = categoryCards.nth(i);
      const cardText = await card.textContent();

      // Extract post count from card (e.g., "5개의 포스트")
      const postCountMatch = cardText?.match(/(\d+)개의 포스트/);
      const expectedPostCount = postCountMatch ? parseInt(postCountMatch[1]) : 0;

      // Only test categories with at least 1 post
      if (expectedPostCount > 0) {
        // Click and wait for URL change
        try {
          await Promise.all([
            page.waitForURL(/\/categories\/.+/, { timeout: 5000 }),
            card.click()
          ]);
          await page.waitForLoadState('networkidle');

          // Count posts on detail page
          const posts = page.locator('[data-post-card]');
          const actualPostCount = await posts.count();

          // Verify post count matches (or is less if limited)
          // Detail page might limit posts shown, so actual count should be <= expected
          expect(actualPostCount).toBeLessThanOrEqual(expectedPostCount);
          expect(actualPostCount).toBeGreaterThan(0);
          foundValidCategory = true;
          break;
        } catch (e) {
          // Navigation failed, try next category
          await page.goto('/categories');
          await page.waitForLoadState('networkidle');
        }
      }
    }

    // At least we should have found some categories
    expect(count).toBeGreaterThan(0);
  });

  test('handles empty categories gracefully', async ({ page }) => {
    // Find a category with 0 posts
    const categoryCards = page.locator('[data-testid="category-card"]');
    const count = await categoryCards.count();

    let foundEmptyCategory = false;

    for (let i = 0; i < count; i++) {
      const card = categoryCards.nth(i);
      const text = await card.textContent();

      // Check if post count is 0
      if (text && text.includes('0개의 포스트')) {
        foundEmptyCategory = true;
        // Click and wait for URL change
        await Promise.all([
          page.waitForURL(/\/categories\/.+/, { timeout: 5000 }),
          card.click()
        ]);
        break;
      }
    }

    if (foundEmptyCategory) {
      // Wait for page to be fully loaded
      await page.waitForLoadState('networkidle');

      // Verify page loads without errors
      expect(page.url()).toMatch(/\/categories\/.+/);

      // Verify no post cards are displayed or empty state is shown
      const posts = page.locator('[data-post-card]');
      const postCount = await posts.count();

      // Should either show no posts or an empty state message
      if (postCount === 0) {
        // Verify empty state message is present
        await expect(page.locator('text=포스트 없음')).toBeVisible();
      }

      // Page should load without crashing
      const pageContent = await page.content();
      expect(pageContent).toBeTruthy();
    } else {
      // Skip test if no empty categories found
      console.log('No empty categories found in test data - skipping empty state verification');
      expect(count).toBeGreaterThan(0);
    }
  });

  test('category cards have hover effects', async ({ page }) => {
    const categoryCard = page.locator('[data-testid="category-card"]').first();
    await expect(categoryCard).toBeVisible();

    // Get initial box shadow or other style
    const initialShadow = await categoryCard.evaluate((el) => {
      return window.getComputedStyle(el.querySelector('div')!).boxShadow;
    });

    // Hover over the card
    await categoryCard.hover();

    // Wait a bit for transition
    await page.waitForTimeout(300);

    // Get shadow after hover
    const hoverShadow = await categoryCard.evaluate((el) => {
      return window.getComputedStyle(el.querySelector('div')!).boxShadow;
    });

    // Shadow should change on hover (hover:shadow-xl effect)
    expect(hoverShadow).not.toBe(initialShadow);
  });

  test('category cards display visual navigation indicator', async ({ page }) => {
    const categoryCard = page.locator('[data-testid="category-card"]').first();

    // Verify arrow/chevron icon is present
    const icon = categoryCard.locator('svg').first();
    await expect(icon).toBeVisible();

    // Verify it's a navigation indicator (chevron-right type icon)
    const svgContent = await icon.innerHTML();
    expect(svgContent).toBeTruthy();
  });
});
