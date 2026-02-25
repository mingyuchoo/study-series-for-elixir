---
title: "Elixir에서 효과적인 에러 처리"
author: "정수진"
tags: ["elixir", "programming", "error-handling"]
thumbnail: "/images/thumbnails/error-handling.jpg"
summary: "Elixir의 다양한 에러 처리 방식과 전략을 배웁니다."
published_at: 2024-04-10T09:00:00Z
is_popular: false
---

Elixir는 '실패해야 한다' 철학을 가지고 있습니다. 효과적인 에러 처리 전략을 알아봅시다.

## 기본 에러 처리

### 튜플 기반 응답

```elixir
defmodule UserService do
  def create_user(attrs) do
    with :ok <- validate_email(attrs),
         :ok <- validate_password(attrs),
         {:ok, user} <- Repo.insert(User.changeset(%User{}, attrs)) do
      {:ok, user}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, "Invalid input"}
    end
  end

  defp validate_email(%{"email" => email}) do
    if email =~ ~r/@/ do
      :ok
    else
      {:error, "Invalid email"}
    end
  end

  defp validate_password(%{"password" => pass}) when byte_size(pass) >= 8 do
    :ok
  end

  defp validate_password(_) do
    {:error, "Password too short"}
  end
end
```

### 예외 기반 처리

```elixir
defmodule DataProcessor do
  def process(data) do
    validate!(data)
    transform!(data)
    save!(data)
  catch
    :error, reason ->
      Logger.error("Processing failed: #{inspect(reason)}")
      {:error, "Processing failed"}
  end

  defp validate!(data) do
    if data == nil, do: raise "Data is nil"
    data
  end
end
```

## Result 타입 패턴

```elixir
defmodule Result do
  def ok(value), do: {:ok, value}
  def error(reason), do: {:error, reason}

  def map({:ok, value}, func), do: {:ok, func.(value)}
  def map({:error, reason}, _), do: {:error, reason}

  def flat_map({:ok, value}, func), do: func.(value)
  def flat_map({:error, reason}, _), do: {:error, reason}
end

# 사용
with {:ok, user} <- create_user(attrs),
     {:ok, email} <- send_confirmation(user),
     {:ok, _} <- log_signup(user) do
  {:ok, user}
else
  {:error, reason} -> {:error, reason}
end
```

## 에러 복구

### Retry 패턴

```elixir
defmodule Retry do
  def with_backoff(func, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    backoff = Keyword.get(opts, :backoff, 1000)

    do_retry(func, max_retries, backoff)
  end

  defp do_retry(func, 0, _), do: func.()

  defp do_retry(func, retries, backoff) do
    try do
      func.()
    catch
      :error, reason ->
        Process.sleep(backoff)
        do_retry(func, retries - 1, backoff * 2)
    end
  end
end

# 사용
Retry.with_backoff(
  fn -> fetch_remote_data() end,
  max_retries: 5,
  backoff: 1000
)
```

### Circuit Breaker 패턴

```elixir
defmodule CircuitBreaker do
  @moduledoc "Circuit breaker for fault tolerance"

  def call(service_name, func) do
    case get_state(service_name) do
      :open ->
        {:error, "Service unavailable"}
      :closed ->
        try do
          result = func.()
          record_success(service_name)
          result
        catch
          :error, reason ->
            record_failure(service_name)
            {:error, reason}
        end
      :half_open ->
        try do
          result = func.()
          reset(service_name)
          result
        catch
          :error, reason ->
            open(service_name)
            {:error, reason}
        end
    end
  end

  defp get_state(service_name) do
    case Agent.get(__MODULE__, fn state -> state[service_name] end) do
      nil -> :closed
      {status, _timestamp} -> status
    end
  end

  defp record_failure(service_name) do
    # 일정 횟수의 실패 후 차단
    Agent.update(__MODULE__, fn state ->
      case state[service_name] do
        {_, failures} when failures > 5 ->
          Map.put(state, service_name, {:open, System.monotonic_time()})
        {_, failures} ->
          Map.put(state, service_name, {:closed, failures + 1})
        nil ->
          Map.put(state, service_name, {:closed, 1})
      end
    end)
  end

  defp record_success(service_name) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, service_name, {:closed, 0})
    end)
  end
end
```

## 에러 로깅

### 구조화된 로깅

```elixir
defmodule ErrorLogger do
  require Logger

  def log_error(error, context \\ %{}) do
    error_data = %{
      type: error_type(error),
      message: error_message(error),
      stacktrace: __STACKTRACE__,
      context: context,
      timestamp: DateTime.utc_now()
    }

    Logger.error("Error occurred: #{inspect(error_data)}")
    Sentry.capture_exception(error, extra: context)
  end

  defp error_type({:error, reason}), do: inspect(reason)
  defp error_type(error), do: inspect(error)

  defp error_message({:error, message}), do: message
  defp error_message(message), do: message
end

# 사용
try do
  process_data(data)
catch
  :error, reason ->
    ErrorLogger.log_error(reason, %{data: data, user_id: user_id})
    {:error, "Processing failed"}
end
```

## 에러 응답 변환

```elixir
defmodule ErrorFormatter do
  def format_error({:validation_error, fields}) do
    %{
      status: 422,
      error: "Validation failed",
      details: fields
    }
  end

  def format_error({:not_found, resource}) do
    %{
      status: 404,
      error: "#{resource} not found"
    }
  end

  def format_error(:unauthorized) do
    %{
      status: 401,
      error: "Unauthorized"
    }
  end

  def format_error(_) do
    %{
      status: 500,
      error: "Internal server error"
    }
  end
end
```

## 결론

Elixir의 패턴 매칭과 with 문을 활용하면 안전하고 우아한 에러 처리를 할 수 있습니다. 적절한 로깅, 복구 전략, 그리고 사용자 친화적인 에러 메시지를 통해 안정적인 애플리케이션을 만들 수 있습니다.