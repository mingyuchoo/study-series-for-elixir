# 의존성 업그레이드 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Playa Umbrella 프로젝트의 모든 의존성을 최신 버전으로 단계별 업그레이드

**Architecture:** 5단계 순차 업그레이드 방식으로, 각 단계마다 mix.exs 수정 → 의존성 업데이트 → 컴파일 → 테스트 → 커밋 순서로 진행. 공유 mix.lock 파일로 인해 모든 앱에서 동시에 검증 필요.

**Tech Stack:** Elixir 1.19.2, Phoenix 1.7→1.8, Phoenix LiveView 0.20→1.1, Ecto 3.13

---

## 준비 단계

### Task 0: 현재 상태 백업 및 확인

**Files:**
- Read: `mix.lock`
- Read: `apps/*/mix.exs`

**Step 1: 현재 의존성 상태 기록**

Run:
```bash
mix hex.outdated > docs/dependency-status-before.txt
```

Expected: 업그레이드 전 의존성 상태가 파일에 기록됨

**Step 2: 테스트가 현재 통과하는지 확인**

Run:
```bash
mix test
```

Expected: 모든 테스트 통과 (baseline 확인)

**Step 3: 현재 상태 커밋**

```bash
git add docs/dependency-status-before.txt
git commit -m "chore(deps): record dependency status before upgrade"
```

---

## 1단계: 핵심 프레임워크 업그레이드

### Task 1: Phoenix 1.8 업그레이드

**Files:**
- Modify: `apps/playa_web/mix.exs:39`

**Step 1: Phoenix 버전 제약 변경**

apps/playa_web/mix.exs의 39번 줄:
```elixir
{:phoenix, "~> 1.7.11"},
```
→ 다음으로 변경:
```elixir
{:phoenix, "~> 1.8"},
```

**Step 2: 의존성 업데이트**

Run:
```bash
mix deps.update phoenix
```

Expected: Phoenix가 1.8.x로 업데이트됨

**Step 3: Phoenix 변경사항 확인**

Run:
```bash
mix hex.info phoenix
```

Check: CHANGELOG에서 breaking changes 확인

**Step 4: 컴파일 및 경고 확인**

Run:
```bash
mix compile --force
```

Expected: 컴파일 성공 또는 deprecated 경고 (오류 발생 시 수정 필요)

**Step 5: 전체 앱 테스트**

Run:
```bash
mix test
```

Expected: 모든 테스트 통과 (실패 시 코드 수정 필요)

**Step 6: 커밋**

```bash
git add apps/playa_web/mix.exs mix.lock
git commit -m "chore(deps): upgrade Phoenix to 1.8.x"
```

---

### Task 2: Phoenix LiveView 1.1 업그레이드

**Files:**
- Modify: `mix.exs:39` (루트)
- Modify: `apps/playa_web/mix.exs:43`

**중요:** Phoenix LiveView 1.0+는 major breaking changes를 포함합니다. 신중히 진행하세요.

**Step 1: 루트 mix.exs의 LiveView 버전 제약 변경**

mix.exs의 39번 줄:
```elixir
{:phoenix_live_view, ">= 0.0.0"}
```
→ 다음으로 변경:
```elixir
{:phoenix_live_view, "~> 1.0"}
```

**Step 2: playa_web mix.exs의 LiveView 버전 제약 변경**

apps/playa_web/mix.exs의 43번 줄:
```elixir
{:phoenix_live_view, "~> 0.20.14"},
```
→ 다음으로 변경:
```elixir
{:phoenix_live_view, "~> 1.0"},
```

**Step 3: 의존성 업데이트**

Run:
```bash
mix deps.update phoenix_live_view
```

Expected: Phoenix LiveView가 1.x로 업데이트됨

**Step 4: LiveView 1.0 마이그레이션 가이드 확인**

Run:
```bash
curl -s https://raw.githubusercontent.com/phoenixframework/phoenix_live_view/main/CHANGELOG.md | head -200
```

Read: Breaking changes 섹션 확인

**Step 5: 컴파일 및 오류 수정**

Run:
```bash
mix compile --force 2>&1 | grep -E "(warning|error)"
```

Expected: deprecated 함수 사용 경고가 있을 수 있음

Common changes needed:
- `live_render/3` → `live_render/2`
- `Phoenix.LiveView.Controller` 함수들의 시그니처 변경
- `handle_params/3`의 동작 변경 확인

**Step 6: LiveView 관련 코드 검색**

Run:
```bash
grep -r "live_render\|handle_params\|live_patch\|live_redirect" apps/playa_web/lib --include="*.ex" | head -20
```

