<#
.SYNOPSIS
    Empacota o TF-Toolkit em um arquivo .zip limpo pronto para GitHub Releases e gera o hash SHA-256.
#>
param(
    [string]$Version = "3.0"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Root "release"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$StageDir = Join-Path $env:TEMP ("TF-Toolkit-Stage-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

try {
    $include = @(
        "TF-Toolkit.ps1",
        "TF-Toolkit.bat",
        "Invoke-Preventiva.ps1",
        "Install-Agendamento.ps1",
        "LICENSE",
        "README.md",
        "assets",
        "config",
        "gui",
        "modules"
    )

    foreach ($item in $include) {
        $src = Join-Path $Root $item
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination $StageDir -Recurse -Force
        }
    }

    # Remove preferencias locais antes de empacotar
    Remove-Item -LiteralPath (Join-Path $StageDir "config\theme.pref") -ErrorAction SilentlyContinue

    $zipPath = Join-Path $OutDir "TF-Toolkit-v$Version.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $StageDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    $hashFile = "$zipPath.sha256"
    "$hash  TF-Toolkit-v$Version.zip" | Set-Content -LiteralPath $hashFile -Encoding ASCII

    Write-Host "[OK] Pacote gerado: $zipPath" -ForegroundColor Green
    Write-Host "[OK] SHA-256: $hash" -ForegroundColor Cyan
} finally {
    if (Test-Path -LiteralPath $StageDir) {
        Remove-Item -LiteralPath $StageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
