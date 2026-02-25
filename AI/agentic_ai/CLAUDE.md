# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

Elixir/Phoenix 기반의 Agentic AI 어시스턴트 애플리케이션입니다. ReAct (Reasoning + Acting) 패턴을 구현하여 Azure OpenAI API (gpt-5-mini)를 사용한 도구 호출 기능이 있는 대화형 AI 시스템입니다.

**핵심 기술 스택:**

- Elixir 1.19+ / Phoenix 1.8 (LiveView)
- SQLite3 (Ecto ORM)
- Azure OpenAI API
- Umbrella 프로젝트 구조 (core + web)

## 개발 명령어

### 초기 설정

```bash
# 환경 변수 설정 필요
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com"
export AZURE_OPENAI_API_KEY="your-api-key"

# 의존성 설치 및 데이터베이스 초기화
mix deps.get
mix ecto.create
mix ecto.migrate
```

### 일반 개발

```bash
# 개발 서버 실행
mix phx.server

# IEx 셸과 함께 실행 (디버깅 시 유용)
iex -S mix phx.server

# 테스트 실행
mix test --cover            # 모든 테스트
mix test test/path/file.exs # 특정 파일
mix test --failed           # 실패한 테스트만

# 코드 포매팅
mix format

# 자산 빌드
mix assets.build            # CSS/JS 빌드
mix assets.deploy           # 프로덕션 최적화 빌드
```

### Precommit

```bash
# 커밋 전 모든 검사 실행
mix precommit
```

## 아키텍처 개요

### Umbrella 구조

프로젝트는 두 개의 독립적인 앱으로 구성:

- **`apps/core/`**: 핵심 비즈니스 로직 (AI 에이전트, LLM 클라이언트, 데이터 스키마)
- **`apps/web/`**: Phoenix 웹 인터페이스 (LiveView, 라우팅, UI)

### ReAct 패턴 구현 (`core/agent/worker.ex`)

에이전트는 다음 루프를 최대 10회 반복:

1. **Reasoning**: LLM이 상황을 분석하고 다음 행동 결정
2. **Acting**: 필요한 도구를 호출하여 작업 수행
3. **Observation**: 도구 실행 결과를 관찰
4. **반복**: 목표 달성 또는 최대 반복 횟수 도달까지 반복

핵심 흐름: `handle_continue(:run_agent)` → `chat_completion()` → `process_response()` → 도구 실행 → 다시 반복

### GenServer 기반 에이전트 관리

- 각 대화(`conversation_id`)마다 독립적인 `Core.Agent.Worker` GenServer 프로세스
- `Core.Agent.Supervisor` (DynamicSupervisor)가 프로세스 생명주기 관리
- `Registry`를 통한 대화 ID 기반 프로세스 조회
- 시작: `Core.Agent.Supervisor.start_agent(conversation_id)`

### 도구 시스템

플러그인 방식 아키텍처:

- `Core.Agent.ToolRegistry`: 도구 등록 및 실행 디스패칭
- `apps/core/lib/core/agent/tools/`: 각 도구 모듈 (`calculator.ex`, `web_search.ex`, 등)
- OpenAI Function Calling 명세 준수 (JSON Schema)
- 보안: 파일 시스템 접근은 작업 디렉토리로 제한, 코드 실행은 5초 타임아웃

### 데이터베이스 스키마

**Conversations**: 대화 세션 관리

- `id` (UUID), `title`, `system_prompt`, `status` (active/archived)

**Messages**: 메시지 이력 (system/user/assistant/tool 역할)

- `role`, `content`, `tool_calls` (JSON), `tokens_used`
- `conversation_id` 외래키로 대화와 연결

**Tools**: 사용 가능한 도구 정의

- `name`, `description`, `parameters` (JSON Schema), `enabled`

### LiveView 아키텍처 (`web_web/live/chat_live.ex`)

- 실시간 채팅 UI: 사용자 입력 → `handle_event("send_message")` → GenServer로 비동기 처리 → UI 업데이트
- LiveView streams로 메시지 목록 관리 (메모리 효율성)
- 대화 목록 및 상세 보기 모두 동일 LiveView 모듈에서 처리

## Phoenix v1.8 가이드라인

### 필수 사항

