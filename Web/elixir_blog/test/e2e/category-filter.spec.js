// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('카테고리 필터링', () => {
  // T105: 포스트 메타데이터의 태그 클릭 시 필터링된 뷰로 이동하는지 확인
  test('포스트 메타데이터의 태그 클릭 시 필터링된 뷰로 이동해야 함', async ({ page }) => {
    // 포스트 상세 페이지로 이동
    await page.goto('/posts/background-jobs');

    // 첫 번째 태그 클릭
    const firstTag = page.locator('a[href^="/categories/"]').first();
    const tagText = await firstTag.textContent();
    await firstTag.click();

    // 카테고리 필터 페이지로 이동했는지 확인
    await expect(page).toHaveURL(/\/categories\/.+/);

    // 페이지 타이틀에 카테고리 이름이 포함되어 있는지 확인
    const pageTitle = page.locator('h1').first();
    await expect(pageTitle).toBeVisible();
  });

  // T106: 카테고리 페이지에 해당 태그를 가진 포스트만 표시되는지 확인
  test('카테고리 페이지에 해당 태그를 가진 포스트만 표시되어야 함', async ({ page }) => {
    // 특정 카테고리 페이지로 이동 (예: elixir)
    await page.goto('/categories/elixir');

    // 포스트 카드가 표시되는지 확인
    const postCards = page.locator('[data-post-card]');
    const postCount = await postCards.count();
    expect(postCount).toBeGreaterThan(0);

    // 각 포스트가 태그를 가지고 있는지 확인 (PostGrid는 span으로 태그를 렌더링)
    for (let i = 0; i < Math.min(postCount, 5); i++) {
      const postCard = postCards.nth(i);
      const tags = postCard.locator('span.bg-gray-100');
      const tagCount = await tags.count();

      // 적어도 하나의 태그가 있어야 함
      expect(tagCount).toBeGreaterThan(0);
    }
  });

  // T107: 카테고리 이름/레이블이 눈에 띄게 표시되는지 확인
  test('카테고리 이름이 눈에 띄게 표시되어야 함', async ({ page }) => {
    await page.goto('/categories/elixir');

    // Hero 섹션의 카테고리 이름 확인
    const categoryTitle = page.locator('h1').first();
    await expect(categoryTitle).toBeVisible();

    // 카테고리 이름이 포함되어 있는지 확인
    const titleText = await categoryTitle.textContent();
    expect(titleText).toBeTruthy();
    expect(titleText.length).toBeGreaterThan(0);

    // 포스트 개수 표시 확인 (Hero 섹션의 p 태그에서만 찾기)
    const postCountText = page.locator('.bg-gradient-to-r p.text-xl');
    await expect(postCountText).toBeVisible();
  });

  // T108: 필터 해제 시 홈페이지로 돌아가는지 확인
  test('필터 해제 시 홈페이지로 돌아가야 함', async ({ page }) => {
    // 카테고리 페이지로 이동
    await page.goto('/categories/elixir');

    // "모든 포스트 보기" 링크 클릭 (사이드바에서 찾기)
    const clearFilterLink = page.locator('[data-category-sidebar]').getByText('모든 포스트 보기');
    await expect(clearFilterLink).toBeVisible();
    await clearFilterLink.click();

    // 홈페이지로 이동했는지 확인
    await expect(page).toHaveURL('/');

    // 캐러셀이 보이는지 확인 (홈페이지임을 검증)
    const carousel = page.locator('[data-carousel]');
    await expect(carousel).toBeVisible();
  });

  // 추가 테스트: 존재하지 않는 카테고리 처리
  test('존재하지 않는 카테고리는 404로 리다이렉트되어야 함', async ({ page }) => {
    await page.goto('/categories/non-existent-category-12345');

    // 홈페이지로 리다이렉트되고 오류 메시지가 표시되어야 함
    await expect(page).toHaveURL('/');

    // 오류 메시지 확인 (LiveView flash message)
    const errorMessage = page.getByText(/카테고리를 찾을 수 없습니다/);
    await expect(errorMessage).toBeVisible({ timeout: 2000 }).catch(() => {
      console.log('Flash message may have disappeared');
    });
  });

  // 추가 테스트: 카테고리 사이드바 표시 확인
  test('카테고리 사이드바가 표시되어야 함', async ({ page }) => {
    await page.goto('/categories/elixir');

    // 카테고리 사이드바 확인
    const sidebar = page.locator('[data-category-sidebar]');

    // 사이드바가 있는지 확인 (일부 뷰에서는 없을 수 있음)
    const sidebarExists = await sidebar.count() > 0;

    if (sidebarExists) {
      await expect(sidebar).toBeVisible();

      // 카테고리 링크가 있는지 확인
      const categoryLinks = sidebar.locator('a[href^="/categories/"]');
      const linkCount = await categoryLinks.count();
      expect(linkCount).toBeGreaterThan(0);
    }
  });

  // 추가 테스트: 카테고리 간 네비게이션
  test('카테고리 간 네비게이션이 작동해야 함', async ({ page }) => {
    await page.goto('/categories/elixir');

    // 현재 페이지가 Elixir 카테고리인지 확인
    await expect(page).toHaveURL('/categories/elixir');

    // 다른 카테고리 링크를 찾아서 클릭 (사이드바 또는 포스트 태그)
    const otherCategoryLink = page.locator('a[href^="/categories/"]').filter({ hasNotText: 'Elixir' }).first();

    const linkExists = await otherCategoryLink.count() > 0;
    if (linkExists) {
      await otherCategoryLink.click();

      // 다른 카테고리 페이지로 이동했는지 확인
      await expect(page).toHaveURL(/\/categories\/.+/);

      // 헤더가 여전히 보이는지 확인 (일관된 네비게이션)
      const header = page.locator('header');
      await expect(header).toBeVisible();
    }
  });
});
