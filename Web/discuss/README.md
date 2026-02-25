# Discuss

Discuss는 Phoenix(버전 1.7.21) 기반의 Elixir **엄브렐라(umbrella)** 웹 애플리케이션입니다. PostgreSQL 데이터베이스를 사용하며, Tailwind와 esbuild로 프론트엔드 자산을 빌드합니다. 회원가입/로그인 인증 기능을 포함합니다.

## 프로젝트 구조 (Umbrella)

```
discuss/
├── apps/
│   ├── discuss/          # 도메인 로직 + Ecto Repo
│   │   ├── lib/discuss/
│   │   │   ├── topics/   # Topic 컨텍스트 (게시글)
│   │   │   ├── admin/    # Admin User 컨텍스트
│   │   │   ├── repo.ex
│   │   │   └── mailer.ex
│   │   └── priv/repo/migrations/
│   ├── discuss_auth/     # 인증 앱
│   │   └── lib/discuss_auth/
│   │       └── accounts/ # User, UserToken, Accounts 컨텍스트
│   └── discuss_web/      # 웹 계층 (Phoenix)
│       ├── lib/discuss_web/
│       │   ├── controllers/  # 토픽, 회원가입, 로그인 컨트롤러
│       │   ├── components/   # 레이아웃, CoreComponents
│       │   ├── auth/         # UserAuth Plug (세션 관리)
│       │   └── router.ex
│       └── assets/           # Tailwind, JS
├── config/               # 환경별 설정 파일
└── mix.exs               # 엄브렐라 루트
```

### 앱 의존성 방향

```
discuss_web → discuss_auth → discuss
```

- **discuss**: Ecto Repo, 도메인 스키마 (Topic, Admin.User), PubSub, Mailer
- **discuss_auth**: 인증 로직 (회원가입, 로그인, 세션 토큰, 비밀번호 해싱)
- **discuss_web**: Phoenix Endpoint, 라우터, 컨트롤러, 템플릿, 인증 Plug

## 주요 의존성

- phoenix ~> 1.7.21 (Bandit 어댑터)
- phoenix_ecto, ecto_sql ~> 3.12, postgrex (PostgreSQL 연동)
- pbkdf2_elixir ~> 2.0 (비밀번호 해싱)
- tailwind, esbuild (프론트엔드 빌드)
- swoosh, finch, telemetry, gettext 등

## 인증 기능

- **회원가입**: 이메일 + 비밀번호 (최소 8자)
- **로그인/로그아웃**: 세션 기반 토큰 인증
- **비밀번호 해싱**: Pbkdf2 (PBKDF2-SHA512)
- **세션 관리**: 60일 유효 토큰, 자동 만료
- **인증된 사용자만 토픽 CRUD 가능**

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
```

서버가 시작되면 http://localhost:4000 에서 접속할 수 있습니다.

### 3. 테스트 실행

```bash
mix test
```

## 기본 계정 정보

개발 환경에서 회원가입 페이지(`/users/register`)에서 새 계정을 생성할 수 있습니다.

- **DB 사용자**: postgres / postgres (dev.exs 참고)

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

## 기타 참고 사항

- 자산 빌드: `mix assets.deploy`
- 데이터베이스 마이그레이션/시드: `mix ecto.migrate`, `mix run apps/discuss/priv/repo/seeds.exs`
- 자세한 설정은 `mix.exs` 및 `config/` 디렉토리 참고
