# ============================================================
# Tech Fontes - TF-Toolkit v4.0 (One-Line Runner)
# Uso: irm techfontes.com.br/p | iex
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# --- Configuracao editavel do Banner ---
$BannerTitle    = "====Tech Fontes===="
$BannerSubtitle = "=====TF-Toolkit===="
$AppVersion     = "4.0"
$SiteUrl        = "techfontes.com.br"
# ---------------------------------------

$RepoZipUrl = "https://github.com/Neanderthal86/tf-toolkit/archive/refs/heads/main.zip"
$ShortUrl   = "https://techfontes.com.br/p"
$InstallDir = "C:\ProgramData\TechFontes\TF-Toolkit"

# 1. Eleva automaticamente para Administrador se necessario
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $cmd = "irm '$ShortUrl' | iex"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs
    return
}

# 2. Exibe banner ASCII (TF)
$BannerArt = @"

TTTTTTTTTTTTTTTTTTTTTTTFFFFFFFFFFFFFFFFFFFFFF
T:::::::::::::::::::::TF::::::::::::::::::::F
T:::::::::::::::::::::TF::::::::::::::::::::F
T:::::TT:::::::TT:::::TF::::::FFFFFFFFF:::::F
TTTTTT  T:::::T  TTTTTTFF:::::F       FFFFFF
        T:::::T         F:::::F
        T:::::T         F::::::FFFFFFFFFF
        T:::::T         F:::::::::::::::F
        T:::::T         F:::::::::::::::F
        T:::::T         F::::::FFFFFFFFFF
        T:::::T         F:::::F
        T:::::T         F:::::F
      TT:::::::TT     FF:::::::FF
      T:::::::::T     F::::::::FF
      T:::::::::T     F::::::::FF
      TTTTTTTTTTT     FFFFFFFFFFF

"@

Write-Host $BannerArt -ForegroundColor DarkYellow
Write-Host $BannerTitle -ForegroundColor White
Write-Host $BannerSubtitle -ForegroundColor Cyan
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
$osVer = [System.Environment]::OSVersion.VersionString
Write-Host "[$ts] [INFO] [TF-Toolkit] TF-Toolkit $AppVersion on PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition)), $osVer, process $PID." -ForegroundColor Gray
Write-Host "[$ts] [INFO] [TF-Toolkit] $SiteUrl" -ForegroundColor DarkGray

# 3. Baixa e extrai rapidamente via .NET ZipFile (muito mais rapido que Expand-Archive)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$tempRoot = Join-Path $env:TEMP ("TF-Toolkit-" + [guid]::NewGuid().ToString("N"))
$zipPath  = Join-Path $tempRoot "tf-toolkit.zip"
$extPath  = Join-Path $tempRoot "ext"

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $wc = New-Object System.Net.WebClient
    try { $wc.DownloadFile($RepoZipUrl, $zipPath) } finally { $wc.Dispose() }

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extPath)
    $repoFolder = Get-ChildItem -LiteralPath $extPath -Directory | Select-Object -First 1

    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path (Join-Path $repoFolder.FullName "*") -Destination $InstallDir -Recurse -Force

    $guiScript = Join-Path $InstallDir "WinForge.Gui.ps1"
    if (-not (Test-Path -LiteralPath $guiScript)) {
        throw "WinForge.Gui.ps1 nao encontrado em $InstallDir"
    }

    $ts2 = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Write-Host "[$ts2] [INFO] [UI] Starting the interface thread." -ForegroundColor Gray
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$guiScript`""
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
