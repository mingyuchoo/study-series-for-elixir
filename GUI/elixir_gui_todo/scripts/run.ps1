$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Show-Usage {
  Write-Host "Usage: scripts/run.ps1 [all|build|test|run]"
}

function Ensure-Deps {
  mix deps.get
  mix assets.setup
}

function Prepare-Database {
  New-Item -ItemType Directory -Force (Join-Path $Root "data") | Out-Null
  mix ecto.create --quiet
  mix ecto.migrate --quiet
}

function Build-App {
  Ensure-Deps
  Prepare-Database
  mix assets.build
}

function Test-App {
  mix precommit
}

function Run-App {
  $env:ELIXIR_GUI_TODO_NO_WATCHERS = "true"
  mix phx.server
}

$Command = if ($args.Count -gt 0) { $args[0] } else { "all" }

switch ($Command) {
  "all" {
    Build-App
    Test-App
    Run-App
  }
  "build" {
    Build-App
  }
  "test" {
    Test-App
  }
  "run" {
    Prepare-Database
    Run-App
  }
  { $_ -in @("-h", "--help", "help") } {
    Show-Usage
  }
  default {
    Show-Usage
    exit 64
  }
}
