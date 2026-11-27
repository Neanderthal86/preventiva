# O próprio TF-Toolkit no Windows: ícone, identidade na barra de tarefas e os atalhos (.lnk) que abrem a janela.
# O trabalho de baixo nível (COM e API do shell) fica em Shell.psm1; aqui estão as decisões: o que o atalho executa,
# qual ícone usa e onde é criado.

# O começo do identificador da barra de tarefas; cada pasta do TF-Toolkit completa com o dela (Get-TFToolkitAppId).
$script:TFToolkitAppIdPrefix = "TechFontes.TFToolkit.v4"
$script:TFToolkitAppIds = @{}
# O que foi lido de cada atalho (o destino e o identificador), com a data e o tamanho do arquivo (Read-TFToolkitShortcutCached).
$script:TFToolkitShortcutReads = @{}
$script:TFToolkitAppRoot = Split-Path -Parent $PSScriptRoot
$script:TFToolkitShortcutFileName = "TFToolkit.lnk"
# Quem, além das contas de confiança, pode alterar os arquivos do TF-Toolkit (lido uma vez: Get-TFToolkitAppFolderWriters).
$script:TFToolkitAppFolderWriters = $null
# Se a janela está com a conta de outro Administrador (uma consulta ao WMI; o resumo é refeito a cada troca de tema).
$script:TFToolkitAccountMismatch = $null


function Get-TFToolkitAppRoot {
    # Pasta onde o TF-Toolkit está instalado (a que contém TF-Toolkit.Gui.ps1, modules, assets...).
    return $script:TFToolkitAppRoot
}


function Test-TFToolkitIconFile {
    # Confere o cabeçalho de um arquivo .ico (reservado 0, tipo 1 = ícone, ao menos uma imagem). Pega o arquivo vazio,
    # cortado por um download interrompido ou que não é um ícone; o Windows mostraria um ícone em branco.
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $stream = [System.IO.File]::OpenRead($Path)

        try {
            $header = New-Object byte[] 6

            if ($stream.Read($header, 0, 6) -ne 6) {
                return $false
            }
        }
        finally {
            $stream.Dispose()
        }

        return ($header[0] -eq 0 -and $header[1] -eq 0 -and $header[2] -eq 1 -and $header[3] -eq 0 -and ($header[4] -ne 0 -or $header[5] -ne 0))
    }
    catch {
        return $false
    }
}


function Get-TFToolkitIconPath {
    # Caminho do ícone (assets\TF-Toolkit.ico) ou $null se o arquivo não estiver na pasta ou não for um ícone válido.
    param (
        [string]$Root = (Get-TFToolkitAppRoot)
    )

    $assetsDir = Join-Path $Root "assets"
    foreach ($icoName in @("techfontes-icon.ico", "TF-Toolkit.ico")) {
        $path = Join-Path $assetsDir $icoName
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Test-TFToolkitIconFile -Path $path)) {
            return $path
        }
    }

    return $null
}


