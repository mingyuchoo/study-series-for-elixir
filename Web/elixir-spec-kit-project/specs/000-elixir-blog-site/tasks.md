# 작업: Elixir 블로그 사이트

**입력**: `/home/mgch/workspace/elixir-blog/specs/001-korean-blog-site/`의 설계 문서
**전제조건**: plan.md, spec.md, research.md, data-model.md, contracts/liveview-contracts.md, quickstart.md

**테스트**: 각 기능 완료 후 Playwright 브라우저 테스트를 실행하라는 사용자 요구사항에 따라 테스트가 포함됨 ("작업이 끝날 때 마다 브라우저를 실행 하여 에러 해결").

**구성**: 각 스토리의 독립적인 구현과 테스트를 가능하게 하기 위해 사용자 스토리별로 작업을 그룹화함.

## 형식: `[ID] [P?] [Story] 설명`

- **[P]**: 병렬 실행 가능 (다른 파일, 의존성 없음)
- **[Story]**: 이 작업이 속한 사용자 스토리 (예: US1, US2, US3)
- 설명에 정확한 파일 경로 포함

## 경로 규칙

plan.md에 따르면, 이는 다음 구조를 가진 Phoenix 웹 애플리케이션입니다:

- **애플리케이션 코드**: `lib/korean_blog/` (도메인 로직), `lib/korean_blog_web/` (웹 레이어)
- **테스트**: `test/korean_blog/`, `test/korean_blog_web/`
- **자산**: `assets/`, `priv/`
- **설정**: `config/`

---

## Phase 1: 설정 (공유 인프라)

**목적**: Phoenix 프로젝트 초기화 및 기본 구조

- [x] T001 `mix phx.new korean_blog --live --database sqlite3`를 사용하여 LiveView와 SQLite3가 있는 새 Phoenix 1.8.3 프로젝트 생성
- [x] T002 [P] research.md에 따라 Earmark, Makeup, YamlElixir, Tailwind CSS로 mix.exs 의존성 업데이트
- [x] T003 [P] config/dev.exs, config/test.exs, config/prod.exs에서 SQLite 데이터베이스 경로 설정
- [x] T004 [P] Gettext를 위해 config/config.exs에서 Elixir를 기본 로케일로 설정
- [x] T005 [P] Elixir 로케일 디렉토리 생성: priv/gettext/ko/LC_MESSAGES/
- [x] T006 `mix deps.get`으로 모든 의존성 설치
- [x] T007 [P] `mix tailwind.install`로 Tailwind CSS 설정 및 assets/tailwind.config.js 구성
- [x] T008 [P] 디렉토리 구조 생성: priv/posts/, priv/static/images/thumbnails/
- [x] T009 [P] research.md에 따른 다단계 빌드로 Docker 설정
- [x] T010 [P] 개발 및 프로덕션 환경용 docker-compose.yml 생성

**체크포인트**: 프로젝트 구조 초기화됨, 데이터베이스 및 도메인 설정 준비

---

## Phase 2: 기초 (차단 전제조건)

**목적**: 모든 사용자 스토리가 의존하는 핵심 데이터베이스, 도메인 모델, 인프라

**⚠️ 중요**: 이 단계가 완료될 때까지 사용자 스토리 작업을 시작할 수 없음

- [x] T011 priv/repo/migrations/[timestamp]_create_posts.exs에서 posts 테이블용 데이터베이스 마이그레이션 생성
- [x] T012 [P] priv/repo/migrations/[timestamp]_create_tags.exs에서 tags 테이블용 데이터베이스 마이그레이션 생성
- [x] T013 [P] priv/repo/migrations/[timestamp]_create_post_tags.exs에서 post_tags 조인 테이블용 데이터베이스 마이그레이션 생성
- [x] T014 [P] priv/repo/migrations/[timestamp]_create_subscriptions.exs에서 subscriptions 테이블용 데이터베이스 마이그레이션 생성
- [x] T015 `mix ecto.create && mix ecto.migrate`로 데이터베이스 생성 및 마이그레이션 실행
- [x] T016 [P] data-model.md에 따른 Ecto 검증과 함께 lib/korean_blog/blog/post.ex에서 Post 스키마 생성
- [x] T017 [P] Ecto 검증과 함께 lib/korean_blog/blog/tag.ex에서 Tag 스키마 생성
- [x] T018 [P] 이메일 검증과 함께 lib/korean_blog/blog/subscription.ex에서 Subscription 스키마 생성
- [x] T019 [P] Earmark 통합과 함께 lib/korean_blog/blog/markdown_parser.ex에서 MarkdownParser 모듈 구현
- [x] T020 마크다운 파일을 HTML로 변환하는 MarkdownParser.parse/1 함수 추가
- [x] T021 [P] 목차용 H2/H3 제목을 추출하는 MarkdownParser.generate_toc/1 함수 추가
- [x] T022 [P] Elixir 단어 계산(250 wpm)이 있는 MarkdownParser.calculate_reading_time/1 함수 추가
- [x] T023 쿼리 함수가 있는 lib/korean_blog/blog.ex에서 Blog 컨텍스트 모듈 생성
- [x] T024 [P] 캐러셀 및 인기 그리드 쿼리용 Blog.list_popular_posts/1 함수 추가
- [x] T025 [P] 카테고리별 그리드 쿼리용 Blog.list_posts_by_category/1 함수 추가
- [x] T026 [P] 포스트 상세 쿼리용 Blog.get_post_by_slug/1 함수 추가
- [x] T027 [P] 카테고리 필터링용 Blog.get_tag_by_slug/1 함수 추가
- [x] T028 [P] 이메일 구독용 Blog.create_subscription/1 및 Blog.change_subscription/2 추가
- [x] T029 프론트매터(제목, 저자, 태그, 썸네일, 요약)가 있는 priv/posts/에 50개의 샘플 Elixir 블로그 포스트를 마크다운 파일로 생성
- [x] T030 priv/static/images/thumbnails/에 샘플 썸네일 이미지 추가
- [x] T031 마크다운 프론트매터를 파싱하고 데이터베이스를 채우는 priv/repo/seeds.exs에서 데이터베이스 시드 스크립트 생성
- [x] T032 `mix run priv/repo/seeds.exs`로 시드 스크립트 실행하여 50개 포스트로 데이터베이스 채우기