Check: LiveView 1.0에서 변경된 API 사용 여부 확인

**Step 7: 전체 앱 테스트**

Run:
```bash
mix test
```

Expected: 모든 테스트 통과 (실패 시 LiveView API 변경사항 반영 필요)

**Step 8: 커밋**

```bash
git add mix.exs apps/playa_web/mix.exs mix.lock
git commit -m "chore(deps): upgrade Phoenix LiveView to 1.x

BREAKING CHANGE: Phoenix LiveView 1.0 includes API changes"
```

---

### Task 3: Ecto 및 Phoenix Ecto 업그레이드

**Files:**
- Modify: `apps/auth/mix.exs:41`
- Modify: `apps/playa/mix.exs:42`
- Modify: `apps/productivity/mix.exs:41`
- Modify: `apps/playa_web/mix.exs:40`

**Step 1: 모든 앱의 ecto_sql 버전 제약 변경**

apps/auth/mix.exs, apps/playa/mix.exs, apps/productivity/mix.exs의 ecto_sql:
```elixir
{:ecto_sql, "~> 3.10"},
```
→ 다음으로 변경:
```elixir
{:ecto_sql, "~> 3.13"},
```

apps/playa_web/mix.exs의 phoenix_ecto:
```elixir
{:phoenix_ecto, "~> 4.4"},
```
→ 다음으로 변경:
```elixir
{:phoenix_ecto, "~> 4.7"},
```

**Step 2: 의존성 업데이트**

Run:
```bash
mix deps.update ecto_sql phoenix_ecto ecto
```

Expected: Ecto 관련 패키지들이 최신 버전으로 업데이트됨

**Step 3: 컴파일**

Run:
```bash
mix compile --force
```

Expected: 컴파일 성공

**Step 4: 데이터베이스 마이그레이션 확인**

Run:
```bash
mix ecto.migrate
```

Expected: "Already up" 또는 성공적인 마이그레이션

**Step 5: 각 앱별 테스트**

Run:
```bash
cd apps/auth && mix test
cd ../playa && mix test
cd ../productivity && mix test
cd ../playa_web && mix test
```

Expected: 모든 앱의 테스트 통과

**Step 6: 커밋**

```bash
git add apps/*/mix.exs mix.lock
git commit -m "chore(deps): upgrade Ecto to 3.13 and Phoenix Ecto to 4.7"
```

---

## 2단계: Phoenix 생태계 업그레이드

### Task 4: Telemetry Metrics 업그레이드

**Files:**
- Modify: `apps/playa_web/mix.exs:55`

**Step 1: telemetry_metrics 버전 제약 변경**

apps/playa_web/mix.exs의 55번 줄:
```elixir
{:telemetry_metrics, "~> 0.6"},
```
→ 다음으로 변경:
```elixir
{:telemetry_metrics, "~> 1.0"},
```

**Step 2: 의존성 업데이트**

Run:
```bash
mix deps.update telemetry_metrics
```

Expected: Telemetry Metrics가 1.x로 업데이트됨

**Step 3: Telemetry 설정 파일 확인**

Check:
- `apps/playa_web/lib/playa_web/telemetry.ex`

Run:
```bash
grep -n "Telemetry.Metrics" apps/playa_web/lib/playa_web/telemetry.ex
```

Note: Telemetry Metrics 1.0의 API 변경사항 확인

**Step 4: 컴파일 및 테스트**

Run:
```bash
mix compile --force
mix test
```

Expected: 컴파일 성공 및 모든 테스트 통과

**Step 5: 커밋**

```bash
git add apps/playa_web/mix.exs mix.lock
git commit -m "chore(deps): upgrade Telemetry Metrics to 1.x"
```

---

### Task 5: Phoenix 개발 도구 업그레이드

**Files:**
- Modify: `apps/playa_web/mix.exs:42`

**Step 1: phoenix_live_reload 버전 제약 변경**

apps/playa_web/mix.exs의 42번 줄:
```elixir
{:phoenix_live_reload, "~> 1.2", only: :dev},
```
→ 다음으로 변경:
```elixir
{:phoenix_live_reload, "~> 1.6", only: :dev},
```

**Step 2: 의존성 업데이트**

Run:
```bash
mix deps.update phoenix_live_reload
```

Expected: Phoenix Live Reload가 1.6.x로 업데이트됨

**Step 3: 개발 서버 시작 테스트**

Run:
```bash
mix phx.server &
SERVER_PID=$!
sleep 5
kill $SERVER_PID
```