function Get-TFToolkitPowerShellPath {
    # O Windows PowerShell 5.1: o mesmo que os arquivos .cmd usam e que existe em todo Windows 10/11.
    if (-not [string]::IsNullOrEmpty($env:SystemRoot)) {
        $path = $env:SystemRoot
        foreach ($part in "System32", "WindowsPowerShell", "v1.0", "powershell.exe") {
            $path = Join-Path $path $part
        }

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    return "powershell.exe"
}


function Get-TFToolkitLaunchDefinition {
    <#
    Descreve como abrir a janela do TF-Toolkit: programa, argumentos, pasta de trabalho e ícone. É a mesma linha que o
    TF-Toolkit.cmd usa; a janela se reabre sozinha como Administrador, então o atalho não precisa pedir isso.
    #>
    param (
        [string]$Root = (Get-TFToolkitAppRoot)
    )

    $guiScript = Join-Path $Root "TF-Toolkit.Gui.ps1"

    if (-not (Test-Path -LiteralPath $guiScript -PathType Leaf)) {
        throw (Get-TFToolkitText 'O arquivo TF-Toolkit.Gui.ps1 não foi encontrado em ''{0}''. Extraia a pasta inteira do TF-Toolkit antes de criar o atalho.' "$Root")
    }

    $executable = Get-TFToolkitPowerShellPath
    $icon = Get-TFToolkitIconPath -Root $Root

    # Sem o arquivo do ícone, o atalho mostra o ícone do PowerShell em vez de ficar sem nenhum.
    $iconLocation = "$executable,0"

    if ($null -ne $icon) {
        $iconLocation = "$icon,0"
    }

    return [PSCustomObject]@{
        Executable       = $executable
        Arguments        = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File $(ConvertTo-TFToolkitCommandLineArgument -Value $guiScript)"
        WorkingDirectory = $Root
        IconLocation     = $iconLocation
        HasIcon          = ($null -ne $icon)
        Description      = (Get-TFToolkitText 'TF-Toolkit - manutenção, reparo e diagnóstico do Windows')
        AppId            = (Get-TFToolkitAppId -Root $Root)
    }
}


function Get-TFToolkitAppId {
    <#
    O identificador do TF-Toolkit na barra de tarefas (AppUserModelID) da pasta Root: "TFToolkit.App." e 16 letras do
    SHA-256 do caminho da pasta. A janela, o processo e os atalhos desta pasta usam o mesmo.

    Um por pasta, e não um só para todas as cópias: o Windows junta as janelas de mesmo identificador e guarda, para ele,
    o ícone e o comando de um atalho ou de um item fixado na barra de tarefas. Com um identificador só, a janela de uma
    pasta pegava o ícone de outra, e o de uma pasta já apagada aparecia em branco. Atualizar no lugar mantém a pasta, e com
    ela o identificador.

    O caminho é o mesmo de qualquer jeito que a pasta seja aberta: completo, sem a barra do fim, em maiúsculas (o Windows
    não diferencia) e, numa unidade de rede mapeada (Z:), como \\servidor\pasta, que é como a execução elevada a abre (a
    unidade mapeada não existe para ela; veja Get-GuiLaunchScriptPath). Faz parte do contrato com as versões futuras: outro
    cálculo daria outro identificador à mesma pasta, e os atalhos dela deixariam de se juntar à janela.
    #>
    param (
        [string]$Root = (Get-TFToolkitAppRoot)
    )

    if ($script:TFToolkitAppIds.ContainsKey($Root)) { return $script:TFToolkitAppIds[$Root] }

    $path = [string]$Root

    try { $path = [System.IO.Path]::GetFullPath($path) } catch { $path = [string]$Root }

    if ($path -match '^([A-Za-z]):\\') {
        $drive = $Matches[1]

        try {
            $display = [string](Get-PSDrive -Name $drive -PSProvider FileSystem -ErrorAction Stop).DisplayRoot
            if ($display -match '^\\\\[^\\]') { $path = $display.TrimEnd('\') + $path.Substring(2) }
        }
        catch {
            Write-Verbose "Unidade ${drive}: sem a unidade, vale o caminho como veio ($($_.Exception.Message))"
        }
    }

    $path = $path.TrimEnd('\').ToUpperInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($path))
    }
    finally {
        $sha.Dispose()
    }

    $id = "$($script:TFToolkitAppIdPrefix).$(-join @($hash[0..7] | ForEach-Object { $_.ToString('X2') }))"
    $script:TFToolkitAppIds[$Root] = $id

    return $id
}


function Get-TFToolkitShortcutLocation {
    # Onde o atalho pode ser criado, na ordem em que aparecem para a pessoa. Só entram pastas que este Windows informa.
    $places = @(
        @{ Id = "Desktop"; Label = (Get-TFToolkitText 'Área de Trabalho') },
        @{ Id = "StartMenu"; Label = (Get-TFToolkitText 'Menu Iniciar') }
    )

    foreach ($place in $places) {
        $folder = Get-TFToolkitSpecialFolder -Name $place.Id

        if ([string]::IsNullOrWhiteSpace($folder)) {
            continue
        }

        [PSCustomObject]@{
            Id     = $place.Id
            Label  = $place.Label
            Folder = $folder
            Path   = Join-Path $folder $script:TFToolkitShortcutFileName
        }
    }
}


function Get-TFToolkitShortcutPlaceText {
    # O lugar do atalho numa frase: "na Área de Trabalho", "no Menu Iniciar".
    param (
        [Parameter(Mandatory)]
        $Place
    )

    switch ([string]$Place.Id) {
        "Desktop"   { return (Get-TFToolkitText 'na Área de Trabalho') }
        "StartMenu" { return (Get-TFToolkitText 'no Menu Iniciar') }
        default     { return (Get-TFToolkitText 'em {0}' "$($Place.Label)") }
    }
}


function Initialize-TFToolkitAppIdentity {
    # Chamado pela janela antes de aparecer: o processo passa a se chamar TF-Toolkit (o desta pasta) para o Windows, e o
    # botão da barra de tarefas deixa de ser agrupado com o PowerShell. Devolve $true se o Windows aceitou.
    return (Set-TFToolkitProcessAppId -AppId (Get-TFToolkitAppId))
}


function Set-TFToolkitWindowIdentity {
    # Chamado pela janela depois de criada: o "Fixar na barra de tarefas" passa a abrir o TF-Toolkit, com o ícone dele.
    param (
        [Parameter(Mandatory)]
        [IntPtr]$Handle,

        [string]$Root = (Get-TFToolkitAppRoot)
    )

    try {
        $launch = Get-TFToolkitLaunchDefinition -Root $Root
    }
    catch {
        return $false
    }

    $command = "$(ConvertTo-TFToolkitCommandLineArgument -Value $launch.Executable) $($launch.Arguments)"

    return (Set-TFToolkitWindowRelaunch -Handle $Handle -AppId $launch.AppId -Command $command -IconResource $launch.IconLocation -DisplayName "TF-Toolkit")
}


function New-TFToolkitAppShortcut {
    <#
    Cria o atalho do TF-Toolkit, com o ícone, na Área de Trabalho e/ou no Menu Iniciar. Sem -Location, pergunta onde.
    Se o atalho já existir, é atualizado (por exemplo, depois de mover a pasta do TF-Toolkit).
    #>
    param (
        [ValidateSet("Desktop", "StartMenu")]
        [string[]]$Location,

        [switch]$Embedded,
        [switch]$PassThru
    )

    $title = (Get-TFToolkitText 'Criar atalho do TF-Toolkit')

    Enter-TFToolkitAction -Title $title -Embedded:$Embedded

    $result = New-TFToolkitResult -Kind Skipped -Title $title
    $ready = $false

    try {
        $launch = Get-TFToolkitLaunchDefinition
        $places = @(Get-TFToolkitShortcutLocation)

        if ($places.Count -eq 0) {
            throw (Get-TFToolkitText 'O Windows não informou a Área de Trabalho nem o Menu Iniciar deste usuário.')
        }

        $ready = $true
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message $_.Exception.Message
        $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'atalho não criado') -Title $title) `
            -Headline (Get-TFToolkitText 'O atalho não foi criado') -Note (Format-TFToolkitReasonNote -Text $_.Exception.Message)
    }

    # Elevado com a conta de outro Administrador, a Área de Trabalho e o Menu Iniciar seriam os dessa conta.
    if ($ready -and (Test-TFToolkitUserContextMismatch)) {
        $ready = $false
        $why = (Get-TFToolkitText 'O TF-Toolkit está aberto com a conta de outro Administrador: o atalho iria para a Área de Trabalho dessa conta. Para criar o atalho na sua conta, {0}.' "$(Get-TFToolkitUnelevatedHint)")
        Write-TFToolkitStatus -Type Warning -Message $why
        $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'com a conta de outro Administrador, o atalho não foi criado') -Title $title) `
            -Headline (Get-TFToolkitText 'O atalho não foi criado') -Note $why
    }

    # Com o TF-Toolkit instalado, o atalho do instalador (para todos os usuários) já abre esta pasta: um desta conta no mesmo
    # lugar apareceria repetido. Esses lugares saem da escolha, e um atalho repetido desta conta que abria o TF-Toolkit sai.
    if ($ready) {
        $covered = @($places | Where-Object { $place = $_; try { [bool](Test-TFToolkitInstallerShortcut -Id $place.Id) } catch { $false } })

        if ($covered.Count -gt 0) {
            $coveredIds = @($covered | ForEach-Object { [string]$_.Id })

            foreach ($place in $covered) {
                if (Test-TFToolkitShortcutIsTFToolkit -Path $place.Path) {
                    try { Remove-Item -LiteralPath $place.Path -Force -ErrorAction Stop } catch { Write-Verbose "Atalho repetido: $($_.Exception.Message)" }
                }
            }

            $coveredText = (Get-TFToolkitText 'O atalho do TF-Toolkit instalado já está {0}, para todos os usuários.' "$(Join-TFToolkitList -Items @($covered | ForEach-Object { Get-TFToolkitShortcutPlaceText -Place $_ }))")
            Write-TFToolkitStatus -Type Info -Message $coveredText
            $places = @($places | Where-Object { $coveredIds -notcontains [string]$_.Id })
            if ($PSBoundParameters.ContainsKey("Location")) { $Location = @($Location | Where-Object { $coveredIds -notcontains $_ }) }

            if ($places.Count -eq 0 -or ($PSBoundParameters.ContainsKey("Location") -and @($Location).Count -eq 0)) {
                $ready = $false
                $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'o atalho do TF-Toolkit instalado já existe') -Title $title) `
                    -Headline (Get-TFToolkitText 'O atalho já existe') -Note $coveredText
            }
        }
    }

    if ($ready) {
        Show-TFToolkitFolderWritersNotice
    }

    if ($ready) {
        # @($null) teria um item; por isso "sem -Location" é testado pelos parâmetros recebidos.
        if ($PSBoundParameters.ContainsKey("Location")) {
            $chosen = @($Location)
        }
        else {
            $chosen = @(Select-TFToolkitShortcutLocation -Places $places)
        }

        $selected = @($places | Where-Object { $chosen -contains $_.Id })

        if ($selected.Count -eq 0) {
            if ($chosen.Count -eq 0) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhum atalho foi criado.')
                $result = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title
            }
            else {
                # Pediram um lugar que este Windows não informou (por exemplo, sem o Menu Iniciar do usuário).
                $why = (Get-TFToolkitText 'Este Windows não informou a pasta do lugar pedido para o atalho.')
                Write-TFToolkitStatus -Type Error -Message $why
                $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o lugar pedido não está disponível neste Windows') -Title $title) `
                    -Headline (Get-TFToolkitText 'O atalho não foi criado') -Note $why
            }
        }
        else {
            $result = New-TFToolkitShortcutFiles -Places $selected -Launch $launch
        }
    }

    if ($PassThru) { $result }
    Exit-TFToolkitAction -Embedded:$Embedded -Result $result
}


