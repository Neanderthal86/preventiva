# Segurança: o estado da proteção do Windows (antivírus, firewall, atualizações pendentes, ameaças) e a verificação
# do Windows Defender. Tudo usa os comandos do próprio Windows (Get-MpComputerStatus, Update-MpSignature, Start-MpScan).
#
# Quando outro antivírus protege o PC, o Defender fica desligado ou em modo passivo: o TF-Toolkit diz isso e não
# tenta verificar, em vez de fingir que o PC foi checado.


# Quanto esperar antes de ler de novo o fim da verificação, quando o registro ainda não chegou (Get-TFToolkitScanFinish).
$script:TFToolkitScanFinishRetrySeconds = 2


# ---------------------------------------------------------------------------
# Leitura tolerante
# ---------------------------------------------------------------------------

# As propriedades dos objetos do Defender são lidas com Get-TFToolkitJsonValue (Core): versões diferentes do Windows
# expõem conjuntos diferentes de propriedades, e acessar uma que não existe derrubaria a tela sob Set-StrictMode.

function ConvertTo-TFToolkitMpDate {
    # O Defender usa datas antigas (1601, 1970) para "nunca aconteceu". Qualquer data antes de 2000 vira $null.
    param ($Value)

    if ($Value -isnot [datetime] -or ([datetime]$Value).Year -lt 2000) {
        return $null
    }

    return [datetime]$Value
}


function Get-TFToolkitOtherAntivirus {
    <#
    Nomes dos antivírus registrados na Central de Segurança que não são o Defender e estão com a proteção em tempo real
    ligada; $null quando a consulta falha. Um antivírus só registrado (vencido, desligado) não protege: o bit 0x1000 de
    productState é o "ligado" que a própria Central de Segurança mostra. E "não consegui perguntar" não é "não há outro
    antivírus": com o Defender desligado, a diferença é entre "não foi possível ler" e "PC desprotegido".
    #>
    try {
        $products = @(Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -OperationTimeoutSec 15 -ErrorAction Stop)
    }
    catch {
        return $null
    }

    # A vírgula impede que uma lista vazia vire $null ao sair da função ($null significa "não foi possível ler").
    return , @(
        $products |
            Where-Object { ([int64](Get-TFToolkitJsonValue -Object $_ -Name "productState" -Default 0) -band 0x1000) -ne 0 } |
            ForEach-Object { [string](Get-TFToolkitJsonValue -Object $_ -Name "displayName" -Default "") } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '(?i)^(windows|microsoft) defender' } |
            Select-Object -Unique
    )
}


# ---------------------------------------------------------------------------
# Estado
# ---------------------------------------------------------------------------

function Get-TFToolkitAntivirusStatus {
    <#
    Mode: Active (o Defender protege), Other (outro antivírus protege), Passive (Defender em modo passivo sem outro
    antivírus identificado), Off (desligado e sem outro antivírus ligado) ou Unavailable (não foi possível ler: o
    Defender não respondeu, ou ele não protege e a Central de Segurança não pôde ser consultada). DefenderRead diz se o
    Defender respondeu, para separar os dois casos de Unavailable. QuickScanMinutes é quanto a última verificação rápida
    levou ($null quando o Windows não diz).
    #>
    $computerStatus = $null

    try {
        # Com prazo (Invoke-TFToolkitCimCommand): o serviço do Defender travado deixava a tela, o Início e o monitor parados.
        $computerStatus = @(Invoke-TFToolkitCimCommand -Name "Get-MpComputerStatus")[0]
    }
    catch {
        $computerStatus = $null
    }

    $status = [PSCustomObject]@{
        Mode              = "Unavailable"
        DefenderRead      = ($null -ne $computerStatus)
        RealTime          = $null
        SignaturesUpdated = $null
        SignatureAgeDays  = $null
        SignaturesNeverUpdated = $false
        SignatureVersion  = ""
        TamperProtected   = $null
        LastQuickScan     = $null
        LastFullScan      = $null
        QuickScanMinutes  = $null
        Others            = @()
    }

    if ($null -eq $computerStatus) {
        # Os outros antivírus só importam quando o Defender não é quem protege: com ele ativo, a consulta à Central de
        # Segurança (WMI) seria trabalho perdido.
        $others = Get-TFToolkitOtherAntivirus
        if ($null -ne $others) { $status.Others = @($others) }

        if ($status.Others.Count -gt 0) { $status.Mode = "Other" }

        return $status
    }

    $serviceOn = [bool](Get-TFToolkitJsonValue -Object $computerStatus -Name "AMServiceEnabled" -Default $true)
    $antivirusOn = [bool](Get-TFToolkitJsonValue -Object $computerStatus -Name "AntivirusEnabled" -Default $false)
    $runningMode = [string](Get-TFToolkitJsonValue -Object $computerStatus -Name "AMRunningMode" -Default "")
    $passive = ($runningMode -match 'Passive|EDR Block')

    if (-not $serviceOn -or -not $antivirusOn -or $passive) {
        $others = Get-TFToolkitOtherAntivirus
        if ($null -ne $others) { $status.Others = @($others) }

        if ($status.Others.Count -gt 0) { $status.Mode = "Other" }
        elseif ($null -eq $others) { $status.Mode = "Unavailable" }
        elseif ($passive) { $status.Mode = "Passive" }
        else { $status.Mode = "Off" }
    }
    else {
        $status.Mode = "Active"
    }

    $status.RealTime = [bool](Get-TFToolkitJsonValue -Object $computerStatus -Name "RealTimeProtectionEnabled" -Default $false)
    $status.SignatureVersion = [string](Get-TFToolkitJsonValue -Object $computerStatus -Name "AntivirusSignatureVersion" -Default "")

    $tamper = Get-TFToolkitJsonValue -Object $computerStatus -Name "IsTamperProtected"

    if ($null -ne $tamper) {
        $status.TamperProtected = [bool]$tamper
    }

    $status.LastQuickScan = ConvertTo-TFToolkitMpDate -Value (Get-TFToolkitJsonValue -Object $computerStatus -Name "QuickScanEndTime")

    # Quanto a última verificação rápida levou: a linha do andamento da próxima diz isso (Get-TFToolkitScanDurationText).
    $quickStart = ConvertTo-TFToolkitMpDate -Value (Get-TFToolkitJsonValue -Object $computerStatus -Name "QuickScanStartTime")

    if ($null -ne $quickStart -and $null -ne $status.LastQuickScan -and $status.LastQuickScan -gt $quickStart) {
        $minutes = [int][Math]::Ceiling(($status.LastQuickScan - $quickStart).TotalMinutes)
        if ($minutes -ge 1 -and $minutes -le 120) { $status.QuickScanMinutes = $minutes }
    }
    $status.LastFullScan = ConvertTo-TFToolkitMpDate -Value (Get-TFToolkitJsonValue -Object $computerStatus -Name "FullScanEndTime")
    $status.SignaturesUpdated = ConvertTo-TFToolkitMpDate -Value (Get-TFToolkitJsonValue -Object $computerStatus -Name "AntivirusSignatureLastUpdated")

    if ($null -ne $status.SignaturesUpdated) {
        $status.SignatureAgeDays = [int][math]::Max(0, [math]::Floor(((Get-Date) - $status.SignaturesUpdated).TotalDays))
    }
    elseif ([string](Get-TFToolkitJsonValue -Object $computerStatus -Name "AntivirusSignatureAge" -Default "") -eq "65535") {
        # Sem data e com a idade em 65535: é como o Defender diz que as assinaturas nunca foram atualizadas (as que vêm
        # com o Windows, de meses atrás).
        $status.SignaturesNeverUpdated = $true
    }

    return $status
}


function Get-TFToolkitOtherFirewall {
    <#
    Nomes dos firewalls de outros fabricantes registrados na Central de Segurança e ligados (o mesmo bit 0x1000 de
    productState do antivírus); $null quando a consulta falha. Norton, McAfee, Kaspersky, ESET e outros desligam o
    firewall do Windows e se registram ali, e a própria Segurança do Windows mostra o PC protegido.
    #>
    try {
        $products = @(Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "FirewallProduct" -OperationTimeoutSec 15 -ErrorAction Stop)
    }
    catch {
        return $null
    }

    # A vírgula impede que uma lista vazia vire $null ao sair da função ($null significa "não foi possível ler").
    return , @(
        $products |
            Where-Object { ([int64](Get-TFToolkitJsonValue -Object $_ -Name "productState" -Default 0) -band 0x1000) -ne 0 } |
            ForEach-Object { [string](Get-TFToolkitJsonValue -Object $_ -Name "displayName" -Default "") } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '(?i)^(windows|microsoft)( defender)? firewall|firewall do windows|firewall de (windows|microsoft)' } |
            Select-Object -Unique
    )
}


function Get-TFToolkitFirewallStatus {
    # Um item por perfil de rede (Domain, Private, Public) com Enabled (protegido), Product e Applies (o perfil vale para
    # este PC). $null quando não foi possível ler.
    # ActiveStore é o que vale de fato: a configuração local somada à da política de grupo (GPO) e do MDM da empresa. Sem
    # ela, o Get-NetFirewallProfile lê só a local, que pode dizer "desligado" num PC em que a política liga o firewall (ou
    # o contrário). Se o parâmetro não for aceito, fica a leitura local, melhor que nenhuma.
    try {
        $profiles = @(Invoke-TFToolkitCimCommand -Name "Get-NetFirewallProfile" -Parameters @{ PolicyStore = "ActiveStore" })
    }
    catch {
        # Sem resposta no prazo, a segunda consulta travaria igual.
        if ($_.Exception -is [System.TimeoutException]) { return $null }

        try {
            $profiles = @(Invoke-TFToolkitCimCommand -Name "Get-NetFirewallProfile")
        }
        catch {
            return $null
        }
    }

    if ($profiles.Count -eq 0) {
        return $null
    }

    $status = @(
        foreach ($firewallProfile in $profiles) {
            [PSCustomObject]@{
                Name    = [string](Get-TFToolkitJsonValue -Object $firewallProfile -Name "Name" -Default "")
                Enabled = ([string](Get-TFToolkitJsonValue -Object $firewallProfile -Name "Enabled" -Default "") -eq "True")
                Product = ""
                Applies = $true
            }
        }
    )

    # Com o firewall do Windows desligado num perfil, um firewall de outro fabricante ligado protege esse perfil: sem
    # olhar para ele, a tela, a auditoria e o Início acusariam "firewall desligado" num PC protegido. Os perfis ficam
    # como protegidos (Enabled) e Product diz por quem. Sem resposta da Central de Segurança, vale o que o Windows disse.
    if (@($status | Where-Object { -not $_.Enabled }).Count -gt 0) {
        $others = Get-TFToolkitOtherFirewall

        if ($null -ne $others -and @($others).Count -gt 0) {
            $names = Join-TFToolkitList -Items @($others)

            foreach ($entry in $status) {
                if (-not $entry.Enabled) {
                    $entry.Enabled = $true
                    $entry.Product = $names
                }
            }
        }
    }

    # O perfil Domínio só entra em uso num PC que faz parte de um domínio de empresa: num PC de casa, ele desligado não
    # deixa nenhuma rede sem firewall. Sem conseguir ler, vale como se valesse (melhor um aviso a mais que um a menos).
    $domainOff = @($status | Where-Object { $_.Name -eq "Domain" -and -not $_.Enabled })

    if ($domainOff.Count -gt 0) {
        $system = @(Get-TFToolkitCimOrNull -ClassName "Win32_ComputerSystem") | Select-Object -First 1
        $partOfDomain = Get-TFToolkitJsonValue -Object $system -Name "PartOfDomain" -Default $null

        if ($partOfDomain -is [bool] -and -not $partOfDomain) {
            foreach ($entry in $domainOff) { $entry.Applies = $false }
        }
    }

    return $status
}


function Get-TFToolkitFirewallGaps {
    # Os perfis em que nenhuma rede deste PC fica protegida: desligados e em uso (Get-TFToolkitFirewallStatus). A tela, a
    # auditoria, o Início e o Verificar o PC contam por aqui.
    param ($Firewall)

    return @(@($Firewall) | Where-Object { $null -ne $_ -and -not $_.Enabled -and [bool](Get-TFToolkitJsonValue -Object $_ -Name "Applies" -Default $true) })
}


function Get-TFToolkitFirewallOtherProduct {
    # O firewall de outro fabricante que protege algum perfil (Get-TFToolkitFirewallStatus), ou "".
    param ($Firewall)

    foreach ($entry in @($Firewall)) {
        $product = [string](Get-TFToolkitJsonValue -Object $entry -Name "Product" -Default "")
        if ($product) { return $product }
    }

    return ""
}


function Get-TFToolkitFirewallProfileName {
    param ([string]$Name)

    switch ($Name) {
        "Domain"  { return (Get-TFToolkitText 'Domínio') }
        "Private" { return (Get-TFToolkitText 'Rede privada') }
        "Public"  { return (Get-TFToolkitText 'Rede pública') }
        default   { return $Name }
    }
}


function Get-TFToolkitActiveThreats {
    # Ameaças que o Defender ainda considera ativas. $null quando não foi possível ler.
    try {
        $threats = @(Invoke-TFToolkitCimCommand -Name "Get-MpThreat")
    }
    catch {
        return $null
    }

    # A vírgula impede que uma lista vazia vire $null ao sair da função ($null significa "não foi possível ler").
    return , @(
        $threats |
            Where-Object { [bool](Get-TFToolkitJsonValue -Object $_ -Name "IsActive" -Default $false) } |
            ForEach-Object {
                $name = [string](Get-TFToolkitJsonValue -Object $_ -Name "ThreatName" -Default "")
                if ([string]::IsNullOrWhiteSpace($name)) { $name = (Get-TFToolkitText 'ameaça {0}' "$(Get-TFToolkitJsonValue -Object $_ -Name 'ThreatID' -Default '?')") }
                $name
            } |
            Select-Object -Unique
    )
}


function Get-TFToolkitThreatListText {
    # As ameaças numa lista para ler: o nome curto de cada uma ("Wacatac (trojan)", como no resultado da verificação), sem
    # repetir. O nome completo do Windows Defender, o que se procura na internet, fica nos detalhes técnicos.
    param ([AllowNull()][AllowEmptyCollection()][object[]]$Threats = @())

    return (Join-TFToolkitList -Items @(@($Threats) | Where-Object { $_ } | ForEach-Object { Get-TFToolkitThreatShortName -Name ([string]$_) } | Select-Object -Unique))
}


function New-TFToolkitSecurityFinding {
    # Um ponto de atenção. Id identifica o assunto (a tela e os testes não dependem do texto); Short é o nome curto com
    # que a faixa de resultado lista os pontos ("2 ameaças ativas").
    param (
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet("Warning", "Info")]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Text,

        [string]$Short = ""
    )

    return [PSCustomObject]@{ Id = $Id; Level = $Level; Text = $Text; Short = $Short }
}


function Get-TFToolkitSecurityNextStep {
    <#
    O botão da faixa de resultado para um ponto de atenção (da tela Estado da proteção ou da auditoria), pelo Id: Next é
    o atalho do Windows ou o item do TF-Toolkit que resolve, e Label, o texto do botão; $null quando nenhum lugar resolve
    com um clique (a conta Convidado, a entrada automática, o UAC). Os do antivírus e do firewall abrem direto a página
    certa da Segurança do Windows.
    #>
    param ([AllowEmptyString()][string]$Id)

    $open = (Get-TFToolkitText 'Abrir a Segurança do Windows')

    switch -Regex ($Id) {
        '^(antivirus|realtime|tamper|threats)'  { return [PSCustomObject]@{ Next = "WindowsSecurityThreats"; Label = $open } }
        '^firewall'                             { return [PSCustomObject]@{ Next = "WindowsSecurityFirewall"; Label = $open } }
        '^smartscreen$'                         { return [PSCustomObject]@{ Next = "WindowsSecurity"; Label = $open } }
        '^signatures'                           { return [PSCustomObject]@{ Next = "security.signatures"; Label = (Get-TFToolkitText 'Atualizar as assinaturas') } }
        '^updates$'                             { return [PSCustomObject]@{ Next = "updates.install"; Label = (Get-TFToolkitText 'Instalar as atualizações') } }
        '^windows-support$'                     { return [PSCustomObject]@{ Next = "diagnostics.windows-support"; Label = (Get-TFToolkitText 'Ver o suporte do Windows') } }
        '^smb1$'                                { return [PSCustomObject]@{ Next = "software.features"; Label = (Get-TFToolkitText 'Abrir os recursos do Windows') } }
    }

    return $null
}


function ConvertTo-TFToolkitHeadline {
    # A primeira letra em maiúscula, para um texto curto virar o título da faixa ("antivírus desligado" -> "Antivírus desligado").
    param ([AllowEmptyString()][string]$Text)

    $value = ([string]$Text).Trim()
    if ($value.Length -eq 0) { return "" }

    return $value.Substring(0, 1).ToUpperInvariant() + $value.Substring(1)
}


