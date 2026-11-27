# Drivers: procurar e instalar pelo Windows Update, aqui mesmo, e indicar a ferramenta oficial do fabricante.
#
# O Windows Update é a fonte mais segura de drivers: os fabricantes publicam ali os drivers testados para o Windows. Os
# recomendados vêm marcados; os opcionais (que o Windows só mostra na página de atualizações opcionais) vêm desmarcados,
# porque só valem a pena quando algum dispositivo está com problema. Placa de vídeo e BIOS costumam ter versões mais
# novas nas ferramentas dos próprios fabricantes; a segunda tela indica qual usar, pelo fabricante do PC e da placa.


function Get-TFToolkitDriverSearchCriteria {
    return "IsInstalled=0 and IsHidden=0 and Type='Driver'"
}


function Get-TFToolkitDriverRunDetail {
    # "3 drivers instalados", "2 drivers instalados (1 com erros)", "2 de 3 instalados; 1 falhou", "nenhum dos 2 drivers
    # foi instalado". Ok = instalados sem problema, Warned = instalados com erros (código 3 do Windows Update), Failed = não
    # instalados.
    param (
        [int]$Ok,
        [int]$Failed,
        [int]$Warned = 0
    )

    $installed = $Ok + $Warned
    $total = $installed + $Failed

    if ($installed -eq 0) {
        if ($total -eq 1) { return (Get-TFToolkitText 'o driver não foi instalado') }
        return (Get-TFToolkitText 'nenhum dos {0} drivers foi instalado' "$total")
    }

    if ($Failed -eq 0) {
        $text = Format-TFToolkitCount -Count $installed -One (Get-TFToolkitText 'driver instalado') -Many (Get-TFToolkitText 'drivers instalados')
    }
    else {
        $text = $(if ($installed -eq 1) { (Get-TFToolkitText '1 de {0} instalado' "$total") } else { (Get-TFToolkitText '{0} de {1} instalados' "$installed" "$total") })
    }

    if ($Warned -gt 0) { $text += (Get-TFToolkitText ' ({0} com erros)' "$Warned") }
    if ($Failed -gt 0) { $text += "; $(if ($Failed -eq 1) { (Get-TFToolkitText '1 falhou') } else { (Get-TFToolkitText '{0} falharam' "$Failed") })" }

    return $text
}


