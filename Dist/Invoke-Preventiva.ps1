# ============================================
# TECH FONTES - PREVENTIVA CORPORATIVA WINDOWS
# (Orquestrador modular com presets e tarefas granulares)
# ============================================

param(
    [string]$Mode = "Light",
    [string]$SubModo = "Execucao",
    [string[]]$Tasks,
    [string[]]$Tweaks,
    [switch]$UndoTweaks,
    [switch]$OptimizePower,
    [string[]]$SoftwareToInstall,
    [switch]$UpgradeAllSoftware,
    [switch]$Silent
)

$Mode = $Mode.Trim(); $SubModo = $SubModo.Trim()

# 1. Carregar Configurações
$BaseDir = $PSScriptRoot
if (-not $BaseDir) { $BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ConfigFile = Join-Path $BaseDir "Config\settings.json"
if (-not (Test-Path $ConfigFile)) {
    Write-Host "[ERRO FATAL] Arquivo de configuração não encontrado: $ConfigFile" -ForegroundColor Red
    Start-Sleep -Seconds 5
    return
}
$Config = Get-Content $ConfigFile -Encoding UTF8 -Raw | ConvertFrom-Json

# Normaliza listas caso venham como string separada por vírgula (ex.: via Painel-Preventiva.ps1)
if ($SoftwareToInstall) {
    $SoftwareToInstall = @($SoftwareToInstall | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if ($Tasks) {
    $Tasks = @($Tasks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if ($Tweaks) {
    $Tweaks = @($Tweaks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# 2. Carregar Módulos
Import-Module (Join-Path $BaseDir "Modules\Reporting.psm1") -Force
Import-Module (Join-Path $BaseDir "Modules\SystemInventory.psm1") -Force
Import-Module (Join-Path $BaseDir "Modules\Diagnostics.psm1") -Force
Import-Module (Join-Path $BaseDir "Modules\Maintenance.psm1") -Force
Import-Module (Join-Path $BaseDir "Modules\Optimization.psm1") -Force
Import-Module (Join-Path $BaseDir "Modules\Software.psm1") -Force

# 3. Inicializar Lógica de Modos / Tarefas Granulares
$ExecutarAcoes = ($SubModo -eq "Execucao")

if ($Tasks -and $Tasks.Count -gt 0) {
    # Modo granular: executa apenas as tarefas marcadas
    $RunInventory        = $Tasks -contains "Inventory"
    $RunDiskEvents       = $Tasks -contains "DiskEvents"
    $RunCriticalServices = $Tasks -contains "CriticalServices"
    $RunTempCleanup      = $Tasks -contains "CleanTemp"
    $RunRecycleBin       = $Tasks -contains "EmptyRecycleBin"
    $RunFlushDns         = $Tasks -contains "FlushDns"
    $RunVarredura        = ($Tasks -contains "FolderScan") -or ($Tasks -contains "FullFileScan")
    $RunVarreduraCompleta = $Tasks -contains "FullFileScan"
    $RunSecurityAudit    = ($Tasks -contains "SecurityAudit") -or ($Tasks -contains "DefenderScan")
    $RunDefender         = $Tasks -contains "DefenderScan"
    $RunWU               = $Tasks -contains "WindowsUpdate"
    $RunTrim             = $Tasks -contains "Trim"
    $RunDISM             = $Tasks -contains "Integrity"
    $RunSFC              = $Tasks -contains "Integrity"
    $RunWinSxS           = $Tasks -contains "WinSxS"
    $RunRestorePoint     = $Tasks -contains "RestorePoint"
    $RunRecovery         = $Tasks -contains "Recovery"
} else {
    # Modo preset padrão (compatível com CLI e agendamento semanal)
    $RunInventory        = $true
    $RunDiskEvents       = $true
    $RunCriticalServices = $true
    $RunTempCleanup      = $true
    $RunRecycleBin       = $true
    $RunFlushDns         = $true
    $RunSecurityAudit    = $true

    switch ($Mode) {
        "Light"    { $RunWU=$false; $RunDISM=$false; $RunSFC=$false; $RunRecovery=$false; $RunDefender=$false; $RunTrim=$false; $RunWinSxS=$false; $RunRestorePoint=$false; $RunVarredura=$true;  $RunVarreduraCompleta=$false }
        "Moderate" { $RunWU=$true;  $RunDISM=$false; $RunSFC=$false; $RunRecovery=$false; $RunDefender=$true;  $RunTrim=$true;  $RunWinSxS=$false; $RunRestorePoint=$false; $RunVarredura=$true;  $RunVarreduraCompleta=$false }
        "Heavy"    { $RunWU=$true;  $RunDISM=$true;  $RunSFC=$true;  $RunRecovery=$false; $RunDefender=$true;  $RunTrim=$true;  $RunWinSxS=$true;  $RunRestorePoint=$true;  $RunVarredura=$true;  $RunVarreduraCompleta=$true }
        "Recovery" { $RunWU=$true;  $RunDISM=$true;  $RunSFC=$true;  $RunRecovery=$true;  $RunDefender=$true;  $RunTrim=$true;  $RunWinSxS=$true;  $RunRestorePoint=$true;  $RunVarredura=$true;  $RunVarreduraCompleta=$true }
        default    { $RunWU=$false; $RunDISM=$false; $RunSFC=$false; $RunRecovery=$false; $RunDefender=$false; $RunTrim=$false; $RunWinSxS=$false; $RunRestorePoint=$false; $RunVarredura=$true;  $RunVarreduraCompleta=$false }
    }
}

# Em Diagnostico, trava acoes destrutivas ou demoradas
$RunWU                = $RunWU                -and $ExecutarAcoes
$RunTrim              = $RunTrim              -and $ExecutarAcoes
$RunDISM              = $RunDISM              -and $ExecutarAcoes
$RunSFC               = $RunSFC               -and $ExecutarAcoes
$RunWinSxS            = $RunWinSxS            -and $ExecutarAcoes
$RunRestorePoint      = $RunRestorePoint      -and $ExecutarAcoes
$RunRecovery          = $RunRecovery          -and $ExecutarAcoes
$RunVarreduraCompleta = $RunVarreduraCompleta -and $ExecutarAcoes
$RunScanDefenderReal  = $RunDefender          -and $ExecutarAcoes

function Test-PendingReboot {
    $CBS = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $WU  = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    return ($CBS -or $WU)
}

# 4. Iniciar Execução
Initialize-PreventivaReporting -BaseLogDir $Config.ReportSettings.OutputFolder -Mode $Mode -SubModo $SubModo
$global:PreventivaEspacoAntes = try { [math]::Round((Get-PSDrive C).Free/1GB,2) } catch { 0 }

# Inventário e Rede
if ($RunInventory) {
    Get-PreventivaInventory
    Get-PreventivaBatteryHealth
    Test-PreventivaNetwork
}

# Disco e Eventos (Diagnósticos)
if ($RunDiskEvents) {
    Get-PreventivaDiskHealth -MinFreeSpaceGB $Config.MinFreeSpaceGB
    Get-PreventivaStartupAndDrivers
    Test-PreventivaEvents -EventLimit $Config.EventLimit
}

# Limpeza e Manutenção
$RunAnyMaintenance = $RunCriticalServices -or $RunTempCleanup -or $RunRecycleBin -or $RunFlushDns -or $RunWU -or $RunTrim -or $RunWinSxS -or $RunRestorePoint -or $RunRecovery
if ($RunAnyMaintenance) {
    Invoke-PreventivaMaintenance -ExecutarAcoes $ExecutarAcoes -TempAgeDays $Config.TempAgeDays -CriticalServices $Config.CriticalServices `
        -RunWU $RunWU -RunTrim $RunTrim -RunWinSxS $RunWinSxS -RunRestorePoint $RunRestorePoint -RunRecovery $RunRecovery `
        -RunCriticalServices $RunCriticalServices -RunTempCleanup $RunTempCleanup -RunRecycleBin $RunRecycleBin -RunFlushDns $RunFlushDns
}

# Varreduras, Segurança e Integridade
if ($RunVarredura) {
    Invoke-PreventivaScans -RunVarreduraCompleta $RunVarreduraCompleta -ExecutarAcoes $ExecutarAcoes -LimitFileScanMB $Config.LimitFileScanMB -LargeFolderThresholdMB $Config.LargeFolderThresholdMB
}
if ($RunSecurityAudit) {
    Get-PreventivaSecurity -RunDefenderScan $RunScanDefenderReal
}
if ($RunDISM -or $RunSFC) {
    Invoke-PreventivaIntegrity -RunDISM $RunDISM -RunSFC $RunSFC
}

# Otimizações / Tweaks (se solicitado)
if ($Tweaks -and $Tweaks.Count -gt 0 -and $ExecutarAcoes) {
    Invoke-PreventivaTweaks -Tweaks $Tweaks -Undo:$UndoTweaks
} elseif ($OptimizePower -and $ExecutarAcoes) {
    Set-PreventivaHighPerformance
}

# Instalação / Atualização de Softwares (se solicitado)
if ($SoftwareToInstall -and $SoftwareToInstall.Count -gt 0 -and $ExecutarAcoes) {
    Install-PreventivaSoftware -AppIds $SoftwareToInstall
}
if ($UpgradeAllSoftware -and $ExecutarAcoes) {
    Update-PreventivaAllSoftware
}

# 5. Finalizar
$PendingRebootFlag = Test-PendingReboot
$SpaceAfter = try { [math]::Round((Get-PSDrive C).Free/1GB,2) } catch { 0 }

$EspacoAntes = if ($global:PreventivaEspacoAntes) { $global:PreventivaEspacoAntes } else { 0 }
$AvStatus    = if ($global:PreventivaAVStatus) { $global:PreventivaAVStatus } else { "Não verificado" }

$WebhookUrl = if ($Config.ReportSettings.WebhookUrl) { $Config.ReportSettings.WebhookUrl } else { "" }
$SendWebhookOnlyOnAlerts = if ($null -ne $Config.ReportSettings.SendWebhookOnlyOnAlerts) { $Config.ReportSettings.SendWebhookOnlyOnAlerts } else { $true }
Finalize-PreventivaReporting -Mode $Mode -ExecutarAcoes $ExecutarAcoes -AntivirusTexto $AvStatus -PendingReboot $PendingRebootFlag -EspacoAntes $EspacoAntes -EspacoDepois $SpaceAfter -WebhookUrl $WebhookUrl -SendWebhookOnlyOnAlerts $SendWebhookOnlyOnAlerts
