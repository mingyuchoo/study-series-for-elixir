# Agentic AI Assistant

Elixir/Phoenix 기반의 **Web UI 전용** 에이전트 AI 플랫폼입니다.
Azure OpenAI API(gpt-5-mini)와 다중 에이전트(Supervisor + Worker) 오케스트레이션,
그리고 **MCP(Model Context Protocol)** 표준 도구 연동을 제공합니다.

## 주요 기능

- 회원가입/로그인 (email + password, bcrypt)
- 사용자별 대화 소유권 분리
- LiveView 기반 실시간 스트리밍 채팅
- 대화에 파일 첨부 (텍스트/PDF/이미지 등, workspace에 저장되어 에이전트가 분석 가능)
- 관리자 페이지
  - `/admin/agents` : 에이전트 CRUD
  - `/admin/mcps` : MCP 서버 CRUD (환경변수 상태 확인 포함)
  - `/admin/dashboard` : Phoenix LiveDashboard

## 기술 스택

- **언어**: Elixir 1.19 / OTP 28
- **웹 프레임워크**: Phoenix 1.8 + LiveView 1.1 + Bandit
- **데이터베이스**: SQLite3 (Ecto)
- **AI**: Azure OpenAI API (gpt-5-mini)
- **인증**: bcrypt_elixir
- **프로토콜**: MCP (Model Context Protocol)
- **프로젝트 구조**: Umbrella (`apps/core` + `apps/web`)

## 프로젝트 구조

```text
agentic_ai/
├── apps/
│   ├── core/                    # 도메인 로직
│   │   ├── lib/core/
│   │   │   ├── agent/           # ReAct 패턴 에이전트
│   │   │   ├── contexts/        # Accounts, Conversations, Agents, Mcps
│   │   │   ├── schema/          # User, UserToken, Conversation, Message, Mcp, Agent
│   │   │   ├── llm/             # Azure OpenAI 클라이언트
│   │   │   └── mcp/             # MCP 서버 구현
│   │   └── priv/repo/
│   │       ├── migrations/
│   │       └── seeds.exs
│   └── web/                     # Phoenix UI
│       └── lib/web_web/
│           ├── live/            # ChatLive, AgentLive, McpLive, UserLogin/Register/Settings
│           ├── controllers/     # UserSessionController, PageController
│           ├── user_auth.ex
│           └── router.ex
├── config/
│   ├── agents/                  # 초기 에이전트 시드 (마크다운)
│   └── *.exs
└── mix.exs                      # releases 설정
```

## 설치 및 실행

### 1. 환경 변수 (.env)

```bash
cp .env.example .env
```

`.env` 주요 항목:

| 변수 | 용도 |
|---|---|
| `AZURE_OPENAI_ENDPOINT` / `AZURE_OPENAI_API_KEY` | LLM |
| `FIRECRAWL_API_KEY` | Firecrawl MCP |
| `WORKSPACE_DIR` | 업로드/에이전트 작업 디렉토리 (선택, 개발은 `./workspace` 기본) |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | `seeds.exs`로 만들 초기 관리자 계정 |
| `DATABASE_PATH` / `SECRET_KEY_BASE` / `PHX_HOST` / `PORT` | 프로덕션 전용 |

### 2. 개발 환경 부팅

```bash
# 의존성
mix deps.get

# DB 생성 + 마이그레이션 + 시드(관리자 / 에이전트 / MCP)
mix ecto.setup

# 또는 개별 실행
# mix ecto.create && mix ecto.migrate && mix run apps/core/priv/repo/seeds.exs

# 개발 서버
./start.sh
```

브라우저에서 <http://localhost:4000> 접속 → `/users/register`로 계정 생성 후 `/chat` 이동.

### 3. 프로덕션 릴리스 빌드

```bash
# 에셋 빌드
MIX_ENV=prod mix assets.deploy

# 릴리스 빌드
MIX_ENV=prod mix release

# 실행 (환경변수 필수)
DATABASE_PATH=/var/lib/agentic_ai/agentic_ai.db \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  AZURE_OPENAI_ENDPOINT=https://... AZURE_OPENAI_API_KEY=... \
  PHX_HOST=your.domain PORT=4000 \
  WORKSPACE_DIR=/var/lib/agentic_ai/workspace \
  _build/prod/rel/agentic_ai/bin/agentic_ai start
```

출력물: `_build/prod/rel/agentic_ai/` 및 `*.tar.gz`.

## 라우트 요약

| 경로 | 설명 |
|---|---|
| `/` | 랜딩 페이지 (로그인 시 `/chat`으로 리다이렉트) |
| `/users/register`, `/users/log_in`, `/users/settings` | 계정 |
| `/chat`, `/chat/:id` | LiveView 채팅 (인증 필수) |
| `/admin/agents*` | 에이전트 관리 |
| `/admin/mcps*` | MCP 관리 |
| `/admin/dashboard` | LiveDashboard |
| `/api/health` | 헬스체크 |

## 에이전트 도구

| 도구 | 설명 |
|---|---|
| `get_current_time` | 현재 시간 (타임존 지원) |
| `calculate` | 수학 계산 |
| `search_web` | 웹 검색 (DuckDuckGo) |
| `read_file` / `write_file` / `list_directory` | 워크스페이스 파일 I/O |
| `execute_code` | Elixir 코드 실행 |

## MCP (Model Context Protocol)

외부 MCP 서버는 **DB 테이블(`mcps`)**에서 관리합니다. 최초 1회 `seeds.exs` 실행 시 `.mcp.json`에서 import됩니다.
이후 UI의 `/admin/mcps`에서 CRUD 가능하며, 환경변수 placeholder(`${VAR}`)의 설정 여부로 상태를 표시합니다.

### 내장 MCP 서버 (STDIO)

```bash
mix run --no-halt -e "Core.MCP.Transport.Stdio.start()"
```

지원 메서드: `initialize`, `tools/{list,call}`, `prompts/{list,get}`, `resources/{list,read}`.

## 개발

```bash
iex -S mix phx.server   # IEx + 서버
mix test                # 테스트
mix compile --warnings-as-errors
```

## ReAct 패턴

1. **Reasoning** — LLM이 상황 분석 및 다음 행동 결정
2. **Acting** — 도구 호출
3. **Observation** — 도구 결과 관찰
4. 목표 달성까지 반복

## 라이선스

MIT

---

Made with 💥 by 붐돌이
