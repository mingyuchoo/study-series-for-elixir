# Agentic AI Assistant

Elixir/Phoenix 기반의 Agentic AI 어시스턴트 애플리케이션입니다.
Azure OpenAI API (gpt-5-mini)를 사용하여 도구 호출 기능이 있는 대화형 AI를 구현합니다.

**MCP (Model Context Protocol)** 명세를 준수하여 표준화된 방식으로 도구, 프롬프트, 리소스에 접근할 수 있습니다.

## 기술 스택

- **언어**: Elixir 1.19+
- **웹 프레임워크**: Phoenix 1.8+ (LiveView)
- **데이터베이스**: SQLite3 (Ecto)
- **AI**: Azure OpenAI API (gpt-5-mini)
- **프로토콜**: MCP (Model Context Protocol)
- **프로젝트 구조**: Umbrella

## 프로젝트 구조

```text
agentic_ai/
├── apps/
│   ├── core/                 # 핵심 비즈니스 로직
│   │   ├── lib/core/
│   │   │   ├── agent/        # AI 에이전트 (ReAct 패턴)
│   │   │   │   ├── supervisor.ex
│   │   │   │   ├── worker.ex
│   │   │   │   ├── tool_registry.ex
│   │   │   │   ├── skill_registry.ex
│   │   │   │   └── tools/    # 도구 구현
│   │   │   │       ├── calculator.ex
│   │   │   │       ├── date_time.ex
│   │   │   │       ├── web_search.ex
│   │   │   │       ├── file_system.ex
│   │   │   │       └── code_executor.ex
│   │   │   ├── mcp/          # MCP 서버
│   │   │   │   ├── server.ex
│   │   │   │   ├── protocol.ex
│   │   │   │   ├── tools.ex
│   │   │   │   ├── prompts.ex
│   │   │   │   ├── resources.ex
│   │   │   │   └── transport/
│   │   │   │       └── stdio.ex
│   │   │   ├── llm/          # LLM 클라이언트
│   │   │   │   └── azure_openai.ex
│   │   │   ├── schema/       # Ecto 스키마
│   │   │   │   ├── conversation.ex
│   │   │   │   ├── message.ex
│   │   │   │   └── tool.ex
│   │   │   └── repo.ex
│   │   └── priv/repo/migrations/
│   │
│   └── web/                  # Phoenix 웹 앱
│       └── lib/web_web/
│           ├── live/
│           │   └── chat_live.ex
│           └── router.ex
│
├── config/
│   ├── agents/               # 에이전트 설정 (마크다운)
│   │   ├── supervisor_main.md
│   │   ├── worker_general.md
│   │   ├── worker_calculator.md
│   │   ├── worker_emoji.md
│   │   └── worker_restructure.md
│   ├── skills/               # 스킬 정의 (워크플로우)
│   │   ├── research-report/
│   │   │   └── SKILL.md
│   │   └── code-analysis/
│   │       └── SKILL.md
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   ├── test.exs
│   └── runtime.exs
│
└── mix.exs
```

## 에이전트 도구

| 도구               | 설명                          |
| ------------------ | ----------------------------- |
| `get_current_time` | 현재 시간 조회 (타임존 지원)  |
| `calculate`        | 수학 계산                     |
| `search_web`       | 웹 검색 (DuckDuckGo)          |
| `read_file`        | 파일 읽기                     |
| `write_file`       | 파일 쓰기                     |
| `list_directory`   | 디렉터리 목록                 |
| `execute_code`     | Elixir 코드 실행              |

## MCP (Model Context Protocol)

MCP 명세에 따라 JSON-RPC 2.0 기반 서버를 구현하여 AI 애플리케이션이 표준화된 방식으로 접근할 수 있습니다.

### 지원 엔드포인트

| 메서드             | 설명                                     |
| ------------------ | ---------------------------------------- |
| `initialize`       | 클라이언트-서버 capability 협상          |
| `tools/list`       | 사용 가능한 도구 목록                    |
| `tools/call`       | 도구 실행                                |
| `prompts/list`     | 스킬(워크플로우 템플릿) 목록             |
| `prompts/get`      | 스킬 상세 조회                           |
| `resources/list`   | 에이전트/스킬 설정 리소스 목록           |
| `resources/read`   | 리소스 내용 읽기                         |

### 리소스 URI 스킴

- `agent://supervisor/main` - Supervisor 에이전트 설정
- `agent://worker/general` - Worker 에이전트 설정
- `skill://research-report` - 스킬 정의
- `config://agents` - 모든 에이전트 목록
- `config://skills` - 모든 스킬 목록

### STDIO 모드 실행

```bash
mix run --no-halt -e "Core.MCP.Transport.Stdio.start()"
```

### 사용 예시 (Elixir)

```elixir
# 도구 목록 조회
request = %{
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "tools/list"
}

{:ok, response} = Core.MCP.Server.handle_request(request)
# => %{"tools" => [%{"name" => "calculate", ...}, ...]}

# 도구 실행
request = %{
  "jsonrpc" => "2.0",
  "id" => 2,
  "method" => "tools/call",
  "params" => %{
    "name" => "calculate",
    "arguments" => %{"expression" => "2 + 3 * 4"}
  }
}

{:ok, response} = Core.MCP.Server.handle_request(request)
# => %{"content" => [%{"type" => "text", "text" => "14"}]}
```

## 설치 및 실행

### 빠른 시작 (권장)

start.sh 스크립트를 사용하면 의존성 설치, 데이터베이스 설정, 서버 실행을 한 번에 수행합니다.

```bash
# 1. 환경 변수 설정 (.env 파일 또는 직접 export)
cp .env.example .env  # .env 파일 생성 후 값 수정
# 또는
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com"
export AZURE_OPENAI_API_KEY="your-api-key"

# 2. 스크립트 실행
./start.sh
```

브라우저에서 <http://localhost:4000/chat> 접속

### 수동 설치

단계별로 직접 설치하려면 아래 과정을 따르세요.

#### 1. 환경 변수 설정

```bash
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com"
export AZURE_OPENAI_API_KEY="your-api-key"
```

또는 `.env` 파일에 설정:

```bash
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com
AZURE_OPENAI_API_KEY=your-api-key
```

#### 2. Elixir/Erlang 설치 (asdf 권장)

```bash
# asdf 사용 시
asdf install erlang 28.3
asdf install elixir 1.19.4-otp-28
asdf local erlang 28.3
asdf local elixir 1.19.4-otp-28
```

#### 3. 의존성 설치

```bash
cd agentic_ai
mix deps.get
```

#### 4. 데이터베이스 설정

```bash
mix ecto.create
mix ecto.migrate
```

#### 5. 서버 실행

```bash
mix phx.server
```

브라우저에서 <http://localhost:4000/chat> 접속

## 개발

### IEx 셸에서 실행

```bash
iex -S mix phx.server
```

### 테스트

```bash
mix test
```

## ReAct 패턴

이 에이전트는 ReAct (Reasoning + Acting) 패턴을 구현합니다:

1. **Reasoning**: LLM이 상황을 분석하고 다음 행동을 결정
2. **Acting**: 필요한 도구를 호출하여 작업 수행
3. **Observation**: 도구 실행 결과를 관찰
4. **반복**: 목표 달성까지 1-3단계 반복

## 라이선스

MIT

---

Made with 💥 by 붐돌이