function Test-TFToolkitShortcutIsTFToolkit {
    # Se o atalho abre o TF-Toolkit (de qualquer pasta): só um atalho assim é tirado quando repete o do instalador.
    param ([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    try {
        $target = Get-TFToolkitShortcutTarget -Path $Path
        return ($null -ne $target -and [string]$target.Arguments -match '(?i)TF-Toolkit\.Gui\.ps1')
    }
    catch {
        return $false
    }
}


function Select-TFToolkitShortcutLocation {
    # Pergunta onde criar o atalho. Devolve os Ids escolhidos, ou nada se a pessoa cancelar.
    param (
        [Parameter(Mandatory)]
        [object[]]$Places
    )

    if ($Places.Count -eq 1) {
        return @($Places[0].Id)
    }

    $options = @()
    $position = 0

    # O que cada lugar é, e não a pasta (C:\Users\...\Start Menu\Programs não diz nada a quem não a conhece).
    $about = @{ Desktop = (Get-TFToolkitText 'O ícone fica na tela, junto dos seus arquivos'); StartMenu = (Get-TFToolkitText 'O TF-Toolkit entra na lista de programas do botão Iniciar') }

    foreach ($place in $Places) {
        $position++
        $description = $(if ($about.ContainsKey([string]$place.Id)) { $about[[string]$place.Id] } else { [string]$place.Folder })
        $options += @{ Key = [string]$position; Label = $place.Label; Description = $description; Accent = ($position -eq 1) }
    }

    $options += @{ Key = "A"; Label = (Get-TFToolkitText 'Os dois'); Description = (Join-TFToolkitList -Items @($Places | ForEach-Object { [string]$_.Label })) }
    $options += @{ Key = "0"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }

    $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Onde você quer o atalho do TF-Toolkit?') -Options $options -ShowMenu

    if ($answer -eq "0") {
        return @()
    }

    if ($answer -eq "A") {
        return @($Places | ForEach-Object { $_.Id })
    }

    # Qualquer outra resposta que não seja o número de um lugar da lista é tratada como cancelamento.
    $index = 0

    if ([int]::TryParse([string]$answer, [ref]$index) -and $index -ge 1 -and $index -le $Places.Count) {
        return @($Places[$index - 1].Id)
    }

    return @()
}


function New-TFToolkitShortcutFiles {
    # Grava o atalho em cada lugar escolhido e mostra o resultado. Um lugar com erro não impede os outros.
    param (
        [Parameter(Mandatory)]
        [object[]]$Places,

        [Parameter(Mandatory)]
        $Launch
    )

    $created = 0
    $updated = 0
    $failed = 0
    $appIdMissing = $false
    $createdIds = @()
    $failures = @()

    foreach ($place in $Places) {
        $existed = Test-Path -LiteralPath $place.Path -PathType Leaf

        try {
            if (-not (Test-Path -LiteralPath $place.Folder -PathType Container)) {
                throw (Get-TFToolkitText 'A pasta ''{0}'' não existe.' "$($place.Folder)")
            }

            $saved = Save-TFToolkitShortcutFile -Path $place.Path -Target $Launch.Executable -Arguments $Launch.Arguments `
                -WorkingDirectory $Launch.WorkingDirectory -IconLocation $Launch.IconLocation -Description $Launch.Description -AppId $Launch.AppId

            # Proteção contra ransomware ou antivírus podem bloquear a gravação sem o COM reclamar.
            if (-not (Test-Path -LiteralPath $place.Path -PathType Leaf)) {
                throw (Get-TFToolkitText 'o Windows não gravou o arquivo (a proteção contra ransomware ou um antivírus pode ter bloqueado a pasta).')
            }

            $created++
            $createdIds += [string]$place.Id

            if ($existed) { $updated++ }

            $verb = if ($existed) { (Get-TFToolkitText 'atualizado') } else { (Get-TFToolkitText 'criado') }
            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Atalho {0} {1}.' "$verb" "$(Get-TFToolkitShortcutPlaceText -Place $place)")
            Write-Host "      $($place.Path)" -ForegroundColor DarkGray

            if (-not $saved.AppIdSet) { $appIdMissing = $true }
        }
        catch {
            $failed++
            # A mesma frase na tela e na faixa, com o motivo legível (sem o embrulho do PowerShell).
            $why = ([string](ConvertTo-TFToolkitReadableError -Text ([string]$_.Exception.Message))).Trim().TrimEnd('.')
            $failures += "$(Get-TFToolkitText 'Não foi possível criar o atalho {0}: {1}' "$(Get-TFToolkitShortcutPlaceText -Place $place)" "$why")."
            Write-TFToolkitStatus -Type Error -Message $failures[-1]
        }
    }

    if ($created -gt 0) {
        Write-Host ""

        # O Explorador guarda o ícone de cada atalho: sem este aviso, um atalho regravado continuaria com o ícone antigo.
        if (Initialize-TFToolkitShellInterop) {
            try { [TFToolkit.ShellIdentity]::RefreshIcons() } catch { Write-Verbose "Ícones: $($_.Exception.Message)" }
        }

        if (-not $Launch.HasIcon) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O arquivo assets\TF-Toolkit.ico não foi encontrado; o atalho usa o ícone do PowerShell.')
        }

        if ($appIdMissing) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows não aceitou o identificador da barra de tarefas: fixado na barra, o atalho pode aparecer como PowerShell.')
        }

        # No Windows 11, a opção fica em 'Mostrar mais opções' (Área de Trabalho) ou em 'Mais' (Menu Iniciar). Mover a pasta do TF-Toolkit quebra o atalho: é criar de novo.
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Para fixar na barra de tarefas: botão direito no atalho, ''Fixar na barra de tarefas'' (no Windows 11, dentro de ''Mostrar mais opções'' ou de ''Mais'').')
    }

    if ($created -eq 0) {
        # A faixa diz que nada foi criado e, de cada lugar, o porquê.
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nenhum atalho criado') -Title (Get-TFToolkitText 'Criar atalho do TF-Toolkit')) `
                -Headline (Get-TFToolkitText 'O atalho não foi criado') -Note ($failures -join ' '))
    }

    # Diz onde o atalho ficou, para a faixa de resultado responder a pergunta "onde ele foi parar?".
    $where = Join-TFToolkitList -Items @($createdIds | ForEach-Object { if ($_ -eq "StartMenu") { (Get-TFToolkitText 'no Menu Iniciar') } else { (Get-TFToolkitText 'na Área de Trabalho') } })
    # Frases inteiras por verbo (atualizado, criado ou gravado): o particípio concorda diferente em cada idioma.
    $verb = $(if ($updated -eq $created) { "updated" } elseif ($updated -eq 0) { "created" } else { "written" })
    $doneText = @{
        updated = @{ One = (Get-TFToolkitText 'Atalho atualizado'); Many = (Get-TFToolkitText 'Atalhos atualizados'); Where = (Get-TFToolkitText 'atalho atualizado {0}' "$where"); But = (Get-TFToolkitText 'atalho atualizado {0}, mas {1}' "$where" "{0}"); Only = (Get-TFToolkitText 'Atalho atualizado só {0}' "$where") }
        created = @{ One = (Get-TFToolkitText 'Atalho criado'); Many = (Get-TFToolkitText 'Atalhos criados'); Where = (Get-TFToolkitText 'atalho criado {0}' "$where"); But = (Get-TFToolkitText 'atalho criado {0}, mas {1}' "$where" "{0}"); Only = (Get-TFToolkitText 'Atalho criado só {0}' "$where") }
        written = @{ One = (Get-TFToolkitText 'Atalho gravado'); Many = (Get-TFToolkitText 'Atalhos gravados'); Where = (Get-TFToolkitText 'atalho gravado {0}' "$where"); But = (Get-TFToolkitText 'atalho gravado {0}, mas {1}' "$where" "{0}"); Only = (Get-TFToolkitText 'Atalho gravado só {0}' "$where") }
    }[$verb]

    if ($failed -gt 0) {
        # O título diz onde o atalho ficou; a frase, onde não ficou e por quê.
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0}, {1} com erro' "$(Format-TFToolkitCount -Count $created -One (Get-TFToolkitText 'atalho criado') -Many (Get-TFToolkitText 'atalhos criados'))" "$failed") -Title (Get-TFToolkitText 'Criar atalho do TF-Toolkit')) `
                -Headline $doneText.Only -Note ($failures -join ' '))
    }

    # Um atalho sem o ícone ou sem o identificador da barra de tarefas funciona, mas não é o que a pessoa espera ver. Na
    # faixa, cada ressalva vai com a frase inteira que a tela mostrou.
    $caveats = @()
    $caveatNotes = @()

    if (-not $Launch.HasIcon) {
        $caveats += (Get-TFToolkitText 'está com o ícone do PowerShell')
        $caveatNotes += (Get-TFToolkitText 'O arquivo assets\TF-Toolkit.ico não foi encontrado; o atalho usa o ícone do PowerShell.')
    }

    if ($appIdMissing) {
        $caveats += (Get-TFToolkitText 'o botão pode aparecer como PowerShell ao ser fixado na barra de tarefas')
        $caveatNotes += (Get-TFToolkitText 'O Windows não aceitou o identificador da barra de tarefas: fixado na barra, o atalho pode aparecer como PowerShell.')
    }

    # A faixa da janela: o que foi feito no título; onde ficou e como fixar na frase.
    $headline = $(if ($created -gt 1) { $doneText.Many } else { $doneText.One })
    $pinHint = $(if ($created -gt 1) { (Get-TFToolkitText 'clique num deles com o botão direito') } else { (Get-TFToolkitText 'clique nele com o botão direito') })
    $whereText = $where.Substring(0, 1).ToUpperInvariant() + $where.Substring(1)

    if ($caveats.Count -gt 0) {
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail ($doneText.But.Replace("{0}", ($caveats -join '; '))) -Title (Get-TFToolkitText 'Criar atalho do TF-Toolkit')) `
                -Headline $headline -Note "$whereText. $($caveatNotes -join ' ')")
    }

    return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail $doneText.Where -Title (Get-TFToolkitText 'Criar atalho do TF-Toolkit')) `
            -Headline $headline -Note (Get-TFToolkitText '{0}. Para fixar na barra de tarefas, {1}.' "$whereText" "$pinHint"))
}


