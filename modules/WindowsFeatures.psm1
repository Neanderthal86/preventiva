# Recursos opcionais do Windows (os que ficam em "Ativar ou desativar recursos do Windows"): ligar e desligar os mais
# comuns, com uma explicação em português do que cada um faz. Usa Get-/Enable-/Disable-WindowsOptionalFeature.
#
# Os recursos mudam o sistema por baixo, então sempre é a pessoa quem marca o que alterar, e o PC pode pedir reinício.


# ---------------------------------------------------------------------------
# Catálogo
# ---------------------------------------------------------------------------

function Get-TFToolkitFeatureCatalog {
    <#
    Os recursos que o TF-Toolkit conhece. Name é o nome interno do Windows. RiskOnEnable e RiskOnDisable: texto de alerta
    quando ligar ou desligar o recurso traz risco (a confirmação passa a ter Não como padrão). Hypervisor: ligar o recurso
    liga o hipervisor do Windows, o que a tela avisa (uma vez, para todos os marcados) sem mudar o padrão da confirmação:
    para quem pediu o recurso, ligar é o esperado. Recursos que a edição do Windows não tem não aparecem na tela.
    #>
    return @(
        [PSCustomObject]@{ Name = "Microsoft-Windows-Subsystem-Linux"; Label = (Get-TFToolkitText 'Subsistema do Windows para Linux (WSL)'); Description = (Get-TFToolkitText 'Roda programas de Linux dentro do Windows; usado por desenvolvedores'); RiskOnEnable = ""; RiskOnDisable = (Get-TFToolkitText 'Sem o WSL, os Linux instalados nele deixam de abrir; os arquivos deles continuam no disco.'); Hypervisor = $false },
        [PSCustomObject]@{ Name = "VirtualMachinePlatform"; Label = (Get-TFToolkitText 'Plataforma de Máquina Virtual'); Description = (Get-TFToolkitText 'Necessária para o WSL 2 e para aplicativos que usam máquinas virtuais leves'); RiskOnEnable = ""; RiskOnDisable = (Get-TFToolkitText 'Sem a Plataforma de Máquina Virtual, o WSL 2 e os programas que usam máquinas virtuais leves (como o Docker Desktop) param de funcionar.'); Hypervisor = $true },
        [PSCustomObject]@{ Name = "HypervisorPlatform"; Label = (Get-TFToolkitText 'Plataforma do Hipervisor do Windows'); Description = (Get-TFToolkitText 'Permite que emuladores e programas de terceiros usem a virtualização do Windows'); RiskOnEnable = ""; RiskOnDisable = ""; Hypervisor = $true },
        [PSCustomObject]@{ Name = "Microsoft-Hyper-V-All"; Label = "Hyper-V"; Description = (Get-TFToolkitText 'Cria e roda máquinas virtuais completas (só nas edições Pro, Enterprise e Education)'); RiskOnEnable = ""; RiskOnDisable = (Get-TFToolkitText 'Desligar o Hyper-V faz as máquinas virtuais criadas nele pararem de funcionar; os arquivos delas continuam no disco.'); Hypervisor = $true },
        [PSCustomObject]@{ Name = "Containers-DisposableClientVM"; Label = (Get-TFToolkitText 'Windows Sandbox'); Description = (Get-TFToolkitText 'Uma janela descartável do Windows para testar programas sem risco (só nas edições Pro, Enterprise e Education)'); RiskOnEnable = ""; RiskOnDisable = ""; Hypervisor = $true },
        [PSCustomObject]@{ Name = "NetFx3"; Label = (Get-TFToolkitText '.NET Framework 3.5'); Description = (Get-TFToolkitText 'Necessário para programas antigos; o Windows baixa o componente ao ligar'); RiskOnEnable = ""; RiskOnDisable = (Get-TFToolkitText 'Programas antigos que usam o .NET 3.5 deixam de abrir.'); Hypervisor = $false },
        [PSCustomObject]@{ Name = "TelnetClient"; Label = (Get-TFToolkitText 'Cliente Telnet'); Description = (Get-TFToolkitText 'Comando telnet para testar conexões de rede; pouco usado hoje'); RiskOnEnable = ""; RiskOnDisable = ""; Hypervisor = $false },
        [PSCustomObject]@{ Name = "MicrosoftWindowsPowerShellV2Root"; Label = (Get-TFToolkitText 'Windows PowerShell 2.0'); Description = (Get-TFToolkitText 'Versão antiga e sem proteções do PowerShell; desligar é mais seguro'); RiskOnEnable = (Get-TFToolkitText 'O PowerShell 2.0 é antigo e não tem as proteções modernas; ligue só se um programa antigo exigir.'); RiskOnDisable = ""; Hypervisor = $false },
        [PSCustomObject]@{ Name = "SMB1Protocol"; Label = (Get-TFToolkitText 'Compartilhamento SMB 1.0'); Description = (Get-TFToolkitText 'Protocolo antigo de arquivos em rede, inseguro; só equipamentos muito velhos (scanners, NAS) ainda o exigem'); RiskOnEnable = (Get-TFToolkitText 'O SMB 1.0 é inseguro e foi usado por ataques como o WannaCry; ligue só se um equipamento antigo realmente exigir.'); RiskOnDisable = ""; Hypervisor = $false }
    )
}