function Install-TFToolkitDriverUpdates {
    $title = (Get-TFToolkitText 'Atualizar drivers')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Atualizar drivers exige privilégios de Administrador.'))) {
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador') -Title $title)
            return
        }

        # As mesmas conferências de Instalar atualizações do Windows: um driver também vem do Windows Update (e a pausa vale
        # para eles), e um de firmware (BIOS) interrompido por falta de bateria pode deixar o PC sem ligar.
        $stop = Confirm-TFToolkitUpdateConditions -Title $title -Reboot (Get-TFToolkitText 'Reiniciar antes evita que os drivers novos falhem.') -Battery (Get-TFToolkitText 'Instalar drivers, principalmente de firmware (BIOS), não deve ser interrompido.') -Retry (Get-TFToolkitText 'Atualizações > Atualizar drivers')

        if ($null -ne $stop) {
            Exit-TFToolkitAction -Result $stop
            return
        }

        Write-Progress -Activity (Get-TFToolkitText 'Procurando drivers') -Status (Get-TFToolkitText 'o Windows Update pode levar alguns minutos para responder')

        try {
            $search = Find-TFToolkitWindowsUpdates -Criteria (Get-TFToolkitDriverSearchCriteria)
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Procurando drivers') -Completed
        }

        if ($null -eq $search.Updates) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível consultar o Windows Update: {0}.' "$($search.Problem)")
            Write-TFToolkitWindowsUpdateSearchHelp -Problem $search.Problem
            Exit-TFToolkitAction -Result (Set-TFToolkitUpdateSearchView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível consultar o Windows Update: {0}' "$($search.Problem)") -Title $title) -Problem $search.Problem)
            return
        }

        $drivers = @($search.Updates)

        if ($drivers.Count -eq 0) {
            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O Windows Update não tem drivers novos para este PC.')
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Placa de vídeo e BIOS podem ter versões mais novas no programa do fabricante: veja Atualizações > Ferramentas do fabricante.')
            Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'nenhum driver novo') -Title $title) -Headline (Get-TFToolkitText 'Nenhum driver novo') `
                    -Note (Get-TFToolkitText 'Placa de vídeo e BIOS podem ter versões mais novas no programa do fabricante.') -Next "updates.vendor-tools" -NextLabel (Get-TFToolkitText 'Ver as ferramentas do fabricante'))
            return
        }

        $recommended = @($drivers | Where-Object { -not $_.BrowseOnly })
        $optional = @($drivers | Where-Object { $_.BrowseOnly })

        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Recomendados') -Value $recommended.Count
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Opcionais') -Value $optional.Count
        Write-Host ""

        if ($optional.Count -gt 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Os opcionais vêm desmarcados: instale um deles só se o dispositivo estiver com problema.')
        }

        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Se um driver novo der problema, volte ao anterior em Diagnóstico > Gerenciador de Dispositivos (no aparelho: Propriedades, Driver, Reverter driver).')
        Write-Host ""

        # O título do Windows Update ("Intel - System - 10.1.1.44") se repete para aparelhos diferentes: a descrição diz
        # para que serve cada um ("vídeo: Intel(R) UHD Graphics 620").
        $options = @(
            foreach ($driver in @($recommended + $optional)) {
                $parts = @($(if ($driver.BrowseOnly) { (Get-TFToolkitText 'opcional') } else { (Get-TFToolkitText 'recomendado') }))
                $purpose = Get-TFToolkitDriverPurposeText -Update $driver
                if ($purpose) { $parts += $purpose }
                $parts += Get-TFToolkitUpdateSizeText -Update $driver
                @{ Key = $driver.Id; Label = [string]$driver.Title; Description = ($parts -join " · "); Selected = (-not $driver.BrowseOnly) }
            }
        )

        $picked = Read-TFToolkitMultiSelect -Message (Get-TFToolkitText 'Quais drivers instalar?') -Options $options

        if ($null -eq $picked -or @($picked).Count -eq 0) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $chosen = @($drivers | Where-Object { @($picked) -contains $_.Id })
        $question = Get-TFToolkitSelectionQuestion -Verb (Get-TFToolkitText 'Instalar') -Names @($chosen | ForEach-Object { [string]$_.Title }) -Many (Get-TFToolkitText 'drivers') -Limit 1

        Write-TFToolkitFirmwareWarning -Updates $chosen

        $pendingBytes = [int64]0
        foreach ($driver in @($chosen | Where-Object { -not $_.Downloaded })) { $pendingBytes += [int64]$driver.Size }
        if (@($chosen | Where-Object { -not $_.Downloaded }).Count -gt 0) { Write-TFToolkitMeteredWarning -Bytes $pendingBytes }

        # Com um firmware (BIOS) na escolha, o padrão é Não: um Enter a mais não manda gravar a BIOS.
        $hasFirmware = (@($chosen | Where-Object { Test-TFToolkitFirmwareUpdate -Update $_ }).Count -gt 0)

        if (-not (Confirm-TFToolkitAction -Message $question -DefaultKey $(if ($hasFirmware) { "N" } else { "S" }) -YesLabel (Get-TFToolkitText 'Instalar') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        # Um ponto de restauração antes, quando o Windows deixa (ele limita a um por dia): é a volta mais simples se um
        # driver deixar o PC instável.
        Write-Progress -Activity $title -Status (Get-TFToolkitText 'criando um ponto de restauração')

        # Um erro inesperado ao criar o ponto (o serviço de cópias de sombra, por exemplo) não impede os drivers: a tela diz
        # que segue sem ponto novo, como quando o Windows não o cria.
        try {
            $point = New-TFToolkitRestorePoint -Description (Get-TFToolkitText 'TF-Toolkit - antes dos drivers')
        }
        catch {
            $point = $null
        }
        finally {
            Write-Progress -Activity $title -Completed
        }

        if ($null -eq $point -or [string]$point.Kind -notin @("Ok", "Skipped")) { Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Seguindo sem ponto de restauração novo.') }

        $keepAwake = Set-TFToolkitKeepAwake -Enabled $true

        try {
            $run = Invoke-TFToolkitUpdateInstall -Ids @($chosen | ForEach-Object { $_.Id }) -Criteria (Get-TFToolkitDriverSearchCriteria)
        }
        finally {
            if ($keepAwake) { [void](Set-TFToolkitKeepAwake -Enabled $false) }
        }

        Write-Host ""

        # O mesmo desfecho das atualizações (Get-TFToolkitUpdateRunResult): a tabela, o Histórico de mudanças e a faixa.
        $final = Get-TFToolkitUpdateRunResult -Run $run -Chosen $chosen -Title $title -Drivers
        [void](Set-TFToolkitInstallView -Result $final -One (Get-TFToolkitText 'driver instalado') -Many (Get-TFToolkitText 'drivers instalados') -Each (Get-TFToolkitText 'cada um') -Partial (Get-TFToolkitText '{0} de {1} drivers instalados') `
                -None $(if ($chosen.Count -eq 1) { (Get-TFToolkitText 'O driver não foi instalado') } else { (Get-TFToolkitText 'Nenhum driver instalado') }) `
                -OkNote (Get-TFToolkitText 'Se algum der problema, volte ao driver anterior no Gerenciador de Dispositivos.'))

        [void](Set-TFToolkitInstallErrorView -Result $final)

        if (Test-TFToolkitResultFlag -Result $final -Name "RebootRequired") {
            Request-TFToolkitInstallRestart -What (Get-TFToolkitText 'os drivers') -Later (Get-TFToolkitText 'Os drivers terminam de instalar quando você reiniciar o PC.')
        }
    }
    catch {
        # A mesma tradução dos erros do Windows Update (sem o embrulho do PowerShell, com o código).
        $problem = Get-TFToolkitWindowsUpdateProblem -Message $_.Exception.Message -HResult $_.Exception.HResult
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível atualizar os drivers: {0}.' "$problem")
        $final = New-TFToolkitResult -Kind Failed -Detail $problem -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


# ---------------------------------------------------------------------------
# Ferramentas dos fabricantes
# ---------------------------------------------------------------------------

function Get-TFToolkitVendorToolCatalog {
    <#
    As ferramentas oficiais. WingetId = instalável pelo winget; Url = página oficial (abre no navegador) ou, com
    Store, a página do aplicativo na Microsoft Store; Open = o rótulo do botão quando não há winget; Target = o que abre,
    para a frase "Abrindo {0} no navegador". Cada fabricante tem uma ferramenta para a linha de PCs de empresa e outra
    para a de uso pessoal: a da linha errada diz que o PC não é compatível. A página da HP escolhe o país e o idioma
    sozinha; a do NVIDIA App vai no idioma da tela.
    #>
    $nvidia = switch (Get-TFToolkitLanguage) { "pt" { "pt-br" } "es" { "es-la" } default { "en-us" } }

    return @(
        [PSCustomObject]@{ Id = "dell"; Name = "Dell Command | Update"; For = (Get-TFToolkitText 'PCs Dell Pro, Latitude, OptiPlex, Precision, Vostro e XPS'); WingetId = "Dell.CommandUpdate"; Url = ""; Open = ""; Target = ""; Store = $false },
        [PSCustomObject]@{ Id = "dell-supportassist"; Name = (Get-TFToolkitText 'Dell SupportAssist'); For = (Get-TFToolkitText 'PCs Dell Inspiron, Alienware e G'); WingetId = ""; Url = "https://www.dell.com/support/kbdoc/000130387"; Open = (Get-TFToolkitText 'Abrir a página do Dell SupportAssist'); Target = (Get-TFToolkitText 'a página do Dell SupportAssist'); Store = $false },
        [PSCustomObject]@{ Id = "lenovo"; Name = "Lenovo System Update"; For = (Get-TFToolkitText 'PCs Lenovo ThinkPad, ThinkCentre e ThinkStation'); WingetId = "Lenovo.SystemUpdate"; Url = ""; Open = ""; Target = ""; Store = $false },
        [PSCustomObject]@{ Id = "lenovo-vantage"; Name = "Lenovo Vantage"; For = (Get-TFToolkitText 'PCs Lenovo IdeaPad, Yoga, Legion, ThinkBook e outros'); WingetId = ""; Url = "ms-windows-store://pdp/?ProductId=9WZDNCRFJ4MV"; Open = (Get-TFToolkitText 'Abrir o Lenovo Vantage na Microsoft Store'); Target = ""; Store = $true },
        [PSCustomObject]@{ Id = "hp"; Name = (Get-TFToolkitText 'Site de drivers da HP'); For = (Get-TFToolkitText 'PCs HP'); WingetId = ""; Url = "https://support.hp.com/drivers"; Open = (Get-TFToolkitText 'Abrir o site de drivers da HP'); Target = (Get-TFToolkitText 'o site de drivers da HP'); Store = $false },
        [PSCustomObject]@{ Id = "intel"; Name = "Intel Driver & Support Assistant"; For = (Get-TFToolkitText 'processador e vídeo Intel'); WingetId = "Intel.IntelDriverAndSupportAssistant"; Url = ""; Open = ""; Target = ""; Store = $false },
        [PSCustomObject]@{ Id = "nvidia"; Name = (Get-TFToolkitText 'NVIDIA App'); For = (Get-TFToolkitText 'placas de vídeo NVIDIA'); WingetId = ""; Url = "https://www.nvidia.com/$nvidia/software/nvidia-app/"; Open = (Get-TFToolkitText 'Abrir a página do NVIDIA App'); Target = (Get-TFToolkitText 'a página do NVIDIA App'); Store = $false },
        [PSCustomObject]@{ Id = "amd"; Name = (Get-TFToolkitText 'AMD Adrenalin (detecção automática)'); For = (Get-TFToolkitText 'processador e vídeo AMD'); WingetId = ""; Url = "https://www.amd.com/en/support/download/drivers.html"; Open = (Get-TFToolkitText 'Abrir a página de drivers da AMD'); Target = (Get-TFToolkitText 'a página de drivers da AMD'); Store = $false }
    )
}


function Test-TFToolkitVendorText {
    # Se um texto de fabricante ou modelo diz alguma coisa: placas genéricas vêm com "To Be Filled By O.E.M." e afins.
    param ([string]$Text)

    $value = ([string]$Text).Trim()

    return ($value -and $value -notmatch '(?i)to be filled|default string|system product name|system manufacturer|not applicable|all series|^(none|x|0+|oem|notebook|laptop|desktop|pc)$')
}


function Get-TFToolkitHardwareVendors {
    <#
    Fabricante, modelo e família do PC (a Lenovo põe o tipo de máquina, "21AH", no modelo, e o nome, "ThinkPad T14 Gen 3",
    na família), nomes das placas de vídeo e fabricante do processador. Campos vazios quando não lidos. SystemRead e
    GpuRead dizem se o Windows respondeu: "não consegui ler" não é o mesmo que "fabricante desconhecido".
    #>
    $system = $null
    $cpu = $null
    $gpus = @()
    $systemRead = $true
    $gpuRead = $true

    try { $system = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop } catch { $system = $null; $systemRead = $false }
    try { $cpu = @(Get-CimInstance -ClassName Win32_Processor -OperationTimeoutSec 15 -ErrorAction Stop) | Select-Object -First 1 } catch { $cpu = $null }
    try { $gpus = @(Get-CimInstance -ClassName Win32_VideoController -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object { [string]$_.Name } | Where-Object { $_ }) } catch { $gpus = @(); $gpuRead = $false }

    return [PSCustomObject]@{
        Manufacturer = ([string](Get-TFToolkitJsonValue -Object $system -Name "Manufacturer" -Default "")).Trim()
        Model        = ([string](Get-TFToolkitJsonValue -Object $system -Name "Model" -Default "")).Trim()
        Family       = ([string](Get-TFToolkitJsonValue -Object $system -Name "SystemFamily" -Default "")).Trim()
        Gpus         = @($gpus)
        CpuVendor    = ([string](Get-TFToolkitJsonValue -Object $cpu -Name "Manufacturer" -Default "")).Trim()
        SystemRead   = $systemRead
        GpuRead      = $gpuRead
    }
}


function Get-TFToolkitHardwareModelText {
    <#
    O modelo como a pessoa o conhece. Só a Lenovo põe no modelo um código de tipo de máquina ("21AH0026US"), com o nome
    na família: aí sai "ThinkPad T14 Gen 3 (21AH0026US)". Os outros fabricantes usam a família para códigos internos
    ("103C_5336AN HP ProBook"), e o modelo basta. Vazio sem nada.
    #>
    param ([Parameter(Mandatory)]$Hardware)

    $maker = [string](Get-TFToolkitJsonValue -Object $Hardware -Name "Manufacturer" -Default "")
    $model = [string](Get-TFToolkitJsonValue -Object $Hardware -Name "Model" -Default "")
    $family = [string](Get-TFToolkitJsonValue -Object $Hardware -Name "Family" -Default "")

    if (-not (Test-TFToolkitVendorText -Text $model)) { $model = "" }
    if (-not (Test-TFToolkitVendorText -Text $family)) { $family = "" }

    if ($maker -match '(?i)lenovo' -and $family -and $model -match '^[0-9A-Z]{4}([0-9A-Z]{4,6})?$' -and $model -match '[0-9]') {
        return "$family ($model)"
    }

    return $(if ($model) { $model } else { $family })
}


function Get-TFToolkitVendorTools {
    # As ferramentas que servem a este PC, na ordem: a do fabricante do PC (a da linha certa), depois as das placas de
    # vídeo e do processador.
    param ([Parameter(Mandatory)]$Hardware)

    $catalog = Get-TFToolkitVendorToolCatalog
    $ids = New-Object System.Collections.ArrayList
    $maker = [string]$Hardware.Manufacturer
    $line = "$([string](Get-TFToolkitJsonValue -Object $Hardware -Name 'Model' -Default '')) $([string](Get-TFToolkitJsonValue -Object $Hardware -Name 'Family' -Default ''))"

    if ($maker -match '(?i)\bdell\b|alienware') {
        # Dell Command | Update só atende a linha empresarial (Dell Pro e Pro Max, que sucedem Latitude e Precision, e o
        # XPS); Inspiron, Alienware e G usam o SupportAssist.
        [void]$ids.Add($(if ($line -match '(?i)latitude|optiplex|precision|vostro|rugged|\bxps\b|\bdell pro\b|^\s*pro( max)?\b') { "dell" } else { "dell-supportassist" }))
    }
    elseif ($maker -match '(?i)lenovo') {
        # O Lenovo System Update só atende ThinkPad, ThinkCentre e ThinkStation (não o ThinkBook); o Lenovo Vantage atende
        # as outras linhas.
        [void]$ids.Add($(if ($line -match '(?i)\bthink(pad|centre|station)\b') { "lenovo" } else { "lenovo-vantage" }))
    }
    elseif ($maker -match '(?i)\bhp\b|hewlett') { [void]$ids.Add("hp") }

    $gpuText = (@($Hardware.Gpus) -join " | ")

    if ($gpuText -match '(?i)nvidia|geforce|quadro|rtx') { [void]$ids.Add("nvidia") }
    if ($gpuText -match '(?i)\bamd\b|radeon') { [void]$ids.Add("amd") }
    if ($gpuText -match '(?i)intel' -or [string]$Hardware.CpuVendor -match '(?i)intel') { [void]$ids.Add("intel") }
    if ([string]$Hardware.CpuVendor -match '(?i)amd' -and -not $ids.Contains("amd")) { [void]$ids.Add("amd") }

    return @(foreach ($id in $ids) { $catalog | Where-Object { $_.Id -eq $id } })
}


function Show-TFToolkitVendorTools {
    $title = (Get-TFToolkitText 'Ferramentas do fabricante')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        Write-Progress -Activity $title -Status (Get-TFToolkitText 'lendo o fabricante do PC e da placa de vídeo')

        try {
            $hardware = Get-TFToolkitHardwareVendors
        }
        finally {
            Write-Progress -Activity $title -Completed
        }

        # O Windows que não respondeu (WMI parado ou danificado) não é o mesmo que um fabricante desconhecido: a tela diz que
        # não leu, e a indicação pode estar incompleta.
        $systemRead = [bool](Get-TFToolkitJsonValue -Object $hardware -Name "SystemRead" -Default $true)
        $gpuRead = [bool](Get-TFToolkitJsonValue -Object $hardware -Name "GpuRead" -Default $true)
        $unread = @()
        if (-not $systemRead) { $unread += (Get-TFToolkitText 'o fabricante do PC') }
        if (-not $gpuRead) { $unread += (Get-TFToolkitText 'a placa de vídeo') }
        $unreadText = $(if ($unread.Count -gt 0) { (Get-TFToolkitText 'não foi possível ler {0}' "$(Join-TFToolkitList -Items $unread)") } else { "" })

        # A faixa de quando o Windows não respondeu: a lista (ou a falta dela) pode não valer para este PC.
        $unreadView = {
            param ($Result)
            Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'A indicação pode estar incompleta') -Note "$($unreadText.Substring(0, 1).ToUpper())$($unreadText.Substring(1))."
        }

        $modelText = Get-TFToolkitHardwareModelText -Hardware $hardware

        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Fabricante do PC') -Value $(if (Test-TFToolkitVendorText -Text $hardware.Manufacturer) { $hardware.Manufacturer } elseif (-not $systemRead) { (Get-TFToolkitText 'não foi possível ler') } else { (Get-TFToolkitText 'não informado') })
        if ($modelText) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Modelo') -Value $modelText }
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Placa de vídeo') -Value $(if (@($hardware.Gpus).Count -gt 0) { Join-TFToolkitList -Items @($hardware.Gpus) } elseif (-not $gpuRead) { (Get-TFToolkitText 'não foi possível ler') } else { (Get-TFToolkitText 'não informada') })
        Write-Host ""

        if ($unreadText) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows não respondeu: {0}. A indicação abaixo pode estar incompleta.' "$unreadText")
        }

        $tools = @(Get-TFToolkitVendorTools -Hardware $hardware)

        if ($tools.Count -eq 0) {
            $where = $(if ($modelText) { (Get-TFToolkitText 'pelo modelo {0}' "$modelText") } else { (Get-TFToolkitText 'pelo modelo do PC') })

            if ($unreadText) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Procure, no site do fabricante do PC, a página de suporte {0}.' "$where")
            }
            else {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O TF-Toolkit não conhece a ferramenta deste fabricante. Procure, no site do fabricante, a página de suporte {0}.' "$where")
            }

            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Os drivers que o Windows Update oferece estão em Atualizações > Atualizar drivers.')

            # Uma tela que só indica não tem veredito ("Tudo certo"): sem desfecho registrado, a janela termina sem faixa.
            $none = $(if ($unreadText) { & $unreadView (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0}; nenhuma ferramenta indicada' "$unreadText") -Title $title) } else { $null })
            Exit-TFToolkitAction -Result $none
            return
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Recomendadas para este PC')

        foreach ($tool in $tools) {
            Write-TFToolkitKeyValue -Label $tool.Name -Value (Get-TFToolkitText 'para {0}{1}' "$($tool.For)" "$(if ($tool.WingetId) { (Get-TFToolkitText ' · instala pelo winget') } elseif ($tool.Store) { (Get-TFToolkitText ' · na Microsoft Store') } else { (Get-TFToolkitText ' · página oficial') })") -LabelWidth 34
        }

        Write-Host ""
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Essas ferramentas acham drivers de vídeo e de BIOS mais novos que os do Windows Update. Use uma por vez e siga as instruções dela.')
        Write-Host ""

        $options = @(
            for ($i = 0; $i -lt $tools.Count; $i++) {
                $tool = $tools[$i]
                @{ Key = [string]($i + 1); Label = $(if ($tool.WingetId) { (Get-TFToolkitText 'Instalar {0}' "$($tool.Name)") } else { $tool.Open }); Description = (Get-TFToolkitText 'para {0}' "$($tool.For)") }
            }
        )
        $options += @{ Key = "X"; Label = (Get-TFToolkitText 'Concluir'); Exit = $true; Accent = $true }

        $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Quer usar alguma agora?') -Options $options -DefaultKey "X" -ShowMenu -TextPrompt (Get-TFToolkitText 'Opção (número ou X; ENTER = concluir)')
        $index = 0

        if (-not [int]::TryParse([string]$answer, [ref]$index) -or $index -lt 1 -or $index -gt $tools.Count) {
            # Concluir sem usar nenhuma: a tela só indicou, e a lista é o conteúdo (sem faixa "Tudo certo").
            $indicated = Format-TFToolkitCount -Count $tools.Count -One (Get-TFToolkitText 'ferramenta indicada') -Many (Get-TFToolkitText 'ferramentas indicadas')
            $done = $(if ($unreadText) { & $unreadView (New-TFToolkitResult -Kind Warning -Detail "$indicated; $unreadText" -Title $title) } else { $null })
            Exit-TFToolkitAction -Result $done
            return
        }

        $tool = $tools[$index - 1]

        if ($tool.WingetId) {
            if (-not (Initialize-TFToolkitWinget)) {
                Exit-TFToolkitAction -Result (Get-TFToolkitWingetMissingResult -Title $title)
                return
            }

            $result = Get-TFToolkitLastResult -Output (Invoke-TFToolkitWingetPackages -Operation Install -Packages @([PSCustomObject]@{ Id = $tool.WingetId; Nome = $tool.Name }))
            $final = $(if ($null -ne $result) { $result } else { New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'a instalação não devolveu resultado') })
            $final.Etapa = $title

            if ($final.Kind -eq "Ok") {
                [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText '{0} está instalado' "$($tool.Name)") -Note (Get-TFToolkitText 'Abra-o pelo menu Iniciar e siga as instruções dele.'))
            }
        }
        else {
            # Sem navegador padrão (ou com a associação quebrada), o Windows recusa abrir o endereço com uma mensagem em
            # inglês: a tela diz o que houve e deixa o endereço para copiar.
            $opened = $true

            # Pelo explorer.exe, que entrega a abertura ao Explorador da sessão: o navegador (ou a Store) abre sem o
            # Administrador da janela; aberto direto daqui, ele herdaria a elevação.
            try { Start-Process -FilePath "explorer.exe" -ArgumentList "`"$($tool.Url)`"" -ErrorAction Stop } catch { $opened = $false }

            # "Abrindo a página do NVIDIA App", e não "aberta", porque o Windows só recebeu o pedido. Target vem traduzido do
            # catálogo: tirar o "Abrir " do rótulo do botão só funcionava em português.
            $target = [string]$tool.Target

            if ($opened -and $tool.Store) {
                Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Abrindo o {0} na Microsoft Store.' "$($tool.Name)")
                $final = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'abrindo o {0} na Microsoft Store' "$($tool.Name)") -Title $title
            }
            elseif ($opened) {
                Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Abrindo {0} no navegador.' "$target")
                $final = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'abrindo {0} no navegador' "$target") -Title $title
            }
            elseif ($tool.Store) {
                Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O Windows não abriu a Microsoft Store. Abra-a e procure por {0}.' "$($tool.Name)")
                $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o Windows não abriu a Microsoft Store; procure por {0} nela' "$($tool.Name)") -Title $title
                [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'A Microsoft Store não abriu') -Note (Get-TFToolkitText 'Abra-a e procure por {0}.' "$($tool.Name)"))
            }
            else {
                Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O Windows não abriu o navegador. Copie o endereço e abra-o no navegador: {0}' "$($tool.Url)")
                $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o Windows não abriu o navegador; o endereço está no resumo') -Title $title
                [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'O navegador não abriu') -Note (Get-TFToolkitText 'Copie o endereço que está no resumo e abra-o no navegador.'))
            }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível concluir: {0}.' "$($_.Exception.Message.TrimEnd('.'))")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message.TrimEnd('.') -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