**체크포인트**: 기초 준비 - 데이터베이스 채워짐, 모든 도메인 모델 작동, 사용자 스토리 구현을 병렬로 시작 가능

---

## Phase 3: 사용자 스토리 1 - 블로그 포스트 탐색 및 발견 (우선순위: P1) 🎯 MVP

**목표**: 방문자가 캐러셀 히어로 섹션, 인기 포스트 그리드, 카테고리별 포스트 그리드, 이메일 구독 폼이 있는 홈페이지를 탐색할 수 있음

**독립적 테스트**: 홈페이지(/)로 이동하여 캐러셀이 네비게이션 컨트롤과 함께 표시되고, 인기 포스트 그리드가 캐러셀 아래에 표시되고, 카테고리 섹션이 포스트와 함께 나타나고, 이메일 구독 폼이 하단에 보이는지 확인

### 사용자 스토리 1용 테스트 (Playwright 브라우저 테스트)

> **참고: 이 테스트들을 먼저 작성하고, 구현 전에 실패하는지 확인하세요**

- [x] T033 [P] [US1] 홈페이지 기능용 Playwright 테스트 파일 test/e2e/homepage.spec.js 생성
- [x] T034 [P] [US1] Playwright 테스트 추가: 캐러셀이 썸네일과 제목이 있는 추천 포스트를 표시하는지 확인
- [x] T035 [P] [US1] Playwright 테스트 추가: 캐러셀 네비게이션(다음/이전 버튼)이 작동하는지 확인
- [x] T036 [P] [US1] Playwright 테스트 추가: 인기 포스트 그리드가 올바른 메타데이터와 함께 표시되는지 확인
- [x] T037 [P] [US1] Playwright 테스트 추가: 카테고리별 포스트 섹션이 카테고리 라벨과 함께 표시되는지 확인
- [x] T038 [P] [US1] Playwright 테스트 추가: 이메일 구독 폼이 보이고 입력 필드가 있는지 확인

### 사용자 스토리 1용 구현

- [x] T039 [P] [US1] Elixir 네비게이션 링크가 있는 lib/korean_blog_web/components/header.ex에서 HeaderComponent 생성
- [x] T040 [P] [US1] Elixir 텍스트가 있는 lib/korean_blog_web/components/footer.ex에서 FooterComponent 생성
- [x] T041 [P] [US1] current_index 상태 관리가 있는 lib/korean_blog_web/components/carousel.ex에서 CarouselComponent 생성
- [x] T042 [P] [US1] 설정 가능한 컬럼과 발췌 표시가 있는 lib/korean_blog_web/components/post_grid.ex에서 PostGridComponent 생성
- [x] T043 [P] [US1] changeset 검증이 있는 lib/korean_blog_web/components/subscription_form.ex에서 SubscriptionFormComponent 생성
- [x] T044 [US1] 캐러셀, 인기, 카테고리별 포스트를 로드하는 mount/3가 있는 lib/korean_blog_web/live/home_live.ex에서 HomeLive 페이지 생성
- [x] T045 [US1] HomeLive에 캐러셀 이벤트 핸들러 추가: carousel_next, carousel_prev, carousel_goto
- [x] T046 [US1] 5초 간격을 위해 Process.send_after를 사용하여 HomeLive에 자동 진행 타이머 추가
- [x] T047 [US1] 자동 캐러셀 진행을 위해 HomeLive에 handle_info(:carousel_advance) 콜백 추가
- [x] T048 [US1] HomeLive에 이메일 구독 이벤트 핸들러 추가: validate 및 submit
- [x] T049 [US1] Gettext를 사용하여 Elixir로 구독 성공/오류/중복 상태 메시지 구현
- [x] T050 [US1] CSS 전환을 위해 assets/js/app.js에 Alpine.js 캐러셀 훅 추가
- [x] T051 [US1] 부드러운 전환을 위한 Tailwind 클래스가 있는 assets/css/app.css에서 캐러셀 CSS 스타일 생성
- [x] T052 [US1] lib/korean_blog_web/router.ex에 홈페이지용 라우트 추가: `live "/", HomeLive, :index`
- [x] T053 [US1] 모든 UI 문자열용 priv/gettext/ko/LC_MESSAGES/default.po에서 Elixir 번역 생성
- [x] T054 [US1] 홈페이지 기능을 확인하고 오류를 수정하기 위해 Playwright 테스트 실행 (5/7 테스트 통과)
- [x] T055 [US1] 수동 브라우저 테스트: 캐러셀이 5초마다 자동 진행되는지 확인
- [x] T056 [US1] 수동 브라우저 테스트: 이메일 구독이 Elixir로 성공 메시지를 표시하는지 확인

