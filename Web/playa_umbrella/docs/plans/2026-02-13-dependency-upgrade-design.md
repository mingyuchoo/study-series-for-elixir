# 의존성 업그레이드 디자인

**작성일:** 2026-02-13
**프로젝트:** Playa Umbrella
**목표:** 모든 의존성을 최신 버전으로 업그레이드

## 개요

Phoenix Umbrella 프로젝트(playa_umbrella)의 모든 의존성 패키지를 최신 안정 버전으로 업그레이드합니다. 단계별 순차 업그레이드 방식을 사용하여 각 단계마다 테스트를 수행하고, 문제 발생 시 조기에 발견하고 해결합니다.

## 1. 아키텍처 (Architecture)

### 업그레이드 구조

Phoenix Umbrella 프로젝트의 의존성은 두 계층으로 관리됩니다:

1. **루트 레벨 (mix.exs)**: 공통 도구 의존성 (phoenix_live_view - 포맷팅용)
2. **앱 레벨 (apps/*/mix.exs)**: 각 앱의 기능별 의존성

### 업그레이드 순서

```
┌─────────────────────────────────────────┐
│ 1단계: 핵심 프레임워크                      │
│  - Phoenix, Ecto, Phoenix LiveView      │
│  (모든 앱의 기반이 되는 프레임워크)          │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│ 2단계: Phoenix 생태계                     │
│  - Phoenix PubSub, HTML, Dashboard      │
│  (Phoenix에 의존하는 확장 기능)            │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│ 3단계: 데이터베이스 & 인프라                │
│  - Postgrex, DB Connection, Swoosh      │
│  (데이터 레이어와 외부 서비스)              │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│ 4단계: 인증 & 보안                        │
│  - Guardian, Bcrypt                     │
│  (보안 관련 패키지)                        │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│ 5단계: 유틸리티 & 도구                     │
│  - Timex, Finch, 기타 라이브러리         │
│  (부가 기능 라이브러리)                     │
└─────────────────────────────────────────┘
```

### 공유 의존성 lock 파일

모든 앱이 `../../mix.lock`을 공유하므로, 한 앱에서 업그레이드한 의존성이 다른 앱에도 즉시 영향을 미칩니다. 따라서 각 단계마다 **모든 앱에서 컴파일 및 테스트**를 수행해야 합니다.

## 2. 컴포넌트 (Components)

### 각 단계별 업그레이드 대상 패키지

#### 1단계: 핵심 프레임워크

```elixir
# apps/playa_web/mix.exs, apps/*/mix.exs
{:phoenix, "~> 1.7.11"} → 최신 1.7.x
{:phoenix_live_view, "~> 0.20.14"} → 최신 0.20.x or 1.0.x
{:phoenix_ecto, "~> 4.4"} → 최신 4.x
{:ecto_sql, "~> 3.10"} → 최신 3.x
{:ecto, "~> 3.13.5"} → (의존성으로 자동 업데이트)
```

#### 2단계: Phoenix 생태계

```elixir
{:phoenix_pubsub, "~> 2.1"} → 최신 2.x
{:phoenix_html, "~> 4.0"} → 최신 4.x
{:phoenix_live_dashboard, "~> 0.8.3"} → 최신 0.8.x
{:phoenix_template, "~> 1.0"} → (의존성으로 자동 업데이트)
{:telemetry_metrics, "~> 0.6"} → 최신 0.6.x or 1.x
{:telemetry_poller, "~> 1.0"} → 최신 1.x
```

#### 3단계: 데이터베이스 & 인프라

```elixir
{:postgrex, ">= 0.0.0"} → "~> 0.21" (버전 제약 추가)
{:db_connection, "~> 2.8.1"} → (의존성으로 자동 업데이트)
{:swoosh, "~> 1.5"} → 최신 1.x
{:finch, "~> 0.13"} → 최신 0.20.x
{:dns_cluster, "~> 0.1.1"} → 최신 0.1.x
```

#### 4단계: 인증 & 보안

```elixir
{:guardian, "~> 2.3"} → 최신 2.x
{:bcrypt_elixir, "~> 3.0"} → 최신 3.x
```

#### 5단계: 유틸리티 & 도구

```elixir
{:timex, "~> 3.7.11"} → 최신 3.7.x
{:jason, "~> 1.2"} → 최신 1.4.x
{:gettext, "~> 0.20"} → 최신 0.26.x
{:bandit, "~> 1.2"} → 최신 1.x
{:esbuild, "~> 0.8"} → 최신 0.10.x
{:tailwind, "~> 0.2"} → 최신 0.4.x
{:heroicons, tag: "v2.1.1"} → 최신 v2.x 태그
```

### 주의사항

- `">= 0.0.0"` 형태의 제약은 더 구체적인 버전 제약(`~> x.y`)으로 변경
- 각 패키지의 CHANGELOG를 확인하여 breaking changes 파악
- Phoenix LiveView가 1.0으로 업그레이드된 경우 API 변경사항 주의

## 3. 프로세스 흐름 (Data Flow)

### 각 단계별 실행 흐름

```
각 단계마다 다음 프로세스 반복:

1. 버전 확인
   ├─ mix hex.outdated 실행
   └─ 업그레이드 가능한 버전 파악

2. mix.exs 수정
   ├─ 해당 단계의 패키지 버전 제약 업데이트
   └─ 변경사항 검토

3. 의존성 업데이트
   ├─ mix deps.clean --all
   ├─ mix deps.get
   └─ mix deps.update <패키지명들>

4. 컴파일 검증
   ├─ mix compile
   ├─ 컴파일 오류 발생 시:
   │   ├─ 오류 메시지 분석
   │   ├─ 코드 수정 (deprecated API 교체 등)
   │   └─ 재컴파일
   └─ 성공 시 다음 단계로

5. 데이터베이스 마이그레이션 확인
   ├─ mix ecto.migrate (필요시)
   └─ 마이그레이션 오류 체크

6. 전체 앱 테스트
   ├─ 각 앱에서 mix test 실행:
   │   ├─ cd apps/playa && mix test
   │   ├─ cd apps/auth && mix test
   │   ├─ cd apps/productivity && mix test
   │   └─ cd apps/playa_web && mix test
   ├─ 테스트 실패 시:
   │   ├─ 실패 원인 분석
   │   ├─ 코드 또는 테스트 수정
   │   └─ 재테스트
   └─ 모든 테스트 통과 시 다음 단계로

7. 변경사항 커밋
   ├─ git add mix.exs apps/*/mix.exs mix.lock
   ├─ git commit -m "chore(deps): 단계 N - <패키지군> 업그레이드"
   └─ 각 단계를 별도 커밋으로 관리

8. 다음 단계로 진행
   └─ 1~7 반복
```

### 실패 시 롤백 전략

- 각 단계가 별도 커밋이므로 `git reset --hard HEAD~1`로 쉽게 롤백 가능
- 문제가 발생한 패키지만 이전 버전으로 고정하고 다른 패키지는 계속 진행

## 4. 오류 처리 (Error Handling)

### 예상되는 오류 유형과 해결 방법

#### 컴파일 오류

**1. Deprecated API 사용**
```
warning: Phoenix.Controller.put_view/2 is deprecated
```
→ 해결: CHANGELOG 확인 후 새로운 API로 교체

**2. 함수 시그니처 변경**
```
error: undefined function render/3
```
→ 해결: 패키지 업그레이드 가이드 참조, 함수 호출 방식 수정

**3. 모듈 이름 변경**
```
error: module Ecto.DateTime is not loaded
```
→ 해결: 새로운 모듈명으로 교체 (예: DateTime)

#### 의존성 충돌

**1. 버전 충돌**
```
Failed to use "phoenix" (version 1.7.x) because
  app1 requires ~> 1.7.0
  app2 requires ~> 1.6.0
```
→ 해결: 모든 앱의 mix.exs에서 동일한 버전 제약 사용

**2. 간접 의존성 충돌**
```
mix deps.tree 실행하여 의존성 트리 분석
```
→ 해결: 상위 의존성 버전 조정 또는 명시적 버전 지정

#### 테스트 실패

**1. API 변경으로 인한 테스트 실패**
→ 해결: 테스트 코드를 새 API에 맞게 수정

**2. Mock/Stub 동작 변경**
→ 해결: 테스트 헬퍼 함수 업데이트

**3. 데이터베이스 스키마 문제**
→ 해결: 마이그레이션 파일 추가 또는 수정

#### 런타임 오류

**1. 설정 파일 변경 필요**
```
config :phoenix, :json_library, Jason (필요 여부 확인)
```
→ 해결: config/*.exs 파일 업데이트

**2. 환경 변수 변경**
→ 해결: .env 파일 또는 시스템 환경 변수 업데이트

### 일반 오류 처리 흐름

1. 오류 메시지 전체 읽기
2. 패키지의 CHANGELOG 및 업그레이드 가이드 확인
3. Hex.pm 문서에서 해당 버전의 breaking changes 검색
4. 해결 불가능한 경우: 해당 패키지만 이전 버전으로 고정하고 이슈 트래킹

## 5. 테스트 전략 (Testing)

### 테스트 레벨

#### 1. 단위 테스트 (Unit Tests)

```bash
# 각 앱별로 실행
cd apps/playa && mix test
cd apps/auth && mix test
cd apps/productivity && mix test
cd apps/playa_web && mix test
```

- 각 단계 업그레이드 후 모든 앱의 테스트 실행
- 실패 시 해당 단계에서 멈추고 수정

#### 2. 통합 테스트 (Integration Tests)

```bash
# 루트에서 전체 테스트
mix test
```

- 앱 간 상호작용 검증
- 특히 auth ↔ playa, playa_web ↔ productivity 연동 확인

#### 3. 컴파일 타임 검증

```bash
# 경고를 오류로 처리하여 엄격하게 검증
mix compile --warnings-as-errors
```

- Deprecated API 사용 여부 확인
- 타입 불일치 조기 발견

#### 4. 의존성 검증

```bash
# 의존성 트리 확인
mix deps.tree

# 사용하지 않는 의존성 확인
mix deps.unlock --check-unused
```

- 불필요한 의존성 제거
- 순환 의존성 확인

#### 5. 수동 테스트 체크리스트

각 단계 완료 후 확인:

- [ ] 애플리케이션 시작 (`mix phx.server`)
- [ ] 로그인/로그아웃 기능 (auth 앱)
- [ ] 주요 페이지 렌더링 (playa_web 앱)
- [ ] 데이터베이스 CRUD 작업
- [ ] LiveView 실시간 기능
- [ ] 이메일 발송 (swoosh)

#### 6. 성능 회귀 테스트

```bash
# 애플리케이션 부팅 시간 측정
time mix compile
time mix test --only integration
```

- 업그레이드 전/후 성능 비교
- 큰 차이 발생 시 원인 분석

### 테스트 실패 시 대응

1. 실패한 테스트의 스택 트레이스 확인
2. 업그레이드된 패키지의 변경사항과 연관성 파악
3. 코드 수정 또는 테스트 수정
4. 수정 불가능한 경우: 해당 단계 롤백 및 이슈 기록

## 성공 기준

- [ ] 모든 의존성이 최신 안정 버전으로 업그레이드
- [ ] 모든 컴파일 경고 제거
- [ ] 모든 테스트 통과
- [ ] 애플리케이션이 정상적으로 시작 및 동작
- [ ] 각 단계가 별도 커밋으로 기록
- [ ] Breaking changes가 문서화됨

## 예상 소요 시간

- 1단계: 2-3시간 (핵심 프레임워크, 가장 많은 변경 예상)
- 2단계: 1-2시간
- 3단계: 1-2시간
- 4단계: 1시간
- 5단계: 1-2시간
- **총 예상 시간: 6-10시간**

## 리스크

1. **높음**: Phoenix LiveView 1.0 업그레이드 시 API 변경으로 인한 대규모 코드 수정 가능
2. **중간**: Guardian 또는 Bcrypt 업그레이드 시 인증 로직 영향
3. **낮음**: 유틸리티 라이브러리는 보통 호환성 유지

## 참고 문서

- [Phoenix 1.7 업그레이드 가이드](https://hexdocs.pm/phoenix/1.7.0/upgrade_guides.html)
- [Ecto 3.x 마이그레이션 가이드](https://hexdocs.pm/ecto/Ecto.Migrator.html)
- [Phoenix LiveView 변경 로그](https://github.com/phoenixframework/phoenix_live_view/blob/main/CHANGELOG.md)