- `Req` 라이브러리를 HTTP 요청에 사용 (httpoison, tesla 등 피할 것)
- LiveView 템플릿은 항상 `<Layouts.app flash={@flash}>` 로 시작
- 아이콘은 `<.icon name="hero-x-mark" class="w-5 h-5"/>` 컴포넌트 사용
- 폼 입력은 `<.input>` 컴포넌트 사용 (`core_components.ex`에서 import)

### LiveView 규칙

```elixir
# 네비게이션: live_redirect/live_patch 사용 금지
# 템플릿에서:
<.link navigate={href}>링크</.link>
<.link patch={href}>패치</.link>

# LiveView에서:
push_navigate(socket, to: path)
push_patch(socket, to: path)
```

### LiveView Streams

컬렉션은 항상 streams 사용 (메모리 문제 방지):

```elixir
# LiveView에서
stream(socket, :messages, [new_msg])                    # 추가
stream(socket, :messages, messages, reset: true)        # 리셋
stream_delete(socket, :messages, msg)                   # 삭제

# 템플릿에서
<div id="messages" phx-update="stream">
  <div :for={{id, msg} <- @streams.messages} id={id}>
    {msg.text}
  </div>
</div>
```

**중요**: Streams는 enumerable이 아니므로 필터링/변경 시 전체 데이터를 다시 fetch하고 `reset: true`로 재설정해야 함.

### 폼 처리

```elixir
# LiveView에서 changeset을 to_form으로 변환
socket = assign(socket, form: to_form(changeset))

# 템플릿에서 항상 @form 사용 (changeset 직접 사용 금지)
<.form for={@form} id="my-form" phx-submit="save">
  <.input field={@form[:email]} type="email" />
</.form>
```

### HEEx 템플릿

- `if/elsif/else if` 지원 안 됨 → 다중 조건은 `cond` 또는 `case` 사용
- 속성 내 보간: `{...}` 사용 (예: `<div id={@id}>`)
- 태그 body 내 블록 구문: `<%= ... %>` 사용 (예: `<%= if @condition do %>`)
- 리스트 렌더링: `<%= for item <- @items do %>` 사용 (`Enum.each` 금지)
- 코드 블록 표시 시: `<code phx-no-curly-interpolation>` 사용
- 클래스 목록: `class={["base-class", @flag && "extra-class"]}` 형태로 사용

### JavaScript 상호작용

**인라인 Hook (권장):**

```heex
<input id="phone" phx-hook=".PhoneNumber" />
<script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
  export default {
    mounted() { /* 로직 */ }
  }
</script>
```

- Hook 이름은 `.` prefix 필수 (예: `.PhoneNumber`)
- 자동으로 app.js에 번들링됨

**외부 Hook:**

- `assets/js/`에 배치하고 `LiveSocket` 생성자에 전달
- `phx-hook`과 함께 `phx-update="ignore"` 사용 시 고유 DOM id 필수

## 테스트 가이드라인 (TDD 필수)

모든 코드 변경은 **TDD(Test-Driven Development)** 방식을 따라야 합니다.

### TDD 사이클

새로운 기능 추가 또는 버그 수정 시 반드시 다음 순서를 따릅니다:

1. **Red**: 실패하는 테스트를 먼저 작성
2. **Green**: 테스트를 통과하는 최소한의 구현 코드 작성
3. **Refactor**: 테스트가 통과하는 상태를 유지하며 코드 개선

### TDD 규칙

- **테스트 먼저**: 구현 코드를 작성하기 전에 반드시 테스트를 먼저 작성
- **최소 구현**: 테스트를 통과하기 위한 최소한의 코드만 작성
- **점진적 진행**: 한 번에 하나의 테스트만 추가하고 통과시키기
- **커버리지 유지**: `mix test --cover`로 커버리지 확인, 새 코드는 반드시 테스트 포함
- **테스트 격리**: 각 테스트는 독립적으로 실행 가능해야 함 (다른 테스트에 의존 금지)

### 테스트 작성 패턴

```elixir
# describe 블록으로 함수 단위 그룹화
describe "create_user/1" do
  test "유효한 속성으로 사용자 생성 성공" do
    attrs = %{name: "홍길동", email: "hong@example.com"}
    assert {:ok, %User{} = user} = Accounts.create_user(attrs)
    assert user.name == "홍길동"
  end

  test "이메일 누락 시 에러 반환" do
    attrs = %{name: "홍길동"}
    assert {:error, %Ecto.Changeset{}} = Accounts.create_user(attrs)
  end
end
```