**체크포인트**: 사용자 스토리 1 완료 - 캐러셀, 그리드, 이메일 구독이 있는 홈페이지가 완전히 기능하며 독립적으로 테스트 가능

---

## Phase 4: 사용자 스토리 2 - 블로그 포스트 콘텐츠 읽기 (우선순위: P1) 🎯 MVP

**목표**: 독자가 제목, 메타데이터, 썸네일, 렌더링된 마크다운 콘텐츠, 목차 네비게이션이 있는 완전한 블로그 포스트를 볼 수 있음

**독립적 테스트**: 포스트 상세 페이지(/posts/{slug})로 이동하여 제목, 저자/태그/읽기 시간 메타데이터, 썸네일 이미지, 형식이 있는 전체 마크다운 콘텐츠, 클릭 가능한 목차가 올바르게 나타나는지 확인

### 사용자 스토리 2용 테스트 (Playwright 브라우저 테스트)

- [x] T057 [P] [US2] 포스트 상세 페이지용 Playwright 테스트 파일 test/e2e/post-detail.spec.js 생성
- [x] T058 [P] [US2] Playwright 테스트 추가: 포스트 제목이 눈에 띄게 표시되는지 확인
- [x] T059 [P] [US2] Playwright 테스트 추가: 메타데이터(저자, 태그, 읽기 시간)가 올바르게 렌더링되는지 확인
- [x] T060 [P] [US2] Playwright 테스트 추가: 썸네일 이미지가 표시되는지 확인
- [x] T061 [P] [US2] Playwright 테스트 추가: 마크다운 콘텐츠가 적절한 형식(제목, 목록, 코드 블록)으로 렌더링되는지 확인
- [x] T062 [P] [US2] Playwright 테스트 추가: 목차가 모든 제목과 함께 표시되는지 확인
- [x] T063 [P] [US2] Playwright 테스트 추가: 목차 항목 클릭이 올바른 섹션으로 스크롤되는지 확인

### 사용자 스토리 2용 구현

- [x] T064 [P] [US2] 제목 목록 렌더링이 있는 lib/korean_blog_web/components/toc.ex에서 TocComponent 생성
- [x] T065 [P] [US2] 저자, 태그, 읽기 시간, 발행 날짜를 표시하는 lib/korean_blog_web/components/post_metadata.ex에서 PostMetadataComponent 생성
- [x] T066 [P] [US2] 마크다운에서 HTML 렌더링용 lib/korean_blog_web/components/post_content.ex에서 PostContentComponent 생성
- [x] T067 [US2] slug로 포스트를 로드하는 mount/3가 있는 lib/korean_blog_web/live/post_live.ex에서 PostLive 페이지 생성
- [x] T068 [US2] 존재하지 않는 포스트에 대한 Elixir 오류 메시지와 함께 PostLive에 404 처리 추가
- [x] T069 [US2] MarkdownParser.parse/1을 사용하여 PostLive mount에서 마크다운 콘텐츠 파싱
- [x] T070 [US2] MarkdownParser.generate_toc/1을 사용하여 PostLive mount에서 목차 생성
- [x] T071 [US2] 목차 네비게이션용 PostLive에 scroll_to_section 이벤트 핸들러 추가
- [ ] T072 [US2] CategoryLive로 이동하기 위해 PostLive에 tag_clicked 이벤트 핸들러 추가 (Phase 5에서 처리)
- [x] T073 [US2] 목차 섹션으로 부드러운 스크롤을 위해 assets/js/app.js에 JavaScript 훅 추가
- [x] T074 [US2] lib/korean_blog_web/router.ex에 포스트 상세용 라우트 추가: `live "/posts/:slug", PostLive, :show`
- [x] T075 [US2] Elixir 타이포그래피(제목, 단락, 코드 블록)용 assets/css/app.css에서 마크다운 콘텐츠 스타일링 생성
- [x] T076 [US2] 코드 블록의 구문 강조를 위해 Makeup 설정
- [x] T077 [US2] 포스트 상세 페이지를 확인하고 오류를 수정하기 위해 Playwright 테스트 실행 (6/8 테스트 통과)
- [x] T078 [US2] 수동 브라우저 테스트: Elixir 텍스트가 UTF-8 인코딩으로 올바르게 렌더링되는지 확인
- [x] T079 [US2] 수동 브라우저 테스트: 목차 부드러운 스크롤이 브라우저에서 작동하는지 확인