function Get-TFToolkitAppFolderWriters {
    <#
    As contas, além da sua, dos Administradores e do sistema, que podem alterar os arquivos do TF-Toolkit (a mesma conta do
    agendamento: Get-TFToolkitScheduleUntrustedWriters). A janela roda esses arquivos como Administrador: numa pasta que
    outras contas do PC alteram (C:\TF-Toolkit criada direto no disco, onde os "Usuários autenticados" podem modificar),
    qualquer uma delas passaria a rodar código como Administrador. Lido uma vez por processo; permissões que não puderam
    ser lidas não entram (não é um alarme).
    #>
    if ($null -ne $script:TFToolkitAppFolderWriters) { return $script:TFToolkitAppFolderWriters }

    $writers = @()

    try {
        if (Get-Command -Name Get-TFToolkitScheduleUntrustedWriters -ErrorAction SilentlyContinue) {
            $writers = @(Get-TFToolkitScheduleUntrustedWriters -Root (Get-TFToolkitAppRoot) | Where-Object { [string]$_ -notlike (Get-TFToolkitText 'não foi possível conferir as permissões de {0}' '*') })
        }
    }
    catch {
        $writers = @()
    }

    $script:TFToolkitAppFolderWriters = $writers
    return $writers
}


function Show-TFToolkitFolderWritersNotice {
    # O aviso de Criar atalho quando outras contas podem alterar os arquivos do TF-Toolkit (Get-TFToolkitAppFolderWriters).
    $writers = @(Get-TFToolkitAppFolderWriters)

    if ($writers.Count -eq 0) { return }

    Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Outras contas deste PC ({0}) podem alterar os arquivos do TF-Toolkit, que roda como Administrador: se mais alguém usa este PC, extraia o TF-Toolkit de novo em Arquivos de Programas e crie o atalho de lá.' "$($writers -join ', ')")
    Write-Host ""
}


