// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('홈페이지 기능', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  // T034: 캐러셀이 썸네일과 제목이 있는 추천 포스트를 표시하는지 확인
  test('캐러셀이 추천 포스트를 표시해야 함', async ({ page }) => {
    // 캐러셀 컨테이너가 보이는지 확인
    const carousel = page.locator('[data-carousel]');
    await expect(carousel).toBeVisible();

    // 캐러셀 슬라이드가 존재하는지 확인
    const slides = page.locator('[data-carousel-slide]');
    await expect(slides.first()).toBeVisible();

    // 첫 번째 슬라이드에 제목이 있는지 확인
    const firstSlide = slides.first();
    const title = firstSlide.locator('h2');
    await expect(title).toBeVisible();

    // 요약 텍스트가 있는지 확인
    const summary = firstSlide.locator('p').first();
    await expect(summary).toBeVisible();

    // 읽어보기 버튼이 있는지 확인
    const readMoreLink = firstSlide.getByText('읽어보기');
    await expect(readMoreLink).toBeVisible();
  });

  // T035: 캐러셀 네비게이션(다음/이전 버튼)이 작동하는지 확인
  test('캐러셀 네비게이션 버튼이 작동해야 함', async ({ page }) => {
    const carousel = page.locator('[data-carousel]');
    await expect(carousel).toBeVisible();

    // 다음 버튼 찾기
    const nextButton = page.locator('button[phx-click="carousel_next"]');
    await expect(nextButton).toBeVisible();

    // 이전 버튼 찾기
    const prevButton = page.locator('button[phx-click="carousel_prev"]');
    await expect(prevButton).toBeVisible();

    // 다음 버튼 클릭
    await nextButton.click();

    // LiveView가 업데이트되기를 기다림
    await page.waitForTimeout(500);

    // 이전 버튼 클릭
    await prevButton.click();

    // LiveView가 업데이트되기를 기다림
    await page.waitForTimeout(500);
  });

  // T036: 인기 포스트 그리드가 올바른 메타데이터와 함께 표시되는지 확인
  test('인기 포스트 그리드가 메타데이터와 함께 표시되어야 함', async ({ page }) => {
    // "인기 포스트" 제목 확인
    const gridTitle = page.getByText('인기 포스트');
    await expect(gridTitle).toBeVisible();

    // 포스트 카드 찾기
    const postCards = page.locator('[data-post-card]');
    await expect(postCards.first()).toBeVisible();

    // 첫 번째 포스트 카드의 메타데이터 확인
    const firstCard = postCards.first();

    // 제목이 있는지 확인
    const cardTitle = firstCard.locator('h3, h4');
    await expect(cardTitle).toBeVisible();

    // 요약이 있는지 확인
    const summary = firstCard.locator('p').first();
    await expect(summary).toBeVisible();

    // 읽기 시간 메타데이터 확인 (단순히 "분"이 포함되어 있는지 확인)
    const metadata = firstCard.getByText(/\d+분/);
    await expect(metadata).toBeVisible();
  });

  // T037: 카테고리별 포스트 섹션이 카테고리 라벨과 함께 표시되는지 확인
  test('카테고리별 포스트 섹션이 표시되어야 함', async ({ page }) => {
    // 페이지 하단으로 스크롤
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight / 2));

    // 카테고리 섹션 찾기 (인기 포스트가 아닌 다른 섹션)
    const categorySections = page.locator('[data-category-section]');

    // 최소 하나의 카테고리 섹션이 있어야 함
    const count = await categorySections.count();
    expect(count).toBeGreaterThan(0);

    // 첫 번째 카테고리 섹션에 제목이 있는지 확인
    if (count > 0) {
      const firstSection = categorySections.first();
      const sectionTitle = firstSection.locator('h2, h3').first();
      await expect(sectionTitle).toBeVisible();
    }
  });

  // T038: 이메일 구독 폼이 보이고 입력 필드가 있는지 확인
  test('이메일 구독 폼이 표시되어야 함', async ({ page }) => {
    // 페이지 하단으로 스크롤
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));

    // 구독 섹션 찾기
    const subscriptionSection = page.getByText('최신 글을 이메일로 받아보세요');
    await expect(subscriptionSection).toBeVisible();

    // 이메일 입력 필드 확인
    const emailInput = page.locator('input[type="email"]');
    await expect(emailInput).toBeVisible();

    // 구독 버튼 확인
    const submitButton = page.getByRole('button', { name: /구독하기/ });
    await expect(submitButton).toBeVisible();
  });

  // 추가 테스트: 이메일 구독 기능 테스트
  test('이메일 구독이 성공 메시지를 표시해야 함', async ({ page }) => {
    // 페이지 하단으로 스크롤
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));

    // 이메일 입력 필드 찾기
    const emailInput = page.locator('input[type="email"]');
    await expect(emailInput).toBeVisible();

    // 고유한 이메일 주소 생성
    const timestamp = Date.now();
    const testEmail = `test${timestamp}@example.com`;

    // 이메일 입력
    await emailInput.fill(testEmail);

    // 구독 버튼 클릭
    const submitButton = page.getByRole('button', { name: /구독하기/ });
    await submitButton.click();

    // 성공 메시지 확인 (부분 매칭)
    await expect(page.getByText(/구독이 완료되었습니다/)).toBeVisible({ timeout: 10000 });
  });

  // 추가 테스트: 중복 이메일 처리
  test('중복 이메일 구독 시 적절한 메시지를 표시해야 함', async ({ page }) => {
    // 페이지 하단으로 스크롤
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));

    const emailInput = page.locator('input[type="email"]');
    const submitButton = page.getByRole('button', { name: /구독하기/ });

    const testEmail = 'duplicate@example.com';

    // 첫 번째 구독
    await emailInput.fill(testEmail);
    await submitButton.click();
    await page.waitForTimeout(1000);

    // 페이지 새로고침
    await page.reload();
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));

    // 같은 이메일로 다시 구독 시도
    await page.locator('input[type="email"]').fill(testEmail);
    await page.getByRole('button', { name: /구독하기/ }).click();

    // 중복 메시지 확인 (부분 매칭)
    await expect(page.getByText(/이미 구독하신 이메일입니다/)).toBeVisible({ timeout: 10000 });
  });
});