function Get-TFToolkitSecurityFindings {
    <#
    Os pontos de atenção da proteção, do mais importante ao menos. Level = Warning (agir) ou Info (saber).
    Updates e Threats nulos significam "não foi possível consultar" (ou "não consultado").
    #>
    param (
        [Parameter(Mandatory)]
        $Antivirus,

        $Firewall = $null,
        $Updates = $null,
        $Threats = $null
    )

    $findings = @()

    switch ($Antivirus.Mode) {
        "Off"         { $findings += New-TFToolkitSecurityFinding -Id "antivirus-off" -Level Warning -Short (Get-TFToolkitText 'antivírus desligado') -Text (Get-TFToolkitText 'O antivírus do Windows está desligado e nenhum outro está ligado. Ligue-o em Segurança > Segurança do Windows.') }
        "Unavailable" { $findings += New-TFToolkitSecurityFinding -Id "antivirus-unreadable" -Level Warning -Short (Get-TFToolkitText 'antivírus sem leitura') -Text (Get-TFToolkitText 'Não foi possível ler o estado do antivírus. Confira em Segurança > Segurança do Windows.') }
        "Passive"     { $findings += New-TFToolkitSecurityFinding -Id "antivirus-passive" -Level Warning -Short (Get-TFToolkitText 'Defender em modo passivo') -Text (Get-TFToolkitText 'O Windows Defender está em modo passivo e nenhum outro antivírus ligado foi identificado: o PC pode estar desprotegido. Confira em Segurança > Segurança do Windows.') }
        "Other"       { $findings += New-TFToolkitSecurityFinding -Id "antivirus-other" -Level Info -Text (Get-TFToolkitText 'Outro antivírus protege este PC ({0}); o Windows Defender fica de reserva.' "$(Join-TFToolkitList -Items @($Antivirus.Others))") }
        "Active" {
            if ($Antivirus.RealTime -eq $false) {
                $findings += New-TFToolkitSecurityFinding -Id "realtime-off" -Level Warning -Short (Get-TFToolkitText 'proteção em tempo real desligada') -Text (Get-TFToolkitText 'A proteção em tempo real está desligada. Ligue-a em Segurança > Segurança do Windows.')
            }
        }
    }

    # Assinaturas que nunca foram atualizadas (as que vêm com o Windows, de meses atrás): o mesmo ponto do Início.
    if ($Antivirus.Mode -eq "Active" -and [bool](Get-TFToolkitJsonValue -Object $Antivirus -Name "SignaturesNeverUpdated" -Default $false)) {
        $findings += New-TFToolkitSecurityFinding -Id "signatures-old" -Level Warning -Short (Get-TFToolkitText 'assinaturas nunca atualizadas') -Text (Get-TFToolkitText 'O antivírus nunca foi atualizado. Use Segurança > Atualizar assinaturas do antivírus.')
    }
    elseif ($Antivirus.Mode -eq "Active" -and $null -ne $Antivirus.SignatureAgeDays) {
        $days = [int]$Antivirus.SignatureAgeDays

        if ($days -gt 7) {
            $findings += New-TFToolkitSecurityFinding -Id "signatures-old" -Level Warning -Short (Get-TFToolkitText 'assinaturas com {0} dias' "$days") -Text (Get-TFToolkitText 'As assinaturas do antivírus têm {0} dias. Use Segurança > Atualizar assinaturas do antivírus.' "$days")
        }
        elseif ($days -gt 3) {
            $findings += New-TFToolkitSecurityFinding -Id "signatures-aging" -Level Info -Text (Get-TFToolkitText 'As assinaturas do antivírus têm {0} dias; o normal é atualizarem todo dia.' "$days")
        }
    }

    if ($null -ne $Threats -and @($Threats).Count -gt 0) {
        $count = Format-TFToolkitCount -Count @($Threats).Count -One (Get-TFToolkitText 'ameaça ativa') -Many (Get-TFToolkitText 'ameaças ativas')
        $findings += New-TFToolkitSecurityFinding -Id "threats" -Level Warning -Short $count -Text (Get-TFToolkitText '{0}: {1}. Abra Segurança > Segurança do Windows para ver as ações.' "${count}" "$(Get-TFToolkitThreatListText -Threats @($Threats))")
    }

    if ($null -eq $Firewall) {
        $findings += New-TFToolkitSecurityFinding -Id "firewall-unreadable" -Level Info -Text (Get-TFToolkitText 'Não foi possível ler o estado do firewall.')
    }
    else {
        $off = @(Get-TFToolkitFirewallGaps -Firewall $Firewall | ForEach-Object { Get-TFToolkitFirewallProfileName -Name $_.Name })

        if ($off.Count -gt 0) {
            $where = Join-TFToolkitList -Items $off
            $findings += New-TFToolkitSecurityFinding -Id "firewall-off" -Level Warning -Short (Get-TFToolkitText 'firewall desligado ({0})' "$where") -Text (Get-TFToolkitText 'O firewall está desligado em: {0}. Ligue-o em Segurança > Segurança do Windows.' "$where")
        }

        $otherFirewall = Get-TFToolkitFirewallOtherProduct -Firewall $Firewall

        if ($otherFirewall) {
            $findings += New-TFToolkitSecurityFinding -Id "firewall-other" -Level Info -Text (Get-TFToolkitText 'Outro firewall protege este PC ({0}); o firewall do Windows fica desligado.' "$otherFirewall")
        }
    }

    if ($null -ne $Updates -and $Updates.Count -gt 0) {
        $findings += New-TFToolkitSecurityFinding -Id "updates" -Level Warning -Short (Format-TFToolkitCount -Count $Updates.Count -One (Get-TFToolkitText 'atualização pendente') -Many (Get-TFToolkitText 'atualizações pendentes')) `
            -Text (Get-TFToolkitText '{0}. Use Atualizações > Instalar atualizações do Windows.' "$(Format-TFToolkitCount -Count $Updates.Count -One (Get-TFToolkitText 'atualização do Windows pendente') -Many (Get-TFToolkitText 'atualizações do Windows pendentes'))")
    }

    # Avisos primeiro, mantendo a ordem em que foram encontrados dentro de cada grupo.
    return @(@($findings | Where-Object { $_.Level -eq "Warning" }) + @($findings | Where-Object { $_.Level -ne "Warning" }))
}


function Get-TFToolkitSecurityStatus {
    # A parte rápida do estado da proteção (antivírus, firewall e ameaças), que a tela e o relatório mostram. As
    # atualizações pendentes ficam de fora: a consulta vai até o serviço do Windows Update e demora, então a tela as
    # busca depois (Get-TFToolkitPendingWindowsUpdates) e o relatório nem espera por elas. Findings já vem sem elas.
    $antivirus = Get-TFToolkitAntivirusStatus
    $firewall = Get-TFToolkitFirewallStatus
    $threats = Get-TFToolkitActiveThreats

    return [PSCustomObject]@{
        Antivirus = $antivirus
        Firewall  = $firewall
        Threats   = $threats
        Findings  = @(Get-TFToolkitSecurityFindings -Antivirus $antivirus -Firewall $firewall -Threats $threats)
    }
}


function Get-TFToolkitAntivirusModeText {
    param ([Parameter(Mandatory)]$Antivirus)

    switch ($Antivirus.Mode) {
        "Active"      { return $(if ($Antivirus.RealTime -eq $false) { (Get-TFToolkitText 'Windows Defender ligado, sem proteção em tempo real') } else { (Get-TFToolkitText 'Windows Defender ativo, com proteção em tempo real') }) }
        "Other"       { return (Get-TFToolkitText 'Outro antivírus em uso: {0}' "$(Join-TFToolkitList -Items @($Antivirus.Others))") }
        "Passive"     { return (Get-TFToolkitText 'Windows Defender em modo passivo') }
        "Off"         { return (Get-TFToolkitText 'Desligado') }
        default       { return (Get-TFToolkitText 'Não foi possível ler') }
    }
}


function Get-TFToolkitSignatureText {
    param ([Parameter(Mandatory)]$Antivirus)

    if ($null -eq $Antivirus.SignaturesUpdated) {
        return $null
    }

    $text = "$(Format-TFToolkitDateTime -When $Antivirus.SignaturesUpdated) ($(Format-TFToolkitRelativeTime -When $Antivirus.SignaturesUpdated))"

    if ($Antivirus.SignatureVersion) {
        $text += (Get-TFToolkitText ', versão {0}' "$($Antivirus.SignatureVersion)")
    }

    return $text
}


function Get-TFToolkitScanDateText {
    param ($When)

    if ($null -eq $When) {
        return (Get-TFToolkitText 'Nunca')
    }

    return "$(Format-TFToolkitDateTime -When ([datetime]$When)) ($(Format-TFToolkitRelativeTime -When ([datetime]$When)))"
}


function Get-TFToolkitAntivirusRows {
    <#
    As linhas do antivírus (Label e Value) que a tela Estado da proteção e o relatório mostram, na mesma ordem e com os
    mesmos textos. Assinaturas e verificações são do Windows Defender: aparecem quando ele protege o PC (ou está em modo
    passivo sem outro antivírus identificado), e não ao lado do nome de outro antivírus, que tem as dele. As ameaças que
    o Defender guarda só aparecem, com outro antivírus, se houver alguma. -Brief deixa de fora a verificação completa.
    #>
    param (
        [Parameter(Mandatory)]
        $Antivirus,

        $Threats = $null,

        [switch]$Brief
    )

    $rows = New-Object System.Collections.Generic.List[object]
    # Level pinta o valor na tela (verde, amarelo, vermelho); o relatório usa só o texto.
    $modeLevel = switch ($Antivirus.Mode) { "Active" { $(if ($Antivirus.RealTime -eq $false) { "Warn" } else { "Ok" }) } "Other" { "Ok" } "Passive" { "Warn" } "Off" { "Bad" } default { "Normal" } }
    $rows.Add([PSCustomObject]@{ Label = (Get-TFToolkitText 'Situação'); Value = (Get-TFToolkitAntivirusModeText -Antivirus $Antivirus); Level = $modeLevel })

    if ($Antivirus.Mode -in "Active", "Passive") {
        $signatures = Get-TFToolkitSignatureText -Antivirus $Antivirus
        $age = Get-TFToolkitJsonValue -Object $Antivirus -Name "SignatureAgeDays" -Default $null
        $never = [bool](Get-TFToolkitJsonValue -Object $Antivirus -Name "SignaturesNeverUpdated" -Default $false)
        $rows.Add([PSCustomObject]@{ Label = (Get-TFToolkitText 'Assinaturas'); Value = $(if ($signatures) { $signatures } elseif ($never) { (Get-TFToolkitText 'Nunca atualizadas') } else { (Get-TFToolkitText 'Não foi possível ler') }); Level = $(if ($never -or ($null -ne $age -and [int]$age -gt 7)) { "Warn" } else { "Normal" }) })
    }

    if ($Antivirus.Mode -eq "Active") {
        $rows.Add([PSCustomObject]@{ Label = (Get-TFToolkitText 'Última verificação rápida'); Value = (Get-TFToolkitScanDateText -When $Antivirus.LastQuickScan); Level = "Normal" })

        if (-not $Brief) {
            $rows.Add([PSCustomObject]@{ Label = (Get-TFToolkitText 'Última verificação completa'); Value = (Get-TFToolkitScanDateText -When $Antivirus.LastFullScan); Level = "Normal" })
        }
    }

    if ($null -ne $Threats) {
        $list = @($Threats)

        if ($Antivirus.Mode -ne "Other") {
            # "Nenhuma" em verde só com o Defender examinando: desligado (ou sem tempo real, em modo passivo, sem leitura),
            # a lista vazia não quer dizer que o PC está limpo, só que nada foi registrado.
            $watching = ($Antivirus.Mode -eq "Active" -and $Antivirus.RealTime -ne $false)
            $none = $(if ($watching) { (Get-TFToolkitText 'Nenhuma') } elseif ($Antivirus.Mode -eq "Off") { (Get-TFToolkitText 'Nenhuma registrada (com o antivírus desligado, nada está sendo examinado)') } else { (Get-TFToolkitText 'Nenhuma registrada') })
            $rows.Add([PSCustomObject]@{ Label = (Get-TFToolkitText 'Ameaças ativas'); Value = $(if ($list.Count -eq 0) { $none } else { Get-TFToolkitThreatListText -Threats $list }); Level = $(if ($list.Count -gt 0) { "Bad" } elseif ($watching) { "Ok" } else { "Normal" }) })
        }
        elseif ($list.Count -gt 0) {
            $rows.Add([PSCustomObject]@{ Label = (Get-TFToolkitText 'Ameaças no Defender'); Value = (Get-TFToolkitThreatListText -Threats $list); Level = "Warn" })
        }
    }
    elseif ($Antivirus.Mode -eq "Active") {
        # Com outro antivírus no lugar, o Defender não responder é esperado; com ele ativo, é uma lacuna a dizer.
        $rows.Add([PSCustomObject]@{ Label = (Get-TFToolkitText 'Ameaças ativas'); Value = (Get-TFToolkitText 'Não foi possível consultar'); Level = "Normal" })
    }

    return $rows.ToArray()
}


function Show-TFToolkitSecurityStatus {
    $title = (Get-TFToolkitText 'Estado da proteção')

    Enter-TFToolkitAction -Title $title

    $result = $null
    $search = $null

    try {
        # "Última verificação completa" tem 27 letras: com o tamanho padrão da coluna (24), os dois pontos saíam tortos.
        $labelWidth = 28

        # A consulta ao Windows Update, a mais demorada, começa antes e corre enquanto o antivírus e o firewall são lidos.
        $search = Start-TFToolkitPendingUpdatesSearch

        # O andamento vai na barra: uma linha "Consultando..." ficaria no resumo como se a consulta continuasse.
        Write-Progress -Activity $title -Status (Get-TFToolkitText 'consultando o antivírus e o firewall')

        try {
            $status = Get-TFToolkitSecurityStatus
        }
        finally {
            Write-Progress -Activity $title -Completed
        }

        $antivirus = $status.Antivirus

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Antivírus')

        foreach ($row in @(Get-TFToolkitAntivirusRows -Antivirus $antivirus -Threats $status.Threats)) {
            Write-TFToolkitKeyValue -LabelWidth $labelWidth -Label $row.Label -Value $row.Value -Level $row.Level
        }

        # Os nomes completos das ameaças, os que se procuram na internet, ficam nos detalhes técnicos.
        $threatNames = @(@($status.Threats) | Where-Object { $_ })
        if (@($threatNames | Where-Object { (Get-TFToolkitThreatShortName -Name ([string]$_)) -ne [string]$_ }).Count -gt 0) {
            Write-Host "      $($threatNames -join '; ')" -ForegroundColor DarkGray
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Firewall')

        if ($null -eq $status.Firewall) {
            Write-TFToolkitKeyValue -LabelWidth $labelWidth -Label (Get-TFToolkitText 'Situação') -Value (Get-TFToolkitText 'Não foi possível ler')
        }
        else {
            foreach ($firewallProfile in @($status.Firewall)) {
                $product = [string](Get-TFToolkitJsonValue -Object $firewallProfile -Name "Product" -Default "")
                $applies = [bool](Get-TFToolkitJsonValue -Object $firewallProfile -Name "Applies" -Default $true)
                # O perfil Domínio só vale para um PC num domínio de empresa.
                $value = $(if ($product) { (Get-TFToolkitText 'Protegido por {0}' "$product") } elseif ($firewallProfile.Enabled) { (Get-TFToolkitText 'Ligado') } elseif (-not $applies) { (Get-TFToolkitText 'Desligado (não vale para este PC)') } else { (Get-TFToolkitText 'Desligado') })
                $level = $(if ($firewallProfile.Enabled) { "Ok" } elseif (-not $applies) { "Normal" } else { "Bad" })
                Write-TFToolkitKeyValue -LabelWidth $labelWidth -Label (Get-TFToolkitFirewallProfileName -Name $firewallProfile.Name) -Value $value -Level $level
            }
        }

        # O que já se sabe aparece antes; a consulta ao Windows Update, que pode demorar, vem por último.
        Write-TFToolkitSection -Title (Get-TFToolkitText 'Windows Update')
        Write-Progress -Activity (Get-TFToolkitText 'Windows Update') -Status (Get-TFToolkitText 'procurando atualizações pendentes (pode levar até um minuto e meio)')

        try {
            $updates = Get-TFToolkitPendingWindowsUpdates -Search $search
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Windows Update') -Completed
        }

        if ($null -eq $updates) {
            Write-TFToolkitKeyValue -LabelWidth $labelWidth -Label (Get-TFToolkitText 'Atualizações pendentes') -Value (Get-TFToolkitText 'Não foi possível consultar (o Windows Update demorou ou está indisponível)')
        }
        elseif ($updates.Count -eq 0) {
            Write-TFToolkitKeyValue -LabelWidth $labelWidth -Label (Get-TFToolkitText 'Atualizações pendentes') -Value (Get-TFToolkitText 'Nenhuma') -Level Ok
        }
        else {
            Write-TFToolkitKeyValue -LabelWidth $labelWidth -Label (Get-TFToolkitText 'Atualizações pendentes') -Value $updates.Count -Level Warn

            # Os nomes como mensagens: na janela, entram no resumo (linhas soltas só apareceriam nos detalhes técnicos).
            foreach ($updateTitle in @($updates.Titles | Select-Object -First 5)) {
                Write-TFToolkitStatus -Type Info -Message $updateTitle
            }

            if ($updates.Count -gt 5) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'E mais {0}.' "$(Format-TFToolkitCount -Count ($updates.Count - 5) -One (Get-TFToolkitText 'atualização') -Many (Get-TFToolkitText 'atualizações'))")
            }
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')

        $findings = @(Get-TFToolkitSecurityFindings -Antivirus $antivirus -Firewall $status.Firewall -Updates $updates -Threats $status.Threats)

        # O que não pôde ser lido não conta como "em ordem": dizer que não há ponto de atenção sem ter olhado seria
        # enganoso. Também não é um problema do PC: a faixa o diz à parte, depois dos pontos de atenção. O antivírus sem
        # leitura tem a própria mensagem (sem ele, nem se sabe se o PC está protegido); o resto vai numa frase só.
        $antivirusUnread = ($antivirus.Mode -eq "Unavailable")
        $unread = @()
        if ($null -eq $status.Firewall) { $unread += (Get-TFToolkitText 'o firewall') }
        if ($null -eq $status.Threats -and $antivirus.Mode -eq "Active") { $unread += (Get-TFToolkitText 'as ameaças ativas') }
        if ($null -eq $updates) { $unread += (Get-TFToolkitText 'o Windows Update') }

        $problems = @($findings | Where-Object { $_.Level -eq "Warning" -and $_.Id -ne "antivirus-unreadable" })
        $unreadText = Join-TFToolkitList -Items $unread
        $check = $(if ($null -eq $status.Firewall) { (Get-TFToolkitText ' Confira em Segurança > Segurança do Windows.') } else { "" })

        if ($problems.Count -eq 0 -and -not $antivirusUnread -and $unread.Count -eq 0) {
            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Nenhum ponto de atenção na proteção do PC.')
        }
        elseif ($problems.Count -eq 0 -and -not $antivirusUnread) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Nenhum ponto de atenção no que foi lido, mas não foi possível consultar {0}.{1}' "$unreadText" "$check")
        }

        # A falta de leitura do firewall já está na frase acima (ou na abaixo): não repete.
        foreach ($finding in @($findings | Where-Object { $_.Id -ne "firewall-unreadable" })) {
            Write-TFToolkitStatus -Type $finding.Level -Message $finding.Text
        }

        if (($problems.Count -gt 0 -or $antivirusUnread) -and $unread.Count -gt 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Também não foi possível consultar {0}.{1}' "$unreadText" "$check")
        }

        if ($antivirusUnread) {
            $unread = @((Get-TFToolkitText 'o antivírus')) + $unread
            $unreadText = Join-TFToolkitList -Items $unread
        }

        # A faixa diz o que foi encontrado, e não só a última mensagem.
        if ($problems.Count -gt 0) {
            $detail = "$(Format-TFToolkitCount -Count $problems.Count -One (Get-TFToolkitText 'ponto de atenção') -Many (Get-TFToolkitText 'pontos de atenção')): $(Join-TFToolkitList -Items @($problems | ForEach-Object { $_.Short }))"
            if ($unread.Count -gt 0) { $detail += (Get-TFToolkitText '; não foi possível consultar {0}' "$unreadText") }

            $result = New-TFToolkitResult -Kind Warning -Detail $detail
        }
        elseif ($unread.Count -gt 0) {
            $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'nenhum ponto de atenção no que foi lido; não foi possível consultar {0}' "$unreadText")
        }
        else {
            $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'nenhum ponto de atenção')
        }

        # A faixa da janela: o título diz o que pede ação (um ponto pelo nome, vários pela conta), em vermelho quando o PC
        # está sem proteção (antivírus ou tempo real desligado, ameaça ativa, firewall desligado na rede pública), e o
        # botão leva aonde se resolve o mais grave. Antes, era sempre o amarelo de "Concluído com ressalvas", com todos os
        # pontos numa frase só.
        $publicOff = ($null -ne $status.Firewall -and @(Get-TFToolkitFirewallGaps -Firewall $status.Firewall | Where-Object { $_.Name -eq "Public" }).Count -gt 0)
        # Com outro antivírus no lugar, as ameaças que o Defender guarda são ressalva (quem decide é o outro), como na auditoria.
        $severe = @($problems | Where-Object { $_.Id -in @("antivirus-off", "realtime-off") -or ($_.Id -eq "threats" -and $antivirus.Mode -ne "Other") -or ($_.Id -eq "firewall-off" -and $publicOff) })
        # Select-Object em vez de [0]: sem nenhum ponto, a lista vem vazia (e, com Set-StrictMode, o índice dá erro).
        $first = @(@($severe) + @($problems) + @($findings | Where-Object { $_.Id -eq "antivirus-unreadable" })) | Select-Object -First 1
        $step = $(if ($null -ne $first) { Get-TFToolkitSecurityNextStep -Id $first.Id } else { $null })
        # Com a primeira letra em maiúscula: em inglês a frase começa pelo que faltou ("The antivirus could not be queried.").
        $unreadNote = $(if ($unread.Count -gt 0) { ConvertTo-TFToolkitHeadline -Text (Get-TFToolkitText 'Não foi possível consultar {0}.' "$unreadText") } else { "" })

        # Sem nenhum ponto pedindo ação, o firewall sem leitura também tem o botão para conferir.
        if ($null -eq $step -and $null -eq $status.Firewall) { $step = Get-TFToolkitSecurityNextStep -Id "firewall-unreadable" }

        if ($problems.Count -eq 1) {
            $headline = ConvertTo-TFToolkitHeadline -Text $problems[0].Short
            $note = (@([string]$problems[0].Text, $unreadNote) | Where-Object { $_ }) -join " "
        }
        elseif ($problems.Count -gt 1) {
            $headline = Format-TFToolkitCount -Count $problems.Count -One (Get-TFToolkitText 'ponto de atenção') -Many (Get-TFToolkitText 'pontos de atenção')
            $note = (@("$(ConvertTo-TFToolkitHeadline -Text (Join-TFToolkitList -Items @($problems | ForEach-Object { $_.Short }))).", $unreadNote) | Where-Object { $_ }) -join " "
        }
        elseif ($antivirusUnread) {
            # Sem saber se há um antivírus protegendo, "nenhum ponto de atenção" não é o que importa: o título diz o que faltou.
            $others = @($unread | Select-Object -Skip 1)
            $headline = ConvertTo-TFToolkitHeadline -Text (Get-TFToolkitText 'antivírus sem leitura')
            $note = (@((Get-TFToolkitText 'Não foi possível ler o estado do antivírus. Confira em Segurança > Segurança do Windows.'), $(if ($others.Count -gt 0) { ConvertTo-TFToolkitHeadline -Text (Get-TFToolkitText 'Não foi possível consultar {0}.' "$(Join-TFToolkitList -Items $others)") })) | Where-Object { $_ }) -join " "
        }
        elseif ($unread.Count -gt 0) {
            $headline = (Get-TFToolkitText 'Nenhum ponto de atenção no que foi lido')
            $note = $unreadNote
        }
        else {
            $headline = (Get-TFToolkitText 'Nenhum ponto de atenção')
            $note = (Get-TFToolkitText 'Antivírus, firewall e atualizações do Windows em ordem.')
        }

        $tone = $(if ($severe.Count -gt 0) { "Bad" } elseif ($problems.Count -gt 0 -or $unread.Count -gt 0) { "Warn" } else { "" })
        [void](Set-TFToolkitResultView -Result $result -Headline $headline -Note $note -Tone $tone -Next $(if ($null -ne $step) { $step.Next } else { "" }) -NextLabel $(if ($null -ne $step) { $step.Label } else { "" }))
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro ao consultar a proteção do PC: {0}' "$($_.Exception.Message)")
        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }
    finally {
        # Sem chegar a pedir a resposta (um erro antes dela, ou o Parar), a consulta não fica rodando.
        Stop-TFToolkitInBackground -Task $search
    }

    $result.Etapa = $title
    Exit-TFToolkitAction -Result $result
}


# ---------------------------------------------------------------------------
# Assinaturas e verificação
# ---------------------------------------------------------------------------

function Test-TFToolkitDefenderReady {
    <#
    Confere se dá para usar o Defender agora: Administrador, comandos disponíveis e o Defender sendo quem protege o PC.
    Devolve Ready e, quando não está pronto, o Result que a ação deve devolver (já com a explicação na tela e o título da
    faixa da janela). Antivirus é o estado lido na conferência ($null se parou antes, por falta de Administrador), para
    quem chama não ler de novo.
    Sem nada verificado, o resultado diz o estado do PC, como Estado da proteção e o Início: com outro antivírus no lugar
    é "Ignorado" (é com ele); o Defender desligado é falha (o PC está sem antivírus); em modo passivo ou sem resposta é
    ressalva (o PC pode estar desprotegido).
    #>
    if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Esta ação exige privilégios de Administrador.'))) {
        return [PSCustomObject]@{ Ready = $false; Result = (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador')); Antivirus = $null }
    }

    $antivirus = Get-TFToolkitAntivirusStatus
    $open = (Get-TFToolkitText 'Abrir a Segurança do Windows')
    $result = $null

    switch ([string]$antivirus.Mode) {
        "Active" {
            return [PSCustomObject]@{ Ready = $true; Result = $null; Antivirus = $antivirus }
        }
        "Other" {
            # Com outro antivírus, o Defender fica desligado ou em modo passivo: verificar e atualizar é com o outro.
            $names = @($antivirus.Others | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $list = Join-TFToolkitList -Items $names

            if ($names.Count -gt 1) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Outros antivírus protegem este PC ({0}): use um deles para verificar o PC.' "$list")
                $headline = (Get-TFToolkitText 'Outros antivírus protegem este PC')
                $note = (Get-TFToolkitText 'Use um deles para verificar o PC: {0}.' "$list")
            }
            elseif ($names.Count -eq 1) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Outro antivírus protege este PC ({0}): use-o para verificar o PC.' "$list")
                $headline = (Get-TFToolkitText 'Outro antivírus protege este PC')
                $note = (Get-TFToolkitText 'Use o {0} para verificar o PC.' "$list")
            }
            else {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Outro antivírus protege este PC: use-o para verificar o PC.')
                $headline = (Get-TFToolkitText 'Outro antivírus protege este PC')
                $note = (Get-TFToolkitText 'Use-o para verificar o PC.')
            }

            $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'outro antivírus em uso')) -Headline $headline -Note $note
        }
        "Passive" {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows Defender está em modo passivo e nenhum outro antivírus ligado foi encontrado. Confira em Segurança > Segurança do Windows.')
            $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o Windows Defender está em modo passivo')) `
                -Headline (Get-TFToolkitText 'O Windows Defender está em modo passivo') -Note (Get-TFToolkitText 'Nenhum outro antivírus ligado foi encontrado: o PC pode estar sem proteção.') `
                -Tone Warn -Next "WindowsSecurityThreats" -NextLabel $open
        }
        "Off" {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O antivírus do Windows está desligado e nenhum outro está ligado. Ligue-o em Segurança > Segurança do Windows.')
            $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o antivírus está desligado')) `
                -Headline (Get-TFToolkitText 'Antivírus desligado') -Note (Get-TFToolkitText 'Nenhum antivírus protege o PC. Ligue o Windows Defender na Segurança do Windows.') `
                -Tone Bad -Next "WindowsSecurityThreats" -NextLabel $open
        }
        default {
            if ([bool](Get-TFToolkitJsonValue -Object $antivirus -Name "DefenderRead" -Default $false)) {
                # O Defender respondeu (desligado ou passivo), mas a Central de Segurança não: não dá para dizer se outro
                # antivírus protege o PC, e "o serviço não respondeu" seria falso.
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows Defender não está protegendo o PC, e não foi possível ver se outro antivírus está. Confira em Segurança > Segurança do Windows.')
                $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'não foi possível confirmar qual antivírus protege o PC')) `
                    -Headline (Get-TFToolkitText 'Não foi possível confirmar a proteção') -Note (Get-TFToolkitText 'O Windows Defender não está protegendo o PC, e não foi possível ver se outro antivírus está.') `
                    -Tone Warn -Next "WindowsSecurityThreats" -NextLabel $open
            }
            else {
                # Os comandos do Defender podem faltar neste Windows; o mais comum é o serviço parado.
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows Defender não respondeu. Confira a proteção em Segurança > Segurança do Windows.')
                $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o Windows Defender não respondeu')) `
                    -Headline (Get-TFToolkitText 'O Windows Defender não respondeu') -Note (Get-TFToolkitText 'Confira a proteção na Segurança do Windows.') `
                    -Tone Warn -Next "WindowsSecurityThreats" -NextLabel $open
            }
        }
    }

    return [PSCustomObject]@{ Ready = $false; Result = $result; Antivirus = $antivirus }
}


function Test-TFToolkitMmpcFallback {
    # Se o Defender pode baixar as assinaturas direto da Microsoft (MMPC) quando o caminho normal falha. Sem nada
    # configurado, a ordem de fontes do Windows termina no MMPC; uma empresa que o tirou da lista tem os motivos dela.
    $order = [string](Get-TFToolkitDefenderPreference -Name "SignatureFallbackOrder")

    return ([string]::IsNullOrWhiteSpace($order) -or $order -match '(?i)\bMMPC\b')
}


function Invoke-TFToolkitSignatureUpdate {
    <#
    Atualiza as assinaturas do Defender e devolve um TFToolkit.Result. Não abre nem fecha a ação (quem chama faz isso).
    -AssumeReady pula a conferência de Test-TFToolkitDefenderReady quando quem chama já a fez; -Current traz então o
    estado do antivírus que essa conferência leu (sem ele, é lido aqui). Quando a atualização não dá certo, Data.Caveat é
    a frase que explica isso na faixa do Verificar vírus.
    #>
    param (
        [switch]$AssumeReady,
        $Current = $null
    )

    if (-not $AssumeReady) {
        $ready = Test-TFToolkitDefenderReady

        if (-not $ready.Ready) {
            return $ready.Result
        }

        $Current = $ready.Antivirus
    }

    if ($null -eq $Current) {
        $Current = Get-TFToolkitAntivirusStatus
    }

    $before = [string]$Current.SignatureVersion

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Atualização do antivírus')
    Write-TFToolkitCommand -Command "Update-MpSignature"

    # O andamento vai na barra: uma linha "Baixando..." ficaria no resumo depois de terminado.
    Write-Progress -Activity (Get-TFToolkitText 'Windows Defender') -Status (Get-TFToolkitText 'baixando as assinaturas mais recentes')

    $failure = $null
    $after = $null

    try {
        try {
            [void](Update-MpSignature -ErrorAction Stop)
        }
        catch {
            $failure = $_
        }

        if ($null -eq $failure) {
            $after = Get-TFToolkitAntivirusStatus
        }

        # Pelo caminho normal (o Windows Update), a atualização falha com o Windows Update desligado ou quebrado, e o
        # próprio Defender só tenta a Microsoft depois de 7 dias sem assinaturas novas. Uma segunda tentativa, direto da
        # Microsoft, resolve esses casos; só o resultado final aparece.
        $stale = ($null -ne $after -and $null -ne $after.SignatureAgeDays -and [int]$after.SignatureAgeDays -gt 3)

        if (($null -ne $failure -or $stale) -and (Test-TFToolkitMmpcFallback)) {
            Write-TFToolkitCommand -Command "Update-MpSignature -UpdateSource MMPC"

            try {
                [void](Update-MpSignature -UpdateSource MMPC -ErrorAction Stop)
                $failure = $null
                $after = Get-TFToolkitAntivirusStatus
            }
            catch {
                Write-Host (Get-TFToolkitText '      A segunda tentativa, direto da Microsoft, também falhou: {0}.' "$(Get-TFToolkitDefenderErrorText -ErrorRecord $_)") -ForegroundColor DarkGray
            }
        }
    }
    finally {
        Write-Progress -Activity (Get-TFToolkitText 'Windows Defender') -Completed
    }

    if ($null -ne $failure) {
        $info = Get-TFToolkitDefenderErrorInfo -ErrorRecord $failure
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O antivírus não foi atualizado: {0}.' "$($info.Full)")

        # "Confira a internet" só quando o erro é de conexão: com outro motivo, despistaria.
        if ($info.Network) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Confira a conexão com a internet e tente de novo.')
        }

        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o antivírus não foi atualizado: {0}' "$($info.Text)") -Data @{ Caveat = (Get-TFToolkitText 'O antivírus não foi atualizado: {0}.' "$($info.Text)") })
    }

    if ($null -eq $after.SignatureAgeDays) {
        # O Windows não devolveu a data das assinaturas: sem ela não dá para dizer "em dia".
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows não informou a data das assinaturas; confira em Segurança > Segurança do Windows.')
        return (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'não foi possível confirmar a data das assinaturas') -Data @{ SignatureVersion = $after.SignatureVersion; Caveat = (Get-TFToolkitText 'Não foi possível confirmar se o antivírus está atualizado.') })
    }

    if ($after.SignatureAgeDays -gt 3) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O antivírus continua desatualizado: as assinaturas têm {0} dias.' "$($after.SignatureAgeDays)")
        Write-Host (Get-TFToolkitText '      Assinaturas: {0}.' "$(Get-TFToolkitSignatureText -Antivirus $after)") -ForegroundColor DarkGray
        return (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'as assinaturas continuam com {0} dias' "$($after.SignatureAgeDays)") -Data @{ SignatureVersion = $after.SignatureVersion; Caveat = (Get-TFToolkitText 'As assinaturas do antivírus continuam com {0} dias.' "$($after.SignatureAgeDays)") })
    }

    $changed = ($before -and $after.SignatureVersion -and $before -ne $after.SignatureVersion)
    $same = ($before -and $before -eq $after.SignatureVersion)

    # A linha do resumo é curta; a data e as versões ficam nos detalhes técnicos.
    Write-TFToolkitStatus -Type Success -Message $(if ($same) { (Get-TFToolkitText 'O antivírus já estava atualizado.') } else { (Get-TFToolkitText 'Antivírus atualizado.') })
    Write-Host $(if ($changed) { (Get-TFToolkitText '      Assinaturas: {0}; antes: {1}.' "$(Get-TFToolkitSignatureText -Antivirus $after)" "$before") } else { (Get-TFToolkitText '      Assinaturas: {0}.' "$(Get-TFToolkitSignatureText -Antivirus $after)") }) -ForegroundColor DarkGray

    # A faixa diz se veio algo novo: com as assinaturas já em dia, o Windows não baixa nada, e isso também é "em dia".
    $detail = $(
        if ($changed) { (Get-TFToolkitText 'assinaturas atualizadas agora') }
        elseif ($same) { (Get-TFToolkitText 'as assinaturas já estavam em dia') }
        else { (Get-TFToolkitText 'assinaturas em dia') }
    )

    return (New-TFToolkitResult -Kind Ok -Detail $detail -Data @{ SignatureVersion = $after.SignatureVersion })
}


function Get-TFToolkitThreatStatusText {
    <#
    O que o Defender fez com uma ameaça (ThreatStatusID de Get-MpThreatDetection), em poucas palavras, e Resolved, se ela
    já não oferece risco. 2 limpa, 3 em quarentena, 4 removida e 6 bloqueada estão resolvidas; 5 é a ameaça que alguém
    permitiu; 1 (detectada), as falhas (101 a 107) e o que o Defender não informou pedem ação.
    #>
    param ($StatusId)

    $id = -1
    if ($null -ne $StatusId) { [void][int]::TryParse([string]$StatusId, [ref]$id) }

    switch ($id) {
        2 { return [PSCustomObject]@{ Text = (Get-TFToolkitText 'limpa'); Resolved = $true } }
        3 { return [PSCustomObject]@{ Text = (Get-TFToolkitText 'em quarentena'); Resolved = $true } }
        4 { return [PSCustomObject]@{ Text = (Get-TFToolkitText 'removida'); Resolved = $true } }
        6 { return [PSCustomObject]@{ Text = (Get-TFToolkitText 'bloqueada'); Resolved = $true } }
        5 { return [PSCustomObject]@{ Text = (Get-TFToolkitText 'liberada por alguém'); Resolved = $false } }
        { $_ -in 101, 102, 103, 104, 105, 107 } { return [PSCustomObject]@{ Text = (Get-TFToolkitText 'não resolvida'); Resolved = $false } }
        1 { return [PSCustomObject]@{ Text = (Get-TFToolkitText 'pede ação'); Resolved = $false } }
        default { return [PSCustomObject]@{ Text = (Get-TFToolkitText 'situação desconhecida'); Resolved = $false } }
    }
}


function Get-TFToolkitDefenderNeeds {
    <#
    O que o Windows Defender ainda pede para terminar o serviço, pelos bits que ele publica: Reboot, OfflineScan,
    FullScan e Manual. DetectionMask é o AdditionalActionsBitMask de uma detecção (4 verificação completa, 8 reiniciar, 16
    ação manual, 32768 verificação offline; um bit desconhecido conta como ação manual); ComputerState é o do PC inteiro,
    de Get-MpComputerStatus (1 verificação completa, 2 reiniciar, 4 ação manual, 8 verificação offline).
    #>
    param (
        [int64]$DetectionMask = 0,
        [int64]$ComputerState = 0
    )

    $needs = @()

    if (($DetectionMask -band 8) -ne 0 -or ($ComputerState -band 2) -ne 0) { $needs += "Reboot" }
    if (($DetectionMask -band 32768) -ne 0 -or ($ComputerState -band 8) -ne 0) { $needs += "OfflineScan" }
    if (($DetectionMask -band 4) -ne 0 -or ($ComputerState -band 1) -ne 0) { $needs += "FullScan" }
    if (($DetectionMask -band 16) -ne 0 -or ($ComputerState -band 4) -ne 0 -or ($DetectionMask -band (-bnot [int64]32796)) -ne 0) { $needs += "Manual" }

    # Quem chama põe a lista em @(...): nenhuma é uma lista vazia.
    return $needs
}


function Get-TFToolkitDefenderNeedText {
    # O que completa "o Windows Defender pede ...": "para reiniciar o PC", "a verificação completa"...
    param ([AllowEmptyCollection()][string[]]$Needs = @())

    $texts = @(
        foreach ($need in @($Needs)) {
            switch ($need) {
                "Reboot" { (Get-TFToolkitText 'para reiniciar o PC') }
                "OfflineScan" { (Get-TFToolkitText 'a verificação offline') }
                "FullScan" { (Get-TFToolkitText 'a verificação completa') }
                default { (Get-TFToolkitText 'uma ação sua') }
            }
        }
    )

    return (Join-TFToolkitList -Items @($texts | Select-Object -Unique))
}


function Get-TFToolkitThreatShortName {
    <#
    O nome de uma ameaça como a pessoa lê: "Trojan:Win32/Wacatac.H!ml" vira "Wacatac (trojan)". O nome completo do
    Windows Defender, o que se procura na internet, fica nos detalhes técnicos. Fora desse formato, o nome como veio.
    #>
    param ([AllowEmptyString()][string]$Name)

    if ($Name -notmatch '^(?<category>[A-Za-z]+):[^/:]+/(?<family>[^.!/]+)') { return $Name }

    $family = $Matches["family"]
    $category = $Matches["category"]

    $kind = switch -Regex ($category) {
        '^(?i)ransom' { (Get-TFToolkitText 'ransomware'); break }
        '^(?i)(trojanspy|spyware|pws|keylogger)$' { "spyware"; break }
        '^(?i)trojan' { (Get-TFToolkitText 'trojan'); break }
        '^(?i)backdoor$' { "backdoor"; break }
        '^(?i)worm$' { "worm"; break }
        '^(?i)virus$' { (Get-TFToolkitText 'vírus'); break }
        '^(?i)(pua|softwarebundler|app$)' { (Get-TFToolkitText 'programa indesejado'); break }
        '^(?i)behavior$' { (Get-TFToolkitText 'comportamento suspeito'); break }
        '^(?i)(hacktool|virtool)$' { (Get-TFToolkitText 'ferramenta de invasão'); break }
        '^(?i)exploit$' { "exploit"; break }
        '^(?i)(adware|browsermodifier)$' { "adware"; break }
        default { "" }
    }

    if ($kind) { return "$family ($kind)" }

    return $family
}


function Get-TFToolkitDetectionIds {
    <#
    Os DetectionID das detecções que o Windows Defender já guarda. Lidos antes de uma verificação, separam o que ela achou
    do que já estava lá, sem depender do relógio (um ajuste da hora ou o horário de verão no meio dela). $null quando não
    foi possível ler.
    #>
    try {
        $all = @(Invoke-TFToolkitCimCommand -Name "Get-MpThreatDetection")
    }
    catch {
        return $null
    }

    # A vírgula impede que uma lista vazia vire $null ao sair da função ($null significa "não foi possível ler").
    return , @($all | ForEach-Object { [string](Get-TFToolkitJsonValue -Object $_ -Name "DetectionID" -Default "") } | Where-Object { $_ })
}


function Get-TFToolkitScanDetections {
    <#
    O que a verificação achou: Found, um item por ameaça detectada por ela (ThreatID, Name, ShortName, Resources, Status,
    Resolved e Needs, o que o Defender ainda pede), e Leftover, as ameaças de antes que o Defender ainda considera ativas
    (sem as achadas agora). $null se o Windows não deixou consultar.
    Waiting diz que o Defender já agiu e só espera um passo do PC (Needs).
    Uma detecção é desta verificação quando o DetectionID dela não estava em Known (lido antes de começar). Sem o
    DetectionID, vale a hora da detecção (InitialDetectionTime, comparada em UTC): a última mudança de uma detecção antiga
    também pode ser alguém limpando-a na Segurança do Windows, e ela não foi achada por esta verificação.
    #>
    param (
        [Parameter(Mandatory)]
        [datetime]$Since,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Known = $null
    )

    try {
        $detections = @(Invoke-TFToolkitCimCommand -Name "Get-MpThreatDetection")
    }
    catch {
        return $null
    }

    $sinceUtc = $Since.ToUniversalTime()

    $recent = @(
        $detections | Where-Object {
            $detectionId = [string](Get-TFToolkitJsonValue -Object $_ -Name "DetectionID" -Default "")

            if ($null -ne $Known -and $detectionId) { return ($Known -notcontains $detectionId) }

            $when = Get-TFToolkitJsonValue -Object $_ -Name "InitialDetectionTime" -Default $null
            return ($when -is [datetime] -and $when.ToUniversalTime() -ge $sinceUtc)
        }
    )

    # Os nomes e as ameaças ainda ativas numa consulta só. Sem ela (o Defender não respondeu), a ameaça fica com o Id e as
    # de antes, sem leitura: perguntar o nome de uma em uma esperaria o mesmo prazo de novo a cada ameaça.
    $names = @{}
    $active = @()
    $threatsRead = $false

    try {
        foreach ($threat in @(Invoke-TFToolkitCimCommand -Name "Get-MpThreat")) {
            $id = [string](Get-TFToolkitJsonValue -Object $threat -Name "ThreatID" -Default "")
            $name = [string](Get-TFToolkitJsonValue -Object $threat -Name "ThreatName" -Default "")
            if ($id -and $name) { $names[$id] = $name }

            if ([bool](Get-TFToolkitJsonValue -Object $threat -Name "IsActive" -Default $false)) { $active += $threat }
        }

        $threatsRead = $true
    }
    catch {
        $threatsRead = $false
    }

    # A mais recente de cada ameaça diz o que o Defender fez por último.
    $lastChange = {
        param ($Detection)

        $latest = $null

        foreach ($field in @("InitialDetectionTime", "LastThreatStatusChangeTime", "RemediationTime")) {
            $when = Get-TFToolkitJsonValue -Object $Detection -Name $field -Default $null
            if ($when -is [datetime] -and ($null -eq $latest -or $when -gt $latest)) { $latest = $when }
        }

        $latest
    }

    $found = @()

    foreach ($group in @($recent | Group-Object -Property { [string](Get-TFToolkitJsonValue -Object $_ -Name "ThreatID" -Default "") })) {
        $latest = $group.Group | Sort-Object -Property { & $lastChange $_ } -Descending | Select-Object -First 1
        $resources = @($group.Group | ForEach-Object { Get-TFToolkitJsonValue -Object $_ -Name "Resources" -Default @() } | ForEach-Object { $_ } | Select-Object -Unique)
        $threatId = [string](Get-TFToolkitJsonValue -Object $latest -Name "ThreatID" -Default "")
        $status = Get-TFToolkitThreatStatusText -StatusId (Get-TFToolkitJsonValue -Object $latest -Name "ThreatStatusID" -Default $null)

        # Resolvida pela situação, mas com a ação mal-sucedida ou com outra ação pedida (reiniciar, verificação completa
        # ou offline): ainda não está resolvida, e a linha diz o que falta.
        $actionOk = Get-TFToolkitJsonValue -Object $latest -Name "ActionSuccess" -Default $null
        $mask = 0L
        [void][int64]::TryParse([string](Get-TFToolkitJsonValue -Object $latest -Name "AdditionalActionsBitMask" -Default 0), [ref]$mask)
        $needs = @(Get-TFToolkitDefenderNeeds -DetectionMask $mask)
        $waiting = $false

        if ($status.Resolved -and $actionOk -eq $false) {
            $status = [PSCustomObject]@{ Text = (Get-TFToolkitText 'não resolvida'); Resolved = $false }
        }
        elseif ($status.Resolved -and $needs.Count -gt 0) {
            # O Defender agiu e só espera um passo do PC: reiniciar, a verificação completa ou a offline.
            $status = [PSCustomObject]@{ Text = (Get-TFToolkitText 'pede {0}' "$(Get-TFToolkitDefenderNeedText -Needs $needs)"); Resolved = $false }
            $waiting = $true
        }

        $name = $(if ($names.ContainsKey($threatId)) { $names[$threatId] } else { (Get-TFToolkitText 'ameaça {0}' "$(if ($threatId) { $threatId } else { '?' })") })

        $found += [PSCustomObject]@{
            ThreatID  = $threatId
            Name      = $name
            ShortName = (Get-TFToolkitThreatShortName -Name $name)
            Resources = @($resources)
            Status    = $status.Text
            Resolved  = [bool]$status.Resolved
            Needs     = @($needs)
            Waiting   = $waiting
        }
    }

    # Uma ameaça de antes, ainda ativa, não aparece como detecção nova: dizer só "nenhuma ameaça" (ou "resolvida") seria
    # enganoso. As achadas agora não entram duas vezes.
    $foundIds = @($found | ForEach-Object { [string]$_.ThreatID })
    $leftover = @()

    if ($threatsRead) {
        foreach ($threat in $active) {
            $id = [string](Get-TFToolkitJsonValue -Object $threat -Name "ThreatID" -Default "")
            if ($id -and $foundIds -contains $id) { continue }

            $name = [string](Get-TFToolkitJsonValue -Object $threat -Name "ThreatName" -Default "")
            if ([string]::IsNullOrWhiteSpace($name)) { $name = (Get-TFToolkitText 'ameaça {0}' "$(if ($id) { $id } else { '?' })") }

            $leftover += [PSCustomObject]@{
                ThreatID  = $id
                Name      = $name
                ShortName = (Get-TFToolkitThreatShortName -Name $name)
                Resources = @(Get-TFToolkitJsonValue -Object $threat -Name "Resources" -Default @() | ForEach-Object { $_ })
                Status    = (Get-TFToolkitText 'ativa desde antes')
                Resolved  = $false
                Needs     = @()
                Waiting   = $false
            }
        }
    }

    return [PSCustomObject]@{ Found = @($found); Leftover = @($leftover) }
}


function ConvertTo-TFToolkitThreatResourceText {
    <#
    Onde a ameaça estava, como o Defender guarda ("file:_C:\pasta\arquivo.exe", "containerfile:_..."): sem o prefixo do
    tipo, que não diz nada para a pessoa. Um arquivo baixado ("webfile:_C:\...|https://site/a.exe|pid:123,...") fica só
    com o caminho; um processo ou um comportamento ("process:_pid:4321,ProcessStart:...", "behavior:_pid:4321:7378...")
    vira "programa em execução (processo 4321)".
    #>
    param ([AllowEmptyString()][string]$Resource)

    $text = [string]$Resource

    if ($text -match '^(?i)(process|behavior):_pid:([0-9]+)') { return (Get-TFToolkitText 'programa em execução (processo {0})' "$($Matches[2])") }

    $text = ($text -replace '^(?i)[a-z]+:_', '')
    if ($text.Contains("|")) { $text = $text.Substring(0, $text.IndexOf("|")) }

    return $text.Trim()
}


function Write-TFToolkitThreatLine {
    <#
    Uma linha curta por ameaça no resumo: o nome legível, o que o Defender fez e o arquivo ("Wacatac (trojan) · em
    quarentena · setup.exe e mais 2"). O nome completo e os caminhos inteiros vão para os detalhes técnicos. A resolvida
    tem o ícone de feito; a que ainda pede ação, o de erro.
    #>
    param ([Parameter(Mandatory)]$Threat)

    $places = @($Threat.Resources | ForEach-Object { ConvertTo-TFToolkitThreatResourceText -Resource ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
    $line = "$($Threat.ShortName) · $($Threat.Status)"

    if ($places.Count -gt 0) {
        $first = [string]$places[0]

        # Só o nome do arquivo (as barras do Windows, também quando o texto vem de outro sistema).
        if ($first -notlike (Get-TFToolkitText 'programa em execução (processo {0})' '*')) {
            $segments = @($first -split '[\\/]' | Where-Object { $_ })
            if ($segments.Count -gt 0) { $first = [string]$segments[$segments.Count - 1] }
        }

        $line += " · $first"
        if ($places.Count -gt 1) { $line += (Get-TFToolkitText ' e mais {0}' "$($places.Count - 1)") }
    }

    Write-TFToolkitStatus -Type $(if ($Threat.Resolved) { "Success" } else { "Error" }) -Message $line

    if ($places.Count -gt 0 -or $Threat.ShortName -ne $Threat.Name) {
        Write-Host "      $($Threat.Name)$(if ($places.Count -gt 0) { ': ' + ($places -join '; ') })" -ForegroundColor DarkGray
    }
}


function Write-TFToolkitScanIntro {
    # O que a verificação faz e quanto demora, quando isso não cabe na linha do andamento. Vem antes de começar (na
    # completa, antes da pergunta): na janela, estas mensagens ficam no resumo, acima dos botões. Na rápida, o tempo vai
    # na linha do andamento (Get-TFToolkitScanDurationText).
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Quick", "Full", "Custom")]
        [string]$Type,

        [string]$Path = ""
    )

    # O Defender cuida sozinho do que encontrar (quarentena ou remoção): a pessoa só age depois, se alguma ameaça ainda
    # pedir ação.
    switch ($Type) {
        "Full" {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Examina todos os arquivos: leva horas e deixa o PC mais lento.')

            # Com DisableRemovableDriveScanning, a completa não entra nas unidades removíveis (pendrives e cartões de memória),
            # e a de uma pasta, sim: quem espera que elas sejam examinadas precisa saber.
            if ((Get-TFToolkitDefenderPreference -Name "DisableRemovableDriveScanning") -eq $true) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Pendrives e cartões de memória ficam de fora; para eles, use Segurança > Verificar uma pasta.')
            }
        }
        "Custom" { Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Examina somente: {0}' "$Path") }
    }
}


function Get-TFToolkitScanDurationText {
    # A linha do andamento da verificação, que não tem porcentagem: quanto a rápida levou da última vez neste PC (o estado
    # do antivírus lido na conferência, quando o Windows diz), ou quanto costuma levar.
    param (
        [Parameter(Mandatory)]
        [string]$Type,

        [string]$Path = "",

        $Antivirus = $null
    )

    switch ($Type) {
        "Full" { return (Get-TFToolkitText 'pode levar horas') }
        "Custom" { return (Get-TFToolkitText 'examinando {0}' "$Path") }
    }

    $minutes = Get-TFToolkitJsonValue -Object $Antivirus -Name "QuickScanMinutes" -Default $null

    if ($null -ne $minutes) { return (Get-TFToolkitText 'a última levou cerca de {0} min' "$minutes") }

    return (Get-TFToolkitText 'costuma levar de 2 a 15 minutos')
}


function Get-TFToolkitDefenderErrorCode {
    # O código HRESULT de um erro do Defender ("0x80072EE7"), ou "". Os cmdlets do Defender o põem no identificador do erro
    # ("HRESULT 0x80070002,Update-MpSignature"), e não na mensagem, que é só "a atualização terminou com erros".
    param ([Parameter(Mandatory)]$ErrorRecord)

    $texts = @()
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $texts += [string]$ErrorRecord.FullyQualifiedErrorId; $texts += [string]$ErrorRecord.Exception.Message }
    elseif ($ErrorRecord -is [System.Exception]) { $texts += [string]$ErrorRecord.Message }
    else { $texts += [string]$ErrorRecord }

    foreach ($text in $texts) {
        if ($text -match '0x([0-9A-Fa-f]{8})') { return "0x$($Matches[1].ToUpperInvariant())" }
    }

    return ""
}


function Test-TFToolkitDefenderNetworkError {
    # Se o erro é de conexão com a internet: só então "confira a internet" ajuda. Um erro sem código não é tomado como de
    # conexão (um acesso negado também chega sem código).
    param ([Parameter(Mandatory)]$ErrorRecord)

    return ((Get-TFToolkitDefenderErrorCode -ErrorRecord $ErrorRecord) -in @("0x80072EE7", "0x8024402C", "0x80072EFD", "0x80072EFE", "0x80072EE2", "0x8024401C"))
}


function Get-TFToolkitDefenderErrorInfo {
    <#
    Um erro do Defender em português, para os códigos mais comuns ao baixar assinaturas ou verificar: Text é a frase
    ("o PC não encontrou o servidor, sem internet ou sem DNS"), Full a frase com o código ("... (erro 0x80072EE7)"), Code
    o código e Network se é de conexão. Sem código conhecido, a mensagem do Windows como veio.
    #>
    param ([Parameter(Mandatory)]$ErrorRecord)

    $exception = $(if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception } elseif ($ErrorRecord -is [System.Exception]) { $ErrorRecord } else { $null })
    $message = $(if ($null -ne $exception) { [string]$exception.Message } else { [string]$ErrorRecord })
    $code = Get-TFToolkitDefenderErrorCode -ErrorRecord $ErrorRecord

    $text = switch ($code) {
        "0x80072EE7" { (Get-TFToolkitText 'o PC não encontrou o servidor, sem internet ou sem DNS') }
        "0x8024402C" { (Get-TFToolkitText 'o PC não encontrou o servidor, sem internet, sem DNS ou com o proxy errado') }
        "0x80072EFD" { (Get-TFToolkitText 'não foi possível conectar ao servidor, sem internet ou com um firewall ou proxy bloqueando') }
        "0x80072EFE" { (Get-TFToolkitText 'a conexão com o servidor caiu') }
        "0x80072EE2" { (Get-TFToolkitText 'a conexão com o servidor esgotou o tempo') }
        "0x8024401C" { (Get-TFToolkitText 'o servidor de atualizações demorou demais para responder') }
        "0x80244022" { (Get-TFToolkitText 'o servidor de atualizações está sobrecarregado; tente mais tarde') }
        "0x8024401B" { (Get-TFToolkitText 'o proxy pede usuário e senha') }
        "0x80072F8F" { (Get-TFToolkitText 'a conexão segura com o servidor falhou; confira a data e a hora do PC') }
        "0x80072F78" { (Get-TFToolkitText 'o servidor respondeu com dados inválidos') }
        "0x80070652" { (Get-TFToolkitText 'outra instalação está em andamento; tente de novo em alguns minutos') }
        "0x80070422" { (Get-TFToolkitText 'um serviço de que a atualização precisa, geralmente o Windows Update, está desativado') }
        "0x80240022" { (Get-TFToolkitText 'o Windows Update não conseguiu instalar a atualização') }
        "0x8024402F" { (Get-TFToolkitText 'o Windows Update encontrou erros no pacote da atualização') }
        "0x800106BA" { (Get-TFToolkitText 'o serviço do Windows Defender não iniciou') }
        "0x8007139F" { (Get-TFToolkitText 'o Windows Defender não está pronto: desligado ou substituído por outro antivírus') }
        "0x800704EC" { (Get-TFToolkitText 'uma política do Windows bloqueia o Windows Defender') }
        "0x80070005" { (Get-TFToolkitText 'o Windows negou o acesso') }
        "0x80508018" { (Get-TFToolkitText 'a verificação foi interrompida antes do fim') }
        "0x80508007" { (Get-TFToolkitText 'faltou memória para o Windows Defender') }
        "0x8050800C" { (Get-TFToolkitText 'o Windows Defender teve um erro interno; reinicie o PC e tente de novo') }
        "0x80508023" { (Get-TFToolkitText 'a ameaça não está mais no lugar, ou algo impediu a verificação') }
        "0x80508031" { (Get-TFToolkitText 'o Windows Defender está desatualizado; atualize o Windows') }
        default { "" }
    }

    if ($text) {
        return [PSCustomObject]@{ Text = $text; Full = (Get-TFToolkitText '{0} (erro {1})' "$text" "$code"); Code = $code; Network = (Test-TFToolkitDefenderNetworkError -ErrorRecord $ErrorRecord) }
    }

    $message = (ConvertTo-TFToolkitReadableError -Text $message).Trim().TrimEnd(".")
    $full = $message
    if ($code -and $message -notmatch [regex]::Escape($code.Substring(2))) { $full += (Get-TFToolkitText ' (erro {0})' "$code") }

    return [PSCustomObject]@{ Text = $message; Full = $full; Code = $code; Network = (Test-TFToolkitDefenderNetworkError -ErrorRecord $ErrorRecord) }
}


function Get-TFToolkitDefenderErrorText {
    # O erro do Defender em português, com o código: "frase (erro 0x80072EE7)" (Get-TFToolkitDefenderErrorInfo).
    param ([Parameter(Mandatory)]$ErrorRecord)

    return [string](Get-TFToolkitDefenderErrorInfo -ErrorRecord $ErrorRecord).Full
}


function Get-TFToolkitDefenderPreference {
    # Uma preferência do Defender (Get-MpPreference), ou $null quando não foi possível ler.
    param ([Parameter(Mandatory)][string]$Name)

    try {
        return (Get-TFToolkitJsonValue -Object (@(Invoke-TFToolkitCimCommand -Name "Get-MpPreference")[0]) -Name $Name -Default $null)
    }
    catch {
        return $null
    }
}


function Test-TFToolkitNetworkPath {
    # Se o caminho está na rede: \\servidor\pasta, ou uma unidade mapeada (Z:).
    param ([AllowEmptyString()][string]$Path)

    # \\?\C:\... e \\.\ são caminhos locais escritos do jeito longo, não pastas de rede.
    if ($Path -match '^[\\/]{2}(?![?.][\\/])') { return $true }

    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        if ([string]::IsNullOrWhiteSpace($root)) { return $false }

        return ((New-Object System.IO.DriveInfo($root)).DriveType -eq [System.IO.DriveType]::Network)
    }
    catch {
        return $false
    }
}


function Test-TFToolkitNetworkScanSkipped {
    # Se o Defender vai pular os arquivos deste caminho: ele está na rede e o Defender não examina arquivos de rede
    # (DisableScanningNetworkFiles, ligado por padrão). Sem ler a preferência, não afirma nada.
    param ([AllowEmptyString()][string]$Path)

    if (-not (Test-TFToolkitNetworkPath -Path $Path)) { return $false }

    return ((Get-TFToolkitDefenderPreference -Name "DisableScanningNetworkFiles") -eq $true)
}


function Get-TFToolkitMpCmdRunPath {
    # O MpCmdRun.exe do Defender: a pasta de plataforma mais nova (Windows atual) ou a antiga, em Arquivos de Programas.
    $candidates = @()

    try {
        $platform = Join-Path $env:ProgramData "Microsoft\Windows Defender\Platform"

        if (Test-Path -LiteralPath $platform -PathType Container) {
            $candidates += @(
                Get-ChildItem -LiteralPath $platform -Directory -ErrorAction Stop |
                    Sort-Object { try { [version]($_.Name -replace '[^0-9.].*$', '') } catch { [version]"0.0" } } -Descending |
                    ForEach-Object { Join-Path $_.FullName "MpCmdRun.exe" }
            )
        }
    }
    catch {
        # Sem a pasta de plataforma, vale o caminho clássico.
    }

    $candidates += (Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe")

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    return $null
}


function Stop-TFToolkitDefenderScan {
    # Pede ao Defender que cancele a verificação rápida ou completa em andamento (MpCmdRun -Scan -Cancel). O Parar
    # interrompe o Start-MpScan, mas não a verificação, que roda no próprio Defender: sem isto, ela continuaria escondida,
    # consumindo o PC. Devolve se o Defender aceitou o pedido; melhor esforço.
    $path = Get-TFToolkitMpCmdRunPath

    if ($null -eq $path) { return $false }

    try {
        $run = Invoke-TFToolkitCapture -FilePath $path -Arguments @("-Scan", "-Cancel")
        return ($run.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}


function Write-TFToolkitScanStopped {
    # Depois do Parar: cancela a verificação no Defender e diz o que aconteceu. A de uma pasta não tem como ser cancelada
    # por fora (o pedido do MpCmdRun vale para a rápida e a completa, e cancelaria outra que estivesse rodando).
    param ([Parameter(Mandatory)][string]$Type)

    if ($Type -eq "Custom") {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Verificação interrompida; o Windows Defender pode continuar examinando a pasta até o fim.')
        return
    }

    if (Stop-TFToolkitDefenderScan) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Verificação cancelada.')
    }
    else {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Verificação interrompida; o Windows Defender pode continuar até o fim. Confira em Segurança > Segurança do Windows.')
    }
}


function Get-TFToolkitScanFinish {
    <#
    O que o Windows Defender registrou depois da verificação. Confirmed: $true quando o fim da rápida (ou da completa)
    registrado é de depois do começo desta; $false quando o último fim registrado é de antes, ou seja, esta não chegou ao
    fim (cancelada por fora, por exemplo); $null quando não dá para saber (a verificação de uma pasta não deixa registro,
    ou o Windows não respondeu). Needs: o que o Defender ainda pede ao PC inteiro (ComputerState).
    #>
    param (
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][datetime]$Since
    )

    $field = switch ($Type) { "Quick" { "QuickScanEndTime" } "Full" { "FullScanEndTime" } default { "" } }
    $confirmed = $null
    $state = 0L

    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $status = $null

        try {
            $status = @(Invoke-TFToolkitCimCommand -Name "Get-MpComputerStatus")[0]
        }
        catch {
            $status = $null
        }

        if ($null -eq $status) { break }

        [void][int64]::TryParse([string](Get-TFToolkitJsonValue -Object $status -Name "ComputerState" -Default 0), [ref]$state)

        if (-not $field) { break }

        $end = ConvertTo-TFToolkitMpDate -Value (Get-TFToolkitJsonValue -Object $status -Name $field)
        if ($null -eq $end) { break }

        # Uma folga de segundos para o relógio; o fim de verdade é sempre depois do começo.
        $confirmed = ($end.ToUniversalTime() -ge $Since.ToUniversalTime().AddSeconds(-5))

        # O registro pode chegar um instante depois de o Start-MpScan voltar: confere mais uma vez antes de duvidar.
        if ($confirmed -or $attempt -gt 0) { break }

        Start-Sleep -Seconds $script:TFToolkitScanFinishRetrySeconds
    }

    return [PSCustomObject]@{ Confirmed = $confirmed; Needs = @(Get-TFToolkitDefenderNeeds -ComputerState $state) }
}


function ConvertTo-TFToolkitScanFailure {
    # O resultado de um Start-MpScan que falhou. Uma verificação do próprio Windows já em andamento (a agendada, ou uma
    # aberta na Segurança do Windows) não é defeito: é ressalva, e basta verificar de novo quando ela terminar.
    param (
        [Parameter(Mandatory)]$ErrorRecord,
        [Parameter(Mandatory)][string]$Type
    )

    $message = $(if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { [string]$ErrorRecord.Exception.Message } else { [string]$ErrorRecord })

    if ($message -match '(?i)scan is already in progress|verifica\S* j\S* est\S* em andamento|ya (hay|se est\S*) .{0,40}en curso') {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Já havia uma verificação do Windows Defender em andamento; verifique de novo quando ela terminar.')
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'outra verificação do Windows Defender já estava em andamento') -Data @{ ScanType = $Type }) `
            -Headline (Get-TFToolkitText 'Já havia uma verificação em andamento') -Note (Get-TFToolkitText 'Verifique de novo quando ela terminar.') -Tone Warn)
    }

    $info = Get-TFToolkitDefenderErrorInfo -ErrorRecord $ErrorRecord
    Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'A verificação não foi concluída: {0}.' "$($info.Full)")

    return (New-TFToolkitResult -Kind Failed -Detail $info.Text -Data @{ ScanType = $Type })
}