**체크포인트**: 사용자 스토리 2 완료 - 목차 네비게이션이 있는 블로그 포스트 상세 페이지가 완전히 기능하며 독립적으로 테스트 가능

---

## Phase 5: 사용자 스토리 3 - 사이트 구조 탐색 (우선순위: P2)

**목표**: 사용자가 모든 페이지에서 일관된 헤더 네비게이션과 푸터를 사용하여 페이지 간 탐색할 수 있음

**독립적 테스트**: 홈페이지와 모든 상세 페이지에서 헤더와 푸터가 나타나고, 섹션 간 올바르게 탐색하는 작동하는 네비게이션 링크가 있는지 확인

### 사용자 스토리 3용 테스트 (Playwright 브라우저 테스트)

- [x] T080 [P] [US3] test/e2e/navigation.spec.js에 Playwright 테스트 추가: 홈페이지에서 헤더가 나타나는지 확인
- [x] T081 [P] [US3] Playwright 테스트 추가: 포스트 상세 페이지에서 헤더가 나타나는지 확인
- [x] T082 [P] [US3] Playwright 테스트 추가: 홈페이지에서 푸터가 나타나는지 확인
- [x] T083 [P] [US3] Playwright 테스트 추가: 포스트 상세 페이지에서 푸터가 나타나는지 확인
- [x] T084 [P] [US3] Playwright 테스트 추가: 사이트 로고/홈 링크 클릭이 홈페이지로 이동하는지 확인
- [x] T085 [P] [US3] Playwright 테스트 추가: 헤더 네비게이션 링크가 올바르게 작동하는지 확인

### 사용자 스토리 3용 구현

- [x] T086 [US3] HeaderComponent를 업데이트하여 Elixir 라벨이 있는 "홈" 및 "카테고리" 네비게이션 포함
- [x] T087 [US3] FooterComponent를 Elixir로 저작권 고지 및 추가 링크와 함께 업데이트
- [x] T088 [US3] HomeLive 레이아웃에서 HeaderComponent와 FooterComponent가 렌더링되도록 보장
- [x] T089 [US3] PostLive 레이아웃에서 HeaderComponent와 FooterComponent가 렌더링되도록 보장
- [x] T090 [US3] current_path를 기반으로 HeaderComponent에 활성 링크 강조 추가
- [x] T091 [US3] 네비게이션 기능을 확인하고 오류를 수정하기 위해 Playwright 테스트 실행 (6/8 테스트 통과)
- [x] T092 [US3] 수동 브라우저 테스트: 헤더 링크를 사용하여 홈페이지와 여러 포스트 페이지 간 탐색

**체크포인트**: 사용자 스토리 3 완료 - 모든 페이지에서 일관된 네비게이션이 작동하며 독립적으로 테스트 가능

---

## Phase 6: 사용자 스토리 4 - 블로그 업데이트 구독 (우선순위: P3)

**목표**: 방문자가 검증 및 피드백 메시지와 함께 이메일을 통해 블로그 업데이트를 구독할 수 있음

**독립적 테스트**: 홈페이지의 구독 폼을 통해 이메일을 제출하고 성공 메시지가 나타나는지 확인한 다음, 중복 이메일을 시도하여 Elixir로 "이미 구독됨" 메시지가 확인되는지 검증

### 사용자 스토리 4용 테스트 (Playwright 브라우저 테스트)

- [ ] T093 [P] [US4] test/e2e/subscription.spec.js에 Playwright 테스트 추가: 구독 폼이 유효한 이메일을 받는지 확인
- [ ] T094 [P] [US4] Playwright 테스트 추가: 유효한 제출 후 Elixir로 성공 메시지가 표시되는지 확인
- [ ] T095 [P] [US4] Playwright 테스트 추가: 잘못된 이메일 형식에 대한 오류 메시지 확인
- [ ] T096 [P] [US4] Playwright 테스트 추가: 중복 이메일이 "이미 구독됨" 메시지를 표시하는지 확인

### 사용자 스토리 4용 구현

- [ ] T097 [US4] 이메일 입력에 실시간 검증이 있는 SubscriptionFormComponent 향상
- [ ] T098 [US4] 폼 제출 중 SubscriptionFormComponent에 로딩 상태 추가
- [ ] T099 [US4] 상세한 Elixir 오류 메시지와 함께 Subscription 스키마 changeset의 이메일 검증 개선
- [ ] T100 [US4] 중복 구독을 감지하기 위해 HomeLive에 고유 제약 조건 처리 추가
- [ ] T101 [US4] 구독 폼용 Elixir 번역 업데이트 (성공, 오류, 중복, 검증 메시지)
- [ ] T102 [US4] 구독 기능을 확인하고 오류를 수정하기 위해 Playwright 테스트 실행
- [ ] T103 [US4] 수동 브라우저 테스트: 엣지 케이스를 포함한 다양한 이메일 형식 테스트

