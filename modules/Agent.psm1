# Monitor na bandeja: um ícone perto do relógio que fica de olho no PC e avisa quando algo pede atenção.
#
# O monitor é o TF-Toolkit.Agent.ps1, na pasta do TF-Toolkit. Ele começa com o Windows (uma entrada em Run, do usuário) e só
# lê: espaço no disco, disco com sinais de falha, proteção, reinício pendente, manutenção, suporte do Windows, programas
# desatualizados e o resultado do teste de memória, quando ele foi pedido. Cada aviso
# aparece no máximo uma vez a cada tanto tempo (veja Get-TFToolkitAgentChecks) e pode ser pausado por 24 horas no menu do
# ícone. Este módulo tem as regras (o que avisar e quando) e o liga/desliga; o script cuida do ícone.

$script:TFToolkitAgentRunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$script:TFToolkitAgentRunName = "TF-Toolkit Monitor"
# Onde o Gerenciador de Tarefas (aba Inicializar) marca uma entrada de Run como desativada.
$script:TFToolkitAgentApprovedKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
$script:TFToolkitAgentStopEvent = "Local\TFToolkit.Agent.Stop"
# Quanto tempo esperar o monitor aparecer depois de pedir a abertura.
$script:TFToolkitAgentStartWaitSeconds = 8


function Get-TFToolkitAgentActionIds {
    # As ações que o monitor pede à janela: as do menu do ícone e as dos avisos. A janela só roda estas quando o pedido
    # chega de outra abertura (Receive-TFToolkitWindowRequest).
    # app.monitor (Configurar o monitor) e cleanup.custom (Limpeza personalizada, do aviso de pouco espaço) só mostram a
    # tela de escolha, e app.update (Verificar nova versão, do aviso da versão nova) só consulta e pergunta antes de
    # baixar: nada muda sem um clique nelas.
    return @("performance.boost", "cleanup.quick", "cleanup.custom", "maintenance.checkup", "diagnostics.pending-reboot", "security.status", "diagnostics.windows-support", "updates.winget", "app.monitor", "diagnostics.disk-health", "diagnostics.memory-test", "diagnostics.blue-screens", "app.update")
}


function Get-TFToolkitAgentScriptPath {
    # O script do monitor desta pasta do TF-Toolkit (-Root: de outra, como a que o instalador acabou de atualizar).
    param ([string]$Root = (Get-TFToolkitAppRoot))

    return (Join-Path $Root "TF-Toolkit.Agent.ps1")
}


function Get-TFToolkitAgentStopEventName {
    return $script:TFToolkitAgentStopEvent
}


function Get-TFToolkitAgentCommandLine {
    # A linha que o Windows roda ao entrar: o PowerShell, oculto, com o script do monitor (-Root: o de outra pasta do
    # TF-Toolkit, como a que o instalador acabou de criar).
    param ([string]$Root = (Get-TFToolkitAppRoot))

    $script = Get-TFToolkitAgentScriptPath -Root $Root

    return "$(ConvertTo-TFToolkitCommandLineArgument -Value (Get-TFToolkitPowerShellPath)) -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File $(ConvertTo-TFToolkitCommandLineArgument -Value $script)"
}


function Get-TFToolkitAgentRunState {
    <#
    Se o monitor começa com o Windows: On; Off (sem a entrada); Elsewhere (a entrada aponta para outra pasta do TF-Toolkit,
    ou para um script que não existe mais: a pasta mudou de lugar); Disabled (desativado no Gerenciador de Tarefas, aba
    Inicializar: o Windows não roda a entrada).
    #>
    $value = [string](Get-TFToolkitRegistryValueOrNull -Path $script:TFToolkitAgentRunKey -Name $script:TFToolkitAgentRunName)

    if ([string]::IsNullOrWhiteSpace($value)) { return "Off" }

    $script = Get-TFToolkitAgentScriptPath

    if ($value.IndexOf($script, [StringComparison]::OrdinalIgnoreCase) -lt 0 -or -not (Test-Path -LiteralPath $script -PathType Leaf)) {
        return "Elsewhere"
    }

    # O primeiro byte ímpar (03, 07) é "desativado"; par (02, 06) ou sem o valor, "ativado".
    $approved = Get-TFToolkitRegistryValueOrNull -Path $script:TFToolkitAgentApprovedKey -Name $script:TFToolkitAgentRunName

    $first = $(if ($null -ne $approved) { @($approved)[0] } else { $null })

    if ($first -is [byte] -and ($first -band 1) -eq 1) { return "Disabled" }

    return "On"
}


function Test-TFToolkitAgentEnabled {
    # Se o monitor de fato começa com o Windows (a entrada existe, aponta para esta pasta e não foi desativada).
    return ((Get-TFToolkitAgentRunState) -eq "On")
}


function Get-TFToolkitAgentProcesses {
    # Os processos do monitor que estão rodando agora nesta sessão do Windows (pela linha de comando). Lista vazia se não
    # der para ler. Os monitores de outras contas logadas (troca rápida de usuário) não são deste usuário: ligar, abrir e
    # desligar nunca mexem neles.
    try {
        $session = [System.Diagnostics.Process]::GetCurrentProcess().SessionId

        return @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -OperationTimeoutSec 15 -ErrorAction Stop |
                Where-Object { [string]$_.CommandLine -like "*TF-Toolkit.Agent.ps1*" -and [int](Get-TFToolkitJsonValue -Object $_ -Name "SessionId" -Default $session) -eq $session })
    }
    catch {
        return @()
    }
}


function Test-TFToolkitAgentStartBlocked {
    # Se o monitor não deve ser ligado nem aberto daqui: com a conta de outro Administrador, ele ficaria no perfil dessa
    # conta. Na janela elevada da própria conta, ele abre sem a elevação (Start-TFToolkitAgent).
    return [bool](Test-TFToolkitUserContextMismatch)
}


