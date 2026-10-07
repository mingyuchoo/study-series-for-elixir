# Agentic AI Assistant

Elixir/Phoenix 기반의 **Web UI 전용** 에이전트 AI 플랫폼입니다.
Azure OpenAI API(gpt-5-mini)와 다중 에이전트(Supervisor + Worker) 오케스트레이션,
그리고 **MCP(Model Context Protocol)** 표준 도구 연동을 제공합니다.

## 주요 기능

- 회원가입/로그인 (email + password, bcrypt)
- 사용자별 대화 소유권 분리
- LiveView 기반 실시간 스트리밍 채팅
- 대화에 파일 첨부 (텍스트/PDF/이미지 등, workspace에 저장되어 에이전트가 분석 가능)
- 사용자별 지식 문서 업로드/검색 (`/knowledge`)
- 관리자 페이지
  - `/admin/agents` : 에이전트 CRUD
  - `/admin/mcps` : MCP 서버 CRUD (환경변수 상태 확인 포함)
  - `/knowledge` : 본인 지식 문서 관리
  - `/admin/dashboard/home` : 운영 대시보드
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
multi_ai_assistants/
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
│           ├── live/            # ChatLive, AgentLive, McpLive, RagLive, User 계정 LiveView
│           ├── controllers/     # UserSessionController, PageController
│           ├── user_auth.ex
│           └── router.ex
├── config/
│   ├── agents/                  # 초기 에이전트 시드 (마크다운)
│   └── *.exs
└── mix.exs                      # releases 설정
```

## 설치 및 실행

### 1. 설정

애플리케이션은 `.env` 파일 없이도 기본 설정으로 부팅됩니다. `scripts/run.sh`는 프로젝트 루트에 `.env`가 있으면 이를 로드합니다. 직접 `mix`를 실행하거나 배포할 때는 OS 환경변수, 배포 시스템 secret, systemd `EnvironmentFile` 등 런타임 환경으로 주입하세요.

`.env.example`은 참고용 템플릿입니다. 로컬 실행용 설정은 `.env`에 저장하세요.

주요 설정 항목:

| 변수 | 용도 |
|---|---|
| `AZURE_OPENAI_ENDPOINT` / `AZURE_OPENAI_API_KEY` | LLM. 미설정 시 앱은 부팅되지만 AI 채팅 호출은 실패 |
| `AZURE_OPENAI_API_VERSION` | Azure OpenAI API 버전. 미설정 시 `2024-12-01-preview` |
| `AZURE_OPENAI_DEPLOYMENT` | Azure 배포 이름. 미설정 시 `gpt-5-mini` |
| `AZURE_OPENAI_EMBEDDING_DEPLOYMENT` | 선택. 설정 시 실제 임베딩과 HNSW 검색, 미설정 시 키워드 검색 |
| `MAX_MODEL_CALLS_PER_RUN` / `MAX_TOOL_CALLS_PER_RUN` / `MAX_TOKENS_PER_RUN` | 실행별 예산. 기본값 18 / 24 / 60000 |
| `FIRECRAWL_API_KEY` | Firecrawl MCP |
| `CONTEXT7_API_KEY` | Context7 MCP |
| `MCP_FILESYSTEM_ROOT` | Filesystem MCP 허용 루트 디렉터리 |
| `WORKSPACE_DIR` | 업로드/에이전트 작업 디렉토리. 미설정 시 `./workspace` |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | `seeds.exs`로 만들 초기 관리자 계정. 미설정 시 개발용 기본값 |
| `ADMIN_EMAILS` | 관리자 UI 허용 목록(쉼표 구분). 시드 계정도 여기에 별도로 등록해야 함 |
| `DATABASE_PATH` | 프로덕션 DB 경로. 미설정 시 릴리스 루트의 `multi_ai_assistants.db` |
| `SECRET_KEY_BASE` | 프로덕션 필수 secret. `mix phx.gen.secret`로 생성 |
| `PHX_HOST` / `PORT` | 프로덕션 웹 서버 설정. 미설정 시 `localhost` / `4000` |

### 2. 개발 환경 부팅

```bash
# 의존성
mix deps.get

# DB 생성 + 마이그레이션 + 시드(관리자 / 에이전트 / MCP)
mix ecto.setup

# 또는 개별 실행
# mix ecto.create && mix ecto.migrate && mix run apps/core/priv/repo/seeds.exs

# 개발 서버 (macOS / Linux)
./scripts/run.sh

# 개발 서버 (Windows / PowerShell)
./scripts/run.ps1
```

브라우저에서 <http://localhost:4000> 접속 → `/users/register`로 계정 생성 후 `/chat` 이동.

AI 채팅을 사용하려면 실행 전에 Azure OpenAI 환경변수를 설정하세요.

```bash
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com"
export AZURE_OPENAI_API_KEY="your-api-key"
export AZURE_OPENAI_DEPLOYMENT="your-deployment-name"
```

### 3. 프로덕션 릴리스 빌드

```bash
# 에셋 빌드
MIX_ENV=prod mix assets.deploy

