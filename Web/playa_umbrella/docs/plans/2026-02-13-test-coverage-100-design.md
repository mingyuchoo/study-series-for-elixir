# 테스트 커버리지 100% 달성 설계

**작성일:** 2026-02-13
**목표:** 모든 앱(playa, auth, productivity)의 테스트 커버리지를 100%로 달성

## 1. 전체 아키텍처 및 테스트 전략

### 목표
모든 파일의 테스트 커버리지를 100%로 만들되, 각 파일의 특성에 맞는 테스트 전략을 적용합니다.

### 전체 워크플로우
```
1. 각 파일 분석 → 2. 테스트 작성 → 3. 커버리지 검증 → 4. 다음 파일로 이동
```

### 파일별 우선순위 및 이유

| 순위 | 파일 | 현재 커버리지 | 예상 난이도 | 이유 |
|------|------|---------------|-------------|------|
| 1 | `health_check.ex` | 0% | ⭐ 쉬움 | 단순한 DB 연결 체크 로직 |
| 2 | `accounts_fixtures.ex` | 78.5% | ⭐ 쉬움 | 테스트 헬퍼, 누락된 edge case만 추가 |
| 3 | `accounts.ex` | 43.7% | ⭐⭐ 보통 | Facade 패턴, 모든 defdelegate 호출 검증 |
| 4 | `users.ex` | 96.1% | ⭐ 쉬움 | 거의 완성, 1줄만 커버 |
| 5 | `user.ex` | 93.1% | ⭐ 쉬움 | 거의 완성, 2줄만 커버 |
| 6 | `auth/application.ex` | 0% | ⭐⭐⭐ 어려움 | OTP Application 통합 테스트 |
| 7 | `productivity/application.ex` | 0% | ⭐⭐⭐ 어려움 | OTP Application 통합 테스트 |

### 테스트 검증 방법
각 파일마다:
1. **테스트 작성 완료 후:** `mix test apps/[app_name]/test/path/to/test_file.exs` 실행
2. **전체 커버리지 확인:** `make test` 실행하여 해당 파일이 100%인지 확인
3. **커밋:** 각 파일 작업 완료 후 개별 커밋

## 2. 파일별 테스트 전략

### 1. `lib/playa/health_check.ex` (0% → 100%)

**현재 코드:**
```elixir
def server_healthy? do
  case Accounts.get_role!(@role_id) do
    %Role{} -> true
    _ -> false
  end
end
```

**테스트 전략:**
- ✅ **성공 케이스:** DB에 role_id=1이 존재할 때 `true` 반환
- ✅ **실패 케이스:** role_id=1이 없을 때 예외 발생 (Ecto.NoResultsError)
- **테스트 파일:** `test/playa/health_check_test.exs` (신규 생성)

---

### 2. `test/support/fixtures/accounts_fixtures.ex` (78.5% → 100%)

**누락 예상 라인:**
- `unique_user_email/0` 호출
- `valid_user_password/0` 호출
- `unique_role_name/0` 호출

**테스트 전략:**
- 각 헬퍼 함수가 유니크한 값을 생성하는지 검증
- **테스트 파일:** `test/support/fixtures/accounts_fixtures_test.exs` (신규 생성)

---

### 3. `lib/playa/accounts.ex` (43.7% → 100%)

**문제:** 이 파일은 모든 함수가 `defdelegate`로 구성되어 있습니다. 27개의 미싱 라인은 호출되지 않은 delegate 함수들입니다.

**테스트 전략:**
- 기존 `test/playa/accounts_test.exs`에 누락된 함수 호출 추가
- 각 delegate 함수가 올바른 하위 모듈 함수로 위임되는지 검증
- 예상 누락 함수들:
  - `list_users_by_role_id/1`
  - `update_user_nickname/2`
  - `change_user_nickname/1,2`
  - `list_remain_roles_by_user_id/1`
  - `increase_user_count/1`
  - `decrease_user_count/1`
  - `list_role_user_not_user_id/1`
  - 기타 role_user 관련 함수들

---

### 4. `lib/playa/accounts/users.ex` (96.1% → 100%)

**1개 미싱 라인 예상:**
- 아마도 특정 edge case 또는 조건 분기의 else 절

**테스트 전략:**
- HTML 커버리지 리포트 확인: `open apps/playa/cover/excoveralls.html`
- 정확한 미싱 라인 파악 후 해당 케이스 테스트 추가

---

### 5. `lib/playa/accounts/user.ex` (93.1% → 100%)

**2개 미싱 라인 예상:**
- `valid_password?/2`의 두 번째 함수 절 (invalid 케이스)

**테스트 전략:**
- 사용자가 없거나 비밀번호가 빈 문자열일 때 테스트
- `test/playa/accounts/users_test.exs` 또는 별도 user schema 테스트에 추가

---

### 6-7. Application 모듈들 (0% → 100%)

**파일:**
- `apps/auth/lib/auth/application.ex`
- `apps/productivity/lib/productivity/application.ex`

**테스트 전략:**
- `start/2` 함수 호출하여 Supervisor가 정상 시작되는지 검증
- 자식 프로세스 스펙이 올바른지 검증
- **주의사항:** 테스트 환경에서 이미 시작된 앱과 충돌하지 않도록 주의

**테스트 패턴:**
```elixir
test "starts supervision tree successfully" do
  assert {:ok, _pid} = Application.start(:normal, [])
end
```

## 3. 실행 순서 및 에러 핸들링

### 테스트 실행 플로우

각 파일마다 다음 단계를 반복합니다:

