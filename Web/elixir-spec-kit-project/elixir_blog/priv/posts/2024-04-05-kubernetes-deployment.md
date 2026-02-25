---
title: "Kubernetes에서 Elixir/Phoenix 애플리케이션 배포"
author: "박민수"
tags: ["kubernetes", "devops", "deployment"]
thumbnail: "/images/thumbnails/kubernetes-deployment.jpg"
summary: "Kubernetes 클러스터에 Elixir 애플리케이션을 배포하고 관리하는 방법을 배웁니다."
published_at: 2024-04-05T14:30:00Z
is_popular: true
---

Kubernetes는 현대적인 컨테이너 오케스트레이션 플랫폼입니다. Elixir 애플리케이션을 Kubernetes에 배포하는 방법을 알아봅시다.

## Dockerfile 최적화

### Kubernetes용 이미지

```dockerfile
FROM elixir:1.14-alpine as builder

WORKDIR /app

RUN apk add --no-cache git build-base nodejs npm

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix deps.get

COPY . .
RUN mix assets.deploy && mix release

# 런타임 이미지
FROM alpine:latest

RUN apk add --no-cache openssl bash curl

WORKDIR /app
COPY --from=builder /app/_build/prod/rel/myapp ./

# 헬스 체크
HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1

ENV HOME=/app PORT=4000
EXPOSE 4000

CMD ["bin/myapp", "start"]
```

## Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-deployment
  labels:
    app: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:1.0.0
        ports:
        - containerPort: 4000
        env:
        - name: REPLACE_OS_VARS
          value: "true"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: SECRET_KEY_BASE
          valueFrom:
            secretKeyRef:
              name: app-secret
              key: key
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 4000
          initialDelaySeconds: 5
          periodSeconds: 5
```

## Service 설정

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  type: LoadBalancer
  selector:
    app: myapp
  ports:
  - protocol: TCP
    port: 80
    targetPort: 4000
```

## 분산 Elixir 클러스터

### Erlang 분산 모드

```elixir
# config/runtime.exs
config :kernel,
  inet_dist_listen_min: 9001,
  inet_dist_listen_max: 9001

# 클러스터 연결
def establish_cluster do
  case System.get_env("CLUSTER_MODE") do
    "kubernetes" -> connect_kubernetes_cluster()
    _ -> :ok
  end
end

defp connect_kubernetes_cluster do
  app_name = System.get_env("APP_NAME")
  namespace = System.get_env("NAMESPACE", "default")
  domain = System.get_env("CLUSTER_DOMAIN", "cluster.local")

  for i <- 0..2 do
    node = :"#{app_name}-#{i}@#{app_name}-#{i}.#{app_name}.#{namespace}.svc.#{domain}"
    Node.connect(node)
  end
end
```

### StatefulSet 사용

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: myapp
spec:
  serviceName: myapp
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:1.0.0
        ports:
        - containerPort: 4000
          name: web
        - containerPort: 9001
          name: epmd
        env:
        - name: CLUSTER_MODE
          value: "kubernetes"
        - name: APP_NAME
          value: "myapp"
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
```

## 자동 스케일링

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## ConfigMap과 Secret

```bash
# 설정 저장
kubectl create configmap app-config --from-file=config.exs

# 민감한 정보 저장
kubectl create secret generic db-secret --from-literal=url=postgres://...

# YAML에서 사용
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  config.exs: |
    config :myapp, ...
```

## 헬스 체크 구현

```elixir
# lib/myapp_web/controllers/health_controller.ex
defmodule MyappWeb.HealthController do
  use MyappWeb, :controller

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case check_dependencies() do
      :ok ->
        json(conn, %{status: "ready"})
      :error ->
        conn
        |> put_status(503)
        |> json(%{status: "not_ready"})
    end
  end

  defp check_dependencies do
    with :ok <- check_database(),
         :ok <- check_cache() do
      :ok
    else
      _ -> :error
    end
  end
end
```

## 로깅 및 모니터링

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
data:
  promtail-config.yaml: |
    clients:
      - url: http://loki:3100/loki/api/v1/push
    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
```

## 결론

Kubernetes를 사용하면 Elixir 애플리케이션을 확장 가능하고 안정적으로 배포할 수 있습니다. 적절한 리소스 설정, 헬스 체크, 자동 스케일링을 통해 프로덕션 환경에서 최적의 성능을 달성할 수 있습니다.