function Get-TFToolkitShortcutState {
    <#
    Cada lugar do atalho (Área de Trabalho, Menu Iniciar) com Exists e Current (o atalho abre esta pasta do TF-Toolkit;
    um atalho que não pôde ser lido conta como desta pasta, para não acusar à toa). Sem um atalho desta conta, o do
    instalador (para todos os usuários) no mesmo lugar conta como atalho desta pasta, com Common.

    Com -Identity, Outdated diz se o atalho desta conta que abre esta pasta tem outro identificador da barra de tarefas
    (Get-TFToolkitAppId): um atalho de antes do identificador por pasta, ou sem nenhum. Ele abre o TF-Toolkit, mas, fixado na
    barra, ficaria ao lado da janela, e não junto. Um identificador que não pôde ser lido não acusa. Sem -Identity (o
    Início, que não espera por isso), Outdated é sempre $false.
    #>
    param ([switch]$Identity)

    $script = Join-Path (Get-TFToolkitAppRoot) "TF-Toolkit.Gui.ps1"
    $appId = $(if ($Identity) { Get-TFToolkitAppId } else { "" })

    foreach ($place in @(Get-TFToolkitShortcutLocation)) {
        $exists = Test-Path -LiteralPath $place.Path -PathType Leaf
        $current = $true
        $common = $false
        $outdated = $false

        if (-not $exists) {
            try { $common = [bool](Test-TFToolkitInstallerShortcut -Id $place.Id) } catch { $common = $false }
        }

        if ($exists) {
            $target = Read-TFToolkitShortcutCached -Path $place.Path -Kind Target

            if ($null -ne $target -and [string]$target.Arguments -and ([string]$target.Arguments).IndexOf($script, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                $current = $false
            }

            # Só o atalho que, lido, abre esta pasta: o de outra pasta já pede Criar atalho de novo (o identificador dele é
            # o daquela pasta), e um que não pôde ser lido não acusa.
            if ($Identity -and $null -ne $target -and ([string]$target.Arguments).IndexOf($script, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $saved = Read-TFToolkitShortcutCached -Path $place.Path -Kind AppId
                $outdated = ($null -ne $saved -and -not [string]::Equals([string]$saved, $appId, [StringComparison]::OrdinalIgnoreCase))
            }
        }

        [PSCustomObject]@{ Id = $place.Id; Label = $place.Label; Path = $place.Path; Exists = ($exists -or $common); Current = $current; Common = $common; Outdated = $outdated }
    }
}


function Read-TFToolkitShortcutCached {
    <#
    O destino (Target: Get-TFToolkitShortcutTarget) ou o identificador da barra de tarefas (AppId: Get-TFToolkitShortcutAppId)
    de um atalho, lido uma vez enquanto o arquivo não muda. Cada leitura abre o atalho pelo COM, e a página Sobre o TF-Toolkit
    pergunta duas vezes a cada vez que é desenhada (o resumo e o destaque), o Início também, e a troca de tema a desenha de
    novo. Um atalho regravado (Criar atalho do TF-Toolkit) muda a data e o tamanho, e é lido de novo. $null se não foi
    possível ler; o que não pôde ser lido não fica guardado, e a próxima vez tenta de novo.
    #>
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet("Target", "AppId")][string]$Kind
    )

    $stamp = ""

    try {
        $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $stamp = "$($file.LastWriteTimeUtc.Ticks)|$($file.Length)"
    }
    catch {
        return $null
    }

    $key = "$Kind|$Path"
    $known = $script:TFToolkitShortcutReads[$key]
    if ($null -ne $known -and $known.Stamp -eq $stamp) { return $known.Value }

    $value = $null

    try {
        $value = $(if ($Kind -eq "Target") { Get-TFToolkitShortcutTarget -Path $Path } else { Get-TFToolkitShortcutAppId -Path $Path })
    }
    catch {
        $value = $null
    }

    if ($null -ne $value) { $script:TFToolkitShortcutReads[$key] = @{ Stamp = $stamp; Value = $value } }

    return $value
}


