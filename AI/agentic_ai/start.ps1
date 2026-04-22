# ============================================
# Agentic AI Assistant 시작 스크립트 (Windows / PowerShell)
# ============================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# .env 파일 로드 (KEY=VALUE, # 으로 시작하는 주석 행 무시)
$EnvFile = Join-Path $ScriptDir '.env'
if (Test-Path -LiteralPath $EnvFile) {
    Get-Content -LiteralPath $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { return }

        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }

        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()

        # 양끝 따옴표 제거
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        Set-Item -Path "env:$key" -Value $value
    }
}

# Elixir/Erlang 경로 설정 (.tool-versions 기준, asdf 사용 시)
# Windows 의 Elixir/Erlang 설치 경로가 다르면 아래 블록을 환경에 맞게 수정하거나
# 시스템 PATH 에 등록된 설치본을 그대로 사용하세요.
$ErlangHome = Join-Path $HOME '.asdf\installs\erlang\28.4.2'
$ElixirHome = Join-Path $HOME '.asdf\installs\elixir\1.19.5-otp-28'

if (Test-Path -LiteralPath $ErlangHome) { $env:ERLANG_HOME = $ErlangHome }
if (Test-Path -LiteralPath $ElixirHome) { $env:ELIXIR_HOME = $ElixirHome }

$extraPath = @()
if ($env:ELIXIR_HOME) { $extraPath += (Join-Path $env:ELIXIR_HOME 'bin') }
if ($env:ERLANG_HOME) { $extraPath += (Join-Path $env:ERLANG_HOME 'bin') }
if ($extraPath.Count -gt 0) {
    $env:PATH = ($extraPath -join ';') + ';' + $env:PATH
}

# 배너
Write-Host ''
Write-Host '╔═══════════════════════════════════════╗' -ForegroundColor Blue
Write-Host '║     Agentic AI Assistant              ║' -ForegroundColor Blue
Write-Host '║     Elixir + Phoenix + Azure OpenAI   ║' -ForegroundColor Blue
Write-Host '╚═══════════════════════════════════════╝' -ForegroundColor Blue
Write-Host ''

# 환경 변수 확인
function Write-Warn($message, $hint) {
    Write-Host '[WARN]' -ForegroundColor Yellow -NoNewline
    Write-Host " $message"
    if ($hint) { Write-Host "       $hint" }
}

function Write-Info($message) {
    Write-Host '[INFO]' -ForegroundColor Green -NoNewline
    Write-Host " $message"
}

function Write-Link($message) {
    Write-Host '[INFO]' -ForegroundColor Blue -NoNewline
    Write-Host " $message"
}

# bcrypt_elixir 등 C NIF 의존성을 빌드하기 위해 MSVC(nmake) 환경을 현재 세션에 로드
function Initialize-MsvcEnvironment {
    if (Get-Command nmake.exe -ErrorAction SilentlyContinue) {
        return
    }

    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not $programFilesX86) { $programFilesX86 = 'C:\Program Files (x86)' }
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'

    if (-not (Test-Path -LiteralPath $vswhere)) {
        Write-Warn 'Visual Studio / Build Tools 를 찾을 수 없습니다 (bcrypt_elixir 컴파일에 nmake 필요).' `
            'https://visualstudio.microsoft.com/downloads/ 에서 "Build Tools for Visual Studio" 설치 후 "Desktop development with C++" 워크로드를 선택하세요.'
        return
    }

    # -all -prerelease 로 incomplete/prerelease 설치까지 포함해 VC 툴셋을 탐색하고
    # -find 로 vcvars64.bat 의 실제 경로를 직접 돌려받는다.
    $vcvars = & $vswhere -all -prerelease -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -find 'VC\Auxiliary\Build\vcvars64.bat' 2>$null |
        Select-Object -First 1

    if (-not $vcvars -or -not (Test-Path -LiteralPath $vcvars)) {
        Write-Warn 'MSVC C++ 툴셋(vcvars64.bat) 을 찾을 수 없습니다.' `
            'Visual Studio Installer 에서 "Desktop development with C++" 워크로드를 추가하세요.'
        return
    }

    Write-Info "MSVC 환경 로드: $vcvars"

    # cmd 에서 vcvars64 실행 후 환경변수 스냅샷을 파일로 덤프하고 현재 세션에 반영
    $tempFile = [IO.Path]::GetTempFileName()
    try {
        cmd.exe /s /c " `"$vcvars`" >nul && set > `"$tempFile`" "
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "vcvars64.bat 실행 실패 (exit=$LASTEXITCODE)"
            return
        }
        Get-Content -LiteralPath $tempFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                Set-Item -Path ("env:" + $Matches[1]) -Value $Matches[2]
            }
        }
    } finally {
        Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
    }

    if (-not (Get-Command nmake.exe -ErrorAction SilentlyContinue)) {
        Write-Warn 'MSVC 환경을 로드했으나 nmake 를 여전히 찾을 수 없습니다.'
    }
}

