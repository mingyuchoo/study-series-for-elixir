---
title: "모니터링과 옵저버빌리티 구축"
author: "김철수"
tags: ["monitoring", "devops", "performance"]
thumbnail: "/images/thumbnails/monitoring.jpg"
summary: "프로메테우스와 그라파나를 이용한 애플리케이션 모니터링 시스템을 구축합니다."
published_at: 2024-05-15T14:20:00Z
is_popular: true
---

효과적한 모니터링은 프로덕션 애플리케이션 운영의 핵심입니다. 모니터링과 옵저버빌리티를 구축해봅시다.

## 프로메테우스 메트릭

```elixir
# lib/myapp/metrics.ex
defmodule Myapp.Metrics do
  def init do
    :prometheus_counter.new([
      {:name, :http_requests_total},
      {:help, "Total HTTP requests"}
    ])

    :prometheus_histogram.new([
      {:name, :http_request_duration_seconds},
      {:help, "HTTP request duration"},
      {:buckets, [0.1, 0.5, 1.0, 5.0]}
    ])

    :prometheus_gauge.new([
      {:name, :db_connections_active},
      {:help, "Active database connections"}
    ])
  end

  def record_request(method, status) do
    :prometheus_counter.inc(:http_requests_total, [method, status])
  end

  def record_request_duration(duration) do
    :prometheus_histogram.observe(:http_request_duration_seconds, duration)
  end

  def set_active_connections(count) do
    :prometheus_gauge.set(:db_connections_active, count)
  end
end

# 플러그
defmodule MyappWeb.Plugs.MetricsCollector do
  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, _opts) do
    start_time = System.monotonic_time()

    register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start_time
      duration_seconds = duration / 1_000_000_000

      Myapp.Metrics.record_request(conn.method, conn.status)
      Myapp.Metrics.record_request_duration(duration_seconds)

      conn
    end)
  end
end
```

## 로깅 및 분산 추적

```elixir
# config/config.exs
config :logger,
  backends: [{:console, []}, :syslog],
  level: :info

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :duration_ms]

# Sentry 통합
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: config_env(),
  enable_source_code_context: true,
  root_source_code_path: File.cwd!()
```

### 구조화된 로깅

```elixir
defmodule LogHelper do
  require Logger

  def log_request(conn, metadata \\ %{}) do
    Logger.info("Request started", Map.merge(metadata, %{
      method: conn.method,
      path: conn.request_path,
      query_string: conn.query_string
    }))
  end

  def log_response(conn, duration, metadata \\ %{}) do
    Logger.info("Request completed", Map.merge(metadata, %{
      status: conn.status,
      duration_ms: duration,
      path: conn.request_path
    }))
  end

  def log_error(error, metadata \\ %{}) do
    Logger.error("Error occurred: #{inspect(error)}", metadata)
    Sentry.capture_exception(error, extra: metadata)
  end
end
```

## 헬스 체크

```elixir
# lib/myapp_web/controllers/health_controller.ex
defmodule MyappWeb.HealthController do
  use MyappWeb, :controller

  def liveness(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def readiness(conn, _params) do
    case check_system_health() do
      :ok ->
        json(conn, %{status: "ready"})
      :error ->
        conn
        |> put_status(503)
        |> json(%{status: "not_ready"})
    end
  end

  defp check_system_health do
    with :ok <- check_database(),
         :ok <- check_cache() do
      :ok
    else
      _ -> :error
    end
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Myapp.Repo, "SELECT 1") do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp check_cache do
    case Redix.command(:redix, ["PING"]) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end
end
```

## 알림 설정

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: "myapp"
    static_configs:
      - targets: ["localhost:4000"]
```

```yaml
# alerts.yml
groups:
  - name: myapp
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status="500"}[5m]) > 0.05
        for: 5m
        annotations:
          summary: "High error rate detected"

      - alert: HighLatency
        expr: histogram_quantile(0.99, http_request_duration_seconds) > 1.0
        for: 5m
        annotations:
          summary: "High request latency"

      - alert: DatabaseDown
        expr: up{job="database"} == 0
        for: 1m
        annotations:
          summary: "Database is down"
```

## 트레이싱

```elixir
# config/config.exs
config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "http://localhost:4317"

# 커스텀 스팬
defmodule MyappWeb.Plugs.OpenTelemetry do
  def init(options) do
    options
  end

  def call(conn, _opts) do
    ctx = OpenTelemetry.Tracer.start_span(
      :http,
      %{
        "http.method" => conn.method,
        "http.url" => conn.request_path,
        "http.target" => conn.request_path
      }
    )

    OpenTelemetry.Ctx.attach(ctx)

    Plug.Conn.register_before_send(conn, fn conn ->
      OpenTelemetry.Tracer.set_attribute("http.status_code", conn.status)
      OpenTelemetry.Tracer.end_span()
      conn
    end)
  end
end
```

## 대시보드

그라파나 대시보드 JSON:

```json
{
  "dashboard": {
    "title": "Elixir/Phoenix Application",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])"
          }
        ]
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=\"500\"}[5m])"
          }
        ]
      },
      {
        "title": "Response Time",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, http_request_duration_seconds)"
          }
        ]
      }
    ]
  }
}
```

## 결론

효과적한 모니터링은 문제를 조기에 발견하고 성능을 지속적으로 개선하는 데 도움이 됩니다. 메트릭, 로그, 트레이스의 세 가지 요소를 모두 수집하면 완벽한 옵저버빌리티를 달성할 수 있습니다.