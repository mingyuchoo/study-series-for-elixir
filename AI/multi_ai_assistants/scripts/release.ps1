#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$AppName = 'multi_ai_assistants'
$PackageName = 'multi-ai-assistants'
$DisplayName = 'Agentic AI'
$ReleaseDir = Join-Path $ProjectRoot "_build\prod\rel\$AppName"
$BuildDir = Join-Path $ProjectRoot '_build\release-packages\windows'
$DistDir = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $ProjectRoot 'dist' }

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Hint
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name. $Hint"
    }
}

function Get-ProjectVersion {
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        return $Version
    }

    Push-Location $ProjectRoot
    try {
        return (& mix eval 'Mix.Project.get!(); IO.write(Mix.Project.config()[:version])')
    } finally {
        Pop-Location
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

function Build-Release {
    Push-Location $ProjectRoot
    try {
        $env:MIX_ENV = 'prod'
        Invoke-Checked mix deps.get --only prod
        Invoke-Checked mix assets.deploy
        Invoke-Checked mix release --overwrite
    } finally {
        Pop-Location
    }
}

function Write-WixSource {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$ProductVersion
    )

    $escapedSourceDir = $SourceDir.Replace('\', '\\')
    $wxs = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package
      Name="$DisplayName"
      Manufacturer="mingyuchoo"
      Version="$ProductVersion"
      UpgradeCode="9f83a4ef-7bc4-42fc-83c2-302d4f2e7b3d">
    <MajorUpgrade DowngradeErrorMessage="A newer version of $DisplayName is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <StandardDirectory Id="ProgramFilesFolder">
      <Directory Id="INSTALLFOLDER" Name="$PackageName" />
    </StandardDirectory>

    <ComponentGroup Id="ApplicationFiles" Directory="INSTALLFOLDER">
      <Files Include="$escapedSourceDir\\**" />
    </ComponentGroup>

    <Feature Id="MainFeature" Title="$DisplayName" Level="1">
      <ComponentGroupRef Id="ApplicationFiles" />
    </Feature>
  </Package>
</Wix>
"@

    Set-Content -LiteralPath $Path -Value $wxs -Encoding UTF8
}

function Prepare-Stage {
    param([Parameter(Mandatory = $true)][string]$StageDir)

    if (Test-Path -LiteralPath $StageDir) {
        Remove-Item -LiteralPath $StageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

    Copy-Item -Path (Join-Path $ReleaseDir '*') -Destination $StageDir -Recurse -Force

    $envExample = @"
DATABASE_PATH=C:\ProgramData\$PackageName\$AppName.db
WORKSPACE_DIR=C:\ProgramData\$PackageName\workspace
PHX_HOST=localhost
PORT=4000
SECRET_KEY_BASE=replace-with-output-of-mix-phx-gen-secret
AZURE_OPENAI_ENDPOINT=
AZURE_OPENAI_API_KEY=
AZURE_OPENAI_API_VERSION=2024-10-21
FIRECRAWL_API_KEY=
CONTEXT7_API_KEY=
MCP_FILESYSTEM_ROOT=C:\ProgramData\$PackageName\workspace
"@
    Set-Content -LiteralPath (Join-Path $StageDir "$AppName.env.example") -Value $envExample -Encoding UTF8
}

function Build-Msi {
    param([Parameter(Mandatory = $true)][string]$ProductVersion)

    Assert-Command wix 'Install WiX Toolset v4 and ensure wix.exe is on PATH: dotnet tool install --global wix'

    $stageDir = Join-Path $BuildDir 'stage'
    $wxsPath = Join-Path $BuildDir "$PackageName.wxs"
    $msiPath = Join-Path $DistDir "$PackageName-$ProductVersion-windows.msi"

    New-Item -ItemType Directory -Force -Path $BuildDir, $DistDir | Out-Null
    Prepare-Stage -StageDir $stageDir
    Write-WixSource -Path $wxsPath -SourceDir $stageDir -ProductVersion $ProductVersion

    if (Test-Path -LiteralPath $msiPath) {
        Remove-Item -LiteralPath $msiPath -Force
    }

    Invoke-Checked wix build $wxsPath -o $msiPath
    Write-Host "Release artifact written to $msiPath"
}

Assert-Command mix 'Install Elixir and ensure mix is on PATH.'

$projectVersion = Get-ProjectVersion
Build-Release
Build-Msi -ProductVersion $projectVersion
