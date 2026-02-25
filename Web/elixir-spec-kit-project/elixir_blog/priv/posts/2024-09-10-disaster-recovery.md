---
title: "재해 복구 및 비즈니스 연속성"
author: "임동현"
tags: ["devops", "disaster-recovery", "reliability"]
thumbnail: "/images/thumbnails/disaster-recovery.jpg"
summary: "시스템 장애에 대비한 재해 복구 계획과 구현을 배웁니다."
published_at: 2024-09-10T14:00:00Z
is_popular: false
---

효과적인 재해 복구 전략은 비즈니스의 지속성을 보장합니다.

## 백업 전략

```elixir
# lib/myapp/backup/backup_service.ex
defmodule Myapp.Backup.BackupService do
  def create_database_backup do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    backup_file = "backups/db_#{timestamp}.dump"

    case System.cmd("pg_dump", [
      "-h", System.get_env("DB_HOST"),
      "-U", System.get_env("DB_USER"),
      "-d", System.get_env("DB_NAME"),
      "-F", "c",
      "-f", backup_file
    ]) do
      {_output, 0} ->
        upload_to_s3(backup_file)
        {:ok, backup_file}
      {error, _code} ->
        {:error, error}
    end
  end

  def create_file_backup do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    backup_file = "backups/files_#{timestamp}.tar.gz"

    case System.cmd("tar", [
      "-czf", backup_file,
      "priv/static/uploads/"
    ]) do
      {_output, 0} ->
        upload_to_s3(backup_file)
        {:ok, backup_file}
      {error, _code} ->
        {:error, error}
    end
  end

  def schedule_daily_backup do
    Oban.insert(%{
      type: "backup",
      args: %{
        "type" => "full",
        "target" => "database"
      },
      scheduled_at: DateTime.add(DateTime.utc_now(), 86400)
    })
  end

  defp upload_to_s3(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        ExAws.S3.put_object("backups", file_path, content)
        |> ExAws.request()
      {:error, _} -> :error
    end
  end
end
```

## 복제 설정

```elixir
# config/config.exs
config :myapp, Myapp.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: System.schedulers_online() * 2

# 읽기 전용 복제본
config :myapp, Myapp.Repo.ReadReplica,
  url: System.get_env("DATABASE_REPLICA_URL"),
  pool_size: System.schedulers_online() * 2,
  timeout: 15000

# lib/myapp/repo/read_replica.ex
defmodule Myapp.Repo.ReadReplica do
  use Ecto.Repo, otp_app: :myapp, adapter: Ecto.Adapters.Postgres
end

# 사용
from(p in Post, where: p.id == ^id)
|> Myapp.Repo.ReadReplica.one()
```

## 페일오버 메커니즘

```elixir
# lib/myapp/failover/failover_manager.ex
defmodule Myapp.Failover.FailoverManager do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    check_primary_health()
    {:ok, %{primary_healthy: true}}
  end

  def handle_info(:health_check, state) do
    new_state = case check_primary_health() do
      :ok ->
        use_primary()
        %{state | primary_healthy: true}
      :error ->
        if not state.primary_healthy do
          failover_to_secondary()
        end
        %{state | primary_healthy: false}
    end

    schedule_next_check()
    {:noreply, new_state}
  end

  defp check_primary_health do
    case Ecto.Adapters.SQL.query(Myapp.Repo, "SELECT 1") do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp use_primary do
    Application.put_env(:myapp, :db_connection, :primary)
  end

  defp failover_to_secondary do
    Application.put_env(:myapp, :db_connection, :secondary)
    notify_ops_team()
  end

  defp notify_ops_team do
    # Slack, PagerDuty 등으로 알림 발송
    :ok
  end

  defp schedule_next_check do
    Process.send_after(self(), :health_check, 30_000)
  end
end
```

## 복구 계획

```elixir
# lib/myapp/disaster_recovery/recovery_plan.ex
defmodule DisasterRecovery.RecoveryPlan do
  def execute_recovery do
    case get_failure_type() do
      :database_failure -> recover_database()
      :disk_failure -> recover_disk()
      :network_failure -> recover_network()
      :complete_failure -> recover_complete()
    end
  end

  defp recover_database do
    # 최근 백업 복원
    backup_file = get_latest_backup()

    case restore_from_backup(backup_file) do
      :ok -> {:ok, "Database restored"}
      :error -> {:error, "Restore failed"}
    end
  end

  defp recover_disk do
    # 데이터 디스크 복구
    :ok
  end

  defp recover_network do
    # 네트워크 연결 복구
    :ok
  end

  defp recover_complete do
    # 전체 시스템 복구
    # 1. 데이터베이스 복구
    recover_database()
    # 2. 파일 복구
    recover_disk()
    # 3. 서비스 재시작
    restart_services()
    # 4. 헬스 체크
    verify_system_health()
  end

  defp get_latest_backup do
    backups = ExAws.S3.list_objects("backups")
    |> ExAws.request!()

    backups.contents
    |> Enum.sort_by(&(&1.last_modified), {:desc, DateTime})
    |> List.first()
    |> Map.get(:key)
  end

  defp restore_from_backup(backup_file) do
    case System.cmd("pg_restore", [
      "-h", System.get_env("DB_HOST"),
      "-U", System.get_env("DB_USER"),
      "-d", System.get_env("DB_NAME"),
      backup_file
    ]) do
      {_output, 0} -> :ok
      {_error, _code} -> :error
    end
  end

  defp restart_services do
    System.cmd("systemctl", ["restart", "myapp"])
  end

  defp verify_system_health do
    # 시스템 헬스 체크
    :ok
  end
end
```

## RTO/RPO 모니터링

```elixir
# lib/myapp/sla/sla_monitor.ex
defmodule SLA.Monitor do
  @rto_minutes 1    # 복구 목표 시간 (분)
  @rpo_minutes 15   # 복구 목표 지점 (분)

  def check_rto do
    failure_time = get_last_failure_time()
    recovery_time = get_recovery_time()

    actual_rto = DateTime.diff(recovery_time, failure_time, :minute)

    case actual_rto <= @rto_minutes do
      true -> {:ok, "RTO met"}
      false -> {:error, "RTO exceeded"}
    end
  end

  def check_rpo do
    last_backup_time = get_last_backup_time()
    failure_time = get_last_failure_time()

    actual_rpo = DateTime.diff(failure_time, last_backup_time, :minute)

    case actual_rpo <= @rpo_minutes do
      true -> {:ok, "RPO met"}
      false -> {:error, "RPO exceeded"}
    end
  end

  defp get_last_failure_time do
    # 마지막 장애 시간 조회
    DateTime.utc_now()
  end

  defp get_recovery_time do
    # 복구 완료 시간 조회
    DateTime.utc_now()
  end

  defp get_last_backup_time do
    # 마지막 백업 시간 조회
    DateTime.utc_now()
  end
end
```

## 결론

철저한 재해 복구 계획은 비즈니스 연속성을 보장합니다. 정기적인 백업, 복제, 페일오버 메커니즘, 그리고 복구 테스트를 통해 예상치 못한 장애에 대비할 수 있습니다.