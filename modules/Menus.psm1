# Menus do console, montados a partir da tabela de Navigation.psm1.
# A janela gráfica não usa este módulo: ela desenha a barra lateral e os cartões com a mesma tabela.


function Read-TFToolkitMenuKey {
    # Lê a opção de um menu. Devolve $null quando a entrada acaba (por exemplo, entrada redirecionada encerrada),
    # para que o menu saia em vez de repetir a pergunta para sempre.
    # -Hint: a linha de ajuda logo acima do pedido ("Digite o número e tecle Enter. 0 volta.").
    param (
        [Parameter(Mandatory)]
        [object[]]$Options,

        [switch]$ShowMenu,

        [string]$Hint = (Get-TFToolkitText 'Digite o número e tecle Enter. 0 volta.')
    )

    try {
        return (Read-TFToolkitChoice -Message $Hint -Options $Options -ShowMenu:$ShowMenu)
    }
    catch {
        return $null
    }
}


function Invoke-TFToolkitNavItem {
    # Executa um item da navegação no console. Erros inesperados viram uma mensagem; o menu continua.
    param (
        [Parameter(Mandatory)]
        $Item
    )

    try {
        if ($Item.Kind -eq "Shortcut") {
            Show-TFToolkitHeader $Item.Label
            [void](Open-TFToolkitShortcut -Name $Item.Shortcut)
            Wait-TFToolkitKey
        }
        else {
            # O desfecho que o fim da ação mostra é só o desta ação (Exit-TFToolkitAction).
            Reset-TFToolkitOutcome
            & $Item.Command
        }
    }
    catch {
        Write-Host ""
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro em ''{0}'': {1}' "$($Item.Label)" "$($_.Exception.Message)")
        Wait-TFToolkitKey
    }
}


function Show-TFToolkitPageMenu {
    param (
        [Parameter(Mandatory)]
        $Page
    )

    while ($true) {
        Show-TFToolkitHeader $Page.Title
        Write-TFToolkitWrappedLine -Text $Page.Summary -Color DarkGray
        Write-Host ""

        $options = @()
        $position = 0
        $group = $null

        # As seções da página ("Liberar espaço", "Ferramentas do Windows") separam os itens, como na janela; a numeração
        # segue direto de uma seção para a outra.
        foreach ($item in $Page.Items) {
            $position++

            if ([string]$item.Group -and [string]$item.Group -ne $group) {
                if ($null -ne $group) { Write-Host "" }
                Write-Host "  $($item.Group)" -ForegroundColor DarkCyan
                $group = [string]$item.Group
            }

            Write-TFToolkitMenuItem -Key ([string]$position) -Label $item.Label -Description $item.Description -Accent:$item.Accent -Recommended:$item.Accent
            $options += @{ Key = [string]$position; Label = $item.Label; Description = $item.Description; Accent = $item.Accent }
        }

        Write-Host ""
        Write-TFToolkitMenuItem -Key "0" -Label (Get-TFToolkitText 'Voltar') -Exit
        Write-Host ""

        $options += @{ Key = "0"; Label = (Get-TFToolkitText 'Voltar'); Exit = $true }

        $choice = Read-TFToolkitMenuKey -Options $options

        if ($null -eq $choice -or $choice -eq "0") {
            return
        }

        Invoke-TFToolkitNavItem -Item $Page.Items[[int]$choice - 1]

        # A atualização com um clique: o instalador espera este menu fechar para trocar os arquivos.
        if (Get-TFToolkitAppExitRequest) { return }
    }
}


function Get-TFToolkitTweaksMenuLetters {
    # A tecla de cada ação de uma página de ajustes (Ajustes do Windows ou Personalização), na ordem da tabela de navegação.
    param ([string]$PageId = "tweaks")

    $keys = @{
        "tweaks.recommended" = "A"; "tweaks.profiles" = "P"; "tweaks.keyboard-language" = "T"; "tweaks.notifications" = "N"
        "tweaks.restore-point" = "R"; "tweaks.export" = "E"; "tweaks.import" = "I"; "tweaks.revert-all" = "D"
        "personalize.accent-color" = "C"; "personalize.lock-screen" = "B"; "personalize.settings" = "P"
    }

    $page = Get-TFToolkitNavPage -Id $PageId
    $letters = [ordered]@{}

    foreach ($item in @($page.Items)) {
        if ($keys.ContainsKey([string]$item.Id)) { $letters[[string]$item.Id] = $keys[[string]$item.Id] }
    }

    return $letters
}


