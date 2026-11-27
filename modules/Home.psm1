# Tela inicial (Início): a nota de saúde, os cartões do estado do PC e o que o TF-Toolkit já fez ("Histórico neste PC").
#
# A leitura é dividida em etapas independentes (Read-TFToolkitHomeStep): a janela lê uma etapa por vez num runspace à
# parte e mostra cada cartão assim que a etapa dele termina; a verificação rápida da linha de comando
# (Get-TFToolkitHomeStatus) e o relatório leem todas de uma vez. Uma etapa que falha vira "Não foi possível ler" e não
# apaga as outras; se ela entra na nota, a nota diz que ficou sem essa leitura.
#
# Os cartões só mostram e levam à tela do assunto; quem muda o PC são os botões da nota (Otimizar e Verificar o PC) e
# os de cada ponto de atenção.


# Os fatos da tela inicial, na ordem em que aparecem. A janela desenha os cartões a partir desta lista antes de a
# leitura do sistema terminar, e Get-TFToolkitHomeStatus preenche os mesmos Ids. Primeiro o que pode pedir atenção
# (espaço, proteção, suporte do Windows), depois o cuidado com o PC; a bateria fecha a lista: em desktops o cartão some,
# e no fim isso não muda o lugar de nenhum outro. Só tem cartão o que diz como o PC está: o nome do computador e da
# conta ficam em Sobre este PC (Consertar > Diagnóstico) e no relatório, e a manutenção agendada, que é opcional,
# só aparece quando pede atenção, como um ponto da nota. Na janela, o disco, a proteção e o sistema são cartões grandes;
# a última manutenção, o reinício pendente e a bateria ficam numa linha embaixo deles.
$script:TFToolkitHomeFactLabels = [ordered]@{
    disk        = (Get-TFToolkitText 'Disco do sistema')
    security    = (Get-TFToolkitText 'Proteção')
    windows     = (Get-TFToolkitText 'Sistema')
    reboot      = (Get-TFToolkitText 'Reinício pendente')
    maintenance = (Get-TFToolkitText 'Última manutenção')
    battery     = (Get-TFToolkitText 'Bateria')
}

# Para onde cada cartão leva ao ser clicado (Id de um item da tabela de navegação). Vazio = o cartão só informa. Os
# cartões só mostram: nenhum deles começa uma ação que muda o PC (para isso há os botões da nota de saúde).
$script:TFToolkitHomeFactTargets = @{
    windows     = "diagnostics.windows-support"
    disk        = "diagnostics.disks"
    reboot      = "diagnostics.pending-reboot"
    maintenance = "maintenance.history"
    security    = "security.status"
    battery     = "diagnostics.battery"
}


# As etapas da leitura do sistema, na ordem, e os cartões que cada uma preenche. A janela lê uma etapa por vez (a tela
# continua respondendo entre uma e outra e cada cartão aparece assim que a etapa dele termina); Get-TFToolkitHomeStatus lê
# todas de uma vez, para a verificação rápida da linha de comando.
# A proteção vem por último: é a leitura mais demorada (o Defender e a Central de Segurança), e os outros cartões não
# precisam esperar por ela. A manutenção agendada não tem cartão: a etapa só traz um ponto de atenção quando a tarefa
# existe e não está rodando.
$script:TFToolkitHomeStepFacts = [ordered]@{
    session     = @("windows")
    disk        = @("disk")
    reboot      = @("reboot")
    maintenance = @("maintenance")
    schedule    = @()
    battery     = @("battery")
    security    = @("security")
}

# As etapas que entram na nota de saúde. Se uma delas não puder ser lida, a nota vale só para o resto, e a tela diz isso.
$script:TFToolkitHomeScoredSteps = @("disk", "reboot", "maintenance", "security")

# O que fica sem leitura quando a etapa da sessão falha: o suporte do Windows (o prazo das atualizações de segurança e
# se elas estão em dia) entra na nota, e um Windows sem atualizações não pode passar por "tudo em dia" só porque a
# leitura falhou.
$script:TFToolkitHomeSupportLabel = (Get-TFToolkitText 'Suporte do Windows')

# Um Windows sem a atualização mensal registrada no catálogo, passado o prazo dela (Get-TFToolkitWindowsUpdateLag), está
# sem correções de segurança: é um ponto grave.
$script:TFToolkitHomeUpdateLagWeight = 20

# Um ponto de atenção de peso a partir de 20 (antivírus desligado, disco quase cheio, ameaça ativa...) tira a nota do verde:
# com ele a nota nunca passa de 74 ("Pede atenção"), por mais que o resto esteja em dia.
$script:TFToolkitHealthSevereWeight = 20
$script:TFToolkitHealthSevereCap = 74

# Bateria com esta carga ou menos, fora da tomada, fica em amarelo no cartão (não mexe na nota).
$script:TFToolkitLowBatteryPercent = 15


function Get-TFToolkitHomeFactLabels {
    return $script:TFToolkitHomeFactLabels
}


function Get-TFToolkitHomeScoredFacts {
    # Os cartões cujas etapas entram na nota de saúde (se um deles fica sem leitura, a nota avisa).
    return @(foreach ($step in $script:TFToolkitHomeScoredSteps) { $script:TFToolkitHomeStepFacts[$step] })
}


function Get-TFToolkitHomeOptionalFacts {
    # Os cartões que só existem em alguns PCs (a bateria, nos notebooks): a janela só os mostra depois da leitura.
    return @("battery")
}


function Get-TFToolkitHomeFactTarget {
    param ([Parameter(Mandatory)][string]$Id)

    if ($script:TFToolkitHomeFactTargets.ContainsKey($Id)) {
        return [string]$script:TFToolkitHomeFactTargets[$Id]
    }

    return ""
}


