# 구현 계획: Elixir 블로그 사이트

**브랜치**: `001-korean-blog-site` | **날짜**: 2025-12-29 | **명세서**: [spec.md](spec.md)
**입력**: `/home/mgch/workspace/elixir-blog/specs/001-korean-blog-site/spec.md`의 기능 명세서

**참고**: 이 템플릿은 `/speckit.plan` 명령어로 작성됩니다. 실행 워크플로우는 `.specify/templates/commands/plan.md`를 참조하세요.

## 요약

캐러셀 히어로 섹션, 카테고리별 그리드, 목차 네비게이션이 있는 상세 포스트 페이지를 특징으로 하는 동적 홈페이지를 통해 방문자가 블로그 포스트를 발견하고 읽을 수 있도록 하는 Phoenix LiveView를 사용한 Elixir 블로그 사이트 구축. 시스템은 완전한 메타데이터 지원, 이메일 구독 기능, 포괄적인 Elixir UI와 함께 마크다운 파일로 저장된 50개의 샘플 블로그 포스트를 관리합니다. Elixir 1.19와 Phoenix Framework 1.8.3, 실시간 상호작용을 위한 LiveView, 데이터 지속성을 위한 SQLite, 배포를 위한 Docker를 사용합니다.

## 기술적 맥락

**언어/버전**: Elixir 1.19
**주요 의존성**: Phoenix Framework 1.8.3, Phoenix LiveView, Earmark (마크다운 파서)
**저장소**: SQLite (블로그 포스트 메타데이터, 이메일 구독), 마크다운 파일 (블로그 포스트 콘텐츠)
**테스팅**: ExUnit (Elixir 내장 테스팅 프레임워크), Playwright MCP (브라우저 기반 UI 테스팅)
**대상 플랫폼**: 웹 애플리케이션 (Linux/Docker 컨테이너)
**프로젝트 유형**: 웹 애플리케이션 (Phoenix LiveView - 실시간 업데이트가 있는 서버 렌더링)
**성능 목표**: 명확화 필요: 동시 사용자 목표, 페이지 로드 시간 요구사항
**제약사항**: 필터링된 뷰 <2초 (SC-007 기준), 캐러셀 전환은 부드러워야 함, 목차 네비게이션 <5초 (SC-002 기준)
**규모/범위**: 50개의 초기 블로그 포스트, 단일 사이트 배포, UTF-8 인코딩을 사용한 Elixir 콘텐츠

## 헌법 검사

*게이트: Phase 0 연구 전에 통과해야 함. Phase 1 설계 후 재검사.*

**상태**: 통과 (헌법 정의되지 않음 - 프로젝트 템플릿 기본값 사용)

프로젝트에는 확립된 헌법 파일이 없습니다 (`.specify/memory/constitution.md`에는 템플릿 플레이스홀더만 포함). 시행할 아키텍처 원칙, 테스팅 요구사항, 복잡성 게이트가 정의되지 않았습니다. 이 구현은 표준 Phoenix/Elixir 모범 사례로 진행됩니다:

- LiveView를 사용한 표준 Phoenix 애플리케이션 구조
- 백엔드 테스팅을 위한 ExUnit, UI 테스팅을 위한 Playwright
- 해당하는 경우 RESTful 규칙
- 단일 웹 애플리케이션 (마이크로서비스 복잡성 없음)

**Phase 1 후 재평가**: 통과 - 설계 완료

Phase 1 설계(데이터 모델, 계약, 퀵스타트) 완료 후, 아키텍처는 표준 Phoenix 모범 사례와 일치합니다:

- ✅ 표준 Phoenix 웹 애플리케이션 구조 (위반 없음)
- ✅ 웹 레이어에서 분리된 도메인 로직 (lib/korean_blog vs lib/korean_blog_web)
- ✅ 적절한 검증과 관계를 가진 Ecto 스키마
- ✅ 복잡한 JavaScript 없이 실시간 상호작용을 위한 LiveView
- ✅ 콘텐츠 관리를 위해 정당화된 하이브리드 저장소 (SQLite + 마크다운 파일)
- ✅ 재사용성을 위한 컴포넌트 기반 아키텍처
- ✅ 포괄적인 테스팅을 위한 ExUnit과 Playwright

헌법 위반이 확인되지 않았습니다. 아키텍처는 프로덕션 준비가 되어 있고 유지보수 가능합니다.

## 프로젝트 구조

### 문서 (이 기능)

```text
specs/001-korean-blog-site/
├── spec.md              # 기능 명세서 (/speckit.specify로 생성)
├── plan.md              # 이 파일 (/speckit.plan 명령어 출력)
├── research.md          # Phase 0 출력 (/speckit.plan 명령어)
├── data-model.md        # Phase 1 출력 (/speckit.plan 명령어)
├── quickstart.md        # Phase 1 출력 (/speckit.plan 명령어)
├── contracts/           # Phase 1 출력 (/speckit.plan 명령어)
├── checklists/          # 품질 검증 체크리스트
│   └── requirements.md  # 명세서 품질 체크리스트
└── tasks.md             # Phase 2 출력 (/speckit.tasks 명령어 - /speckit.plan으로 생성되지 않음)
```