function Get-TFToolkitScanOutcome {
    <#
    Escreve o que a verificação achou (uma linha curta por ameaça) e devolve o TFToolkit.Result, com o título da faixa da
    janela. Do mais grave ao mais leve: ameaças que pedem ação (vermelho, com o botão para a Segurança do Windows), o
    Defender pedindo mais um passo ao PC (reiniciar, verificação completa ou offline), a verificação sem registro de fim,
    ameaças achadas e já resolvidas, e nada encontrado.
    #>
    param (
        [Parameter(Mandatory)][string]$Type,
        [string]$Path = "",
        [Parameter(Mandatory)]$Scan,
        [Parameter(Mandatory)]$Finish,
        [bool]$NetworkNote = $false
    )

    $found = @($Scan.Found)
    $leftover = @($Scan.Leftover)
    $pendingFound = @($found | Where-Object { -not [bool]$_.Resolved })
    $pendingCount = $pendingFound.Count + $leftover.Count
    $unconfirmed = ($Finish.Confirmed -eq $false)
    $open = (Get-TFToolkitText 'Abrir a Segurança do Windows')
    $data = @{ ScanType = $Type; ThreatCount = $found.Count; PendingThreats = $pendingCount; ActiveThreats = $leftover.Count }

    foreach ($threat in @($found) + @($leftover)) {
        Write-TFToolkitThreatLine -Threat $threat
    }

    if ($unconfirmed) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows Defender não registrou o fim da verificação; ela pode ter sido interrompida.')
    }

    $foundText = Format-TFToolkitCount -Count $found.Count -One (Get-TFToolkitText 'ameaça encontrada') -Many (Get-TFToolkitText 'ameaças encontradas')
    $unconfirmedText = (Get-TFToolkitText 'o Windows Defender não confirmou o fim da verificação')

    if ($pendingCount -gt 0) {
        $parts = @()
        if ($found.Count -gt 0) { $parts += $foundText } else { $parts += (Get-TFToolkitText 'nenhuma ameaça nova') }
        if ($pendingFound.Count -gt 0) { $parts += (Format-TFToolkitCount -Count $pendingFound.Count -One (Get-TFToolkitText 'ainda pede ação') -Many (Get-TFToolkitText 'ainda pedem ação')) }
        if ($leftover.Count -gt 0) { $parts += (Format-TFToolkitCount -Count $leftover.Count -One (Get-TFToolkitText 'ameaça de antes ainda ativa') -Many (Get-TFToolkitText 'ameaças de antes ainda ativas')) }
        if ($unconfirmed) { $parts += $unconfirmedText }

        # O que falta, quando o Defender já agiu em todas as pendentes e elas só esperam o mesmo passo do PC: reiniciar,
        # ou a verificação completa.
        $needs = @($pendingFound | ForEach-Object { @($_.Needs) } | Select-Object -Unique)
        $allNeed = ($leftover.Count -eq 0 -and @($pendingFound | Where-Object { -not [bool]$_.Waiting }).Count -eq 0)
        $note = (Get-TFToolkitText 'O Windows Defender não resolveu sozinho.')
        $next = "WindowsSecurityThreats"
        $nextLabel = $open

        if ($allNeed -and $needs.Count -eq 1 -and $needs[0] -eq "Reboot") {
            $note = (Get-TFToolkitText 'Reinicie o PC para o Windows Defender terminar a limpeza.')
            $data["RestartNeeded"] = $true
        }
        elseif ($allNeed -and $needs.Count -eq 1 -and $needs[0] -eq "FullScan") {
            $note = (Get-TFToolkitText 'O Windows Defender pede a verificação completa.')
            $next = "security.full-scan"
            $nextLabel = (Get-TFToolkitText 'Fazer a verificação completa')
        }

        # A linha do resumo diz o mesmo que a faixa: quando falta só reiniciar (ou a completa), "escolha o que fazer na
        # Segurança do Windows" mandaria a pessoa procurar uma escolha que não existe.
        Write-TFToolkitStatus -Type Info -Message $(
            if ($note -ne (Get-TFToolkitText 'O Windows Defender não resolveu sozinho.')) { $note }
            elseif ($pendingCount -eq 1) { (Get-TFToolkitText 'Escolha o que fazer com ela em Segurança > Segurança do Windows.') }
            else { (Get-TFToolkitText 'Escolha o que fazer com elas em Segurança > Segurança do Windows.') }
        )

        $result = New-TFToolkitResult -Kind Warning -Detail ($parts -join "; ") -Data $data
        return (Set-TFToolkitResultView -Result $result -Headline (Format-TFToolkitCount -Count $pendingCount -One (Get-TFToolkitText 'ameaça pede ação') -Many (Get-TFToolkitText 'ameaças pedem ação')) `
            -Note $note -Tone Bad -Next $next -NextLabel $nextLabel)
    }

    $resolvedText = $(if ($found.Count -eq 1) { (Get-TFToolkitText '{0}; resolvida pelo Windows Defender' "$foundText") } else { (Get-TFToolkitText '{0}; todas resolvidas pelo Windows Defender' "$foundText") })
    $needs = @($Finish.Needs)

    if ($needs.Count -gt 0) {
        # Nada pendente, mas o Defender ainda pede um passo ao PC (reiniciar depois de limpar, a verificação completa).
        $needText = Get-TFToolkitDefenderNeedText -Needs $needs
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows Defender pede {0}. Veja em Segurança > Segurança do Windows.' "$needText")

        $parts = @($(if ($found.Count -gt 0) { $resolvedText } else { (Get-TFToolkitText 'nenhuma ameaça encontrada') }), (Get-TFToolkitText 'o Windows Defender pede {0}' "$needText"))
        if ($unconfirmed) { $parts += $unconfirmedText }

        $fullScanOnly = ($needs.Count -eq 1 -and $needs[0] -eq "FullScan")
        if ($needs.Count -eq 1 -and $needs[0] -eq "Reboot") { $data["RestartNeeded"] = $true }
        $result = New-TFToolkitResult -Kind Warning -Detail ($parts -join "; ") -Data $data

        return (Set-TFToolkitResultView -Result $result -Headline $(if ($needs.Count -eq 1) { (Get-TFToolkitText 'O Windows Defender pede {0}' "$needText") } else { (Get-TFToolkitText 'O Windows Defender pede mais um passo') }) `
            -Note $(if ($found.Count -gt 0) { "$(Format-TFToolkitCount -Count $found.Count -One (Get-TFToolkitText 'ameaça encontrada e resolvida') -Many (Get-TFToolkitText 'ameaças encontradas e resolvidas'))." } else { (Get-TFToolkitText 'Nenhuma ameaça encontrada nesta verificação.') }) `
            -Tone Warn -Next $(if ($fullScanOnly) { "security.full-scan" } else { "WindowsSecurityThreats" }) -NextLabel $(if ($fullScanOnly) { (Get-TFToolkitText 'Fazer a verificação completa') } else { $open }))
    }

    if ($unconfirmed) {
        $result = New-TFToolkitResult -Kind Warning -Detail "$(if ($found.Count -gt 0) { $resolvedText } else { (Get-TFToolkitText 'nenhuma ameaça encontrada') }); $unconfirmedText" -Data $data
        return (Set-TFToolkitResultView -Result $result -Headline (Get-TFToolkitText 'A verificação pode ter parado antes do fim') -Note (Get-TFToolkitText 'Verifique de novo para ter certeza.') -Tone Warn)
    }

    if ($found.Count -gt 0) {
        $result = New-TFToolkitResult -Kind Ok -Detail $resolvedText -Data $data
        return (Set-TFToolkitResultView -Result $result -Headline (Format-TFToolkitCount -Count $found.Count -One (Get-TFToolkitText 'ameaça resolvida') -Many (Get-TFToolkitText 'ameaças resolvidas')) `
            -Note $(if ($found.Count -eq 1) { (Get-TFToolkitText 'O Windows Defender já cuidou dela; o histórico fica na Segurança do Windows.') } else { (Get-TFToolkitText 'O Windows Defender já cuidou delas; o histórico fica na Segurança do Windows.') }))
    }

    if ($NetworkNote) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Verificação concluída: nenhuma ameaça encontrada, mas os arquivos de rede podem não ter sido examinados.')
        $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'nenhuma ameaça encontrada; os arquivos de rede podem não ter sido examinados') -Data $data
        return (Set-TFToolkitResultView -Result $result -Headline (Get-TFToolkitText 'Nenhum vírus encontrado') -Note (Get-TFToolkitText 'Mas os arquivos de rede podem não ter sido examinados.') -Tone Warn)
    }

    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Verificação concluída: nenhuma ameaça encontrada.')

    $note = switch ($Type) {
        "Quick" { (Get-TFToolkitText 'Verificação rápida concluída.') }
        "Full" { (Get-TFToolkitText 'Verificação completa concluída.') }
        default { (Get-TFToolkitText 'Verificado: {0}' "$Path") }
    }

    # A faixa diz tudo: o resumo só repetiria.
    return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'nenhuma ameaça encontrada') -Data $data) -Headline (Get-TFToolkitText 'Nenhum vírus encontrado') -Note $note -HideSummary)
}