function Get-TFToolkitFeatureStates {
    # Nome -> estado (Enabled, Disabled...) de todos os recursos que o Windows lista. $null quando não foi possível ler.
    try {
        $features = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop)
    }
    catch {
        return $null
    }

    $states = @{}

    foreach ($feature in $features) {
        $name = [string](Get-TFToolkitJsonValue -Object $feature -Name "FeatureName" -Default "")

        if ($name) {
            $states[$name] = [string](Get-TFToolkitJsonValue -Object $feature -Name "State" -Default "")
        }
    }

    return $states
}


function Get-TFToolkitFeatureChoices {
    <#
    Os recursos do catálogo que existem neste Windows, com o estado atual e a ação que a escolha faria (Enable ou
    Disable). Os que estão com a mudança pendente de reinício não entram: o Windows ainda não os aplicou.
    #>
    param (
        [Parameter(Mandatory)]
        [hashtable]$States
    )

    return @(
        foreach ($feature in @(Get-TFToolkitFeatureCatalog)) {
            if (-not $States.ContainsKey($feature.Name)) { continue }

            $state = [string]$States[$feature.Name]

            if ($state -match 'Pending') { continue }

            $enabled = ($state -eq "Enabled")

            [PSCustomObject]@{
                Name         = $feature.Name
                Label        = $feature.Label
                Description  = $feature.Description
                RiskOnEnable = $feature.RiskOnEnable
                RiskOnDisable = $feature.RiskOnDisable
                Hypervisor   = [bool](Get-TFToolkitJsonValue -Object $feature -Name "Hypervisor" -Default $false)
                Enabled      = $enabled
                Action       = $(if ($enabled) { "Disable" } else { "Enable" })
            }
        }
    )
}


function Set-TFToolkitOptionalFeature {
    # Liga ou desliga um recurso sem reiniciar. Devolve RestartNeeded.
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet("Enable", "Disable")]
        [string]$Action
    )

    if ($Action -eq "Enable") {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -All -ErrorAction Stop
    }
    else {
        $result = Disable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop
    }

    return [PSCustomObject]@{ RestartNeeded = [bool](Get-TFToolkitJsonValue -Object $result -Name "RestartNeeded" -Default $false) }
}


function Get-TFToolkitFeaturePendingLabels {
    # Os recursos do catálogo com uma mudança que só termina ao reiniciar (estado "...Pending"): ficam fora da escolha, e a
    # tela diz que estão esperando o reinício.
    param (
        [Parameter(Mandatory)]
        [hashtable]$States
    )

    return @(
        foreach ($feature in @(Get-TFToolkitFeatureCatalog)) {
            if ($States.ContainsKey($feature.Name) -and [string]$States[$feature.Name] -match 'Pending') { $feature.Label }
        }
    )
}


