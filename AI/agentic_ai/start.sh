#!/bin/bash

# ============================================
# Agentic AI Assistant 시작 스크립트
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env 파일 로드
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Elixir/Erlang 경로 설정
export ERLANG_HOME="$HOME/.asdf/installs/erlang/28.3"
export ELIXIR_HOME="$HOME/.asdf/installs/elixir/1.19.4-otp-28"
export PATH="$ELIXIR_HOME/bin:$ERLANG_HOME/bin:$PATH"

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
fi

if [[ -z "$FIRECRAWL_API_KEY" ]]; then
    echo -e "${YELLOW}[WARN]${NC} FIRECRAWL_API_KEY가 설정되지 않았습니다."
    echo "       export FIRECRAWL_API_KEY=\"your-firecrawl-api-key\""
    echo "       (웹 스크래핑/검색 기능이 비활성화됩니다)"
fi

cd "$SCRIPT_DIR"

# 의존성 확인
if [[ ! -d "deps" ]]; then
    echo -e "${GREEN}[INFO]${NC} 의존성 설치 중..."
    mix deps.get
fi

# 데이터베이스 마이그레이션
echo -e "${GREEN}[INFO]${NC} 데이터베이스 마이그레이션..."
mix ecto.create 2>/dev/null || true
mix ecto.migrate

# 서버 시작
echo -e "${GREEN}[INFO]${NC} Phoenix 서버 시작..."
echo -e "${BLUE}[INFO]${NC} 접속: http://localhost:4000/chat"
echo ""

mix phx.server