function Start-TFToolkitAgent {
    <#
    Abre o monitor agora (o próprio script recusa uma segunda cópia) e devolve se ele apareceu em alguns segundos. O monitor
    nunca roda como Administrador: aberto direto da janela elevada, ele herdaria a elevação até o fim da sessão (e o "Abrir
    o TF-Toolkit" do menu abriria a janela elevada sem perguntar). Por isso, da janela elevada, ele abre por um atalho
    (monitor.lnk, na pasta de dados) entregue ao Explorador, que o abre na sessão da pessoa, sem elevação. Quem chama
    confere Test-TFToolkitAgentStartBlocked. Uma falha ao pedir a abertura vira um erro em português. -Root: o monitor de
    outra pasta do TF-Toolkit (a que o instalador acabou de atualizar).
    #>
    param ([string]$Root = (Get-TFToolkitAppRoot))

    $arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File $(ConvertTo-TFToolkitCommandLineArgument -Value (Get-TFToolkitAgentScriptPath -Root $Root))"

    try {
        if (Test-TFToolkitAdministrator) {
            $link = Join-Path (Get-TFToolkitDataPath) "monitor.lnk"
            [void](Save-TFToolkitShortcutFile -Path $link -Target (Get-TFToolkitPowerShellPath) -Arguments $arguments -WorkingDirectory $Root -Description (Get-TFToolkitText 'Monitor do TF-Toolkit'))
            Start-Process -FilePath "explorer.exe" -ArgumentList "`"$link`"" -ErrorAction Stop
        }
        else {
            Start-Process -FilePath (Get-TFToolkitPowerShellPath) -ArgumentList $arguments -WindowStyle Hidden -ErrorAction Stop
        }
    }
    catch {
        throw (Get-TFToolkitText 'o Windows não deixou abrir o monitor agora')
    }

    # O Explorador abre o atalho por conta própria, um instante depois: confere por alguns segundos se o monitor apareceu e
    # continuou aberto por 2 segundos. Um monitor que abriu elevado (o Explorador não fez a troca) fecha sozinho logo no
    # começo (TF-Toolkit.Agent.ps1), e aí a tela diz que ele abre com o Windows, e não "ligado".
    $seen = 0

    for ($i = 0; $i -lt ($script:TFToolkitAgentStartWaitSeconds * 2); $i++) {
        if (@(Get-TFToolkitAgentProcesses).Count -gt 0) { $seen++ } else { $seen = 0 }
        if ($seen -ge 4) { return $true }
        Start-Sleep -Milliseconds 500
    }

    return $false
}


function Stop-TFToolkitAgent {
    # Pede ao monitor que feche (pelo evento que ele escuta) e, se ele não fechar em alguns segundos, encerra o processo.
    try {
        $signal = [System.Threading.EventWaitHandle]::OpenExisting($script:TFToolkitAgentStopEvent)
        [void]$signal.Set()
        $signal.Dispose()
    }
    catch {
        Write-Verbose "O monitor não estava escutando: $($_.Exception.Message)"
    }

    for ($i = 0; $i -lt 10; $i++) {
        if (@(Get-TFToolkitAgentProcesses).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 500
    }

    foreach ($process in @(Get-TFToolkitAgentProcesses)) {
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
    }

    # Um monitor aberto como Administrador não fecha a pedido de uma janela sem elevação: quem chama diz isso.
    return (@(Get-TFToolkitAgentProcesses).Count -eq 0)
}


function Enable-TFToolkitAgent {
    <#
    Grava a entrada em Run (e tira a marca de "desativado" do Gerenciador de Tarefas, se houver) e abre o monitor. Devolve
    "Open" (aberto agora, ou já estava), "Later" (pedido, mas o ícone não apareceu em alguns segundos: abre com o Windows),
    "Blocked" (com a conta de outro Administrador: só fica configurado) ou "StartFailed" (configurado, mas o Windows não
    deixou abrir agora). Sem conseguir gravar a entrada, lança um erro em português e nada muda.
    #>
    if (-not (Test-Path -LiteralPath (Get-TFToolkitAgentScriptPath) -PathType Leaf)) {
        throw (Get-TFToolkitText 'o arquivo TF-Toolkit.Agent.ps1 não está na pasta do TF-Toolkit')
    }

    # O Windows não roda uma entrada de Run com 260 caracteres ou mais.
    $line = Get-TFToolkitAgentCommandLine

    if ($line.Length -ge 260) {
        throw (Get-TFToolkitText 'o caminho da pasta do TF-Toolkit é longo demais para o Windows abrir o monitor sozinho; mova a pasta do TF-Toolkit para um caminho mais curto')
    }

    # -ErrorAction Stop nos dois: sem ele, uma chave que não pode ser criada só escrevia um erro do Windows (em inglês) na
    # tela, e a gravação seguinte falhava com outro.
    try {
        if (-not (Test-Path -LiteralPath $script:TFToolkitAgentRunKey)) {
            [void](New-Item -Path $script:TFToolkitAgentRunKey -Force -ErrorAction Stop)
        }

        Set-ItemProperty -LiteralPath $script:TFToolkitAgentRunKey -Name $script:TFToolkitAgentRunName -Value $line -Type String -ErrorAction Stop
    }
    catch {
        throw (Get-TFToolkitText 'o Windows não deixou gravar a entrada que faz o monitor abrir com o Windows')
    }

    # Desativado antes no Gerenciador de Tarefas, o Windows continuaria sem rodar a entrada.
    try { Remove-TFToolkitRegistryValue -Path $script:TFToolkitAgentApprovedKey -Name $script:TFToolkitAgentRunName } catch { Write-Verbose "Marca de inicialização: $($_.Exception.Message)" }

    # Um monitor aberto de outra pasta do TF-Toolkit (a cópia antiga) seguiria abrindo a janela antiga até sair do Windows.
    $running = @(Get-TFToolkitAgentProcesses)
    $script = Get-TFToolkitAgentScriptPath

    if ($running.Count -gt 0 -and @($running | Where-Object { ([string]$_.CommandLine).IndexOf($script, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) { return "Open" }
    if (Test-TFToolkitAgentStartBlocked) { return "Blocked" }
    if ($running.Count -gt 0) { [void](Stop-TFToolkitAgent) }

    try {
        if (Start-TFToolkitAgent) { return "Open" }
    }
    catch {
        return "StartFailed"
    }

    return "Later"
}


function Move-TFToolkitAgentEntry {
    <#
    Faz a entrada de início do monitor abrir o da pasta Root quando ela abre o de outra pasta do TF-Toolkit (a extraída do
    zip, antes de instalar). A marca de desativado do Gerenciador de Tarefas fica como estava. Devolve se mudou; sem
    conseguir gravar, lança erro.
    #>
    param ([Parameter(Mandatory)][string]$Root)

    $value = [string](Get-TFToolkitRegistryValueOrNull -Path $script:TFToolkitAgentRunKey -Name $script:TFToolkitAgentRunName)
    $script = Get-TFToolkitAgentScriptPath -Root $Root

    if ([string]::IsNullOrWhiteSpace($value) -or $value -notmatch '(?i)TF-Toolkit\.Agent\.ps1') { return $false }
    if ($value.IndexOf($script, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { return $false }

    # O Windows não roda uma entrada de Run com 260 caracteres ou mais (Enable-TFToolkitAgent).
    $line = Get-TFToolkitAgentCommandLine -Root $Root
    if ($line.Length -ge 260) { return $false }

    Set-ItemProperty -LiteralPath $script:TFToolkitAgentRunKey -Name $script:TFToolkitAgentRunName -Value $line -Type String -ErrorAction Stop
    return $true
}


function Remove-TFToolkitAgentStaleEntry {
    # Tira a entrada de início quando ela aponta para o script dado (a pasta antiga, que não existe mais). Devolve se tirou.
    # -RunKey: a chave Run de outra conta (a de quem usa o PC, com o TF-Toolkit elevado pela conta de outro Administrador).
    param (
        [Parameter(Mandatory)][string]$ScriptPath,
        [string]$RunKey = $script:TFToolkitAgentRunKey
    )

    $value = [string](Get-TFToolkitRegistryValueOrNull -Path $RunKey -Name $script:TFToolkitAgentRunName)

    if ([string]::IsNullOrWhiteSpace($value) -or $value.IndexOf($ScriptPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }

    Remove-TFToolkitRegistryValue -Path $RunKey -Name $script:TFToolkitAgentRunName
    return $true
}


function Disable-TFToolkitAgent {
    # Devolve se o monitor fechou (ele pode ter sido aberto como Administrador e não aceitar o pedido desta janela). Sem
    # conseguir remover a entrada em Run, lança um erro em português e não fecha o ícone.
    try {
        Remove-TFToolkitRegistryValue -Path $script:TFToolkitAgentRunKey -Name $script:TFToolkitAgentRunName
    }
    catch {
        throw (Get-TFToolkitText 'o Windows não deixou remover a entrada que faz o monitor abrir com o Windows')
    }

    try { Remove-TFToolkitRegistryValue -Path $script:TFToolkitAgentApprovedKey -Name $script:TFToolkitAgentRunName } catch { Write-Verbose "Marca de inicialização: $($_.Exception.Message)" }

    return (Stop-TFToolkitAgent)
}


# ---------------------------------------------------------------------------
# Regras dos avisos
# ---------------------------------------------------------------------------

function Get-TFToolkitAgentChecks {
    # O que o monitor confere, de quanto em quanto tempo (minutos) e o intervalo mínimo entre dois avisos iguais (horas).
    # RepeatHours = 0: o aviso aparece uma vez por leitura que o traz (uma tela azul nova, um resultado do teste de memória,
    # uma versão nova do TF-Toolkit), e não de novo a cada volta. Heavy = leitura demorada, feita em segundo plano.
    return @(
        @{ Id = "disk"; EveryMinutes = 15; RepeatHours = 24; Heavy = $false },
        @{ Id = "reboot"; EveryMinutes = 60; RepeatHours = 24; Heavy = $false },
        @{ Id = "maintenance"; EveryMinutes = 360; RepeatHours = 168; Heavy = $false },
        @{ Id = "protection"; EveryMinutes = 60; RepeatHours = 12; Heavy = $true },
        @{ Id = "windows"; EveryMinutes = 1440; RepeatHours = 168; Heavy = $false },
        @{ Id = "programs"; EveryMinutes = 1440; RepeatHours = 72; Heavy = $true },
        @{ Id = "catalog"; EveryMinutes = 1440; RepeatHours = 0; Heavy = $true },
        @{ Id = "diskhealth"; EveryMinutes = 360; RepeatHours = 72; Heavy = $true },
        @{ Id = "memtest"; EveryMinutes = 30; RepeatHours = 0; Heavy = $false },
        @{ Id = "bluescreen"; EveryMinutes = 60; RepeatHours = 0; Heavy = $false },
        @{ Id = "tf-toolkit"; EveryMinutes = 360; RepeatHours = 0; Heavy = $true }
    )
}


function Get-TFToolkitAgentStatePath {
    return (Join-Path (Get-TFToolkitDataPath) "agent.json")
}


function Read-TFToolkitAgentState {
    # Quando cada conferência rodou e cada aviso apareceu pela última vez ({ Checked = @{id=data}; Shown = @{id=data} }).
    $state = @{ Checked = @{}; Shown = @{} }

    try {
        $document = (Read-TFToolkitStateFile -Path (Get-TFToolkitAgentStatePath)).Document
        if ($null -eq $document) { return $state }

        foreach ($section in @("Checked", "Shown")) {
            $values = Get-TFToolkitJsonValue -Object $document -Name $section -Default $null
            if ($null -eq $values) { continue }

            foreach ($property in $values.PSObject.Properties) {
                $at = [datetime]::MinValue
                if ([datetime]::TryParse([string]$property.Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$at)) {
                    $state[$section][$property.Name] = $at
                }
            }
        }
    }
    catch {
        Write-Verbose "Estado do monitor ilegível: $($_.Exception.Message)"
    }

    return $state
}


function Save-TFToolkitAgentState {
    param ([Parameter(Mandatory)][hashtable]$State)

    try {
        $document = [ordered]@{}

        foreach ($section in @("Checked", "Shown")) {
            $values = [ordered]@{}
            foreach ($key in @($State[$section].Keys | Sort-Object)) { $values[$key] = ([datetime]$State[$section][$key]).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
            $document[$section] = $values
        }

        Write-TFToolkitStateJson -Path (Get-TFToolkitAgentStatePath) -InputObject $document -Depth 4
    }
    catch {
        Write-Verbose "Não foi possível salvar o estado do monitor: $($_.Exception.Message)"
    }
}


function Test-TFToolkitAgentDue {
    # Se já passou o tempo desde a última vez (Last ausente = nunca). Uma data mais de um dia no futuro (o relógio estava
    # adiantado quando ela foi gravada) também conta como "na hora": senão o monitor ficaria calado até lá.
    param (
        $Last,
        [double]$Minutes,
        [datetime]$Now = (Get-Date)
    )

    if ($null -eq $Last -or [datetime]$Last -gt $Now.AddDays(1)) { return $true }

    return (($Now - [datetime]$Last).TotalMinutes -ge $Minutes)
}


function Get-TFToolkitAgentPausedUntil {
    # Até quando os avisos estão pausados, ou $null. A pausa é de 24 horas: um fim mais longe que isso (gravado com o
    # relógio adiantado) não vale, para o monitor não ficar calado por anos.
    param ([datetime]$Now = (Get-Date))

    $until = [string](Get-TFToolkitSetting -Name "AgentPausedUntil" -Default "")
    $at = [datetime]::MinValue

    if ([string]::IsNullOrWhiteSpace($until) -or -not [datetime]::TryParse($until, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$at)) { return $null }

    if ($at -le $Now -or $at -gt $Now.AddHours(25)) { return $null }

    return $at
}


function Test-TFToolkitAgentPaused {
    param ([datetime]$Now = (Get-Date))

    return ($null -ne (Get-TFToolkitAgentPausedUntil -Now $Now))
}


function Set-TFToolkitAgentPause {
    # Pausa os avisos por algumas horas; Hours = 0 retoma.
    param ([int]$Hours = 24)

    $value = $(if ($Hours -gt 0) { (Get-Date).AddHours($Hours).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) } else { "" })
    [void](Set-TFToolkitSetting -Name "AgentPausedUntil" -Value $value)
}


function Format-TFToolkitAgentPauseEnd {
    # Até quando a pausa vai, como a pessoa diz: "hoje, às 18:40", "amanhã, às 14:30" (uma pausa de 24 horas sempre
    # termina amanhã; "até 14:30" sozinho parecia hoje). Mais longe que isso, com a data: "09/11, às 08:00".
    param (
        [Parameter(Mandatory)][datetime]$Until,
        [datetime]$Now = (Get-Date)
    )

    $time = Format-TFToolkitDateTime -When $Until -Pattern 'HH:mm'

    if ($Until.Date -eq $Now.Date) { return (Get-TFToolkitText 'hoje, às {0}' "$time") }
    if ($Until.Date -eq $Now.Date.AddDays(1)) { return (Get-TFToolkitText 'amanhã, às {0}' "$time") }

    return (Get-TFToolkitText '{0}, às {1}' "$(Format-TFToolkitDateTime -When $Until -Pattern 'dd/MM')" "$time")
}


function Get-TFToolkitAgentSortedAlerts {
    # Os avisos abertos na ordem em que o monitor os mostra: os mais graves (Warning) primeiro.
    param ([AllowEmptyCollection()][object[]]$Alerts = @())

    return @(@($Alerts | Where-Object { $null -ne $_ }) | Sort-Object @{ Expression = { if ($_.Level -eq "Warning") { 0 } else { 1 } } })
}


function Get-TFToolkitAgentTooltip {
    <#
    O texto do ícone ao passar o mouse. O Windows corta em 63 caracteres: um texto maior termina em "...".
    Antes da primeira leitura, "conferindo o PC"; com avisos, o mais grave pelo nome e quantos mais há; pausado, até quando.
    #>
    param (
        [AllowEmptyCollection()][object[]]$Alerts = @(),
        [bool]$FirstReading = $true,
        $PausedUntil = $null,
        [datetime]$Now = (Get-Date)
    )

    $sorted = @(Get-TFToolkitAgentSortedAlerts -Alerts $Alerts)

    $text = $(
        if ($null -ne $PausedUntil) { (Get-TFToolkitText 'TF-Toolkit: avisos pausados até {0}' "$(Format-TFToolkitAgentPauseEnd -Until ([datetime]$PausedUntil) -Now $Now)") }
        elseif (-not $FirstReading) { (Get-TFToolkitText 'TF-Toolkit: conferindo o PC...') }
        elseif ($sorted.Count -eq 0) { (Get-TFToolkitText 'TF-Toolkit: nada pedindo atenção') }
        elseif ($sorted.Count -eq 1) { "TF-Toolkit: $($sorted[0].Title)" }
        else { (Get-TFToolkitText 'TF-Toolkit: {0} e mais {1}' "$($sorted[0].Title)" "$(Format-TFToolkitCount -Count ($sorted.Count - 1) -One (Get-TFToolkitText 'aviso') -Many (Get-TFToolkitText 'avisos'))") }
    )

    if ($text.Length -gt 63) { $text = $text.Substring(0, 60).TrimEnd() + "..." }

    return $text
}


function Get-TFToolkitAgentPauseNotice {
    # O balão que confirma a pausa: até quando e como retomar antes.
    param (
        [Parameter(Mandatory)][datetime]$Until,
        [datetime]$Now = (Get-Date)
    )

    return (Get-TFToolkitText 'O TF-Toolkit volta a avisar {0}. Para retomar antes, use o menu do ícone.' "$(Format-TFToolkitAgentPauseEnd -Until $Until -Now $Now)")
}


function New-TFToolkitAgentAlert {
    # Quiet: o aviso fica no menu do ícone e no texto dele, sem balão (a versão nova do TF-Toolkit que o balão já mostrou).
    param (
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Text,
        [string]$Action = "",
        [ValidateSet("Info", "Warning")][string]$Level = "Warning",
        [switch]$Quiet
    )

    return [PSCustomObject]@{ Id = $Id; Title = $Title; Text = $Text; Action = $Action; Level = $Level; Quiet = [bool]$Quiet }
}


function Get-TFToolkitAgentReading {
    <#
    Lê uma das conferências e devolve o aviso que ela pede, ou $null se está tudo bem. Nunca lança erro: uma leitura que
    falha não avisa nada (o monitor não pode virar uma fonte de alarmes falsos).
    #>
    param ([Parameter(Mandatory)][string]$Id)

    try {
        switch ($Id) {
            "disk" {
                $space = Get-TFToolkitSystemDriveSpace
                if ($null -eq $space) { return $null }

                $level = Get-TFToolkitDiskSpaceLevel -FreeBytes $space.FreeBytes -TotalBytes $space.TotalBytes
                if ($level -notin @("Low", "Critical")) { return $null }

                # O disco pelo nome que a pessoa vê no Explorador (C:), e qual é: o do Windows. O clique abre a Limpeza
                # personalizada, como o "Liberar espaço" do Início: ela mede tudo o que dá para tirar, e não só os temporários.
                $drive = $(if ([string]$env:SystemRoot -match '^([A-Za-z]:)') { $Matches[1].ToUpperInvariant() } else { "C:" })

                return (New-TFToolkitAgentAlert -Id "disk" -Title (Get-TFToolkitText 'Pouco espaço no disco {0}' "$drive") -Text (Get-TFToolkitText 'Restam {0} livres no disco do Windows ({1}). Clique para ver o que dá para apagar.' "$(Format-TFToolkitBytes -Bytes $space.FreeBytes)" "$drive") -Action "cleanup.custom")
            }
            "reboot" {
                if (-not (Test-TFToolkitPendingReboot)) { return $null }

                return (New-TFToolkitAgentAlert -Id "reboot" -Title (Get-TFToolkitText 'Reinício pendente') -Text (Get-TFToolkitText 'O Windows espera o PC reiniciar para terminar uma atualização ou mudança. Clique para ver o motivo.') -Action "diagnostics.pending-reboot" -Level Info)
            }
            "maintenance" {
                # A mesma conta do Início (Get-TFToolkitLastCare): uma data no futuro não cala o lembrete. Registros que
                # existem, mas não puderam ser lidos, não viram "ainda não verificou": sem leitura, sem aviso.
                $latest = $null

                try { $latest = (Get-TFToolkitLastCare -Strict).Latest }
                catch { return $null }

                if ($null -ne $latest -and ((Get-Date) - $latest).TotalDays -lt 30) { return $null }

                # Sem nenhuma verificação ainda, "faz mais de um mês" não seria verdade (como no Início: "ainda não verificado").
                $text = $(if ($null -eq $latest) { (Get-TFToolkitText 'O TF-Toolkit ainda não verificou este PC. Clique para verificar.') } else { (Get-TFToolkitText 'Faz mais de um mês sem verificação. Clique para verificar o PC.') })

                return (New-TFToolkitAgentAlert -Id "maintenance" -Title (Get-TFToolkitText 'Hora de cuidar do PC') -Text $text -Action "maintenance.checkup" -Level Info)
            }
            "protection" {
                $protection = Get-TFToolkitSecurityStatus
                if ($null -eq $protection) { return $null }

                $antivirus = $protection.Antivirus

                if ($null -ne $protection.Threats -and @($protection.Threats).Count -gt 0) {
                    return (New-TFToolkitAgentAlert -Id "protection" -Title (Get-TFToolkitText 'Ameaça encontrada') -Text (Get-TFToolkitText 'O antivírus encontrou uma ameaça que ainda está ativa. Clique para ver.') -Action "security.status")
                }

                if ($antivirus.Mode -eq "Off") {
                    return (New-TFToolkitAgentAlert -Id "protection" -Title (Get-TFToolkitText 'PC sem antivírus ativo') -Text (Get-TFToolkitText 'Nenhum antivírus está protegendo o PC. Clique para ver.') -Action "security.status")
                }

                if ($antivirus.Mode -eq "Active" -and $antivirus.RealTime -eq $false) {
                    return (New-TFToolkitAgentAlert -Id "protection" -Title (Get-TFToolkitText 'Proteção em tempo real desligada') -Text (Get-TFToolkitText 'O Windows Defender não está vigiando os arquivos abertos. Clique para ver.') -Action "security.status")
                }

                return $null
            }
            "windows" {
                $support = Get-TFToolkitWindowsSupportStatus
                $issue = Get-TFToolkitWindowsSupportIssue -Status $support

                if ($null -eq $issue -or $support.State -eq "Esu") { return $null }

                # Uma leitura que não confirmou o ESU não vira aviso: o monitor só avisa do que sabe.
                if ($support.State -eq "EsuAvailable" -and -not [bool](Get-TFToolkitJsonValue -Object $support -Name "EsuChecked" -Default $true)) { return $null }

                # Sem atualizações de segurança (o ponto grave da nota) o título diz isso; perto do fim, só "Suporte do Windows".
                $title = $(if ([int]$issue.Weight -ge 20) { (Get-TFToolkitText 'Windows sem atualizações de segurança') } else { (Get-TFToolkitText 'Suporte do Windows') })

                return (New-TFToolkitAgentAlert -Id "windows" -Title $title -Text (Get-TFToolkitText '{0}. Clique para ver o que fazer.' "$($issue.Text)") -Action "diagnostics.windows-support")
            }
            "programs" {
                # Numa conexão limitada (plano de dados) ou na bateria, o monitor não consulta a internet por conta própria.
                if ((Test-TFToolkitMeteredConnection) -or (Test-TFToolkitOnBattery)) { return $null }
                if (-not (Test-TFToolkitWinget)) { return $null }

                $upgrade = Invoke-TFToolkitCapture -FilePath "winget" -Arguments @("upgrade", "--accept-source-agreements")

                if (Test-TFToolkitWingetNoUpgradeOutput -OutputText $upgrade.Text -ExitCode $upgrade.ExitCode) { return $null }

                $count = @(ConvertFrom-TFToolkitWingetTable -Lines $upgrade.Lines).Count
                if ($count -lt 3) { return $null }

                return (New-TFToolkitAgentAlert -Id "programs" -Title (Get-TFToolkitText 'Programas desatualizados') -Text (Get-TFToolkitText '{0} versão nova. Clique para atualizar.' "$(Format-TFToolkitCount -Count $count -One (Get-TFToolkitText 'programa tem') -Many (Get-TFToolkitText 'programas têm'))") -Action "updates.winget" -Level Info)
            }
            "catalog" {
                if ((Test-TFToolkitMeteredConnection) -or (Test-TFToolkitOnBattery)) { return $null }
                if (Test-TFToolkitCatalogStale -Days 7) { [void](Update-TFToolkitCatalog) }
                return $null
            }
            "diskhealth" {
                # Só o que diz que o disco pode falhar (Test-TFToolkitDiskFailing); sem Administrador, os contadores de erro
                # e de desgaste não vêm, e valem o estado do Windows e a previsão do próprio disco.
                $disk = @(Get-TFToolkitDiskHealth | Where-Object { Test-TFToolkitDiskFailing -Disk $_ })[0]
                if ($null -eq $disk) { return $null }

                $drives = @(Get-TFToolkitJsonValue -Object $disk -Name "Drives" -Default @())
                $name = $(if ($drives.Count -gt 0) { Get-TFToolkitText '{0} ({1})' "$($disk.Name)" "$(Join-TFToolkitList -Items $drives)" } else { [string]$disk.Name })

                return (New-TFToolkitAgentAlert -Id "diskhealth" -Title (Get-TFToolkitText 'Disco pode falhar') -Text (Get-TFToolkitText '{0}: {1}. Faça backup dos seus arquivos e clique para ver.' "$name" "$(Get-TFToolkitDiskFailingText -Disk $disk)") -Action "diagnostics.disk-health")
            }
            "tf-toolkit" {
                # Uma versão nova do TF-Toolkit: a consulta ao GitHub (a mesma de Verificar nova versão) é feita no máximo uma vez
                # a cada 20 horas, e nunca numa conexão limitada (plano de dados) ou na bateria; sem ela, vale a última
                # guardada. O balão aparece uma vez por versão; depois, o aviso só fica no menu do ícone, até a atualização.
                $checked = Get-TFToolkitSettingDate -Name "UpdateCheckedAt"
                $stale = ($null -eq $checked -or $checked -gt (Get-Date).AddDays(1) -or ((Get-Date) - $checked).TotalHours -ge 20)

                if ($stale -and -not (Test-TFToolkitMeteredConnection) -and -not (Test-TFToolkitOnBattery)) {
                    Save-TFToolkitUpdateCheck -Check (Get-TFToolkitUpdateStatus)
                }

                $known = Get-TFToolkitKnownUpdate
                if ($null -eq $known -or -not $known.Newer) { return $null }

                $announced = ([string](Get-TFToolkitSetting -Name "UpdateAnnounced" -Default "") -eq [string]$known.Latest)
                if (-not $announced) { [void](Set-TFToolkitSetting -Name "UpdateAnnounced" -Value ([string]$known.Latest)) }

                return (New-TFToolkitAgentAlert -Id "tf-toolkit" -Title (Get-TFToolkitText 'TF-Toolkit {0} disponível' "$($known.Latest)") -Text (Get-TFToolkitText 'A versão {0} do TF-Toolkit foi publicada. Clique para ver o que mudou e atualizar.' "$($known.Latest)") -Action "app.update" -Level Info -Quiet:$announced)
            }
            "bluescreen" {
                # Uma tela azul nova (registrada depois da última que o monitor viu) vira aviso uma vez, com a causa
                # provável e o caminho para Diagnóstico > Telas azuis. A primeira leitura só marca onde a conta está:
                # telas azuis antigas não viram aviso.
                $latest = @(Get-TFToolkitBlueScreens -Days 30) | Select-Object -First 1
                if ($null -eq $latest) { return $null }

                $seen = Get-TFToolkitSettingDate -Name "BlueScreenSeenAt"
                $new = ($null -ne $seen -and $latest.When -gt $seen)

                if ($null -eq $seen -or $new) { [void](Set-TFToolkitSetting -Name "BlueScreenSeenAt" -Value ($latest.When.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture))) }
                if (-not $new) { return $null }

                $about = Get-TFToolkitBugCheckCauseText -Cause ([string]$latest.Info.Cause)

                return (New-TFToolkitAgentAlert -Id "bluescreen" -Title (Get-TFToolkitText 'O PC teve uma tela azul') -Text (Get-TFToolkitText 'Causa provável: {0}. Clique para ver o que fazer.' "$($about.Cause)") -Action "diagnostics.blue-screens")
            }
            "memtest" {
                # O resultado do Diagnóstico de Memória do Windows (o teste roda no reinício) aparece uma vez, quando chega
                # um novo. Com erros, o aviso vem mesmo que o teste tenha sido pedido por outra conta (o TF-Toolkit elevado
                # pela conta de outro Administrador guarda o pedido nas preferências dela); sem erros, só quando esta
                # conta pediu (Diagnóstico > Teste de memória). O primeiro resultado que o monitor vê sem pedido só marca
                # onde ele está: um teste antigo não vira aviso. Sem resultado em 14 dias, o pedido sai calado.
                $pending = Get-TFToolkitMemoryTestPendingSince
                $result = Get-TFToolkitMemoryTestResult -Days 60
                $seen = Get-TFToolkitSettingDate -Name "MemoryTestSeenAt"

                if ($null -ne $pending -and ($null -eq $result -or $result.When -lt $pending) -and ((Get-Date) - $pending).TotalDays -gt 14) {
                    [void](Set-TFToolkitSetting -Name "MemoryTestRequestedAt" -Value $null)
                }

                if ($null -eq $result) { return $null }

                $requested = ($null -ne $pending -and $result.When -ge $pending)
                $new = $(if ($null -ne $seen) { $result.When -gt $seen } else { $requested })

                if ($null -eq $seen -or $new) { [void](Set-TFToolkitSetting -Name "MemoryTestSeenAt" -Value ($result.When.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture))) }
                if (-not $new) { return $null }
                if ($requested) { [void](Set-TFToolkitSetting -Name "MemoryTestRequestedAt" -Value $null) }

                if ($result.Errors) {
                    return (New-TFToolkitAgentAlert -Id "memtest" -Title (Get-TFToolkitText 'O teste de memória achou erros') -Text (Get-TFToolkitText 'A memória (RAM) tem defeito: é a causa provável de telas azuis e travamentos. Clique para ver o que fazer.') -Action "diagnostics.memory-test")
                }

                if (-not $requested) { return $null }

                return (New-TFToolkitAgentAlert -Id "memtest" -Title (Get-TFToolkitText 'Teste de memória sem erros') -Text (Get-TFToolkitText 'O Diagnóstico de Memória do Windows não achou problemas na RAM.') -Action "diagnostics.memory-test" -Level Info)
            }
        }
    }
    catch {
        Write-Verbose "Monitor, ${Id}: $($_.Exception.Message)"
    }

    return $null
}


function Get-TFToolkitAgentDueChecks {
    # As conferências que já passaram da hora, separadas em leves (rodam na hora) e pesadas (em segundo plano).
    param (
        [Parameter(Mandatory)][hashtable]$State,
        [datetime]$Now = (Get-Date)
    )

    return @(Get-TFToolkitAgentChecks | Where-Object { Test-TFToolkitAgentDue -Last $State.Checked[$_.Id] -Minutes $_.EveryMinutes -Now $Now })
}


function Select-TFToolkitAgentAlerts {
    # Dos avisos lidos, os que podem aparecer agora: não pausados e não repetidos antes do intervalo da conferência.
    param (
        [AllowEmptyCollection()][object[]]$Alerts = @(),
        [Parameter(Mandatory)][hashtable]$State,
        [datetime]$Now = (Get-Date),
        [bool]$Paused = $false
    )

    if ($Paused) { return @() }

    $checks = @{}
    foreach ($check in (Get-TFToolkitAgentChecks)) { $checks[$check.Id] = $check }

    return @(
        foreach ($alert in @($Alerts | Where-Object { $null -ne $_ })) {
            if ([bool](Get-TFToolkitJsonValue -Object $alert -Name "Quiet" -Default $false)) { continue }

            $repeat = $(if ($checks.ContainsKey($alert.Id)) { [double]$checks[$alert.Id].RepeatHours } else { 24 })
            $last = $State.Shown[$alert.Id]

            if ($repeat -le 0) {
                # Uma vez por leitura: o balão volta só se uma leitura mais nova que ele trouxe o aviso de novo.
                $read = $State.Checked[$alert.Id]
                if ($null -eq $last -or ($null -ne $read -and [datetime]$last -lt [datetime]$read)) { $alert }
                continue
            }

            if (Test-TFToolkitAgentDue -Last $last -Minutes ($repeat * 60) -Now $Now) { $alert }
        }
    )
}


# ---------------------------------------------------------------------------
# Tela (Sobre o TF-Toolkit > Monitor na bandeja)
# ---------------------------------------------------------------------------

function Set-TFToolkitMonitor {
    # -Choose On: liga direto, sem a tela de escolha (a configuração inicial, no fim do Início). Já ligado, ou com a
    # conta de outro Administrador, a tela de sempre aparece.
    param ([ValidateSet("", "On")][string]$Choose = "")

    $title = (Get-TFToolkitText 'Monitor na bandeja')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title
    $answer = ""

    try {
        $runState = Get-TFToolkitAgentRunState
        $enabled = ($runState -eq "On")
        $running = (@(Get-TFToolkitAgentProcesses).Count -gt 0)
        $mismatch = Test-TFToolkitAgentStartBlocked
        $pausedUntil = Get-TFToolkitAgentPausedUntil

        $startText = switch ($runState) {
            "On" { (Get-TFToolkitText 'sim') }
            "Elsewhere" { (Get-TFToolkitText 'não: foi ligado de outra pasta do TF-Toolkit; Ligar o monitor passa a usar esta') }
            "Disabled" { (Get-TFToolkitText 'não: desligado em Configurações, Aplicativos, Inicialização (ou no Gerenciador de Tarefas); Ligar o monitor religa') }
            default { (Get-TFToolkitText 'não') }
        }

        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Começa com o Windows') -Value $startText
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Aberto agora') -Value $(if ($running) { (Get-TFToolkitText 'sim') } else { (Get-TFToolkitText 'não') })
        if ($null -ne $pausedUntil) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Avisos') -Value (Get-TFToolkitText 'pausados até {0}' "$(Format-TFToolkitAgentPauseEnd -Until $pausedUntil)") }
        Write-Host ""

        # Os avisos: disco enchendo, proteção desligada, reinício ou manutenção faltando, Windows sem suporte e programas
        # desatualizados. Pelo menu do ícone dá para ver os avisos, verificar, acelerar e limpar o PC, ou pausar os avisos.
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O monitor fica perto do relógio e avisa quando o PC precisa de cuidado; nada muda sem você clicar.')

        # Com a conta de outro Administrador, ligar gravaria o monitor no perfil dele: não oferece.
        if ($mismatch) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O TF-Toolkit está aberto com a conta de outro Administrador. Para ligar ou desligar o monitor na sua conta, {0}.' "$(Get-TFToolkitUnelevatedHint)")
        }

        Write-Host ""

        $options = @()

        if ($mismatch) {
            # Só informa.
        }
        elseif ($enabled) {
            $options += @{ Key = "D"; Label = (Get-TFToolkitText 'Desligar o monitor'); Description = (Get-TFToolkitText 'Fecha o ícone e não abre mais com o Windows') }
            if (-not $running) { $options += @{ Key = "A"; Label = (Get-TFToolkitText 'Abrir agora'); Description = (Get-TFToolkitText 'Ele está configurado, mas não está aberto') } }
        }
        else {
            $options += @{ Key = "L"; Label = (Get-TFToolkitText 'Ligar o monitor'); Description = (Get-TFToolkitText 'Abre agora e passa a abrir com o Windows'); Accent = $true }
            if ($running -or $runState -ne "Off") { $options += @{ Key = "D"; Label = (Get-TFToolkitText 'Desligar o monitor'); Description = (Get-TFToolkitText 'Fecha o ícone e tira a entrada que sobrou') } }
        }

        # A pausa (do menu do ícone) também se desfaz daqui.
        if ($null -ne $pausedUntil -and -not $mismatch) {
            $options += @{ Key = "R"; Label = (Get-TFToolkitText 'Retomar os avisos'); Description = (Get-TFToolkitText 'Os avisos voltam na próxima conferência') }
        }

        $options += @{ Key = "X"; Label = (Get-TFToolkitText 'Voltar'); Exit = $true }

        $answer = $(if ($Choose -eq "On" -and -not $enabled -and -not $mismatch) { "L" } else { Read-TFToolkitChoice -Message (Get-TFToolkitText 'O que deseja fazer?') -Options $options -DefaultKey "X" -ShowMenu -TextPrompt (Get-TFToolkitText 'Opção (0 ou Enter = voltar)') })

        switch ($answer) {
            "L" {
                $open = Enable-TFToolkitAgent
                [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Monitor na bandeja') -Text (Get-TFToolkitText 'ligado (abre com o Windows)'))

                if ($open -eq "Open") {
                    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Monitor ligado; se o ícone não aparecer, ele está na setinha (^) ao lado do relógio.')
                    $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'monitor ligado') -Title $title) `
                        -Headline (Get-TFToolkitText 'Monitor ligado') -Note (Get-TFToolkitText 'Se o ícone não aparecer, ele está na setinha (^) ao lado do relógio.')
                }
                elseif ($open -eq "Later") {
                    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Monitor ligado; o ícone aparece em instantes ou na próxima entrada no Windows.')
                    $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'monitor ligado; o ícone aparece em instantes ou na próxima entrada no Windows') -Title $title) `
                        -Headline (Get-TFToolkitText 'Monitor ligado') -Note (Get-TFToolkitText 'O ícone aparece em instantes ou na próxima entrada no Windows.')
                }
                else {
                    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Monitor ligado, mas o Windows não deixou abri-lo agora: ele abre sozinho na próxima vez que você entrar no Windows.')
                    $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'monitor ligado, mas não abriu agora; abre na próxima entrada no Windows') -Title $title) `
                        -Headline (Get-TFToolkitText 'Monitor ligado, mas não abriu agora') -Note (Get-TFToolkitText 'Ele abre sozinho na próxima vez que você entrar no Windows.')
                }
            }
            "D" {
                $closed = Disable-TFToolkitAgent
                [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Monitor na bandeja') -Text (Get-TFToolkitText 'desligado'))

                if ($closed) {
                    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Monitor desligado.')
                    $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'monitor desligado') -Title $title) `
                        -Headline (Get-TFToolkitText 'Monitor desligado') -Note $(if ($running) { (Get-TFToolkitText 'O ícone fechou e não abre mais com o Windows.') } else { (Get-TFToolkitText 'Ele não abre mais com o Windows.') })
                }
                else {
                    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O monitor não abre mais com o Windows, mas o ícone aberto não fechou: feche pelo menu dele, em Fechar o monitor.')
                    $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o ícone aberto não fechou; feche pelo menu dele') -Title $title) `
                        -Headline (Get-TFToolkitText 'O ícone do monitor não fechou') -Note (Get-TFToolkitText 'Ele não abre mais com o Windows; feche o ícone pelo menu dele, em Fechar o monitor.')
                }
            }
            "A" {
                if (Start-TFToolkitAgent) {
                    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Monitor aberto; se o ícone não aparecer, ele está na setinha (^) ao lado do relógio.')
                    $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'monitor aberto') -Title $title) `
                        -Headline (Get-TFToolkitText 'Monitor aberto') -Note (Get-TFToolkitText 'Se o ícone não aparecer, ele está na setinha (^) ao lado do relógio.')
                }
                else {
                    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O ícone não apareceu agora; ele abre sozinho na próxima entrada no Windows.')
                    $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o ícone não apareceu agora; abre na próxima entrada no Windows') -Title $title) `
                        -Headline (Get-TFToolkitText 'O ícone não apareceu agora') -Note (Get-TFToolkitText 'Ele abre sozinho na próxima vez que você entrar no Windows.')
                }
            }
            "R" {
                Set-TFToolkitAgentPause -Hours 0
                Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Avisos retomados.')
                $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'avisos retomados') -Title $title) `
                    -Headline (Get-TFToolkitText 'Avisos retomados') -Note (Get-TFToolkitText 'Eles voltam na próxima conferência do monitor.')
            }
            default {
                # Voltar sem mudar nada é "Cancelado", como nas outras telas de escolha; com a conta de outro Administrador não
                # havia o que escolher, então é "Nada a fazer", com o motivo.
                if ($mismatch) {
                    $final = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'com a conta de outro Administrador, o monitor só muda com o TF-Toolkit aberto sem Administrador') -Title $title
                }
                else {
                    $final = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title
                }
            }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível mudar o monitor: {0}.' "$($_.Exception.Message.TrimEnd('.'))")
        # O título diz o que não aconteceu (ligar, desligar, abrir); a frase, o porquê.
        $headline = switch ($answer) {
            "L" { (Get-TFToolkitText 'O monitor não foi ligado') }
            "D" { (Get-TFToolkitText 'O monitor não foi desligado') }
            "A" { (Get-TFToolkitText 'O monitor não abriu') }
            default { (Get-TFToolkitText 'Não foi possível mudar o monitor') }
        }
        $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message.TrimEnd('.') -Title $title) -Headline $headline -Note (Format-TFToolkitReasonNote -Text $_.Exception.Message)
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