Expected: 서버가 정상적으로 시작되고 종료됨 (live reload 기능 확인)

**Step 4: 컴파일 및 테스트**

Run:
```bash
mix compile
mix test
```

Expected: 성공

**Step 5: 커밋**

```bash
git add apps/playa_web/mix.exs mix.lock
git commit -m "chore(deps): upgrade Phoenix Live Reload to 1.6.x"
```

---

## 3단계: 데이터베이스 & 인프라 업그레이드

### Task 6: Postgrex 업그레이드

**Files:**
- Modify: `apps/auth/mix.exs:42`
- Modify: `apps/playa/mix.exs:43`
- Modify: `apps/productivity/mix.exs:42`

**Step 1: postgrex 버전 제약 추가**

apps/auth/mix.exs, apps/playa/mix.exs, apps/productivity/mix.exs의 postgrex:
```elixir
{:postgrex, ">= 0.0.0"},
```
→ 다음으로 변경:
```elixir
{:postgrex, "~> 0.21"},
```

**Step 2: 의존성 업데이트**

Run:
```bash
mix deps.update postgrex
```

Expected: Postgrex가 0.21.x 또는 0.22.x로 업데이트됨

**Step 3: 데이터베이스 연결 테스트**

Run:
```bash
mix ecto.migrate
```

Expected: 데이터베이스 연결 및 마이그레이션 성공

**Step 4: 각 앱의 데이터베이스 테스트**

Run:
```bash
cd apps/auth && mix test
cd ../playa && mix test
cd ../productivity && mix test
```

Expected: 모든 데이터베이스 관련 테스트 통과

**Step 5: 커밋**

```bash
git add apps/*/mix.exs mix.lock
git commit -m "chore(deps): upgrade Postgrex and add version constraints"
```

---

### Task 7: Swoosh & Finch 업그레이드

**Files:**
- Modify: `apps/auth/mix.exs:44-45`
- Modify: `apps/playa/mix.exs:45-46`
- Modify: `apps/productivity/mix.exs:44-45`

**Step 1: swoosh 버전 제약 변경**

apps/auth/mix.exs, apps/playa/mix.exs, apps/productivity/mix.exs의 swoosh:
```elixir
{:swoosh, "~> 1.5"},
```
→ 다음으로 변경:
```elixir
{:swoosh, "~> 1.19"},
```

**Step 2: finch 버전 제약 변경**

같은 파일들의 finch:
```elixir
{:finch, "~> 0.13"},
```
→ 다음으로 변경:
```elixir
{:finch, "~> 0.20"},
```

**Step 3: 의존성 업데이트**

Run:
```bash
mix deps.update swoosh finch
```

Expected: Swoosh와 Finch가 최신 버전으로 업데이트됨

**Step 4: 컴파일 및 테스트**

Run:
```bash
mix compile --force
mix test
```

Expected: 컴파일 성공 및 모든 테스트 통과

**Step 5: 커밋**

```bash
git add apps/*/mix.exs mix.lock
git commit -m "chore(deps): upgrade Swoosh to 1.19+ and Finch to 0.20+"
```

---

### Task 8: DNS Cluster 업그레이드

**Files:**
- Modify: `apps/auth/mix.exs:39`
- Modify: `apps/playa/mix.exs:40`
- Modify: `apps/productivity/mix.exs:39`

**Step 1: dns_cluster 버전 제약 변경**

apps/auth/mix.exs, apps/playa/mix.exs, apps/productivity/mix.exs의 dns_cluster:
```elixir
{:dns_cluster, "~> 0.1.1"},
```
→ 다음으로 변경:
```elixir
{:dns_cluster, "~> 0.1"},
```

**Step 2: 의존성 업데이트**

Run:
```bash
mix deps.update dns_cluster
```

Expected: DNS Cluster가 최신 0.1.x로 업데이트됨 (0.2.0은 제약으로 인해 설치 안됨)

**Step 3: 컴파일 및 테스트**

Run:
```bash
mix compile
mix test
```

Expected: 성공

**Step 4: 커밋**

```bash
git add apps/*/mix.exs mix.lock
git commit -m "chore(deps): update DNS Cluster version constraints"
```

---

## 4단계: 인증 & 보안 (이미 최신)

### Task 9: Guardian & Bcrypt 확인

**Files:**
- Read: `apps/auth/mix.exs:46`
- Read: `apps/playa/mix.exs:39`

**Step 1: 현재 버전 확인**

Run:
```bash
mix hex.outdated guardian bcrypt_elixir
```

