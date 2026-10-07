#!/bin/bash

# ============================================
# Agentic AI Assistant 시작 스크립트
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# asdf 설치본이 있으면 프로젝트의 .tool-versions에 지정된 버전을 사용합니다.
# 다른 방식으로 설치했다면 기존 PATH의 mix/erl을 그대로 사용합니다.
TOOL_VERSIONS="$PROJECT_ROOT/.tool-versions"
if [[ -f "$TOOL_VERSIONS" ]]; then
    ERLANG_VERSION="$(awk '$1 == "erlang" { print $2; exit }' "$TOOL_VERSIONS")"
    ELIXIR_VERSION="$(awk '$1 == "elixir" { print $2; exit }' "$TOOL_VERSIONS")"

    if [[ -n "$ERLANG_VERSION" && -x "$HOME/.asdf/installs/erlang/$ERLANG_VERSION/bin/erl" ]]; then
        export ERLANG_HOME="$HOME/.asdf/installs/erlang/$ERLANG_VERSION"
        export PATH="$ERLANG_HOME/bin:$PATH"
    fi
    if [[ -n "$ELIXIR_VERSION" && -x "$HOME/.asdf/installs/elixir/$ELIXIR_VERSION/bin/mix" ]]; then
        export ELIXIR_HOME="$HOME/.asdf/installs/elixir/$ELIXIR_VERSION"
        export PATH="$ELIXIR_HOME/bin:$PATH"
    fi
fi

if ! command -v mix >/dev/null 2>&1 || ! command -v erl >/dev/null 2>&1; then
    echo "[ERROR] Elixir/Erlang을 찾을 수 없습니다. .tool-versions의 버전을 설치하거나 PATH를 설정하세요." >&2
    exit 1
fi

# 로컬 개발 설정을 서버와 시드 실행 과정에 함께 전달합니다.
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════╗"
echo "║     Agentic AI Assistant              ║"
echo "║     Elixir + Phoenix + Azure OpenAI   ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# 환경 변수 확인
if [[ -z "$AZURE_OPENAI_ENDPOINT" ]]; then
    echo -e "${YELLOW}[WARN]${NC} AZURE_OPENAI_ENDPOINT가 설정되지 않았습니다."
    echo "       export AZURE_OPENAI_ENDPOINT=\"https://your-resource.openai.azure.com\""
fi

if [[ -z "$AZURE_OPENAI_API_KEY" ]]; then
    echo -e "${YELLOW}[WARN]${NC} AZURE_OPENAI_API_KEY가 설정되지 않았습니다."
    echo "       export AZURE_OPENAI_API_KEY=\"your-api-key\""
    echo "       (AI 채팅 기능은 설정 전까지 사용할 수 없습니다)"
fi

if [[ -z "$FIRECRAWL_API_KEY" ]]; then
    echo -e "${YELLOW}[WARN]${NC} FIRECRAWL_API_KEY가 설정되지 않았습니다."
    echo "       export FIRECRAWL_API_KEY=\"your-firecrawl-api-key\""
    echo "       (웹 스크래핑/검색 기능이 비활성화됩니다)"
fi

cd "$PROJECT_ROOT"

# 새 Elixir 설치에서 Hex 설치 확인 프롬프트가 뜨지 않도록 준비합니다.
if ! mix hex.info >/dev/null 2>&1; then
    echo -e "${GREEN}[INFO]${NC} Hex 설치 중..."
    mix local.hex --force
fi

# 의존성 확인
if ! mix deps.loadpaths --no-compile >/dev/null 2>&1; then
    echo -e "${GREEN}[INFO]${NC} 의존성 설치 중..."
    mix deps.get
fi

# 데이터베이스 마이그레이션
echo -e "${GREEN}[INFO]${NC} 데이터베이스 마이그레이션..."
mix ecto.create
mix ecto.migrate

# 초기 시드 (관리자 계정 / 에이전트 / MCP)
echo -e "${GREEN}[INFO]${NC} 초기 데이터 시드..."
mix run apps/core/priv/repo/seeds.exs

# 서버 시작
echo -e "${GREEN}[INFO]${NC} Phoenix 서버 시작..."
echo -e "${BLUE}[INFO]${NC} 접속: http://localhost:4000"
echo -e "${BLUE}[INFO]${NC} 계정 생성 후 /chat 으로 이동하세요."
echo ""

mix phx.server
