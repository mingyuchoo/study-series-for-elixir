---
title: "Phoenix LiveView 기본 가이드"
author: "김철수"
tags: ["elixir", "phoenix", "liveview"]
thumbnail: "/images/thumbnails/phoenix-liveview-basics.jpg"
summary: "Phoenix LiveView의 기본 개념과 사용법을 알아봅니다. 실시간 웹 애플리케이션을 쉽게 구축하는 방법을 단계별로 설명합니다."
published_at: 2024-01-15T09:00:00Z
is_popular: true
---

# Phoenix LiveView 기본 가이드

Phoenix LiveView는 Elixir와 Phoenix 프레임워크를 사용하여 실시간 인터랙티브 웹 애플리케이션을 구축할 수 있게 해주는 강력한 라이브러리입니다.

## Phoenix LiveView란?

LiveView는 서버 사이드 렌더링과 클라이언트 사이드의 인터랙티비티를 결합한 혁신적인 접근 방식입니다. JavaScript를 거의 사용하지 않고도 실시간 웹 애플리케이션을 만들 수 있습니다.

### 주요 특징

- **서버 사이드 렌더링**: 모든 로직이 서버에서 실행됩니다
- **실시간 업데이트**: WebSocket을 통한 빠른 상태 동기화
- **적은 JavaScript**: 프론트엔드 복잡성 감소
- **SEO 친화적**: 서버 사이드 렌더링으로 검색 엔진 최적화

## LiveView 시작하기

LiveView를 사용하기 위해서는 먼저 Phoenix 프로젝트를 생성해야 합니다.

```elixir
mix phx.new my_app --live
cd my_app
mix ecto.create
mix phx.server
```

### 첫 번째 LiveView 만들기

간단한 카운터 LiveView를 만들어보겠습니다.

```elixir
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("decrement", _params, socket) do
    {:noreply, update(socket, :count, &(&1 - 1))}
  end
end
```

## 상태 관리

LiveView에서 상태는 `socket.assigns`에 저장됩니다. `mount/3` 함수에서 초기 상태를 설정하고, 이벤트 핸들러에서 상태를 업데이트합니다.

### 이벤트 처리

사용자 인터랙션은 `phx-click`, `phx-change`, `phx-submit` 등의 바인딩을 통해 처리됩니다.

```heex
<div>
  <h1>카운터: <%= @count %></h1>
  <button phx-click="increment">증가</button>
  <button phx-click="decrement">감소</button>
</div>
```

## 성능 최적화

LiveView는 기본적으로 매우 효율적이지만, 몇 가지 최적화 기법을 적용하면 더 나은 성능을 얻을 수 있습니다.

- **Temporary assigns**: 일회성 데이터는 임시 할당으로 처리
- **Live components**: 재사용 가능한 컴포넌트로 분리
- **Debouncing**: 빈번한 이벤트는 디바운싱 적용

## 결론

Phoenix LiveView는 현대적인 웹 애플리케이션 개발을 혁신적으로 단순화합니다. Elixir의 강력한 동시성 모델과 결합하여, 확장 가능하고 유지보수하기 쉬운 실시간 애플리케이션을 만들 수 있습니다.

다음 포스트에서는 LiveView의 고급 기능들을 살펴보겠습니다.