function ConvertTo-TFToolkitHomeLine {
    # Um texto numa linha só: caracteres de controle (quebras de linha, tabulações, ESC, NEL) e os separadores de linha e
    # de parágrafo do Unicode viram um espaço, e espaços repetidos também.
    param ([AllowEmptyString()][AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return "" }

    return (([regex]::Replace($Text, '[\p{Cc}\p{Zl}\p{Zp}]+', ' ')) -replace ' {2,}', ' ').Trim()
}


function Get-TFToolkitHomeReaderModules {
    <#
    Os módulos que a leitura do Início usa (Read-TFToolkitHomeStep e o que ele chama). A janela lê o Início num runspace
    à parte e só importa estes: importar todos os módulos lá atrasava o primeiro cartão em mais de um segundo. Um teste
    confere que cada função chamada pela leitura está num destes módulos.
    #>
    return @("Core", "Catalog", "WindowsSupport", "Security", "Diagnostics", "Schedule", "Launcher", "Home")
}


function New-TFToolkitHomeFact {
    <#
    Um cartão do Início. Text é a frase completa (o leitor de tela, a verificação rápida e o JSON usam ela); Value e
    Detail são o que o cartão da janela mostra, em duas linhas curtas: o valor em destaque e o complemento embaixo. Sem
    Value, o cartão mostra o Text. Level = Normal | Ok | Warn | Muted (a interface escolhe a cor). Visible = falso esconde
    o cartão (por exemplo, Bateria em um desktop). Target é o item da navegação que o clique abre.
    #>
    param (
        [Parameter(Mandatory)][string]$Id,
        [AllowEmptyString()][string]$Text,
        [ValidateSet("Normal", "Ok", "Warn", "Muted")]
        [string]$Level = "Normal",
        [bool]$Visible = $true,
        [AllowEmptyString()][string]$Value = "",
        [AllowEmptyString()][string]$Detail = ""
    )

    # Cada texto é uma linha: o nome de um antivírus, de um computador ou de uma conta vem do Windows e de outros
    # programas, e uma quebra de linha ou um caractere de controle no meio desenharia um cartão torto (ou cortado).
    $Text = ConvertTo-TFToolkitHomeLine -Text $Text
    $Value = ConvertTo-TFToolkitHomeLine -Text $Value
    $Detail = ConvertTo-TFToolkitHomeLine -Text $Detail

    # Um valor vazio (por exemplo, variável de ambiente ausente) não pode virar um cartão em branco.
    if ([string]::IsNullOrWhiteSpace($Text)) {
        $Text = (Get-TFToolkitText 'Não disponível')
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = $Text
    }

    return [PSCustomObject]@{
        Id      = $Id
        Label   = [string]$script:TFToolkitHomeFactLabels[$Id]
        Text    = $Text
        Value   = $Value
        Detail  = $(if ([string]::IsNullOrWhiteSpace($Detail)) { "" } else { $Detail.Trim() })
        Level   = $Level
        Visible = $Visible
        Target  = (Get-TFToolkitHomeFactTarget -Id $Id)
    }
}


function New-TFToolkitHealthIssue {
    # Um ponto que desconta da nota de saúde. Weight = pontos descontados; Target = item da navegação que resolve; Severe =
    # o ponto é grave (limita a nota e aparece em vermelho).
    param (
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$Weight,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$ButtonText
    )

    return [PSCustomObject]@{
        Id         = $Id
        Text       = $Text
        Weight     = $Weight
        Severe     = ($Weight -ge $script:TFToolkitHealthSevereWeight)
        Target     = $Target
        ButtonText = $ButtonText
    }
}


function Get-TFToolkitHealthScore {
    <#
    A nota de 0 a 100 da tela inicial: 100 menos o peso de cada ponto de atenção, e no máximo 74 quando algum ponto é
    grave (peso 20 ou mais). É uma leitura rápida do que o TF-Toolkit consegue ver (espaço, reinício, manutenção,
    proteção), não um laudo do PC. Unread = o que entraria na nota, mas não pôde ser lido (os nomes dos cartões): a nota
    vale para o resto, e a tela avisa.
    #>
    param (
        [object[]]$Issues = @(),
        [string[]]$Unread = @()
    )

    $list = @($Issues | Where-Object { $null -ne $_ })
    $penalty = 0

    foreach ($issue in $list) { $penalty += [int]$issue.Weight }

    $score = [Math]::Max(0, 100 - $penalty)

    if (@($list | Where-Object { [int]$_.Weight -ge $script:TFToolkitHealthSevereWeight }).Count -gt 0) {
        $score = [Math]::Min($score, $script:TFToolkitHealthSevereCap)
    }

    if ($score -ge 90) { $label = (Get-TFToolkitText 'Ótima'); $level = "Ok" }
    elseif ($score -ge 75) { $label = (Get-TFToolkitText 'Boa'); $level = "Ok" }
    elseif ($score -ge 50) { $label = (Get-TFToolkitText 'Pede atenção'); $level = "Warn" }
    else { $label = (Get-TFToolkitText 'Crítica'); $level = "Bad" }

    # Com alguma leitura faltando, uma nota alta não pode parecer um atestado: um antivírus que não respondeu (ou o
    # suporte do Windows) poderia esconder justamente o problema. O número continua o do que foi lido, mas sem o verde.
    if (@($Unread | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -and $level -eq "Ok") {
        $label = (Get-TFToolkitText 'Incompleta')
        $level = "Warn"
    }

    # Do mais pesado ao mais leve e, no mesmo peso, na ordem em que foram lidos: o Sort-Object não garante a ordem dos
    # empates, e os pontos poderiam trocar de lugar entre uma leitura e outra.
    $ordered = @(
        for ($index = 0; $index -lt $list.Count; $index++) { [PSCustomObject]@{ Issue = $list[$index]; Index = $index } }
    )
    $sorted = @($ordered | Sort-Object -Property @{ Expression = { [int]$_.Issue.Weight }; Descending = $true }, @{ Expression = { $_.Index }; Descending = $false } | ForEach-Object { $_.Issue })

    return [PSCustomObject]@{
        Score  = [int]$score
        Label  = $label
        Level  = $level
        Issues = $sorted
        Unread = @($Unread | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
}


function Get-TFToolkitHealthSummary {
    <#
    A frase embaixo da nota: quantos pontos pedem atenção e o que ficou sem leitura (a nota só conta o que foi lido).
    -WithoutCount: a janela, que mostra cada ponto numa linha logo abaixo, só precisa do que ficou sem leitura (com os
    pontos à vista, a contagem repetiria a lista); sem nenhum ponto, a frase vem inteira.
    #>
    param (
        $Health,
        [switch]$WithoutCount
    )

    if ($null -eq $Health) { return "" }

    $count = @($Health.Issues | Where-Object { $null -ne $_ }).Count
    $unread = @(Get-TFToolkitJsonValue -Object $Health -Name "Unread" -Default @())

    if ($count -gt 0 -and $WithoutCount) {
        $text = ""
    }
    elseif ($count -eq 0) {
        $text = $(if ($unread.Count -gt 0) { (Get-TFToolkitText 'Nada pedindo atenção no que foi lido.') } else { (Get-TFToolkitText 'Nada pedindo atenção agora.') })
    }
    elseif ([int](Get-TFToolkitJsonValue -Object $Health -Name "Score" -Default 0) -ge 75) {
        # Com a nota no verde ("Seu PC está em ótima forma", ou "parece bem" quando algo ficou sem leitura), "pede atenção"
        # desdiria a frase de cima (e é o nome da faixa amarela): o que sobrou são detalhes, sem pressa. Vale a nota, e não
        # a cor: a leitura incompleta tira o verde, mas não muda o tamanho dos pontos.
        $text = $(if ($count -eq 1) { (Get-TFToolkitText '1 detalhe para quando puder.') } else { (Get-TFToolkitText '{0} detalhes para quando puder.' "$count") })
    }
    elseif ($count -eq 1) {
        $text = (Get-TFToolkitText '1 ponto pede atenção.')
    }
    else {
        $text = (Get-TFToolkitText '{0} pontos pedem atenção.' "$count")
    }

    if ($unread.Count -gt 0) {
        $text = ((Get-TFToolkitText '{0} Não foi possível ler: {1}.' "$text" "$($unread -join ', ')")).Trim()
    }

    return $text
}


function Test-TFToolkitHealthKnown {
    # Falso quando nada do que entra na nota pôde ser lido (disco, reinício, manutenção e proteção) e nenhum ponto de
    # atenção apareceu: aí um "100" não diria nada sobre o PC, e a tela e a verificação rápida dizem que não foi possível
    # avaliar. Um ponto achado (o antivírus desligado, numa proteção lida pela metade) vale mesmo assim: esconder o que
    # foi visto porque o resto não respondeu seria pior.
    param ($Health)

    if ($null -eq $Health) { return $false }

    if (@(Get-TFToolkitJsonValue -Object $Health -Name "Issues" -Default @() | Where-Object { $null -ne $_ }).Count -gt 0) { return $true }

    $unread = @(Get-TFToolkitJsonValue -Object $Health -Name "Unread" -Default @())
    $scored = @(foreach ($id in (Get-TFToolkitHomeScoredFacts)) { [string]$script:TFToolkitHomeFactLabels[$id] })

    return (@($scored | Where-Object { $_ -notin $unread }).Count -gt 0)
}


function New-TFToolkitHomeStepResult {
    # O resultado de uma etapa da leitura: os cartões que ela preenche, os avisos de destaque, os pontos de atenção e o
    # que deveria contar na nota, mas não pôde ser lido (Unread, os nomes dos cartões).
    param (
        [Parameter(Mandatory)][string]$Step,
        [object[]]$Facts = @(),
        [object[]]$Notices = @(),
        [object[]]$Issues = @(),
        [string[]]$Unread = @()
    )

    return [PSCustomObject]@{ Step = $Step; Facts = @($Facts); Notices = @($Notices); Issues = @($Issues); Unread = @($Unread) }
}


function Get-TFToolkitHomeSteps {
    # Os nomes das etapas, na ordem em que a janela e Get-TFToolkitHomeStatus as leem.
    return @($script:TFToolkitHomeStepFacts.Keys)
}


function Get-TFToolkitUserDisplayName {
    # "PC-DA-ANA\ana" vira "ana": o nome do próprio computador na frente da conta não diz nada a quem está nele. Uma
    # conta de domínio ou da nuvem ("EMPRESA\ana", "AzureAD\ana") continua inteira.
    param (
        [AllowEmptyString()][string]$Name,
        [AllowEmptyString()][string]$Computer
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }

    $parts = $Name.Split([char]'\', 2)

    if ($parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($Computer) -and $parts[0].Equals($Computer, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $parts[1]
    }

    return $Name
}


function Get-TFToolkitHomeWindowsShortName {
    # O nome do Windows no cartão: "Windows 11 Pro" vira "Windows 11" e "Windows Server 2022 Standard", "Windows Server
    # 2022" (a edição fica na frase inteira, que aparece ao passar o mouse), para a versão caber ao lado.
    param ([AllowEmptyString()][string]$Name)

    if ($Name -match '^(Windows 1[0-9])(\s|$)') { return $Matches[1] }

    # "Windows Server 2022 Standard" vira "Windows Server 2022": o nome inteiro não cabe no cartão.
    if ($Name -match '^(Windows Server [0-9]{4}( R2)?)(\s|$)') { return $Matches[1] }

    return $Name
}


function Read-TFToolkitHomeSession {
    $facts = @()
    $notices = @()
    $issues = @()
    $unread = @()

    $computer = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($computer)) { $computer = [Environment]::MachineName }

    try {
        $session = Get-TFToolkitSessionInfo

        if ($null -eq $session) { throw (Get-TFToolkitText 'sem dados') }

        # O nome completo ("Windows 11 Pro") e a versão (24H2) vêm da sessão quando o Windows os informa; senão, o nome curto.
        $name = [string](Get-TFToolkitJsonValue -Object $session -Name "WindowsName" -Default "")
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$session.WindowsLabel }

        $version = [string](Get-TFToolkitJsonValue -Object $session -Name "WindowsVersion" -Default "")
        $build = [int](Get-TFToolkitJsonValue -Object $session -Name "WindowsBuild" -Default 0)

        $windowsText = $name
        if ($version) { $windowsText += " $version" }
        if ($build -gt 0) { $windowsText += (Get-TFToolkitText ' (build {0})' "$build") }

        # No cartão, o Windows e a versão ("Windows 11 24H2") e, embaixo, o prazo do suporte quando ele é conhecido, que é
        # o que importa; sem ele, a build. A edição fica na frase inteira (Text).
        # No Windows Server, o ano já é a versão ("Windows Server 2022"), e o 21H2 ao lado não caberia.
        $windowsValue = (Get-TFToolkitHomeWindowsShortName -Name $name)
        if ($version -and $windowsValue -notmatch '^Windows Server') { $windowsValue += " $version" }
        $windowsDetail = $(if ($build -gt 0) { (Get-TFToolkitText 'build {0}' "$build") } else { "" })

        $windowsLevel = "Normal"

        # Suporte do Windows: sem atualizações de segurança (ou perto disso), o cartão fica amarelo e a nota desconta. O
        # ESU do Windows 10 é conferido pela revisão da build instalada, sem consultar o histórico de atualizações. Sem a
        # build (o WMI e o Registro não responderam), não há o que conferir: a nota diz que ficou sem essa leitura, em vez
        # de tratar o Windows como uma versão fora da lista.
        $support = $null

        if ($build -gt 0) {
            try {
                $support = Get-TFToolkitWindowsSupportStatus -Build $build
            }
            catch {
                $support = $null
            }
        }

        # O suporte entra na nota: sem ele, a nota diz que ficou sem essa leitura (um Windows sem atualizações de segurança
        # não pode passar por "tudo em dia" só porque a leitura falhou).
        if ($null -eq $support) { $unread += $script:TFToolkitHomeSupportLabel }

        if ($null -ne $support) {
            $supportIssue = Get-TFToolkitWindowsSupportIssue -Status $support
            $supportShort = Get-TFToolkitWindowsSupportShortText -Status $support

            if ([string]$support.State -eq "Supported" -and $supportShort) {
                $windowsDetail = $supportShort
            }

            if ($null -ne $supportIssue) {
                $issues += $supportIssue
                $windowsLevel = "Warn"
                $windowsDetail = $supportShort
                $windowsText += " · $($supportIssue.Text.Substring(0, 1).ToLowerInvariant())$($supportIssue.Text.Substring(1))"
            }

            # Com o suporte em dia, falta saber se as atualizações chegaram: um Windows parado na atualização de meses
            # atrás (Windows Update pausado, desligado por um programa de "otimização" ou com defeito) está sem as
            # correções de segurança, mesmo dentro do prazo.
            if ([string]$support.State -in @("Supported", "EndingSoon", "Esu")) {
                $lag = $null

                try { $lag = Get-TFToolkitWindowsUpdateLag -Build $build } catch { $lag = $null }

                if ($lag -eq $true) {
                    $issues += New-TFToolkitHealthIssue -Id "updates" -Text (Get-TFToolkitText 'Faltam atualizações de segurança do Windows') -Weight $script:TFToolkitHomeUpdateLagWeight -Target "updates.install" -ButtonText (Get-TFToolkitText 'Atualizar')
                    $windowsLevel = "Warn"
                    $windowsDetail = (Get-TFToolkitText 'atualizações atrasadas')
                    $windowsText += (Get-TFToolkitText ' · faltam atualizações de segurança')
                }
            }
        }

        $facts += New-TFToolkitHomeFact -Id "windows" -Text $windowsText -Value $windowsValue -Detail $windowsDetail -Level $windowsLevel

        if ($session.UserMismatch) {
            # O nome vem do Windows: numa linha só, e sem ele a frase não fica com um buraco.
            $user = ConvertTo-TFToolkitHomeLine -Text (Get-TFToolkitUserDisplayName -Name ([string]$session.User) -Computer $computer)
            $who = $(if ($user) { (Get-TFToolkitText 'a conta {0}' "$user") } else { (Get-TFToolkitText 'outra conta') })

            $notices += [PSCustomObject]@{
                Level = "Warn"
                Text  = (Get-TFToolkitText 'O TF-Toolkit foi aberto com {0}, não com a que está em uso: a limpeza e os ajustes do Windows valem só para ela.' "$who")
            }
        }
    }
    catch {
        # Sem a sessão, o Windows fica sem leitura, e o suporte também (a nota avisa).
        $notices = @()
        $issues = @()
        $unread = @($script:TFToolkitHomeSupportLabel)
        $facts = @(New-TFToolkitHomeFact -Id "windows" -Text (Get-TFToolkitText 'Não foi possível ler') -Level Muted)
    }

    return New-TFToolkitHomeStepResult -Step "session" -Facts $facts -Notices $notices -Issues $issues -Unread $unread
}


function Read-TFToolkitHomeDisk {
    # O espaço livre na unidade do Windows. Os pontos de atenção levam à Limpeza personalizada: ela mostra o tamanho de
    # cada coisa que dá para limpar (temporários, caches, relatórios de erro, a Lixeira) e solta mais espaço que a
    # Limpeza rápida, que só cuida dos temporários e da Lixeira.
    $fact = $null
    $issues = @()
    $unread = @()

    try {
        $space = Get-TFToolkitSystemDriveSpace

        if ($null -eq $space) { throw (Get-TFToolkitText 'sem dados') }

        $level = Get-TFToolkitDiskSpaceLevel -FreeBytes $space.FreeBytes -TotalBytes $space.TotalBytes

        # Um espaço livre que não é número (ou negativo) não vira "0 B livres" num cartão tranquilo: é leitura que falhou.
        if ($level -eq "Unknown") { throw (Get-TFToolkitText 'espaço livre desconhecido') }

        $free = Format-TFToolkitBytes -Bytes $space.FreeBytes
        $total = Format-TFToolkitBytes -Bytes $space.TotalBytes
        $text = (Get-TFToolkitText '{0} livres de {1}' "$free" "$total")
        $detail = (Get-TFToolkitText 'de {0}' "$total")
        $level = $(switch ($level) { "Critical" { "Critical" } "Low" { "Low" } default { "Normal" } })

        # No cartão, o complemento fica "de 237 GB": o amarelo do valor e da barra, o "99% em uso" ao lado e o ponto da nota
        # já dizem que falta espaço, e " · quase cheio" a mais pedia uma coluna mais larga que a dos três cartões lado a
        # lado (eles iam um embaixo do outro justo com o disco cheio). A frase inteira (Text) continua dizendo.
        switch ($level) {
            "Critical" {
                $text += (Get-TFToolkitText ' (quase cheio)'); $level = "Warn"
                $issues += New-TFToolkitHealthIssue -Id "disk" -Text (Get-TFToolkitText 'O disco do sistema está quase cheio') -Weight 25 -Target "cleanup.custom" -ButtonText (Get-TFToolkitText 'Liberar espaço')
            }
            "Low" {
                $text += (Get-TFToolkitText ' (pouco espaço)'); $level = "Warn"
                $issues += New-TFToolkitHealthIssue -Id "disk" -Text (Get-TFToolkitText 'Pouco espaço livre no disco do sistema') -Weight 12 -Target "cleanup.custom" -ButtonText (Get-TFToolkitText 'Liberar espaço')
            }
        }

        $fact = New-TFToolkitHomeFact -Id "disk" -Text $text -Value (Get-TFToolkitText '{0} livres' "$free") -Detail $detail -Level $level

        # Quanto do disco está em uso, de 0 a 100, para a barra do cartão (a janela; a verificação rápida não leva).
        if ([double]$space.TotalBytes -gt 0) {
            $used = 100.0 * ([double]$space.TotalBytes - [double]$space.FreeBytes) / [double]$space.TotalBytes
            $fact | Add-Member -NotePropertyName Usage -NotePropertyValue ([int][Math]::Max(0, [Math]::Min(100, [Math]::Round($used, [MidpointRounding]::AwayFromZero))))
        }
    }
    catch {
        $issues = @()
        $unread = @($script:TFToolkitHomeFactLabels["disk"])
        $fact = New-TFToolkitHomeFact -Id "disk" -Text (Get-TFToolkitText 'Não foi possível ler') -Level Muted
    }

    return New-TFToolkitHomeStepResult -Step "disk" -Facts @($fact) -Issues $issues -Unread $unread
}


function Read-TFToolkitHomeReboot {
    $fact = $null
    $issues = @()
    $unread = @()

    try {
        if (Test-TFToolkitPendingReboot) {
            $fact = New-TFToolkitHomeFact -Id "reboot" -Text (Get-TFToolkitText 'Sim, reinicie o PC') -Value (Get-TFToolkitText 'Sim') -Detail (Get-TFToolkitText 'reinicie quando puder') -Level Warn
            $issues += New-TFToolkitHealthIssue -Id "reboot" -Text (Get-TFToolkitText 'Há um reinício pendente') -Weight 8 -Target "diagnostics.pending-reboot" -ButtonText (Get-TFToolkitText 'Ver')
        }
        else {
            $fact = New-TFToolkitHomeFact -Id "reboot" -Text (Get-TFToolkitText 'Não') -Level Ok
        }
    }
    catch {
        $issues = @()
        $unread = @($script:TFToolkitHomeFactLabels["reboot"])
        $fact = New-TFToolkitHomeFact -Id "reboot" -Text (Get-TFToolkitText 'Não foi possível ler') -Level Muted
    }

    return New-TFToolkitHomeStepResult -Step "reboot" -Facts @($fact) -Issues $issues -Unread $unread
}


function Get-TFToolkitLastCare {
    <#
    O último cuidado com o PC, do jeito que o Início e o monitor contam: a última manutenção e o último Verificar o PC.
    Uma data mais de um dia no futuro (o relógio do PC estava adiantado quando ela foi gravada) não vale: sem esta regra,
    uma verificação "de 2030" contaria como recente por anos e calaria o lembrete. Devolve Maintenance (o registro da
    última manutenção ou $null), MaintenanceAt, MaintenanceInFuture, CheckupAt ($null quando não há ou está no futuro),
    CheckupFresh (verificação de menos de um mês e mais nova que a manutenção) e Latest (o cuidado mais recente que vale,
    ou $null). CheckupInFuture diz que a verificação gravada tem data no futuro. -Strict: o registro da manutenção ou
    as preferências que existem, mas não puderam ser lidos (presos por outro programa, sem permissão), são um erro, e não
    "nunca rodou" (o Início diz que não conseguiu ler, em vez de pedir uma verificação).
    #>
    param (
        [datetime]$Now = (Get-Date),
        [switch]$Strict
    )

    $limit = $Now.AddDays(1)
    $last = Get-TFToolkitLastMaintenance -Strict:$Strict
    $maintenanceAt = $(if ($null -ne $last) { [datetime]$last.StartedAt } else { $null })
    $maintenanceInFuture = ($null -ne $maintenanceAt -and $maintenanceAt -gt $limit)

    $checkupAt = $null

    if ($Strict) { $checkupAt = Get-TFToolkitLastCheckup -Strict }
    else {
        try { $checkupAt = Get-TFToolkitLastCheckup } catch { $checkupAt = $null }
    }

    $checkupInFuture = ($null -ne $checkupAt -and $checkupAt -gt $limit)
    if ($checkupInFuture) { $checkupAt = $null }

    $validMaintenance = $(if ($maintenanceInFuture) { $null } else { $maintenanceAt })
    $checkupFresh = ($null -ne $checkupAt -and ($Now - $checkupAt).TotalDays -lt 30 -and ($null -eq $validMaintenance -or $checkupAt -gt $validMaintenance))

    $latest = $validMaintenance
    if ($null -ne $checkupAt -and ($null -eq $latest -or $checkupAt -gt $latest)) { $latest = $checkupAt }

    return [PSCustomObject]@{
        Maintenance         = $last
        MaintenanceAt       = $maintenanceAt
        MaintenanceInFuture = $maintenanceInFuture
        CheckupAt           = $checkupAt
        CheckupInFuture     = $checkupInFuture
        CheckupFresh        = $checkupFresh
        Latest              = $latest
    }
}


function Read-TFToolkitHomeMaintenance {
    <#
    O cuidado com o PC: a última manutenção e o último Verificar o PC, contados por Get-TFToolkitLastCare (a mesma conta
    do monitor). Uma verificação de menos de um mês e mais nova que a manutenção cobre o atraso (e o que a manutenção
    antiga deixou pendente), e a segunda linha do cartão diz isso. Sem nenhum dos dois em dia, o ponto de atenção leva ao
    Verificar o PC. Uma manutenção registrada com data no futuro (o relógio estava adiantado, ou foi atrasado depois) não
    vale como recente: o cartão diz isso, em vez de calar o lembrete até aquela data. A página Manutenção mostra o mesmo
    cartão. -Now: a hora de agora (os testes fixam uma).
    #>
    param ([datetime]$Now = (Get-Date))

    $fact = $null
    $issues = @()
    $unread = @()

    try {
        $care = Get-TFToolkitLastCare -Strict -Now $Now
        $last = $care.Maintenance
        # A segunda linha do cartão cabe pouco mais de 25 letras: "verificado há 45 minutos".
        $checkupNote = $(if ($care.CheckupFresh) { (Get-TFToolkitText 'verificado {0}' "$(Format-TFToolkitRelativeTime -When $care.CheckupAt -Now $Now)") } else { "" })

        if ($null -eq $last) {
            if ($care.CheckupFresh) {
                $fact = New-TFToolkitHomeFact -Id "maintenance" -Text (Get-TFToolkitText 'Ainda não executada · {0}' "$checkupNote") -Value (Get-TFToolkitText 'Ainda não executada') -Detail $checkupNote -Level Muted
            }
            else {
                $fact = New-TFToolkitHomeFact -Id "maintenance" -Text (Get-TFToolkitText 'Ainda não executada') -Detail (Get-TFToolkitText 'o ideal é uma por mês') -Level Muted
                $issues += New-TFToolkitHealthIssue -Id "maintenance" -Text (Get-TFToolkitText 'O PC ainda não foi verificado nem passou por uma manutenção') -Weight 5 -Target "maintenance.checkup" -ButtonText (Get-TFToolkitText 'Verificar o PC')
            }
        }
        else {
            $startedAt = $care.MaintenanceAt
            $date = Format-TFToolkitDateTime -When $startedAt

            if ($care.MaintenanceInFuture) {
                # Não dá para saber qual das duas datas está errada (a do registro ou a do relógio de agora): o texto diz
                # só que elas não batem.
                $text = (Get-TFToolkitText 'registrada em {0}, depois da data de hoje no relógio do Windows' "$date")

                if ($care.CheckupFresh) {
                    $fact = New-TFToolkitHomeFact -Id "maintenance" -Text "$text · $checkupNote" -Value (Get-TFToolkitText 'Data no futuro') -Detail $checkupNote -Level Normal
                }
                else {
                    $fact = New-TFToolkitHomeFact -Id "maintenance" -Text $text -Value (Get-TFToolkitText 'Data no futuro') -Detail (Get-TFToolkitText 'confira o relógio') -Level Warn
                    $issues += New-TFToolkitHealthIssue -Id "maintenance" -Text (Get-TFToolkitText 'A data da última manutenção não bate com o relógio do Windows') -Weight 8 -Target "maintenance.checkup" -ButtonText (Get-TFToolkitText 'Verificar o PC')
                }
            }
            elseif ($care.CheckupFresh) {
                $when = Format-TFToolkitRelativeTime -When $startedAt -Now $Now
                $fact = New-TFToolkitHomeFact -Id "maintenance" -Text "$when ($date) · $checkupNote" -Value $when -Detail $checkupNote -Level Normal
            }
            else {
                $problems = @(@($last.Results) | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["Kind"] -and [string]$_.Kind -in @("Warning", "Failed") }).Count
                $old = (($Now - $startedAt).TotalDays -ge 30)
                $when = Format-TFToolkitRelativeTime -When $startedAt -Now $Now
                $steps = Format-TFToolkitCount -Count $problems -One (Get-TFToolkitText 'etapa') -Many (Get-TFToolkitText 'etapas')
                $notes = @()

                if ($problems -gt 0) { $notes += (Get-TFToolkitText '{0} com atenção' "$steps") }

                # Uma manutenção por mês mantém o PC em dia; depois disso vale lembrar.
                if ($old) {
                    $notes += (Get-TFToolkitText 'já passou de um mês')

                    # Antiga e com problemas é um ponto só, com o peso maior (o de estar atrasada): uma manutenção velha que
                    # ainda por cima pediu atenção não pode descontar menos que uma velha que correu bem.
                    $issueText = $(if ($problems -gt 0) { (Get-TFToolkitText 'Faz mais de um mês desde a última manutenção ({0} com atenção)' "$steps") } else { (Get-TFToolkitText 'Faz mais de um mês desde a última manutenção') })
                    $issues += New-TFToolkitHealthIssue -Id "maintenance" -Text $issueText -Weight 8 -Target "maintenance.checkup" -ButtonText (Get-TFToolkitText 'Verificar o PC')
                }
                elseif ($problems -gt 0) {
                    # O que pediu atenção está no histórico (cada etapa com o motivo); refazer a manutenção inteira, uma hora
                    # de trabalho, só para rever duas etapas seria demais.
                    $issues += New-TFToolkitHealthIssue -Id "maintenance" -Text (Get-TFToolkitText 'A última manutenção terminou com {0} pedindo atenção' "$steps") -Weight 6 -Target "maintenance.history" -ButtonText (Get-TFToolkitText 'Ver')
                }

                $text = "$when ($date)"
                if ($notes.Count -gt 0) { $text += " · $($notes -join ' · ')" }

                # A segunda linha do cartão é curta: o que pede atenção, se houver (a idade já está no valor, em amarelo);
                # senão, a data. A frase inteira (Text) leva tudo.
                $fact = New-TFToolkitHomeFact -Id "maintenance" -Text $text -Value $when -Detail $(if ($notes.Count -gt 0) { $notes[0] } else { $date }) -Level $(if ($notes.Count -gt 0) { "Warn" } else { "Normal" })
            }
        }
    }
    catch {
        $issues = @()
        $unread = @($script:TFToolkitHomeFactLabels["maintenance"])
        $fact = New-TFToolkitHomeFact -Id "maintenance" -Text (Get-TFToolkitText 'Não foi possível ler') -Level Muted
    }

    return New-TFToolkitHomeStepResult -Step "maintenance" -Facts @($fact) -Issues $issues -Unread $unread
}


function Get-TFToolkitHomeAntivirusText {
    # O antivírus em poucas palavras, para a segunda linha do cartão Proteção. Com mais de um outro antivírus, o cartão
    # mostra o primeiro e quantos mais ("Avast +1"); -Full dá todos os nomes, para a frase inteira (ao passar o mouse, no
    # leitor de tela e na verificação rápida).
    param (
        $Antivirus,
        [switch]$Full
    )

    switch ([string]$Antivirus.Mode) {
        "Active" {
            if ($Antivirus.RealTime -eq $false) { return (Get-TFToolkitText 'Defender sem tempo real') }
            return "Windows Defender"
        }
        "Other" {
            $others = @(@(Get-TFToolkitJsonValue -Object $Antivirus -Name "Others" -Default @()) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ConvertTo-TFToolkitHomeLine -Text ([string]$_) })

            if ($others.Count -eq 0) { return (Get-TFToolkitText 'outro antivírus') }
            if ($Full -or $others.Count -eq 1) { return ($others -join ", ") }
            return "$($others[0]) +$($others.Count - 1)"
        }
        "Passive" { return (Get-TFToolkitText 'Defender em modo passivo') }
        "Off" { return (Get-TFToolkitText 'antivírus desligado') }
    }

    return (Get-TFToolkitText 'antivírus não lido')
}


function Read-TFToolkitHomeSecurity {
    <#
    Proteção: o antivírus e o firewall, no resumo de uma linha; cada ponto de atenção desconta da nota. Os pontos graves
    que só se resolvem no aplicativo do Windows (antivírus ou tempo real desligados, ameaça ativa, firewall desligado)
    abrem a Segurança do Windows direto na página do assunto (Target é o nome do atalho): a tela Estado da proteção só
    diria para ir lá, e depois de esperar a consulta ao Windows Update. Os que pedem conferência (modo passivo, ameaças
    guardadas com outro antivírus) abrem o Estado da proteção. Um antivírus que não respondeu não é um ponto de atenção:
    a nota diz que a proteção ficou sem leitura (afirmar um problema que não foi visto, ou calar sobre ele, seria pior).
    #>
    $fact = $null
    $issues = @()
    $unread = @()

    try {
        $protection = Get-TFToolkitSecurityStatus

        if ($null -eq $protection) { throw (Get-TFToolkitText 'sem dados') }

        # O aviso "antivírus sem leitura" é leitura que falhou, e não um ponto de atenção: o cartão diz "Leitura incompleta".
        $warnings = @($protection.Findings | Where-Object { $_.Level -eq "Warning" -and [string](Get-TFToolkitJsonValue -Object $_ -Name "Id" -Default "") -ne "antivirus-unreadable" })
        $antivirus = $protection.Antivirus
        $threats = $protection.Threats
        $mode = [string]$antivirus.Mode

        # Ameaças nulas = a consulta falhou (acontece quando outro antivírus ocupa o lugar do Defender): sem leitura, não é
        # "uma ameaça". Só uma lista com nomes conta.
        # Com outro antivírus no lugar, o que o Defender ainda guarda é ressalva (quem decide é o outro antivírus), como na
        # tela Estado da proteção e na auditoria; com o Defender ativo, é ameaça ativa, um ponto grave.
        if ($null -ne $threats -and @($threats).Count -gt 0) {
            $count = @($threats).Count

            if ($mode -eq "Other") {
                $issues += New-TFToolkitHealthIssue -Id "threats" -Text (Get-TFToolkitText 'O Defender guarda {0}; confira no outro antivírus' "$(Format-TFToolkitCount -Count $count -One (Get-TFToolkitText 'ameaça') -Many (Get-TFToolkitText 'ameaças'))") -Weight 10 -Target "security.status" -ButtonText (Get-TFToolkitText 'Ver')
            }
            else {
                $issues += New-TFToolkitHealthIssue -Id "threats" -Text (Get-TFToolkitText '{0} no antivírus' "$(Format-TFToolkitCount -Count $count -One (Get-TFToolkitText 'ameaça ativa') -Many (Get-TFToolkitText 'ameaças ativas'))") -Weight 30 -Target "WindowsSecurityThreats" -ButtonText (Get-TFToolkitText 'Segurança do Windows')
            }
        }

        if ($mode -eq "Off") {
            $issues += New-TFToolkitHealthIssue -Id "antivirus" -Text (Get-TFToolkitText 'Nenhum antivírus ativo foi encontrado') -Weight 25 -Target "WindowsSecurityThreats" -ButtonText (Get-TFToolkitText 'Segurança do Windows')
        }
        elseif ($mode -eq "Passive") {
            # Modo passivo sem outro antivírus identificado: pode haver um que o Windows não lista, então não é "sem
            # antivírus", mas pede conferência.
            $issues += New-TFToolkitHealthIssue -Id "antivirus-passive" -Text (Get-TFToolkitText 'O Defender está em modo passivo, sem outro antivírus à vista') -Weight 15 -Target "security.status" -ButtonText (Get-TFToolkitText 'Ver')
        }
        elseif ($mode -eq "Active" -and $antivirus.RealTime -eq $false) {
            $issues += New-TFToolkitHealthIssue -Id "realtime" -Text (Get-TFToolkitText 'A proteção em tempo real está desligada') -Weight 20 -Target "WindowsSecurityThreats" -ButtonText (Get-TFToolkitText 'Segurança do Windows')
        }

        if ($mode -eq "Active") {
            $age = Get-TFToolkitJsonValue -Object $antivirus -Name "SignatureAgeDays" -Default $null

            if ([bool](Get-TFToolkitJsonValue -Object $antivirus -Name "SignaturesNeverUpdated" -Default $false)) {
                $issues += New-TFToolkitHealthIssue -Id "signatures" -Text (Get-TFToolkitText 'O antivírus nunca foi atualizado') -Weight 10 -Target "security.signatures" -ButtonText (Get-TFToolkitText 'Atualizar')
            }
            elseif ($null -ne $age -and [int]$age -gt 7) {
                $issues += New-TFToolkitHealthIssue -Id "signatures" -Text (Get-TFToolkitText 'O antivírus não é atualizado há {0} dias' "$([int]$age)") -Weight 10 -Target "security.signatures" -ButtonText (Get-TFToolkitText 'Atualizar')
            }
        }

        if ($null -ne $protection.Firewall -and @(Get-TFToolkitFirewallGaps -Firewall $protection.Firewall).Count -gt 0) {
            $issues += New-TFToolkitHealthIssue -Id "firewall" -Text (Get-TFToolkitText 'O firewall está desligado em algum perfil de rede') -Weight 15 -Target "WindowsSecurityFirewall" -ButtonText (Get-TFToolkitText 'Segurança do Windows')
        }

        # "Protegido" só quando o antivírus, o firewall e (com o Defender ativo) as ameaças foram lidos: sem isso, a tela
        # Estado da proteção diria "nenhum ponto de atenção no que foi lido", e o cartão não pode prometer mais que ela. A
        # nota também avisa que a proteção não foi lida por inteiro.
        $incomplete = ($mode -eq "Unavailable") -or ($null -eq $protection.Firewall) -or ($mode -eq "Active" -and $null -eq $threats)
        $detail = Get-TFToolkitHomeAntivirusText -Antivirus $antivirus
        $fullDetail = Get-TFToolkitHomeAntivirusText -Antivirus $antivirus -Full

        if ($incomplete) { $unread = @($script:TFToolkitHomeFactLabels["security"]) }

        $value = $(if ($warnings.Count -gt 0) { Format-TFToolkitCount -Count $warnings.Count -One (Get-TFToolkitText 'ponto de atenção') -Many (Get-TFToolkitText 'pontos de atenção') } elseif ($incomplete) { (Get-TFToolkitText 'Leitura incompleta') } else { (Get-TFToolkitText 'Protegido') })
        $level = $(if ($warnings.Count -gt 0 -or $incomplete) { "Warn" } else { "Ok" })

        # A frase inteira leva o nome de todos os antivírus: no cartão, um nome comprido termina em "...".
        $fact = New-TFToolkitHomeFact -Id "security" -Text "$value · $fullDetail" -Value $value -Detail $detail -Level $level

        # A janela esconde o que só o Defender faz (Verificar vírus) quando ele não é quem protege o PC.
        $fact | Add-Member -NotePropertyName AntivirusMode -NotePropertyValue $mode
    }
    catch {
        $issues = @()
        $unread = @($script:TFToolkitHomeFactLabels["security"])
        $fact = New-TFToolkitHomeFact -Id "security" -Text (Get-TFToolkitText 'Não foi possível ler') -Level Muted
    }

    return New-TFToolkitHomeStepResult -Step "security" -Facts @($fact) -Issues $issues -Unread $unread
}


function Read-TFToolkitHomeBattery {
    # Bateria: só em notebooks. Num desktop, um nobreak ligado pelo USB aparece no Windows como bateria: o cartão some,
    # como quando não há bateria ou ela não pôde ser lida. Se é notebook vem da leitura da sessão (a primeira etapa, que
    # já perguntou ao Windows): perguntar de novo seriam mais duas consultas ao WMI a cada leitura do Início.
    $fact = $null

    try {
        $laptop = [bool](Get-TFToolkitJsonValue -Object (Get-TFToolkitSessionInfo) -Name "IsLaptop" -Default $false)
        $battery = $(if ($laptop) { Get-TFToolkitBatteryState } else { $null })

        if ($null -eq $battery) {
            $fact = New-TFToolkitHomeFact -Id "battery" -Text (Get-TFToolkitText 'Sem bateria') -Level Muted -Visible $false
        }
        else {
            # Alguns drivers informam valores fora de 0 a 100 (255, por exemplo) quando não sabem a carga; a mesma regra da
            # tela Saúde da bateria e do relatório.
            $charge = ConvertTo-TFToolkitBatteryPercent -Value (Get-TFToolkitJsonValue -Object $battery -Name "ChargePercent" -Default $null)

            $state = [string](Get-TFToolkitJsonValue -Object $battery -Name "State" -Default "")
            $value = $(if ($null -ne $charge) { "$charge%" } else { (Get-TFToolkitText 'Carga desconhecida') })
            $text = $value
            if ($state) { $text += " · $state" }

            # Pouca carga e longe da tomada: o cartão fica amarelo (a nota não muda; é o momento, não a saúde do PC).
            $onBattery = ([string](Get-TFToolkitJsonValue -Object $battery -Name "Code" -Default "") -eq "Battery")
            $level = $(if ($null -ne $charge -and $charge -le $script:TFToolkitLowBatteryPercent -and $onBattery) { "Warn" } else { "Normal" })

            $fact = New-TFToolkitHomeFact -Id "battery" -Text $text -Value $value -Detail $state.ToLowerInvariant() -Level $level
        }
    }
    catch {
        $fact = New-TFToolkitHomeFact -Id "battery" -Text (Get-TFToolkitText 'Sem bateria') -Level Muted -Visible $false
    }

    return New-TFToolkitHomeStepResult -Step "battery" -Facts @($fact)
}


function Read-TFToolkitHomeSchedule {
    <#
    Manutenção agendada: não tem cartão (é opcional, e "Não agendada" não diz nada sobre o PC). Só quando a tarefa existe
    e não está rodando (desligada no Agendador de Tarefas, apontando para um TF-Toolkit que sumiu ou mudou de pasta, ou com
    a última execução falha) vira um ponto leve da nota, com o botão para a tela que recria o agendamento. Sem leitura,
    nada: a nota não depende dela.
    ScheduleSetup: o passo da configuração inicial está feito (a tarefa existe e roda o TF-Toolkit desta pasta; sem conseguir
    ler o script dela, vale ela existir). A janela o usa no lugar de consultar o Agendador na thread dela
    (Get-TFToolkitSetupChecklist -ScheduleDone).
    #>
    $issues = @()
    $setup = $false

    try {
        $schedule = Get-TFToolkitScheduleStatus

        if ($null -ne $schedule -and [bool](Get-TFToolkitJsonValue -Object $schedule -Name "Installed" -Default $false)) {
            $setup = ([string](Get-TFToolkitJsonValue -Object $schedule -Name "ScriptPath" -Default "") -eq "" -or -not [bool](Get-TFToolkitJsonValue -Object $schedule -Name "Stale" -Default $false))

            $text = ""

            if (-not [bool](Get-TFToolkitJsonValue -Object $schedule -Name "Enabled" -Default $true)) {
                $text = (Get-TFToolkitText 'A manutenção agendada está desligada no Agendador de Tarefas')
            }
            elseif ([bool](Get-TFToolkitJsonValue -Object $schedule -Name "NeedsAttention" -Default $false)) {
                $moved = ([bool](Get-TFToolkitJsonValue -Object $schedule -Name "ScriptMissing" -Default $false) -or [bool](Get-TFToolkitJsonValue -Object $schedule -Name "Stale" -Default $false))
                $text = $(if ($moved) { (Get-TFToolkitText 'A manutenção agendada usa um TF-Toolkit de outra pasta') } else { (Get-TFToolkitText 'A última manutenção agendada falhou') })
            }

            if ($text) {
                $issues += New-TFToolkitHealthIssue -Id "schedule" -Text $text -Weight 3 -Target "maintenance.schedule" -ButtonText (Get-TFToolkitText 'Ver')
            }
        }
    }
    catch {
        $issues = @()
        $setup = $false
    }

    $result = New-TFToolkitHomeStepResult -Step "schedule" -Issues $issues
    $result | Add-Member -NotePropertyName ScheduleSetup -NotePropertyValue ([bool]$setup)

    return $result
}


function Read-TFToolkitHomeStep {
    <#
    Lê uma etapa da tela inicial (veja Get-TFToolkitHomeSteps) e devolve Step, Facts, Notices, Issues e Unread. Nunca lança
    erro por causa da leitura: se a etapa falhar de um jeito que ela mesma não previu, os cartões dela ficam como "Não foi
    possível ler" (a bateria, que só aparece em notebooks, some), a nota avisa o que ficou de fora e as outras etapas não
    são afetadas.
    #>
    param ([Parameter(Mandatory)][string]$Name)

    if (-not $script:TFToolkitHomeStepFacts.Contains($Name)) {
        throw (Get-TFToolkitText 'Etapa da tela inicial desconhecida: {0}' "$Name")
    }

    try {
        switch ($Name) {
            "session" { return (Read-TFToolkitHomeSession) }
            "disk" { return (Read-TFToolkitHomeDisk) }
            "reboot" { return (Read-TFToolkitHomeReboot) }
            "maintenance" { return (Read-TFToolkitHomeMaintenance) }
            "security" { return (Read-TFToolkitHomeSecurity) }
            "schedule" { return (Read-TFToolkitHomeSchedule) }
            "battery" { return (Read-TFToolkitHomeBattery) }
        }
    }
    catch {
        return (New-TFToolkitHomeStepFailure -Name $Name)
    }
}


function New-TFToolkitHomeStepFailure {
    # O resultado de uma etapa que não pôde ser lida (falhou ou passou do tempo): os cartões dela dizem "Não foi possível
    # ler" (a bateria some) e, se ela entra na nota, a nota diz que ela ficou de fora.
    param ([Parameter(Mandatory)][string]$Name)

    $facts = @(
        foreach ($id in $script:TFToolkitHomeStepFacts[$Name]) {
            if ($id -eq "battery") { New-TFToolkitHomeFact -Id $id -Text (Get-TFToolkitText 'Sem bateria') -Level Muted -Visible $false }
            else { New-TFToolkitHomeFact -Id $id -Text (Get-TFToolkitText 'Não foi possível ler') -Level Muted }
        }
    )

    $unread = @(if ($Name -in $script:TFToolkitHomeScoredSteps) { foreach ($id in $script:TFToolkitHomeStepFacts[$Name]) { $script:TFToolkitHomeFactLabels[$id] } })

    # A sessão traz o suporte do Windows, que entra na nota (Read-TFToolkitHomeSession).
    if ($Name -eq "session") { $unread = @($script:TFToolkitHomeSupportLabel) }

    return (New-TFToolkitHomeStepResult -Step $Name -Facts $facts -Unread $unread)
}


function Get-TFToolkitHomeStatus {
    <#
    Os fatos que a tela inicial mostra (disco do sistema, proteção, Windows, reinício pendente, última manutenção e
    bateria), os avisos que merecem um destaque e a nota de saúde. É a soma
    de todas as etapas (Read-TFToolkitHomeStep); cada uma é independente: uma que falhe vira "Não foi possível ler" e não
    apaga as outras. Facts: Id, Label, Text, Value, Detail, Level, Visible e Target. Notices: Level e Text. Health:
    Score, Label, Level, Issues e Unread.
    #>
    $facts = @()
    $notices = @()
    $issues = @()
    $unread = @()

    foreach ($step in (Get-TFToolkitHomeSteps)) {
        $result = Read-TFToolkitHomeStep -Name $step

        $facts += @($result.Facts)
        $notices += @($result.Notices)
        $issues += @($result.Issues)
        $unread += @($result.Unread)
    }

    return [PSCustomObject]@{
        Facts   = @($facts)
        Notices = @($notices)
        Health  = (Get-TFToolkitHealthScore -Issues $issues -Unread $unread)
    }
}


function Get-TFToolkitSetupChecklist {
    <#
    A configuração inicial, no fim do Início: o atalho, o monitor na bandeja e a manutenção mensal, cada um com Done
    (já feito), o item da navegação que o faz (NavId) e, quando o cartão roda algo diferente do item, Command. Visible:
    o cartão aparece (algum passo falta e ele não foi fechado). Ele fecha de vez com "Agora não" ou quando os três ficam
    feitos (a preferência SetupCardClosed): desligar o monitor depois não o traz de volta. Só leituras rápidas (arquivos e
    registro), para o Início não esperar.
    ScheduleDone: a manutenção mensal desta pasta está agendada. Vem da leitura do Início (Read-TFToolkitHomeSchedule), que
    consulta o Agendador de Tarefas fora da thread da janela e com prazo: um Agendador travado não congela a janela. A
    tarefa conta quando roda o TF-Toolkit desta pasta (uma que abre outra pasta, a extraída do zip ou uma que já foi apagada,
    falharia sem ninguém ver).
    #>
    param ([bool]$ScheduleDone = $false)

    $closed = [bool](Get-TFToolkitSetting -Name "SetupCardClosed" -Default $false)
    $root = Get-TFToolkitAppRoot

    $shortcut = $false
    try {
        $shortcut = (@(Get-TFToolkitShortcutState | Where-Object { $_.Exists -and $_.Current }).Count -gt 0) -or
            (@(Get-TFToolkitCommonShortcutPaths | Where-Object { Test-TFToolkitShortcutOpens -Path $_.Path -Root $root }).Count -gt 0)
    }
    catch { $shortcut = $false }

    $monitor = $false
    try { $monitor = ((Get-TFToolkitAgentRunState) -eq "On") } catch { $monitor = $false }

    $schedule = ((-not $closed) -and $ScheduleDone)

    $steps = @(
        [PSCustomObject]@{ Id = "shortcut"; Icon = "link"; Done = $shortcut; NavId = "app.shortcut"; Command = ""; Admin = $false
            Label = (Get-TFToolkitText 'Atalho do TF-Toolkit'); Description = (Get-TFToolkitText 'Para abrir pelo Menu Iniciar ou pela Área de Trabalho'); Button = (Get-TFToolkitText 'Criar') },
        [PSCustomObject]@{ Id = "monitor"; Icon = "bell"; Done = $monitor; NavId = "app.monitor"; Command = "Set-TFToolkitMonitor -Choose On"; Admin = $false
            Label = (Get-TFToolkitText 'Monitor na bandeja'); Description = (Get-TFToolkitText 'Avisa quando o disco enche, a proteção desliga ou o disco começa a falhar'); Button = (Get-TFToolkitText 'Ligar') },
        [PSCustomObject]@{ Id = "schedule"; Icon = "calendar"; Done = $schedule; NavId = "maintenance.schedule"; Command = ""; Admin = $true
            Label = (Get-TFToolkitText 'Manutenção mensal'); Description = (Get-TFToolkitText 'Uma vez por mês, apaga os temporários e salva um relatório'); Button = (Get-TFToolkitText 'Agendar') }
    )

    $pending = @($steps | Where-Object { -not $_.Done }).Count

    if (-not $closed -and $pending -eq 0) {
        [void](Set-TFToolkitSetting -Name "SetupCardClosed" -Value $true)
        $closed = $true
    }

    return [PSCustomObject]@{ Visible = (-not $closed -and $pending -gt 0); Steps = @($steps) }
}


function Close-TFToolkitSetupCard {
    # "Agora não": a configuração inicial não volta (os passos continuam em Sobre o TF-Toolkit e em Manutenção).
    [void](Set-TFToolkitSetting -Name "SetupCardClosed" -Value $true)
}


function Get-TFToolkitHomeValueSummary {
    <#
    "Histórico neste PC", no Início: o que o TF-Toolkit já fez aqui, só com o que ele mesmo anotou.
    Freed: a soma do que as etapas das manutenções disseram ter liberado ($null quando nenhuma mediu, ou nada foi
    liberado; as gravadas antes da 4.0 não têm a medida). Runs: as manutenções no histórico, o mesmo número da tela
    Histórico de manutenções (Full: o histórico chegou ao limite e guarda só as últimas). Changes: as mudanças anotadas; Undoable: quantas ainda
    têm desfazer. Visible: há algo a mostrar. Só leituras de dois arquivos pequenos, para o Início não esperar.
    #>
    # A gravação já troca a entrada de uma execução gravada de novo (o RunId): cada entrada é uma manutenção.
    $runs = @(Get-TFToolkitMaintenanceHistory | Where-Object { $null -ne $_ })

    $freed = $null
    $measured = @($runs | ForEach-Object { Get-TFToolkitJsonValue -Object $_ -Name "Freed" } | Where-Object { $null -ne $_ })

    if ($measured.Count -gt 0) {
        $total = [int64]0
        foreach ($bytes in $measured) { if ([int64]$bytes -gt 0) { $total += [int64]$bytes } }
        if ($total -gt 0) { $freed = $total }
    }

    $changes = @(Get-TFToolkitChanges)
    $undoable = @($changes | Where-Object { Test-TFToolkitChangeUndoable -Change $_ }).Count

    return [PSCustomObject]@{
        Visible  = ($null -ne $freed -or $runs.Count -gt 0 -or $changes.Count -gt 0)
        Freed    = $freed
        Runs     = $runs.Count
        Full     = ($runs.Count -ge (Get-TFToolkitMaintenanceHistoryLimit))
        Changes  = $changes.Count
        Undoable = $undoable
    }
}


Export-ModuleMember -Function *