function Test-TFToolkitScanPath {
    <#
    Confere o caminho da verificação de uma pasta antes de qualquer trabalho: $null quando ele serve; senão, escreve o
    motivo e devolve o resultado de falha. Um caminho sem a unidade ("Fotos", ".\Downloads", "\Fotos", "C:") seria
    procurado a partir da pasta do TF-Toolkit (ou da unidade atual), e não onde a pessoa pensou: pede o caminho completo,
    com a unidade ou de rede.
    #>
    param ([AllowEmptyString()][string]$Path)

    $complete = ($Path -match '^[A-Za-z]:[\\/]' -or $Path -match '^[\\/]{2}[^\\/]' -or ([System.IO.Path]::DirectorySeparatorChar -eq '/' -and $Path.StartsWith('/')))

    if (-not $complete) {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Informe o caminho completo, com a unidade (por exemplo, D:\Fotos): {0}' "$Path")
        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'caminho incompleto'))
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Pasta ou arquivo não encontrado: {0}' "$Path")
        $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'caminho não encontrado')
        $note = Get-TFToolkitMissingDriveNote -Path $Path

        if ($note) {
            Write-TFToolkitStatus -Type Info -Message $note
            [void](Set-TFToolkitResultView -Result $result -Headline (Get-TFToolkitText 'Pasta ou arquivo não encontrado') -Note $note -Tone Bad)
        }

        return $result
    }

    return $null
}


