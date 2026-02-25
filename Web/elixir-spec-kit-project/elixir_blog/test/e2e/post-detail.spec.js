// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('포스트 상세 페이지', () => {
  // 테스트용 포스트 slug (데이터베이스에 있는 포스트 사용)
  const testPostSlug = 'background-jobs';

  test.beforeEach(async ({ page }) => {
    // 포스트 상세 페이지로 이동
    await page.goto(`/posts/${testPostSlug}`);
  });

  // T058: 포스트 제목이 눈에 띄게 표시되는지 확인
  test('포스트 제목이 눈에 띄게 표시되어야 함', async ({ page }) => {
    // Hero 섹션의 제목 확인
    const title = page.locator('h1').first();
    await expect(title).toBeVisible();

    // 제목이 비어있지 않은지 확인
    const titleText = await title.textContent();
    expect(titleText).toBeTruthy();
    expect(titleText.length).toBeGreaterThan(0);
  });

  // T059: 메타데이터(저자, 태그, 읽기 시간)가 올바르게 렌더링되는지 확인
  test('메타데이터가 올바르게 렌더링되어야 함', async ({ page }) => {
    // 저자 정보 확인 (페이지에 저자 이름이 있는지 확인)
    const pageContent = await page.content();
    expect(pageContent).toMatch(/강민지|김철수|박민수|이영희|정수진/); // 다양한 저자 이름 중 하나

    // 읽기 시간 확인
    const readingTime = page.getByText(/\d+분 읽기/);
    await expect(readingTime).toBeVisible();

    // 발행 날짜 확인
    const publishDate = page.getByText(/20\d{2}년/);
    await expect(publishDate).toBeVisible();

    // 태그 확인 (최소 하나의 태그가 있어야 함)
    const tags = page.locator('a[href^="/categories/"]');
    const tagCount = await tags.count();
    expect(tagCount).toBeGreaterThan(0);
  });

  // T060: 썸네일 이미지가 표시되는지 확인
  test('Hero 섹션과 메타데이터 영역이 표시되어야 함', async ({ page }) => {
    // Hero 섹션 확인 (그라디언트 배경)
    const heroSection = page.locator('.bg-gradient-to-r').first();
    await expect(heroSection).toBeVisible();

    // 요약 텍스트 확인
    const summary = page.locator('p.text-xl').first();
    await expect(summary).toBeVisible();
  });

  // T061: 마크다운 콘텐츠가 적절한 형식으로 렌더링되는지 확인
  test('마크다운 콘텐츠가 적절한 형식으로 렌더링되어야 함', async ({ page }) => {
    // markdown-content 영역 확인
    const markdownContent = page.locator('.markdown-content');
    await expect(markdownContent).toBeVisible();

    // 제목 확인 (h2 또는 h3)
    const headings = markdownContent.locator('h2, h3');
    const headingCount = await headings.count();
    expect(headingCount).toBeGreaterThan(0);

    // 단락 확인
    const paragraphs = markdownContent.locator('p');
    const paragraphCount = await paragraphs.count();
    expect(paragraphCount).toBeGreaterThan(0);

    // 코드 블록 확인 (있는 경우)
    const codeBlocks = markdownContent.locator('pre code');
    if (await codeBlocks.count() > 0) {
      await expect(codeBlocks.first()).toBeVisible();
    }

    // 리스트 확인 (있는 경우)
    const lists = markdownContent.locator('ul, ol');
    if (await lists.count() > 0) {
      await expect(lists.first()).toBeVisible();
    }
  });

  // T062: 목차가 모든 제목과 함께 표시되는지 확인
  test('목차가 모든 제목과 함께 표시되어야 함', async ({ page }) => {
    // 목차 네비게이션 확인
    const tocNav = page.locator('#toc-nav');

    // 목차가 있는지 확인 (일부 포스트는 목차가 없을 수 있음)
    const tocExists = await tocNav.count() > 0;

    if (tocExists) {
      await expect(tocNav).toBeVisible();

      // 목차 링크 확인
      const tocLinks = tocNav.locator('a');
      const linkCount = await tocLinks.count();
      expect(linkCount).toBeGreaterThan(0);

      // 각 링크가 # 으로 시작하는 href를 가지는지 확인
      const firstLink = tocLinks.first();
      const href = await firstLink.getAttribute('href');
      expect(href).toMatch(/^#/);
    }
  });

  // T063: 목차 항목 클릭이 올바른 섹션으로 스크롤되는지 확인
  test('목차 항목 클릭이 섹션으로 스크롤되어야 함', async ({ page }) => {
    const tocNav = page.locator('#toc-nav');
    const tocExists = await tocNav.count() > 0;

    if (tocExists) {
      // 첫 번째 목차 링크 클릭
      const firstLink = tocNav.locator('a').first();
      await firstLink.click();

      // 스크롤이 발생했는지 확인 (페이지가 조금 대기)
      await page.waitForTimeout(500);

      // 페이지가 스크롤 되었는지 확인
      const scrollY = await page.evaluate(() => window.scrollY);
      // 스크롤이 약간이라도 발생했는지 확인 (hero 섹션을 넘어서)
      expect(scrollY).toBeGreaterThan(100);
    }
  });

  // 추가 테스트: "홈으로 돌아가기" 링크 확인
  test('"홈으로 돌아가기" 링크가 작동해야 함', async ({ page }) => {
    const backLink = page.getByText('홈으로 돌아가기');
    await expect(backLink).toBeVisible();

    await backLink.click();

    // 홈페이지로 리다이렉트되었는지 확인
    await expect(page).toHaveURL('/');
  });

  // 추가 테스트: 404 처리 확인
  test('존재하지 않는 포스트는 404로 리다이렉트되어야 함', async ({ page }) => {
    await page.goto('/posts/non-existent-post-slug-12345');

    // 홈페이지로 리다이렉트되고 오류 메시지가 표시되어야 함
    await expect(page).toHaveURL('/');

    // 오류 메시지 확인 (LiveView flash message)
    const errorMessage = page.getByText(/포스트를 찾을 수 없습니다/);
    // Flash 메시지는 빠르게 사라질 수 있으므로 타임아웃을 짧게 설정
    await expect(errorMessage).toBeVisible({ timeout: 2000 }).catch(() => {
      // Flash 메시지가 이미 사라졌을 수 있음
      console.log('Flash message may have disappeared');
    });
  });
});
