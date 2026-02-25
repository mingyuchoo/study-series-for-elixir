---
title: "함수형 프로그래밍 입문"
author: "정수진"
tags: ["programming", "functional", "elixir"]
thumbnail: "/images/thumbnails/functional-programming.jpg"
summary: "함수형 프로그래밍의 핵심 개념을 이해하고 Elixir로 실습해봅니다."
published_at: 2024-02-01T09:00:00Z
is_popular: false
---

# 함수형 프로그래밍 입문

함수형 프로그래밍은 부작용을 최소화하고 불변성을 강조하는 프로그래밍 패러다임입니다.

## 순수 함수

순수 함수는 같은 입력에 대해 항상 같은 출력을 반환하며, 부작용이 없습니다.

```elixir
# 순수 함수
def add(a, b), do: a + b

# 비순수 함수 (IO 부작용)
def add_and_print(a, b) do
  result = a + b
  IO.puts(result)  # 부작용!
  result
end
```

## 불변성

Elixir의 모든 데이터는 불변입니다.

```elixir
list = [1, 2, 3]
new_list = [0 | list]  # 새로운 리스트 생성
# list는 여전히 [1, 2, 3]
```

## 고차 함수

함수를 인자로 받거나 반환하는 함수입니다.

```elixir
Enum.map([1, 2, 3], fn x -> x * 2 end)
# [2, 4, 6]

Enum.filter([1, 2, 3, 4], fn x -> rem(x, 2) == 0 end)
# [2, 4]
```

## 파이프 연산자

파이프 연산자로 함수 체이닝을 읽기 쉽게 만듭니다.

```elixir
[1, 2, 3, 4, 5]
|> Enum.map(&(&1 * 2))
|> Enum.filter(&(&1 > 5))
|> Enum.sum()
```

## 패턴 매칭

Elixir의 가장 강력한 기능 중 하나입니다.

```elixir
defmodule Math do
  def factorial(0), do: 1
  def factorial(n) when n > 0 do
    n * factorial(n - 1)
  end
end
```

## 재귀

함수형 프로그래밍에서 반복은 주로 재귀로 표현됩니다.

```elixir
def sum([]), do: 0
def sum([head | tail]), do: head + sum(tail)
```

## 결론

함수형 프로그래밍은 코드를 더 예측 가능하고 테스트하기 쉽게 만듭니다. Elixir는 함수형 패러다임을 배우기에 최적의 언어입니다.
