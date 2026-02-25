#!/bin/bash
#
# TUI 실행 스크립트
# Agentic AI Terminal User Interface
#

set -e

# 스크립트 위치 = 프로젝트 루트
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$PROJECT_ROOT"

# .env 파일 로드
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# 옵션 처리
case "$1" in
    --help|-h)
        echo "Agentic AI - Terminal User Interface"
        echo ""
        echo "사용법: ./tui.sh [옵션]"
        echo ""
        echo "옵션:"
        echo "  --help, -h     이 도움말 표시"
        echo "  --compile, -c  컴파일 후 실행"
        echo "  --iex          IEx 셸과 함께 실행 (디버깅용)"
        echo ""
        echo "TUI 내부 명령어:"
        echo "  /new           새 대화 시작"
        echo "  /list          대화 목록 보기"
        echo "  /select <번호> 대화 선택"
        echo "  /delete <번호> 대화 삭제"
        echo "  /profile       사용자 프로필 보기"
        echo "  /clear         화면 지우기"
        echo "  /help          도움말"
        echo "  /quit, /exit   종료"
        exit 0
        ;;
    --compile|-c)
        echo "🔨 컴파일 중..."
        mix compile
        echo ""
        ;;
    --iex)
        echo "🚀 IEx 모드로 TUI 시작..."
        echo "   TUI.run()을 입력하여 시작하세요."
        echo ""
        exec iex -S mix
        ;;
esac

# 환경 변수 확인
if [ -z "$AZURE_OPENAI_ENDPOINT" ] || [ -z "$AZURE_OPENAI_API_KEY" ]; then
    echo "⚠️  경고: Azure OpenAI 환경 변수가 설정되지 않았습니다."
    echo ""
    echo "다음 환경 변수를 설정하세요:"
    echo "  export AZURE_OPENAI_ENDPOINT=\"https://your-resource.openai.azure.com\""
    echo "  export AZURE_OPENAI_API_KEY=\"your-api-key\""
    echo ""
fi

# TUI 실행
echo "🚀 Agentic AI TUI 시작..."
exec elixir -S mix run -e "TUI.run()"
