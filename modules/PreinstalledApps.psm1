# Aplicativos que vêm com o Windows (ou que o fabricante e a Microsoft instalam por conta própria) e que muita gente nunca usa.
#
# Só mexe numa lista curta e conhecida, mostra o que existe neste PC e remove apenas o que a pessoa marcar, para o
# usuário atual. Nada é removido do sistema: os aplicativos voltam pela Microsoft Store, menos os que a Microsoft
# aposentou (Reinstallable falso), e a tela diz isso antes.


# ---------------------------------------------------------------------------
# Catálogo
# ---------------------------------------------------------------------------

function Get-TFToolkitAppCatalog {
    <#
    Os aplicativos que o TF-Toolkit oferece para remover. Pattern é o nome interno do pacote (aceita * no fim) e alcança só
    os pacotes daquele aplicativo: "*Facebook*" pegaria também o Instagram e o Messenger, que são do mesmo fabricante. A
    lista é curta de propósito: nada que o Windows precise para funcionar (Loja, Fotos, Calculadora, Terminal, Segurança
    do Windows, instalador de aplicativos, componentes .NET e VCLibs) está nela, e do Xbox só entra o aplicativo: a Game
    Bar e os componentes de identidade e de rede que os jogos usam ficam.
    #>
    return @(
        [PSCustomObject]@{ Pattern = "Microsoft.BingNews"; Label = (Get-TFToolkitText 'Microsoft Notícias'); Description = (Get-TFToolkitText 'Notícias do MSN') },
        [PSCustomObject]@{ Pattern = "Microsoft.BingWeather"; Label = (Get-TFToolkitText 'Clima'); Description = (Get-TFToolkitText 'Previsão do tempo do MSN') },
        [PSCustomObject]@{ Pattern = "Microsoft.GetHelp"; Label = (Get-TFToolkitText 'Obter Ajuda'); Description = (Get-TFToolkitText 'Atendimento da Microsoft dentro do Windows') },
        [PSCustomObject]@{ Pattern = "Microsoft.Getstarted"; Label = (Get-TFToolkitText 'Dicas'); Description = (Get-TFToolkitText 'Dicas e tutoriais do Windows') },
        # O aplicativo do Microsoft 365 (o antigo Office) virou Microsoft 365 Copilot em janeiro de 2025, e a Microsoft o
        # chama agora de Microsoft Copilot: o nome da lista é o que a pessoa vê no Menu Iniciar.
        [PSCustomObject]@{ Pattern = "Microsoft.MicrosoftOfficeHub"; Label = (Get-TFToolkitText 'Microsoft 365 Copilot (antigo Office)'); Description = (Get-TFToolkitText 'O aplicativo do Microsoft 365, que o Windows pode mostrar como Microsoft 365 Copilot ou Copilot; o Office que você já instalou não é afetado') },
        [PSCustomObject]@{ Pattern = "Microsoft.MicrosoftSolitaireCollection"; Label = (Get-TFToolkitText 'Microsoft Solitaire Collection'); Description = (Get-TFToolkitText 'Jogos de cartas com anúncios') },
        [PSCustomObject]@{ Pattern = "Microsoft.People"; Label = (Get-TFToolkitText 'Pessoas'); Description = (Get-TFToolkitText 'Agenda de contatos aposentada pela Microsoft: não volta depois de removida'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.WindowsFeedbackHub"; Label = (Get-TFToolkitText 'Hub de Comentários'); Description = (Get-TFToolkitText 'Envio de sugestões e erros à Microsoft') },
        [PSCustomObject]@{ Pattern = "Microsoft.YourPhone"; Label = (Get-TFToolkitText 'Vínculo com o Celular'); Description = (Get-TFToolkitText 'Liga o celular ao PC; mantenha se você usa') },
        [PSCustomObject]@{ Pattern = "Microsoft.ZuneVideo"; Label = (Get-TFToolkitText 'Filmes e TV'); Description = (Get-TFToolkitText 'Player e loja de vídeos da Microsoft') },
        # O Mapas e o Paint 3D saíram da Microsoft Store (julho de 2025 e novembro de 2024, nos recursos descontinuados do
        # Windows): removidos, não voltam. O Paint de sempre (Microsoft.Paint) é outro pacote e fica protegido.
        [PSCustomObject]@{ Pattern = "Microsoft.WindowsMaps"; Label = (Get-TFToolkitText 'Mapas'); Description = (Get-TFToolkitText 'Mapas do Windows; aposentado pela Microsoft: não volta depois de removido'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.MSPaint"; Label = (Get-TFToolkitText 'Paint 3D'); Description = (Get-TFToolkitText 'Desenho em 3D; aposentado pela Microsoft: não volta depois de removido. O Paint de sempre não é afetado'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.MixedReality.Portal"; Label = (Get-TFToolkitText 'Portal de Realidade Misturada'); Description = (Get-TFToolkitText 'Só para óculos de realidade virtual; aposentado pela Microsoft: não volta depois de removido'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.Microsoft3DViewer"; Label = (Get-TFToolkitText 'Visualizador 3D'); Description = (Get-TFToolkitText 'Abre modelos 3D; saiu da Microsoft Store: não volta depois de removido'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.Print3D"; Label = (Get-TFToolkitText 'Print 3D'); Description = (Get-TFToolkitText 'Impressão 3D; aposentado pela Microsoft: não volta depois de removido'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.SkypeApp"; Label = (Get-TFToolkitText 'Skype'); Description = (Get-TFToolkitText 'Aposentado pela Microsoft em 2025: não volta depois de removido'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.OneConnect"; Label = (Get-TFToolkitText 'Planos Móveis'); Description = (Get-TFToolkitText 'Contratação de planos de celular') },
        [PSCustomObject]@{ Pattern = "Microsoft.Wallet"; Label = (Get-TFToolkitText 'Microsoft Pay'); Description = (Get-TFToolkitText 'Carteira digital') },
        [PSCustomObject]@{ Pattern = "Microsoft.Copilot"; Label = (Get-TFToolkitText 'Copilot'); Description = (Get-TFToolkitText 'Assistente de IA da Microsoft') },
        [PSCustomObject]@{ Pattern = "Microsoft.OutlookForWindows"; Label = (Get-TFToolkitText 'Outlook (novo)'); Description = (Get-TFToolkitText 'O novo aplicativo de e-mail; o Outlook do Office não é afetado') },
        [PSCustomObject]@{ Pattern = "Microsoft.Windows.DevHome"; Label = (Get-TFToolkitText 'Dev Home'); Description = (Get-TFToolkitText 'Painel para desenvolvedores; aposentado pela Microsoft: não volta depois de removido'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.BingSearch"; Label = (Get-TFToolkitText 'Bing Pesquisa'); Description = (Get-TFToolkitText 'Aplicativo de busca do Bing; arquivos e aplicativos continuam sendo achados na pesquisa do Windows') },
        [PSCustomObject]@{ Pattern = "Microsoft.549981C3F5F10"; Label = (Get-TFToolkitText 'Cortana'); Description = (Get-TFToolkitText 'Assistente aposentado pela Microsoft: não volta depois de removido'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.WindowsCommunicationsApps"; Label = (Get-TFToolkitText 'Email e Calendário (antigo)'); Description = (Get-TFToolkitText 'Aposentado pela Microsoft, não volta depois de removido; e-mails guardados só neste PC são apagados'); Reinstallable = $false },
        [PSCustomObject]@{ Pattern = "Microsoft.PowerAutomateDesktop"; Label = (Get-TFToolkitText 'Power Automate'); Description = (Get-TFToolkitText 'Automação de tarefas; mantenha se você criou fluxos nele') },
        [PSCustomObject]@{ Pattern = "Microsoft.Todos"; Label = (Get-TFToolkitText 'Microsoft To Do'); Description = (Get-TFToolkitText 'Lista de tarefas; mantenha se você usa') },
        [PSCustomObject]@{ Pattern = "Microsoft.GamingApp"; Label = (Get-TFToolkitText 'Xbox'); Description = (Get-TFToolkitText 'Loja e Game Pass de jogos para PC; mantenha se você joga pelo Xbox ou pelo Game Pass') },
        [PSCustomObject]@{ Pattern = "Clipchamp.Clipchamp"; Label = (Get-TFToolkitText 'Clipchamp'); Description = (Get-TFToolkitText 'Editor de vídeo') },
        [PSCustomObject]@{ Pattern = "MicrosoftTeams"; Label = (Get-TFToolkitText 'Microsoft Teams (chat pessoal)'); Description = (Get-TFToolkitText 'Versão pessoal do Teams; o Teams de trabalho ou escola não é afetado') },
        [PSCustomObject]@{ Pattern = "MSTeams"; Label = (Get-TFToolkitText 'Microsoft Teams (novo)'); Description = (Get-TFToolkitText 'O Teams atual, pessoal e de trabalho ou escola; mantenha se você usa o Teams') },
        [PSCustomObject]@{ Pattern = "king.com.CandyCrush*"; Label = (Get-TFToolkitText 'Candy Crush'); Description = (Get-TFToolkitText 'Jogos instalados por promoção') },
        [PSCustomObject]@{ Pattern = "SpotifyAB.SpotifyMusic"; Label = (Get-TFToolkitText 'Spotify'); Description = (Get-TFToolkitText 'Aplicativo de música instalado por promoção') },
        [PSCustomObject]@{ Pattern = "4DF9E0F8.Netflix"; Label = (Get-TFToolkitText 'Netflix'); Description = (Get-TFToolkitText 'Aplicativo instalado por promoção') },
        [PSCustomObject]@{ Pattern = "Disney.*"; Label = (Get-TFToolkitText 'Disney+'); Description = (Get-TFToolkitText 'Aplicativo instalado por promoção') },
        [PSCustomObject]@{ Pattern = "BytedancePte.Ltd.TikTok"; Label = "TikTok"; Description = (Get-TFToolkitText 'Aplicativo instalado por promoção') },
        [PSCustomObject]@{ Pattern = "AmazonVideo.PrimeVideo"; Label = (Get-TFToolkitText 'Prime Video'); Description = (Get-TFToolkitText 'Aplicativo instalado por promoção') },
        [PSCustomObject]@{ Pattern = "Facebook.Facebook"; Label = (Get-TFToolkitText 'Facebook'); Description = (Get-TFToolkitText 'Aplicativo instalado por promoção') },
        [PSCustomObject]@{ Pattern = "Facebook.InstagramBeta"; Label = (Get-TFToolkitText 'Instagram'); Description = (Get-TFToolkitText 'Aplicativo instalado por promoção') },
        [PSCustomObject]@{ Pattern = "7EE7776C.LinkedInforWindows"; Label = "LinkedIn"; Description = (Get-TFToolkitText 'Aplicativo instalado por promoção') }
    )
}


function Test-TFToolkitAppProtected {
    <#
    Pacotes que nunca podem ser removidos, mesmo que um padrão do catálogo os alcance: componentes (framework), itens
    marcados pelo Windows como não removíveis e pacotes assinados como parte do sistema.
    #>
    param (
        [Parameter(Mandatory)]
        $Package
    )

    if ([bool](Get-TFToolkitJsonValue -Object $Package -Name "IsFramework" -Default $false)) { return $true }
    if ([bool](Get-TFToolkitJsonValue -Object $Package -Name "NonRemovable" -Default $false)) { return $true }
    if ([string](Get-TFToolkitJsonValue -Object $Package -Name "SignatureKind" -Default "") -eq "System") { return $true }

    $name = [string](Get-TFToolkitJsonValue -Object $Package -Name "Name" -Default "")

    return ($name -match '^(Microsoft\.(WindowsStore|StorePurchaseApp|DesktopAppInstaller|SecHealthUI|WindowsTerminal|WindowsCalculator|Windows\.Photos|WindowsNotepad|Paint|NET\.|VCLibs|UI\.Xaml|Services\.Store)|Windows\.|MicrosoftWindows\.)')
}


function Get-TFToolkitInstalledAppCatalog {
    <#
    Os aplicativos do catálogo que existem neste PC, para o usuário atual: Key (uma por item do catálogo), Label,
    Description e FullNames (um por arquitetura instalada). Pacotes protegidos nunca entram. Sem conseguir listar os
    pacotes, lança o erro: "nenhum instalado" seria um palpite.
    #>
    # Uma consulta só, filtrada aqui: perguntar ao Windows item por item levava uma consulta por aplicativo do catálogo.
    $installed = @(Get-AppxPackage -ErrorAction Stop | Where-Object { $null -ne $_ -and -not (Test-TFToolkitAppProtected -Package $_) })
    $taken = @{}
    $found = @()

    foreach ($entry in @(Get-TFToolkitAppCatalog)) {
        # Um pacote pertence a um item só (o primeiro que o alcança): remover um item nunca remove o pacote de outro.
        $packages = @($installed | Where-Object { [string]$_.Name -like $entry.Pattern -and -not $taken.ContainsKey([string]$_.PackageFullName) })

        if ($packages.Count -eq 0) { continue }

        foreach ($package in $packages) { $taken[[string]$package.PackageFullName] = $true }

        $found += [PSCustomObject]@{
            Key           = [string]$entry.Pattern
            Label         = $entry.Label
            Description   = $entry.Description
            Reinstallable = [bool](Get-TFToolkitJsonValue -Object $entry -Name "Reinstallable" -Default $true)
            FullNames     = @($packages | ForEach-Object { [string]$_.PackageFullName } | Select-Object -Unique)
        }
    }

    return @($found | Sort-Object -Property Label)
}


function Get-TFToolkitAppRemovalResult {
    <#
    O resultado de remover um aplicativo a partir do erro do Remove-AppxPackage. Os códigos conhecidos viram frase, com o
    código junto ("o aplicativo está aberto; feche-o e tente de novo — erro 0x80073D02"); os significados são os da tabela
    de erros de implantação de aplicativos da Microsoft. Um pacote que já não estava instalado conta como removido.
    #>
    param (
        [string]$Message,
        [int]$HResult = 0
    )

    $code = Get-TFToolkitErrorCode -Message $Message -HResult $HResult

    switch ($code) {
        "0x80073CF1" { return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'já não estava instalado')) }
        "0x80073D02" { return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o aplicativo está aberto; feche-o e tente de novo — erro {0}' "$code")) }
        "0x80073CFA" { return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o Windows não permitiu a remoção — erro {0}' "$code")) }
        "0x80070005" { return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'acesso negado — erro {0}' "$code")) }
    }

    if ($code) {
        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'a remoção falhou — erro {0}' "$code"))
    }

    $text = @(([string]$Message) -split "[\r\n]+" | Where-Object { $_.Trim() }) | Select-Object -First 1
    $text = $(if ($text) { ([string]$text).Trim().TrimEnd('.') } else { (Get-TFToolkitText 'a remoção falhou') })

    return (New-TFToolkitResult -Kind Failed -Detail $text)
}


function Get-TFToolkitCheckedAppResults {
    <#
    A conferência depois de remover: um aplicativo só conta como removido quando nenhum pacote dele (pelo nome do pacote,
    em qualquer arquitetura ou versão) aparece mais na lista do Windows para o usuário atual. Apps: os itens marcados
    (FullNames); Results: o resultado da remoção de cada um, na mesma ordem. Devolve o resultado final de cada um:
    - saiu: o resultado da remoção ("removido", "já não estava instalado"), ou Ok se a remoção relatou erro e ainda assim
      saiu;
    - continua: o erro da remoção, ou Failed "continua instalado" se a remoção não relatou erro;
    - a lista não pôde ser lida: Failed "não foi possível conferir se saiu" (nada é dado como removido sem ela).
    #>
    param (
        [Parameter(Mandatory)][object[]]$Apps,
        [Parameter(Mandatory)][object[]]$Results
    )

    # O nome do pacote é a parte do nome completo antes do primeiro "_" (Microsoft.BingWeather_4.53_x64__8wekyb3d8bbwe).
    $left = $null

    try {
        $left = @(Get-AppxPackage -ErrorAction Stop | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Name })
    }
    catch {
        $left = $null
    }

    $final = @()

    for ($i = 0; $i -lt @($Apps).Count; $i++) {
        $result = $Results[$i]
        $names = @(@($Apps[$i].FullNames) | ForEach-Object { ([string]$_).Split('_')[0] } | Select-Object -Unique)

        if ($null -eq $left) {
            if ($result.Kind -ne "Failed") { $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível conferir se saiu') }
        }
        elseif (@($left | Where-Object { $names -contains $_ }).Count -gt 0) {
            if ($result.Kind -ne "Failed") { $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'continua instalado') }
        }
        elseif ($result.Kind -eq "Failed") {
            $result = New-TFToolkitResult -Kind Ok
        }

        $result.Etapa = [string]$Apps[$i].Label
        $final += $result
    }

    return $final
}


# ---------------------------------------------------------------------------
# Ação
# ---------------------------------------------------------------------------

function Remove-TFToolkitPreinstalledApps {
    $title = (Get-TFToolkitText 'Remover aplicativos do Windows')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        # Elevado com outra conta, os aplicativos removidos seriam os dessa conta, não os da pessoa logada.
        if (Test-TFToolkitUserContextMismatch) {
            $interactiveUser = Get-TFToolkitInteractiveUser
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O TF-Toolkit está elevado com outra conta, não a de {0}. Abra-o sem trocar de conta.' "$interactiveUser")
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'o TF-Toolkit está elevado com outra conta') -Title $title)
            return
        }

        Write-Progress -Activity (Get-TFToolkitText 'Remover aplicativos do Windows') -Status (Get-TFToolkitText 'procurando os aplicativos da lista neste PC')

        try {
            $apps = @(Get-TFToolkitInstalledAppCatalog)
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Remover aplicativos do Windows') -Completed
        }

        if ($apps.Count -eq 0) {
            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Nenhum dos aplicativos da lista está instalado.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nenhum aplicativo da lista está instalado') -Title $title)
            return
        }

        # Nada vem marcado. A remoção vale para o usuário atual, e o aplicativo volta pela Microsoft Store, menos os que a
        # Microsoft aposentou (a descrição deles diz isso, e a confirmação repete).
        $options = @($apps | ForEach-Object { @{ Key = $_.Key; Label = $_.Label; Description = $_.Description } })
        $picked = Read-TFToolkitMultiSelect -Message (Get-TFToolkitText 'Quais aplicativos remover?') -Options $options -NoSelectAll -ConfirmLabel (Get-TFToolkitText 'Remover')

        if ($null -eq $picked -or @($picked).Count -eq 0) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $chosen = @($apps | Where-Object { @($picked) -contains $_.Key })
        $question = Get-TFToolkitSelectionQuestion -Verb (Get-TFToolkitText 'Remover') -Names @($chosen | ForEach-Object { [string]$_.Label }) -Many (Get-TFToolkitText 'aplicativos')
        $retired = @($chosen | Where-Object { -not $_.Reinstallable } | ForEach-Object { [string]$_.Label })

        # Os que a Microsoft aposentou não voltam pela Store: a confirmação repete o que a descrição deles já dizia.
        if ($retired.Count -gt 0) {
            Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText '{0} {1} pela Microsoft Store.' "$(Join-TFToolkitList -Items $retired)" "$(if ($retired.Count -eq 1) { (Get-TFToolkitText 'não volta') } else { (Get-TFToolkitText 'não voltam') })")
        }

        # Um aposentado removido não volta: o botão vem como o das ações que apagam sem volta.
        if (-not (Confirm-TFToolkitAction -Message $question -DefaultKey "N" -Danger:($retired.Count -gt 0) -YesLabel (Get-TFToolkitText 'Remover') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $results = @()
        $position = 0

        try {
            foreach ($app in $chosen) {
                $position++
                Write-Progress -Activity (Get-TFToolkitText 'Removendo aplicativos') -Status (Get-TFToolkitText '{0} de {1}: {2}' "$position" "$($chosen.Count)" "$($app.Label)") -PercentComplete ([int](($position - 1) * 100 / $chosen.Count))

                # Um aplicativo pode ter um pacote por arquitetura: a primeira falha decide, e "já não estava instalado" só
                # vale quando nenhum dos pacotes estava.
                $failure = $null
                $absent = 0

                foreach ($fullName in $app.FullNames) {
                    try {
                        Remove-AppxPackage -Package $fullName -ErrorAction Stop
                    }
                    catch {
                        $attempt = Get-TFToolkitAppRemovalResult -Message $_.Exception.Message -HResult $_.Exception.HResult

                        if ($attempt.Kind -eq "Ok") { $absent++ }
                        elseif ($null -eq $failure) { $failure = $attempt }
                    }
                }

                $result = $(if ($null -ne $failure) { $failure } elseif ($absent -eq @($app.FullNames).Count) { New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'já não estava instalado') } else { New-TFToolkitResult -Kind Ok })
                $result.Etapa = $app.Label
                $results += $result
            }

            # A conferência: um aplicativo só conta como removido quando sai da lista de pacotes do Windows
            # (Get-TFToolkitCheckedAppResults).
            Write-Progress -Activity (Get-TFToolkitText 'Removendo aplicativos') -Status (Get-TFToolkitText 'conferindo o que saiu')
            $results = @(Get-TFToolkitCheckedAppResults -Apps $chosen -Results $results)
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Removendo aplicativos') -Completed
        }

        foreach ($result in $results) {
            if ($result.Kind -eq "Ok") {
                Write-TFToolkitStatus -Type Success -Message "$($result.Etapa): $(if ($result.Detail) { $result.Detail } else { (Get-TFToolkitText 'removido') })."
            }
            else {
                Write-TFToolkitStatus -Type Error -Message "$($result.Etapa): $($result.Detail)."
            }
        }

        # No console, a tabela junta tudo no fim; na janela, cada aplicativo já tem a sua linha no resumo.
        if ($results.Count -gt 1 -and -not (Test-TFToolkitGuiMode)) {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')
            Write-TFToolkitResultTable -Results $results
        }

        $failed = @($results | Where-Object { $_.Kind -eq "Failed" })
        $names = Join-TFToolkitList -Items @($failed | ForEach-Object { [string]$_.Etapa })
        $removed = @($results | Where-Object { $_.Kind -ne "Failed" } | ForEach-Object { [string]$_.Etapa })
        $back = @($chosen | Where-Object { $removed -contains [string]$_.Label -and $_.Reinstallable } | ForEach-Object { [string]$_.Label })
        $gone = @($chosen | Where-Object { $removed -contains [string]$_.Label -and -not $_.Reinstallable } | ForEach-Object { [string]$_.Label })

        if ($removed.Count -gt 0) {
            # O Histórico não promete a volta pela Store de um aplicativo que a Microsoft aposentou.
            # "1 aplicativo removido: Dicas", e não "Dicas removido": o nome do aplicativo pode ser feminino ou plural.
            $parts = @()
            if ($back.Count -gt 0) {
                $parts += $(if ($back.Count -eq 1) { (Get-TFToolkitText '1 aplicativo removido: {0} (volta pela Microsoft Store)' "$(Join-TFToolkitList -Items $back)") } else { (Get-TFToolkitText '{0} aplicativos removidos: {1} (voltam pela Microsoft Store)' "$($back.Count)" "$(Join-TFToolkitList -Items $back)") })
            }
            if ($gone.Count -gt 0) {
                $parts += $(if ($gone.Count -eq 1) { (Get-TFToolkitText '1 aplicativo removido: {0} (aposentado pela Microsoft, não volta)' "$(Join-TFToolkitList -Items $gone)") } else { (Get-TFToolkitText '{0} aplicativos removidos: {1} (aposentados pela Microsoft, não voltam)' "$($gone.Count)" "$(Join-TFToolkitList -Items $gone)") })
            }
            [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Aplicativos do Windows') -Text ($parts -join "; "))
            # A marca de "já instalado" das telas de instalar é lida de novo.
            Clear-TFToolkitInstalledWingetIdsCache
        }

        if ($failed.Count -eq 0) {
            $detail = $(if ($results.Count -eq 1) { (Get-TFToolkitText '1 aplicativo removido: {0}' "$($results[0].Etapa)") } else { (Get-TFToolkitText '{0} aplicativos removidos' "$($results.Count)") })
            $final = New-TFToolkitResult -Kind Ok -Detail $detail -Title $title

            # Na janela, o título diz quantos; a frase, quais e se voltam pela Microsoft Store.
            $storeNote = $(
                if ($gone.Count -eq 0) { $(if ($back.Count -eq 1) { (Get-TFToolkitText 'Volta pela Microsoft Store, se precisar.') } else { (Get-TFToolkitText 'Voltam pela Microsoft Store, se precisar.') }) }
                elseif ($back.Count -eq 0) { $(if ($gone.Count -eq 1) { (Get-TFToolkitText 'Não volta pela Microsoft Store: a Microsoft aposentou esse aplicativo.') } else { (Get-TFToolkitText 'Não voltam pela Microsoft Store: a Microsoft aposentou esses aplicativos.') }) }
                else { $(if ($back.Count -eq 1) { (Get-TFToolkitText 'Só {0} volta pela Microsoft Store.' "$(Join-TFToolkitShortList -Items $back)") } else { (Get-TFToolkitText 'Só {0} voltam pela Microsoft Store.' "$(Join-TFToolkitShortList -Items $back)") }) }
            )
            [void](Set-TFToolkitResultView -Result $final -Headline (Format-TFToolkitCount -Count $removed.Count -One (Get-TFToolkitText 'aplicativo removido') -Many (Get-TFToolkitText 'aplicativos removidos')) `
                    -Note "$(Join-TFToolkitShortList -Items $removed). $storeNote")
        }
        elseif ($failed.Count -eq $results.Count) {
            $detail = $(if ($results.Count -eq 1) { (Get-TFToolkitText 'não foi possível remover {0}: {1}' "$($names)" "$($failed[0].Detail)") } else { (Get-TFToolkitText 'nenhum aplicativo foi removido: {0}' "$names") })
            $final = New-TFToolkitResult -Kind Failed -Detail $detail -Title $title

            # Na janela, o título diz que nada saiu; a frase, o motivo (de um só) ou onde estão os motivos.
            [void](Set-TFToolkitResultView -Result $final -Headline $(if ($results.Count -eq 1) { (Get-TFToolkitText 'O aplicativo não foi removido') } else { (Get-TFToolkitText 'Nenhum aplicativo foi removido') }) `
                    -Note $(if ($results.Count -eq 1) { "$($failed[0].Etapa): $(([string]$failed[0].Detail).TrimEnd('.'))." } else { (Get-TFToolkitText 'O motivo de cada um está no resumo.') }))
        }
        else {
            $verbText = $(if ($failed.Count -eq 1) { (Get-TFToolkitText 'não foi removido') } else { (Get-TFToolkitText 'não foram removidos') })
            $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0} de {1} {2}: {3}' "$($failed.Count)" "$($results.Count)" "${verbText}" "$names") -Title $title
            $reason = $(if ($failed.Count -eq 1) { (Get-TFToolkitText 'o motivo está no resumo') } else { (Get-TFToolkitText 'o motivo de cada um está no resumo') })
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText '{0} de {1} aplicativos removidos' "$($removed.Count)" "$($results.Count)") `
                    -Note "$(Join-TFToolkitShortList -Items @($failed | ForEach-Object { [string]$_.Etapa })) ${verbText}; $reason.")
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível remover os aplicativos: {0}' "$($_.Exception.Message)")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
