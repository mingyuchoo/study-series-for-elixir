---
title: "Elixir 모듈과 함수의 완벽한 이해"
author: "이영희"
tags: ["elixir", "programming", "functional"]
thumbnail: "/images/thumbnails/elixir-modules-functions.jpg"
summary: "Elixir의 모듈 시스템과 함수 정의 방식을 깊이 있게 학습합니다. 함수형 프로그래밍의 핵심을 마스터하세요."
published_at: 2024-02-10T10:30:00Z
is_popular: false
---

Elixir는 함수형 프로그래밍 언어로서, 모듈과 함수는 코드의 기본 단위입니다. 이번 글에서 이들을 완벽하게 이해해봅시다.

## 모듈의 기본 개념

모듈은 함수들을 그룹화하는 방법입니다. Elixir에서는 모든 함수가 모듈 안에 정의되어야 합니다.

```elixir
defmodule Math do
  def add(a, b) do
    a + b
  end

  def multiply(a, b) do
    a * b
  end
end

# 호출
Math.add(5, 3)  # 8
Math.multiply(4, 2)  # 8
```

모듈은 `defmodule` 키워드로 정의되며, 관례적으로 파스칼 케이스를 사용합니다.

## 함수의 여러 형태

### 한 줄 함수

```elixir
defmodule String do
  def reverse(str), do: String.reverse(str)
  def length(str), do: String.length(str)
end
```

간단한 함수는 한 줄로 간결하게 작성할 수 있습니다.

### 패턴 매칭을 이용한 함수 오버로딩

```elixir
defmodule Greeting do
  def greet("English"), do: "Hello"
  def greet("Korean"), do: "안녕하세요"
  def greet("Spanish"), do: "Hola"
  def greet(_), do: "Hi there"
end
```

### 기본값 설정

```elixir
defmodule Config do
  def get(key, default \\ nil) do
    Application.get_env(:myapp, key, default)
  end
end
```

## 고급 함수 개념

### 프라이빗 함수

```elixir
defmodule Process do
  def process(data) do
    validate_input(data)
    |> transform()
  end

  defp validate_input(data) do
    if is_nil(data), do: raise "Invalid input"
    data
  end

  defp transform(data) do
    String.upcase(data)
  end
end
```

`defp`로 정의한 함수는 모듈 내부에서만 사용할 수 있습니다.

### 고차 함수

Elixir는 함수를 인자로 받을 수 있습니다.

```elixir
defmodule List do
  def map(list, func) do
    Enum.map(list, func)
  end
end

# 사용
List.map([1, 2, 3], fn x -> x * 2 end)  # [2, 4, 6]
```

## 함수형 프로그래밍 패턴

### 파이프 연산자

```elixir
defmodule Pipeline do
  def process(data) do
    data
    |> validate()
    |> transform()
    |> save()
  end
end
```

파이프 연산자 `|>`는 이전 함수의 결과를 다음 함수의 첫 번째 인자로 전달합니다.

### 누적 함수

```elixir
defmodule Counter do
  def count(list, acc \\ 0)

  def count([], acc), do: acc
  def count([_|tail], acc) do
    count(tail, acc + 1)
  end
end
```

## 결론

Elixir의 모듈과 함수 시스템은 함수형 프로그래밍의 강력함을 보여줍니다. 패턴 매칭, 파이프 연산자, 고차 함수 등의 개념을 잘 이해하면 우아하고 효율적인 Elixir 코드를 작성할 수 있습니다.