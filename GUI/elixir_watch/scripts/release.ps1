param(
    [ValidateSet("deps", "build", "msi", "all", "clean", "help")]
    [string]$Command = "all"
)

$ErrorActionPreference = "Stop"

$AppRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $AppRoot

$AppName = "elixir_watch"
$PackageName = "elixir-watch"
$DisplayName = "Elixir Watch"
$Manufacturer = "mingyuchoo"
$MixEnv = if ([string]::IsNullOrWhiteSpace($env:MIX_ENV)) { "prod" } else { $env:MIX_ENV }
$MixTarget = if ([string]::IsNullOrWhiteSpace($env:MIX_TARGET)) { "host" } else { $env:MIX_TARGET }
$DistDir = if ([string]::IsNullOrWhiteSpace($env:DIST_DIR)) { Join-Path $AppRoot "dist" } else { $env:DIST_DIR }
$PackageBuildDir = Join-Path $AppRoot "_build/package"

function Show-Usage {
    @"
Usage: .\scripts\release.ps1 [deps|build|msi|all|clean]

Commands:
  deps   Install Hex/Rebar and fetch production dependencies.
  build  Build the production Mix release.
  msi    Build a Windows .msi package from the production release.
  all    Build the Windows .msi package. This is the default.
  clean  Remove packaging output under dist/ and _build/package.

Environment:
  MIX_ENV     Defaults to prod.
  MIX_TARGET  Defaults to host.
  DIST_DIR    Output directory. Defaults to .\dist.

Requirements:
  Elixir/Mix, Windows C/C++ build tools for Scenic native dependencies,
  and WiX Toolset v3 (candle.exe/light.exe) or WiX v4+ (wix.exe).
"@
}

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name"
    }
}

function Invoke-WithMixRuntime {
    param(
        [scriptblock]$Script
    )

    $previousEnv = $env:MIX_ENV
    $previousTarget = $env:MIX_TARGET
    $env:MIX_ENV = $MixEnv
    $env:MIX_TARGET = $MixTarget

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
    }
}

function Get-AppVersion {
    Invoke-WithMixRuntime {
        $output = mix run --no-start -e "IO.write(Mix.Project.config()[:version])"
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to read Mix project version."
        }
        return $output
    }
}

function Get-ReleaseDir {
    return Join-Path $AppRoot "_build/$MixEnv/rel/$AppName"
}