function Get-TFToolkitMissingDriveNote {
    <#
    Para um caminho cuja unidade não existe para o TF-Toolkit (Z:\Documentos): aberto como Administrador, ele não vê as
    unidades de rede mapeadas na sessão comum, porque cada mapeamento vale só para a sessão em que foi criado. Devolve a
    frase que diz isso e o que fazer, ou "" quando a unidade existe, o caminho não começa por uma letra ou o TF-Toolkit não
    está como Administrador.
    #>
    param ([AllowEmptyString()][string]$Path)

    if ($Path -notmatch '^([A-Za-z]):') { return "" }

    $drive = "$($Matches[1].ToUpperInvariant()):"

    if ((Test-Path -LiteralPath "$drive\") -or -not (Test-TFToolkitAdministrator)) { return "" }

    return (Get-TFToolkitText 'A unidade {0} não aparece para o TF-Toolkit. Se é uma unidade de rede, use o caminho da rede (\\servidor\pasta): aberto como Administrador, o TF-Toolkit não vê as unidades mapeadas.' "$drive")
}


function Invoke-TFToolkitDefenderScan {
    <#
    Roda uma verificação do Defender (Quick, Full ou Custom com -Path) e devolve um TFToolkit.Result, já com o título da
    faixa da janela. Data traz ScanType, ThreatCount (as achadas por esta verificação), PendingThreats (as que ainda pedem
    ação, inclusive as de antes), ActiveThreats (as de antes ainda ativas) e, quando o Defender só espera reiniciar o PC
    para terminar a limpeza, RestartNeeded (Request-TFToolkitScanRestart oferece o reinício). Não abre nem fecha a ação
    (quem chama faz isso).
    #>
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Quick", "Full", "Custom")]
        [string]$Type,

        [string]$Path = "",

        # Pula a conferência de Test-TFToolkitDefenderReady quando quem chama já a fez; -Current traz então o estado do
        # antivírus que ela leu (para a linha do andamento dizer quanto a última rápida levou).
        [switch]$AssumeReady,

        $Current = $null,

        # Quem chama já mostrou o que a verificação faz (a completa mostra antes de perguntar se pode começar).
        [switch]$SkipIntro
    )

    if (-not $AssumeReady) {
        $ready = Test-TFToolkitDefenderReady

        if (-not $ready.Ready) {
            return $ready.Result
        }

        $Current = $ready.Antivirus
    }

    $scanType = switch ($Type) {
        "Quick"  { "QuickScan" }
        "Full"   { "FullScan" }
        "Custom" { "CustomScan" }
    }

    $arguments = @{ ScanType = $scanType }
    $command = "Start-MpScan -ScanType $scanType"

    $networkNote = $false

    if ($Type -eq "Custom") {
        $invalid = Test-TFToolkitScanPath -Path $Path
        if ($null -ne $invalid) { return $invalid }

        $arguments["ScanPath"] = $Path
        $command += " -ScanPath `"$Path`""
        $networkNote = (Test-TFToolkitNetworkScanSkipped -Path $Path)
    }

    # O título da fase: na janela, é a frase em destaque enquanto a verificação roda.
    Write-TFToolkitSection -Title $(switch ($Type) { "Quick" { (Get-TFToolkitText 'Verificação rápida') } "Full" { (Get-TFToolkitText 'Verificação completa') } default { (Get-TFToolkitText 'Verificação da pasta') } })

    if (-not $SkipIntro) {
        Write-TFToolkitScanIntro -Type $Type -Path $Path
    }

    if ($networkNote) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows Defender está configurado para não examinar arquivos de rede: verifique esta pasta no PC onde ela está.')
    }

    Write-TFToolkitCommand -Command $command

    # O que o Defender já tinha registrado: separa o que esta verificação achou do que já estava lá.
    $known = Get-TFToolkitDetectionIds
    $estimate = Get-TFToolkitScanDurationText -Type $Type -Path $Path -Antivirus $Current

    # Nenhuma verificação pode parar no meio porque o Windows suspendeu o PC: nem a completa (horas), nem a rápida, que
    # num notebook na bateria passa do tempo de suspensão.
    $awake = [bool](Set-TFToolkitKeepAwake -Enabled $true)

    # Sem porcentagem: o Defender só responde quando termina. A barra indeterminada mostra que ainda está trabalhando, e a
    # linha diz quanto costuma levar (uma linha "Verificando..." ficaria no resumo depois do fim).
    Write-Progress -Activity (Get-TFToolkitText 'Windows Defender') -Status $estimate

    $finished = $false
    $scanStart = Get-Date

    try {
        [void](Start-MpScan @arguments -ErrorAction Stop)
        $finished = $true
    }
    catch {
        $finished = $true
        return (ConvertTo-TFToolkitScanFailure -ErrorRecord $_ -Type $Type)
    }
    finally {
        Write-Progress -Activity (Get-TFToolkitText 'Windows Defender') -Completed

        if ($awake) { [void](Set-TFToolkitKeepAwake -Enabled $false) }

        # Sem ter terminado nem falhado, quem interrompeu foi a pessoa (Parar): o Defender seguiria varrendo sozinho.
        if (-not $finished) {
            try {
                Write-TFToolkitScanStopped -Type $Type
            }
            catch {
                # O fluxo já está sendo encerrado; nada mais a fazer.
            }
        }
    }

    $finish = Get-TFToolkitScanFinish -Type $Type -Since $scanStart
    $scan = Get-TFToolkitScanDetections -Since $scanStart.AddSeconds(-5) -Known $known

    if ($null -eq $scan) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A verificação terminou, mas não foi possível consultar o resultado. Confira em Segurança > Segurança do Windows.')
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'resultado não consultado') -Data @{ ScanType = $Type }) `
            -Headline (Get-TFToolkitText 'Não foi possível ler o resultado') -Note (Get-TFToolkitText 'A verificação terminou, mas o Windows não deixou consultar o que ela achou.') `
            -Tone Warn -Next "WindowsSecurityThreats" -NextLabel (Get-TFToolkitText 'Abrir a Segurança do Windows'))
    }

    return (Get-TFToolkitScanOutcome -Type $Type -Path $Path -Scan $scan -Finish $finish -NetworkNote $networkNote)
}


function Request-TFToolkitScanRestart {
    <#
    Depois de uma verificação em que o Windows Defender só espera reiniciar o PC para terminar a limpeza (Data.RestartNeeded,
    de Get-TFToolkitScanOutcome): oferece reiniciar ali mesmo, com o Depois como padrão, como o reparo da rede. Quem chama
    não oferece dentro do Otimizar (-Embedded), que tem o próprio fim.
    #>
    param ([Parameter(Mandatory)]$Result)

    if (-not [bool](Get-TFToolkitResultData -Result $Result -Name "RestartNeeded")) { return }

    Request-TFToolkitRestartOffer -Reason (Get-TFToolkitText 'Reiniciar agora deixa o Windows Defender terminar a limpeza.') `
        -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit para o Windows Defender terminar a limpeza.') `
        -DeclinedMessage (Get-TFToolkitText 'O PC não foi reiniciado. O Windows Defender termina a limpeza quando você reiniciar.') `
        -Fallback (Get-TFToolkitText 'Reinicie o PC para o Windows Defender terminar a limpeza.')
}


# ---------------------------------------------------------------------------
# Ações
# ---------------------------------------------------------------------------

function Update-TFToolkitDefenderSignatures {
    param (
        [switch]$Embedded,
        [switch]$PassThru
    )

    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Atualizar assinaturas do antivírus') -Embedded:$Embedded

    $result = $null

    try {
        $result = Invoke-TFToolkitSignatureUpdate
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro ao atualizar as assinaturas: {0}' "$($_.Exception.Message)")
        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }

    $result.Etapa = (Get-TFToolkitText 'Atualizar assinaturas do antivírus')
    Exit-TFToolkitAction -Embedded:$Embedded -Result $result

    if ($PassThru) {
        return $result
    }
}


function Start-TFToolkitFullScan {
    param (
        [switch]$Embedded,
        [switch]$PassThru
    )

    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Verificação completa de vírus') -Embedded:$Embedded

    $result = $null

    try {
        # Antes de perguntar: sem Administrador ou sem o Defender protegendo, perguntar "deseja começar?" seria à toa.
        $ready = Test-TFToolkitDefenderReady

        if (-not $ready.Ready) {
            $result = $ready.Result
        }
        else {
            # O que a verificação faz antes da pergunta: na janela, fica no resumo, acima dos botões.
            Write-TFToolkitScanIntro -Type Full

            # Horas de disco e processador esgotam a bateria de um notebook (e a verificação recomeça do zero).
            if (Test-TFToolkitOnBattery) {
                Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'O notebook está na bateria: conecte o carregador, a verificação completa pode levar horas.')
            }

            Write-Host ""

            if (-not $Embedded -and -not (Confirm-TFToolkitAction (Get-TFToolkitText 'Deseja começar a verificação completa agora?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Começar') -NoLabel (Get-TFToolkitText 'Agora não'))) {
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
                $result = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário')
            }
            else {
                # Horas de verificação com as assinaturas de dias atrás deixariam passar o que surgiu nesse meio-tempo: o
                # antivírus é atualizado antes, como no Verificar vírus (o Start-MpScan não atualiza nada antes de começar).
                $update = Invoke-TFToolkitSignatureUpdate -AssumeReady -Current $ready.Antivirus
                $scan = Invoke-TFToolkitDefenderScan -Type Full -AssumeReady -Current $ready.Antivirus -SkipIntro
                $result = Join-TFToolkitSecurityCheckResult -Update $update -Scan $scan
                if (-not $Embedded) { Request-TFToolkitScanRestart -Result $result }
            }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro na verificação: {0}' "$($_.Exception.Message)")
        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }

    $result.Etapa = (Get-TFToolkitText 'Verificação completa de vírus')
    Exit-TFToolkitAction -Embedded:$Embedded -Result $result

    if ($PassThru) {
        return $result
    }
}


function ConvertTo-TFToolkitScanPath {
    # O caminho como a pessoa o cola: sem espaços nas pontas, sem aspas (duplas, do "Copiar como caminho", ou simples),
    # com variáveis como %USERPROFILE% já resolvidas e "E:" como a raiz da unidade (E:\). Vazio quando não há nada.
    param ($Text)

    $path = ([string]$Text).Trim().Trim('"', "'").Trim()

    if ($path.Contains("%")) {
        $path = [Environment]::ExpandEnvironmentVariables($path)
    }

    # Só a letra da unidade ("E:", um pen drive) é a raiz dela: sem a barra, valeria a pasta atual daquela unidade.
    if ($path -match '^[A-Za-z]:$') {
        $path += "\"
    }

    return $path
}


function Get-TFToolkitRemovableDrives {
    <#
    Os pendrives e cartões de memória conectados (as unidades removíveis do Windows), para oferecê-los como destino:
    Root ("E:\") e Label ("E: (KINGSTON)"). Um leitor de cartão sem cartão também é uma unidade removível, mas sem tamanho
    (Size vazio): fica de fora, porque escolhê-lo só daria "não encontrado". Vazio quando não há nenhum ou o Windows não
    respondeu.
    #>
    $drives = @()

    try {
        foreach ($drive in @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 2" -OperationTimeoutSec 15 -ErrorAction Stop)) {
            $letter = [string](Get-TFToolkitJsonValue -Object $drive -Name "DeviceID" -Default "")
            if (-not $letter) { continue }

            if ($null -ne $drive.PSObject.Properties["Size"]) {
                $size = 0L
                if (-not [int64]::TryParse([string]$drive.Size, [ref]$size) -or $size -le 0) { continue }
            }

            $name = [string](Get-TFToolkitJsonValue -Object $drive -Name "VolumeName" -Default "")
            $drives += [PSCustomObject]@{ Root = "$letter\"; Label = $(if ($name) { "$letter ($name)" } else { $letter }) }
        }
    }
    catch {
        Write-Verbose "Unidades removíveis: $($_.Exception.Message)"
    }

    return @($drives)
}


function Select-TFToolkitScanTarget {
    # Pergunta o que verificar: as pastas mais comuns e os pendrives conectados em botões, ou um caminho digitado. Devolve
    # o caminho, ou "" quando a pessoa cancela.
    $options = @()
    $downloads = ""
    $desktop = ""

    try { $downloads = [string](Get-TFToolkitDownloadsPath) } catch { $downloads = "" }
    try { $desktop = [string][Environment]::GetFolderPath("Desktop") } catch { $desktop = "" }

    if ($downloads -and (Test-Path -LiteralPath $downloads -PathType Container)) {
        $options += @{ Key = "D"; Label = (Get-TFToolkitText 'Downloads'); Description = $downloads; Accent = $true }
    }

    if ($desktop -and (Test-Path -LiteralPath $desktop -PathType Container)) {
        $options += @{ Key = "A"; Label = (Get-TFToolkitText 'Área de Trabalho'); Description = $desktop }
    }

    # Os pendrives conectados: a verificação completa pode deixá-los de fora (Write-TFToolkitScanIntro manda vir aqui).
    $drives = @{}
    $position = 0

    foreach ($drive in @(Get-TFToolkitRemovableDrives | Select-Object -First 9)) {
        $position++
        $drives[[string]$position] = $drive.Root
        $options += @{ Key = [string]$position; Label = $drive.Label; Description = (Get-TFToolkitText 'pendrive ou cartão de memória') }
    }

    $options += @{ Key = "O"; Label = (Get-TFToolkitText 'Outra pasta ou arquivo'); Description = (Get-TFToolkitText 'por exemplo D:\Fotos') }
    $options += @{ Key = "C"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }

    $choice = [string](Read-TFToolkitChoice -Message (Get-TFToolkitText 'O que deseja verificar?') -Options $options -DefaultKey "C" -ShowMenu)

    if ($drives.ContainsKey($choice)) { return $drives[$choice] }

    switch ($choice) {
        "D" { return $downloads }
        "A" { return $desktop }
        "O" { return (ConvertTo-TFToolkitScanPath -Text (Read-TFToolkitText -Message (Get-TFToolkitText 'Cole o caminho da pasta ou do arquivo (ENTER cancela)'))) }
        default { return "" }
    }
}


function Start-TFToolkitFolderScan {
    param (
        [switch]$Embedded,
        [switch]$PassThru
    )

    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Verificar uma pasta') -Embedded:$Embedded

    $result = $null

    try {
        # Antes de perguntar o que verificar: sem Administrador ou sem o Defender protegendo, a pergunta seria à toa.
        $ready = Test-TFToolkitDefenderReady

        if (-not $ready.Ready) {
            $result = $ready.Result
        }
        else {
            $path = [string](Select-TFToolkitScanTarget)
            $invalid = $(if ([string]::IsNullOrWhiteSpace($path)) { $null } else { Test-TFToolkitScanPath -Path $path })

            if ([string]::IsNullOrWhiteSpace($path)) {
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
                $result = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário')
            }
            elseif ($null -ne $invalid) {
                # O caminho errado é dito antes de atualizar o antivírus: a atualização seria trabalho à toa.
                $result = $invalid
            }
            else {
                # Quem verifica um arquivo baixado agora quer as assinaturas de hoje: o antivírus é atualizado antes.
                $update = Invoke-TFToolkitSignatureUpdate -AssumeReady -Current $ready.Antivirus
                $scan = Invoke-TFToolkitDefenderScan -Type Custom -Path $path -AssumeReady -Current $ready.Antivirus
                $result = Join-TFToolkitSecurityCheckResult -Update $update -Scan $scan
                if (-not $Embedded) { Request-TFToolkitScanRestart -Result $result }
            }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro na verificação: {0}' "$($_.Exception.Message)")
        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }

    $result.Etapa = (Get-TFToolkitText 'Verificar uma pasta')
    Exit-TFToolkitAction -Embedded:$Embedded -Result $result

    if ($PassThru) {
        return $result
    }
}


function Join-TFToolkitSecurityCheckResult {
    <#
    O resultado de uma verificação feita depois de atualizar o antivírus (o Verificar vírus, a completa e a de uma
    pasta): o da verificação, com a atualização junto quando ela não deu certo (a verificação rodou com as assinaturas
    de antes, e o Otimizar e o histórico precisam saber disso). A cor é a pior das duas: nada encontrado com o antivírus
    sem atualizar fica amarelo, e a faixa diz por quê.
    #>
    param (
        [Parameter(Mandatory)]$Update,
        [Parameter(Mandatory)]$Scan
    )

    if ([string]$Update.Kind -eq "Ok") {
        if ([string]$Scan.Kind -eq "Ok" -and [int](Get-TFToolkitResultData -Result $Scan -Name "ThreatCount") -eq 0 -and $Scan.Data -is [System.Collections.IDictionary]) {
            # A da pasta continua dizendo o que foi examinado ("verificado: D:\Fotos").
            $scanNote = ([string](Get-TFToolkitResultData -Result $Scan -Name "Note")).Trim()

            $Scan.Data["Note"] = switch ([string](Get-TFToolkitResultData -Result $Scan -Name "ScanType")) {
                "Full" { (Get-TFToolkitText 'Antivírus atualizado e verificação completa concluída.') }
                "Custom" { $(if ($scanNote) { (Get-TFToolkitText 'Antivírus atualizado; ') + $scanNote.Substring(0, 1).ToLowerInvariant() + $scanNote.Substring(1) } else { (Get-TFToolkitText 'Antivírus atualizado e pasta verificada.') }) }
                default { (Get-TFToolkitText 'Antivírus atualizado e verificação rápida concluída.') }
            }
        }

        return $Scan
    }

    $data = @{}

    if ($Scan.Data -is [System.Collections.IDictionary]) {
        foreach ($key in @($Scan.Data.Keys)) { $data[$key] = $Scan.Data[$key] }
    }

    $kind = $(if ([string]$Scan.Kind -eq "Failed") { "Failed" } else { "Warning" })
    $detail = (@([string]$Scan.Detail, [string]$Update.Detail) | Where-Object { $_ }) -join "; "
    $result = New-TFToolkitResult -Kind $kind -Detail $detail -Data $data

    if ([string]$Scan.Kind -eq "Ok") {
        # O resumo mostra a linha da atualização que não deu certo: ele não fica escondido.
        $headline = [string](Get-TFToolkitResultData -Result $Scan -Name "Headline")
        [void](Set-TFToolkitResultView -Result $result -Headline $(if ($headline) { $headline } else { (Get-TFToolkitText 'Nenhum vírus encontrado') }) `
            -Note ([string](Get-TFToolkitResultData -Result $Update -Name "Caveat")) -Tone Warn)
    }
    elseif ([string]$Scan.Kind -eq "Failed") {
        # Os dois motivos juntos dariam uma frase longa demais para a faixa: ela diz o da verificação, e que a atualização
        # também não deu certo; o detalhe (o Otimizar e o histórico) continua com os dois.
        $reason = ([string]$Scan.Detail).Trim().TrimEnd(".").Trim()
        if ($reason) { $reason = $reason.Substring(0, 1).ToUpperInvariant() + $reason.Substring(1) + ". " }

        [void](Set-TFToolkitResultView -Result $result -Headline (Get-TFToolkitText 'A verificação não foi concluída') -Note (Get-TFToolkitText '{0}O antivírus também não foi atualizado.' "${reason}") -Tone Bad)
    }

    return $result
}


function Invoke-TFToolkitSecurityCheck {
    <#
    Verificar vírus (o botão do Início, Segurança > Verificar vírus e a etapa do Otimizar): atualiza as assinaturas e faz
    a verificação rápida. O resultado é o da verificação; a atualização que não deu certo entra junto e deixa o resultado
    pelo menos com ressalva (a verificação rodou com as assinaturas de antes).
    #>
    param (
        [switch]$Embedded,
        [switch]$PassThru
    )

    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Verificar vírus') -Embedded:$Embedded

    $result = $null

    try {
        $ready = Test-TFToolkitDefenderReady

        if (-not $ready.Ready) {
            # Nada a verificar: o motivo já está na tela.
            $result = $ready.Result
        }
        else {
            $update = Invoke-TFToolkitSignatureUpdate -AssumeReady -Current $ready.Antivirus
            $scan = Invoke-TFToolkitDefenderScan -Type Quick -AssumeReady -Current $ready.Antivirus
            $result = Join-TFToolkitSecurityCheckResult -Update $update -Scan $scan

            # No Otimizar, a pergunta não aparece no meio (ele tem o próprio fim).
            if (-not $Embedded) { Request-TFToolkitScanRestart -Result $result }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro na verificação de vírus: {0}' "$($_.Exception.Message)")
        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }

    $result.Etapa = (Get-TFToolkitText 'Verificar vírus')
    Exit-TFToolkitAction -Embedded:$Embedded -Result $result

    if ($PassThru) {
        return $result
    }
}


# ---------------------------------------------------------------------------
# Auditoria de segurança (somente leitura)
# ---------------------------------------------------------------------------

function Get-TFToolkitGuestAccount {
    <#
    A conta Convidado: Enabled e Name, o nome dela neste Windows ("Convidado", "Guest", "Invitado", ou o que uma política
    deu). Ela tem sempre o SID terminado em -501, qualquer que seja o idioma; o nome muda com o idioma em que o Windows foi
    instalado, e não com o da tela do TF-Toolkit. $null = não foi possível ler.
    #>
    try {
        $guest = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -like "*-501" } | Select-Object -First 1)

        # Sem a conta Convidado (removida da imagem do Windows), não há o que entrar sem senha.
        if ($guest.Count -eq 0) {
            return [PSCustomObject]@{ Enabled = $false; Name = "" }
        }

        return [PSCustomObject]@{ Enabled = [bool]$guest[0].Enabled; Name = [string]$guest[0].Name }
    }
    catch {
        return $null
    }
}


