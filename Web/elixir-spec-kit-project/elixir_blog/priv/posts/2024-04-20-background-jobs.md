---
title: "Elixir에서 백그라운드 작업 처리"
author: "강민지"
tags: ["elixir", "programming", "architecture"]
thumbnail: "/images/thumbnails/background-jobs.jpg"
summary: "Oban을 이용한 안정적인 백그라운드 작업 처리 방법을 배웁니다."
published_at: 2024-04-20T10:20:00Z
is_popular: false
---

장시간 걸리는 작업은 백그라운드에서 처리해야 합니다. Oban을 이용한 백그라운드 작업 처리를 알아봅시다.

## Oban 기본 설정

```elixir
# mix.exs
defp deps do
  [
    {:oban, "~> 2.17"}
  ]
end

# config/config.exs
config :myapp, Oban,
  engine: Oban.Engines.Basic,
  queues: [default: 10, mailers: 20, analytics: 5],
  repo: Myapp.Repo

# config/dev.exs
config :myapp, Oban,
  engine: Oban.Engines.Basic,
  queues: false
```

## 작업 정의

```elixir
defmodule MyappWeb.Workers.SendWelcomeEmail do
  use Oban.Worker, queue: :mailers, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    user = Repo.get!(User, user_id)

    case send_email(user) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_email(user) do
    MyappWeb.Email.welcome_email(user)
    |> Mailer.deliver()
  end
end
```

## 작업 예약

### 즉시 실행

```elixir
%{"user_id" => user.id}
|> MyappWeb.Workers.SendWelcomeEmail.new()
|> Oban.insert()
```

### 지연 실행

```elixir
%{"user_id" => user.id}
|> MyappWeb.Workers.SendWelcomeEmail.new(scheduled_at: DateTime.add(DateTime.utc_now(), 3600))
|> Oban.insert()
```

### 반복 작업

```elixir
defmodule MyappWeb.Workers.DailyReport do
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(_job) do
    generate_and_send_report()
  end

  def schedule_daily do
    %{}
    |> new(schedule_in: {1, :day})
    |> Oban.insert()
  end
end
```

## 작업 모니터링

```elixir
defmodule JobMonitor do
  def job_stats do
    %{
      scheduled: count_scheduled(),
      executing: count_executing(),
      completed: count_completed(),
      failed: count_failed()
    }
  end

  defp count_scheduled do
    from(j in Oban.Job, where: j.state == "scheduled")
    |> Repo.aggregate(:count)
  end

  defp count_executing do
    from(j in Oban.Job, where: j.state == "executing")
    |> Repo.aggregate(:count)
  end

  defp count_completed do
    from(j in Oban.Job, where: j.state == "completed")
    |> Repo.aggregate(:count)
  end

  defp count_failed do
    from(j in Oban.Job, where: j.state == "discarded")
    |> Repo.aggregate(:count)
  end
end
```

## 에러 처리 및 재시도

```elixir
defmodule MyappWeb.Workers.DataImport do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    timeout: 30000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => file_id}, attempt: attempt}) do
    file = Repo.get!(File, file_id)

    case import_data(file) do
      :ok ->
        :ok
      {:error, :temporary} when attempt < 5 ->
        {:reschedule, 300}  # 5분 후 재시도
      {:error, :permanent} ->
        {:cancel, "Permanent error"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_data(file) do
    try do
      # 데이터 임포트 로직
      :ok
    catch
      :error, _reason -> {:error, :temporary}
    end
  end
end
```

## 복잡한 워크플로우

```elixir
defmodule UserRegistrationFlow do
  alias MyappWeb.Workers

  def register_user(user_attrs) do
    with {:ok, user} <- create_user(user_attrs),
         :ok <- enqueue_email(user),
         :ok <- enqueue_analytics(user) do
      {:ok, user}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_user(attrs) do
    Repo.insert(User.changeset(%User{}, attrs))
  end

  defp enqueue_email(user) do
    %{"user_id" => user.id}
    |> Workers.SendWelcomeEmail.new()
    |> Oban.insert()

    :ok
  end

  defp enqueue_analytics(user) do
    %{"user_id" => user.id, "event" => "user_registered"}
    |> Workers.LogAnalytics.new()
    |> Oban.insert()

    :ok
  end
end
```

## Oban 웹 대시보드

```elixir
# mix.exs
defp deps do
  [
    {:oban, "~> 2.17"},
    {:oban_web, "~> 2.0"}
  ]
end

# config/config.exs
config :myapp, MyappWeb.Endpoint,
  plug: [ObanWeb.Router]

# lib/myapp_web/router.ex
defmodule MyappWeb.Router do
  use MyappWeb, :router

  scope "/oban" do
    pipe_through :browser
    oban_dashboard()
  end
end
```

## 성능 최적화

```elixir
defmodule MyappWeb.Workers.BulkEmailSend do
  use Oban.Worker, queue: :mailers, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_ids" => user_ids}}) do
    users = Repo.all(from u in User, where: u.id in ^user_ids)

    users
    |> Enum.chunk_every(100)
    |> Enum.each(&send_batch/1)

    :ok
  end

  defp send_batch(users) do
    Enum.each(users, fn user ->
      send_email(user)
    end)
  end
end
```

## 결론

Oban을 이용하면 안정적이고 확장 가능한 백그라운드 작업 처리 시스템을 구축할 수 있습니다. 작업 큐, 재시도 전략, 모니터링을 통해 프로덕션 환경에서 안전하게 비동기 작업을 처리할 수 있습니다.