### 테스트 모범 사례

- 프로세스 시작 시 `start_supervised!/1` 사용
- 테스트 동기화: `Process.sleep/1` 대신 `Process.monitor/1` 사용
- 외부 API 호출은 Mock/Stub 사용 (Mox 라이브러리 권장)
- 픽스처 대신 ExMachina 또는 팩토리 패턴 사용 권장
- `async: true` 설정으로 테스트 병렬 실행 (DB 격리 필요 시 Sandbox 사용)

## Elixir 가이드라인

### 중요 주의사항

```elixir
# ❌ 리스트 인덱스 접근 불가 (Invalid)
list[0]

# ✅ Enum.at 사용
Enum.at(list, 0)

# ❌ if 블록 내 재할당 (Invalid)
if condition do
  socket = assign(socket, :val, val)
end

# ✅ if 결과를 변수에 할당
socket =
  if condition do
    assign(socket, :val, val)
  else
    socket
  end

# ❌ Struct에 map 접근 구문 사용 금지
changeset[:field]

# ✅ Struct 필드 직접 접근 또는 전용 API
changeset.field
Ecto.Changeset.get_field(changeset, :field)
```

### 모범 사례

- Predicate 함수는 `?`로 끝나야 함 (예: `valid?/1`)
- `is_` prefix는 guard 함수용으로 예약
- 사용자 입력에 `String.to_atom/1` 사용 금지 (메모리 누수 위험)
- 중첩 모듈 정의 금지 (순환 의존성 위험)

### OTP 패턴

```elixir
# DynamicSupervisor, Registry는 child_spec에 name 필요
{DynamicSupervisor, name: MyApp.MySupervisor}

# 이후 이름으로 참조
DynamicSupervisor.start_child(MyApp.MySupervisor, child_spec)

# 동시 처리는 Task.async_stream 사용
Task.async_stream(collection, fn item -> process(item) end, timeout: :infinity)
```

## UI/UX 가이드라인

- **DaisyUI + Tailwind CSS** 조합으로 세련되고 반응형 인터페이스 제작
- DaisyUI 컴포넌트를 우선 사용하고, 부족한 부분은 Tailwind 유틸리티로 보완
- 하드코딩된 색상 (`bg-blue-600`, `text-white` 등) 사용 금지 → 시맨틱 클래스 (`bg-primary`, `text-base-content` 등) 사용
- 미묘한 마이크로 인터랙션 구현 (hover 효과, 전환 애니메이션)
- 깨끗한 타이포그래피, 간격, 레이아웃 균형 유지
- 참고: [DaisyUI Components](https://daisyui.com/components/)

## 환경 변수

필수:

- `AZURE_OPENAI_ENDPOINT`: Azure OpenAI 리소스 엔드포인트
- `AZURE_OPENAI_API_KEY`: API 키

옵션:

- `AZURE_OPENAI_API_VERSION`: 기본값 `2024-10-21`
- `FIRECRAWL_API_KEY`: Firecrawl MCP 서버용 API 키 ([발급 링크](https://firecrawl.dev/app/api-keys))

## MCP 서버 설정

프로젝트는 `.mcp.json` 파일을 통해 MCP(Model Context Protocol) 서버를 설정합니다.

### Firecrawl MCP

웹 스크래핑, 크롤링, 검색 기능을 제공하는 MCP 서버입니다.

```bash
# API 키 발급
# https://firecrawl.dev/app/api-keys

# 환경 변수 설정
export FIRECRAWL_API_KEY="your-firecrawl-api-key"
```

**사용 가능한 도구:**

- `scrape`: 단일 페이지 콘텐츠 추출
- `crawl`: 웹사이트 크롤링
- `map`: 사이트 구조 매핑
- `search`: 웹 검색
- `extract`: 구조화된 데이터 추출

**관련 스킬:** `config/skills/firecrawl/SKILL.md`

## 주요 라우트

- `/` - 홈 페이지
- `/chat` - 대화 목록
- `/chat/:id` - 특정 대화 상세
- `/api/health` - 헬스 체크
