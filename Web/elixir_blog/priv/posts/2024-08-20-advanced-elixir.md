---
title: "고급 Elixir 패턴과 기법"
author: "강민지"
tags: ["elixir", "advanced", "programming"]
thumbnail: "/images/thumbnails/advanced-elixir.jpg"
summary: "메타프로그래밍, 매크로, 프로토콜 등 고급 Elixir 기능을 배웁니다."
published_at: 2024-08-20T11:00:00Z
is_popular: false
---

Elixir의 고급 기능들을 마스터하면 더 강력하고 유연한 코드를 작성할 수 있습니다.

## 매크로 작성

```elixir
defmodule LogMacro do
  defmacro log(message) do
    quote do
      require Logger
      Logger.info(unquote(message))
    end
  end

  defmacro debug(expr) do
    quote do
      result = unquote(expr)
      IO.inspect(result, label: unquote(Macro.to_string(expr)))
      result
    end
  end
end

# 사용
defmodule MyModule do
  import LogMacro

  def example do
    log("Starting process")
    debug(1 + 2)
  end
end
```

## 프로토콜 정의

```elixir
defprotocol Serializable do
  @doc "Serialize a value"
  def serialize(value)
end

defimpl Serializable, for: String do
  def serialize(string) do
    {:string, string}
  end
end

defimpl Serializable, for: Integer do
  def serialize(integer) do
    {:integer, integer}
  end
end

defimpl Serializable, for: List do
  def serialize(list) do
    {:list, Enum.map(list, &Serializable.serialize/1)}
  end
end

# 사용
Serializable.serialize("hello")     # {:string, "hello"}
Serializable.serialize(42)          # {:integer, 42}
Serializable.serialize([1, 2, 3])  # {:list, [{:integer, 1}, {:integer, 2}, {:integer, 3}]}
```

## 고급 패턴 매칭

```elixir
defmodule PatternMatching do
  def process_user(%{age: age, name: name} = user) when age >= 18 do
    {:adult, user}
  end

  def process_user(%{age: age} = user) when age < 18 do
    {:minor, user}
  end

  def extract_nested({:ok, %{"data" => %{"value" => value}}}) do
    value
  end

  def extract_nested(_), do: nil

  # 가드절 조합
  def validate(value)
  when is_binary(value) and byte_size(value) > 0 and byte_size(value) < 100 do
    {:ok, value}
  end

  def validate(_), do: {:error, "Invalid"}
end
```

## 메타프로그래밍

```elixir
defmodule QueryBuilder do
  defmacro create_query(name, fields) do
    quote do
      def unquote(String.to_atom("query_#{name}"))(params) do
        unquote(fields)
        |> Enum.filter(fn field -> params[field] end)
        |> Enum.reduce("", fn field, acc ->
          acc <> "#{field}=#{params[field]} AND "
        end)
      end
    end
  end
end

defmodule UserQueries do
  import QueryBuilder

  create_query(:user, [:id, :name, :email])
  # 결과: query_user(params) 함수 생성
end
```

## 프로세스와 감시

```elixir
defmodule HealthCheck do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    schedule_check()
    {:ok, %{status: :ok, last_check: DateTime.utc_now()}}
  end

  def handle_info(:check, state) do
    status = perform_health_check()
    schedule_check()
    {:noreply, %{state | status: status, last_check: DateTime.utc_now()}}
  end

  defp schedule_check do
    Process.send_after(self(), :check, 30_000)
  end

  defp perform_health_check do
    case check_database() do
      :ok -> :ok
      _ -> :unhealthy
    end
  end

  defp check_database do
    # 데이터베이스 헬스 체크
    :ok
  end
end
```

## 동적 모듈 생성

```elixir
defmodule DynamicModuleCreator do
  def create_module(name, functions) do
    quoted = quote do
      unquote_splicing(
        Enum.map(functions, fn {fname, arity, body} ->
          create_function(fname, arity, body)
        end)
      )
    end

    Module.create(
      String.to_atom("Elixir.#{name}"),
      quoted,
      Macro.Env.location(__ENV__)
    )
  end

  defp create_function(name, arity, body) do
    args = Enum.map(1..arity, &Macro.var(:"arg#{&1}", nil))

    quote do
      def unquote(name)(unquote_splicing(args)) do
        unquote(body)
      end
    end
  end
end
```

## ETS 고급 사용

```elixir
defmodule AdvancedETS do
  def create_ordered_set do
    :ets.new(:my_ordered_set, [:ordered_set, :public])
  end

  def batch_insert(table, records) do
    :ets.insert(table, records)
  end

  def select_with_pattern(table, pattern) do
    :ets.select(table, [{pattern, [], [:"$_"]}])
  end

  def atomic_update(table, key, fun) do
    :ets.update_counter(table, key, fun)
  end
end
```

## 결론

고급 Elixir 기능들은 매우 강력하지만 신중하게 사용해야 합니다. 매크로, 프로토콜, 메타프로그래밍을 올바르게 사용하면 우아하고 확장 가능한 코드를 작성할 수 있습니다.