function Show-TFToolkitTweaksMenu {
    # Os ajustes são numerados; as ações da página (nomes vindos da tabela de navegação) têm uma letra como tecla.
    # Cada item mostra o recurso do Windows como a chave da janela: ativado ou desativado, lido do Windows agora.
    param ([string]$PageId = "tweaks")

    $page = Get-TFToolkitNavPage -Id $PageId
    $letters = Get-TFToolkitTweaksMenuLetters -PageId $PageId

    while ($true) {
        Show-TFToolkitHeader $page.Title
        Write-TFToolkitWrappedLine -Text $page.Summary -Color DarkGray
        Write-TFToolkitWrappedLine -Text (Get-TFToolkitText 'Cada item mostra como o Windows está agora: ativado ou desativado (? = não identificado).') -Color DarkGray

        $overview = @(Get-TFToolkitTweakOverview -Page $PageId)
        $options = @()
        $lastCategory = ""
        $position = 0

        # Elevado com outra conta, os do perfil do usuário mostrariam o perfil dessa conta: ficam com um traço, e a linha diz
        # por quê (a página da janela diz o mesmo no alto).
        if (@($overview | Where-Object { [bool](Get-TFToolkitJsonValue -Object $_ -Name "OtherAccount" -Default $false) }).Count -gt 0) {
            Write-TFToolkitWrappedLine -Text (Get-TFToolkitText 'O TF-Toolkit está elevado com outra conta: os ajustes do perfil do usuário (com -) ficam de fora.') -Color Yellow
        }

        foreach ($tweak in $overview) {
            if ($tweak.Category -ne $lastCategory) {
                Write-TFToolkitSection -Title $tweak.Category
                $lastCategory = $tweak.Category
            }

            $position++
            $options += @{ Key = [string]$position; Label = $tweak.Name }

            $state = Get-TFToolkitTweakSwitchState -Status $tweak.Status -Inverted ([bool]$tweak.Inverted)

            if ([bool](Get-TFToolkitJsonValue -Object $tweak -Name "OtherAccount" -Default $false)) {
                $badge = "[    -     ]"
                $badgeColor = "DarkGray"
            }
            elseif ($tweak.Status -eq "Desconhecido") {
                $badge = "[    ?     ]"
                $badgeColor = "Yellow"
            }
            elseif ($state.IsOn) {
                $badge = (Get-TFToolkitText '[ativado   ]')
                $badgeColor = "White"
            }
            else {
                $badge = (Get-TFToolkitText '[desativado]')
                $badgeColor = "DarkGray"
            }

            Write-Host "  [" -ForegroundColor DarkGray -NoNewline
            Write-Host ([string]$position).PadLeft(2) -ForegroundColor Cyan -NoNewline
            Write-Host "] " -ForegroundColor DarkGray -NoNewline
            Write-Host "$badge " -ForegroundColor $badgeColor -NoNewline
            Write-Host $tweak.Name -ForegroundColor Gray -NoNewline

            if (-not [string]::IsNullOrWhiteSpace($tweak.LaptopNote)) {
                Write-Host (Get-TFToolkitText '  (aviso para notebook ao escolher)') -ForegroundColor Yellow -NoNewline
            }

            Write-Host ""
        }

        Write-Host ""
        foreach ($id in $letters.Keys) {
            $item = $page.Items | Where-Object { $_.Id -eq $id } | Select-Object -First 1
            Write-TFToolkitMenuItem -Key $letters[$id] -Label $item.Label -Description $item.Description -Accent:$item.Accent
            $options += @{ Key = $letters[$id]; Label = $item.Label }
        }

        Write-Host ""
        Write-TFToolkitMenuItem -Key "0" -Label (Get-TFToolkitText 'Voltar') -Exit
        Write-Host ""

        $options += @{ Key = "0"; Label = (Get-TFToolkitText 'Voltar'); Exit = $true }

        $choice = Read-TFToolkitMenuKey -Options $options -Hint (Get-TFToolkitText 'Digite o número de um item para ativar ou desativar, ou a letra de uma ação, e tecle Enter. 0 volta.')

        if ($null -eq $choice -or $choice -eq "0") {
            return
        }

        try {
            $letterId = @($letters.Keys | Where-Object { $letters[$_] -eq $choice.ToUpperInvariant() }) | Select-Object -First 1

            if ($null -ne $letterId) {
                Invoke-TFToolkitNavItem -Item ($page.Items | Where-Object { $_.Id -eq $letterId } | Select-Object -First 1)
            }
            else {
                Reset-TFToolkitOutcome
                Invoke-TFToolkitTweakToggle -Tweak (Get-TFToolkitTweakById -Id $overview[[int]$choice - 1].Id)
            }
        }
        catch {
            Write-Host ""
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro: {0}' "$($_.Exception.Message)")
            Wait-TFToolkitKey
        }
    }
}


function Show-TFToolkitMainMenu {
    while ($true) {
        Show-TFToolkitHeader "TF-Toolkit"

        $pages = @(Get-TFToolkitNavigation)
        $options = @()
        $position = 0
        $footer = $false

        foreach ($page in $pages) {
            $position++

            # A página do rodapé da barra lateral (Sobre o TF-Toolkit) fica separada das outras, como na janela.
            if ([string]$page.Placement -eq "Footer" -and -not $footer) {
                Write-Host ""
                $footer = $true
            }

            Write-TFToolkitMenuItem -Key ([string]$position) -Label $page.Title -Description $page.Summary -Accent:($position -eq 1) -Recommended:($position -eq 1)
            $options += @{ Key = [string]$position; Label = $page.Title; Description = $page.Summary; Accent = ($position -eq 1) }
        }

        Write-Host ""
        Write-TFToolkitMenuItem -Key "0" -Label (Get-TFToolkitText 'Sair') -Exit
        Write-Host ""

        $options += @{ Key = "0"; Label = (Get-TFToolkitText 'Sair'); Exit = $true }

        $choice = Read-TFToolkitMenuKey -Options $options -Hint (Get-TFToolkitText 'Digite o número e tecle Enter. 0 sai do TF-Toolkit.')

        if ($null -eq $choice -or $choice -eq "0") {
            Write-Host ""
            Write-Host (Get-TFToolkitText '  Saindo do TF-Toolkit...') -ForegroundColor Yellow
            return
        }

        $page = $pages[[int]$choice - 1]

        if ($page.Kind -eq "Tweaks") {
            Show-TFToolkitTweaksMenu -PageId $page.Id
        }
        else {
            Show-TFToolkitPageMenu -Page $page
        }

        if (Get-TFToolkitAppExitRequest) {
            Write-Host ""
            Write-Host (Get-TFToolkitText '  Fechando para instalar a versão nova; o TF-Toolkit abre de novo em alguns segundos...') -ForegroundColor Yellow
            # Um instante para a frase ser lida antes de a janela fechar.
            Start-Sleep -Seconds 2
            return
        }
    }
}


Export-ModuleMember -Function *