function Get-TFToolkitSmb1State {
    <#
    O SMB 1.0, o protocolo antigo de compartilhamento de arquivos (usado por ataques como o WannaCry): "On" quando o
    recurso do Windows está ligado (ou liga no próximo reinício), "Off" quando está desligado ou nem existe neste
    Windows, e $null quando não foi possível ler (a consulta pede Administrador). É o recurso de "Ativar ou desativar
    recursos do Windows" (SMB1Protocol), o caminho que a Microsoft indica para conferir o SMB 1.0 no Windows 10 e 11.
    #>
    try {
        $feature = @(Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        return $null
    }

    if ($null -eq $feature) { return "Off" }

    return $(if ([string](Get-TFToolkitJsonValue -Object $feature -Name "State" -Default "") -in @("Enabled", "EnablePending")) { "On" } else { "Off" })
}


function Get-TFToolkitBitLockerState {
    <#
    O disco do sistema: "On" (criptografado e protegido), "Suspended" (criptografado, com chave de proteção, mas com a
    proteção suspensa: a chave fica gravada no disco, como depois de uma atualização da BIOS), "Encrypting" (ainda
    criptografando, ou com a criptografia pausada), "Pending" (criptografado, mas sem nenhuma chave de proteção: a
    criptografia do dispositivo esperando ativação), "Off" (sem criptografia) ou $null quando não dá para saber (sem
    Administrador, edição sem BitLocker...). Os estados vêm pelos nomes do módulo BitLocker.
    #>
    try {
        $drive = if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { "C:" } else { $env:SystemDrive }
        $volume = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
        $protection = [string](Get-TFToolkitJsonValue -Object $volume -Name "ProtectionStatus" -Default "")
        $volumeStatus = [string](Get-TFToolkitJsonValue -Object $volume -Name "VolumeStatus" -Default "")
        $protectors = @(Get-TFToolkitJsonValue -Object $volume -Name "KeyProtector" -Default @() | Where-Object { $null -ne $_ })

        if ($protection -in @("On", "1")) { return "On" }
        if ($protection -notin @("Off", "0")) { return $null }

        # Proteção "Off" vale para um disco sem criptografia, um ainda criptografando e um criptografado com a proteção
        # suspensa ou esperando ativação: o estado do volume e as chaves desempatam.
        switch ($volumeStatus) {
            "FullyDecrypted" { return "Off" }
            "FullyEncrypted" { return $(if ($protectors.Count -gt 0) { "Suspended" } else { "Pending" }) }
            { $_ -in @("EncryptionInProgress", "EncryptionSuspended") } { return "Encrypting" }
            { $_ -in @("DecryptionInProgress", "DecryptionSuspended") } { return "Off" }
        }

        # Sem o estado do volume, a proteção desligada vale como sem criptografia.
        return "Off"
    }
    catch {
        # Sem resposta: fica como "não verificado".
    }

    return $null
}


function Get-TFToolkitMemoryIntegrityState {
    <#
    A integridade da memória (Segurança do Windows > Segurança do dispositivo > Isolamento de núcleo; HVCI): "On" (em uso),
    "Pending" (configurada, mas fora de uso: falta reiniciar, ou o PC não conseguiu usá-la), "Off" ou $null quando não
    foi possível ler. A leitura é a que a Microsoft indica, a classe Win32_DeviceGuard: o valor 2 em
    SecurityServicesRunning diz que ela está em uso, e em SecurityServicesConfigured, que está configurada. Só lê: alguns
    drivers e programas não funcionam com ela, e ligá-la é escolha da pessoa.
    #>
    try {
        $guard = @(Get-CimInstance -Namespace "root\Microsoft\Windows\DeviceGuard" -ClassName "Win32_DeviceGuard" -OperationTimeoutSec 15 -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        return $null
    }

    if ($null -eq $guard) { return $null }

    $running = @(Get-TFToolkitJsonValue -Object $guard -Name "SecurityServicesRunning" -Default @() | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    $configured = @(Get-TFToolkitJsonValue -Object $guard -Name "SecurityServicesConfigured" -Default @() | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })

    if ($running -contains "2") { return "On" }
    if ($configured -contains "2") { return "Pending" }

    return "Off"
}


function Get-TFToolkitSecurityAuditFacts {
    <#
    Lê, sem alterar nada, o que a auditoria avalia. Cada leitura que falha vira $null ("não verificado"), nunca erro.
    As atualizações pendentes (que demoram) vêm de fora, por -Updates.
    #>
    param (
        $Updates = $null
    )

    $system = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

    $uac = Get-TFToolkitRegistryValueOrNull -Path $system -Name "EnableLUA"
    # O nível "Nunca notificar" do UAC deixa EnableLUA em 1 e zera ConsentPromptBehaviorAdmin: os programas ganham
    # Administrador sem perguntar.
    $uacPrompt = Get-TFToolkitRegistryValueOrNull -Path $system -Name "ConsentPromptBehaviorAdmin"
    # A Área de Trabalho Remota: a política (de grupo, ou do MDM da empresa), quando configurada, decide no lugar da chave
    # que a tela do Windows grava; sem ela, vale essa chave.
    $denyRdpPolicy = Get-TFToolkitRegistryValueOrNull -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fDenyTSConnections"
    $denyRdp = $(if ($null -ne $denyRdpPolicy) { $denyRdpPolicy } else { Get-TFToolkitRegistryValueOrNull -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" })
    # O Secure Boot com a mesma leitura do Diagnóstico (Sobre este PC): o modo de inicialização, o Registro (legível sem
    # Administrador) e, sem ele, a consulta do Windows. "Legacy" = o Windows iniciou no modo BIOS legado.
    $secureBootState = [string](Get-TFToolkitSecureBootState)
    $secureBoot = $(
        if ($secureBootState -eq "On") { $true }
        elseif ($secureBootState -eq "Off") { $false }
        elseif ($secureBootState -eq "Legacy") { "Legacy" }
        else { $null }
    )
    $explorerSmartScreen = Get-TFToolkitRegistryValueOrNull -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled"
    # Ligado de forma explícita (Warn ou RequireAdmin, ou a política em 1); sem nenhum dos dois, vale o padrão do Windows.
    $smartScreenSet = ([string]$explorerSmartScreen -in @("Warn", "RequireAdmin"))
    $policySmartScreen = Get-TFToolkitRegistryValueOrNull -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen"
    $autoLogon = Get-TFToolkitRegistryValueOrNull -Path $winlogon -Name "AutoAdminLogon"
    $storedPassword = Get-TFToolkitRegistryValueOrNull -Path $winlogon -Name "DefaultPassword"
    $currentVersion = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $guest = Get-TFToolkitGuestAccount

    return [PSCustomObject]@{
        Antivirus        = Get-TFToolkitAntivirusStatus
        Firewall         = Get-TFToolkitFirewallStatus
        Threats          = Get-TFToolkitActiveThreats
        Updates          = $Updates
        UacEnabled       = $(if ($null -eq $uac) { $null } else { [int]$uac -ne 0 })
        UacNeverNotify   = ($null -ne $uacPrompt -and [string]$uacPrompt -eq "0")
        SmartScreenOff   = ($explorerSmartScreen -eq "Off" -or ($null -ne $policySmartScreen -and [int]$policySmartScreen -eq 0))
        SmartScreenSet   = ($smartScreenSet -or ($null -ne $policySmartScreen -and [string]$policySmartScreen -eq "1"))
        RdpEnabled       = $(if ($null -eq $denyRdp) { $null } else { [int]$denyRdp -eq 0 })
        RdpByPolicy      = ($null -ne $denyRdpPolicy)
        GuestEnabled     = $(if ($null -eq $guest) { $null } else { [bool]$guest.Enabled })
        GuestName        = $(if ($null -eq $guest) { "" } else { [string]$guest.Name })
        # Sem Administrador, o Windows nega algumas leituras (as ameaças guardadas, o SMB 1.0 e o BitLocker): a linha diz isso.
        Administrator    = [bool](Test-TFToolkitAdministrator)
        AutoLogon        = ([string]$autoLogon -eq "1")
        PasswordStored   = (-not [string]::IsNullOrEmpty([string]$storedPassword))
        BitLocker        = Get-TFToolkitBitLockerState
        Smb1             = Get-TFToolkitSmb1State
        SecureBoot       = $secureBoot
        MemoryIntegrity  = Get-TFToolkitMemoryIntegrityState
        WindowsBuild     = Get-TFToolkitWindowsBuild
        WindowsRevision  = Get-TFToolkitWindowsRevision
        WindowsEdition   = Get-TFToolkitWindowsEditionId
        WindowsVersion   = [string](Get-TFToolkitRegistryValueOrNull -Path $currentVersion -Name "DisplayVersion")
        Now              = Get-Date
    }
}


function New-TFToolkitAuditCheck {
    <#
    Um ponto da auditoria. Status: Ok, Warn (merece atenção), Bad (risco real) ou Unknown (não foi possível verificar).
    Weight 0 = só informa e não entra na nota. Critical = um Bad aqui deixa a nota em no máximo 74.
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateSet("Ok", "Warn", "Bad", "Unknown")]
        [string]$Status,

        [int]$Weight = 0,
        [string]$Detail = "",
        [string]$Advice = "",
        [switch]$Critical
    )

    return [PSCustomObject]@{
        Id       = $Id
        Title    = $Title
        Status   = $Status
        Weight   = $Weight
        Detail   = $Detail
        # Num ponto que só informa (peso 0), o conselho vale também com tudo certo: o BitLocker ligado lembra de guardar a chave.
        Advice   = $(if ($Status -in "Warn", "Bad" -or $Weight -eq 0) { $Advice } else { "" })
        Critical = [bool]$Critical
    }
}


function Get-TFToolkitWindowsSupportCheck {
    <#
    O ponto "Suporte do Windows" da auditoria: se esta versão ainda recebe correções de segurança. A resposta é a mesma da
    tela Diagnóstico > Suporte do Windows e do Início (Get-TFToolkitWindowsSupportStatus): as datas vêm do catálogo, a
    edição passa pela mesma regra (sem ela, vale o prazo de Home e Pro, o mais curto) e o ESU do Windows 10 é conferido
    pela build instalada. Sem suporte é risco real (Bad); acabando em breve ou no ESU, ressalva (Warn).
    #>
    param (
        [Parameter(Mandatory)]
        $Facts
    )

    $title = (Get-TFToolkitText 'Suporte do Windows')
    $build = [int]$Facts.WindowsBuild
    $edition = [string](Get-TFToolkitJsonValue -Object $Facts -Name "WindowsEdition" -Default "")
    $displayVersion = [string](Get-TFToolkitJsonValue -Object $Facts -Name "WindowsVersion" -Default "")

    if ($build -lt 10240) {
        return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Unknown -Weight 15 -Detail (Get-TFToolkitText 'Não foi possível identificar a versão'))
    }

    try {
        $status = Get-TFToolkitWindowsSupportStatus -Build $build -EditionId $edition -Revision (Get-TFToolkitJsonValue -Object $Facts -Name "WindowsRevision") -Today ([datetime]$Facts.Now).Date
    }
    catch {
        return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Unknown -Weight 15 -Detail (Get-TFToolkitText 'Não foi possível conferir as datas de suporte'))
    }

    $label = [string]$status.Product
    if ($status.Class -eq "Ltsc") { $label += $(if ($edition -match '^IoT') { " (IoT Enterprise LTSC)" } else { (Get-TFToolkitText ' (LTSC)') }) }

    $endText = $(if ($status.EndDate -is [datetime]) { Format-TFToolkitDateTime -When $status.EndDate -Pattern "dd/MM/yyyy" } else { "" })
    $advice = ([string]$status.Advice).TrimEnd(".")

    switch ([string]$status.State) {
        "Supported" {
            return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Ok -Weight 15 -Detail (Get-TFToolkitText '{0}: correções de segurança até {1}' "${label}" "$endText"))
        }
        "EndingSoon" {
            return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Warn -Weight 15 -Detail $(if ([int]$status.DaysLeft -le 0) { (Get-TFToolkitText '{0}: as correções de segurança terminam hoje ({1})' "${label}" "$endText") } else { (Get-TFToolkitText '{0}: as correções de segurança acabam em {1} ({2})' "${label}" "$endText" "$(Get-TFToolkitSupportDaysText -Days $status.DaysLeft)") }) -Advice $advice)
        }
        "Esu" {
            return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Warn -Weight 15 -Detail (Get-TFToolkitText '{0}: correções pelo programa ESU{1}; o suporte normal acabou em {2}' "${label}" "$(if ($status.EsuEnd -is [datetime]) { (Get-TFToolkitText ' até {0}' "$(Format-TFToolkitDateTime -When $status.EsuEnd -Pattern 'dd/MM/yyyy')") } else { (Get-TFToolkitText ' da organização') })" "$endText") -Advice $advice)
        }
        "EsuAvailable" {
            if (-not [bool]$status.EsuChecked) {
                # Sem a build instalada, não dá para dizer se o PC está no ESU: fica como não verificado.
                return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Unknown -Weight 15 -Detail (Get-TFToolkitText '{0}: o suporte gratuito terminou em {1} e não foi possível conferir o programa ESU' "${label}" "$endText"))
            }

            return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Bad -Weight 15 -Detail (Get-TFToolkitText '{0}: o suporte gratuito terminou em {1}, e nenhuma correção do programa ESU foi instalada' "${label}" "$endText") -Advice $advice)
        }
        "Ended" {
            $since = $(if ($endText) { (Get-TFToolkitText 'a última correção de segurança saiu em {0}' "$endText") } else { (Get-TFToolkitText 'sem correções de segurança') })
            return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Bad -Weight 15 -Detail "${label}: $since" -Advice $advice)
        }
    }

    # Fora da lista de datas (Windows 11 mais novo que ela, prévia do Insider): o nome, sem prometer prazo.
    $unknownLabel = $(if ($displayVersion) { (Get-TFToolkitText 'Windows 11 versão {0}' "$displayVersion") } else { $label })

    return (New-TFToolkitAuditCheck -Id "windows-support" -Title $title -Status Unknown -Weight 15 -Detail (Get-TFToolkitText '{0}: versão fora da lista de datas do TF-Toolkit' "${unknownLabel}"))
}


