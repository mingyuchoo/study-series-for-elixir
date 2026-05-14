param(
    [ValidateSet("deps", "build", "test", "run", "all", "help")]
    [string]$Command = "all"
)

$ErrorActionPreference = "Stop"

$AppRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $AppRoot

if ([string]::IsNullOrWhiteSpace($env:MIX_ENV)) {
    $MixEnv = "dev"
} else {
    $MixEnv = $env:MIX_ENV
}

if ([string]::IsNullOrWhiteSpace($env:MIX_TARGET)) {
    $MixTarget = "host"
} else {
    $MixTarget = $env:MIX_TARGET
}

if ([string]::IsNullOrWhiteSpace($env:SCENIC_WINDOW_TITLE)) {
    $ScenicWindowTitle = "elixir_watch"
} else {
    $ScenicWindowTitle = $env:SCENIC_WINDOW_TITLE
}

function Show-Usage {
    @"
Usage: .\scripts\run.ps1 [deps|build|test|run|all]

Commands:
  deps   Install Hex/Rebar if needed and fetch dependencies.
  build  Compile the Scenic desktop application.
  test   Run the test suite.
  run    Start the Scenic desktop application.
  all    Run deps, build, test, then run. This is the default.

Environment:
  MIX_ENV  Mix environment to use. Defaults to dev.
  MIX_TARGET  Scenic local target to build. Defaults to host.
  SCENIC_DEBUG  Set to 1 to enable Scenic local driver debug logging.
  SCENIC_VIEWPORT_SIZE  Viewport size as WIDTHxHEIGHT.
  SCENIC_WINDOW_TITLE  Window title used by the Scenic local driver. Defaults to elixir_watch.
"@
}

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name"
    }
}

function Setup-Mix {
    Require-Command "mix"
    mix local.hex --force
    mix local.rebar --force
}

function Test-PkgConfigPackage {
    param([string]$Name)

    if (-not (Get-Command "pkg-config" -ErrorAction SilentlyContinue)) {
        return $false
    }

    pkg-config --exists $Name
    return ($LASTEXITCODE -eq 0)
}

function Test-ScenicNativeDeps {
    $isWindows = $IsWindows -or ($env:OS -eq "Windows_NT")
    $isMacOS = $IsMacOS
    $isLinux = $IsLinux

    if ($isLinux -or $isMacOS) {
        Require-Command "pkg-config"

        if ((-not (Test-PkgConfigPackage "glfw3")) -or (-not (Test-PkgConfigPackage "glew"))) {
            if ($isMacOS) {
                throw "Missing Scenic native dependencies. Install them with: brew install pkg-config glfw glew"
            }

            throw "Missing Scenic native dependencies. Debian/Ubuntu: sudo apt install build-essential pkg-config libglfw3-dev libglew-dev"
        }
    } elseif ($isWindows) {
        Write-Host "Using Windows build tools from the current shell. Scenic local driver requires C/C++ build tools plus GLFW/GLEW available to the build environment."
    }
}

function Invoke-WithMixRuntime {
    param(
        [string]$Value,
        [scriptblock]$Script
    )

    $previousEnv = $env:MIX_ENV
    $previousTarget = $env:MIX_TARGET
    $previousTitle = $env:SCENIC_WINDOW_TITLE
    $env:MIX_ENV = $Value
    $env:MIX_TARGET = $MixTarget
    $env:SCENIC_WINDOW_TITLE = $ScenicWindowTitle

    try {
        & $Script
    } finally {
        if ($null -eq $previousEnv) {
            Remove-Item Env:MIX_ENV -ErrorAction SilentlyContinue
        } else {
            $env:MIX_ENV = $previousEnv
        }

        if ($null -eq $previousTarget) {
            Remove-Item Env:MIX_TARGET -ErrorAction SilentlyContinue
        } else {
            $env:MIX_TARGET = $previousTarget
        }

        if ($null -eq $previousTitle) {
            Remove-Item Env:SCENIC_WINDOW_TITLE -ErrorAction SilentlyContinue
        } else {
            $env:SCENIC_WINDOW_TITLE = $previousTitle
        }
    }
}

function Get-ScenicDriverBinary {
    param([string]$EnvName)

    $privDir = Join-Path $AppRoot "_build/$EnvName/lib/scenic_driver_local/priv"
    $binary = Join-Path $privDir "scenic_driver_local"
    $windowsBinary = Join-Path $privDir "scenic_driver_local.exe"

    if (Test-Path $windowsBinary) {
        return $windowsBinary
    }

    return $binary
}

function Ensure-ScenicDriverCompiled {
    param([string]$EnvName)

    $driverBinary = Get-ScenicDriverBinary $EnvName

    if (-not (Test-Path $driverBinary)) {
        Write-Host "Scenic local driver executable is missing; rebuilding scenic_driver_local for MIX_ENV=$EnvName."
        Invoke-WithMixRuntime $EnvName { mix deps.compile }

        if (-not (Test-Path $driverBinary)) {
            Invoke-WithMixRuntime $EnvName { mix deps.compile scenic_driver_local --force }
        }
    }
}

function Fetch-Deps {
    Setup-Mix
    Invoke-WithMixRuntime $MixEnv { mix deps.get }
}

function Build-App {
    Test-ScenicNativeDeps
    Ensure-ScenicDriverCompiled $MixEnv
    Invoke-WithMixRuntime $MixEnv { mix compile }
}

function Test-App {
    Test-ScenicNativeDeps
    Ensure-ScenicDriverCompiled "test"
    Invoke-WithMixRuntime "test" { mix test --no-start }
}

function Run-App {
    Invoke-WithMixRuntime $MixEnv { mix run --no-halt }
}

switch ($Command) {
    "deps" {
        Fetch-Deps
    }
    "build" {
        Fetch-Deps
        Build-App
    }
    "test" {
        Fetch-Deps
        Test-App
    }
    "run" {
        Fetch-Deps
        Build-App
        Run-App
    }
    "all" {
        Fetch-Deps
        Build-App
        Test-App
        Run-App
    }
    "help" {
        Show-Usage
    }
}