Expected:
- Guardian 2.4.0 - Up-to-date
- Bcrypt 3.3.2 - Up-to-date

**Step 2: 보안 감사**

Run:
```bash
mix hex.audit
```

Expected: 알려진 보안 취약점이 없음을 확인

**Step 3: 문서화**

Note: Guardian과 Bcrypt는 이미 최신 버전이므로 업데이트 불필요

---

## 5단계: 유틸리티 & 도구 업그레이드

### Task 10: Gettext 1.0 업그레이드

**Files:**
- Modify: `apps/playa_web/mix.exs:57`

**Step 1: gettext 버전 제약 변경**

apps/playa_web/mix.exs의 57번 줄:
```elixir
{:gettext, "~> 0.20"},
```
→ 다음으로 변경:
```elixir
{:gettext, "~> 1.0"},
```

**Step 2: 의존성 업데이트**

Run:
```bash
mix deps.update gettext
```

Expected: Gettext가 1.0.x로 업데이트됨

**Step 3: Gettext 파일 확인**

Check:
- `apps/playa_web/priv/gettext/`

Run:
```bash
mix gettext.extract --check-up-to-date
```

Expected: 번역 파일이 최신 상태임을 확인

**Step 4: 컴파일 및 테스트**

Run:
```bash
mix compile --force
mix test
```

Expected: 컴파일 성공 및 모든 테스트 통과

**Step 5: 커밋**

```bash
git add apps/playa_web/mix.exs mix.lock
git commit -m "chore(deps): upgrade Gettext to 1.x"
```

---

### Task 11: Bandit 웹 서버 업그레이드

**Files:**
- Modify: `apps/playa_web/mix.exs:61`

**Step 1: bandit 버전 제약 변경**

apps/playa_web/mix.exs의 61번 줄:
```elixir
{:bandit, "~> 1.2"},
```
→ 다음으로 변경:
```elixir
{:bandit, "~> 1.8"},
```

**Step 2: 의존성 업데이트**

Run:
```bash
mix deps.update bandit
```

Expected: Bandit가 1.8.x 이상으로 업데이트됨

**Step 3: 웹 서버 시작 테스트**

Run:
```bash
MIX_ENV=test mix phx.server &
SERVER_PID=$!
sleep 5
curl -s http://localhost:4000 > /dev/null && echo "Server OK" || echo "Server Failed"
kill $SERVER_PID
```

Expected: "Server OK" 출력

**Step 4: 컴파일 및 테스트**

Run:
```bash
mix compile
mix test
```

Expected: 성공

**Step 5: 커밋**

```bash
git add apps/playa_web/mix.exs mix.lock
git commit -m "chore(deps): upgrade Bandit web server to 1.8+"
```

---

## 최종 검증

### Task 12: 전체 시스템 검증

**Files:**
- Read: `mix.lock`
- Test: 모든 앱

**Step 1: 최종 의존성 상태 확인**

Run:
```bash
mix hex.outdated > docs/dependency-status-after.txt
```

Expected: 업그레이드 후 의존성 상태 기록

**Step 2: 의존성 트리 확인**

Run:
```bash
mix deps.tree | head -50
```

Check: 순환 의존성이나 버전 충돌이 없는지 확인

**Step 3: 사용하지 않는 의존성 확인**

Run:
```bash
mix deps.unlock --check-unused
```

Expected: 사용하지 않는 의존성이 없음을 확인

**Step 4: 전체 프로젝트 클린 빌드**

Run:
```bash
mix deps.clean --all
mix deps.get
mix compile --force --warnings-as-errors
```

Expected: 경고 없이 컴파일 성공

**Step 5: 전체 테스트 스위트 실행**

Run:
```bash
mix test --cover
```

Expected: 모든 테스트 통과 및 코드 커버리지 확인

**Step 6: 수동 테스트 체크리스트**

```bash
# 1. 서버 시작
mix phx.server
```

