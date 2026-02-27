# Discuss

Discuss는 Phoenix(버전 1.7.21) 기반의 Elixir **엄브렐라(umbrella)** 웹 애플리케이션입니다. PostgreSQL 데이터베이스를 사용하며, Tailwind와 esbuild로 프론트엔드 자산을 빌드합니다. 회원가입/로그인 인증, 마크다운 지원 토픽 관리, REST API를 포함합니다.

## 프로젝트 구조 (Umbrella)

```
discuss/
├── apps/
│   ├── discuss/          # 도메인 로직 + Ecto Repo
│   │   ├── lib/discuss/
│   │   │   ├── topics/   # Topic 컨텍스트 (게시글)
│   │   │   ├── admin/    # Admin User 컨텍스트
│   │   │   ├── markdown.ex  # 마크다운 → HTML 변환 헬퍼
│   │   │   ├── repo.ex
│   │   │   └── mailer.ex
│   │   └── priv/repo/migrations/
│   ├── discuss_auth/     # 인증 앱
│   │   └── lib/discuss_auth/
│   │       └── accounts/ # User, UserToken, Accounts 컨텍스트
│   └── discuss_web/      # 웹 계층 (Phoenix)
│       ├── lib/discuss_web/
│       │   ├── controllers/     # 토픽, 회원가입, 로그인, 관리자 컨트롤러
│       │   │   └── api/         # REST API 컨트롤러 (JSON)
│       │   ├── components/      # 레이아웃, CoreComponents
│       │   ├── auth/            # UserAuth Plug (세션 관리)
│       │   └── router.ex
│       └── assets/              # Tailwind, JS, 마크다운 에디터
├── config/               # 환경별 설정 파일
└── mix.exs               # 엄브렐라 루트
```

### 앱 의존성 방향

```
discuss_web → discuss_auth → discuss
```

- **discuss**: Ecto Repo, 도메인 스키마 (Topic, Admin.User), PubSub, Mailer, Markdown 헬퍼
- **discuss_auth**: 인증 로직 (회원가입, 로그인, 세션 토큰, 비밀번호 해싱)
- **discuss_web**: Phoenix Endpoint, 라우터, 컨트롤러, 템플릿, 인증 Plug, REST API

## 주요 기능

### 토픽 관리
- 토픽 CRUD (생성, 조회, 수정, 삭제)
- **마크다운 본문** 지원 (최대 50,000자)
- **분할 창 라이브 프리뷰 에디터** (좌: 마크다운 편집, 우: 실시간 미리보기)
- 서버 사이드 마크다운 렌더링 (Earmark) — 상세 페이지, API 응답
- 클라이언트 사이드 마크다운 렌더링 (marked + DOMPurify) — 편집기 실시간 프리뷰
- 제목 및 본문 검색, 페이지네이션
- 소프트 삭제 (삭제된 토픽은 목록에서 제외)
- 소유자만 수정/삭제 가능

### 인증
- **회원가입**: 이메일 + 비밀번호 (최소 8자)
- **로그인/로그아웃**: 세션 기반 토큰 인증
- **비밀번호 해싱**: Pbkdf2 (PBKDF2-SHA512)
- **세션 관리**: 60일 유효 토큰, 자동 만료
- **이메일 인증**: 확인 토큰 발송
- **비밀번호 재설정**: 토큰 기반 재설정 플로우

### 관리자 기능
- 관리자 사용자 관리 (`/admin/users`)
- 시드 파일로 초기 관리자 계정 생성

### REST API
- `GET /api/topics` — 토픽 목록 (페이지네이션, 검색)
- `GET /api/topics/:id` — 토픽 상세 (`body`, `body_html` 포함)
- `POST /api/topics` — 토픽 생성 (Bearer 토큰 인증 필요)
- `PUT /api/topics/:id` — 토픽 수정 (소유자만)
- `DELETE /api/topics/:id` — 토픽 삭제 (소유자만)

## 주요 의존성

| 패키지 | 용도 |
|--------|------|
| phoenix ~> 1.7.21 | 웹 프레임워크 (Bandit 어댑터) |
| ecto_sql ~> 3.12, postgrex | PostgreSQL 연동 |
| pbkdf2_elixir ~> 2.0 | 비밀번호 해싱 |
| earmark ~> 1.4 | 서버 사이드 마크다운 → HTML 변환 |
| tailwind, esbuild | 프론트엔드 빌드 |
| @tailwindcss/typography | 마크다운 콘텐츠 타이포그래피 스타일 |
| marked, dompurify | 클라이언트 사이드 마크다운 프리뷰 + XSS 방어 |
| swoosh, finch | 이메일 발송 |

## 개발 및 실행 방법

### 1. 의존성 설치 및 초기화

```bash
mix setup
# 또는 아래 명령어를 순차적으로 실행
mix deps.get
mix ecto.setup
```

### 2. 개발 서버 실행

```bash
mix phx.server
# 또는 IEx 셸 포함
iex -S mix phx.server
```

서버가 시작되면 http://localhost:4000 에서 접속할 수 있습니다.

### 3. 테스트 실행

```bash
mix test                                        # 전체 테스트
mix test apps/discuss/test/                     # 도메인 앱 테스트
mix test apps/discuss_web/test/                 # 웹 앱 테스트
mix test apps/discuss_auth/test/                # 인증 앱 테스트
```

### 4. 자산 빌드

```bash
mix assets.build    # 개발용 빌드 (CSS + JS)
mix assets.deploy   # 프로덕션용 빌드 (minify + digest)
```

### Makefile 단축 명령어

```bash
make all      # clean → deps.get → ecto.create → ecto.migrate → iex -S mix phx.server
make release  # Docker build + run
```

## 기본 계정 정보

개발 환경에서 회원가입 페이지(`/users/register`)에서 새 계정을 생성할 수 있습니다.

- **DB 사용자**: postgres / postgres (dev.exs 참고)

### 초기 관리자 계정

시드 파일(`mix run apps/discuss/priv/repo/seeds.exs`)을 실행하면 아래 관리자 계정이 생성됩니다.

| 항목 | 값 |
|------|-----|
| 이메일 | `admin@email.com` |
| 비밀번호 | `password!` |
| 역할 | `admin` |
| 관리자 페이지 | `/admin/users` |

## 배포(Release) 및 Docker 빌드

### 1. 환경 변수 설정

```bash
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export DATABASE_URL=ecto://{username}:{password}@{hostname}:{port}/{database-name}
```

### 2. 프로덕션 빌드

```bash
mix deps.get --only prod
MIX_ENV=prod mix compile
mix assets.deploy
mix phx.gen.release --docker
```

### 3. Docker 이미지 빌드 및 실행

```bash
docker build -t discuss:latest .
docker run -it \
  -e SECRET_KEY_BASE=$SECRET_KEY_BASE \
  -e DATABASE_URL=$DATABASE_URL \
  -p 4000:4000 \
  discuss:latest
```

## 개발 도구

- **대시보드**: http://localhost:4000/dev/dashboard (개발 환경 전용)
- **메일 미리보기**: http://localhost:4000/dev/mailbox (개발 환경 전용)