function Get-TFToolkitFeatureErrorText {
    <#
    O motivo de um recurso não ter mudado, a partir do erro do cmdlet. Os códigos mais comuns viram frase, com o código
    junto; os demais ficam com a primeira linha da mensagem do Windows e o código, quando houver.
    #>
    param (
        [string]$Message,
        [int]$HResult = 0
    )

    $code = Get-TFToolkitErrorCode -Message $Message -HResult $HResult

    $phrase = switch ($code) {
        "0x800F081F" { (Get-TFToolkitText 'o Windows não encontrou os arquivos do recurso; confira a internet e o Windows Update') }
        "0x800F0906" { (Get-TFToolkitText 'o Windows não conseguiu baixar os arquivos do recurso; confira a internet') }
        "0x800F0907" { (Get-TFToolkitText 'uma política de rede impediu o download dos arquivos do recurso; fale com o suporte de TI') }
        "0x800F0954" { (Get-TFToolkitText 'o Windows não conseguiu os arquivos do recurso; costuma acontecer quando o PC busca atualizações num servidor de empresa (WSUS), o que, num PC de casa, um bloqueador de atualizações pode ter configurado') }
        "0x800F080C" { (Get-TFToolkitText 'o recurso não existe nesta edição do Windows') }
        "0x80070005" { (Get-TFToolkitText 'acesso negado') }
        default { "" }
    }

    if ($phrase) {
        return (Get-TFToolkitText '{0} — erro {1}' "$phrase" "$code")
    }

    $text = @(([string]$Message) -split "[\r\n]+" | Where-Object { $_.Trim() }) | Select-Object -First 1
    $text = $(if ($text) { ([string]$text).Trim().TrimEnd('.') } else { (Get-TFToolkitText 'o Windows não aplicou a mudança') })

    if ($code -and $text.IndexOf($code, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return (Get-TFToolkitText '{0} — erro {1}' "$text" "$code")
    }

    return $text
}


# ---------------------------------------------------------------------------
# Ação
# ---------------------------------------------------------------------------

function Set-TFToolkitWindowsFeatures {
    $title = (Get-TFToolkitText 'Recursos opcionais do Windows')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Ligar ou desligar recursos do Windows exige privilégios de Administrador.'))) {
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador') -Title $title)
            return
        }

        Write-Progress -Activity (Get-TFToolkitText 'Recursos opcionais do Windows') -Status (Get-TFToolkitText 'lendo os recursos (pode levar alguns segundos)')

        try {
            $states = Get-TFToolkitFeatureStates
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Recursos opcionais do Windows') -Completed
        }

        if ($null -eq $states) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível ler os recursos do Windows neste PC.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível ler os recursos do Windows') -Title $title)
            return
        }

        $choices = @(Get-TFToolkitFeatureChoices -States $states)
        $pending = @(Get-TFToolkitFeaturePendingLabels -States $states)

        if ($choices.Count -eq 0 -and $pending.Count -eq 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhum dos recursos conhecidos está disponível nesta edição do Windows.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nenhum recurso disponível nesta edição do Windows') -Title $title)
            return
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Situação atual')

        foreach ($choice in $choices) {
            Write-TFToolkitKeyValue -Label $choice.Label -Value $(if ($choice.Enabled) { (Get-TFToolkitText 'Ligado') } else { (Get-TFToolkitText 'Desligado') }) -LabelWidth 38
        }

        foreach ($label in $pending) {
            Write-TFToolkitKeyValue -Label $label -Value (Get-TFToolkitText 'Mudança pendente') -LabelWidth 38
        }

        Write-Host ""

        if ($pending.Count -eq 1) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Reinicie o PC para concluir a mudança pendente; até lá, esse recurso fica fora da lista.')
        }
        elseif ($pending.Count -gt 1) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Reinicie o PC para concluir as mudanças pendentes; até lá, esses recursos ficam fora da lista.')
        }

        if ($choices.Count -eq 0) {
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'os recursos esperam o reinício do PC') -Title $title)
            return
        }

        $options = @(
            foreach ($choice in $choices) {
                $verb = if ($choice.Enabled) { (Get-TFToolkitText 'Desligar') } else { (Get-TFToolkitText 'Ligar') }

                @{ Key = $choice.Name; Label = "${verb}: $($choice.Label)"; Description = $choice.Description }
            }
        )

        $picked = Read-TFToolkitMultiSelect -Message (Get-TFToolkitText 'Marque o que deseja mudar') -Options $options -NoSelectAll -ConfirmLabel (Get-TFToolkitText 'Mudar')

        if ($null -eq $picked -or @($picked).Count -eq 0) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $changes = @($choices | Where-Object { @($picked) -contains $_.Name })

        # O WSL 2, o padrão hoje, roda sobre a Plataforma de Máquina Virtual: ligar o WSL sem ela daria só o WSL 1.
        $platform = @($choices | Where-Object { $_.Name -eq "VirtualMachinePlatform" -and -not $_.Enabled }) | Select-Object -First 1
        $addedPlatform = $false

        if (@($changes | Where-Object { $_.Name -eq "Microsoft-Windows-Subsystem-Linux" -and $_.Action -eq "Enable" }).Count -gt 0 -and $null -ne $platform -and @($changes | Where-Object { $_.Name -eq "VirtualMachinePlatform" }).Count -eq 0) {
            $changes += $platform
            $addedPlatform = $true
        }

        $risky = @($changes | Where-Object { ($_.Action -eq "Enable" -and $_.RiskOnEnable) -or ($_.Action -eq "Disable" -and $_.RiskOnDisable) })

        # O que vai mudar fica no resumo, junto com o alerta de cada recurso arriscado: a pergunta só confirma.
        Write-TFToolkitSection -Title (Get-TFToolkitText 'O que vai mudar')

        foreach ($change in $changes) {
            Write-TFToolkitKeyValue -Label $change.Label -Value $(if ($change.Action -eq "Enable") { (Get-TFToolkitText 'Ligar') } else { (Get-TFToolkitText 'Desligar') }) -LabelWidth 38
        }

        Write-Host ""

        if ($addedPlatform) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A Plataforma de Máquina Virtual entra junto (o WSL 2 precisa dela): ela liga o hipervisor do Windows a cada início, o que pode atrapalhar VirtualBox e VMware antigos, emuladores de Android e o antitrapaça de jogos.')
        }

        # O mesmo aviso para o que a pessoa marcou e liga o hipervisor (sem repetir o da Plataforma que entrou junto).
        $hypervisor = @($changes | Where-Object { $_.Action -eq "Enable" -and (Get-TFToolkitJsonValue -Object $_ -Name "Hypervisor" -Default $false) -and -not ($addedPlatform -and $_.Name -eq "VirtualMachinePlatform") } | ForEach-Object { [string]$_.Label })

        if ($hypervisor.Count -gt 0) {
            Write-TFToolkitStatus -Type Warning -Notice -Message $(if ($hypervisor.Count -eq 1) { Get-TFToolkitText '{0} liga o hipervisor do Windows a cada início, o que pode atrapalhar VirtualBox e VMware antigos, emuladores de Android e o antitrapaça de jogos.' "$(Join-TFToolkitList -Items $hypervisor)" } else { Get-TFToolkitText '{0} ligam o hipervisor do Windows a cada início, o que pode atrapalhar VirtualBox e VMware antigos, emuladores de Android e o antitrapaça de jogos.' "$(Join-TFToolkitList -Items $hypervisor)" })
        }

        foreach ($change in $risky) {
            Write-TFToolkitStatus -Type Warning -Message $(if ($change.Action -eq "Enable") { $change.RiskOnEnable } else { $change.RiskOnDisable })
        }

        # A pergunta inteira por idioma: "Ligar {0}?" muda de ordem e de palavra em cada um.
        $question = $(if ($changes.Count -eq 1) { $(if ($changes[0].Action -eq 'Enable') { (Get-TFToolkitText 'Ligar {0}?' "$($changes[0].Label)") } else { (Get-TFToolkitText 'Desligar {0}?' "$($changes[0].Label)") }) } else { (Get-TFToolkitText 'Aplicar as {0} mudanças?' "$($changes.Count)") })

        # O botão diz o que acontece: Ligar ou Desligar, com um recurso; Aplicar, com vários.
        $yes = $(if ($changes.Count -gt 1) { (Get-TFToolkitText 'Aplicar') } elseif ($changes[0].Action -eq 'Enable') { (Get-TFToolkitText 'Ligar') } else { (Get-TFToolkitText 'Desligar') })

        if (-not (Confirm-TFToolkitAction -Message $question -DefaultKey $(if ($risky.Count -gt 0) { "N" } else { "S" }) -YesLabel $yes -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $results = @()
        $restart = $false
        $position = 0

        try {
            foreach ($change in $changes) {
                $position++
                $doing = $(if ($change.Action -eq "Enable") { (Get-TFToolkitText 'ligando') } else { (Get-TFToolkitText 'desligando') })
                $done = $(if ($change.Action -eq "Enable") { (Get-TFToolkitText 'ligado') } else { (Get-TFToolkitText 'desligado') })

                Write-Progress -Activity (Get-TFToolkitText 'Alterando recursos do Windows') -Status (Get-TFToolkitText '{0} de {1}: {2} {3}' "$position" "$($changes.Count)" "$doing" "$($change.Label)") -PercentComplete ([int](($position - 1) * 100 / $changes.Count))

                try {
                    $applied = Set-TFToolkitOptionalFeature -Name $change.Name -Action $change.Action
                    $restart = $restart -or $applied.RestartNeeded
                    $result = New-TFToolkitResult -Kind Ok -Detail $done -Data @{ RebootRequired = [bool]$applied.RestartNeeded }
                    Write-TFToolkitStatus -Type Success -Message $(if ($applied.RestartNeeded) { (Get-TFToolkitText '{0}: {1}; termina ao reiniciar o PC.' "$($change.Label)" "$done") } else { "$($change.Label): $done." })
                    $opposite = $(if ($change.Action -eq "Enable") { "Disable" } else { "Enable" })
                    [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Recurso do Windows') -Text "$($change.Label) $done" -Undo @{ Kind = "feature"; Name = [string]$change.Name; Action = $opposite })
                }
                catch {
                    $reason = Get-TFToolkitFeatureErrorText -Message $_.Exception.Message -HResult $_.Exception.HResult
                    Write-TFToolkitStatus -Type Error -Message "$($change.Label): $reason."
                    $result = New-TFToolkitResult -Kind Failed -Detail $reason
                }

                $result.Etapa = $change.Label
                $results += $result
            }
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Alterando recursos do Windows') -Completed
        }

        # No console, a tabela junta tudo no fim; na janela, cada recurso já tem a sua linha no resumo.
        if ($results.Count -gt 1 -and -not (Test-TFToolkitGuiMode)) {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')
            Write-TFToolkitResultTable -Results $results
        }

        $failed = @($results | Where-Object { $_.Kind -eq "Failed" })
        $names = Join-TFToolkitList -Items @($failed | ForEach-Object { [string]$_.Etapa })

        # Ligar o WSL não instala nenhum Linux: falta escolher uma distribuição.
        $wsl = @($changes | Where-Object { $_.Name -eq "Microsoft-Windows-Subsystem-Linux" -and $_.Action -eq "Enable" }) | Select-Object -First 1
        if ($null -ne $wsl -and @($results | Where-Object { $_.Etapa -eq $wsl.Label -and $_.Kind -ne "Failed" }).Count -gt 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Depois de reiniciar, instale um Linux pela Microsoft Store ou com wsl --install (a virtualização precisa estar ligada na BIOS).')
        }

        # A faixa acrescenta "Reinicie o PC para concluir." quando RebootRequired está ligado.
        if ($failed.Count -eq 0) {
            $detail = $(if ($results.Count -eq 1) { "$($results[0].Etapa) $($results[0].Detail)" } else { (Get-TFToolkitText '{0} recursos alterados' "$($results.Count)") })
            $final = New-TFToolkitResult -Kind Ok -Detail $detail -Title $title -Data @{ RebootRequired = $restart }

            # Na janela, o título diz quantos e o que mudou; a frase, quais. O pedido de reinício a faixa acrescenta.
            $on = @($results | Where-Object { $_.Detail -eq (Get-TFToolkitText 'ligado') } | ForEach-Object { [string]$_.Etapa })
            $off = @($results | Where-Object { $_.Detail -eq (Get-TFToolkitText 'desligado') } | ForEach-Object { [string]$_.Etapa })

            if ($off.Count -eq 0) {
                [void](Set-TFToolkitResultView -Result $final -Headline (Format-TFToolkitCount -Count $on.Count -One (Get-TFToolkitText 'recurso ligado') -Many (Get-TFToolkitText 'recursos ligados')) -Note "$(Join-TFToolkitShortList -Items $on).")
            }
            elseif ($on.Count -eq 0) {
                [void](Set-TFToolkitResultView -Result $final -Headline (Format-TFToolkitCount -Count $off.Count -One (Get-TFToolkitText 'recurso desligado') -Many (Get-TFToolkitText 'recursos desligados')) -Note "$(Join-TFToolkitShortList -Items $off).")
            }
            else {
                [void](Set-TFToolkitResultView -Result $final -Headline (Format-TFToolkitCount -Count $results.Count -One (Get-TFToolkitText 'recurso alterado') -Many (Get-TFToolkitText 'recursos alterados')) `
                        -Note "$(if ($on.Count -eq 1) { (Get-TFToolkitText 'Ligado: {0}.' "$(Join-TFToolkitShortList -Items $on)") } else { (Get-TFToolkitText 'Ligados: {0}.' "$(Join-TFToolkitShortList -Items $on)") }) $(if ($off.Count -eq 1) { (Get-TFToolkitText 'Desligado: {0}.' "$(Join-TFToolkitShortList -Items $off)") } else { (Get-TFToolkitText 'Desligados: {0}.' "$(Join-TFToolkitShortList -Items $off)") })")
            }
        }
        elseif ($failed.Count -eq $results.Count) {
            $detail = $(if ($results.Count -eq 1) { (Get-TFToolkitText '{0} não mudou: {1}' "$names" "$($failed[0].Detail)") } else { (Get-TFToolkitText 'nenhum recurso mudou: {0}' "$names") })
            $final = New-TFToolkitResult -Kind Failed -Detail $detail -Title $title

            # Na janela, o título diz que nada mudou; a frase, o motivo (de um só) ou onde estão os motivos.
            [void](Set-TFToolkitResultView -Result $final -Headline $(if ($results.Count -eq 1) { (Get-TFToolkitText 'O recurso não mudou') } else { (Get-TFToolkitText 'Nenhum recurso mudou') }) `
                    -Note $(if ($results.Count -eq 1) { "$($failed[0].Etapa): $(([string]$failed[0].Detail).TrimEnd('.'))." } else { (Get-TFToolkitText 'O motivo de cada um está no resumo.') }))
        }
        else {
            $verbText = $(if ($failed.Count -eq 1) { (Get-TFToolkitText 'não mudou') } else { (Get-TFToolkitText 'não mudaram') })
            $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0} de {1} {2}: {3}' "$($failed.Count)" "$($results.Count)" "${verbText}" "$names") -Title $title -Data @{ RebootRequired = $restart }
            $reason = $(if ($failed.Count -eq 1) { (Get-TFToolkitText 'o motivo está no resumo') } else { (Get-TFToolkitText 'o motivo de cada um está no resumo') })
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText '{0} de {1} recursos alterados' "$($results.Count - $failed.Count)" "$($results.Count)") `
                    -Note "$(Join-TFToolkitShortList -Items @($failed | ForEach-Object { [string]$_.Etapa })) ${verbText}; $reason.")
        }

        # O que mudou só termina ao reiniciar: o reinício é oferecido ali mesmo (Não como padrão), como nas Atualizações.
        if ($restart) {
            Request-TFToolkitRestartOffer -Reason (Get-TFToolkitText 'Para terminar de ligar ou desligar os recursos, o Windows precisa reiniciar.') `
                -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit para terminar de alterar recursos do Windows.') `
                -DeclinedMessage (Get-TFToolkitText 'Reinicialização não iniciada. Os recursos terminam de mudar quando você reiniciar o PC.')
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível alterar os recursos: {0}' "$($_.Exception.Message)")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
