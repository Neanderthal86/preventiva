# Verificar o PC: olha tudo de uma vez e corrige com um clique o que é seguro corrigir.
#
# A verificação só lê (espaço e saúde dos discos, lixo acumulado, registro, atalhos, memória, inicialização, programas
# desatualizados, suporte e atualizações do Windows, proteção, reinício pendente e telas azuis). A consulta do winget, a
# mais demorada (depende da rede), começa antes de todas e corre junto com as outras etapas, com prazo. Depois, uma lista
# de marcar traz o que dá para corrigir aqui mesmo, com o que é seguro já marcado: temporários e relatórios de erro (o Windows recria), atalhos
# quebrados (para a Lixeira) e assinaturas do antivírus. As referências quebradas do registro ficam na lista, desmarcadas
# (a Microsoft não recomenda limpar o registro; o TF-Toolkit guarda backup e desfaz, mas o ganho é pequeno). O resto vira
# um atalho para a tela certa: liberar espaço, fechar o que pesa na memória, decidir o que abre com o Windows ou
# atualizar programas pede o olhar da pessoa.


function New-TFToolkitCheckupFinding {
    <#
    Um achado da verificação. Fix = nome da correção (vazio = não se corrige daqui); Selected = vem marcado; Target = item
    da navegação para ver de perto; Level = Ok | Warn | Info; Data = o que a correção precisa; Unread = a leitura não
    respondeu (a etapa conta como não lida no veredito). Short = o nome nas listas ("ainda pedem você: ..."), quando o
    rótulo da linha não serve para elas; sem ele, vale o Label.
    #>
    param (
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet("Ok", "Warn", "Info")][string]$Level = "Info",
        [string]$Fix = "",
        [string]$FixLabel = "",
        [bool]$Selected = $false,
        [string]$Target = "",
        [string]$Advice = "",
        $Data = $null,
        [bool]$Unread = $false,
        [string]$Short = ""
    )

    return [PSCustomObject]@{
        Id       = $Id
        Label    = $Label
        Short    = $(if ($Short) { $Short } else { $Label })
        Value    = $Value
        Level    = $Level
        Fix      = $Fix
        FixLabel = $FixLabel
        Selected = $Selected
        Target   = $Target
        Advice   = $Advice
        Data     = $Data
        Unread   = $Unread
    }
}


function Get-TFToolkitCheckupSteps {
    # As etapas da verificação, na ordem, com o texto da barra de progresso.
    return @(
        @{ Id = "disk"; Label = (Get-TFToolkitText 'Espaço no disco'); Text = (Get-TFToolkitText 'medindo o espaço livre e conferindo a saúde dos discos') },
        @{ Id = "junk"; Label = (Get-TFToolkitText 'Temporários'); Text = (Get-TFToolkitText 'medindo temporários e caches') },
        @{ Id = "registry"; Label = (Get-TFToolkitText 'Registro'); Text = (Get-TFToolkitText 'procurando referências quebradas no registro') },
        @{ Id = "shortcuts"; Label = (Get-TFToolkitText 'Atalhos'); Text = (Get-TFToolkitText 'conferindo os atalhos') },
        @{ Id = "memory"; Label = (Get-TFToolkitText 'Memória'); Text = (Get-TFToolkitText 'lendo o uso de memória') },
        @{ Id = "startup"; Label = (Get-TFToolkitText 'Abrem com o Windows'); Text = (Get-TFToolkitText 'contando o que abre com o Windows') },
        @{ Id = "programs"; Label = (Get-TFToolkitText 'Programas desatualizados'); Text = (Get-TFToolkitText 'procurando programas desatualizados (winget)') },
        @{ Id = "windows"; Label = (Get-TFToolkitText 'Suporte do Windows'); Text = (Get-TFToolkitText 'conferindo o suporte e as atualizações do Windows') },
        @{ Id = "protection"; Label = (Get-TFToolkitText 'Proteção'); Text = (Get-TFToolkitText 'conferindo a proteção') },
        @{ Id = "reboot"; Label = (Get-TFToolkitText 'Reinício pendente'); Text = (Get-TFToolkitText 'conferindo se falta reiniciar') },
        @{ Id = "bluescreens"; Label = (Get-TFToolkitText 'Telas azuis'); Text = (Get-TFToolkitText 'procurando telas azuis recentes') }
    )
}


function Get-TFToolkitCheckupDisk {
    # O espaço livre no disco do Windows (Get-TFToolkitCheckupDiskSpace) e, quando algum disco dá sinais de que pode falhar
    # (Test-TFToolkitDiskFailing, o mesmo aviso do monitor na bandeja), um achado a mais, que leva a Diagnóstico > Saúde
    # dos discos. Com mais de um disco falhando, é um ponto só, com os nomes: dois pontos iguais ("Saúde do disco e Saúde
    # do disco") não diziam qual era qual. Uma leitura da saúde que falha não tira o espaço livre da conta.
    $findings = @(Get-TFToolkitCheckupDiskSpace)

    try {
        $failing = @(Get-TFToolkitDiskHealth | Where-Object { Test-TFToolkitDiskFailing -Disk $_ })
        $names = @(foreach ($disk in $failing) {
                $drives = @(Get-TFToolkitJsonValue -Object $disk -Name "Drives" -Default @())
                $(if ($drives.Count -gt 0) { Get-TFToolkitText '{0} ({1})' "$($disk.Name)" "$(Join-TFToolkitList -Items $drives)" } else { [string]$disk.Name })
            })
        $advice = (Get-TFToolkitText 'faça backup dos seus arquivos e veja Diagnóstico > Saúde dos discos')

        if ($failing.Count -eq 1) {
            $findings += New-TFToolkitCheckupFinding -Id "disk-health" -Label (Get-TFToolkitText 'Saúde do disco') -Value (Get-TFToolkitText '{0}: {1}' "$($names[0])" "$(Get-TFToolkitDiskFailingText -Disk $failing[0])") -Level Warn `
                -Target "diagnostics.disk-health" -Advice $advice
        }
        elseif ($failing.Count -gt 1) {
            # O sinal de cada um fica na tela aonde o ponto leva: na faixa, a frase com todos passaria das 220 letras.
            $findings += New-TFToolkitCheckupFinding -Id "disk-health" -Label (Get-TFToolkitText 'Saúde dos discos') -Value (Get-TFToolkitText '{0} dão sinal de falha' "$(Join-TFToolkitList -Items $names)") -Level Warn `
                -Target "diagnostics.disk-health" -Advice $advice
        }
    }
    catch {
        Write-Verbose "Saúde do disco: $($_.Exception.Message)"
    }

    return $findings
}