### 소스 코드 (저장소 루트)

```text
korean_blog/                    # Phoenix 애플리케이션 루트
├── config/
│   ├── config.exs             # 애플리케이션 설정
│   ├── dev.exs                # 개발 환경 설정
│   ├── prod.exs               # 프로덕션 환경 설정
│   └── test.exs               # 테스트 환경 설정
├── lib/
│   ├── korean_blog/           # 핵심 애플리케이션 로직
│   │   ├── blog/              # 블로그 도메인 컨텍스트
│   │   │   ├── post.ex        # 블로그 포스트 스키마 & 쿼리
│   │   │   ├── tag.ex         # 태그 스키마 & 쿼리
│   │   │   ├── subscription.ex # 이메일 구독 스키마
│   │   │   └── markdown_parser.ex # 마크다운 처리 유틸리티
│   │   ├── repo.ex            # Ecto 저장소 (SQLite)
│   │   └── application.ex     # 애플리케이션 슈퍼바이저
│   └── korean_blog_web/       # 웹 인터페이스
│       ├── components/        # 재사용 가능한 LiveView 컴포넌트
│       │   ├── header.ex      # 헤더 네비게이션 컴포넌트
│       │   ├── footer.ex      # 푸터 컴포넌트
│       │   ├── carousel.ex    # 캐러셀 히어로 컴포넌트
│       │   ├── post_grid.ex   # 포스트 그리드 컴포넌트
│       │   └── toc.ex         # 목차 컴포넌트
│       ├── live/              # LiveView 페이지
│       │   ├── home_live.ex   # 캐러셀 & 그리드가 있는 홈페이지
│       │   ├── post_live.ex   # 블로그 포스트 상세 페이지
│       │   └── category_live.ex # 카테고리 필터링된 뷰
│       ├── controllers/       # 전통적인 컨트롤러 (필요한 경우)
│       ├── router.ex          # 라우트 정의
│       ├── endpoint.ex        # Phoenix 엔드포인트
│       └── gettext.ex         # Elixir i18n 지원
├── test/
│   ├── korean_blog/           # 도메인 로직 테스트
│   │   └── blog/
│   │       ├── post_test.exs
│   │       ├── tag_test.exs
│   │       └── markdown_parser_test.exs
│   ├── korean_blog_web/       # 웹 레이어 테스트
│   │   ├── live/
│   │   │   ├── home_live_test.exs
│   │   │   └── post_live_test.exs
│   │   └── components/
│   │       └── carousel_test.exs
│   └── support/               # 테스트 헬퍼
├── priv/
│   ├── repo/
│   │   ├── migrations/        # 데이터베이스 마이그레이션
│   │   └── seeds.exs          # 샘플 데이터 시딩
│   ├── posts/                 # 마크다운 블로그 포스트 파일
│   │   ├── 2024-01-01-post-slug.md
│   │   └── [49개 더 많은 포스트]
│   ├── static/                # 정적 자산
│   │   ├── images/            # 포스트 썸네일
│   │   └── css/
│   └── gettext/               # Elixir 번역
│       └── ko/
│           └── LC_MESSAGES/
├── assets/                    # 프론트엔드 자산 (사전 컴파일)
│   ├── css/
│   │   └── app.css           # Tailwind CSS (LiveView에 권장)
│   └── js/
│       └── app.js            # 캐러셀 상호작용을 위한 Alpine.js
├── Dockerfile                 # Docker 컨테이너 설정
├── docker-compose.yml         # Docker Compose 설정
├── mix.exs                    # Elixir 프로젝트 & 의존성
└── mix.lock                   # 의존성 잠금 파일
```

**구조 결정**: 이는 LiveView를 사용하는 서버 렌더링 웹 애플리케이션이므로 Phoenix 웹 애플리케이션 구조를 선택했습니다. 표준 Phoenix 레이아웃은 도메인 로직(`lib/korean_blog/`)을 웹 관심사(`lib/korean_blog_web/`)에서 분리하며, 상호작용 UI 요소를 위한 LiveView 컴포넌트를 포함합니다. 블로그 포스트 콘텐츠는 효율적인 쿼리와 필터링을 위해 SQLite에 저장된 메타데이터와 함께 `priv/posts/`의 마크다운 파일로 저장됩니다.

## 복잡성 추적

> **헌법 검사에서 정당화되어야 하는 위반이 있는 경우에만 작성**

복잡성 위반이 확인되지 않았습니다. 구현은 추가적인 아키텍처 복잡성 없이 표준 Phoenix 애플리케이션 패턴을 따릅니다.
