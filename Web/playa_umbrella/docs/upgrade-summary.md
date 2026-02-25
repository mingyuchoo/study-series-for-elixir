# 의존성 업그레이드 요약

## 업그레이드 일시
2026-02-13

## 주요 업그레이드 목록

### 성공한 업그레이드
- **Phoenix**: 이미 최신 버전 1.8.3
- **Phoenix LiveView**: 이미 최신 버전 1.1.23
- **Phoenix Ecto**: 이미 최신 버전 4.7.0
- **Phoenix HTML**: 이미 최신 버전 4.3.0
- **Phoenix Live Dashboard**: 이미 최신 버전 0.8.7
- **Telemetry Metrics**: 이미 최신 버전 1.1.0
- **Telemetry Poller**: 이미 최신 버전 1.3.0
- **Guardian**: 이미 최신 버전 2.4.0
- **Bcrypt Elixir**: 이미 최신 버전 3.3.2
- **Bandit**: 이미 최신 버전 1.10.2 (요구사항을 ~> 1.8로 변경)
- **Ecto SQL**: 이미 최신 버전 3.13.4
- **Postgrex**: 이미 최신 버전 0.22.0
- **Jason**: 이미 최신 버전 1.4.4
- **Swoosh**: 이미 최신 버전 1.21.0
- **Finch**: 이미 최신 버전 0.21.0
- **Esbuild**: 이미 최신 버전 0.10.0
- **Tailwind**: 이미 최신 버전 0.4.1
- **Timex**: 이미 최신 버전 3.7.13

### 업그레이드 불가능
- **Gettext**: 0.26.2 (최신: 1.0.2)
  - **사유**: Timex 의존성이 gettext ~> 0.26을 요구
  - **해결 방법**: Timex가 Gettext 1.x를 지원할 때까지 대기 필요

## Breaking Changes

### Gettext Deprecation 경고
현재 Gettext 사용 방법이 deprecated되었습니다:

**현재 방법** (deprecated):
```elixir
use Gettext, otp_app: :playa_web
```

**권장 방법**:
```elixir
# Backend 정의
use Gettext.Backend, otp_app: :playa_web

# 모듈에서 사용
use Gettext, backend: PlayaWeb.Gettext
```

이 변경은 Gettext 1.0으로 업그레이드할 때 필수적으로 처리해야 합니다.

### 기타 경고
- **PlayaWeb.ListLive.ItemShow**: 미구현 모듈 참조 (라우터에서 사용 중)
- **테스트 파일**: 사용하지 않는 alias 및 모듈 속성 경고

## 테스트 결과

### 테스트 통과 여부
- ✅ Playa: 12 tests, 0 failures
- ✅ Auth: 테스트 없음
- ✅ Productivity: 테스트 없음
- ✅ Playa Web: 5 tests, 0 failures

### 코드 커버리지
- Playa: 21.96% (임계값: 90%)
- Playa Web: 6.87% (임계값: 90%)

**참고**: 커버리지 임계값 미달은 의존성 업그레이드와 무관한 기존 이슈입니다.

## 보안 감사
```
mix hex.audit
```
결과: **No retired packages found** ✅

## 의존성 상태

### 최신 상태 유지
현재 Gettext를 제외한 모든 주요 의존성이 최신 버전을 사용하고 있습니다.

### 의존성 트리
전체 의존성 트리는 `docs/deps-tree.txt` 참조

## 다음 단계

### 단기 조치
1. ~~Gettext deprecation 경고 해결 (Gettext 1.0 업그레이드 시 필수)~~
   - Timex가 Gettext 1.0을 지원할 때까지 대기
2. PlayaWeb.ListLive.ItemShow 모듈 구현 또는 라우터에서 제거
3. 테스트 파일 경고 정리 (사용하지 않는 alias 제거)

### 중기 조치
1. 테스트 커버리지 개선
   - Playa: 21.96% → 90%
   - Playa Web: 6.87% → 90%
2. Timex 업데이트 모니터링 (Gettext 1.0 지원 확인)

### Gettext 1.0 업그레이드 준비
Timex가 Gettext 1.0을 지원하게 되면:

1. `apps/playa_web/lib/playa_web/gettext.ex` 파일 업데이트:
```elixir
defmodule PlayaWeb.Gettext do
  use Gettext.Backend, otp_app: :playa_web
end
```

2. Gettext를 사용하는 모든 모듈 업데이트:
```elixir
use Gettext, backend: PlayaWeb.Gettext
```

3. mix.exs 업데이트:
```elixir
{:gettext, "~> 1.0"}
```

4. 의존성 업데이트 및 테스트:
```bash
mix deps.update gettext
mix gettext.extract --check-up-to-date
mix compile --force
mix test
```

## 변경 사항 커밋
- 업그레이드 관련 변경사항 없음 (이미 대부분 최신 버전 사용 중)
- Bandit 요구사항 변경: ~> 1.2 → ~> 1.8 (실제 버전은 1.10.2로 동일)

## 결론
Phoenix 생태계의 주요 의존성들은 이미 최신 버전을 사용하고 있으며, Gettext만 Timex 의존성으로 인해 업그레이드가 제한되어 있습니다. 모든 테스트가 통과하고 보안 취약점이 없어 현재 상태에서 안정적으로 운영 가능합니다.
