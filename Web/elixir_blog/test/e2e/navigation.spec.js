// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('사이트 네비게이션', () => {
  // T080: 홈페이지에 헤더가 표시되는지 확인
  test('홈페이지에 헤더가 표시되어야 함', async ({ page }) => {
    await page.goto('/');

    // 헤더 확인
    const header = page.locator('header');
    await expect(header).toBeVisible();

    // 사이트 로고/타이틀 확인 (header 내에서만 찾기)
    const siteLogo = page.locator('header').getByRole('link', { name: 'Elixir 블로그' });
    await expect(siteLogo).toBeVisible();

    // 네비게이션 링크 확인
    const homeLink = page.locator('header').getByText('홈');
    await expect(homeLink).toBeVisible();

    const categoriesLink = page.locator('header').getByText('카테고리');
    await expect(categoriesLink).toBeVisible();
  });

  // T081: 포스트 상세 페이지에 헤더가 표시되는지 확인
  test('포스트 상세 페이지에 헤더가 표시되어야 함', async ({ page }) => {
    await page.goto('/posts/background-jobs');

    // 헤더 확인
    const header = page.locator('header');
    await expect(header).toBeVisible();

    // 사이트 로고/타이틀 확인 (header 내에서만 찾기)
    const siteLogo = page.locator('header').getByRole('link', { name: 'Elixir 블로그' });
    await expect(siteLogo).toBeVisible();

    // 네비게이션 링크 확인
    const homeLink = page.locator('header').getByText('홈');
    await expect(homeLink).toBeVisible();

    const categoriesLink = page.locator('header').getByText('카테고리');
    await expect(categoriesLink).toBeVisible();
  });

  // T082: 홈페이지에 푸터가 표시되는지 확인
  test('홈페이지에 푸터가 표시되어야 함', async ({ page }) => {
    await page.goto('/');

    // 푸터 확인
    const footer = page.locator('footer');
    await expect(footer).toBeVisible();

    // Copyright 정보 확인
    const copyright = page.getByText(/All rights reserved/);
    await expect(copyright).toBeVisible();

    // "Built with Phoenix LiveView" 확인
    const builtWith = page.getByText('Built with Phoenix LiveView');
    await expect(builtWith).toBeVisible();

    // 푸터 링크 확인
    const footerHomeLink = page.locator('footer').getByText('홈');
    await expect(footerHomeLink).toBeVisible();

    const footerCategoriesLink = page.locator('footer').getByText('카테고리');
    await expect(footerCategoriesLink).toBeVisible();
  });

  // T083: 포스트 상세 페이지에 푸터가 표시되는지 확인
  test('포스트 상세 페이지에 푸터가 표시되어야 함', async ({ page }) => {
    await page.goto('/posts/background-jobs');

    // 페이지 하단으로 스크롤
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));

    // 푸터 확인
    const footer = page.locator('footer');
    await expect(footer).toBeVisible();

    // Copyright 정보 확인
    const copyright = page.getByText(/All rights reserved/);
    await expect(copyright).toBeVisible();
  });

  // T084: 사이트 로고/홈 링크 클릭 시 홈페이지로 이동하는지 확인
  test('사이트 로고 클릭 시 홈페이지로 이동해야 함', async ({ page }) => {
    // 포스트 페이지에서 시작
    await page.goto('/posts/background-jobs');

    // 사이트 로고 클릭
    const siteLogo = page.locator('header').getByText('Elixir 블로그');
    await siteLogo.click();

    // 홈페이지로 이동했는지 확인
    await expect(page).toHaveURL('/');

    // 캐러셀이 보이는지 확인 (홈페이지임을 검증)
    const carousel = page.locator('[data-carousel]');
    await expect(carousel).toBeVisible();
  });

  // T085: 헤더 네비게이션 링크가 제대로 작동하는지 확인
  test('헤더 네비게이션 링크가 작동해야 함', async ({ page }) => {
    await page.goto('/');

    // "홈" 링크 클릭
    const homeLink = page.locator('header').getByText('홈');
    await homeLink.click();
    await expect(page).toHaveURL('/');

    // 포스트 페이지로 이동
    await page.goto('/posts/background-jobs');

    // "홈" 링크 클릭하여 다시 홈으로
    await page.locator('header').getByText('홈').click();
    await expect(page).toHaveURL('/');

    // 캐러셀 확인
    const carousel = page.locator('[data-carousel]');
    await expect(carousel).toBeVisible();
  });

  // 추가 테스트: 활성 링크 하이라이팅 확인
  test('활성 링크가 하이라이트되어야 함', async ({ page }) => {
    // 홈페이지에서 "홈" 링크가 활성화되어 있는지 확인
    await page.goto('/');

    const homeLink = page.locator('header a[href="/"]').filter({ hasText: '홈' });

    // 활성 링크는 text-primary-600 클래스를 가져야 함
    const homeLinkClass = await homeLink.getAttribute('class');
    expect(homeLinkClass).toContain('text-primary-600');
  });

  // 추가 테스트: 포스트 간 네비게이션
  test('포스트 간 네비게이션이 작동해야 함', async ({ page }) => {
    // 홈페이지에서 시작
    await page.goto('/');

    // 첫 번째 포스트 카드 클릭
    const firstPost = page.locator('[data-post-card]').first();
    await firstPost.click();

    // 포스트 페이지로 이동했는지 확인
    await expect(page).toHaveURL(/\/posts\/.+/);

    // 헤더가 여전히 보이는지 확인
    const header = page.locator('header');
    await expect(header).toBeVisible();

    // "홈으로 돌아가기" 링크로 홈 복귀
    const backLink = page.getByText('홈으로 돌아가기');
    await backLink.click();

    await expect(page).toHaveURL('/');
  });
});
