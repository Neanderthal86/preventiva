function Invoke-WinUtilPreventiva {
    param(
        [ValidateSet("Light", "Moderate", "Heavy")]
        [string]$Mode = "Light"
    )

    $OutputFolder = "C:\ProgramData\Preventiva"
    $CriticalServices = @('BITS', 'wuauserv', 'Spooler', 'CryptSvc', 'LanmanWorkstation')

    switch ($Mode) {
        "Light" {
            $TempAgeDays = 3; $RunWU = $false; $RunTrim = $false; $RunWinSxS = $false
            $RunRestorePoint = $false; $RunDefender = $false; $RunDISM = $false; $RunSFC = $false
            $RunVarreduraCompleta = $false
        }
        "Moderate" {
            $TempAgeDays = 3; $RunWU = $true; $RunTrim = $true; $RunWinSxS = $false
            $RunRestorePoint = $false; $RunDefender = $true; $RunDISM = $false; $RunSFC = $false
            $RunVarreduraCompleta = $false
        }
        "Heavy" {
            $TempAgeDays = 3; $RunWU = $true; $RunTrim = $true; $RunWinSxS = $true
            $RunRestorePoint = $true; $RunDefender = $true; $RunDISM = $true; $RunSFC = $true
            $RunVarreduraCompleta = $true
        }
    }

    Initialize-PreventivaReporting -BaseLogDir $OutputFolder -Mode $Mode -SubModo "Execucao"

    Get-PreventivaInventory
    Get-PreventivaBatteryHealth
    Test-PreventivaNetwork
    Get-PreventivaDiskHealth -MinFreeSpaceGB 15
    Get-PreventivaStartupAndDrivers
    Test-PreventivaEvents -EventLimit 20

    Invoke-PreventivaMaintenance -ExecutarAcoes $true -TempAgeDays $TempAgeDays -CriticalServices $CriticalServices `
        -RunWU $RunWU -RunTrim $RunTrim -RunWinSxS $RunWinSxS -RunRestorePoint $RunRestorePoint -RunRecovery $false

    Invoke-PreventivaScans -RunVarreduraCompleta $RunVarreduraCompleta -ExecutarAcoes $true -LimitFileScanMB 200 -LargeFolderThresholdMB 100
    Get-PreventivaSecurity -RunDefenderScan $RunDefender
    Invoke-PreventivaIntegrity -RunDISM $RunDISM -RunSFC $RunSFC

    $CBS = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $WU  = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    $PendingRebootFlag = ($CBS -or $WU)
    $SpaceAfter  = try { [math]::Round((Get-PSDrive C).Free / 1GB, 2) } catch { 0 }
    $EspacoAntes = if ($global:PreventivaEspacoAntes) { $global:PreventivaEspacoAntes } else { 0 }
    $AvStatus    = if ($global:PreventivaAVStatus) { $global:PreventivaAVStatus } else { "Desconhecido" }

    Finalize-PreventivaReporting -Mode $Mode -ExecutarAcoes $true -AntivirusTexto $AvStatus `
        -PendingReboot $PendingRebootFlag -EspacoAntes $EspacoAntes -EspacoDepois $SpaceAfter
}
