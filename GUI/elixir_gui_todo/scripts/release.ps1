$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Prepare-Release {
  $env:MIX_ENV = "prod"
  $env:ELIXIR_GUI_TODO_DESKTOP = "true"

  mix compile
  mix assets.deploy
  mix release --overwrite

  $ResourceDir = Join-Path $Root "src-tauri/resources/elixir_gui_todo"
  New-Item -ItemType Directory -Force $ResourceDir | Out-Null
  Get-ChildItem $ResourceDir -Force |
    Where-Object { $_.Name -ne ".gitkeep" } |
    Remove-Item -Recurse -Force
  Copy-Item -Path (Join-Path $Root "_build/prod/rel/elixir_gui_todo/*") -Destination $ResourceDir -Recurse -Force
}

function Build-Installers {
  npm exec -- tauri build --bundles msi
}

$Command = if ($args.Count -gt 0) { $args[0] } else { "build" }

switch ($Command) {
  "build" {
    Build-Installers
  }
  "prepare" {
    Prepare-Release
  }
  { $_ -in @("-h", "--help", "help") } {
    Write-Host "Usage: scripts/release.ps1 [build|prepare]"
  }
  default {
    Write-Error "Usage: scripts/release.ps1 [build|prepare]"
    exit 64
  }
}
