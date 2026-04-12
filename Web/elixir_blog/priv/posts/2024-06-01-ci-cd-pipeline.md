---
title: "CI/CD 파이프라인 구축"
author: "정수진"
tags: ["devops", "ci-cd", "automation"]
thumbnail: "/images/thumbnails/ci-cd.jpg"
summary: "GitHub Actions를 이용한 자동화된 테스트 및 배포 파이프라인을 구축합니다."
published_at: 2024-06-01T10:00:00Z
is_popular: false
---

CI/CD는 빠른 배포와 안정성을 보장합니다. GitHub Actions를 이용한 파이프라인을 구축해봅시다.

## GitHub Actions 설정

```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-elixir@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'

      - name: Restore dependencies cache
        uses: actions/cache@v3
        with:
          path: deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-

      - name: Install dependencies
        run: mix deps.get

      - name: Run formatter
        run: mix format --check-formatted

      - name: Run Credo
        run: mix credo suggest

      - name: Run Dialyzer
        run: mix dialyzer

      - name: Create database
        run: mix ecto.create
        env:
          MIX_ENV: test

      - name: Run migrations
        run: mix ecto.migrate
        env:
          MIX_ENV: test

      - name: Run tests
        run: mix test --cover
        env:
          MIX_ENV: test

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./cover/coverage.xml
```

## 배포 파이프라인

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    needs: test

    steps:
      - uses: actions/checkout@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            myapp:latest
            myapp:${{ github.sha }}

      - name: Deploy to production
        run: |
          curl -X POST ${{ secrets.DEPLOY_WEBHOOK }} \
            -H "Content-Type: application/json" \
            -d '{"image": "myapp:${{ github.sha }}"}'
```

## Elixir 프로젝트 설정

```yaml
# .github/workflows/quality.yml
name: Code Quality

on: [push, pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-elixir@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'

      - name: Install dependencies
        run: mix deps.get

      - name: Check code style
        run: mix format --check-formatted

      - name: Check for issues
        run: mix credo suggest --strict

      - name: Run type checking
        run: mix dialyzer --plt

      - name: Check docs
        run: mix docs --extra-apps none

      - name: Check for security issues
        run: mix sobelow --config
```

## 릴리스 자동화

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Elixir
        uses: erlef/setup-elixir@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'

      - name: Create changelog entry
        run: |
          echo "## Version ${{ github.ref_name }}" > CHANGELOG_ENTRY.md
          git log --oneline $(git describe --tags --abbrev=0)..HEAD >> CHANGELOG_ENTRY.md

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          body_path: CHANGELOG_ENTRY.md
          files: |
            dist/myapp.tar.gz
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Notify deployment
        run: |
          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -d "{\"text\": \"New release: ${{ github.ref_name }} deployed\"}"
```

## mix.exs 설정

```elixir
# mix.exs
def project do
  [
    app: :myapp,
    version: "0.1.0",
    elixir: "~> 1.14",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      test: :test,
      "test.watch": :test,
      coveralls: :test,
      "coveralls.html": :test,
      dialyzer: :dev,
      credo: :dev
    ]
  ]
end

defp deps do
  [
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
    {:excoveralls, "~> 0.16", only: :test},
    {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
  ]
end
```

## 배포 스크립트

```bash
#!/bin/bash
# scripts/deploy.sh

set -e

VERSION=$1
IMAGE="myapp:${VERSION}"

echo "Deploying $IMAGE..."

# 이미지 빌드
docker build -t $IMAGE .

# 이미지 푸시
docker push $IMAGE

# Kubernetes 업데이트
kubectl set image deployment/myapp-deployment \
  myapp=$IMAGE \
  -n production

# 롤아웃 상태 확인
kubectl rollout status deployment/myapp-deployment -n production

echo "Deployment complete!"
```

## 결론

자동화된 CI/CD 파이프라인은 코드 품질을 보장하고 배포를 신속하게 합니다. GitHub Actions를 이용하면 별도의 인프라 없이도 강력한 자동화를 구현할 수 있습니다.