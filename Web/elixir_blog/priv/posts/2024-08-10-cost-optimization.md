---
title: "클라우드 비용 최적화"
author: "최지훈"
tags: ["devops", "cloud", "cost"]
thumbnail: "/images/thumbnails/cost-optimization.jpg"
summary: "클라우드 인프라 비용을 최적화하고 효율성을 높이는 방법을 배웁니다."
published_at: 2024-08-10T14:30:00Z
is_popular: true
---

클라우드 비용은 빠르게 증가할 수 있습니다. 효과적인 비용 최적화 전략을 알아봅시다.

## 리소스 모니터링

```elixir
# lib/myapp/cloud/resource_monitor.ex
defmodule Myapp.Cloud.ResourceMonitor do
  def get_resource_usage do
    %{
      cpu: get_cpu_usage(),
      memory: get_memory_usage(),
      storage: get_storage_usage(),
      network: get_network_usage()
    }
  end

  defp get_cpu_usage do
    {output, _} = System.cmd("top", ["-bn1", "-d1"])
    parse_cpu_usage(output)
  end

  defp get_memory_usage do
    {output, _} = System.cmd("free", ["-h"])
    parse_memory_usage(output)
  end

  def estimate_monthly_cost(usage) do
    %{
      compute: usage.cpu * 0.05,
      memory: usage.memory * 0.02,
      storage: usage.storage * 0.001,
      network: usage.network * 0.01
    }
    |> Enum.map(fn {_k, v} -> v end)
    |> Enum.sum()
  end
end
```

## 자동 스케일링

```elixir
# lib/myapp/autoscaler.ex
defmodule Myapp.AutoScaler do
  def scale_based_on_load do
    cpu_usage = get_cpu_usage()
    memory_usage = get_memory_usage()

    case {cpu_usage, memory_usage} do
      {cpu, _mem} when cpu > 80 ->
        scale_up()
      {cpu, _mem} when cpu < 20 ->
        scale_down()
      _ ->
        :no_action
    end
  end

  defp scale_up do
    # 인스턴스 추가
    {:ok, "Scaled up"}
  end

  defp scale_down do
    # 인스턴스 감소
    {:ok, "Scaled down"}
  end

  defp get_cpu_usage do
    # CPU 사용률 조회
    50
  end

  defp get_memory_usage do
    # 메모리 사용률 조회
    40
  end
end
```

## 데이터베이스 비용 최적화

```elixir
defmodule DatabaseOptimization do
  def analyze_query_costs do
    expensive_queries = [
      "SELECT * FROM posts JOIN comments...",
      "SELECT COUNT(*) FROM users..."
    ]

    Enum.map(expensive_queries, fn query ->
      cost = estimate_query_cost(query)
      {query, cost}
    end)
  end

  defp estimate_query_cost(query) do
    # 쿼리 비용 추정
    1.5
  end

  def optimize_indexes do
    # 미사용 인덱스 삭제
    "DROP INDEX idx_posts_created_at;"

    # 새 인덱스 추가
    "CREATE INDEX idx_posts_status ON posts(status) WHERE published = true;"
  end

  def enable_connection_pooling do
    # 데이터베이스 연결 풀 설정
    %{
      pool_size: System.schedulers_online() * 2,
      max_overflow: 10,
      timeout: 15000
    }
  end
end
```

## 스토리지 비용 최적화

```elixir
defmodule StorageOptimization do
  def cleanup_old_files do
    cutoff_date = DateTime.add(DateTime.utc_now(), -90 * 24 * 3600)

    files = from(f in File,
      where: f.created_at < ^cutoff_date
    ) |> Repo.all()

    Enum.each(files, fn file ->
      delete_file(file)
    end)

    {:ok, Enum.count(files)}
  end

  def compress_old_data do
    # 오래된 데이터 압축
    :ok
  end

  def use_cheaper_storage_tier do
    # 덜 접근되는 데이터를 저가 스토리지로 이동
    :ok
  end

  defp delete_file(file) do
    Repo.delete(file)
    # 실제 저장소에서도 삭제
  end
end
```

## 네트워크 비용 최적화

```elixir
defmodule NetworkOptimization do
  def analyze_bandwidth_usage do
    %{
      inbound: get_inbound_bandwidth(),
      outbound: get_outbound_bandwidth(),
      cross_region: get_cross_region_traffic()
    }
  end

  defp get_inbound_bandwidth do
    # 인바운드 대역폭 조회
    100  # MB
  end

  defp get_outbound_bandwidth do
    # 아웃바운드 대역폭 조회
    500  # MB
  end

  defp get_cross_region_traffic do
    # 리전 간 트래픽 조회
    50   # MB
  end

  def enable_caching do
    # CloudFront 또는 CDN 활성화
    :ok
  end

  def optimize_api_payloads do
    # API 응답 크기 최소화
    :ok
  end
end
```

## 비용 리포팅

```elixir
defmodule CostReporter do
  def generate_weekly_report do
    costs = %{
      compute: 150,
      database: 80,
      storage: 30,
      network: 25,
      other: 15
    }

    total = Enum.sum(Map.values(costs))

    %{
      period: "2024-08-01 to 2024-08-07",
      costs: costs,
      total: total,
      trend: "up 5%",
      recommendations: get_recommendations()
    }
  end

  defp get_recommendations do
    [
      "스케일링 정책 검토 (CPU 사용률 20% 미만인 시간대 많음)",
      "미사용 인스턴스 삭제",
      "예약 인스턴스 구매 고려 (30% 절감)"
    ]
  end

  def send_cost_alert(threshold) do
    current_month_cost = get_current_month_cost()

    if current_month_cost > threshold do
      send_email_alert(current_month_cost)
    end
  end

  defp get_current_month_cost do
    # 이번 달 비용 계산
    500
  end

  defp send_email_alert(cost) do
    # 알림 이메일 발송
    :ok
  end
end
```

## 결론

체계적인 모니터링과 최적화를 통해 클라우드 비용을 크게 절감할 수 있습니다. 자동 스케일링, 인덱스 최적화, 캐싱 등 다양한 기법을 활용하여 비용 효율성을 높일 수 있습니다.