```
1. HTML 커버리지 리포트 확인
   ↓
2. 미싱 라인 정확히 파악
   ↓
3. 테스트 작성
   ↓
4. 개별 테스트 실행
   ↓
5. 전체 테스트 실행 (make test)
   ↓
6. 커버리지 100% 확인
   ↓
7. Git 커밋
   ↓
8. 다음 파일로 이동
```

### 커버리지 리포트 확인 방법

**HTML 리포트 위치:**
- `apps/playa/cover/excoveralls.html` (또는 `cover/` 디렉토리)
- `apps/auth/cover/`
- `apps/productivity/cover/`

**확인 명령:**
```bash
# 전체 테스트 + 커버리지 생성
make test

# 특정 앱만
cd apps/playa && mix test --cover
```

### 에러 핸들링 전략

#### 시나리오 1: 테스트 작성 후 기존 테스트 실패
**원인:** 새 테스트가 기존 테스트의 DB 상태에 영향
**해결:**
- 각 테스트에 `setup` 블록으로 독립적인 데이터 준비
- `DataCase`의 sandbox 모드 확인
- 필요시 `async: false` 설정

#### 시나리오 2: 커버리지가 여전히 100%가 안 됨
**원인:** 미싱 라인을 잘못 파악했거나 다른 조건 필요
**해결:**
1. HTML 리포트 재확인
2. 해당 함수의 모든 분기(if/case/cond) 검토
3. edge case 추가 (nil, 빈 값, 경계값 등)

#### 시나리오 3: Application 테스트 시 충돌
**원인:** 테스트 환경에서 이미 앱이 시작됨
**해결:**
- `Application.stop/1` 후 `Application.start/2` 호출
- 또는 Supervisor spec만 검증하는 방식으로 변경
- 필요시 격리된 프로세스에서 테스트

#### 시나리오 4: HealthCheck 테스트 시 role_id=1 없음
**원인:** 테스트 DB에 초기 데이터 없음
**해결:**
- 테스트 setup에서 `role_fixture(%{id: 1})` 생성
- 또는 `Repo.insert!(%Role{id: 1, ...})` 직접 삽입

### 롤백 전략

각 파일이 독립적으로 커밋되므로:
- 문제 발생 시 해당 파일의 커밋만 revert
- 다른 파일 작업은 영향 없음
- 필요시 나중에 재시도

## 4. 테스트 품질 기준 및 완료 조건

### 테스트 품질 기준

#### 1. 테스트 독립성
- 각 테스트는 다른 테스트에 의존하지 않음
- `setup` 블록으로 필요한 데이터 준비
- 테스트 순서와 무관하게 통과해야 함

#### 2. 명확한 테스트 이름
```elixir
# 좋은 예
test "server_healthy?/0 returns true when role exists"
test "server_healthy?/0 raises when role does not exist"

# 나쁜 예
test "health check"
test "test 1"
```

#### 3. Arrange-Act-Assert 패턴
```elixir
test "example" do
  # Arrange: 데이터 준비
  role = role_fixture(%{id: 1})

  # Act: 함수 실행
  result = HealthCheck.server_healthy?()

  # Assert: 결과 검증
  assert result == true
end
```

#### 4. Edge Case 커버리지
각 함수마다 다음을 테스트:
- ✅ 정상 케이스 (happy path)
- ✅ 에러 케이스 (nil, 빈 값, 잘못된 타입)
- ✅ 경계값 (있다면)

### 완료 조건 (Definition of Done)

각 파일마다 다음 조건을 **모두** 충족해야 다음 파일로 이동:

#### ✅ 체크리스트
1. [ ] 테스트 코드 작성 완료
2. [ ] 개별 테스트 파일 실행 성공
3. [ ] `make test` 실행 시 모든 테스트 통과
4. [ ] 해당 파일 커버리지 100% 확인
5. [ ] 다른 파일의 커버리지가 하락하지 않음
6. [ ] Git 커밋 완료 (의미 있는 커밋 메시지)

#### 커밋 메시지 형식
```
test(playa): add tests for HealthCheck to achieve 100% coverage

- Add test for server_healthy?/0 success case
- Add test for server_healthy?/0 error case
- Coverage: 0% -> 100%
```

### 최종 검증

모든 파일 작업 완료 후:

```bash
# 전체 테스트 실행
make test

# 결과 확인
# - playa: 100% coverage
# - auth: 100% coverage
# - productivity: 100% coverage
```

**기대 결과:**
```
==> playa
[TOTAL]  100.0%

==> auth
|     100.00% | Total

==> productivity
|     100.00% | Total
```

### 주의사항

1. **기존 테스트를 깨뜨리지 않기**
   - 새 테스트 추가만, 기존 테스트 수정 최소화

2. **불필요한 테스트 작성하지 않기**
   - 커버리지 100%만 목표, 중복 테스트 배제

3. **테스트 가독성 유지**
   - 복잡한 setup은 헬퍼 함수로 추출

## 5. 작업 순서 요약

1. ✅ `lib/playa/health_check.ex` (0% → 100%)
2. ✅ `test/support/fixtures/accounts_fixtures.ex` (78.5% → 100%)
3. ✅ `lib/playa/accounts.ex` (43.7% → 100%)
4. ✅ `lib/playa/accounts/users.ex` (96.1% → 100%)
5. ✅ `lib/playa/accounts/user.ex` (93.1% → 100%)
6. ✅ `apps/auth/lib/auth/application.ex` (0% → 100%)
7. ✅ `apps/productivity/lib/productivity/application.ex` (0% → 100%)

---

**승인일:** 2026-02-13
**다음 단계:** Implementation Plan 작성