function Test-TFToolkitAppShortcutNeeded {
    <#
    Se a página Sobre o TF-Toolkit põe Criar atalho em destaque: falta o atalho desta pasta (desta conta ou do instalador),
    um deles abre outra pasta do TF-Toolkit ou o desta conta precisa ser atualizado (o identificador da barra de tarefas de
    antes). Com o atalho pronto, ele é uma linha como as outras. Com a conta de outro Administrador (o atalho iria para
    essa conta) ou sem as pastas do atalho, criar não daria certo: sem destaque. Sem conseguir ler, fica em destaque, como
    antes.
    #>
    try {
        # A mesma consulta do resumo do alto (Get-TFToolkitAboutPageStatus): a conta da janela não muda enquanto ela está aberta.
        if ($null -eq $script:TFToolkitAccountMismatch) { $script:TFToolkitAccountMismatch = [bool](Test-TFToolkitUserContextMismatch) }
        if ($script:TFToolkitAccountMismatch) { return $false }

        $places = @(Get-TFToolkitShortcutState -Identity)
    }
    catch {
        return $true
    }

    if ($places.Count -eq 0) { return $false }
    if (@($places | Where-Object { $_.Exists -and (-not $_.Current -or $_.Outdated) }).Count -gt 0) { return $true }

    return (@($places | Where-Object { $_.Exists }).Count -eq 0)
}


