#Requires -Version 5.1
<#
.SYNOPSIS
    Valida a integridade do repositório TF-Toolkit antes de publicar (BOM UTF-8, sintaxe PowerShell 5.1, run.ps1 ASCII e ausência de mojibake).
.EXAMPLE
    .\tools\Test-Release.ps1
    .\tools\Test-Release.ps1 -FixBom
#>
param (
    [switch]$FixBom
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$issues = New-Object System.Collections.Generic.List[string]

Write-Host "=== TF-Toolkit Release Validator ===" -ForegroundColor Cyan

# 1. Validar run.ps1 (deve ser ASCII puro SEM BOM para funcionar em irm ... | iex)
$runPath = Join-Path $root "run.ps1"
if (Test-Path -LiteralPath $runPath -PathType Leaf) {
    $runBytes = [System.IO.File]::ReadAllBytes($runPath)
    if ($runBytes.Length -ge 3 -and $runBytes[0] -eq 239 -and $runBytes[1] -eq 187 -and $runBytes[2] -eq 191) {
        $issues.Add("run.ps1 possui UTF-8 BOM (deve ser ASCII puro sem BOM para irm | iex).")
    } elseif ($runBytes[0] -ne 35) {
        $issues.Add("run.ps1 não inicia com '#' (byte 0 = $($runBytes[0])).")
    } else {
        Write-Host "[OK] run.ps1 (ASCII sem BOM)" -ForegroundColor Green
    }
    try {
        $null = [scriptblock]::Create((Get-Content -LiteralPath $runPath -Raw))
    } catch {
        $issues.Add("Erro de sintaxe em run.ps1: $($_.Exception.Message)")
    }
}

# 2. Validar todos os arquivos .ps1 / .psm1 / .psd1 (exceto run.ps1): UTF-8 COM BOM + sintaxe + sem mojibake
$psFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.Extension -in '.ps1', '.psm1', '.psd1' -and
    $_.Name -ne 'run.ps1' -and
    $_.FullName -notmatch '\\\.git\\'
})

$fixedCount = 0
foreach ($f in $psFiles) {
    $rel = $f.FullName.Substring($root.Length + 1)
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)

    if (-not $hasBom) {
        if ($FixBom) {
            $bom = [byte[]](239, 187, 191)
            $out = New-Object byte[] ($bom.Length + $bytes.Length)
            [Array]::Copy($bom, 0, $out, 0, 3)
            [Array]::Copy($bytes, 0, $out, 3, $bytes.Length)
            [System.IO.File]::WriteAllBytes($f.FullName, $out)
            $fixedCount++
            Write-Host "[FIX] UTF-8 BOM restaurado: $rel" -ForegroundColor Yellow
        } else {
            $issues.Add("Sem UTF-8 BOM: $rel (rode com -FixBom para corrigir)")
        }
    }

    $txt = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    if ($txt -match '\u00C3[\u0080-\u00BF]|\u00C2[\u0080-\u00BF]') {
        $issues.Add("Possível mojibake detectado em: $rel")
    }

    try {
        $null = [scriptblock]::Create((Get-Content -LiteralPath $f.FullName -Raw))
    } catch {
        $issues.Add("Erro de sintaxe em ${rel}: $($_.Exception.Message)")
    }
}

Write-Host "[OK] $($psFiles.Count) scripts PowerShell verificados (BOM restaurado em $fixedCount)." -ForegroundColor Green

if ($issues.Count -gt 0) {
    Write-Host ""
    Write-Host "FALHAS ENCONTRADAS ($($issues.Count)):" -ForegroundColor Red
    foreach ($i in $issues) { Write-Host "  - $i" -ForegroundColor Red }
    exit 1
}

Write-Host ""
Write-Host "TUDO VALIDADO COM SUCESSO! Pronto para commit/push." -ForegroundColor Green
exit 0