function Get-TFToolkitSecurityAuditChecks {
    # Transforma o que foi lido (Get-TFToolkitSecurityAuditFacts) nos pontos da auditoria, do mais importante ao menos.
    param (
        [Parameter(Mandatory)]
        $Facts
    )

    $checks = @()
    $antivirus = $Facts.Antivirus

    # O que o Windows nega sem Administrador diz isso na própria linha, e não "não foi possível ler" (ou um motivo errado).
    $needsAdmin = (-not [bool](Get-TFToolkitJsonValue -Object $Facts -Name "Administrator" -Default $true))
    $adminText = (Get-TFToolkitText 'Pede o TF-Toolkit aberto como Administrador')

    # Antivírus
    switch ($antivirus.Mode) {
        "Active" {
            $checks += New-TFToolkitAuditCheck -Id "antivirus" -Title (Get-TFToolkitText 'Antivírus') -Status Ok -Weight 30 -Detail (Get-TFToolkitText 'Windows Defender ativo')
        }
        "Other" {
            $checks += New-TFToolkitAuditCheck -Id "antivirus" -Title (Get-TFToolkitText 'Antivírus') -Status Ok -Weight 30 -Detail (Get-TFToolkitText 'Outro antivírus protege o PC ({0})' "$(Join-TFToolkitList -Items @($antivirus.Others))")
        }
        "Passive" {
            $checks += New-TFToolkitAuditCheck -Id "antivirus" -Title (Get-TFToolkitText 'Antivírus') -Status Warn -Weight 30 -Detail (Get-TFToolkitText 'O Windows Defender está em modo passivo e nenhum outro antivírus ligado foi identificado') `
                -Advice (Get-TFToolkitText 'Confirme em Segurança > Segurança do Windows se há outro antivírus ativo; sem ele, o PC fica desprotegido')
        }
        "Off" {
            $checks += New-TFToolkitAuditCheck -Id "antivirus" -Title (Get-TFToolkitText 'Antivírus') -Status Bad -Weight 30 -Critical -Detail (Get-TFToolkitText 'Desligado e nenhum outro antivírus ligado foi encontrado') `
                -Advice (Get-TFToolkitText 'Ligue o antivírus em Segurança > Segurança do Windows')
        }
        default {
            $checks += New-TFToolkitAuditCheck -Id "antivirus" -Title (Get-TFToolkitText 'Antivírus') -Status Unknown -Weight 30 -Detail (Get-TFToolkitText 'Não foi possível ler o estado')
        }
    }

    if ($antivirus.Mode -eq "Active") {
        if ($antivirus.RealTime -eq $false) {
            $checks += New-TFToolkitAuditCheck -Id "realtime" -Title (Get-TFToolkitText 'Proteção em tempo real') -Status Bad -Weight 15 -Critical -Detail (Get-TFToolkitText 'Desligada') `
                -Advice (Get-TFToolkitText 'Ligue a proteção em tempo real em Segurança > Segurança do Windows')
        }
        elseif ($antivirus.RealTime -eq $true) {
            $checks += New-TFToolkitAuditCheck -Id "realtime" -Title (Get-TFToolkitText 'Proteção em tempo real') -Status Ok -Weight 15 -Detail (Get-TFToolkitText 'Ligada')
        }

        $tamper = Get-TFToolkitJsonValue -Object $antivirus -Name "TamperProtected"

        if ($tamper -eq $false) {
            $checks += New-TFToolkitAuditCheck -Id "tamper" -Title (Get-TFToolkitText 'Proteção contra adulterações') -Status Warn -Weight 5 -Detail (Get-TFToolkitText 'Desligada') `
                -Advice (Get-TFToolkitText 'Ligue-a em Segurança > Segurança do Windows; ela impede que vírus desliguem o antivírus')
        }
        elseif ($tamper -eq $true) {
            $checks += New-TFToolkitAuditCheck -Id "tamper" -Title (Get-TFToolkitText 'Proteção contra adulterações') -Status Ok -Weight 5 -Detail (Get-TFToolkitText 'Ligada')
        }

        $age = Get-TFToolkitJsonValue -Object $antivirus -Name "SignatureAgeDays"

        if ([bool](Get-TFToolkitJsonValue -Object $antivirus -Name "SignaturesNeverUpdated" -Default $false)) {
            # Nunca atualizadas (as que vêm com o Windows, de meses atrás): o mesmo ponto do Estado da proteção e do Início,
            # e não "não foi possível ler".
            $checks += New-TFToolkitAuditCheck -Id "signatures" -Title (Get-TFToolkitText 'Assinaturas do antivírus') -Status Bad -Weight 10 -Detail (Get-TFToolkitText 'Nunca atualizadas') `
                -Advice (Get-TFToolkitText 'Use Segurança > Atualizar assinaturas do antivírus')
        }
        elseif ($null -eq $age) {
            # Sem a data das assinaturas, o ponto não some da conta em silêncio: fica como não verificado, e a tela diz.
            $checks += New-TFToolkitAuditCheck -Id "signatures" -Title (Get-TFToolkitText 'Assinaturas do antivírus') -Status Unknown -Weight 10 -Detail (Get-TFToolkitText 'Não foi possível ler a data da última atualização')
        }
        else {
            if ($age -gt 7) {
                $checks += New-TFToolkitAuditCheck -Id "signatures" -Title (Get-TFToolkitText 'Assinaturas do antivírus') -Status Bad -Weight 10 -Detail (Get-TFToolkitText 'Têm {0} dias' "$age") `
                    -Advice (Get-TFToolkitText 'Use Segurança > Atualizar assinaturas do antivírus')
            }
            elseif ($age -gt 3) {
                $checks += New-TFToolkitAuditCheck -Id "signatures" -Title (Get-TFToolkitText 'Assinaturas do antivírus') -Status Warn -Weight 10 -Detail (Get-TFToolkitText 'Têm {0} dias; o normal é atualizarem todo dia' "$age") `
                    -Advice (Get-TFToolkitText 'Use Segurança > Atualizar assinaturas do antivírus')
            }
            else {
                $checks += New-TFToolkitAuditCheck -Id "signatures" -Title (Get-TFToolkitText 'Assinaturas do antivírus') -Status Ok -Weight 10 -Detail $(
                    # "há 12 horas", e não "hoje": atualizadas às 23h de ontem, às 8h ainda têm menos de um dia.
                    $updated = Get-TFToolkitJsonValue -Object $antivirus -Name "SignaturesUpdated"
                    if ($updated -is [datetime]) { (Get-TFToolkitText 'Atualizadas {0}' "$(Format-TFToolkitRelativeTime -When $updated -Now ([datetime]$Facts.Now))") }
                    elseif ($age -le 0) { (Get-TFToolkitText 'Atualizadas há menos de um dia') }
                    else { (Get-TFToolkitText 'Atualizadas há {0}' "$(Format-TFToolkitCount -Count $age -One (Get-TFToolkitText 'dia') -Many (Get-TFToolkitText 'dias'))") }
                )
            }
        }
    }

    # Ameaças ativas: como na tela Estado da proteção, a lista do Defender só é avaliada quando ele protege o PC. Com
    # outro antivírus no lugar, o Defender não responder é o esperado (não é "sem verificar"), e o que ele ainda guarda
    # é ressalva: quem decide é o outro antivírus.
    if ($null -ne $Facts.Threats -and @($Facts.Threats).Count -gt 0) {
        $threatList = "$(@($Facts.Threats).Count): $(Get-TFToolkitThreatListText -Threats @($Facts.Threats))"

        if ($antivirus.Mode -eq "Other") {
            $checks += New-TFToolkitAuditCheck -Id "threats" -Title (Get-TFToolkitText 'Ameaças no Defender') -Status Warn -Weight 20 -Detail $threatList `
                -Advice (Get-TFToolkitText 'Abra Segurança > Segurança do Windows e confira as ameaças que o Defender ainda guarda; confirme também no outro antivírus')
        }
        else {
            $checks += New-TFToolkitAuditCheck -Id "threats" -Title (Get-TFToolkitText 'Ameaças ativas') -Status Bad -Weight 20 -Critical -Detail $threatList `
                -Advice (Get-TFToolkitText 'Abra Segurança > Segurança do Windows e aplique as ações indicadas para cada ameaça')
        }
    }
    elseif ($antivirus.Mode -eq "Active") {
        if ($null -eq $Facts.Threats) {
            $checks += New-TFToolkitAuditCheck -Id "threats" -Title (Get-TFToolkitText 'Ameaças ativas') -Status Unknown -Weight 20 -Detail $(if ($needsAdmin) { $adminText } else { (Get-TFToolkitText 'Não foi possível consultar') })
        }
        else {
            $checks += New-TFToolkitAuditCheck -Id "threats" -Title (Get-TFToolkitText 'Ameaças ativas') -Status Ok -Weight 20 -Detail (Get-TFToolkitText 'Nenhuma')
        }
    }

    # Firewall
    if ($null -eq $Facts.Firewall) {
        $checks += New-TFToolkitAuditCheck -Id "firewall" -Title (Get-TFToolkitText 'Firewall') -Status Unknown -Weight 20 -Detail (Get-TFToolkitText 'Não foi possível ler')
    }
    else {
        $off = @(Get-TFToolkitFirewallGaps -Firewall $Facts.Firewall)
        $unused = @($Facts.Firewall | Where-Object { -not $_.Enabled -and -not [bool](Get-TFToolkitJsonValue -Object $_ -Name "Applies" -Default $true) })

        $otherFirewall = Get-TFToolkitFirewallOtherProduct -Firewall $Facts.Firewall

        if ($off.Count -eq 0 -and $otherFirewall) {
            $checks += New-TFToolkitAuditCheck -Id "firewall" -Title (Get-TFToolkitText 'Firewall') -Status Ok -Weight 20 -Detail (Get-TFToolkitText 'Outro firewall protege o PC ({0})' "$otherFirewall")
        }
        elseif ($off.Count -eq 0 -and $unused.Count -gt 0) {
            $checks += New-TFToolkitAuditCheck -Id "firewall" -Title (Get-TFToolkitText 'Firewall') -Status Ok -Weight 20 -Detail (Get-TFToolkitText 'Ligado nas redes privada e pública (o perfil Domínio, desligado, não vale para este PC)')
        }
        elseif ($off.Count -eq 0) {
            $checks += New-TFToolkitAuditCheck -Id "firewall" -Title (Get-TFToolkitText 'Firewall') -Status Ok -Weight 20 -Detail (Get-TFToolkitText 'Ligado em todos os perfis de rede')
        }
        else {
            $names = @($off | ForEach-Object { Get-TFToolkitFirewallProfileName -Name $_.Name })
            $publicOff = @($off | Where-Object { $_.Name -eq "Public" }).Count -gt 0

            $checks += New-TFToolkitAuditCheck -Id "firewall" -Title (Get-TFToolkitText 'Firewall') -Status $(if ($publicOff) { "Bad" } else { "Warn" }) -Weight 20 -Critical:$publicOff `
                -Detail (Get-TFToolkitText 'Desligado em: {0}' "$(Join-TFToolkitList -Items $names)") -Advice (Get-TFToolkitText 'Ligue o firewall em Segurança > Segurança do Windows')
        }
    }

    # Controle de Conta de Usuário
    if ($null -eq $Facts.UacEnabled) {
        $checks += New-TFToolkitAuditCheck -Id "uac" -Title (Get-TFToolkitText 'Controle de Conta de Usuário (UAC)') -Status Unknown -Weight 15 -Detail (Get-TFToolkitText 'Não foi possível ler')
    }
    elseif ($Facts.UacEnabled -and [bool](Get-TFToolkitJsonValue -Object $Facts -Name "UacNeverNotify" -Default $false)) {
        $checks += New-TFToolkitAuditCheck -Id "uac" -Title (Get-TFToolkitText 'Controle de Conta de Usuário (UAC)') -Status Bad -Weight 15 -Critical -Detail (Get-TFToolkitText 'No nível ''Nunca notificar'': os programas ganham Administrador sem perguntar') `
            -Advice (Get-TFToolkitText 'Procure ''Alterar configurações de Controle de Conta de Usuário'' no menu Iniciar e escolha um nível acima de ''Nunca notificar''')
    }
    elseif ($Facts.UacEnabled) {
        $checks += New-TFToolkitAuditCheck -Id "uac" -Title (Get-TFToolkitText 'Controle de Conta de Usuário (UAC)') -Status Ok -Weight 15 -Detail (Get-TFToolkitText 'Ligado')
    }
    else {
        $checks += New-TFToolkitAuditCheck -Id "uac" -Title (Get-TFToolkitText 'Controle de Conta de Usuário (UAC)') -Status Bad -Weight 15 -Critical -Detail (Get-TFToolkitText 'Desligado') `
            -Advice (Get-TFToolkitText 'Procure ''Alterar configurações de Controle de Conta de Usuário'' no menu Iniciar, escolha um nível acima de ''Nunca notificar'' e reinicie o PC')
    }

    # SmartScreen
    if ($Facts.SmartScreenOff) {
        $checks += New-TFToolkitAuditCheck -Id "smartscreen" -Title "SmartScreen" -Status Warn -Weight 5 -Detail (Get-TFToolkitText 'Desligado') `
            -Advice (Get-TFToolkitText 'Ligue-o em Segurança > Segurança do Windows; ele avisa sobre programas e sites perigosos')
    }
    elseif ([bool](Get-TFToolkitJsonValue -Object $Facts -Name "SmartScreenSet" -Default $false)) {
        $checks += New-TFToolkitAuditCheck -Id "smartscreen" -Title "SmartScreen" -Status Ok -Weight 5 -Detail (Get-TFToolkitText 'Ligado')
    }
    else {
        # Nada gravado: vale o padrão do Windows, que é ligado.
        $checks += New-TFToolkitAuditCheck -Id "smartscreen" -Title "SmartScreen" -Status Ok -Weight 5 -Detail (Get-TFToolkitText 'Ligado (o padrão do Windows)')
    }

    # Atualizações pendentes
    if ($null -eq $Facts.Updates) {
        $checks += New-TFToolkitAuditCheck -Id "updates" -Title (Get-TFToolkitText 'Atualizações do Windows') -Status Unknown -Weight 10 -Detail (Get-TFToolkitText 'Não foi possível consultar o Windows Update')
    }
    elseif ($Facts.Updates.Count -gt 0) {
        $checks += New-TFToolkitAuditCheck -Id "updates" -Title (Get-TFToolkitText 'Atualizações do Windows') -Status Warn -Weight 10 -Detail (Format-TFToolkitCount -Count $Facts.Updates.Count -One (Get-TFToolkitText 'pendente') -Many (Get-TFToolkitText 'pendentes')) `
            -Advice (Get-TFToolkitText 'Use Atualizações > Instalar atualizações do Windows')
    }
    else {
        $checks += New-TFToolkitAuditCheck -Id "updates" -Title (Get-TFToolkitText 'Atualizações do Windows') -Status Ok -Weight 10 -Detail (Get-TFToolkitText 'Nenhuma pendente')
    }

    # Versão do Windows ainda recebe correções?
    $checks += Get-TFToolkitWindowsSupportCheck -Facts $Facts

    # Área de Trabalho Remota
    if ($null -eq $Facts.RdpEnabled) {
        $checks += New-TFToolkitAuditCheck -Id "rdp" -Title (Get-TFToolkitText 'Área de Trabalho Remota') -Status Unknown -Weight 10 -Detail (Get-TFToolkitText 'Não foi possível ler')
    }
    else {
        # Com uma política decidindo, o botão das Configurações fica travado: o conselho diz onde ela se muda.
        $rdpByPolicy = [bool](Get-TFToolkitJsonValue -Object $Facts -Name "RdpByPolicy" -Default $false)

        if ($Facts.RdpEnabled -and $rdpByPolicy) {
            $checks += New-TFToolkitAuditCheck -Id "rdp" -Title (Get-TFToolkitText 'Área de Trabalho Remota') -Status Warn -Weight 10 -Detail (Get-TFToolkitText 'Ligada por uma política: outros computadores podem tentar entrar neste') `
                -Advice (Get-TFToolkitText 'Uma política trava o botão das Configurações: se você não usa o acesso remoto, desligue-a no Editor de Política de Grupo ou peça a quem cuida dos PCs da empresa')
        }
        elseif ($Facts.RdpEnabled) {
            $checks += New-TFToolkitAuditCheck -Id "rdp" -Title (Get-TFToolkitText 'Área de Trabalho Remota') -Status Warn -Weight 10 -Detail (Get-TFToolkitText 'Ligada: outros computadores podem tentar entrar neste') `
                -Advice (Get-TFToolkitText 'Se você não usa o acesso remoto, desligue-o em Configurações, Sistema, Área de Trabalho Remota')
        }
        else {
            $checks += New-TFToolkitAuditCheck -Id "rdp" -Title (Get-TFToolkitText 'Área de Trabalho Remota') -Status Ok -Weight 10 -Detail $(if ($rdpByPolicy) { (Get-TFToolkitText 'Desligada por uma política') } else { (Get-TFToolkitText 'Desligada') })
        }
    }

    # Conta Convidado
    if ($null -eq $Facts.GuestEnabled) {
        $checks += New-TFToolkitAuditCheck -Id "guest" -Title (Get-TFToolkitText 'Conta Convidado') -Status Unknown -Weight 8 -Detail (Get-TFToolkitText 'Não foi possível ler')
    }
    else {
        if ($Facts.GuestEnabled) {
            # O comando com o nome da conta neste Windows: "net user Guest" não acha a conta de um Windows em português.
            $guestName = [string](Get-TFToolkitJsonValue -Object $Facts -Name "GuestName" -Default "")
            $checks += New-TFToolkitAuditCheck -Id "guest" -Title (Get-TFToolkitText 'Conta Convidado') -Status Warn -Weight 8 -Detail (Get-TFToolkitText 'Ligada: permite entrar sem senha') `
                -Advice $(if ($guestName) { (Get-TFToolkitText 'No menu Iniciar, procure Prompt de Comando, escolha Executar como administrador e digite: net user "{0}" /active:no' "$guestName") } else { (Get-TFToolkitText 'No menu Iniciar, procure Prompt de Comando, escolha Executar como administrador e digite: net user Convidado /active:no') })
        }
        else {
            $checks += New-TFToolkitAuditCheck -Id "guest" -Title (Get-TFToolkitText 'Conta Convidado') -Status Ok -Weight 8 -Detail (Get-TFToolkitText 'Desativada')
        }
    }

    # SMB 1.0: só entra quando foi lido (os fatos montados à mão por outra parte do TF-Toolkit podem não trazê-lo).
    if ($null -ne $Facts.PSObject.Properties["Smb1"]) {
        $smbTitle = (Get-TFToolkitText 'Compartilhamento SMB 1.0')

        if ($null -eq $Facts.Smb1) {
            $checks += New-TFToolkitAuditCheck -Id "smb1" -Title $smbTitle -Status Unknown -Weight 8 -Detail $(if ($needsAdmin) { $adminText } else { (Get-TFToolkitText 'Não foi possível ler') })
        }
        elseif ([string]$Facts.Smb1 -eq "On") {
            $checks += New-TFToolkitAuditCheck -Id "smb1" -Title $smbTitle -Status Warn -Weight 8 -Detail (Get-TFToolkitText 'Ligado: protocolo antigo e inseguro de arquivos em rede, usado por ataques como o WannaCry') `
                -Advice (Get-TFToolkitText 'Se nenhum equipamento antigo (scanner, NAS) precisa dele, desligue-o em Programas > Recursos opcionais do Windows')
        }
        else {
            $checks += New-TFToolkitAuditCheck -Id "smb1" -Title $smbTitle -Status Ok -Weight 8 -Detail (Get-TFToolkitText 'Desligado')
        }
    }

    # Entrada automática no Windows
    if ($Facts.AutoLogon -and $Facts.PasswordStored) {
        $checks += New-TFToolkitAuditCheck -Id "autologon" -Title (Get-TFToolkitText 'Entrada automática') -Status Bad -Weight 8 -Detail (Get-TFToolkitText 'Ligada, com a senha gravada em texto no registro') `
            -Advice (Get-TFToolkitText 'No menu Iniciar, digite netplwiz, pressione Enter e marque ''Os usuários devem digitar um nome de usuário e uma senha para usar este computador''; depois troque a senha dessa conta')
    }
    elseif ($Facts.AutoLogon) {
        $checks += New-TFToolkitAuditCheck -Id "autologon" -Title (Get-TFToolkitText 'Entrada automática') -Status Warn -Weight 8 -Detail (Get-TFToolkitText 'Ligada: quem ligar o PC entra sem senha') `
            -Advice (Get-TFToolkitText 'Se o PC sai de casa: no menu Iniciar, digite netplwiz, pressione Enter e marque ''Os usuários devem digitar um nome de usuário e uma senha para usar este computador''')
    }
    else {
        $checks += New-TFToolkitAuditCheck -Id "autologon" -Title (Get-TFToolkitText 'Entrada automática') -Status Ok -Weight 8 -Detail (Get-TFToolkitText 'Desligada')
    }

    # Só informam (não entram na nota)
    if ($null -eq $Facts.BitLocker) {
        $checks += New-TFToolkitAuditCheck -Id "bitlocker" -Title (Get-TFToolkitText 'Criptografia do disco') -Status Unknown -Detail $(if ($needsAdmin) { $adminText } else { (Get-TFToolkitText 'Não verificada (esta edição do Windows pode não ter o BitLocker)') })
    }
    elseif ($Facts.BitLocker -eq "On") {
        # Com o disco protegido, o que falta é ter a chave de recuperação fora do PC.
        $checks += New-TFToolkitAuditCheck -Id "bitlocker" -Title (Get-TFToolkitText 'Criptografia do disco') -Status Ok -Detail (Get-TFToolkitText 'Ligada no disco do sistema') `
            -Advice (Get-TFToolkitText 'Guarde uma cópia da chave de recuperação fora do PC em Segurança > Chave de recuperação do BitLocker')
    }
    elseif ($Facts.BitLocker -eq "Suspended") {
        # A proteção costuma ficar suspensa depois de uma atualização da BIOS.
        $checks += New-TFToolkitAuditCheck -Id "bitlocker" -Title (Get-TFToolkitText 'Criptografia do disco') -Status Warn -Detail (Get-TFToolkitText 'Criptografado, mas com a proteção suspensa: a chave fica gravada no disco') `
            -Advice (Get-TFToolkitText 'Retome a proteção no Painel de Controle, em Criptografia de Unidade de Disco BitLocker (ou em Criptografia do dispositivo)')
    }
    elseif ($Facts.BitLocker -eq "Encrypting") {
        $checks += New-TFToolkitAuditCheck -Id "bitlocker" -Title (Get-TFToolkitText 'Criptografia do disco') -Status Ok -Detail (Get-TFToolkitText 'Criptografando o disco do sistema; a proteção liga quando terminar')
    }
    elseif ($Facts.BitLocker -eq "Pending") {
        $checks += New-TFToolkitAuditCheck -Id "bitlocker" -Title (Get-TFToolkitText 'Criptografia do disco') -Status Warn -Detail (Get-TFToolkitText 'O disco do sistema está preparado, mas a criptografia espera ativação') `
            -Advice (Get-TFToolkitText 'Ligue-a em Configurações, Privacidade e segurança, Criptografia do dispositivo; ela guarda a chave de recuperação na sua conta Microsoft')
    }
    else {
        $checks += New-TFToolkitAuditCheck -Id "bitlocker" -Title (Get-TFToolkitText 'Criptografia do disco') -Status Warn -Detail (Get-TFToolkitText 'Desligada no disco do sistema') `
            -Advice (Get-TFToolkitText 'Em notebooks, a criptografia protege seus arquivos se o PC for perdido ou roubado')
    }

    if ($null -eq $Facts.SecureBoot) {
        $checks += New-TFToolkitAuditCheck -Id "secureboot" -Title (Get-TFToolkitText 'Inicialização segura (Secure Boot)') -Status Unknown -Detail (Get-TFToolkitText 'Não verificada')
    }
    elseif ([string]$Facts.SecureBoot -eq "Legacy") {
        $checks += New-TFToolkitAuditCheck -Id "secureboot" -Title (Get-TFToolkitText 'Inicialização segura (Secure Boot)') -Status Warn -Detail (Get-TFToolkitText 'Indisponível: o Windows iniciou no modo BIOS legado') `
            -Advice (Get-TFToolkitText 'Ela pede o modo UEFI, trabalho para um técnico')
    }
    elseif ($Facts.SecureBoot -eq $true) {
        $checks += New-TFToolkitAuditCheck -Id "secureboot" -Title (Get-TFToolkitText 'Inicialização segura (Secure Boot)') -Status Ok -Detail (Get-TFToolkitText 'Ligada')
    }
    else {
        $checks += New-TFToolkitAuditCheck -Id "secureboot" -Title (Get-TFToolkitText 'Inicialização segura (Secure Boot)') -Status Warn -Detail (Get-TFToolkitText 'Desligada') `
            -Advice (Get-TFToolkitText 'Ligue-a na configuração da placa-mãe (UEFI); ela impede vírus de carregar antes do Windows')
    }

    # Integridade da memória: só entra quando foi lida (os fatos montados à mão por outra parte do TF-Toolkit podem não
    # trazê-la). Só informa: alguns drivers e programas não funcionam com ela ligada.
    if ($null -ne $Facts.PSObject.Properties["MemoryIntegrity"]) {
        $hvciTitle = (Get-TFToolkitText 'Integridade da memória')
        $hvciPath = (Get-TFToolkitText 'Segurança do Windows > Segurança do dispositivo > Detalhes de isolamento do núcleo')

        switch ([string]$Facts.MemoryIntegrity) {
            "On" {
                $checks += New-TFToolkitAuditCheck -Id "memory-integrity" -Title $hvciTitle -Status Ok -Detail (Get-TFToolkitText 'Ligada')
            }
            "Pending" {
                $checks += New-TFToolkitAuditCheck -Id "memory-integrity" -Title $hvciTitle -Status Warn -Detail (Get-TFToolkitText 'Ligada nas configurações, mas fora de uso') `
                    -Advice (Get-TFToolkitText 'Reinicie o PC; se continuar assim, veja o motivo em {0}' "$hvciPath")
            }
            "Off" {
                $checks += New-TFToolkitAuditCheck -Id "memory-integrity" -Title $hvciTitle -Status Warn -Detail (Get-TFToolkitText 'Desligada') `
                    -Advice (Get-TFToolkitText 'Ligue-a em {0}; alguns drivers e programas antigos não funcionam com ela' "$hvciPath")
            }
            default {
                $checks += New-TFToolkitAuditCheck -Id "memory-integrity" -Title $hvciTitle -Status Unknown -Detail $(if ($needsAdmin) { $adminText } else { (Get-TFToolkitText 'Não foi possível ler') })
            }
        }
    }

    return @($checks)
}


function Get-TFToolkitSecurityGrade {
    <#
    A nota da auditoria, de 0 a 100, com as mesmas faixas da nota de saúde do Início (Grade): Ótima de 90, Boa de 75,
    Pede atenção de 50, senão Crítica. Ok vale o peso inteiro, Warn metade e Bad zero; o que não pôde ser verificado
    (Unknown) e o que só informa (peso 0) ficam fora da conta.
    Sem nota ("?", Score nulo) quando menos da metade do peso pôde ser verificada (NoGradeReason = "Coverage"): uma nota
    alta tirada só da conta Convidado e da entrada automática diria que o PC está protegido sem ter olhado o antivírus.
    Pelo mesmo motivo, também não há nota quando o próprio antivírus não pôde ser verificado (NoGradeReason =
    "Antivirus"), mesmo com o resto lido: sem saber se há um antivírus ativo, nenhuma nota diz se o PC está protegido.
    Unverified diz quantos pontos com peso ficaram de fora; Verified e Total, quantos pontos com peso existem e quantos
    foram lidos. Dois tetos evitam uma nota alta com um problema real: qualquer ponto em Bad deixa a nota em no máximo 89
    (fora de Ótima), e um problema grave (Critical + Bad: antivírus, tempo real, ameaças, firewall público ou UAC) em no
    máximo 74 (fora do verde), como um ponto grave no Início. Cap é o teto aplicado (74, 89 ou nulo) e Capped diz se ele
    baixou a nota.
    #>
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Checks
    )

    $weighted = @($Checks | Where-Object { $_.Weight -gt 0 })
    $scored = @($weighted | Where-Object { $_.Status -ne "Unknown" })
    $unverified = $weighted.Count - $scored.Count
    $totalWeight = 0
    $possible = 0
    $earned = 0.0

    foreach ($check in $weighted) { $totalWeight += $check.Weight }

    foreach ($check in $scored) {
        $possible += $check.Weight

        switch ($check.Status) {
            "Ok"   { $earned += $check.Weight }
            "Warn" { $earned += $check.Weight / 2 }
        }
    }

    $antivirusUnknown = (@($weighted | Where-Object { $_.Id -eq "antivirus" -and $_.Status -eq "Unknown" }).Count -gt 0)
    $noGradeReason = $(if ($possible -eq 0 -or ($possible * 2) -lt $totalWeight) { "Coverage" } elseif ($antivirusUnknown) { "Antivirus" } else { "" })

    if ($noGradeReason) {
        return [PSCustomObject]@{ Score = $null; Grade = "?"; Cap = $null; Capped = $false; Scored = $scored.Count; Unverified = $unverified; Verified = $scored.Count; Total = $weighted.Count; NoGradeReason = $noGradeReason }
    }

    $score = [int][math]::Round(100 * $earned / $possible, [MidpointRounding]::AwayFromZero)
    $cap = $null

    if (@($scored | Where-Object { $_.Critical -and $_.Status -eq "Bad" }).Count -gt 0) {
        $cap = 74
    }
    elseif (@($scored | Where-Object { $_.Status -eq "Bad" }).Count -gt 0) {
        $cap = 89
    }

    $capped = ($null -ne $cap -and $score -gt $cap)

    if ($capped) { $score = [int]$cap }

    $grade = Get-TFToolkitSecurityGradeLabel -Score $score

    return [PSCustomObject]@{ Score = $score; Grade = $grade; Cap = $cap; Capped = $capped; Scored = $scored.Count; Unverified = $unverified; Verified = $scored.Count; Total = $weighted.Count; NoGradeReason = "" }
}


function Get-TFToolkitSecurityGradeLabel {
    # A faixa de uma nota de 0 a 100, a mesma da nota de saúde do Início: as duas notas do TF-Toolkit falam a mesma língua.
    param ([int]$Score)

    if ($Score -ge 90) { return (Get-TFToolkitText 'Ótima') }
    if ($Score -ge 75) { return (Get-TFToolkitText 'Boa') }
    if ($Score -ge 50) { return (Get-TFToolkitText 'Pede atenção') }

    return (Get-TFToolkitText 'Crítica')
}


function Format-TFToolkitSecurityGrade {
    # "84 de 100 · Boa" (a nota com a faixa), como a tela e a linha de comando mostram.
    param ([Parameter(Mandatory)]$Grade)

    if ($null -eq $Grade.Score) { return (Get-TFToolkitText 'sem nota') }

    return (Get-TFToolkitText '{0} de 100 · {1}' "$($Grade.Score)" "$($Grade.Grade)")
}


function Get-TFToolkitSecurityAuditStatusType {
    param ([Parameter(Mandatory)][string]$Status)

    switch ($Status) {
        "Ok"    { return "Success" }
        "Warn"  { return "Warning" }
        "Bad"   { return "Error" }
        default { return "Info" }
    }
}


