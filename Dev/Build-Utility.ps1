<#
.SYNOPSIS
    Sincroniza os módulos da Preventiva (Dist\Modules), compila o WinUtil customizado
    e publica o arquivo final em Dist\TechFontes-Utility.ps1.
#>

$ErrorActionPreference = "Stop"
$WinUtilDir = Join-Path $PSScriptRoot "winutil-main"
$DistTarget = Join-Path $PSScriptRoot "..\Dist\TechFontes-Utility.ps1"

Push-Location -LiteralPath $WinUtilDir
try {
    Write-Host "[1/3] Sincronizando módulos de Dist\Modules para winutil-main..." -ForegroundColor Cyan
    & .\copy.ps1

    Write-Host "[2/3] Compilando winutil.ps1..." -ForegroundColor Cyan
    & .\Compile.ps1

    Write-Host "[3/3] Publicando em $DistTarget..." -ForegroundColor Cyan
    Copy-Item -LiteralPath (Join-Path $WinUtilDir "winutil.ps1") -Destination $DistTarget -Force

    Write-Host "[OK] TechFontes-Utility.ps1 atualizado com sucesso!" -ForegroundColor Green
} finally {
    Pop-Location
}
