# Playa Umbrella

Phoenix 1.8 기반의 Elixir 우산(Umbrella) 프로젝트로, 사용자 관리, JWT 인증, 역할 기반 접근 제어(RBAC), 생산성 도구를 제공하는 웹 애플리케이션입니다.

## 목차

- [프로젝트 구조](#프로젝트-구조)
- [주요 기능](#주요-기능)
- [기술 스택](#기술-스택)
- [데이터베이스 아키텍처](#데이터베이스-아키텍처)
- [시작하기](#시작하기)
- [환경 설정](#환경-설정)
- [개발 가이드](#개발-가이드)
- [API 엔드포인트](#api-엔드포인트)
- [테스트](#테스트)
- [프로덕션 배포](#프로덕션-배포)

## 프로젝트 구조

이 프로젝트는 4개의 독립적인 Elixir 앱으로 구성되어 있습니다:

### Dependency Diagram

```text
                   ┌──────────────┐
      ┌────────────┤     auth     ◄─────────────┐
      │            └──────────────┘             │
      │                                         │
      │                                         │
      │                                         │
      │                                         │
┌─────▼─────┐      ┌──────────────┐       ┌─────┴───────┐
│   playa   ◄──────┤ productivity ◄───────┤  playa_web  │
└───────────┘      └──────────────┘       └─────────────┘
```

### 각 앱의 역할

| 앱 | 포트 | 주요 책임 |
| --- | --- | --- |
| **playa** | - | 계정 관리 (사용자, 역할, 세션, 토큰) |
| **auth** | - | Guardian JWT 기반 인증 시스템 |
| **productivity** | - | 생산성 도구 (리스트, 아이템 관리) |
| **playa_web** | 4000 | Phoenix 웹 인터페이스, LiveView, API |

## 주요 기능

### 사용자 관리 (Playa.Accounts)

- ✅ 사용자 등록/로그인 (Bcrypt 해싱)
- ✅ 이메일 기반 계정 확인
- ✅ 비밀번호 재설정
- ✅ 세션 토큰 관리
- ✅ 사용자 프로필 수정

### 역할 기반 접근 제어 (RBAC)

- ✅ 역할 생성/수정/삭제
- ✅ 사용자-역할 할당
- ✅ 역할별 권한 관리
- ✅ Many-to-Many 관계 지원

### 인증 (Auth.Guardian)

- ✅ JWT 토큰 기반 인증
- ✅ Access Token (60초 TTL)
- ✅ Refresh Token (24시간 TTL)
- ✅ API 엔드포인트 인증

### 생산성 도구 (Productivity.Works)

- ✅ 리스트 생성/관리
- ✅ 아이템 생성/수정 (상태: todo/doing/done)
- ✅ 사용자별 리스트 소유권

### 웹 인터페이스 (PlayaWeb)

- ✅ Phoenix LiveView 실시간 UI
- ✅ 사용자 관리 대시보드
- ✅ 역할 관리 인터페이스
- ✅ 리스트/아이템 관리
- ✅ 반응형 디자인 (Tailwind CSS)

## 기술 스택

| 카테고리 | 기술 | 버전 |
| --- | --- | --- |
| **언어** | Elixir | ~1.19 |
| **프레임워크** | Phoenix | ~1.8 |
| **UI** | Phoenix LiveView | ~1.1 |
| **데이터베이스** | PostgreSQL + Ecto | 3.13 |
| **인증** | Guardian | ~2.3 |
| **비밀번호** | Bcrypt | ~3.0 |
| **스타일링** | Tailwind CSS | ~0.2 |
| **JS 번들링** | esbuild | ~0.8 |
| **이메일** | Swoosh | ~1.19 |
| **시간 처리** | Timex | ~3.7.11 |
| **테스트** | ExUnit + ExCoveralls | ~0.18 |

## 데이터베이스 아키텍처

PostgreSQL 단일 데이터베이스에 3개의 스키마를 사용합니다:

### 스키마 구조

| 스키마 | 용도 | 주요 테이블 |
| --- | --- | --- |
| `playa` | 사용자 및 역할 관리 | users, roles, roles_users, users_tokens |
| `auth` | Auth 앱 전용 | (현재 미사용) |
| `productivity` | 생산성 도구 | lists, items |

### 주요 테이블 관계

```text
playa.users ──┬── playa.users_tokens (토큰)
              ├── playa.roles_users ──── playa.roles
              ├── productivity.lists (리스트)
              └── productivity.items (아이템)

productivity.lists ──── productivity.items
```

### 스키마 생성 예시

새로운 자식 프로젝트를 위한 데이터베이스 스키마 생성:

```elixir
# 스키마 생성 마이그레이션
def up do
  execute "CREATE SCHEMA IF NOT EXISTS <schema_name>"
end

def down do
  execute "DROP SCHEMA IF EXISTS <schema_name>"
end
```

```elixir
# 테이블 생성 (특정 스키마에)
def change do
  create table(:<table_name>, prefix: :<schema_name>) do
    add :<column_name>, references(:lists, prefix: :productivity, on_delete: :nilify_all), null: true
    timestamps()
  end

  create index(:<table_name>, [:<column_name>], prefix: :<schema_name>)
end
```

```elixir
# 스키마 모듈에서 prefix 지정
@schema_prefix :<schema_name>
schema "<table_name>" do
  field :<column_name>, :<data_type>
end
```

## 시작하기

### 요구사항

- Elixir 1.19+
- Erlang/OTP 27+
- PostgreSQL 14+
- Node.js 18+ (프론트엔드 에셋용)

### 설치 및 실행

#### 1. 저장소 클론

```bash
git clone <repository-url>
cd playa_umbrella
```

#### 2. 환경 변수 설정

```bash
cp .env.example .env
# .env 파일을 편집하여 필요한 값 설정
direnv allow  # direnv 사용 시
```

#### 3. 개발 환경 초기화

```bash
# 방법 1: Makefile 사용 (권장)
make dev  # 의존성 설치 + DB 생성 + 마이그레이션 + 시딩 + 실행

# 방법 2: Mix 명령어
mix setup  # 모든 앱에서 setup 실행
mix phx.server
```

#### 4. 브라우저에서 접속

```text
http://localhost:4000
```

#### 5. 테스트 로그인

- 이메일: `ghost@email.com`
- 비밀번호: `qwe123QWE!@#`

## 환경 설정

`.env.example` 파일을 참고하여 `.env` 파일을 생성하세요.

### 필수 환경 변수

```bash
# 데이터베이스 설정
DATABASE_URL=ecto://postgres:postgres@localhost/playa_dev
POOL_SIZE=10
ECTO_IPV6=false

# Phoenix 설정
PHX_HOST=localhost
PORT=4000
SECRET_KEY_BASE=  # mix phx.gen.secret 실행하여 생성

# Guardian JWT 설정
GUARDIAN_SECRET_KEY=  # mix guardian.gen.secret 실행하여 생성

# 클러스터 설정 (선택사항)
DNS_CLUSTER_QUERY=
```

### 시크릿 키 생성

```bash
# Phoenix Secret Key 생성
mix phx.gen.secret

# Guardian Secret Key 생성
mix guardian.gen.secret
```

## 개발 가이드

### Makefile 명령어

| 명령어 | 설명 |
| --- | --- |
| `make dev` | 전체 개발 환경 초기화 및 실행 |
| `make clean` | 빌드 결과물 삭제 |
| `make create` | 의존성 설치, DB 생성 |
| `make migrate` | 모든 마이그레이션 실행 |
| `make seed` | 데이터 시딩 |
| `make format` | 코드 포매팅 |
| `make test` | 전체 테스트 실행 |
| `make run` | iex로 서버 실행 |
| `make pack` | 프로덕션 빌드 |

### 개별 앱 작업

```bash
# 특정 앱의 디렉토리로 이동
cd apps/playa

# 컴파일
mix compile

# 테스트
mix test

# 특정 레포 마이그레이션
mix ecto.migrate --repo Playa.Repo
```

### 전체 프로젝트 작업

```bash
# 루트 디렉토리에서
cd playa_umbrella

# 전체 컴파일
mix compile

# 전체 테스트
mix test

# 모든 레포 마이그레이션
mix ecto.migrate
```

### 데이터베이스 작업

```bash
# 데이터베이스 생성
mix ecto.create

# 마이그레이션 실행
mix ecto.migrate

# 마이그레이션 롤백
mix ecto.rollback --step 1

# 데이터베이스 재설정 (주의!)
mix ecto.reset
```

## API 엔드포인트

### 인증 API

| 메서드 | 경로 | 설명 | 인증 필요 |
| --- | --- | --- | --- |
| GET | `/api/health-check` | 헬스 체크 | ❌ |
| GET | `/api/get_token` | JWT 토큰 발급 (이메일/비밀번호) | ❌ |
| GET | `/api/me` | 현재 사용자 정보 조회 | ✅ |
| GET | `/api/delete` | 로그아웃 | ✅ |

### 웹 라우트

#### 공개 라우트

- `/` - 홈페이지
- `/components` - 컴포넌트 갤러리

#### 인증 라우트

- `/users/register` - 사용자 등록
- `/users/log_in` - 로그인
- `/users/reset_password` - 비밀번호 재설정
- `/users/reset_password/:token` - 비밀번호 재설정 토큰

#### 보호된 라우트 (로그인 필요)

- `/counter` - 카운터 데모
- `/users/settings` - 사용자 설정
- `/users/settings/confirm_email/:token` - 이메일 확인
- `/works/lists` - 리스트 관리
- `/works/lists/:id` - 리스트 상세
- `/accounts/roles` - 역할 관리
- `/accounts/users` - 사용자 관리

#### 개발 도구 (dev 환경만)

- `/dev/dashboard` - Phoenix LiveDashboard
- `/dev/mailbox` - Swoosh 이메일 미리보기

## 테스트

### 테스트 실행

```bash
# 전체 테스트 실행
mix test

# 특정 앱 테스트
cd apps/playa
mix test

# 특정 파일 테스트
mix test test/playa/accounts_test.exs

# 특정 라인 테스트
mix test test/playa/accounts_test.exs:42
```

### 테스트 커버리지

```bash
# 커버리지 리포트 생성
mix coveralls

# 상세 커버리지
mix coveralls.detail

# HTML 리포트 생성
mix coveralls.html
# 결과: cover/excoveralls.html
```

### 테스트 통계 (2024-02)

```text
총 79개 테스트, 0 실패
- playa: 32 tests
- auth: 15 tests
- productivity: 20 tests
- playa_web: 12 tests
```

## 프로덕션 배포

### Docker를 사용한 배포

#### 1. PostgreSQL 컨테이너 실행

```bash
docker-compose up -d
```

#### 2. 애플리케이션 빌드 및 실행

```bash
# 빌드
make pack

# Docker 이미지 생성
make ship

# 컨테이너 실행
make launch
```

### 릴리즈 빌드 (Mix Release)

```bash
cd playa_umbrella

# 환경 변수 로드
direnv allow

# 개발 환경 설정
make

# 프로덕션 릴리즈 생성
MIX_ENV=prod mix release

# 릴리즈 실행
_build/prod/rel/playa_umbrella/bin/playa_umbrella start

# 릴리즈 중지
_build/prod/rel/playa_umbrella/bin/playa_umbrella stop
```

### 프로덕션 환경 변수

프로덕션에서는 `config/runtime.exs`가 다음 환경 변수를 읽습니다:

- `DATABASE_URL` - PostgreSQL 연결 문자열
- `SECRET_KEY_BASE` - Phoenix 시크릿 키
- `GUARDIAN_SECRET_KEY` - Guardian JWT 시크릿
- `PHX_HOST` - 호스트명
- `PORT` - 포트 번호 (기본: 4000)
- `POOL_SIZE` - DB 연결 풀 크기 (기본: 10)

## 디렉토리 구조

```text
playa_umbrella/
├── apps/
│   ├── playa/                         # 계정 관리 앱
│   │   ├── lib/playa/
│   │   │   ├── accounts/              # 사용자, 역할, 세션
│   │   │   │   ├── users.ex
│   │   │   │   ├── roles.ex
│   │   │   │   ├── sessions.ex
│   │   │   │   └── role_assignments.ex
│   │   │   └── accounts.ex            # Public Context API
│   │   └── priv/repo/migrations/      # Playa 마이그레이션
│   │
│   ├── auth/                          # JWT 인증 앱
│   │   └── lib/auth/
│   │       └── guardian.ex            # Guardian 설정
│   │
│   ├── productivity/                  # 생산성 도구 앱
│   │   ├── lib/productivity/
│   │   │   └── works/                 # 리스트, 아이템
│   │   └── priv/repo/migrations/      # Productivity 마이그레이션
│   │
│   └── playa_web/                     # 웹 인터페이스 앱
│       ├── lib/playa_web/
│       │   ├── live/                  # LiveView 페이지
│       │   ├── controllers/           # 컨트롤러
│       │   ├── components/            # UI 컴포넌트
│       │   └── router.ex              # 라우팅
│       └── assets/                    # 프론트엔드 에셋
│
├── config/
│   ├── config.exs                     # 전역 설정
│   ├── dev.exs                        # 개발 환경
│   ├── prod.exs                       # 프로덕션 환경
│   ├── runtime.exs                    # 런타임 설정
│   └── test.exs                       # 테스트 환경
│
├── docker-compose.yml                 # Docker 설정
├── Dockerfile                         # Docker 이미지 빌드
├── Makefile                           # 개발 작업 자동화
├── mix.exs                            # 우산 프로젝트 설정
├── .env.example                       # 환경 변수 템플릿
└── README.md                          # 이 파일
```

## 문제 해결

### 데이터베이스 연결 오류

```bash
# PostgreSQL이 실행 중인지 확인
docker-compose ps

# 데이터베이스 재생성
mix ecto.drop
mix ecto.create
mix ecto.migrate
```

### 포트 충돌

```bash
# 다른 포트로 실행
PORT=4001 mix phx.server
```

### 의존성 문제

```bash
# 의존성 클린 재설치
mix deps.clean --all
mix deps.get
mix compile
```

## 참고 자료

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Ecto](https://hexdocs.pm/ecto/)
- [Guardian](https://hexdocs.pm/guardian/)
- [Containerizing a Phoenix 1.6 Umbrella Project](https://medium.com/@alistairisrael/containerizing-a-phoenix-1-6-umbrella-project-8ec03651a59c)
- [AsciiFlow](https://asciiflow.com/) - ASCII 다이어그램 생성 도구

## 라이센스

이 프로젝트는 학습 목적으로 작성되었습니다.

## 기여

이슈나 풀 리퀘스트를 환영합니다!
