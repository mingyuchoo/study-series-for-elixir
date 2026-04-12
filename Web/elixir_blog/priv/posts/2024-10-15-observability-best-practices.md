---
title: "옵저버빌리티 모범 사례"
author: "송태양"
tags: ["observability", "monitoring", "devops"]
thumbnail: "/images/thumbnails/observability-practices.jpg"
summary: "로그, 메트릭, 트레이스를 통한 완벽한 시스템 관찰 방법을 배웁니다."
published_at: 2024-10-15T13:45:00Z
is_popular: false
---

완벽한 옵저버빌리티는 시스템 문제를 빠르게 파악하고 해결하는 데 도움이 됩니다.

## 구조화된 로깅

```elixir
# lib/myapp/logging/structured_logger.ex
defmodule StructuredLogger do
  require Logger

  def log_request(conn, metadata \\ %{}) do
    Logger.info("HTTP Request", Map.merge(%{
      method: conn.method,
      path: conn.request_path,
      remote_ip: format_ip(conn.remote_ip),
      user_agent: get_user_agent(conn)
    }, metadata))
  end

  def log_response(conn, duration_ms, metadata \\ %{}) do
    Logger.info("HTTP Response", Map.merge(%{
      status: conn.status,
      duration_ms: duration_ms,
      method: conn.method,
      path: conn.request_path
    }, metadata))
  end

  def log_error(error, context \\ %{}) do
    Logger.error("Error occurred", Map.merge(%{
      error: inspect(error),
      stacktrace: __STACKTRACE__
    }, context))
  end

  def log_database_query(query, duration_ms, rows_affected \\ nil) do
    Logger.debug("Database Query", %{
      query: query,
      duration_ms: duration_ms,
      rows_affected: rows_affected
    })
  end

  defp format_ip(ip_tuple) do
    ip_tuple
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp get_user_agent(conn) do
    get_req_header(conn, "user-agent")
    |> List.first("")
  end
end
```

## 커스텀 메트릭

```elixir
# lib/myapp/metrics/custom_metrics.ex
defmodule CustomMetrics do
  def setup do
    # 비즈니스 메트릭
    :prometheus_gauge.new([
      {:name, :active_users},
      {:help, "Number of active users"}
    ])

    :prometheus_counter.new([
      {:name, :orders_total},
      {:help, "Total orders placed"}
    ])

    :prometheus_gauge.new([
      {:name, :revenue},
      {:help, "Total revenue"}
    ])
  end

  def record_active_users(count) do
    :prometheus_gauge.set(:active_users, count)
  end

  def record_order(amount) do
    :prometheus_counter.inc(:orders_total)
    :prometheus_gauge.inc(:revenue, amount)
  end
end
```

## 분산 추적 (Distributed Tracing)

```elixir
# lib/myapp/tracing/trace_context.ex
defmodule TraceContext do
  @trace_id_header "x-trace-id"
  @span_id_header "x-span-id"

  def create_trace_id do
    UUID.uuid4()
  end

  def create_span_id do
    UUID.uuid4()
  end

  def get_or_create_trace_id(headers) do
    get_header(headers, @trace_id_header) || create_trace_id()
  end

  def get_headers(trace_id, span_id) do
    [
      {@trace_id_header, trace_id},
      {@span_id_header, span_id}
    ]
  end

  defp get_header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      String.downcase(key) == name && value
    end)
  end
end

# 미들웨어
defmodule TracingMiddleware do
  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, _opts) do
    trace_id = TraceContext.get_or_create_trace_id(conn.req_headers)
    span_id = TraceContext.create_span_id()

    Logger.metadata(trace_id: trace_id, span_id: span_id)

    conn
    |> assign(:trace_id, trace_id)
    |> assign(:span_id, span_id)
  end
end
```

## 알림 설정

```elixir
# lib/myapp/alerts/alert_manager.ex
defmodule AlertManager do
  def setup_alerts do
    # 높은 에러율 알림
    create_alert(:high_error_rate, %{
      condition: "rate(http_requests_total{status=\"500\"}[5m]) > 0.05",
      threshold: 5,
      action: :notify_ops
    })

    # 높은 응답시간 알림
    create_alert(:high_latency, %{
      condition: "histogram_quantile(0.95, http_request_duration_seconds) > 1",
      threshold: 10,
      action: :notify_ops
    })

    # 데이터베이스 연결 풀 고갈
    create_alert(:db_connection_pool_exhausted, %{
      condition: "db_connections_active >= db_connection_pool_size",
      threshold: 1,
      action: :page_oncall
    })
  end

  defp create_alert(name, config) do
    # 알림 규칙 생성
    :ok
  end

  def send_alert(alert_type, severity, message) do
    case severity do
      :critical -> page_oncall(message)
      :high -> notify_slack(message)
      :medium -> notify_email(message)
      :low -> log_only(message)
    end
  end

  defp page_oncall(message) do
    # PagerDuty 호출
    :ok
  end

  defp notify_slack(message) do
    # Slack 알림
    :ok
  end

  defp notify_email(message) do
    # 이메일 알림
    :ok
  end

  defp log_only(message) do
    Logger.warn(message)
  end
end
```

## 대시보드 설정

```elixir
# 그라파나 대시보드 JSON
defmodule DashboardConfig do
  def get_dashboard do
    %{
      "dashboard" => %{
        "title" => "Application Overview",
        "panels" => [
          %{
            "title" => "Request Rate",
            "targets" => [
              %{"expr" => "rate(http_requests_total[5m])"}
            ]
          },
          %{
            "title" => "Error Rate",
            "targets" => [
              %{"expr" => "rate(http_requests_total{status=\"500\"}[5m])"}
            ]
          },
          %{
            "title" => "Response Time (P95)",
            "targets" => [
              %{"expr" => "histogram_quantile(0.95, http_request_duration_seconds)"}
            ]
          },
          %{
            "title" => "Database Connections",
            "targets" => [
              %{"expr" => "db_connections_active"}
            ]
          }
        ]
      }
    }
  end
end
```

## 결론

완벽한 옵저버빌리티를 통해 시스템의 상태를 실시간으로 파악하고, 문제가 발생했을 때 신속하게 대응할 수 있습니다. 로그, 메트릭, 트레이스의 세 기둥을 모두 구현하면 진정한 옵저버빌리티를 달성할 수 있습니다.