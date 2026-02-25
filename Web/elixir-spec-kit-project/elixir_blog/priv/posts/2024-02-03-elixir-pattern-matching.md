---
title: "Elixir 패턴 매칭 완벽 가이드"
author: "이영희"
tags: ["elixir", "functional-programming", "beginner"]
thumbnail: "/images/thumbnails/elixir-pattern-matching.jpg"
summary: "Elixir의 가장 강력한 기능 중 하나인 패턴 매칭을 상세히 알아봅니다. 실전 예제와 함께 설명합니다."
published_at: 2024-02-03T10:30:00Z
is_popular: true
---

# Elixir 패턴 매칭 완벽 가이드

패턴 매칭은 Elixir의 핵심 기능으로, 데이터 구조를 분해하고 검사하는 강력한 방법을 제공합니다.

## 패턴 매칭이란?

Elixir에서 `=` 연산자는 단순한 할당이 아니라 매치 연산자입니다. 좌변과 우변이 같은 구조를 가질 때만 성공합니다.

```elixir
# 기본 매칭
x = 1  # x는 1
1 = x  # 성공: 1 == 1

# 리스트 매칭
[head | tail] = [1, 2, 3, 4]
# head = 1, tail = [2, 3, 4]
```

## 튜플 매칭

튜플은 고정된 크기의 데이터 구조로, 패턴 매칭과 완벽하게 어울립니다.

```elixir
{:ok, result} = {:ok, "성공"}
# result = "성공"

{:error, reason} = {:error, "실패"}
# reason = "실패"
```

### 함수 헤드에서의 패턴 매칭

```elixir
defmodule Math do
  def calculate({:add, a, b}), do: a + b
  def calculate({:subtract, a, b}), do: a - b
  def calculate({:multiply, a, b}), do: a * b
end

Math.calculate({:add, 5, 3})  # 8
```

## 맵 매칭

맵의 패턴 매칭은 특정 키의 존재를 확인하고 값을 추출할 때 유용합니다.

```elixir
%{name: name, age: age} = %{name: "철수", age: 30, city: "서울"}
# name = "철수", age = 30
```

## 핀 연산자

`^` 핀 연산자는 변수의 현재 값과 매칭하도록 강제합니다.

```elixir
x = 1
^x = 1  # 성공
^x = 2  # 매칭 실패
```

## 가드 절

가드 절을 사용하면 패턴 매칭에 추가 조건을 붙일 수 있습니다.

```elixir
defmodule Number do
  def classify(n) when n < 0, do: "음수"
  def classify(n) when n == 0, do: "영"
  def classify(n) when n > 0, do: "양수"
end
```

## 실전 활용 예제

### API 응답 처리

```elixir
case HTTPoison.get(url) do
  {:ok, %{status_code: 200, body: body}} ->
    parse_body(body)

  {:ok, %{status_code: 404}} ->
    {:error, :not_found}

  {:error, %{reason: reason}} ->
    {:error, reason}
end
```

### 재귀 함수

```elixir
defmodule List do
  def sum([]), do: 0
  def sum([head | tail]), do: head + sum(tail)
end
```

## 결론

패턴 매칭은 Elixir 코드를 간결하고 표현력 있게 만들어줍니다. 이를 잘 활용하면 복잡한 로직도 명확하게 표현할 수 있습니다.