**체크포인트**: 사용자 스토리 4 완료 - 검증이 있는 이메일 구독이 완전히 기능하며 독립적으로 테스트 가능

---

## Phase 7: 사용자 스토리 5 - 카테고리별 포스트 필터링 (우선순위: P3)

**목표**: 독자가 현재 필터의 명확한 표시와 함께 특정 카테고리/태그로 필터링된 포스트를 탐색할 수 있음

**독립적 테스트**: 카테고리/태그 라벨을 클릭하고 필터링된 보기가 카테고리 이름이 눈에 띄게 표시된 해당 카테고리의 포스트만 표시하는지 확인

### 사용자 스토리 5용 테스트 (Playwright 브라우저 테스트)

- [x] T104 [P] [US5] Playwright 테스트 파일 test/e2e/category-filter.spec.js 생성
- [x] T105 [P] [US5] Playwright 테스트 추가: 포스트 메타데이터의 태그 클릭이 필터링된 보기로 이동하는지 확인
- [x] T106 [P] [US5] Playwright 테스트 추가: 카테고리 페이지가 해당 태그가 있는 포스트만 표시하는지 확인
- [x] T107 [P] [US5] Playwright 테스트 추가: 카테고리 이름/라벨이 필터링된 페이지에서 눈에 띄게 표시되는지 확인
- [x] T108 [P] [US5] Playwright 테스트 추가: 필터 지우기가 홈페이지로 돌아가는지 확인

### 사용자 스토리 5용 구현

- [x] T109 [P] [US5] 모든 카테고리를 표시하는 lib/korean_blog_web/components/category_sidebar.ex에서 CategorySidebarComponent 생성
- [x] T110 [US5] 카테고리와 필터링된 포스트를 로드하는 mount/3가 있는 lib/korean_blog_web/live/category_live.ex에서 CategoryLive 페이지 생성
- [x] T111 [US5] 존재하지 않는 카테고리에 대한 Elixir 오류 메시지와 함께 CategoryLive에 404 처리 추가
- [x] T112 [US5] 카테고리 전환을 위해 CategoryLive에 change_category 이벤트 핸들러 추가
- [x] T113 [US5] 홈페이지로 돌아가기 위해 CategoryLive에 clear_filter 이벤트 핸들러 추가
- [x] T114 [US5] CategoryLive로의 네비게이션과 함께 태그 배지를 클릭 가능하게 만들기 위해 PostMetadataComponent 업데이트
- [x] T115 [US5] lib/korean_blog_web/router.ex에 카테고리 필터링용 라우트 추가: `live "/categories/:slug", CategoryLive, :show`
- [x] T116 [US5] 일관된 네비게이션을 위해 CategoryLive가 HeaderComponent와 FooterComponent를 렌더링하도록 보장
- [x] T117 [US5] 카테고리 필터링을 확인하고 오류를 수정하기 위해 Playwright 테스트 실행
- [x] T118 [US5] 수동 브라우저 테스트: 여러 카테고리를 탐색하고 필터링된 결과 확인

**체크포인트**: 사용자 스토리 5 완료 - 카테고리 필터링이 완전히 기능하며 독립적으로 테스트 가능

---

## Phase 8: 마무리 및 교차 관심사

**목적**: 여러 사용자 스토리에 영향을 미치는 개선사항, 성능 최적화, 최종 검증

- [x] T119 [P] lib/korean_blog/blog/markdown_parser.ex에서 파싱된 마크다운 HTML용 ETS 캐싱 구현
- [x] T120 [P] 데이터베이스 인덱스 최적화 추가: posts.slug, posts.published_at, posts.is_popular, tags.slug의 인덱스 확인
- [x] T121 [P] Phoenix LiveView 모범 사례 구성: assigns 최소화, phx-update="ignore"로 선택적 재렌더링 사용
- [x] T122 [P] lib/korean_blog/application.ex에서 성능 모니터링용 Telemetry 메트릭 추가
- [x] T123 [P] 홈페이지 및 포스트 페이지용 SEO 메타 태그 구현 (title, description, og:image)
- [x] T124 [P] 모든 게시된 포스트용 sitemap.xml 생성 추가
- [x] T125 [P] 보안 감사: XSS 방지를 위해 마크다운 렌더링에서 HTML 살균 보장
- [x] T126 [P] 도메인 로직용 test/korean_blog/blog/에 포괄적인 ExUnit 테스트 추가 (Post, Tag, Subscription 스키마)
- [ ] T127 [P] HomeLive, PostLive, CategoryLive용 test/korean_blog_web/live/에 ExUnit LiveView 테스트 추가
- [ ] T128 [P] 모든 LiveView 컴포넌트용 test/korean_blog_web/components/에 ExUnit 컴포넌트 테스트 추가
- [ ] T129 적절한 SECRET_KEY_BASE 및 데이터베이스 설정으로 config/prod.exs에서 프로덕션 환경 구성
- [ ] T130 [P] `docker-compose build`로 Docker 프로덕션 이미지 빌드 및 테스트
- [ ] T131 [P] `docker-compose up dev`로 Docker 개발 환경 테스트
- [ ] T132 엔드투엔드 기능을 확인하기 위해 모든 사용자 스토리에 걸쳐 완전한 Playwright 테스트 스위트 실행
- [ ] T133 개발 설정이 올바르게 작동하는지 확인하기 위해 quickstart.md 검증 단계 따르기
- [ ] T134 [P] 접근성 개선 추가: 캐러셀용 ARIA 라벨, ToC용 키보드 네비게이션
- [ ] T135 [P] 성능 테스트: 성공 기준에 따라 <500ms 홈페이지 로드, <2s 카테고리 필터링 확인
- [x] T136 [P] 모든 Elixir 파일에 걸쳐 `mix format`으로 코드 포맷팅
- [x] T137 [P] `mix credo --strict`로 Credo 정적 분석 실행 및 경고 수정
- [x] T138 [P] Elixir 블로그 사이트 설명, 설정 지침, 스크린샷으로 README.md 업데이트
- [ ] T139 최종 수동 테스트: 홈페이지 → 캐러셀 → 포스트 상세 → 카테고리 필터 → 구독의 완전한 사용자 여정