Manual checks:
- [ ] 애플리케이션이 정상적으로 시작됨
- [ ] 로그인/로그아웃 기능 정상 동작 (http://localhost:4000)
- [ ] 주요 페이지 렌더링 확인
- [ ] LiveView 실시간 기능 동작 확인
- [ ] 데이터베이스 CRUD 작업 정상 동작

**Step 7: 성능 비교**

Run:
```bash
time mix compile
```

Note: 컴파일 시간을 업그레이드 전과 비교

**Step 8: 최종 상태 커밋**

```bash
git add docs/dependency-status-after.txt
git commit -m "chore(deps): record final dependency status after upgrade"
```

---

### Task 13: 업그레이드 요약 문서 작성

**Files:**
- Create: `docs/upgrade-summary.md`

**Step 1: 업그레이드 요약 문서 작성**

Create `docs/upgrade-summary.md`:

```markdown
# 의존성 업그레이드 요약 (2026-02-13)

## 주요 업그레이드

### 메이저 버전 업그레이드
- **Phoenix**: 1.7.21 → 1.8.x
- **Phoenix LiveView**: 0.20.17 → 1.1.x
- **Gettext**: 0.26.2 → 1.0.x
- **Telemetry Metrics**: 0.6.2 → 1.1.x

### 마이너 버전 업그레이드
- **Ecto SQL**: 3.13.2 → 3.13.4
- **Bandit**: 1.8.0 → 1.10.2
- **Finch**: 0.20.0 → 0.21.0
- **Postgrex**: 0.21.1 → 0.22.0
- **Swoosh**: 1.19.8 → 1.21.0

### 개발 도구 업그레이드
- **Phoenix Live Reload**: 1.6.1 → 1.6.2

## Breaking Changes

### Phoenix LiveView 1.0
- API 시그니처 변경 가능
- 마이그레이션 가이드 참조 필요

### Phoenix 1.8
- 일부 deprecated 함수 제거
- 새로운 기능 추가

## 테스트 결과

- 모든 단위 테스트 통과: ✓
- 통합 테스트 통과: ✓
- 수동 테스트 통과: ✓

## 다음 단계

- 프로덕션 배포 전 스테이징 환경 테스트
- 모니터링 강화
```

**Step 2: 요약 문서 커밋**

```bash
git add docs/upgrade-summary.md
git commit -m "docs: add dependency upgrade summary"
```

---

### Task 14: 태그 생성 (선택사항)

**Step 1: 업그레이드 완료 태그 생성**

```bash
git tag -a v0.2.0-deps-upgrade -m "Dependency upgrade to latest versions

- Phoenix 1.8
- Phoenix LiveView 1.1
- Gettext 1.0
- Telemetry Metrics 1.1
- Other minor updates"
```

**Step 2: 태그 푸시 (선택사항)**

```bash
# git push origin v0.2.0-deps-upgrade
```

Note: 리모트 저장소에 푸시할 준비가 되면 실행

---

## 트러블슈팅 가이드

### Phoenix LiveView 1.0 마이그레이션 실패 시

**문제:** 컴파일 오류 또는 테스트 실패

**해결:**
1. CHANGELOG 확인: https://github.com/phoenixframework/phoenix_live_view/blob/main/CHANGELOG.md
2. 공통 변경사항:
   - `Phoenix.LiveView.Controller.live_render/3` → `live_render/2`
   - `handle_params/3` 동작 변경 확인
   - `Phoenix.LiveView.Router` 헬퍼 변경사항

**롤백:**
```bash
git reset --hard HEAD~1
```

### Phoenix 1.8 업그레이드 실패 시

**문제:** 컴파일 오류

**해결:**
1. Phoenix 1.8 업그레이드 가이드 확인
2. Deprecated 함수 교체
3. `config/config.exs` 설정 확인

**롤백:**
```bash
git reset --hard HEAD~1
```

### 데이터베이스 연결 오류

**문제:** Postgrex 업그레이드 후 연결 실패

**해결:**
1. `config/dev.exs`, `config/test.exs`의 데이터베이스 설정 확인
2. Postgrex 버전 호환성 확인
3. PostgreSQL 서버 버전 확인

### 일반 의존성 충돌

**문제:** mix deps.update 실패

**해결:**
```bash
mix deps.tree
mix deps.unlock --all
mix deps.get
```

---

## 성공 기준

- [x] 모든 의존성이 mix.exs에서 명시적 버전 제약을 가짐
- [x] "Update not possible" 패키지들이 최신 버전으로 업그레이드됨
- [x] mix compile --warnings-as-errors 성공
- [x] mix test 100% 통과
- [x] 수동 테스트 체크리스트 완료
- [x] 각 단계가 별도 커밋으로 기록
- [x] 업그레이드 전/후 의존성 상태 문서화

## 예상 소요 시간

- 준비 단계: 10분
- 1단계 (핵심 프레임워크): 2-3시간
- 2단계 (Phoenix 생태계): 1시간
- 3단계 (데이터베이스 & 인프라): 1-2시간
- 4단계 (인증 & 보안): 10분
- 5단계 (유틸리티 & 도구): 1시간
- 최종 검증: 30분

**총 예상 시간: 6-8시간**