# 릴리스 빌드
MIX_ENV=prod mix release --overwrite

# 실행
DATABASE_PATH=/var/lib/multi_ai_assistants/multi_ai_assistants.db \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  AZURE_OPENAI_ENDPOINT=https://... AZURE_OPENAI_API_KEY=... \
  AZURE_OPENAI_DEPLOYMENT=... \
  PHX_HOST=your.domain PORT=4000 \
  WORKSPACE_DIR=/var/lib/multi_ai_assistants/workspace \
  _build/prod/rel/multi_ai_assistants/bin/multi_ai_assistants start
```

출력물: `_build/prod/rel/multi_ai_assistants/` 및 `*.tar.gz`.

패키지 산출물이 필요하면 호스트 OS에 맞춰 스크립트를 사용할 수 있습니다.

```bash
./scripts/release.sh linux
./scripts/release.sh macos
```

## 라우트 요약

| 경로 | 설명 |
|---|---|
| `/` | 랜딩 페이지 (로그인 시 `/chat`으로 리다이렉트) |
| `/users/register`, `/users/log_in`, `/users/settings` | 계정 |
| `/chat`, `/chat/:id` | LiveView 채팅 (인증 필수) |
| `/admin/agents*` | 에이전트 관리 |
| `/admin/mcps*` | MCP 관리 |
| `/knowledge` | 본인 지식 문서 관리 |
| `/admin/dashboard/home` | 운영 대시보드 |
| `/admin/dashboard` | LiveDashboard |
| `/api/health` | 헬스체크 |

## 에이전트 도구

| 도구 | 설명 |
|---|---|
| `get_current_time` | 현재 시간 (타임존 지원) |
| `calculate` | 수학 계산 |
| `search_web` | 웹 검색 (DuckDuckGo) |
| `firecrawl_scrape` / `firecrawl_search` | Firecrawl 기반 스크래핑/검색 |
| `read_file` / `list_directory` | 현재 사용자 워크스페이스의 파일 조회 |
| `write_file` | 승인 흐름이 구현될 때까지 비활성화 |
| `search_vector_rag` | 업로드된 Vector RAG 문서 검색 |
| `execute_code` | 안전한 격리 실행 환경이 제공될 때까지 비활성화 |
| `mcp_filesystem_call` / `mcp_desktop_commander_call` | 승인 흐름이 구현될 때까지 비활성화 |

## 실행 및 데이터 경계

- 사용자 프로필, 에이전트 메모리, 지식 문서, 첨부 파일은 사용자별로 분리됩니다. 파일 도구는 `WORKSPACE_DIR/users/<user_id>` 아래 상대 경로만 읽으며 상위 디렉터리 이동과 심볼릭 링크를 거부합니다. 과거 공용 Markdown 메모리는 대화 실행 때 자동으로 읽거나 쓰지 않습니다.
- 관리자 UI는 `ADMIN_EMAILS`에 등록된 사용자만 접근할 수 있습니다. 기존 전역 Vector RAG 문서에는 소유자 정보가 없으므로 새 검색에서 제외됩니다. 소유자가 자신의 문서를 다시 업로드해야 합니다.
- 그룹 채팅은 `agent_runs`에 라운드별 체크포인트와 사용량을 기록합니다. 중단 후 5분이 지난 실행은 채팅 화면에서 재개하거나 취소할 수 있습니다. 실행 중인 작업은 아직 영속 작업 큐에서 자동 재시작되지 않습니다.
- 라우터가 첫 워커를 고르고, 모더레이터는 독립적인 2~3개 워커 작업을 병렬로 배정할 수 있습니다. 병렬 배정은 모더레이터 판단에 따릅니다.
- 지식 문서에 임베딩 배포를 설정하면 Azure 임베딩과 HNSW 검색을 키워드 검색과 결합합니다. 설정하지 않으면 키워드 검색을 사용합니다. 각 검색 결과에는 원본 파일명이 포함됩니다.
- MCP 클라이언트는 2026-07-28 `server/discover`를 우선 시도하고 이전 `initialize` 방식으로 돌아갑니다. 서버도 두 요청 방식을 지원합니다.
- 도구, 모델, 실행 시간과 토큰 사용량은 Telemetry 이벤트로 수집됩니다. 외부 관측 시스템으로 내보내려면 별도 핸들러가 필요합니다.
- 라우팅 회귀 평가 데이터는 `apps/core/priv/evals/routing.json`에 있습니다. 시드가 적용된 DB에서 `mix run scripts/evaluate_routing.exs`로 실행하고 실패 사례를 데이터에 추가하세요. 답변 품질 평가는 별도 라벨 데이터가 필요합니다.

## MCP (Model Context Protocol)

외부 MCP 서버는 **DB 테이블(`mcps`)**에서 관리합니다. 최초 1회 `seeds.exs` 실행 시 `.mcp.json`에서 import됩니다.
이후 UI의 `/admin/mcps`에서 CRUD 가능하며, 환경변수 placeholder(`${VAR}`)의 설정 여부로 상태를 표시합니다.

기본 외부 MCP 서버:

- `firecrawl`: 웹 스크래핑/검색 MCP. `FIRECRAWL_API_KEY` 필요.
- `context7`: 최신 라이브러리/API 문서 조회 MCP. `CONTEXT7_API_KEY` 권장 및 기본 설정에 사용.
- `filesystem`: 지정한 로컬 디렉터리 파일 접근 MCP. `MCP_FILESYSTEM_ROOT` 필요.
- `desktop-commander`: 로컬 파일/터미널 제어 MCP. 기본 비활성 상태로 등록되며, 활성화 전 권한 위임 수준을 확인해야 합니다.

로컬 권한 위임 수준:

- `none`: 로컬 권한 위임 없음.
- `read_only`: 읽기/검색 중심으로만 사용해야 하는 MCP.
- `workspace`: 지정된 워크스페이스 내부 파일 작업까지 허용하는 MCP.
- `full`: 파일 수정과 터미널 실행 등 강한 로컬 권한을 위임하는 MCP.

현재 권한 위임 수준은 `/admin/mcps`에서 관리하는 정책 메타데이터입니다. 외부 MCP 클라이언트를 직접 실행하는 경우에는 MCP 서버 자체의 허용 디렉터리, 차단 명령, OS 권한 설정도 함께 제한해야 합니다.

### 내장 MCP 서버 (STDIO)

```bash
mix run --no-halt -e "Core.MCP.Transport.Stdio.start()"
```

지원 메서드: `initialize`, `tools/{list,call}`, `prompts/{list,get}`, `resources/{list,read}`.

## UI / 디자인 시스템

- **Tailwind CSS 3.4** (Phoenix standalone CLI) + **daisyUI v5**(라이트/다크 테마) + **Heroicons v2**.
- Heroicons 는 `apps/web/mix.exs`에 git 의존성으로 포함되어 `deps/heroicons/optimized` 에서 SVG 를 읽고, `apps/web/assets/vendor/heroicons.js` Tailwind 플러그인이 `hero-*` 유틸리티 클래스를 생성합니다. `<.icon name="hero-x-mark" />` 형태로 사용합니다.
- 자산 빌드 산출물은 `apps/web/priv/static/assets/` 로 출력되며, 개발 환경에서는 watcher(`esbuild --watch`, `tailwind --watch`)가 자동으로 재빌드합니다.
- ⚠️ `apps/web/assets/vendor/daisyui.js` 는 ESM 형식으로 `default` export 를 노출하므로 `tailwind.config.js` 에서 `require("./vendor/daisyui").default` 로 unwrap 해야 컴포넌트 CSS(`navbar`, `btn`, `dropdown`, `card` 등)가 정상 생성됩니다.

### 컴포넌트 규칙

모든 UI 요소는 daisyUI 컴포넌트 + `core_components.ex` 헬퍼를 우선적으로 사용합니다.

| 용도 | 방식 |
|---|---|
| 폼 입력(텍스트/비밀번호/선택/텍스트영역/체크박스) | `<.input field={@form[:x]} type="..." label="..." />` 로 통일. 라벨·오류 메시지·`input-error` 상태가 자동 처리됩니다. |
| 페이지 헤더 | `<.header>...<:subtitle>...</:subtitle><:actions>...</:actions></.header>` |
| 플래시/알림 | `flash_group` + daisyUI `toast` / `alert` (`role="alert"`) |
| 테마 토글 | `<.theme_dropdown />` (Light / Dark / System 3단 전환, `localStorage` 저장) |
| 상태 표시 (MCP 등) | `<span class="status status-success" />` 의 daisyUI `status` 컴포넌트 |
| 리스트/메뉴 | `menu menu-sm`, 활성 항목은 `menu-active` |
| 채팅 | `chat chat-start|chat-end` + `chat-bubble chat-bubble-primary|accent|warning` |
| 로딩 인디케이터 | `loading loading-dots|spinner loading-xs|sm|md` |
| 레이아웃 | `hero`, `card bg-base-100 shadow-xl`, `navbar`, `join` (버튼 그룹) 우선 |

커스텀 CSS는 `apps/web/assets/css/app.css`의 **채팅 마크다운 `prose` 스타일** 과 LiveView 로딩 유틸리티(`phx-click-loading`, `phx-loading`) 만 유지하며, 그 외 폼/모달/토스트 관련 규칙은 daisyUI 에 위임합니다.

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
