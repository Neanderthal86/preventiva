# ============================================================
# Tech Fontes - TF-Toolkit (One-Line Runner)
# Uso: irm techfontes.com.br/p | iex
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# --- Configuracao editavel do Banner ---
$BannerTitle    = "====Tech Fontes===="
$BannerSubtitle = "=====TF-Toolkit===="
$AppVersion     = "2.0"
$SiteUrl        = "techfontes.com.br"
# ---------------------------------------

$RawBase    = "https://raw.githubusercontent.com/Neanderthal86/tf-toolkit/main/Dist"
$ShortUrl   = "https://techfontes.com.br/p"
$InstallDir = "C:\ProgramData\TechFontes\Preventiva"

# 1. Eleva automaticamente para Administrador se necessario
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $cmd = "irm '$ShortUrl' | iex"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs
    return
}

# 2. Exibe banner ASCII estilo WinUtil (TF)
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

# 3. Sincroniza silenciosamente os arquivos de Dist/
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Files = @(
    "Painel-Preventiva.ps1",
    "Invoke-Preventiva.ps1",
    "Install-Agendamento.ps1",
    "Rodar-Preventiva.bat",
    "Rodar-Utilitario.bat",
    "TechFontes-Utility.ps1",
    "Assets/logo.png",
    "Config/settings.json",
    "Modules/SystemInventory.psm1",
    "Modules/Diagnostics.psm1",
    "Modules/Maintenance.psm1",
    "Modules/Optimization.psm1",
    "Modules/Software.psm1",
    "Modules/Reporting.psm1"
)

foreach ($sub in @("", "Assets", "Config", "Modules")) {
    $dir = if ($sub) { Join-Path $InstallDir $sub } else { $InstallDir }
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$wc = New-Object System.Net.WebClient
try {
    foreach ($rel in $Files) {
        $url = "$RawBase/$rel"
        $dest = Join-Path $InstallDir ($rel -replace '/', '\')
        $wc.DownloadFile($url, $dest)
    }
} finally {
    $wc.Dispose()
}

$panelScript = Join-Path $InstallDir "Painel-Preventiva.ps1"
if (-not (Test-Path -LiteralPath $panelScript)) {
    throw "Painel-Preventiva.ps1 nao encontrado em $InstallDir"
}

$ts2 = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
Write-Host "[$ts2] [INFO] [UI] Starting the interface thread." -ForegroundColor Gray
Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$panelScript`""
