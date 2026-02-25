# Context 패턴 리팩토링 설계

## 목적

컨트롤러에서 `Repo`를 직접 호출하는 현재 구조를 Phoenix Context 패턴으로 리팩토링하여 비즈니스 로직을 캡슐화한다.

## 변경 범위

### 1. Discuss.Topics Context 생성

`lib/discuss/topics.ex` - 공개 API:
- `list_topics/0`, `get_topic!/1`, `create_topic/1`, `update_topic/2`, `delete_topic/1`, `change_topic/2`

`lib/discuss/topics/topic.ex` - 기존 `lib/discuss/topic.ex`에서 이동

### 2. Discuss.Admin Context 생성

`lib/discuss/admin.ex` - 공개 API:
- `list_users/0`, `get_user!/1`, `create_user/1`, `update_user/2`, `delete_user/1`, `change_user/1`

`lib/discuss/admin/user.ex` - 신규 Ecto 스키마

### 3. TopicController 리팩토링

`Repo` 직접 호출을 `Discuss.Topics` Context 호출로 대체

### 4. 테스트

- `test/discuss/topics_test.exs` + `test/support/fixtures/topics_fixtures.ex` 신규
- `test/discuss_web/controllers/topic_controller_test.exs` 신규
- 기존 `admin_test.exs` + `admin_fixtures.ex` 통과 확인

### 변경하지 않는 것

라우터, HEEx 템플릿, 설정 파일, Repo, DiscussWeb 모듈