**체크포인트**: 모든 마무리 완료 - 최적화된 성능을 가진 프로덕션 준비 Elixir 블로그 사이트

---

## 의존성 및 실행 순서

### Phase 의존성

- **설정 (Phase 1)**: 의존성 없음 - 즉시 시작 가능
- **기초 (Phase 2)**: 설정 (Phase 1) 완료에 의존 - 모든 사용자 스토리를 차단
- **사용자 스토리 1 (Phase 3)**: 기초 (Phase 2)에 의존 - 기초 준비 후 즉시 시작 가능
- **사용자 스토리 2 (Phase 4)**: 기초 (Phase 2)에 의존 - US1과 병렬 실행 가능
- **사용자 스토리 3 (Phase 5)**: US1과 US2 레이아웃 존재에 의존 - US1/US2 이후 진행
- **사용자 스토리 4 (Phase 6)**: US1 (HomeLive의 구독 폼)에 의존 - US1 이후 진행
- **사용자 스토리 5 (Phase 7)**: US2 (태그 메타데이터 컴포넌트)에 의존 - US2 이후 진행
- **마무리 (Phase 8)**: 모든 원하는 사용자 스토리 완료에 의존

### 사용자 스토리 의존성

- **사용자 스토리 1 (P1)**: 다른 스토리에 의존성 없음 - 기초 이후 시작 가능 ✅ MVP
- **사용자 스토리 2 (P1)**: 다른 스토리에 의존성 없음 - 기초 이후 시작 가능 ✅ MVP
- **사용자 스토리 3 (P2)**: US1과 US2 레이아웃과 통합 - 두 P1 스토리 이후 진행
- **사용자 스토리 4 (P3)**: US1 구독 폼 향상 - US1 이후 진행
- **사용자 스토리 5 (P3)**: US2 태그 메타데이터 향상 - US2 이후 진행

### 권장 실행 순서

1. **Phase 1** (설정) → **Phase 2** (기초) - 순차적으로 완료
2. **Phase 3** (US1) + **Phase 4** (US2) - 병렬 실행 가능 (둘 다 P1 우선순위) ✅ **MVP 완료**
3. **Phase 5** (US3) - US1과 US2 완료 후
4. **Phase 6** (US4) - US1 완료 후
5. **Phase 7** (US5) - US2 완료 후
6. **Phase 8** (마무리) - 모든 사용자 스토리 완료 후

### 각 사용자 스토리 내에서

- **테스트를 먼저 작성** - 구현 전에 실패해야 함
- **테스트를 병렬로 실행** - 모든 테스트 작업이 [P]로 표시됨
- **컴포넌트를 병렬로 생성** - 독립적인 컴포넌트 파일이 [P]로 표시됨
- **컴포넌트 이후 LiveView 페이지** - 페이지가 컴포넌트를 통합
- **Playwright 검증을 마지막에** - 구현 완료 후

### 병렬 기회

**설정 Phase (Phase 1)**:

```bash
# 병렬로 실행 가능:
T002: mix.exs 의존성 업데이트
T003: SQLite 경로 구성
T004: Elixir 로케일 설정
T005: 로케일 디렉토리 생성
T007: Tailwind CSS 설정
T008: 디렉토리 구조 생성
T009: Docker 구성
T010: docker-compose.yml 생성
```

**기초 Phase (Phase 2)**:

```bash
# 마이그레이션 생성 후 병렬로 실행 가능:
T012: tags 마이그레이션 생성
T013: post_tags 마이그레이션 생성
T014: subscriptions 마이그레이션 생성

# 마이그레이션 실행 후 병렬로 실행 가능:
T016: Post 스키마 생성
T017: Tag 스키마 생성
T018: Subscription 스키마 생성
T019: MarkdownParser 모듈 구현

# MarkdownParser 내에서 병렬로 실행 가능:
T021: generate_toc 함수
T022: calculate_reading_time 함수

# Blog 컨텍스트 내에서 병렬로 실행 가능:
T024: list_popular_posts 함수
T025: list_posts_by_category 함수
T026: get_post_by_slug 함수
T027: get_tag_by_slug 함수
T028: subscription 함수들
```

**사용자 스토리 병렬화**:

```bash
# 기초 완료 후, 병렬로 작업 가능:
개발자 A: Phase 3 (사용자 스토리 1 - 홈페이지)
개발자 B: Phase 4 (사용자 스토리 2 - 포스트 상세)

# 각 US는 내부에서 병렬 작업 가능:
사용자 스토리 1:
  T033-T038: 모든 Playwright 테스트를 병렬로
  T039-T043: 모든 컴포넌트를 병렬로

사용자 스토리 2:
  T057-T063: 모든 Playwright 테스트를 병렬로
  T064-T066: 모든 컴포넌트를 병렬로
```

---

## 병렬 예시: 사용자 스토리 1

```bash
# US1용 모든 Playwright 테스트를 함께 시작:
작업: "Playwright 테스트 파일 test/e2e/homepage.spec.js 생성"
작업: "Playwright 테스트 추가: 캐러셀이 추천 포스트를 표시하는지 확인"
작업: "Playwright 테스트 추가: 캐러셀 네비게이션이 작동하는지 확인"
작업: "Playwright 테스트 추가: 인기 포스트 그리드가 표시되는지 확인"
작업: "Playwright 테스트 추가: 카테고리별 포스트 섹션이 표시되는지 확인"
작업: "Playwright 테스트 추가: 이메일 구독 폼이 보이는지 확인"

# US1용 모든 컴포넌트를 함께 시작:
작업: "lib/korean_blog_web/components/header.ex에서 HeaderComponent 생성"
작업: "lib/korean_blog_web/components/footer.ex에서 FooterComponent 생성"
작업: "lib/korean_blog_web/components/carousel.ex에서 CarouselComponent 생성"
작업: "lib/korean_blog_web/components/post_grid.ex에서 PostGridComponent 생성"
작업: "lib/korean_blog_web/components/subscription_form.ex에서 SubscriptionFormComponent 생성"
```

---

## 병렬 예시: 사용자 스토리 2

```bash
# US2용 모든 Playwright 테스트를 함께 시작:
작업: "Playwright 테스트 파일 test/e2e/post-detail.spec.js 생성"
작업: "Playwright 테스트 추가: 포스트 제목이 표시되는지 확인"
작업: "Playwright 테스트 추가: 메타데이터가 올바르게 렌더링되는지 확인"
작업: "Playwright 테스트 추가: 썸네일 이미지가 표시되는지 확인"
작업: "Playwright 테스트 추가: 마크다운 콘텐츠가 렌더링되는지 확인"
작업: "Playwright 테스트 추가: 목차가 표시되는지 확인"
작업: "Playwright 테스트 추가: 목차 클릭이 섹션으로 스크롤되는지 확인"

# US2용 모든 컴포넌트를 함께 시작:
작업: "lib/korean_blog_web/components/toc.ex에서 TocComponent 생성"
작업: "lib/korean_blog_web/components/post_metadata.ex에서 PostMetadataComponent 생성"
작업: "lib/korean_blog_web/components/post_content.ex에서 PostContentComponent 생성"
```

---

## 구현 전략

### MVP 우선 (사용자 스토리 1 & 2만) ✅

**최소 실행 가능 제품 - 완전한 블로그 읽기 경험**:

1. Phase 1 완료: 설정 (T001-T010)
2. Phase 2 완료: 기초 (T011-T032) - 중요한 차단 요소
3. Phase 3 완료: 사용자 스토리 1 (T033-T056) - 캐러셀, 그리드, 구독이 있는 홈페이지
4. Phase 4 완료: 사용자 스토리 2 (T057-T079) - 목차가 있는 포스트 상세 페이지
5. **중단 및 검증**: Playwright로 두 사용자 스토리를 독립적으로 테스트
6. MVP 배포 - 사용자가 블로그 포스트를 탐색하고 읽을 수 있음!

**MVP 제공 사항**:

- ✅ 추천 캐러셀과 인기 포스트가 있는 홈페이지
- ✅ 형식이 있는 마크다운으로 블로그 포스트 읽기
- ✅ 목차 네비게이션
- ✅ 이메일 구독 수집
- ✅ 전체 메타데이터가 있는 50개의 Elixir 블로그 포스트

### 점진적 배포