function Get-TFToolkitCheckupDiskSpace {
    # O espaço livre no disco do Windows, com a regra do Início (Get-TFToolkitDiskSpaceLevel): menos de 20 GB pede
    # atenção, menos de 10 GB é quase cheio. Não se corrige daqui: a Limpeza personalizada mostra o tamanho de cada
    # coisa que dá para apagar (os temporários desta verificação, logo abaixo, já ajudam).
    $space = Get-TFToolkitSystemDriveSpace
    $level = $(if ($null -eq $space) { "Unknown" } else { Get-TFToolkitDiskSpaceLevel -FreeBytes $space.FreeBytes -TotalBytes $space.TotalBytes })

    if ($level -eq "Unknown") {
        return (New-TFToolkitCheckupFinding -Id "disk" -Label (Get-TFToolkitText 'Espaço no disco') -Value (Get-TFToolkitText 'não foi possível ler') -Level Info -Unread $true)
    }

    $value = (Get-TFToolkitText '{0} livres de {1}' "$(Format-TFToolkitBytes -Bytes $space.FreeBytes)" "$(Format-TFToolkitBytes -Bytes $space.TotalBytes)")

    # Data = o nível, que decide o peso do ponto (Get-TFToolkitCheckupWeight): o disco quase cheio vem antes.
    if ($level -in @("Critical", "Low")) {
        return (New-TFToolkitCheckupFinding -Id "disk" -Label (Get-TFToolkitText 'Espaço no disco') -Value $(if ($level -eq 'Critical') { (Get-TFToolkitText '{0} (quase cheio)' "$value") } else { (Get-TFToolkitText '{0} (pouco espaço)' "$value") }) -Level Warn `
                -Target "cleanup.custom" -Advice (Get-TFToolkitText 'libere espaço em Limpeza > Limpeza personalizada') -Data $level)
    }

    return (New-TFToolkitCheckupFinding -Id "disk" -Label (Get-TFToolkitText 'Espaço no disco') -Value $value -Level Ok)
}


function Get-TFToolkitCheckupJunk {
    $isAdmin = Test-TFToolkitAdministrator
    $all = @(Get-TFToolkitCleanupTargets)
    $targets = @($all | Where-Object { $_.Selected -and ($isAdmin -or -not $_.Admin) })
    $measured = @(foreach ($target in $targets) { Measure-TFToolkitCleanupTarget -Target $target })
    $size = [int64]0
    foreach ($target in $measured) { if ($null -ne $target.Size) { $size += [int64]$target.Size } }

    # O nome da correção diz o que ela apaga. Com Administrador, o que vem marcado na Limpeza personalizada inclui os
    # relatórios de erro e o cache da Otimização de Entrega (pedaços de atualizações já instaladas); sem ele, os dois pedem
    # Administrador e ficam de fora: só os temporários desta conta. A linha e as listas dizem só "Temporários" (um nome com
    # vírgulas se perdia no meio de "ainda pedem você: Espaço no disco, Temporários, ...").
    $ids = @($measured | ForEach-Object { [string]$_.Id })
    $label = (Get-TFToolkitText 'Temporários')
    $fixLabel = $(
        if ($ids -contains "delivery-optimization") { (Get-TFToolkitText 'Apagar temporários, relatórios de erro e cache de atualizações') }
        elseif ($ids -contains "error-reports") { (Get-TFToolkitText 'Apagar temporários e relatórios de erro') }
        else { (Get-TFToolkitText 'Apagar os temporários do usuário') }
    )

    $findings = @()

    # Nenhuma pasta pôde ser medida (sem permissão para ler): "nada acumulado" afirmaria o que não foi visto, como a
    # Limpeza personalizada já evita.
    if ($measured.Count -gt 0 -and @($measured | Where-Object { $null -ne $_.Size }).Count -eq 0) {
        $findings += New-TFToolkitCheckupFinding -Id "junk" -Label $label -Value (Get-TFToolkitText 'não foi possível ler') -Level Info -Target "cleanup.custom" -Unread $true
    }
    elseif ($size -ge 50MB) {
        $findings += New-TFToolkitCheckupFinding -Id "junk" -Label $label -Value (Format-TFToolkitBytes -Bytes $size) -Level Warn `
            -Fix "junk" -FixLabel $fixLabel -Selected $true -Target "cleanup.custom" -Data @($measured)
    }
    else {
        $findings += New-TFToolkitCheckupFinding -Id "junk" -Label $label -Value $(if ($size -gt 0) { (Get-TFToolkitText 'pouco ({0})' "$(Format-TFToolkitBytes -Bytes $size)") } else { (Get-TFToolkitText 'nada acumulado') }) -Level Ok
    }

    $browser = @($all | Where-Object { $_.Id -eq "browser-cache" }) | Select-Object -First 1

    if ($null -ne $browser) {
        $browser = Measure-TFToolkitCleanupTarget -Target $browser

        if ($null -ne $browser.Size -and [int64]$browser.Size -ge 200MB) {
            $findings += New-TFToolkitCheckupFinding -Id "browser" -Label (Get-TFToolkitText 'Cache dos navegadores') -Value (Format-TFToolkitBytes -Bytes $browser.Size) -Level Info `
                -Fix "browser" -FixLabel (Get-TFToolkitText 'Limpar o cache dos navegadores') -Target "cleanup.custom" -Data @($browser) `
                -Advice (Get-TFToolkitText 'senhas, cookies e histórico ficam; as páginas abrem mais devagar na primeira vez')
        }
    }

    if (-not $isAdmin) {
        $findings += New-TFToolkitCheckupFinding -Id "junk-admin" -Label (Get-TFToolkitText 'Temporários do Windows') -Value (Get-TFToolkitText 'só com Administrador') -Level Info -Target "cleanup.quick"
    }

    return @($findings)
}


function Get-TFToolkitCheckupRegistry {
    # As bibliotecas compartilhadas (SharedDLLs) ficam fora da correção com um clique: é uma contagem de uso que
    # instaladores consultam, e quem decide removê-la é a pessoa, olhando a lista em Limpeza > Limpar o registro. As
    # outras referências quebradas vêm na lista desmarcadas: a Microsoft não dá suporte a programas de limpeza do registro
    # (KB2563254), e o ganho de remover chaves órfãs é pequeno; o backup e o desfazer continuam valendo para quem marcar.
    # Por isso elas são informação, e não um ponto de atenção: quase todo PC tem alguma, e um ponto que o próprio TF-Toolkit
    # não recomenda corrigir deixaria toda verificação "com ressalvas" ("ainda pede atenção: Registro").
    $all = @(Find-TFToolkitRegistryIssues)
    $issues = @($all | Where-Object { $_.Category -ne "shared-dlls" })
    $shared = $all.Count - $issues.Count
    $advice = $(if ($shared -gt 0) { (Get-TFToolkitText '{0} para você revisar em Limpeza > Limpar o registro' "$(Format-TFToolkitCount -Count $shared -One (Get-TFToolkitText 'biblioteca compartilhada fica') -Many (Get-TFToolkitText 'bibliotecas compartilhadas ficam'))") } else { "" })

    if ($issues.Count -eq 0) {
        if ($shared -gt 0) {
            # Sobras comuns e inofensivas: informação, sem orientação, e não um ponto que pede decisão a cada verificação.
            return (New-TFToolkitCheckupFinding -Id "registry" -Label (Get-TFToolkitText 'Registro') -Value (Format-TFToolkitCount -Count $shared -One (Get-TFToolkitText 'biblioteca compartilhada que não existe mais') -Many (Get-TFToolkitText 'bibliotecas compartilhadas que não existem mais')) -Level Info `
                    -Target "cleanup.registry")
        }

        return (New-TFToolkitCheckupFinding -Id "registry" -Label (Get-TFToolkitText 'Registro') -Value (Get-TFToolkitText 'nenhuma referência quebrada') -Level Ok)
    }

    return (New-TFToolkitCheckupFinding -Id "registry" -Label (Get-TFToolkitText 'Registro') -Value (Format-TFToolkitCount -Count $issues.Count -One (Get-TFToolkitText 'referência quebrada') -Many (Get-TFToolkitText 'referências quebradas')) -Level Info `
            -Fix "registry" -FixLabel (Get-TFToolkitText 'Remover as referências quebradas do registro (com backup)') -Selected $false -Target "cleanup.registry" -Advice $advice -Data $issues)
}


function Get-TFToolkitCheckupShortcuts {
    # Os atalhos do OneDrive ficam fora da correção de um clique: o programa pode estar instalado em outro PC da pessoa, e
    # o atalho apagado aqui some de lá também. Eles aparecem, desmarcados, em Limpeza > Remover atalhos quebrados, e a
    # linha diz isso, como o registro faz com as bibliotecas compartilhadas: "nenhum quebrado" com eles lá não era verdade.
    $isAdmin = Test-TFToolkitAdministrator
    $usable = @(Find-TFToolkitBrokenShortcuts | Where-Object { $isAdmin -or -not $_.Admin })
    $broken = @($usable | Where-Object { -not [bool](Get-TFToolkitJsonValue -Object $_ -Name "Synced" -Default $false) })
    $synced = $usable.Count - $broken.Count

    if ($broken.Count -eq 0) {
        if ($synced -gt 0) {
            return (New-TFToolkitCheckupFinding -Id "shortcuts" -Label (Get-TFToolkitText 'Atalhos') -Value (Format-TFToolkitCount -Count $synced -One (Get-TFToolkitText 'atalho quebrado no OneDrive') -Many (Get-TFToolkitText 'atalhos quebrados no OneDrive')) -Level Info `
                    -Target "cleanup.shortcuts" -Advice (Get-TFToolkitText 'revise em Limpeza > Remover atalhos quebrados; o programa pode estar em outro PC seu'))
        }

        return (New-TFToolkitCheckupFinding -Id "shortcuts" -Label (Get-TFToolkitText 'Atalhos') -Value (Get-TFToolkitText 'nenhum quebrado') -Level Ok)
    }

    $advice = $(if ($synced -gt 0) { (Get-TFToolkitText '{0} para você revisar em Limpeza > Remover atalhos quebrados' "$(Format-TFToolkitCount -Count $synced -One (Get-TFToolkitText 'atalho do OneDrive fica') -Many (Get-TFToolkitText 'atalhos do OneDrive ficam'))") } else { "" })

    return (New-TFToolkitCheckupFinding -Id "shortcuts" -Label (Get-TFToolkitText 'Atalhos') -Value (Format-TFToolkitCount -Count $broken.Count -One (Get-TFToolkitText 'atalho quebrado') -Many (Get-TFToolkitText 'atalhos quebrados')) -Level Warn `
            -Fix "shortcuts" -FixLabel (Get-TFToolkitText 'Enviar os atalhos quebrados para a Lixeira') -Selected $true -Target "cleanup.shortcuts" -Advice $advice -Data $broken)
}


function Get-TFToolkitCheckupMemory {
    $memory = Get-TFToolkitMemoryUsage

    # Sem leitura, a linha diz isso: sumir com ela pareceria que a memória nem foi olhada (ou que está tudo bem).
    if ($null -eq $memory) {
        return (New-TFToolkitCheckupFinding -Id "memory" -Label (Get-TFToolkitText 'Memória') -Value (Get-TFToolkitText 'não foi possível ler') -Level Info -Unread $true)
    }

    $text = (Get-TFToolkitText '{0}% em uso ({1} de {2})' "$($memory.Percent)" "$(Format-TFToolkitBytes -Bytes $memory.Used)" "$(Format-TFToolkitBytes -Bytes $memory.Total)")

    # Sem correção daqui: esvaziar a memória dos programas não resolve (eles a recarregam do disco, mais devagar, e a
    # memória volta a encher). O que resolve é fechar o que pesa.
    if (Test-TFToolkitMemoryHigh -Memory $memory) {
        return (New-TFToolkitCheckupFinding -Id "memory" -Label (Get-TFToolkitText 'Memória') -Value $text -Level Warn -Target "performance.processes" `
                -Advice (Get-TFToolkitText 'feche o que pesa em Desempenho > Programas pesando agora'))
    }

    return (New-TFToolkitCheckupFinding -Id "memory" -Label (Get-TFToolkitText 'Memória') -Value $text -Level Ok)
}


function Get-TFToolkitCheckupStartup {
    # Mais de 8 pede atenção, com o caminho para Desempenho > Gerenciar inicialização: a página do PC lento, a mesma aonde
    # a memória alta leva.
    $enabled = @(Get-TFToolkitStartupItems | Where-Object { $_.Enabled }).Count

    if ($enabled -gt 8) {
        return (New-TFToolkitCheckupFinding -Id "startup" -Label (Get-TFToolkitText 'Abrem com o Windows') -Value (Format-TFToolkitCount -Count $enabled -One (Get-TFToolkitText 'programa') -Many (Get-TFToolkitText 'programas')) -Level Warn `
                -Target "performance.startup" -Advice (Get-TFToolkitText 'desligue o que não precisa em Desempenho > Gerenciar inicialização'))
    }

    return (New-TFToolkitCheckupFinding -Id "startup" -Label (Get-TFToolkitText 'Abrem com o Windows') -Value (Format-TFToolkitCount -Count $enabled -One (Get-TFToolkitText 'programa') -Many (Get-TFToolkitText 'programas')) -Level Ok)
}


function Get-TFToolkitCheckupPrograms {
    <#
    Os programas desatualizados. -Read: a consulta já começada (Start-TFToolkitWingetUpgradeRead, a mesma do Otimizar);
    sem ela, a consulta começa agora. A espera vai até o prazo dela (Receive-TFToolkitWingetUpgradeRead, contado do começo
    da consulta) e continua interrompível pelo Parar; sem resposta, a consulta é largada e a etapa fica como não lida.
    Sem o winget, o ponto leva ao reparo, como a tela Programas: quase tudo lá depende dele, e a pessoa nem saberia dos
    programas desatualizados.
    #>
    param ($Read = $null)

    $label = (Get-TFToolkitText 'Programas desatualizados')

    if (-not (Test-TFToolkitWinget)) {
        return (New-TFToolkitCheckupFinding -Id "programs" -Label $label -Short (Get-TFToolkitText 'Instalador de Aplicativo') -Value (Get-TFToolkitText 'não dá para conferir sem o Instalador de Aplicativo (winget)') -Level Warn `
                -Target "software.winget-repair" -Advice (Get-TFToolkitText 'veja o que fazer em Programas > Reparar o Instalador de Aplicativo'))
    }

    if ($null -eq $Read) { $Read = Start-TFToolkitWingetUpgradeRead }

    $received = Receive-TFToolkitWingetUpgradeRead -Task $Read

    if ($received.TimedOut) {
        return (New-TFToolkitCheckupFinding -Id "programs" -Label $label -Value (Get-TFToolkitText 'o Instalador de Aplicativo não respondeu em {0} segundos' "$($received.TimeoutSeconds)") -Level Info -Target "updates.winget" -Unread $true)
    }

    if ($null -eq $received.Upgrade) {
        Write-Verbose "Programas desatualizados: $($received.Error)"
        return (New-TFToolkitCheckupFinding -Id "programs" -Label $label -Value (Get-TFToolkitText 'não foi possível ler') -Level Info -Target "updates.winget" -Unread $true)
    }

    return (ConvertTo-TFToolkitCheckupProgramsFinding -Upgrade $received.Upgrade)
}


function ConvertTo-TFToolkitCheckupProgramsFinding {
    # O ponto dos programas desatualizados a partir da resposta do "winget upgrade" (ExitCode, Lines e Text), com as
    # mesmas regras da tela Atualizar programas: nada a atualizar pelo código ou pela frase, os marcados para não atualizar
    # fora da conta, e uma resposta sem tabela que não diz "nada a atualizar" como não lida.
    param ([Parameter(Mandatory)]$Upgrade)

    $label = (Get-TFToolkitText 'Programas desatualizados')

    if (Test-TFToolkitWingetNoUpgradeOutput -OutputText ([string]$Upgrade.Text) -ExitCode ([int]$Upgrade.ExitCode)) {
        return (New-TFToolkitCheckupFinding -Id "programs" -Label $label -Value (Get-TFToolkitText 'nenhum') -Level Ok)
    }

    $available = @(ConvertFrom-TFToolkitWingetTable -Lines @($Upgrade.Lines))

    if ($available.Count -eq 0) {
        return (New-TFToolkitCheckupFinding -Id "programs" -Label $label -Value (Get-TFToolkitText 'não foi possível ler') -Level Info -Target "updates.winget" -Unread $true)
    }

    return (New-TFToolkitCheckupFinding -Id "programs" -Label $label -Value (Format-TFToolkitCount -Count $available.Count -One (Get-TFToolkitText 'programa') -Many (Get-TFToolkitText 'programas')) -Level Warn `
            -Target "updates.winget" -Advice (Get-TFToolkitText 'atualize em Atualizações > Atualizar programas (winget)'))
}


function Get-TFToolkitCheckupWindows {
    # O ESU do Windows 10 é conferido pela revisão da build instalada, sem consultar o histórico de atualizações.
    $support = Get-TFToolkitWindowsSupportStatus

    $issue = Get-TFToolkitWindowsSupportIssue -Status $support
    $findings = @()

    # Com o suporte em dia, falta saber se as atualizações chegaram (a mesma conta do Início): um Windows parado na
    # atualização de meses atrás (Windows Update pausado, desligado ou com defeito) está sem as correções de segurança,
    # mesmo dentro do prazo. Sem como saber (versão fora do catálogo, Windows Server), a linha só aparece com a pausa.
    # Pausadas (Configurações > Windows Update), o Windows não instala nada até a data: com as de segurança atrasadas, o
    # que resolve é retomar, e o ponto leva ao Windows Update, como a linha da página Atualizações; em dia, a pausa é uma
    # escolha da pessoa (até 35 dias) e fica como informação.
    if ([string]$support.State -in @("Supported", "EndingSoon", "Esu")) {
        $label = (Get-TFToolkitText 'Atualizações do Windows')
        $lag = $null
        $pause = Get-TFToolkitWindowsUpdatePause
        $paused = $(if ($null -ne $pause) { Get-TFToolkitUpdatePauseText -Pause $pause -Detail } else { "" })

        try { $lag = Get-TFToolkitWindowsUpdateLag -Build ([int]$support.Build) } catch { $lag = $null }

        if ($lag -eq $true -and $paused) {
            $findings += New-TFToolkitCheckupFinding -Id "updates" -Label $label -Value (Get-TFToolkitText 'faltam atualizações de segurança; {0}' "$paused") -Level Warn `
                -Target "updates.windows" -Advice (Get-TFToolkitText 'retome as atualizações em Atualizações > Windows Update')
        }
        elseif ($lag -eq $true) {
            $findings += New-TFToolkitCheckupFinding -Id "updates" -Label $label -Value (Get-TFToolkitText 'faltam atualizações de segurança') -Level Warn `
                -Target "updates.install" -Advice (Get-TFToolkitText 'instale em Atualizações > Instalar atualizações do Windows')
        }
        elseif ($lag -eq $false) {
            $findings += $(if ($paused) { New-TFToolkitCheckupFinding -Id "updates" -Label $label -Value (Get-TFToolkitText 'nenhuma atualização de segurança atrasada; {0}' "$paused") -Level Info -Target "updates.windows" }
                else { New-TFToolkitCheckupFinding -Id "updates" -Label $label -Value (Get-TFToolkitText 'nenhuma atualização de segurança atrasada') -Level Ok })
        }
        elseif ($paused) {
            $findings += New-TFToolkitCheckupFinding -Id "updates" -Label $label -Value $paused -Level Info -Target "updates.windows"
        }
    }

    if ($null -eq $issue) {
        $value = $(if ($support.State -eq "Supported") { (Get-TFToolkitText '{0}: atualizações até {1}' "$($support.Product)" "$(Format-TFToolkitDateTime -When $support.EndDate -Pattern 'dd/MM/yyyy')") } else { (Get-TFToolkitText '{0}: data não conhecida' "$($support.Product)") })
        return @(@(New-TFToolkitCheckupFinding -Id "windows" -Label (Get-TFToolkitText 'Suporte do Windows') -Value $value -Level $(if ($support.State -eq "Supported") { "Ok" } else { "Info" })) + $findings)
    }

    $value = switch ([string]$support.State) {
        "EndingSoon" { $(if ([int]$support.DaysLeft -le 0) { (Get-TFToolkitText 'atualizações só até hoje') } else { (Get-TFToolkitText 'atualizações só até {0}' "$(Format-TFToolkitDateTime -When $support.EndDate -Pattern 'dd/MM/yyyy')") }) }
        "Esu" { Get-TFToolkitEsuText -Status $support }
        default {
            if ([string]$support.State -eq "EsuAvailable" -and -not [bool](Get-TFToolkitJsonValue -Object $support -Name "EsuChecked" -Default $true)) { (Get-TFToolkitText 'não foi possível conferir o ESU') }
            else { (Get-TFToolkitText 'sem atualizações de segurança') }
        }
    }

    return @(@(New-TFToolkitCheckupFinding -Id "windows" -Label (Get-TFToolkitText 'Suporte do Windows') -Value "$($support.Product): $value" -Level Warn -Target "diagnostics.windows-support" -Advice (Get-TFToolkitText 'veja o que fazer em Diagnóstico > Suporte do Windows')) + $findings)
}


function Get-TFToolkitCheckupProtection {
    $protection = Get-TFToolkitSecurityStatus

    if ($null -eq $protection) {
        return (New-TFToolkitCheckupFinding -Id "protection" -Label (Get-TFToolkitText 'Proteção') -Value (Get-TFToolkitText 'não foi possível ler') -Level Info -Target "security.status" -Unread $true)
    }

    $antivirus = $protection.Antivirus

    # Os mesmos pontos da tela Estado da proteção, aonde a linha leva (Get-TFToolkitSecurityFindings), com o nome curto de
    # cada um: "2 ameaças ativas", "antivírus desligado", "firewall desligado (Rede pública)". As assinaturas têm a linha
    # delas, logo abaixo, com a correção.
    $problems = @(Get-TFToolkitSecurityFindings -Antivirus $antivirus -Firewall $protection.Firewall -Threats $protection.Threats |
            Where-Object { $_.Level -eq "Warning" -and [string]$_.Id -notlike "signatures*" -and -not [string]::IsNullOrWhiteSpace([string]$_.Short) } |
            ForEach-Object { [string]$_.Short })

    # O que não pôde ser lido (como na tela Estado da proteção e no Início): sem o firewall, ou sem as ameaças com o
    # Defender protegendo, "em dia" seria afirmar o que não foi visto. Unread: na frase da linha ("o firewall") e nas
    # listas da faixa ("Firewall"), como as etapas que não responderam.
    $unread = @()
    $unreadNames = @()
    if ($null -eq $protection.Firewall) { $unread += (Get-TFToolkitText 'o firewall'); $unreadNames += (Get-TFToolkitText 'Firewall') }
    if ($antivirus.Mode -eq "Active" -and $null -eq $protection.Threats) { $unread += (Get-TFToolkitText 'as ameaças ativas'); $unreadNames += (Get-TFToolkitText 'Ameaças ativas') }

    $findings = @()

    if ($problems.Count -gt 0) {
        $value = Join-TFToolkitList -Items $problems
        if ($unread.Count -gt 0) { $value += (Get-TFToolkitText '; não foi possível ler {0}' "$(Join-TFToolkitList -Items $unread)") }

        $findings += New-TFToolkitCheckupFinding -Id "protection" -Label (Get-TFToolkitText 'Proteção') -Value $value -Level Warn -Target "security.status" -Advice (Get-TFToolkitText 'veja em Segurança > Estado da proteção')
    }
    elseif ($unread.Count -gt 0) {
        # Sem nada pedindo atenção no que foi lido, o que faltou vai para a faixa ("Não foi possível ler: Firewall"): sem
        # isso, ela dizia "Tudo certo" em verde.
        $findings += New-TFToolkitCheckupFinding -Id "protection" -Label (Get-TFToolkitText 'Proteção') -Short (Join-TFToolkitList -Items $unreadNames) -Value (Get-TFToolkitText 'leitura incompleta: não foi possível ler {0}' "$(Join-TFToolkitList -Items $unread)") -Level Info -Target "security.status" -Unread $true
    }

    $isAdmin = Test-TFToolkitAdministrator

    # Os mesmos limites da tela Estado da proteção e do Início: mais de 7 dias (ou nunca atualizadas) pede atenção; de 4 a
    # 7, o Windows costuma atualizar sozinho (um notebook desligado num feriado), então é só informação, com a atualização
    # à mão e desmarcada.
    $never = [bool](Get-TFToolkitJsonValue -Object $antivirus -Name "SignaturesNeverUpdated" -Default $false)

    if ($antivirus.Mode -eq "Active" -and ($never -or ($null -ne $antivirus.SignatureAgeDays -and [int]$antivirus.SignatureAgeDays -gt 3))) {
        $old = ($never -or [int]$antivirus.SignatureAgeDays -gt 7)
        $age = $(if ($never) { (Get-TFToolkitText 'nunca atualizadas') } else { (Get-TFToolkitText 'atualizadas há {0} dias' "$($antivirus.SignatureAgeDays)") })

        $findings += New-TFToolkitCheckupFinding -Id "signatures" -Label (Get-TFToolkitText 'Assinaturas do antivírus') -Value $age -Level $(if ($old) { "Warn" } else { "Info" }) `
            -Fix $(if ($isAdmin) { "signatures" } else { "" }) -FixLabel (Get-TFToolkitText 'Atualizar as assinaturas do antivírus') -Selected ($isAdmin -and $old) -Target "security.signatures" `
            -Advice $(if ($isAdmin) { "" } elseif ($old) { (Get-TFToolkitText 'atualize em Segurança > Atualizar assinaturas do antivírus') } else { "" })
    }

    if ($findings.Count -eq 0) {
        $findings += New-TFToolkitCheckupFinding -Id "protection" -Label (Get-TFToolkitText 'Proteção') -Value (Get-TFToolkitText 'em dia') -Level Ok
    }

    return @($findings)
}


function Get-TFToolkitCheckupReboot {
    if (Test-TFToolkitPendingReboot) {
        return (New-TFToolkitCheckupFinding -Id "reboot" -Label (Get-TFToolkitText 'Reinício pendente') -Value (Get-TFToolkitText 'sim') -Level Warn -Target "diagnostics.pending-reboot" -Advice (Get-TFToolkitText 'reinicie o PC quando puder; o motivo está em Diagnóstico > Reinício pendente'))
    }

    return (New-TFToolkitCheckupFinding -Id "reboot" -Label (Get-TFToolkitText 'Reinício pendente') -Value (Get-TFToolkitText 'não') -Level Ok)
}


function Get-TFToolkitCheckupBlueScreens {
    # As telas azuis dos últimos 30 dias (Get-TFToolkitBlueScreens): com alguma, um ponto de atenção que leva à causa
    # provável em Diagnóstico > Telas azuis. Não há o que corrigir daqui.
    $screens = @(Get-TFToolkitBlueScreens -Days 30)

    if ($screens.Count -eq 0) {
        return (New-TFToolkitCheckupFinding -Id "bluescreens" -Label (Get-TFToolkitText 'Telas azuis') -Value (Get-TFToolkitText 'nenhuma nos últimos 30 dias') -Level Ok)
    }

    $count = Format-TFToolkitCount -Count $screens.Count -One (Get-TFToolkitText 'tela azul') -Many (Get-TFToolkitText 'telas azuis')
    $about = Get-TFToolkitBugCheckCauseText -Cause ([string](Get-TFToolkitBlueScreenMainCause -Screens $screens).Cause)

    return (New-TFToolkitCheckupFinding -Id "bluescreens" -Label (Get-TFToolkitText 'Telas azuis') -Value (Get-TFToolkitText '{0} nos últimos 30 dias; causa mais provável: {1}' "$count" "$($about.Cause)") -Level Warn `
            -Target "diagnostics.blue-screens" -Advice (Get-TFToolkitText 'veja o que fazer em Diagnóstico > Telas azuis'))
}


function Invoke-TFToolkitCheckupScan {
    <#
    Roda as etapas da verificação, uma por vez, com a barra de progresso. Uma etapa que falha vira um achado "não foi
    possível ler" e não interrompe as outras. A consulta do winget começa antes de todas e corre junto com elas
    (Start-TFToolkitWingetUpgradeRead): na vez dela, a etapa dos programas só recebe a resposta. Devolve os achados.
    #>
    $steps = @(Get-TFToolkitCheckupSteps)
    $findings = @()
    $position = 0
    $programs = $null

    $readers = @{
        disk        = { Get-TFToolkitCheckupDisk }
        junk        = { Get-TFToolkitCheckupJunk }
        registry    = { Get-TFToolkitCheckupRegistry }
        shortcuts   = { Get-TFToolkitCheckupShortcuts }
        memory      = { Get-TFToolkitCheckupMemory }
        startup     = { Get-TFToolkitCheckupStartup }
        programs    = { Get-TFToolkitCheckupPrograms -Read $programs }
        windows     = { Get-TFToolkitCheckupWindows }
        protection  = { Get-TFToolkitCheckupProtection }
        reboot      = { Get-TFToolkitCheckupReboot }
        bluescreens = { Get-TFToolkitCheckupBlueScreens }
    }

    try {
        # Sem a consulta começada aqui, a etapa dos programas a começa na vez dela (e, se falhar de novo, fica não lida).
        try { $programs = Start-TFToolkitWingetUpgradeRead } catch { Write-Verbose "Verificar o PC, programas: $($_.Exception.Message)" }

        foreach ($step in $steps) {
            Write-Progress -Activity (Get-TFToolkitText 'Verificando o PC') -Status (Get-TFToolkitText '{0} de {1}: {2}' "$($position + 1)" "$($steps.Count)" "$($step.Text)") -PercentComplete ([int]($position * 100 / $steps.Count))
            $position++

            try {
                $read = @(& $readers[$step.Id] | Where-Object { $null -ne $_ })
            }
            catch {
                Write-Verbose "Verificar o PC, $($step.Id): $($_.Exception.Message)"
                $read = @(New-TFToolkitCheckupFinding -Id $step.Id -Label $step.Label -Value (Get-TFToolkitText 'não foi possível ler') -Level Info -Unread $true)
            }

            # A etapa de cada achado: o veredito conta etapas lidas, não achados (a limpeza e a proteção dão mais de um).
            foreach ($finding in $read) { Add-Member -InputObject $finding -NotePropertyName StepId -NotePropertyValue $step.Id -Force }

            $findings += $read
        }
    }
    finally {
        # Parada no meio (o Parar), a consulta do winget que ninguém vai receber não fica rodando.
        Stop-TFToolkitInBackground -Task $programs
        Write-Progress -Activity (Get-TFToolkitText 'Verificando o PC') -Completed
    }

    return @($findings)
}


function Invoke-TFToolkitCheckupFix {
    # Aplica uma correção e devolve um TFToolkit.Result (Etapa = o rótulo da correção; Data.FreedBytes quando libera espaço).
    param ([Parameter(Mandatory)]$Finding)

    switch ($Finding.Fix) {
        { $_ -in "junk", "browser" } {
            $result = Invoke-TFToolkitCleanupTargets -Targets @($Finding.Data) -NoSummary

            # Nada liberado e alguma parte com problema (tudo em uso, uma pasta recusada): a limpeza não aconteceu, e
            # contá-la como "correção feita" escondia isso na faixa.
            $cleaned = Get-TFToolkitResultData -Result $result -Name "FreedBytes"

            if ($result.Kind -eq "Warning" -and ($null -eq $cleaned -or [int64]$cleaned -le 0)) {
                $result = New-TFToolkitResult -Kind Failed -Detail $result.Detail -Data $result.Data
            }
        }
        "registry" {
            $result = Clear-TFToolkitRegistryIssues -Issues @($Finding.Data)
        }
        "shortcuts" {
            $moved = @()
            $failed = 0

            try {
                foreach ($shortcut in @($Finding.Data)) {
                    # Aberto em outro programa, o Windows mostraria a janela "Arquivo em uso" e a correção ficaria parada.
                    if (Test-TFToolkitItemInUse -Path $shortcut.Path) { $failed++; continue }

                    try { Move-TFToolkitItemToRecycleBin -Path $shortcut.Path; $moved += $shortcut.Name } catch { $failed++ }
                }
            }
            finally {
                # No finally: parar a correção no meio não deixa sem anotação o que já foi para a Lixeira.
                if ($moved.Count -gt 0) {
                    [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Atalhos quebrados') -Text $(if ($moved.Count -eq 1) { (Get-TFToolkitText '{0} foi para a Lixeira' "$(Join-TFToolkitList -Items $moved)") } else { (Get-TFToolkitText '{0} foram para a Lixeira' "$(Join-TFToolkitList -Items $moved)") }))
                }
            }

            $text = Format-TFToolkitCount -Count $moved.Count -One (Get-TFToolkitText 'atalho foi para a Lixeira') -Many (Get-TFToolkitText 'atalhos foram para a Lixeira')
            $result = $(if ($failed -eq 0) { New-TFToolkitResult -Kind Ok -Detail $text } elseif ($moved.Count -eq 0) { New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nenhum atalho foi removido') } else { New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0}; {1} não' "$text" "$failed") })
        }
        "signatures" {
            $result = Update-TFToolkitDefenderSignatures -Embedded -PassThru
        }
        default {
            $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'correção desconhecida')
        }
    }

    $result.Etapa = $Finding.FixLabel

    return $result
}


function Get-TFToolkitCheckupWeight {
    <#
    O peso de um ponto de atenção, para a ordem das listas e o botão da faixa: o que põe os arquivos ou o PC em risco (um
    disco falhando, a proteção, as atualizações de segurança) vem antes do que só deixa o PC mais lento ou mais cheio. Os
    mesmos pesos do Início onde a nota de saúde tem o ponto (Home.psm1): a proteção, o disco quase cheio ou com pouco
    espaço, as atualizações de segurança, as assinaturas e o reinício.
    #>
    param ([Parameter(Mandatory)]$Finding)

    switch ([string]$Finding.Id) {
        "disk-health" { return 35 }
        "protection" { return 30 }
        "disk" { return $(if ([string]$Finding.Data -eq "Critical") { 25 } else { 12 }) }
        "updates" { return 20 }
        "windows" { return 20 }
        "bluescreens" { return 15 }
        "signatures" { return 10 }
        "reboot" { return 8 }
        "programs" { return 6 }
        "memory" { return 5 }
        "startup" { return 4 }
        "junk" { return 3 }
        "shortcuts" { return 2 }
        default { return 1 }
    }
}


function Get-TFToolkitCheckupOrder {
    # Os pontos do mais importante ao menos (Get-TFToolkitCheckupWeight); no mesmo peso, na ordem das etapas.
    param ([object[]]$Findings = @())

    $position = 0
    $ranked = @(foreach ($finding in @($Findings | Where-Object { $null -ne $_ })) {
            $position++
            [PSCustomObject]@{ Finding = $finding; Weight = (Get-TFToolkitCheckupWeight -Finding $finding); Position = $position }
        })

    return @($ranked | Sort-Object -Property @{ Expression = "Weight"; Descending = $true }, @{ Expression = "Position"; Descending = $false } | ForEach-Object { $_.Finding })
}


function Format-TFToolkitCheckupReason {
    # O motivo de uma correção que não deu certo, para depois de "Nome: " na faixa: legível, sem o ponto final e com a
    # primeira letra minúscula (menos numa sigla). Longo demais (a faixa tem 220 letras para tudo), fica a primeira parte
    # ("nada foi liberado", sem a lista das pastas) ou nada, e a frase diz só o nome: o motivo inteiro continua no resumo.
    param ([AllowEmptyString()][AllowNull()][string]$Text)

    $why = ([string](ConvertTo-TFToolkitReadableError -Text $Text)).Trim().TrimEnd('.').Trim()

    if ($why.Length -gt 90) { $why = ($why -split ';')[0].Trim() }
    if (-not $why -or $why.Length -gt 90) { return "" }

    if ($why.Length -gt 1 -and [char]::IsUpper($why[0]) -and -not [char]::IsUpper($why[1])) {
        $why = $why.Substring(0, 1).ToLowerInvariant() + $why.Substring(1)
    }

    return $why
}


function Set-TFToolkitCheckupView {
    <#
    Como a janela mostra o fim da verificação. O título da faixa diz o que aconteceu ("3 correções feitas, 1,9 GB
    liberados", "Nenhuma correção funcionou", "2 pontos pedem você", "Nada pedindo atenção no que foi lido"); a frase
    embaixo, a correção que deu problema e por quê, o que ainda pede a pessoa e o que não foi lido. Os pontos vêm do mais
    importante ao menos (Get-TFToolkitCheckupWeight), e o botão da faixa leva à tela do primeiro deles. O console continua
    com o Detail.
    Problems: as correções que falharam ou ficaram pela metade, cada uma com Finding e Result. -NotRead: a maior parte das
    etapas não respondeu.
    #>
    param (
        [Parameter(Mandatory)]$Result,
        [object[]]$Results = @(),
        [int]$Failed = 0,
        [int64]$Freed = 0,
        [object[]]$Remaining = @(),
        [object[]]$Problems = @(),
        [AllowEmptyString()][string]$Unread = "",
        [switch]$Declined,
        [switch]$NotRead
    )

    if ($NotRead) {
        return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'Não foi possível verificar o PC') `
                -Note (Get-TFToolkitText 'Não foi possível ler a maior parte do PC: tente de novo; se continuar, reinicie o PC.'))
    }

    $troubled = @($Problems | Where-Object { $null -ne $_ -and $null -ne $_.Finding })
    $troubledIds = @($troubled | ForEach-Object { [string]$_.Finding.Id })

    # O que ainda pede a pessoa, sem as correções que deram problema: essas vêm à parte, com o motivo.
    $still = @(Get-TFToolkitCheckupOrder -Findings @($Remaining | Where-Object { $null -ne $_ -and $troubledIds -notcontains [string]$_.Id }))

    $next = ""
    $nextLabel = ""
    $first = @(Get-TFToolkitCheckupOrder -Findings @(@($troubled | ForEach-Object { $_.Finding }) + @($still)) | Where-Object { -not [string]::IsNullOrEmpty([string]$_.Target) }) | Select-Object -First 1

    if ($null -ne $first) {
        try {
            $item = Get-TFToolkitNavItem -Id ([string]$first.Target)
            if ($null -ne $item) { $next = [string]$item.Id; $nextLabel = [string]$item.Label }
        }
        catch {
            Write-Verbose "Próximo passo da verificação: $($_.Exception.Message)"
        }
    }

    $done = @($Results).Count - $Failed
    $headline = ""
    $notes = @()

    if (@($Results).Count -gt 0 -and $done -le 0) {
        $headline = (Get-TFToolkitText 'Nenhuma correção funcionou')
    }
    elseif (@($Results).Count -gt 0) {
        $headline = Format-TFToolkitCount -Count $done -One (Get-TFToolkitText 'correção feita') -Many (Get-TFToolkitText 'correções feitas')
        if ($Freed -gt 0) { $headline += (Get-TFToolkitText ', {0} liberados' "$(Format-TFToolkitBytes -Bytes $Freed)") }
    }
    elseif ($Declined) {
        $headline = (Get-TFToolkitText 'Nenhuma correção feita')
    }
    elseif ($still.Count -gt 0) {
        $headline = Format-TFToolkitCount -Count $still.Count -One (Get-TFToolkitText 'ponto pede você') -Many (Get-TFToolkitText 'pontos pedem você')
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Unread)) {
        # Tudo o que foi lido está em dia, mas não tudo foi lido: "Tudo certo" afirmaria o que não foi visto.
        $headline = (Get-TFToolkitText 'Nada pedindo atenção no que foi lido')
    }
    else {
        return $Result
    }

    # A correção que deu problema: com uma só, o motivo; com mais, os nomes (os motivos ficam no resumo).
    if ($troubled.Count -eq 1) {
        $why = Format-TFToolkitCheckupReason -Text ([string]$troubled[0].Result.Detail)
        $notes += $(if ($why) { (Get-TFToolkitText '{0}: {1}' "$($troubled[0].Finding.Short)" "$why") } else { (Get-TFToolkitText 'Com problema: {0}' "$($troubled[0].Finding.Short)") })
    }
    elseif ($troubled.Count -gt 1) {
        $notes += (Get-TFToolkitText 'Com problema: {0}' "$(Join-TFToolkitShortList -Items @($troubled | ForEach-Object { [string]$_.Finding.Short }))")
    }

    if ($still.Count -gt 0) {
        # Os nomes curtos, do mais importante ao menos; numa lista longa, os primeiros e "e mais N", para a frase não
        # cortar no meio o que vem depois (o que não foi lido).
        $names = Join-TFToolkitShortList -Items @($still | ForEach-Object { [string]$_.Short })

        if (@($Results).Count -gt 0 -or $Declined) {
            $notes += $(if ($still.Count -eq 1) { (Get-TFToolkitText 'Ainda pede você: {0}' "$names") } else { (Get-TFToolkitText 'Ainda pedem você: {0}' "$names") })
        }
        elseif ($still.Count -eq 1) {
            # Um ponto só: o que ele é, e não só o nome ("Proteção: 2 ameaças ativas e antivírus desligado").
            $notes += (Get-TFToolkitText '{0}: {1}' "$($still[0].Label)" "$($still[0].Value)")
        }
        else {
            $notes += $names
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Unread)) { $notes += (Get-TFToolkitText 'Não foi possível ler: {0}' "$Unread") }
    if ($notes.Count -eq 0) { $notes += (Get-TFToolkitText 'Nada mais pedindo atenção') }

    return (Set-TFToolkitResultView -Result $Result -Headline $headline -Note "$($notes -join '. ')." -Next $next -NextLabel $nextLabel)
}


function Invoke-TFToolkitCheckup {
    $title = (Get-TFToolkitText 'Verificar o PC')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        $findings = @(Invoke-TFToolkitCheckupScan)

        Write-TFToolkitSection -Title (Get-TFToolkitText 'O que a verificação encontrou')

        foreach ($finding in $findings) {
            Write-TFToolkitKeyValue -Label $finding.Label -Value $finding.Value -LabelWidth 32 -Level $(if ($finding.Level -eq "Info") { "Normal" } else { $finding.Level })
        }

        Write-Host ""

        $attention = @($findings | Where-Object { $_.Level -eq "Warn" })
        $fixable = @($findings | Where-Object { $_.Fix })
        $safe = @($fixable | Where-Object { $_.Selected })
        $manual = @($attention | Where-Object { -not $_.Fix -and $_.Advice })

        foreach ($finding in $manual) {
            Write-TFToolkitStatus -Type Warning -Message "$($finding.Label): $($finding.Advice)."
        }

        # A informação com orientação própria e sem correção daqui (atalhos quebrados só no OneDrive) diz onde ver, sem
        # pedir nada: sem a linha, a orientação não aparecia em lugar nenhum.
        $hints = @($findings | Where-Object { $_.Level -eq "Info" -and -not $_.Fix -and $_.Advice -and -not [bool](Get-TFToolkitJsonValue -Object $_ -Name "Unread" -Default $false) })

        foreach ($finding in $hints) {
            Write-TFToolkitStatus -Type Info -Message "$($finding.Label): $($finding.Advice)."
        }

        # A verificação conta como cuidado com o PC (o Início e o monitor param de lembrar por um mês) só quando ela de
        # fato olhou o PC (mais da metade das etapas respondeu) e não deixou correções seguras para trás: cancelada, ou
        # com todas as correções falhando, ela não cuidou de nada.
        $unreadFindings = @($findings | Where-Object { [bool](Get-TFToolkitJsonValue -Object $_ -Name "Unread" -Default $false) })
        $stepOf = { param ($item) [string](Get-TFToolkitJsonValue -Object $item -Name "StepId" -Default $item.Id) }
        $stepCount = @($findings | ForEach-Object { & $stepOf $_ } | Select-Object -Unique).Count
        $unreadSteps = @($unreadFindings | ForEach-Object { & $stepOf $_ } | Select-Object -Unique).Count
        $scanRead = ($stepCount -gt 0 -and ($unreadSteps * 2) -lt $stepCount)

        # O que não respondeu vai junto do veredito (como a nota "Incompleta" do Início): "nada pedindo atenção" em verde
        # afirmaria o que não foi visto.
        $unreadText = Join-TFToolkitList -Items @($unreadFindings | ForEach-Object { [string]$_.Short })

        $results = @()
        # Cada correção feita, com o ponto dela: a faixa diz pelo nome do ponto qual deu problema.
        $pairs = @()
        $fixedIds = @()
        $freed = [int64]0
        # A pessoa cancelou a lista de correções: o veredito é o da verificação, sem conta como cuidado com o PC.
        $declined = $false

        if ($fixable.Count -gt 0) {
            if ($manual.Count + $hints.Count -gt 0) { Write-Host "" }

            if ($safe.Count -gt 0) {
                # Só o que está de fato marcado na lista: falar do registro ou dos atalhos quando eles nem aparecem confunde.
                $why = @{
                    junk       = (Get-TFToolkitText 'os temporários o Windows recria')
                    registry   = (Get-TFToolkitText 'o registro tem backup e volta em Manutenção > Histórico de mudanças')
                    shortcuts  = (Get-TFToolkitText 'os atalhos vão para a Lixeira')
                    signatures = (Get-TFToolkitText 'as assinaturas só são atualizadas')
                }
                $reasons = @($safe | Where-Object { $why.ContainsKey([string]$_.Fix) } | ForEach-Object { $why[[string]$_.Fix] } | Select-Object -Unique)
                $message = $(if ($reasons.Count -gt 0) { (Get-TFToolkitText 'O que vem marcado é seguro: {0}.' "$(Join-TFToolkitList -Items $reasons)") } else { (Get-TFToolkitText 'O que vem marcado é seguro de corrigir.') })

                Write-TFToolkitStatus -Type Info -Message $message
            }
            else {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nada desta lista é necessário: marque só o que quiser fazer agora.')
            }

            Write-Host ""

            $options = @(
                foreach ($finding in $fixable) {
                    $description = $finding.Value
                    if ($finding.Advice) { $description += " · $($finding.Advice)" }
                    @{ Key = $finding.Id; Label = $finding.FixLabel; Description = $description; Selected = [bool]$finding.Selected }
                }
            )

            try {
                $picked = Read-TFToolkitMultiSelect -Message (Get-TFToolkitText 'O que corrigir agora?') -Options $options -ConfirmLabel (Get-TFToolkitText 'Corrigir') -CancelLabel (Get-TFToolkitText 'Agora não')
            }
            catch {
                # No menu de texto, respostas que não valem até o limite: é não corrigir nada, e não um erro da verificação
                # (o que ela achou continua na tela e na faixa).
                Write-Verbose "Lista do que corrigir sem resposta: $($_.Exception.Message)"
                $picked = $null
            }

            # Com correções seguras na lista, não escolher nada é cancelar as correções, mas não a verificação: o que ela
            # achou continua na tela e na faixa (um antivírus desligado não pode sumir num "Operação cancelada"). Só com o
            # que é opcional (o cache dos navegadores, por exemplo), é a resposta "não, obrigado".
            if (($null -eq $picked -or @($picked).Count -eq 0) -and $safe.Count -gt 0) {
                $declined = $true
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhuma correção foi feita.')
            }

            $chosen = @($fixable | Where-Object { $null -ne $picked -and @($picked) -contains $_.Id })
            $position = 0

            foreach ($finding in $chosen) {
                Write-Progress -Activity (Get-TFToolkitText 'Corrigindo') -Status (Get-TFToolkitText '{0} de {1}: {2}' "$($position + 1)" "$($chosen.Count)" "$($finding.FixLabel)") -PercentComplete ([int]($position * 100 / $chosen.Count))
                $position++

                try {
                    $result = Invoke-TFToolkitCheckupFix -Finding $finding
                }
                catch {
                    $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message.TrimEnd('.')
                    $result.Etapa = $finding.FixLabel
                }

                $bytes = Get-TFToolkitResultData -Result $result -Name "FreedBytes"
                if ($null -ne $bytes) { $freed += [int64]$bytes }
                # Remaining: a correção rodou, mas o ponto continua pedindo atenção (a memória ainda alta, por exemplo).
                if ($result.Kind -ne "Failed" -and -not [bool](Get-TFToolkitResultData -Result $result -Name "Remaining")) { $fixedIds += $finding.Id }

                $results += $result
                $pairs += [PSCustomObject]@{ Finding = $finding; Result = $result }
            }

            if ($chosen.Count -gt 0) {
                Write-Progress -Activity (Get-TFToolkitText 'Corrigindo') -Completed

                Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')
                Write-TFToolkitResultTable -Results $results

                if ($freed -gt 0) {
                    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Espaço liberado') -Value (Format-TFToolkitBytes -Bytes $freed) -Level Ok

                    # Com espaço liberado, o disco é lido de novo: "ainda pede atenção: Espaço no disco" com ele já acima do
                    # limite seria falso. Sem leitura agora, fica o que a verificação viu.
                    $diskFinding = @($attention | Where-Object { [string]$_.Id -eq "disk" }) | Select-Object -First 1

                    if ($null -ne $diskFinding) {
                        try {
                            $now = Get-TFToolkitCheckupDiskSpace

                            if ($null -ne $now -and -not [bool]$now.Unread) {
                                $diskFinding.Value = $now.Value
                                $diskFinding.Data = $now.Data
                                Write-TFToolkitKeyValue -Label $now.Label -Value $now.Value -Level $now.Level
                                if ($now.Level -eq "Ok") { $fixedIds += "disk" }
                            }
                        }
                        catch {
                            Write-Verbose "Espaço no disco depois das correções: $($_.Exception.Message)"
                        }
                    }
                }
            }
        }

        $failed = @($results | Where-Object { $_.Kind -eq "Failed" })
        $warned = @($results | Where-Object { $_.Kind -eq "Warning" })
        $problems = @($pairs | Where-Object { $_.Result.Kind -in @("Failed", "Warning") })

        # O que continua pedindo atenção: tudo o que foi apontado e não foi corrigido (por escolha, ou porque a correção
        # falhou), do mais importante ao menos. Sem isso, "1 correção feita" em verde esconderia um antivírus desligado.
        $remaining = @(Get-TFToolkitCheckupOrder -Findings @($attention | Where-Object { $fixedIds -notcontains $_.Id }))

        if ($scanRead -and -not $declined -and ($results.Count -eq 0 -or $failed.Count -lt $results.Count)) {
            [void](Set-TFToolkitSetting -Name "LastCheckup" -Value (Get-Date).ToString("s", [System.Globalization.CultureInfo]::InvariantCulture))
        }

        $data = @{ FreedBytes = $freed }

        if ($results.Count -eq 0 -and -not $scanRead) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível ler a maior parte do PC: tente de novo; se continuar, reinicie o PC.')
            $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível ler a maior parte do PC') -Title $title
            $final = Set-TFToolkitCheckupView -Result $final -NotRead
        }
        elseif ($results.Count -gt 0 -and $failed.Count -eq $results.Count) {
            $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nenhuma correção funcionou') -Title $title -Data $data
            $final = Set-TFToolkitCheckupView -Result $final -Results $results -Failed $failed.Count -Remaining $remaining -Problems $problems -Unread $unreadText
        }
        else {
            $parts = @()

            if ($results.Count -gt 0) {
                $done = Format-TFToolkitCount -Count ($results.Count - $failed.Count) -One (Get-TFToolkitText 'correção feita') -Many (Get-TFToolkitText 'correções feitas')
                $parts += $(if ($freed -gt 0) { (Get-TFToolkitText '{0}; {1} liberados' "$done" "$(Format-TFToolkitBytes -Bytes $freed)") } else { $done })
            }
            elseif ($declined) {
                $parts += (Get-TFToolkitText 'nenhuma correção feita')
            }

            if ($problems.Count -gt 0) {
                $parts += (Get-TFToolkitText '{0} com problema' "$(Join-TFToolkitList -Items @($problems | ForEach-Object { [string]$_.Finding.Short }))")
            }

            if ($remaining.Count -gt 0) {
                # A faixa diz o que pede atenção pelo nome (um "2 pontos pedem a sua decisão" não diz quais).
                $still = ($results.Count -gt 0 -or $declined)
                $names = Join-TFToolkitList -Items @($remaining | ForEach-Object { [string]$_.Short })
                $parts += $(
                    if ($still -and $remaining.Count -eq 1) { (Get-TFToolkitText 'ainda pede atenção: {0}' "$names") }
                    elseif ($still) { (Get-TFToolkitText 'ainda pedem atenção: {0}' "$names") }
                    elseif ($remaining.Count -eq 1) { (Get-TFToolkitText 'pede atenção: {0}' "$names") }
                    else { (Get-TFToolkitText 'pedem atenção: {0}' "$names") }
                )

                if ($results.Count -gt 0 -or $declined) {
                    # O que fazer com cada um que tem orientação e ainda não a mostrou (os sem correção já a mostraram
                    # antes da lista): a memória, por exemplo, só tinha a dica dentro da lista de marcar.
                    foreach ($finding in @($remaining | Where-Object { $_.Fix -and $_.Advice })) {
                        Write-TFToolkitStatus -Type Warning -Message "$($finding.Label): $($finding.Advice)."
                    }

                    Write-TFToolkitStatus -Type Warning -Message $(if ($remaining.Count -eq 1) { (Get-TFToolkitText 'Ainda pede atenção: {0}.' "$names") } else { (Get-TFToolkitText 'Ainda pedem atenção: {0}.' "$names") })
                }
            }

            if ($unreadFindings.Count -gt 0) { $parts += (Get-TFToolkitText 'não foi possível ler: {0}' "$unreadText") }

            if ($parts.Count -eq 0) {
                Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Nada pedindo atenção.')
                $parts += (Get-TFToolkitText 'nada pedindo atenção')
            }
            elseif ($results.Count -eq 0 -and $remaining.Count -eq 0) {
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Nada pedindo atenção no que foi lido; não foi possível ler: {0}.' "$unreadText")
                $parts = @((Get-TFToolkitText 'nada pedindo atenção no que foi lido; não foi possível ler: {0}' "$unreadText"))
            }

            $clean = ($failed.Count -eq 0 -and $warned.Count -eq 0 -and $remaining.Count -eq 0 -and $unreadFindings.Count -eq 0)
            $final = New-TFToolkitResult -Kind $(if ($clean) { "Ok" } else { "Warning" }) -Detail ($parts -join "; ") -Title $title -Data $data
            $final = Set-TFToolkitCheckupView -Result $final -Results $results -Failed $failed.Count -Freed $freed -Remaining $remaining -Problems $problems -Unread $unreadText -Declined:$declined
        }
    }
    catch {
        Write-Progress -Activity (Get-TFToolkitText 'Verificando o PC') -Completed
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível verificar o PC: {0}.' "$($_.Exception.Message.TrimEnd('.'))")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message.TrimEnd('.') -Title $title
        $final = Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'Não foi possível verificar o PC') -Note (Format-TFToolkitReasonNote -Text $_.Exception.Message)
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
