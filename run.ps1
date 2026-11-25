# ============================================================
# Tech Fontes - Preventiva Corporativa Windows (One-Line Runner)
# Uso: irm techfontes.com.br/p | iex
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RawBase    = "https://raw.githubusercontent.com/Neanderthal86/tf-toolkit/main/Dist"
$ShortUrl   = "https://techfontes.com.br/p"
$InstallDir = "C:\ProgramData\TechFontes\Preventiva"

# 1. Eleva automaticamente para Administrador se necessario
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[TECH FONTES] Solicitando privilegios de Administrador..." -ForegroundColor Yellow
    $cmd = "irm '$ShortUrl' | iex"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs
    return
}

# 2. Baixa diretamente apenas os arquivos da pasta Dist/ (sem ZIP, ~2 segundos)
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

Write-Host "[TECH FONTES] Baixando arquivos da Preventiva ($($Files.Count) arquivos)..." -ForegroundColor Cyan

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

Write-Host "[TECH FONTES] Abrindo Painel da Preventiva..." -ForegroundColor Green
Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$panelScript`""