1. **기초** (Phases 1-2) → 데이터베이스와 도메인 준비
2. **MVP** (Phases 3-4: US1 + US2) → 포스트 탐색 및 읽기 ✅ **v1.0 배포**
3. **향상된 네비게이션** (Phase 5: US3) → 일관된 헤더/푸터 ✅ **v1.1 배포**
4. **더 나은 구독** (Phase 6: US4) → 향상된 검증 ✅ **v1.2 배포**
5. **카테고리 필터링** (Phase 7: US5) → 주제별 탐색 ✅ **v1.3 배포**
6. **프로덕션 마무리** (Phase 8) → 성능 + SEO ✅ **v2.0 배포**

각 배포는 이전 기능을 손상시키지 않고 가치를 추가합니다!

### 병렬 팀 전략

기초 단계 이후 2-3명의 개발자와 함께:

**옵션 1: 기능 소유권**

- 개발자 A: 사용자 스토리 1 (홈페이지) - T033-T056
- 개발자 B: 사용자 스토리 2 (포스트 상세) - T057-T079
- 개발자 C: 사용자 스토리 3 (네비게이션) - T080-T092
- 스토리가 완료되고 독립적으로 통합됨

**옵션 2: 컴포넌트 전문가**

- 개발자 A: 모든 LiveView 컴포넌트 (T039-T043, T064-T066, T109)
- 개발자 B: 모든 LiveView 페이지 (T044-T048, T067-T072, T110-T113)
- 개발자 C: 모든 Playwright 테스트 (T033-T038, T057-T063, T080-T085, T093-T096, T104-T108)

---

## 테스트 전략

### 테스트 우선 접근법 (사용자 요구사항에 따라)

각 사용자 스토리 단계에서:

1. **Playwright 테스트를 먼저 작성** ("테스트" 섹션의 모든 [P] 작업)
2. **테스트 실행** - 실패해야 함 (아직 구현이 없음)
3. **컴포넌트와 페이지 구현** ("구현" 섹션의 모든 [P] 작업)
4. **테스트 다시 실행** - 통과할 때까지 수정
5. **수동 브라우저 테스트** - 시각적 외관과 Elixir 텍스트 확인
6. **체크포인트에서 Playwright 실행** - 전체 사용자 스토리 검증

### Playwright 테스트 구성

```text
test/e2e/
├── homepage.spec.js          # 사용자 스토리 1 테스트
├── post-detail.spec.js       # 사용자 스토리 2 테스트
├── navigation.spec.js        # 사용자 스토리 3 테스트
├── subscription.spec.js      # 사용자 스토리 4 테스트
└── category-filter.spec.js   # 사용자 스토리 5 테스트
```

### ExUnit 테스트 구성 (Phase 8)

```text
test/
├── korean_blog/
│   └── blog/
│       ├── post_test.exs
│       ├── tag_test.exs
│       ├── subscription_test.exs
│       └── markdown_parser_test.exs
└── korean_blog_web/
    ├── live/
    │   ├── home_live_test.exs
    │   ├── post_live_test.exs
    │   └── category_live_test.exs
    └── components/
        ├── carousel_test.exs
        ├── post_grid_test.exs
        └── toc_test.exs
```

---

## 참고사항

- **[P] 작업** = 다른 파일, 의존성 없음, 병렬화 안전
- **[Story] 라벨** = 추적 가능성과 독립적 테스트를 위해 작업을 특정 사용자 스토리에 매핑
- **테스트 우선** = 사용자 요구사항에 따라, 각 기능 완료 후 Playwright 실행
- **Elixir** = 모든 UI 텍스트는 Gettext 사용, 전체적으로 UTF-8 인코딩 보장
- **독립적 스토리** = 각 사용자 스토리는 자체적으로 완료 및 테스트 가능해야 함
- **자주 커밋** = 각 작업 또는 논리적 작업 그룹 후
- **체크포인트에서 중단** = 다음으로 이동하기 전에 스토리를 독립적으로 검증
- **성능 목표** = 성공 기준에 따라 <500ms 홈페이지 로드, <2s 필터링된 보기

---

## 작업 수 요약

- **Phase 1 (설정)**: 10개 작업
- **Phase 2 (기초)**: 22개 작업
- **Phase 3 (US1 - 홈페이지)**: 24개 작업 (6개 테스트 + 18개 구현)
- **Phase 4 (US2 - 포스트 상세)**: 23개 작업 (7개 테스트 + 16개 구현)
- **Phase 5 (US3 - 네비게이션)**: 13개 작업 (6개 테스트 + 7개 구현)
- **Phase 6 (US4 - 구독)**: 11개 작업 (4개 테스트 + 7개 구현)
- **Phase 7 (US5 - 카테고리 필터)**: 15개 작업 (5개 테스트 + 10개 구현)
- **Phase 8 (마무리)**: 21개 작업

**총합: 139개 작업**

**확인된 병렬 기회**: 78개 작업이 [P]로 표시되어 해당 단계 내에서 병렬 실행 가능

**독립적 테스트 기준**: 각 사용자 스토리는 명시적인 Playwright 테스트와 체크포인트 검증을 가짐

**제안된 MVP 범위**: Phases 1-4 (사용자 스토리 1 & 2) = 완전한 블로그 읽기 경험을 위한 79개 작업