function Set-TFToolkitInterfaceLanguage {
    <#
    Sobre o TF-Toolkit > Idioma, pelo menu de texto (na janela, o cartão Idioma da página faz o mesmo): como o Windows,
    português, inglês ou espanhol. A escolha fica guardada e vale na próxima vez que o TF-Toolkit abrir; o -Language do
    TF-Toolkit-Console.cmd, quando usado, passa na frente dela só naquela execução.
    #>
    $title = (Get-TFToolkitText 'Idioma')

    Enter-TFToolkitAction -Title $title

    $current = Get-TFToolkitLanguagePreference
    $choices = @(Get-TFToolkitLanguageChoices)
    $inUse = Get-TFToolkitLanguage

    # Os nomes vêm das escolhas do cartão Idioma (cada idioma escrito nele mesmo), e não de uma segunda lista.
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Escolhido') -Value ([string](@($choices | Where-Object { $_.Id -eq $current })[0].Label))
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Em uso agora') -Value ([string](@($choices | Where-Object { $_.Id -eq $inUse })[0].Label))
    Write-Host ""

    $options = @()
    $position = 1

    foreach ($choice in $choices) {
        $options += @{ Key = "$position"; Label = [string]$choice.Label; Description = $(if ($choice.Id -eq $current) { (Get-TFToolkitText 'a escolha atual') } else { "" }) }
        $position++
    }

    $options += @{ Key = "0"; Label = (Get-TFToolkitText 'Voltar'); Exit = $true }

    $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Em que idioma o TF-Toolkit deve abrir?') -Options $options -DefaultKey "0" -ShowMenu

    $index = 0
    if (-not [int]::TryParse([string]$answer, [ref]$index) -or $index -lt 1 -or $index -gt $choices.Count) {
        Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nada mudou') -Title $title)
        return
    }

    $chosen = $choices[$index - 1]

    if ([string]$chosen.Id -eq $current) {
        Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'o idioma escolhido já era esse') -Title $title)
        return
    }

    if (-not (Set-TFToolkitLanguagePreference -Language ([string]$chosen.Id))) {
        $failed = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível guardar a escolha do idioma') -Title $title
        Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result $failed -Headline (Get-TFToolkitText 'O idioma não mudou') -Note (Format-TFToolkitReasonNote -Text $failed.Detail))
        return
    }

    $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'idioma escolhido: {0}; vale quando o TF-Toolkit abrir de novo' "$($chosen.Label)") -Title $title
    Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result $result -Headline (Get-TFToolkitText 'Idioma escolhido: {0}' "$($chosen.Label)") -Note (Get-TFToolkitText 'Vale quando o TF-Toolkit abrir de novo.'))
}


