# 엄브렐라 구조 전환 + 인증 시스템 설계

## 날짜: 2026-02-25

## 개요

기존 단일(flat) Phoenix 프로젝트를 3개 앱으로 구성된 엄브렐라 구조로 전환하고,
`phx.gen.auth` 기반 회원가입/로그인 기능을 추가한다.

## 결정 사항

- **접근 방식**: 새 엄브렐라 프로젝트 생성 후 기존 코드 이전 (방식 A)
- **인증 방식**: `phx.gen.auth` (bcrypt, 세션 토큰)
- **앱 분리**: 3개 앱 (discuss, discuss_auth, discuss_web)
- **User 모델**: 인증 User와 Admin.User를 분리 유지, FK로 연결

## 엄브렐라 구조

```
discuss/                          # 엄브렐라 루트
├── mix.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   ├── runtime.exs
│   └── test.exs
└── apps/
    ├── discuss/                   # 비즈니스 도메인
    │   ├── mix.exs
    │   ├── lib/discuss/
    │   │   ├── application.ex     # Repo 슈퍼바이저
    │   │   ├── repo.ex
    │   │   ├── mailer.ex
    │   │   ├── topics.ex          # Topics 컨텍스트
    │   │   ├── topics/topic.ex    # Topic 스키마
    │   │   ├── admin.ex           # Admin 컨텍스트
    │   │   └── admin/user.ex      # Admin User 스키마 (프로필)
    │   ├── priv/repo/migrations/
    │   └── test/
    │
    ├── discuss_auth/              # 인증 전용
    │   ├── mix.exs
    │   ├── lib/discuss_auth/
    │   │   ├── accounts.ex        # Accounts 컨텍스트
    │   │   └── accounts/
    │   │       ├── user.ex        # 인증 User (email, hashed_password)
    │   │       └── user_token.ex  # 세션/리셋 토큰
    │   ├── priv/repo/migrations/
    │   └── test/
    │
    └── discuss_web/               # Phoenix 웹 계층
        ├── mix.exs
        ├── lib/discuss_web/
        │   ├── endpoint.ex
        │   ├── router.ex
        │   ├── telemetry.ex
        │   ├── controllers/
        │   ├── components/
        │   └── auth/              # 인증 plug
        ├── assets/
        ├── priv/static/
        └── test/
```

## 앱 간 의존성

```
discuss_web → discuss_auth → discuss
```

- `discuss`: Repo, 도메인 스키마, 비즈니스 로직 (최하위, 의존성 없음)
- `discuss_auth`: 인증 컨텍스트 (discuss의 Repo를 공유)
- `discuss_web`: 웹 계층 (discuss, discuss_auth 모두 참조)

## 인증 시스템

### 인증 User (DiscussAuth.Accounts.User)

phx.gen.auth가 생성하는 표준 구조:
- `email` (unique, 필수)
- `hashed_password` (bcrypt via `bcrypt_elixir`)
- `confirmed_at` (이메일 인증)

### 프로필 User (Discuss.Admin.User)

기존 스키마에 `auth_user_id` FK 추가:
- `name`, `email`, `role`, `address` (기존 필드)
- `auth_user_id` (FK → DiscussAuth accounts_users 테이블)

### Topics 연결

- `topics` 테이블에 `auth_user_id` FK 추가
- 토픽 작성 시 현재 로그인 사용자 자동 연결

## 라우팅

### 공개 경로 (비로그인 접근 가능)
- `GET /` - 홈 페이지
- `GET/POST /users/register` - 회원가입
- `GET/POST /users/log_in` - 로그인
- `GET/POST /users/reset_password` - 비밀번호 재설정

### 보호 경로 (로그인 필수)
- `DELETE /users/log_out` - 로그아웃
- `GET/PUT /users/settings` - 계정 설정
- `/topics/*` - 토픽 CRUD 전체

## 마이그레이션 전략

1. 기존 `create_topics`, `create_users` 마이그레이션을 `apps/discuss/priv/repo/migrations/`로 이전
2. `phx.gen.auth` 마이그레이션을 `apps/discuss_auth/priv/repo/migrations/`에 생성
   (단, 같은 Repo를 공유하므로 실제로는 `apps/discuss/priv/repo/migrations/`에 통합)
3. 추가 마이그레이션:
   - `alter topics add auth_user_id`
   - `alter users add auth_user_id`
