---
title: "Elixir에서의 타입 안전성"
author: "박민수"
tags: ["elixir", "programming", "types"]
thumbnail: "/images/thumbnails/type-safety.jpg"
summary: "Dialyzer와 Typespecs을 이용한 타입 검사와 안전성을 강화합니다."
published_at: 2024-05-25T11:30:00Z
is_popular: true
---

Elixir는 동적 타입 언어이지만, Dialyzer를 통해 정적 타입 검사를 할 수 있습니다.

## Typespec 정의

```elixir
defmodule UserService do
  @type user :: %{
    id: integer(),
    email: String.t(),
    name: String.t(),
    age: non_neg_integer()
  }

  @spec create_user(map()) :: {:ok, user()} | {:error, String.t()}
  def create_user(attrs) do
    with :ok <- validate_attrs(attrs),
         {:ok, user} <- insert_user(attrs) do
      {:ok, user}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec validate_attrs(map()) :: :ok | {:error, String.t()}
  defp validate_attrs(%{"email" => email, "name" => name}) do
    cond do
      not is_binary(email) -> {:error, "Email must be a string"}
      not is_binary(name) -> {:error, "Name must be a string"}
      true -> :ok
    end
  end

  @spec validate_attrs(any()) :: {:error, String.t()}
  defp validate_attrs(_) do
    {:error, "Invalid attributes"}
  end

  @spec insert_user(map()) :: {:ok, user()} | {:error, String.t()}
  defp insert_user(attrs) do
    {:ok, %{id: 1, email: attrs["email"], name: attrs["name"], age: 0}}
  end
end
```

## 기본 타입

```elixir
defmodule TypeExamples do
  # 기본 타입들
  @spec add_numbers(integer(), integer()) :: integer()
  def add_numbers(a, b) do
    a + b
  end

  @spec concat_strings(String.t(), String.t()) :: String.t()
  def concat_strings(a, b) do
    a <> b
  end

  # 리스트 타입
  @spec first_element(list()) :: any() | nil
  def first_element([head | _]), do: head
  def first_element([]), do: nil

  # 타입 보장된 리스트
  @spec sum_integers(list(integer())) :: integer()
  def sum_integers(list) do
    Enum.sum(list)
  end

  # 맵 타입
  @spec get_user_name(map()) :: String.t()
  def get_user_name(%{"name" => name}) do
    name
  end
end
```

## 복잡한 타입

```elixir
defmodule ComplexTypes do
  @type status :: :ok | :error | :pending
  @type result(value) :: {:ok, value} | {:error, String.t()}

  @spec process(any()) :: result(String.t())
  def process(data) do
    case validate(data) do
      {:ok, validated} -> {:ok, "Processed: #{validated}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec validate(any()) :: result(binary())
  defp validate(value) when is_binary(value) do
    {:ok, value}
  end

  defp validate(_) do
    {:error, "Not a binary"}
  end

  @type person :: %{
    name: String.t(),
    age: non_neg_integer(),
    email: String.t() | nil
  }

  @spec create_person(String.t(), non_neg_integer()) :: person()
  def create_person(name, age) do
    %{name: name, age: age, email: nil}
  end
end
```

## Dialyzer 실행

```bash
# mix.exs에 추가
def project do
  [
    app: :myapp,
    version: "0.1.0",
    elixir: "~> 1.14",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    dialyzer: [
      plt_add_apps: [:ex_unit, :mix],
      plt_add_deps: :transitive
    ]
  ]
end
```

```bash
# Dialyzer 실행
mix dialyzer

# 또는 incremental mode
mix dialyzer --incremental
```

## 타입 검사 결과 해석

```elixir
defmodule Examples do
  # 좋은 예: 타입이 명확함
  @spec double(integer()) :: integer()
  def double(x) do
    x * 2
  end

  # 잠재적 문제: 타입이 일치하지 않을 수 있음
  @spec unsafe_operation(any()) :: String.t()
  def unsafe_operation(value) do
    value <> "appended"  # value가 문자열이 아닐 수 있음
  end

  # 개선: 타입 검사 추가
  @spec safe_operation(String.t()) :: String.t()
  def safe_operation(value) when is_binary(value) do
    value <> "appended"
  end
end
```

## 문서와 함께하는 Typespec

```elixir
defmodule DocumentedService do
  @doc """
  사용자를 생성합니다.

  ## 파라미터
    * `attrs` - 사용자 속성 맵

  ## 반환값
    * `{:ok, user}` - 성공
    * `{:error, reason}` - 실패

  ## 예제
      iex> create_user(%{email: "test@example.com", name: "John"})
      {:ok, %{id: 1, email: "test@example.com", name: "John"}}
  """
  @spec create_user(map()) :: {:ok, map()} | {:error, String.t()}
  def create_user(attrs) do
    {:ok, %{id: 1}}
  end
end
```

## 커스텀 타입

```elixir
defmodule CustomTypes do
  @type user_id :: pos_integer()
  @type email :: String.t()
  @type status :: :active | :inactive | :suspended

  @spec get_user(user_id()) :: {:ok, map()} | {:error, String.t()}
  def get_user(id) when is_integer(id) and id > 0 do
    {:ok, %{id: id}}
  end

  @spec set_status(user_id(), status()) :: :ok
  def set_status(_id, status) when status in [:active, :inactive, :suspended] do
    :ok
  end
end
```

## 결론

Dialyzer와 Typespecs은 런타임 오류를 조기에 발견할 수 있게 해줍니다. 명확한 타입 정의는 코드의 신뢰성과 가독성을 높입니다.