function Show-TFToolkitAbout {
    # Tela "Versão e pastas": o que está aberto, de que pasta (instalada ou só extraída: a linha Instalação diz) e onde
    # ficam os logs, os relatórios e os atalhos.
    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Versão e pastas')

    $dataPath = Get-TFToolkitDataPath

    Write-TFToolkitSection -Title "TF-Toolkit"
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Versão') -Value "$(Get-TFToolkitBuild)"
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Pasta do TF-Toolkit') -Value (Get-TFToolkitAppRoot)

    try { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Instalação') -Value (Get-TFToolkitInstallStateText).Text } catch { Write-Verbose "Instalação: $($_.Exception.Message)" }
    Write-TFToolkitKeyValue -Label "PowerShell" -Value "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Administrador') -Value $(if (Test-TFToolkitAdministrator) { (Get-TFToolkitText 'Sim') } else { (Get-TFToolkitText 'Não') })

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Pastas')
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Logs e relatórios') -Value $dataPath

    $logPath = Get-TFToolkitLogPath

    if (-not [string]::IsNullOrWhiteSpace($logPath)) {
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Log desta sessão') -Value $logPath
    }

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Atalho')

    $iconMissing = ($null -eq (Get-TFToolkitIconPath))

    if ($iconMissing) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O arquivo assets\TF-Toolkit.ico não foi encontrado; os atalhos usam o ícone do PowerShell.')
    }

    foreach ($place in @(Get-TFToolkitShortcutState -Identity)) {
        $text = $(if (-not $place.Exists) { (Get-TFToolkitText 'Sem atalho') } elseif ($place.Common) { (Get-TFToolkitText 'Atalho do instalador, para todos os usuários') } elseif (-not $place.Current) { (Get-TFToolkitText 'Atalho de outra pasta do TF-Toolkit; crie de novo') } elseif ($place.Outdated) { (Get-TFToolkitText 'Atalho precisa ser atualizado; crie de novo') } else { (Get-TFToolkitText 'Atalho criado') })
        Write-TFToolkitKeyValue -Label $place.Label -Value $text
    }

    # É uma tela de leitura: sem problema, não há faixa de resultado; com o ícone faltando, a faixa diz exatamente isso.
    if ($iconMissing) {
        $missing = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o ícone assets\TF-Toolkit.ico não foi encontrado') -Title (Get-TFToolkitText 'Versão e pastas')
        Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result $missing -Headline (Get-TFToolkitText 'O ícone do TF-Toolkit não foi encontrado') `
                -Note (Get-TFToolkitText 'Os atalhos usam o ícone do PowerShell até você extrair a pasta inteira do TF-Toolkit de novo.'))
    }
    else {
        Exit-TFToolkitAction
    }
}


function Get-TFToolkitAboutShortcutRow {
    # A linha Atalho do resumo de Sobre o TF-Toolkit: onde o atalho desta pasta já existe, ou o que falta nele.
    try {
        $places = @(Get-TFToolkitShortcutState -Identity)
        $with = @($places | Where-Object { $_.Exists -and $_.Current } | ForEach-Object { [string]$_.Label })
        $stale = @($places | Where-Object { $_.Exists -and -not $_.Current } | ForEach-Object { [string]$_.Label })
        $outdated = @($places | Where-Object { $_.Exists -and $_.Current -and $_.Outdated } | ForEach-Object { [string]$_.Label })

        if ($places.Count -eq 0) {
            return [PSCustomObject]@{ Label = (Get-TFToolkitText 'Atalho'); Text = (Get-TFToolkitText 'o Windows não informou as pastas do atalho'); Level = "Muted" }
        }

        if ($stale.Count -gt 0) {
            # O atalho de uma cópia antiga (outra pasta) abriria a versão velha.
            return [PSCustomObject]@{ Label = (Get-TFToolkitText 'Atalho'); Text = (Get-TFToolkitText 'o de {0} abre outra pasta do TF-Toolkit; use Criar atalho do TF-Toolkit' "$(Join-TFToolkitList -Items $stale)"); Level = "Warn" }
        }

        if ($outdated.Count -gt 0) {
            # Abre esta pasta, com o identificador da barra de tarefas de antes: fixado, ficaria ao lado da janela.
            return [PSCustomObject]@{ Label = (Get-TFToolkitText 'Atalho'); Text = (Get-TFToolkitText 'o de {0} precisa ser atualizado; use Criar atalho do TF-Toolkit' "$(Join-TFToolkitList -Items $outdated)"); Level = "Warn" }
        }

        if ($with.Count -eq 0) {
            return [PSCustomObject]@{ Label = (Get-TFToolkitText 'Atalho'); Text = (Get-TFToolkitText 'ainda não criado; use Criar atalho do TF-Toolkit'); Level = "Muted" }
        }

        return [PSCustomObject]@{ Label = (Get-TFToolkitText 'Atalho'); Text = (Join-TFToolkitList -Items $with); Level = "Normal" }
    }
    catch {
        return [PSCustomObject]@{ Label = (Get-TFToolkitText 'Atalho'); Text = (Get-TFToolkitText 'não foi possível ler'); Level = "Muted" }
    }
}


function Get-TFToolkitAboutPageStatus {
    <#
    O resumo no alto da página Sobre o TF-Toolkit: a versão (e o que o TF-Toolkit sabe da última publicada), onde o atalho já
    existe (e se ele abre esta pasta), a instalação, o ícone e, quando é o caso, a falta de Administrador, a conta e as
    permissões da pasta. Cada linha tem Label, Text, Level (Normal | Warn | Muted) e, a da versão nova, Opens (Verificar
    nova versão). Só lê o que é local, sem consultar a internet: a última publicada é a da última consulta (Verificar nova
    versão ou o monitor). Cada linha que não puder ser lida vira "não foi possível ler" sozinha, em vez de derrubar a página.
    #>
    $rows = @()

    try {
        $build = "$(Get-TFToolkitBuild)"
        $known = $null
        try { $known = Get-TFToolkitKnownUpdate } catch { $known = $null }

        if ($null -ne $known -and $known.Newer) {
            $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Versão'); Text = (Get-TFToolkitText '{0}; a versão {1} está disponível' "$build" "$($known.Latest)"); Level = "Warn"; Opens = "app.update" }
        }
        elseif ($null -ne $known -and $known.Fresh -and $known.Current) {
            $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Versão'); Text = (Get-TFToolkitText '{0}, a mais recente' "$build"); Level = "Normal" }
        }
        else {
            $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Versão'); Text = $build; Level = "Normal" }
        }
    }
    catch {
        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Versão'); Text = (Get-TFToolkitText 'não foi possível ler'); Level = "Muted" }
    }

    # Uma consulta só por processo: a conta da janela não muda enquanto ela está aberta.
    $mismatch = $false
    try {
        if ($null -eq $script:TFToolkitAccountMismatch) { $script:TFToolkitAccountMismatch = [bool](Test-TFToolkitUserContextMismatch) }
        $mismatch = [bool]$script:TFToolkitAccountMismatch
    }
    catch {
        Write-Verbose "Conta: $($_.Exception.Message)"
    }

    # Com a conta de outro Administrador, a Área de Trabalho e o Menu Iniciar seriam os dessa conta, onde Criar atalho não
    # grava: a linha Conta diz isso, e o atalho não aparece como "ainda não criado".
    if (-not $mismatch) { $rows += Get-TFToolkitAboutShortcutRow }

    # Instalado (desinstala por Configurações > Aplicativos) ou aberto da pasta extraída (instala pelo TF-Toolkit-Setup.cmd).
    try {
        $install = Get-TFToolkitInstallStateText
        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Instalação'); Text = $install.Text; Level = $install.Level }
    }
    catch {
        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Instalação'); Text = (Get-TFToolkitText 'não foi possível ler'); Level = "Muted" }
    }

    # O ícone na sua própria linha: uma falha ao conferi-lo não vira uma segunda linha "Atalho".
    try {
        if ($null -eq (Get-TFToolkitIconPath)) {
            $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Ícone'); Text = (Get-TFToolkitText 'o arquivo do ícone (assets\TF-Toolkit.ico) não foi encontrado; extraia a pasta inteira do TF-Toolkit de novo'); Level = "Warn" }
        }
    }
    catch {
        Write-Verbose "Ícone: $($_.Exception.Message)"
    }

    try {
        # O TF-Toolkit abre sempre como Administrador, e a barra lateral já diz isso: a linha só aparece sem ele (a pessoa
        # recusou o aviso do Windows ao abrir), com o que muda.
        if (-not (Test-TFToolkitAdministrator)) {
            $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Administrador'); Text = (Get-TFToolkitText 'esta janela está sem Administrador; as ações que alteram o sistema pedem a permissão de novo'); Level = "Warn" }
        }
    }
    catch {
        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Administrador'); Text = (Get-TFToolkitText 'não foi possível ler'); Level = "Muted" }
    }

    if ($mismatch) {
        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Conta'); Text = (Get-TFToolkitText 'o TF-Toolkit está aberto com a conta de outro Administrador; atalhos, pastas e o monitor são os dessa conta'); Level = "Warn" }
    }

    $writers = @(Get-TFToolkitAppFolderWriters)

    if ($writers.Count -gt 0) {
        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Pasta'); Text = (Get-TFToolkitText 'outras contas deste PC podem alterar os arquivos do TF-Toolkit; se mais alguém usa o PC, extraia o TF-Toolkit de novo em Arquivos de Programas'); Level = "Warn" }
    }

    return $rows
}


Export-ModuleMember -Function *