function Show-TFToolkitSecurityAudit {
    <#
    Confere vários pontos da proteção do PC e dá uma nota. Só lê: nada é ligado, desligado ou alterado.
    #>
    param (
        [switch]$Embedded,
        [switch]$PassThru
    )

    $title = (Get-TFToolkitText 'Auditoria de segurança')

    Enter-TFToolkitAction -Title $title -Embedded:$Embedded

    $result = $null

    try {
        # A auditoria só lê as configurações do PC: nada é alterado (por isso não há pergunta antes).
        # O andamento vai na barra: linhas "Consultando..." ficariam no resumo depois do fim.
        # A consulta ao Windows Update, a mais demorada, começa antes e corre enquanto o resto é lido.
        $search = Start-TFToolkitPendingUpdatesSearch
        Write-Progress -Activity $title -Status (Get-TFToolkitText 'consultando o antivírus, o firewall e as configurações do Windows')

        try {
            $facts = Get-TFToolkitSecurityAuditFacts
            Write-Progress -Activity $title -Status (Get-TFToolkitText 'consultando o Windows Update (pode levar até um minuto e meio)')
            $facts.Updates = Get-TFToolkitPendingWindowsUpdates -Search $search
        }
        finally {
            Write-Progress -Activity $title -Completed

            # Sem chegar a pedir a resposta (um erro numa leitura, ou o Parar), a consulta não fica rodando.
            Stop-TFToolkitInBackground -Task $search
        }

        $checks = @(Get-TFToolkitSecurityAuditChecks -Facts $facts)
        $grade = Get-TFToolkitSecurityGrade -Checks $checks
        $unverifiedChecks = @($checks | Where-Object { $_.Weight -gt 0 -and $_.Status -eq "Unknown" })

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Nota')

        # Por que não há nota: o antivírus sem leitura, ou menos da metade da proteção verificada.
        $noGradeAntivirus = ([string](Get-TFToolkitJsonValue -Object $grade -Name "NoGradeReason" -Default "") -eq "Antivirus")
        $coverage = $(
            if ($noGradeAntivirus) { (Get-TFToolkitText 'o antivírus não pôde ser verificado') }
            elseif ($grade.Verified -eq 0) { (Get-TFToolkitText 'nenhum ponto pôde ser verificado') }
            else { (Get-TFToolkitText 'só {0} de {1} pontos puderam ser verificados' "$($grade.Verified)" "$($grade.Total)") }
        )

        if ($null -eq $grade.Score) {
            # O motivo já está na linha da nota: a nota precisa do antivírus verificado (sem saber se há um ativo, ela
            # diria mais do que foi visto) e de pelo menos metade da proteção verificada.
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Nota de segurança') -Value (Get-TFToolkitText 'Sem nota: {0}' "$coverage")
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não puderam ser verificados: {0}.' "$(Join-TFToolkitList -Items @($unverifiedChecks | ForEach-Object { $_.Title }))")
        }
        else {
            $noteText = Format-TFToolkitSecurityGrade -Grade $grade

            if ($unverifiedChecks.Count -gt 0) {
                $noteText += (Get-TFToolkitText ', sem {0}' "$(Format-TFToolkitCount -Count $unverifiedChecks.Count -One (Get-TFToolkitText 'ponto que não pôde ser verificado') -Many (Get-TFToolkitText 'pontos que não puderam ser verificados'))")
            }

            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Nota de segurança') -Value $noteText

            if ($unverifiedChecks.Count -gt 0) {
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Ficaram de fora: {0}.' "$(Join-TFToolkitList -Items @($unverifiedChecks | ForEach-Object { $_.Title }))")
            }

            if ($grade.Capped -and [int]$grade.Cap -eq 74) {
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A nota ficou em no máximo 74 por causa de um problema grave na proteção do PC.')
            }
            elseif ($grade.Capped) {
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A nota ficou em no máximo 89 porque há pelo menos um ponto com risco real.')
            }
        }

        $scoredChecks = @($checks | Where-Object { $_.Weight -gt 0 })
        $infoChecks = @($checks | Where-Object { $_.Weight -eq 0 })

        # O que fazer vem como mensagem logo abaixo do ponto: na janela, fica no resumo (os detalhes técnicos ficam
        # recolhidos quando há faixa de resultado).
        Write-TFToolkitSection -Title (Get-TFToolkitText 'Pontos verificados')

        # O que pede ação primeiro (risco real, depois atenção), depois o que não pôde ser verificado e, por último, o que
        # está em ordem; dentro de cada grupo, a ordem de importância.
        $order = @{ "Bad" = 0; "Warn" = 1; "Unknown" = 2; "Ok" = 3 }
        $position = 0
        $scoredChecks = @($scoredChecks | ForEach-Object { [PSCustomObject]@{ Check = $_; Rank = $order[[string]$_.Status]; Position = $position++ } } | Sort-Object -Property Rank, Position | ForEach-Object { $_.Check })

        foreach ($check in $scoredChecks) {
            Write-TFToolkitStatus -Type (Get-TFToolkitSecurityAuditStatusType -Status $check.Status) -Message "$($check.Title): $($check.Detail)"

            if (-not [string]::IsNullOrWhiteSpace($check.Advice)) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O que fazer: {0}.' "$($check.Advice)")
            }
        }

        if ($infoChecks.Count -gt 0) {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Só para saber (não entram na nota)')

            foreach ($check in $infoChecks) {
                Write-TFToolkitStatus -Type $(if ($check.Status -eq "Ok") { "Success" } else { "Info" }) -Message "$($check.Title): $($check.Detail)"

                if (-not [string]::IsNullOrWhiteSpace($check.Advice)) {
                    Write-TFToolkitStatus -Type Info -Message "$($check.Advice)."
                }
            }
        }

        # Sem Administrador, algumas leituras são negadas pelo Windows (as ameaças guardadas e o BitLocker, por exemplo).
        if (@($checks | Where-Object { $_.Status -eq "Unknown" }).Count -gt 0 -and -not (Test-TFToolkitAdministrator)) {
            Write-Host ""
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Alguns pontos só podem ser verificados com o TF-Toolkit aberto como Administrador.')
        }

        $attention = @($checks | Where-Object { $_.Weight -gt 0 -and $_.Status -in "Warn", "Bad" })
        $attentionText = Format-TFToolkitCount -Count $attention.Count -One (Get-TFToolkitText 'ponto de atenção') -Many (Get-TFToolkitText 'pontos de atenção')
        $unverifiedNote = $(if ($grade.Unverified -gt 0) { (Get-TFToolkitText '; {0} sem verificar' "$($grade.Unverified)") } else { "" })
        $data = @{ Grade = $grade.Grade; Score = $grade.Score }

        if ($null -eq $grade.Score) {
            $detail = (Get-TFToolkitText 'sem nota: {0}' "$coverage")
            if ($attention.Count -gt 0) { $detail += "; $attentionText" }

            $result = New-TFToolkitResult -Kind Warning -Detail $detail -Data $data
        }
        elseif ($attention.Count -eq 0 -and $grade.Unverified -eq 0) {
            $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'nota {0}; nenhum ponto de atenção' "$(Format-TFToolkitSecurityGrade -Grade $grade)") -Data $data
        }
        elseif ($attention.Count -eq 0) {
            # Nenhum problema nos pontos lidos, mas um "tudo certo" só vale se tudo o que pesa na nota foi lido.
            $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'nota {0}; nenhum ponto de atenção no que foi lido{1}' "$(Format-TFToolkitSecurityGrade -Grade $grade)" "$unverifiedNote") -Data $data
        }
        else {
            $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'nota {0}; {1}{2}' "$(Format-TFToolkitSecurityGrade -Grade $grade)" "$attentionText" "$unverifiedNote") -Data $data
        }

        # A faixa da janela: a nota como título; embaixo, os pontos que pedem ação, pelo nome. Vermelho com um problema
        # grave (o que segura a nota em 74) ou nota abaixo de 50; o botão leva aonde se resolve o primeiro da lista.
        $sortedAttention = @($scoredChecks | Where-Object { $_.Status -in "Warn", "Bad" })
        $step = $null

        foreach ($check in $sortedAttention) {
            $step = Get-TFToolkitSecurityNextStep -Id $check.Id
            if ($null -ne $step) { break }
        }

        $headline = $(if ($null -eq $grade.Score) { (Get-TFToolkitText 'Sem nota de segurança') } else { (Get-TFToolkitText 'Nota {0} de 100 · {1}' "$($grade.Score)" "$($grade.Grade)") })
        $noteParts = @()
        if ($null -eq $grade.Score) { $noteParts += "$(ConvertTo-TFToolkitHeadline -Text $coverage)." }
        if ($sortedAttention.Count -gt 0) { $noteParts += "$(ConvertTo-TFToolkitHeadline -Text $attentionText): $(Join-TFToolkitList -Items @($sortedAttention | ForEach-Object { $_.Title }))." }
        if ($grade.Unverified -gt 0 -and $null -ne $grade.Score) { $noteParts += "$(ConvertTo-TFToolkitHeadline -Text (Format-TFToolkitCount -Count $grade.Unverified -One (Get-TFToolkitText 'ponto não pôde ser verificado') -Many (Get-TFToolkitText 'pontos não puderam ser verificados')))." }
        if ($noteParts.Count -eq 0) { $noteParts += (Get-TFToolkitText 'Nenhum ponto de atenção.') }

        $severe = (@($scoredChecks | Where-Object { $_.Critical -and $_.Status -eq "Bad" }).Count -gt 0) -or ($null -ne $grade.Score -and [int]$grade.Score -lt 50)
        $tone = $(if ($severe) { "Bad" } elseif ($sortedAttention.Count -gt 0 -or $grade.Unverified -gt 0 -or $null -eq $grade.Score) { "Warn" } else { "" })

        [void](Set-TFToolkitResultView -Result $result -Headline $headline -Note ($noteParts -join " ") -Tone $tone -Next $(if ($null -ne $step) { $step.Next } else { "" }) -NextLabel $(if ($null -ne $step) { $step.Label } else { "" }))
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro na auditoria de segurança: {0}' "$($_.Exception.Message)")
        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }

    $result.Etapa = $title
    Exit-TFToolkitAction -Embedded:$Embedded -Result $result

    if ($PassThru) {
        return $result
    }
}


# ---------------------------------------------------------------------------
# Chave de recuperação do BitLocker (Segurança > Chave de recuperação do BitLocker)
# ---------------------------------------------------------------------------

function Get-TFToolkitBitLockerVolumes {
    <#
    Os discos com BitLocker (criptografados, criptografando ou preparados): MountPoint (C:), System (o disco do Windows),
    State (On, Suspended, Encrypting ou Pending, como em Get-TFToolkitBitLockerState) e Keys, as chaves de recuperação (Id,
    sem chaves; Password, os 48 números). Pede Administrador; lança erro quando o Windows não responde. As chaves nunca
    vão para a tela nem para o log por aqui.
    #>
    $found = @()

    foreach ($volume in @(Get-BitLockerVolume -ErrorAction Stop)) {
        $status = [string](Get-TFToolkitJsonValue -Object $volume -Name "VolumeStatus" -Default "")
        $protection = [string](Get-TFToolkitJsonValue -Object $volume -Name "ProtectionStatus" -Default "")
        $protectors = @(Get-TFToolkitJsonValue -Object $volume -Name "KeyProtector" -Default @() | Where-Object { $null -ne $_ })

        if ($status -in @("FullyDecrypted", "DecryptionInProgress", "DecryptionSuspended") -and $protection -notin @("On", "1")) { continue }

        $state = $(if ($protection -in @("On", "1")) { "On" }
            elseif ($status -in @("EncryptionInProgress", "EncryptionSuspended")) { "Encrypting" }
            elseif ($protectors.Count -gt 0) { "Suspended" }
            else { "Pending" })

        $keys = @(
            foreach ($protector in $protectors) {
                if ([string](Get-TFToolkitJsonValue -Object $protector -Name "KeyProtectorType" -Default "") -notin @("RecoveryPassword", "3")) { continue }

                [PSCustomObject]@{
                    Id       = ([string](Get-TFToolkitJsonValue -Object $protector -Name "KeyProtectorId" -Default "")).Trim('{', '}')
                    Password = [string](Get-TFToolkitJsonValue -Object $protector -Name "RecoveryPassword" -Default "")
                }
            }
        )

        $mount = ([string](Get-TFToolkitJsonValue -Object $volume -Name "MountPoint" -Default "")).TrimEnd('\')

        $found += [PSCustomObject]@{
            MountPoint = $mount
            System     = ([string](Get-TFToolkitJsonValue -Object $volume -Name "VolumeType" -Default "") -in @("OperatingSystem", "0"))
            State      = $state
            Keys       = @($keys | Where-Object { $_.Password })
        }
    }

    return @($found | Sort-Object @{ Expression = { -not $_.System } }, MountPoint)
}


function Get-TFToolkitBitLockerStateText {
    param ([Parameter(Mandatory)][string]$State)

    switch ($State) {
        "On" { return (Get-TFToolkitText 'protegido') }
        "Suspended" { return (Get-TFToolkitText 'criptografado, com a proteção suspensa') }
        "Encrypting" { return (Get-TFToolkitText 'criptografando') }
        default { return (Get-TFToolkitText 'preparado, esperando ativação') }
    }
}


function Save-TFToolkitBitLockerKeyFile {
    # Grava as chaves num arquivo de texto, com o que fazer com ele. Devolve o caminho. A chave não passa pela tela.
    param (
        [Parameter(Mandatory)][object[]]$Volumes,
        [Parameter(Mandatory)][string]$Folder
    )

    $stamp = (Get-Date).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    $name = (Get-TFToolkitText 'Chave de recuperação BitLocker - {0} - {1}.txt' "$env:COMPUTERNAME" "$stamp")
    $path = Join-Path $Folder $name
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add((Get-TFToolkitText 'Chave de recuperação do BitLocker'))
    $lines.Add((Get-TFToolkitText 'PC: {0}' "$env:COMPUTERNAME"))
    $lines.Add((Get-TFToolkitText 'Guardada pelo TF-Toolkit em {0}.' "$(Format-TFToolkitDateTime -When (Get-Date))"))
    $lines.Add("")

    foreach ($volume in $Volumes) {
        foreach ($key in @($volume.Keys)) {
            $lines.Add((Get-TFToolkitText 'Disco: {0}' "$($volume.MountPoint)"))
            $lines.Add((Get-TFToolkitText 'Identificação da chave: {0}' "$($key.Id)"))
            $lines.Add((Get-TFToolkitText 'Chave de recuperação: {0}' "$($key.Password)"))
            $lines.Add("")
        }
    }

    $lines.Add((Get-TFToolkitText 'Se o PC pedir a chave de recuperação, confira se a identificação na tela começa como a daqui e digite a chave de 48 números.'))
    $lines.Add((Get-TFToolkitText 'Guarde este arquivo fora do PC (num pendrive, impresso ou num e-mail para você): quem tiver esta chave consegue abrir o disco.'))

    [System.IO.File]::WriteAllText($path, ($lines -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding $true))

    return $path
}


function Select-TFToolkitBitLockerKeyFolder {
    # Onde salvar a cópia: um pendrive (as unidades removíveis à vista) ou uma pasta digitada. "" = cancelado.
    $options = @()
    $places = @{}
    $position = 0

    foreach ($drive in @(Get-TFToolkitRemovableDrives | Select-Object -First 9)) {
        $position++
        $places[[string]$position] = $drive.Root
        $options += @{ Key = [string]$position; Label = $drive.Label; Description = (Get-TFToolkitText 'pendrive ou cartão de memória'); Accent = ($position -eq 1) }
    }

    $options += @{ Key = "O"; Label = (Get-TFToolkitText 'Outra pasta'); Description = (Get-TFToolkitText 'Digitar o caminho de uma pasta') }
    $options += @{ Key = "0"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }

    $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Onde salvar a cópia da chave?') -Options $options -ShowMenu

    if ($places.ContainsKey([string]$answer)) { return $places[[string]$answer] }
    if ([string]$answer -ne "O") { return "" }

    # Só caminho completo (E:\Chaves, \\servidor\pasta): um relativo seria conferido numa pasta e gravado noutra.
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $typed = ([string](Read-TFToolkitText -Message (Get-TFToolkitText 'Caminho da pasta (ENTER cancela)'))).Trim().Trim('"')

        if (-not $typed) { return "" }

        $typed = [Environment]::ExpandEnvironmentVariables($typed)

        # "E:" sozinho é a raiz do pendrive.
        if ($typed -match '^[A-Za-z]:$') { $typed += "\" }
        if ($typed -match '^[A-Za-z]:[\\/]' -or $typed -match '^\\\\[^\\]+\\[^\\]+') { return $typed }

        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Digite o caminho completo da pasta, com a letra do disco (por exemplo, E:\Chaves).')
    }

    return ""
}


function Show-TFToolkitBitLockerKey {
    $title = (Get-TFToolkitText 'Chave de recuperação do BitLocker')
    Enter-TFToolkitAction -Title $title

    $final = $null
    $created = @()

    try {
        if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Ler a chave de recuperação do BitLocker exige privilégios de Administrador.'))) {
            $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador') -Title $title
            Exit-TFToolkitAction -Result $final
            return
        }

        if ($null -eq (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Este Windows não tem o BitLocker: não há chave de recuperação.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'este Windows não tem o BitLocker') -Title $title)
            return
        }

        $volumes = @(Get-TFToolkitBitLockerVolumes)

        if ($volumes.Count -eq 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhum disco deste PC usa o BitLocker: não há chave de recuperação para guardar.')
            Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nenhum disco com BitLocker') -Title $title) `
                    -Headline (Get-TFToolkitText 'Nenhum disco com BitLocker') -Note (Get-TFToolkitText 'Os discos deste PC não estão criptografados; não há chave para guardar.'))
            return
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Discos com BitLocker')

        foreach ($volume in $volumes) {
            # Esperando ativação, o disco ainda abre sem chave: não ter uma é o normal, e não um alerta.
            if ($volume.State -eq "Pending") {
                Write-TFToolkitKeyValue -Label $volume.MountPoint -Value (Get-TFToolkitBitLockerStateText -State $volume.State) -LabelWidth 8
                continue
            }

            $keys = $(if (@($volume.Keys).Count -gt 0) { Join-TFToolkitList -Items @($volume.Keys | ForEach-Object { (Get-TFToolkitText 'chave {0}' "$($_.Id.Substring(0, [Math]::Min(8, $_.Id.Length)))") }) } else { (Get-TFToolkitText 'sem chave de recuperação') })
            Write-TFToolkitKeyValue -Label $volume.MountPoint -Value (Get-TFToolkitText '{0}; {1}' "$(Get-TFToolkitBitLockerStateText -State $volume.State)" "$keys") -Level $(if (@($volume.Keys).Count -gt 0) { "Normal" } else { "Warn" }) -LabelWidth 8
        }

        Write-Host ""

        if (@($volumes | Where-Object { $_.State -eq "Pending" }).Count -gt 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Esperando ativação, a criptografia ainda não protege o disco, e ele abre sem chave. Para ligar, use Configurações, Privacidade e segurança, Criptografia do dispositivo; a chave de recuperação fica guardada na sua conta Microsoft.')
        }

        $withKeys = @($volumes | Where-Object { @($_.Keys).Count -gt 0 })
        $withoutKeys = @($volumes | Where-Object { @($_.Keys).Count -eq 0 -and $_.State -ne "Pending" })

        # Só discos esperando ativação: não há chave para guardar nem para criar daqui.
        if ($withKeys.Count -eq 0 -and $withoutKeys.Count -eq 0) {
            Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'criptografia esperando ativação') -Title $title) `
                    -Headline (Get-TFToolkitText 'Criptografia esperando ativação') -Note (Get-TFToolkitText 'O disco ainda não está protegido e abre sem chave; não há chave para guardar.'))
            return
        }

        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Se o PC pedir a chave (depois de trocar uma peça ou atualizar a BIOS), sem ela os arquivos do disco ficam inacessíveis. Com uma conta Microsoft, uma cópia costuma estar em aka.ms/myrecoverykey.')
        Write-Host ""

        $options = @()

        if ($withKeys.Count -gt 0) {
            $options += @{ Key = "S"; Label = (Get-TFToolkitText 'Salvar uma cópia num arquivo'); Description = (Get-TFToolkitText 'Num pendrive ou noutra pasta, fora deste disco'); Accent = $true }
            $options += @{ Key = "M"; Label = (Get-TFToolkitText 'Mostrar na tela'); Description = (Get-TFToolkitText 'Para anotar; a chave não vai para o log do TF-Toolkit') }
        }

        if ($withoutKeys.Count -gt 0) {
            $options += @{ Key = "C"; Label = (Get-TFToolkitText 'Criar uma chave de recuperação'); Description = (Join-TFToolkitList -Items @($withoutKeys | ForEach-Object { $_.MountPoint })); Accent = ($withKeys.Count -eq 0) }
        }

        $options += @{ Key = "X"; Label = (Get-TFToolkitText 'Voltar'); Exit = $true }

        $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'O que deseja fazer?') -Options $options -DefaultKey "X" -ShowMenu -TextPrompt (Get-TFToolkitText 'Opção (0 ou Enter = voltar)')

        if ($answer -eq "C") {
            foreach ($volume in $withoutKeys) {
                try {
                    # O próprio comando escreve a chave nova num aviso: calado, para ela não ir para o log.
                    [void](Add-BitLockerKeyProtector -MountPoint $volume.MountPoint -RecoveryPasswordProtector -ErrorAction Stop -WarningAction SilentlyContinue)
                }
                catch {
                    # Uma política da empresa que exige guardar a chave no Active Directory recusa a criação quando não consegue:
                    # a falha é de criar, e não de ler o BitLocker.
                    $reason = ([string]$_.Exception.Message).Trim().TrimEnd('.')
                    Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível criar a chave de recuperação de {0}: {1}.' "$($volume.MountPoint)" "$reason")
                    $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'a chave de {0} não foi criada: {1}' "$($volume.MountPoint)" "$reason") -Title $title
                    break
                }

                [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Chave de recuperação do BitLocker') -Text (Get-TFToolkitText 'chave criada para o disco {0}' "$($volume.MountPoint)"))
                $created += $volume.MountPoint
                Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Chave de recuperação criada para o disco {0}.' "$($volume.MountPoint)")
            }

            if ($null -eq $final) {
                $volumes = @(Get-TFToolkitBitLockerVolumes)
                $withKeys = @($volumes | Where-Object { @($_.Keys).Count -gt 0 })
                Write-Host ""
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Agora guarde uma cópia da chave nova fora do PC.')
                $answer = "S"
            }
            else {
                $answer = ""
            }
        }

        if ($answer -eq "M") {
            foreach ($volume in $withKeys) {
                foreach ($key in @($volume.Keys)) { Write-TFToolkitSecret -Label (Get-TFToolkitText '{0} (chave {1})' "$($volume.MountPoint)" "$($key.Id.Substring(0, [Math]::Min(8, $key.Id.Length)))") -Value $key.Password -LabelWidth 8 }
            }

            Write-Host ""
            Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'A chave aparece só na tela: ela não vai para o log do TF-Toolkit. Anote e guarde fora do PC.')
            $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'chave mostrada na tela') -Title $title) `
                -Headline (Get-TFToolkitText 'Chave de recuperação na tela') -Note (Get-TFToolkitText 'Ela está no resumo, abaixo, e não vai para o log do TF-Toolkit. Anote e guarde fora do PC.')
        }
        elseif ($answer -eq "S") {
            $folder = Select-TFToolkitBitLockerKeyFolder

            if (-not $folder) {
                $final = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title
            }
            elseif (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'A pasta não existe: {0}' "$folder")
                $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'a pasta não existe') -Title $title
                $note = Get-TFToolkitMissingDriveNote -Path $folder

                if ($note) {
                    Write-TFToolkitStatus -Type Info -Message $note
                    [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'A pasta não existe') -Note $note -Tone Bad)
                }
            }
            else {
                # Uma cópia dentro do próprio disco criptografado não ajuda quando o disco não abre.
                $letter = ([System.IO.Path]::GetPathRoot((Get-TFToolkitFullPath -Path $folder))).TrimEnd('\')
                $go = $true

                if (@($volumes | Where-Object { $_.MountPoint -ieq $letter }).Count -gt 0) {
                    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Esta pasta fica num disco com BitLocker ({0}): se o PC pedir a chave, esse disco não abre. Use um pendrive ou copie o arquivo para fora depois.' "$letter")
                    $go = Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Salvar aí mesmo assim?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Salvar mesmo assim') -NoLabel (Get-TFToolkitText 'Cancelar')
                }

                if (-not $go) {
                    $final = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title
                }
                else {
                    try {
                        $path = Save-TFToolkitBitLockerKeyFile -Volumes $withKeys -Folder $folder
                        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Cópia da chave salva: {0}' "$path")
                        $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'cópia da chave salva em {0}' "$path") -Title $title) `
                            -Headline (Get-TFToolkitText 'Cópia da chave salva') -Note (Get-TFToolkitText 'Está em {0}. Guarde esse arquivo fora do PC: quem tiver a chave consegue abrir o disco.' "$path")
                    }
                    catch {
                        # A falha é de gravar (o pendrive tirado, protegido contra gravação ou cheio, a pasta sem permissão), e
                        # não de ler o BitLocker: a tela diz isso, e o botão tenta de novo.
                        $reason = ([string](ConvertTo-TFToolkitReadableError -Text ([string]$_.Exception.Message))).Trim().TrimEnd('.')
                        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível salvar a cópia da chave: {0}.' "$reason")
                        $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'a cópia da chave não foi salva: {0}' "$reason") -Title $title) `
                            -Headline (Get-TFToolkitText 'A cópia da chave não foi salva') -Note (Get-TFToolkitText 'Confira se o pendrive está conectado e com espaço, ou escolha outra pasta.') `
                            -Tone Bad -Next "security.bitlocker-key" -NextLabel (Get-TFToolkitText 'Tentar de novo')
                    }
                }
            }
        }
        elseif ($null -eq $final) {
            $final = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível ler o BitLocker: {0}.' "$(([string]$_.Exception.Message).TrimEnd('.'))")
        $final = New-TFToolkitResult -Kind Failed -Detail ([string]$_.Exception.Message).TrimEnd('.') -Title $title
    }

    # Uma chave criada agora sem cópia guardada (a pessoa desistiu de onde salvar, ou não deu para salvar): é o que o
    # resultado diz, e o próximo passo é guardá-la.
    if ($created.Count -gt 0 -and ($null -eq $final -or $final.Kind -ne "Ok")) {
        $where = Join-TFToolkitList -Items $created
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A chave nova de {0} foi criada, mas nenhuma cópia foi guardada.' "$where")
        $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'chave criada para {0}, mas nenhuma cópia foi guardada' "$where") -Title $title) `
            -Headline (Get-TFToolkitText 'Chave criada, sem cópia guardada') -Note (Get-TFToolkitText 'Guarde uma cópia agora: salve num arquivo fora deste disco ou anote a chave.') `
            -Next "security.bitlocker-key" -NextLabel (Get-TFToolkitText 'Guardar a chave')
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