if ([string]::IsNullOrEmpty($env:AZURE_OPENAI_ENDPOINT)) {
    Write-Warn 'AZURE_OPENAI_ENDPOINT가 설정되지 않았습니다.' `
        '$env:AZURE_OPENAI_ENDPOINT = "https://your-resource.openai.azure.com"'
}

if ([string]::IsNullOrEmpty($env:AZURE_OPENAI_API_KEY)) {
    Write-Warn 'AZURE_OPENAI_API_KEY가 설정되지 않았습니다.' `
        '$env:AZURE_OPENAI_API_KEY = "your-api-key"'
}

if ([string]::IsNullOrEmpty($env:AZURE_OPENAI_DEPLOYMENT)) {
    Write-Warn 'AZURE_OPENAI_DEPLOYMENT 가 설정되지 않아 기본값 "gpt-5-mini" 를 사용합니다.' `
        'Azure 포털의 실제 배포 이름과 다르면 404 오류가 발생합니다. 예: $env:AZURE_OPENAI_DEPLOYMENT = "gpt-4o"'
}

if ([string]::IsNullOrEmpty($env:FIRECRAWL_API_KEY)) {
    Write-Warn 'FIRECRAWL_API_KEY가 설정되지 않았습니다.' `
        '$env:FIRECRAWL_API_KEY = "your-firecrawl-api-key"   (웹 스크래핑/검색 기능이 비활성화됩니다)'
}

Set-Location -LiteralPath $ScriptDir

# NIF(C 코드) 컴파일을 위한 MSVC 환경 준비 (bcrypt_elixir, exqlite 등)
Initialize-MsvcEnvironment

# 의존성 확인
if (-not (Test-Path -LiteralPath (Join-Path $ScriptDir 'deps'))) {
    Write-Info '의존성 설치 중...'
    mix deps.get
    if ($LASTEXITCODE -ne 0) { throw "mix deps.get 실패 (exit=$LASTEXITCODE)" }
}

# 프로젝트 컴파일 (프로토콜 컨솔리데이션 디렉터리 생성을 위해 명시적으로 수행)
# Elixir 1.19 의 일부 빌드 경로에서 _build/dev/consolidated 가 자동으로 생성되지 않아
# 후속 mix run / mix ecto.* 가 protocol consolidation 단계에서 실패하는 문제를 예방합니다.
$ConsolidatedDir = Join-Path $ScriptDir '_build/dev/consolidated'
if (-not (Test-Path -LiteralPath $ConsolidatedDir)) {
    New-Item -ItemType Directory -Force -Path $ConsolidatedDir | Out-Null
}
Write-Info '프로젝트 컴파일...'
mix compile
if ($LASTEXITCODE -ne 0) { throw "mix compile 실패 (exit=$LASTEXITCODE)" }

# 데이터베이스 마이그레이션
Write-Info '데이터베이스 마이그레이션...'
# ecto.create 는 이미 존재하면 오류 코드를 반환하므로 실패해도 계속 진행
& mix ecto.create *> $null
mix ecto.migrate
if ($LASTEXITCODE -ne 0) { throw "mix ecto.migrate 실패 (exit=$LASTEXITCODE)" }

# 초기 시드 (관리자 계정 / 에이전트 / MCP)
Write-Info '초기 데이터 시드...'
mix run apps/core/priv/repo/seeds.exs
if ($LASTEXITCODE -ne 0) { throw "seeds.exs 실행 실패 (exit=$LASTEXITCODE)" }

# 서버 시작
Write-Info 'Phoenix 서버 시작...'
Write-Link '접속: http://localhost:4000'
Write-Link '계정 생성 후 /chat 으로 이동하세요.'
Write-Host ''

mix phx.server
