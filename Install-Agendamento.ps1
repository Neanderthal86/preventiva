<#
.SYNOPSIS
    Registra a rotina de manutenção preventiva no Agendador de Tarefas do Windows do cliente.
    A preventiva rodará em modo invisível, usando permissões de SYSTEM, toda sexta-feira às 18:00.
#>

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Este script precisa ser executado como Administrador para criar tarefas agendadas."
    Start-Sleep -Seconds 3
    exit
}

$TaskName = "TechFontes-Preventiva-Semanal"
$Description = "Rotina corporativa de manutenção preventiva e envio de telemetria da Tech Fontes."

$ScriptPath = Join-Path $PSScriptRoot "Invoke-Preventiva.ps1"

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Script principal não encontrado em $ScriptPath"
    exit
}

# Configura a ação para rodar silenciosamente (Hidden)
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Mode Light -SubModo Execucao -Silent"

# Dispara toda sexta-feira às 18h
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At 18:00

# Roda como SYSTEM com maiores privilégios para não piscar tela para o usuário logado
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Configurações para garantir que rode em notebooks fora da tomada e que rode assim que possível se estiver desligado
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

try {
    Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -TaskName $TaskName -Description $Description -Force | Out-Null
    Write-Host "[SUCESSO] Tarefa '$TaskName' agendada com êxito!" -ForegroundColor Green
    Write-Host "Ela rodará o script $ScriptPath toda sexta-feira às 18:00 no modo Light/Execucao."
} catch {
    Write-Error "Falha ao registrar a tarefa agendada: $_"
}

Write-Host "Pressione qualquer tecla para sair..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