function New-Directory {
    param([string]$Path)

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Fetch-Deps {
    Require-Command "mix"
    mix local.hex --force
    mix local.rebar --force
    Invoke-WithMixRuntime { mix deps.get --only $MixEnv }
}

function Build-Release {
    Fetch-Deps
    Invoke-WithMixRuntime { mix compile }
    Invoke-WithMixRuntime { mix release --overwrite }
}

function Copy-Release {
    param([string]$Target)

    if (Test-Path $Target) {
        Remove-Item -Recurse -Force $Target
    }

    New-Directory (Split-Path -Parent $Target)
    Copy-Item -Recurse -Force (Get-ReleaseDir) $Target
}

function Convert-ToWixId {
    param([string]$Value)

    $id = $Value -replace '[^A-Za-z0-9_\.]', '_'
    if ($id -match '^[0-9]') {
        $id = "I_$id"
    }

    if ($id.Length -gt 70) {
        $hashBytes = [System.Security.Cryptography.SHA1]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
        $hash = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
        $id = $id.Substring(0, 29) + "_" + $hash.Substring(0, 40)
    }

    return $id
}

function Get-RelativePath {
    param(
        [string]$Base,
        [string]$Path
    )

    $baseUri = [System.Uri]((Resolve-Path $Base).Path.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [System.Uri]((Resolve-Path $Path).Path)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Add-WixDirectory {
    param(
        [System.Xml.XmlDocument]$Document,
        [System.Xml.XmlElement]$Parent,
        [System.IO.DirectoryInfo]$Directory,
        [string]$BaseDir,
        [System.Collections.Generic.List[string]]$ComponentIds
    )

    foreach ($childDir in Get-ChildItem -LiteralPath $Directory.FullName -Directory | Sort-Object FullName) {
        $relative = Get-RelativePath $BaseDir $childDir.FullName
        $dirElement = $Document.CreateElement("Directory", $Document.DocumentElement.NamespaceURI)
        $dirElement.SetAttribute("Id", "D_" + (Convert-ToWixId $relative))
        $dirElement.SetAttribute("Name", $childDir.Name)
        [void]$Parent.AppendChild($dirElement)
        Add-WixDirectory -Document $Document -Parent $dirElement -Directory $childDir -BaseDir $BaseDir -ComponentIds $ComponentIds
    }

    foreach ($file in Get-ChildItem -LiteralPath $Directory.FullName -File | Sort-Object FullName) {
        $relative = Get-RelativePath $BaseDir $file.FullName
        $componentId = "C_" + (Convert-ToWixId $relative)
        $fileId = "F_" + (Convert-ToWixId $relative)

        $component = $Document.CreateElement("Component", $Document.DocumentElement.NamespaceURI)
        $component.SetAttribute("Id", $componentId)
        $component.SetAttribute("Guid", "*")
        [void]$Parent.AppendChild($component)

        $fileElement = $Document.CreateElement("File", $Document.DocumentElement.NamespaceURI)
        $fileElement.SetAttribute("Id", $fileId)
        $fileElement.SetAttribute("Source", $file.FullName)
        $fileElement.SetAttribute("KeyPath", "yes")
        [void]$component.AppendChild($fileElement)

        $ComponentIds.Add($componentId)
    }
}

function New-WixSource {
    param(
        [string]$StageDir,
        [string]$Version,
        [string]$OutputPath
    )

    $namespace = "http://schemas.microsoft.com/wix/2006/wi"
    $document = New-Object System.Xml.XmlDocument
    $declaration = $document.CreateXmlDeclaration("1.0", "UTF-8", $null)
    [void]$document.AppendChild($declaration)

    $wix = $document.CreateElement("Wix", $namespace)
    [void]$document.AppendChild($wix)

    $product = $document.CreateElement("Product", $namespace)
    $product.SetAttribute("Id", "*")
    $product.SetAttribute("Name", $DisplayName)
    $product.SetAttribute("Language", "1033")
    $product.SetAttribute("Version", $Version)
    $product.SetAttribute("Manufacturer", $Manufacturer)
    $product.SetAttribute("UpgradeCode", "3F319924-78E9-4ACB-A541-783FDF314C56")
    [void]$wix.AppendChild($product)

    $package = $document.CreateElement("Package", $namespace)
    $package.SetAttribute("InstallerVersion", "500")
    $package.SetAttribute("Compressed", "yes")
    $package.SetAttribute("InstallScope", "perMachine")
    [void]$product.AppendChild($package)

    $majorUpgrade = $document.CreateElement("MajorUpgrade", $namespace)
    $majorUpgrade.SetAttribute("DowngradeErrorMessage", "A newer version of $DisplayName is already installed.")
    [void]$product.AppendChild($majorUpgrade)

    $mediaTemplate = $document.CreateElement("MediaTemplate", $namespace)
    [void]$product.AppendChild($mediaTemplate)

    $targetDir = $document.CreateElement("Directory", $namespace)
    $targetDir.SetAttribute("Id", "TARGETDIR")
    $targetDir.SetAttribute("Name", "SourceDir")
    [void]$product.AppendChild($targetDir)

    $programFiles = $document.CreateElement("Directory", $namespace)
    $programFiles.SetAttribute("Id", "ProgramFilesFolder")
    [void]$targetDir.AppendChild($programFiles)

    $installDir = $document.CreateElement("Directory", $namespace)
    $installDir.SetAttribute("Id", "INSTALLFOLDER")
    $installDir.SetAttribute("Name", $DisplayName)
    [void]$programFiles.AppendChild($installDir)

    $componentIds = New-Object 'System.Collections.Generic.List[string]'
    Add-WixDirectory -Document $document -Parent $installDir -Directory (Get-Item $StageDir) -BaseDir $StageDir -ComponentIds $componentIds

    $feature = $document.CreateElement("Feature", $namespace)
    $feature.SetAttribute("Id", "DefaultFeature")
    $feature.SetAttribute("Title", $DisplayName)
    $feature.SetAttribute("Level", "1")
    [void]$product.AppendChild($feature)

    foreach ($componentId in $componentIds) {
        $componentRef = $document.CreateElement("ComponentRef", $namespace)
        $componentRef.SetAttribute("Id", $componentId)
        [void]$feature.AppendChild($componentRef)
    }

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
    try {
        $document.Save($writer)
    } finally {
        $writer.Close()
    }
}

function Invoke-WixBuild {
    param(
        [string]$WxsPath,
        [string]$MsiPath
    )

    $wix = Get-Command "wix" -ErrorAction SilentlyContinue
    if ($wix) {
        & $wix.Source build $WxsPath -o $MsiPath
        if ($LASTEXITCODE -ne 0) {
            throw "wix build failed."
        }
        return
    }

    $candle = Get-Command "candle" -ErrorAction SilentlyContinue
    $light = Get-Command "light" -ErrorAction SilentlyContinue
    if (-not $candle -or -not $light) {
        throw "Missing WiX Toolset. Install WiX v3 with candle.exe/light.exe, or WiX v4+ with wix.exe."
    }

    $wixObj = [System.IO.Path]::ChangeExtension($WxsPath, ".wixobj")
    & $candle.Source -out $wixObj $WxsPath
    if ($LASTEXITCODE -ne 0) {
        throw "candle.exe failed."
    }

    & $light.Source -out $MsiPath $wixObj
    if ($LASTEXITCODE -ne 0) {
        throw "light.exe failed."
    }
}

function Build-Msi {
    if (-not ($IsWindows -or $env:OS -eq "Windows_NT")) {
        throw "Windows .msi packages must be built on Windows."
    }

    Build-Release
    $version = Get-AppVersion
    New-Directory $DistDir
    New-Directory $PackageBuildDir

    $stageDir = Join-Path $PackageBuildDir "windows-msi/$DisplayName"
    if (Test-Path $stageDir) {
        Remove-Item -Recurse -Force $stageDir
    }
    New-Directory $stageDir

    Copy-Release (Join-Path $stageDir "rel")

    $launcher = Join-Path $stageDir "$AppName.cmd"
    @"
@echo off
setlocal
set APP_DIR=%~dp0
"%APP_DIR%rel\bin\$AppName.bat" start %*
"@ | Set-Content -Encoding ASCII $launcher

    $wxsPath = Join-Path $PackageBuildDir "$PackageName.wxs"
    $msiPath = Join-Path $DistDir "${PackageName}_${version}_windows.msi"
    New-WixSource -StageDir $stageDir -Version $version -OutputPath $wxsPath
    Invoke-WixBuild -WxsPath $wxsPath -MsiPath $msiPath
}

function Clean {
    if (Test-Path $DistDir) {
        Remove-Item -Recurse -Force $DistDir
    }

    if (Test-Path $PackageBuildDir) {
        Remove-Item -Recurse -Force $PackageBuildDir
    }
}

switch ($Command) {
    "deps" {
        Fetch-Deps
    }
    "build" {
        Build-Release
    }
    "msi" {
        Build-Msi
    }
    "all" {
        Build-Msi
    }
    "clean" {
        Clean
    }
    "help" {
        Show-Usage
    }
}
