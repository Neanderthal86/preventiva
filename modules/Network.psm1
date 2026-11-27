# Rede: o que o Windows diz da conexão (a faixa da página), o teste de conectividade (ping), o reparo de rede e DNS, o
# teste de velocidade e as informações dos adaptadores. A troca do DNS, o Wi-Fi (relatório e senha) e o relógio ficam em
# NetworkTools.psm1.

# O teste de velocidade atrás de um proxy que pede autenticação e não aceitou a conta do Windows.
$script:TFToolkitProxyAuthProblem = (Get-TFToolkitText 'o proxy da rede pediu autenticação (HTTP 407) e não aceitou a conta do Windows; o teste não consegue passar por ele')


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

function Get-TFToolkitMbps {
    # Megabits por segundo a partir de bytes e segundos; devolve 0 quando o tempo é desprezível.
    param (
        [double]$Bytes,
        [double]$Seconds
    )

    if ($Seconds -lt 0.05 -or $Bytes -le 0) {
        return 0.0
    }

    return [Math]::Round((($Bytes * 8) / 1000000) / $Seconds, 2)
}


function Get-TFToolkitInnerMessage {
    # Exceções de tarefas assíncronas chegam embrulhadas em AggregateException.
    param (
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $current = $Exception

    while ($null -ne $current.InnerException) {
        $current = $current.InnerException
    }

    return $current.Message
}


function New-TFToolkitSpeedHttpClient {
    <#
    O HttpClient do teste de velocidade, pelo proxy do sistema e com a conta do Windows: numa rede de empresa o proxy
    pede autenticação, e o navegador passa por ele com a conta logada. Sem isso o teste parava num "407" sem explicação.
    #>
    param ([int]$TimeoutSeconds = 30)

    $handler = New-Object System.Net.Http.HttpClientHandler

    try {
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy()

        if ($null -ne $proxy) {
            $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
            $handler.Proxy = $proxy
            $handler.UseProxy = $true
        }
    }
    catch {
        # Sem o proxy do sistema, segue com o padrão do HttpClient.
    }

    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

    return $client
}


function Get-TFToolkitSpeedProblem {
    # O motivo de uma medição ter falhado, para a pessoa: o proxy que pede autenticação (HTTP 407) vira uma frase; o resto
    # é a mensagem mais interna da exceção.
    param (
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $message = Get-TFToolkitInnerMessage -Exception $Exception
    $texts = New-Object System.Collections.ArrayList
    $current = $Exception

    while ($null -ne $current) {
        [void]$texts.Add([string]$current.Message)
        $current = $current.InnerException
    }

    # "(407) Proxy Authentication Required" (Windows PowerShell) ou "407 (Proxy Authentication Required)" (PowerShell 7).
    if (($texts -join " ") -match '(?i)\(407\)|\b407 \(|proxy authentication required') {
        return $script:TFToolkitProxyAuthProblem
    }

    return $message
}


function Assert-TFToolkitSpeedResponse {
    # Falha com uma frase quando o servidor (ou o proxy) não respondeu com sucesso.
    param ([Parameter(Mandatory)]$Response)

    if ([int]$Response.StatusCode -eq 407) {
        throw $script:TFToolkitProxyAuthProblem
    }

    [void]$Response.EnsureSuccessStatusCode()
}


function Wait-TFToolkitTask {
    # Espera uma Task em fatias curtas: o botão Parar (ou Ctrl+C) interrompe o teste sem esperar a rede.
    param (
        [Parameter(Mandatory)]
        $Task,

        [int]$TimeoutSeconds = 30
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while (-not $Task.Wait(250)) {
        if ($stopwatch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            throw (Get-TFToolkitText 'Tempo esgotado ao aguardar a resposta do servidor.')
        }
    }
}


# ---------------------------------------------------------------------------
# Conectividade e ping
# ---------------------------------------------------------------------------

function Get-TFToolkitPingReplies {
    <#
    Pinga os endereços todos ao mesmo tempo, Count vezes cada, uma rodada por segundo, como o ping do Windows. Devolve uma
    tabela com, para cada endereço, os tempos de ida e volta (ms) das respostas que voltaram. Usa a classe Ping do .NET
    (pedidos de eco ICMP), a mesma nos dois PowerShell: cada pedido espera até TimeoutMilliseconds, e um nome que não vira
    endereço, uma falha no envio ou um tempo esgotado contam como pacote perdido. Antes, o Test-Connection pingava um
    endereço depois do outro (cerca de 4 s por endereço com a internet funcionando, e mais sem ela), e cada versão do
    PowerShell devolvia as respostas de um jeito. Activity: o andamento das rodadas na barra de progresso; quem chama a
    encerra.
    #>
    param (
        [Parameter(Mandatory)]
        [string[]]$ComputerName,

        [ValidateRange(1, 50)]
        [int]$Count = 4,

        [ValidateRange(500, 10000)]
        [int]$TimeoutMilliseconds = 2000,

        [string]$Activity = ""
    )

    $replies = @{}
    foreach ($name in $ComputerName) { $replies[$name] = New-Object System.Collections.Generic.List[double] }

    for ($round = 0; $round -lt $Count; $round++) {
        if ($Activity) { Write-Progress -Activity $Activity -Status (Get-TFToolkitText 'pacote {0} de {1}' "$($round + 1)" "$Count") -PercentComplete ([int]($round * 100 / $Count)) }

        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $sent = New-Object System.Collections.Generic.List[object]

        try {
            foreach ($name in $ComputerName) {
                # Um Ping por pedido: a mesma instância não aceita dois envios ao mesmo tempo.
                $entry = [PSCustomObject]@{ Name = $name; Ping = (New-Object System.Net.NetworkInformation.Ping); Task = $null }
                $sent.Add($entry)

                try {
                    $entry.Task = $entry.Ping.SendPingAsync($name, $TimeoutMilliseconds)
                }
                catch {
                    # Um nome que não vira endereço pode falhar já no envio: é um pacote perdido, como os outros.
                    Write-Verbose "Ping para ${name}: $($_.Exception.Message)"
                }
            }

            foreach ($entry in $sent) {
                if ($null -eq $entry.Task) { continue }

                try {
                    Wait-TFToolkitTask -Task $entry.Task -TimeoutSeconds ([int][Math]::Ceiling($TimeoutMilliseconds / 1000) + 3)
                    $reply = $entry.Task.Result
                    if ($null -ne $reply -and [string]$reply.Status -eq "Success") { $replies[$entry.Name].Add([double]$reply.RoundtripTime) }
                }
                catch {
                    # Sem resposta (o nome não resolve, a rede recusou o envio): pacote perdido.
                    Write-Verbose "Ping para $($entry.Name): $($_.Exception.Message)"
                }
            }
        }
        finally {
            foreach ($entry in $sent) { $entry.Ping.Dispose() }
        }

        # Uma rodada por segundo: o que sobra do segundo é a espera até a próxima.
        $rest = 1000 - [int]$clock.ElapsedMilliseconds
        if ($round -lt $Count - 1 -and $rest -gt 0) { Start-Sleep -Milliseconds $rest }
    }

    return $replies
}


function ConvertTo-TFToolkitPingStats {
    # A perda (em %) e os tempos (média, mínimo e máximo, em ms) de um endereço, a partir dos tempos das respostas que
    # voltaram (Get-TFToolkitPingReplies) e de quantos pacotes foram enviados. Sem resposta, os tempos ficam "-": um
    # pacote perdido não marca o endereço inteiro como falho.
    param (
        [AllowEmptyCollection()]
        [object[]]$Latencies = @(),

        [ValidateRange(1, 50)]
        [int]$Sent = 4
    )

    $times = @($Latencies | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    $received = [Math]::Min($times.Count, $Sent)
    $lossPercent = [Math]::Round((($Sent - $received) / $Sent) * 100, 0)

    if ($times.Count -gt 0) {
        $measure = $times | Measure-Object -Average -Minimum -Maximum
        $average = [Math]::Round($measure.Average, 1)
        $minimum = [Math]::Round($measure.Minimum, 1)
        $maximum = [Math]::Round($measure.Maximum, 1)
    }
    else {
        $average = "-"; $minimum = "-"; $maximum = "-"
    }

    return [PSCustomObject]@{
        Received = $received
        Sent     = $Sent
        Loss     = $lossPercent
        Average  = $average
        Minimum  = $minimum
        Maximum  = $maximum
    }
}


function Get-TFToolkitPingStatusText {
    param (
        [int]$LossPercent
    )

    if ($LossPercent -ge 100) { return (Get-TFToolkitText 'Sem resposta') }
    if ($LossPercent -gt 0) { return (Get-TFToolkitText 'Instável') }
    return "OK"
}


function Test-TFToolkitInternetConnectivity {
    # Separa "sem rota" (acesso a IPs) de "sem DNS" (resolução de nomes): cada um aponta para um reparo diferente.
    # Redes e firewalls que bloqueiam o ping (ICMP) são comuns; por isso, se o ping falha, uma conexão TCP na porta 443
    # decide. Sem isso, uma rede saudável seria tratada como quebrada e a Manutenção redefiniria o Winsock sem motivo.
    $pingOk = $false
    $viaTcp = $false
    $targets = @("1.1.1.1", "8.8.8.8")

    # Os dois ao mesmo tempo: basta um responder.
    try {
        $replies = Get-TFToolkitPingReplies -ComputerName $targets -Count 2
        $pingOk = (@($targets | Where-Object { @($replies[$_] | Where-Object { $null -ne $_ }).Count -gt 0 }).Count -gt 0)
    }
    catch {
        $pingOk = $false
    }

    if (-not $pingOk) {
        foreach ($target in $targets) {
            if (Test-TFToolkitTcpConnection -ComputerName $target -Port 443) {
                $pingOk = $true
                $viaTcp = $true
                break
            }
        }
    }

    $dnsOk = Test-TFToolkitDnsResolution -Name "www.microsoft.com"

    return [PSCustomObject]@{
        PingOk = $pingOk
        ViaTcp = $viaTcp
        DnsOk  = $dnsOk
        Ok     = ($pingOk -and $dnsOk)
    }
}


function Get-TFToolkitWindowsInternetStatus {
    <#
    O que o próprio Windows diz da conexão (o teste dele passa pelo proxy configurado no PC): $true quando alguma rede
    conectada tem acesso à internet (IPv4Connectivity ou IPv6Connectivity = Internet), $false quando há redes e nenhuma
    tem, e $null quando não deu para saber.
    #>
    try {
        $profiles = @(Get-NetConnectionProfile -ErrorAction Stop | Where-Object { $null -ne $_ })
    }
    catch {
        return $null
    }

    foreach ($connection in $profiles) {
        foreach ($name in @("IPv4Connectivity", "IPv6Connectivity")) {
            $property = $connection.PSObject.Properties[$name]
            if ($null -ne $property -and [string]$property.Value -eq "Internet") { return $true }
        }
    }

    return $false
}


function Test-TFToolkitNetworkConnected {
    <#
    Se o Windows está ligado a alguma rede (um perfil de conexão, com ou sem internet): $true, $false quando não há
    nenhuma (Wi-Fi desligado, cabo solto, modo avião) e $null quando não deu para saber.
    #>
    try {
        $profiles = @(Get-NetConnectionProfile -ErrorAction Stop | Where-Object { $null -ne $_ })
    }
    catch {
        # Sem nenhum perfil, a consulta pode responder com o erro de "nenhum objeto encontrado" em vez de uma lista vazia.
        if ([string]$_.Exception.Message -match 'MSFT_NetConnectionProfile') { return $false }

        return $null
    }

    return ($profiles.Count -gt 0)
}


function Get-TFToolkitInternetConnection {
    <#
    O que o próprio Windows diz da conexão agora: o indicador de conectividade dele, o mesmo do ícone de rede da barra de
    tarefas, lido pela API do Windows (Windows.Networking.Connectivity), na hora e sem o WMI. Devolve Level e Name.
    Level: Internet (com internet), Limited (acesso limitado: em geral, um Wi-Fi que pede login numa página, como o de
    hotel e aeroporto; às vezes, um proxy no caminho), Local (ligado a uma rede, sem internet), None (nenhuma rede) ou ""
    (não deu para saber). Name: a rede, como a pessoa a conhece ("Wi-Fi Casa", "Cabo de rede", "Rede celular").
    A Microsoft avisa que é um indício: quem confirma é o teste de conectividade, para onde a faixa da página leva.
    #>
    try {
        $network = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]
        $connection = $network::GetInternetConnectionProfile()

        # Sem a conexão preferida (o Windows a devolve vazia quando está desconectado), vale a melhor das ativas.
        if ($null -eq $connection) {
            $rank = @{ "LocalAccess" = 1; "ConstrainedInternetAccess" = 2; "InternetAccess" = 3 }
            $connection = @(
                @($network::GetConnectionProfiles()) | Where-Object { $null -ne $_ -and $rank.ContainsKey([string]$_.GetNetworkConnectivityLevel()) } |
                    Sort-Object -Property @{ Expression = { $rank[[string]$_.GetNetworkConnectivityLevel()] } } -Descending
            ) | Select-Object -First 1
        }

        if ($null -eq $connection) { return [PSCustomObject]@{ Level = "None"; Name = "" } }

        $level = switch ([string]$connection.GetNetworkConnectivityLevel()) {
            "InternetAccess" { "Internet" }
            "ConstrainedInternetAccess" { "Limited" }
            "LocalAccess" { "Local" }
            default { "None" }
        }

        # O nome que a pessoa reconhece: o da rede Wi-Fi (sem a Localização, no Windows 11 recente, pode vir vazio), o cabo
        # ou a rede celular.
        $name = ""

        try {
            if ([bool]$connection.IsWlanConnectionProfile) {
                $ssid = ""
                try { $ssid = [string]$connection.WlanConnectionProfileDetails.GetConnectedSsid() } catch { $ssid = "" }
                if (-not $ssid) { $ssid = [string]$connection.ProfileName }
                $name = $(if ($ssid) { (Get-TFToolkitText 'Wi-Fi {0}' "$ssid") } else { "Wi-Fi" })
            }
            elseif ([bool]$connection.IsWwanConnectionProfile) { $name = (Get-TFToolkitText 'Rede celular') }
            elseif ([int]$connection.NetworkAdapter.IanaInterfaceType -eq 6) { $name = (Get-TFToolkitText 'Cabo de rede') }
            else { $name = [string]$connection.ProfileName }
        }
        catch {
            $name = [string]$connection.ProfileName
        }

        return [PSCustomObject]@{ Level = $level; Name = $name.Trim() }
    }
    catch {
        Write-Verbose "Conexão segundo o Windows: $($_.Exception.Message)"
        return [PSCustomObject]@{ Level = ""; Name = "" }
    }
}


function Get-TFToolkitNetworkPageStatus {
    <#
    O resumo no alto da página Rede: a conexão, como o Windows a vê agora (Get-TFToolkitInternetConnection, na hora, sem o
    WMI). Cada linha tem Label, Text, Level (Normal | Warn | Muted) e Opens. Sem internet, com o acesso limitado (um
    Wi-Fi que pede login) ou sem rede, a linha fica em amarelo e abre o Testar conectividade, que confirma o problema e
    leva ao que resolve (o reparo, as configurações de rede ou a página de login da rede).
    #>
    $connection = Get-TFToolkitInternetConnection
    $name = $(if ([string]$connection.Name) { [string]$connection.Name } else { (Get-TFToolkitText 'Conectado') })
    $row = [PSCustomObject]@{ Label = (Get-TFToolkitText 'Conexão'); Text = (Get-TFToolkitText 'não foi possível ler'); Level = "Muted"; Opens = "" }

    switch ([string]$connection.Level) {
        "Internet" { $row.Text = (Get-TFToolkitText '{0} · com internet' "$name"); $row.Level = "Normal" }
        "Limited" { $row.Text = (Get-TFToolkitText '{0} · acesso limitado (a rede pode pedir login)' "$name"); $row.Level = "Warn"; $row.Opens = "network.ping" }
        "Local" { $row.Text = (Get-TFToolkitText '{0} · sem internet' "$name"); $row.Level = "Warn"; $row.Opens = "network.ping" }
        "None" { $row.Text = (Get-TFToolkitText 'nenhuma rede conectada'); $row.Level = "Warn"; $row.Opens = "network.ping" }
    }

    return @($row)
}


function Set-TFToolkitNoNetworkView {
    # A faixa de quando o PC não está ligado a nenhuma rede (Wi-Fi desligado, cabo solto, modo avião): o que fazer e o
    # botão das configurações de rede. A mesma no teste de conectividade, no de velocidade, nas informações e no reparo.
    # Devolve o próprio resultado.
    param ([Parameter(Mandatory)]$Result)

    return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'Nenhuma rede conectada') -Note (Get-TFToolkitText 'Ligue o Wi-Fi ou conecte o cabo; confira também o modo avião.') `
            -Next "NetworkSettings" -NextLabel (Get-TFToolkitText 'Abrir as configurações de rede'))
}


function Get-TFToolkitIpReachText {
    # Texto do "acesso por IP direto" (sem DNS) para as telas de diagnóstico e de reparo.
    param (
        [Parameter(Mandatory)]
        $Connectivity
    )

    if (-not $Connectivity.PingOk) { return (Get-TFToolkitText 'Sem resposta') }
    if ($Connectivity.ViaTcp) { return (Get-TFToolkitText 'Responde (o ping está bloqueado, mas a conexão TCP funciona)') }

    return (Get-TFToolkitText 'Responde')
}


function Test-TFToolkitIpAddressText {
    # Verdadeiro só se o texto inteiro é um endereço IPv4 (quatro números) ou IPv6. Uma página HTML, uma mensagem de erro ou
    # um texto vazio dão falso.
    param (
        [string]$Text
    )

    $value = ([string]$Text).Trim()
    $parsed = $null

    if ($value -match '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' -or ($value -match '^[0-9A-Fa-f:.]+$' -and $value.Contains(":"))) {
        return [System.Net.IPAddress]::TryParse($value, [ref]$parsed)
    }

    return $false
}


function Get-TFToolkitProxySettings {
    <#
    O proxy do usuário, como o Windows o guarda (servidor manual e script de configuração automática). Text vem vazio
    quando não há nenhum, ou quando não deu para ler: na dúvida, nada a dizer. Um usuário e uma senha embutidos no
    endereço ("conta:senha@servidor") nunca vão para a tela: só o servidor.
    #>
    $server = ""
    $scriptUrl = ""

    try {
        $settings = Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction Stop

        if ([string](Get-TFToolkitJsonValue -Object $settings -Name "ProxyEnable" -Default 0) -eq "1") {
            $server = ([string](Get-TFToolkitJsonValue -Object $settings -Name "ProxyServer" -Default "")).Trim()
        }

        $scriptUrl = ([string](Get-TFToolkitJsonValue -Object $settings -Name "AutoConfigURL" -Default "")).Trim()
    }
    catch {
        $server = ""
        $scriptUrl = ""
    }

    # Usuário e senha embutidos ("conta:senha@servidor", e a senha pode ter "@", "/" ou ";"): fica só o que vem depois do
    # último "@". No script, o endereço volta sem a conta e sem a consulta ("?..."), que às vezes leva uma chave de acesso.
    if ($server.Contains("@")) { $server = $server.Substring($server.LastIndexOf("@") + 1) }

    if ($scriptUrl) {
        $uri = $null

        if ([System.Uri]::TryCreate($scriptUrl, [System.UriKind]::Absolute, [ref]$uri)) {
            $scriptUrl = $uri.GetComponents([System.UriComponents]::SchemeAndServer -bor [System.UriComponents]::Path, [System.UriFormat]::Unescaped)
        }
        else {
            $scheme = $(if ($scriptUrl -match '^([A-Za-z][A-Za-z0-9+.-]*://)') { $Matches[1] } else { "" })
            if ($scriptUrl.Contains("@")) { $scriptUrl = $scheme + $scriptUrl.Substring($scriptUrl.LastIndexOf("@") + 1) }
            $scriptUrl = ($scriptUrl -split '\?')[0]
        }
    }
    $serverText = $(if ($server.Length -gt 60) { $server.Substring(0, 57) + "..." } else { $server })
    $scriptText = $(if ($scriptUrl.Length -gt 60) { $scriptUrl.Substring(0, 57) + "..." } else { $scriptUrl })
    $parts = @()
    if ($server) { $parts += (Get-TFToolkitText '{0} (manual)' "$serverText") }
    if ($scriptUrl) { $parts += (Get-TFToolkitText 'script de configuração ({0})' "$scriptText") }

    return [PSCustomObject]@{
        Server    = $server
        ScriptUrl = $scriptUrl
        Text      = (Join-TFToolkitList -Items $parts)
    }
}


function Get-TFToolkitPingVerdict {
    <#
    Conclusão do teste de conectividade. Results: objetos com Host e Loss (perda em %), e Resolved (opcional: o DNS do PC
    resolve o nome, mesmo que ele não responda ao ping). Separa os casos que pedem ações diferentes: nada responde (sem
    internet), os IPs respondem mas os nomes não resolvem (DNS), a conexão perde dados (instável: dois ou mais alvos com
    perda, ou um com perda de 50% ou mais) e tudo responde. Um alvo que não responde nada enquanto os outros respondem é só
    um servidor que ignora o ping, não um problema; nomes que resolvem mas não respondem ao ping também não. -Limited (o
    Windows diz que a rede limita o acesso: em geral, um Wi-Fi que pede login numa página): o "sem internet" e o "DNS"
    viram o que a pessoa precisa fazer, entrar na página da rede; o reparo não resolve isso.
    Devolve Level (Warning ou Success, para a última linha da tela), Message, Kind (Warning ou Ok), Detail (a faixa no
    console e no histórico) e, para a janela, Headline e Note (o título e a frase da faixa) e Next e NextLabel (o botão do
    que resolve: o reparo, quando ele resolve; nenhum quando o problema está fora do PC).
    #>
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Results,

        [switch]$Limited
    )

    $answered = @($Results | Where-Object { [int]$_.Loss -lt 100 })
    $byAddress = @($Results | Where-Object { Test-TFToolkitIpAddressText -Text ([string]$_.Host) })
    $byName = @($Results | Where-Object { -not (Test-TFToolkitIpAddressText -Text ([string]$_.Host)) })
    $addressAnswered = @($byAddress | Where-Object { [int]$_.Loss -lt 100 }).Count
    $nameAnswered = @($byName | Where-Object { [int]$_.Loss -lt 100 }).Count
    $nameResolved = @($byName | Where-Object { $_.PSObject.Properties.Name -contains "Resolved" -and $_.Resolved }).Count
    $lossy = @($answered | Where-Object { [int]$_.Loss -gt 0 })
    $heavy = @($lossy | Where-Object { [int]$_.Loss -ge 50 })

    $verdict = {
        param ($Kind, $Message, $Detail, $Headline, $Note, $Next = "", $NextLabel = "")
        [PSCustomObject]@{
            Level = $(if ($Kind -eq "Ok") { "Success" } else { "Warning" }); Message = $Message; Kind = $Kind; Detail = $Detail
            Headline = $Headline; Note = $Note; Next = $Next; NextLabel = $NextLabel
        }
    }

    $dnsBroken = ($addressAnswered -gt 0 -and $byName.Count -gt 0 -and $nameAnswered -eq 0 -and $nameResolved -eq 0)

    if ($Limited -and ($answered.Count -eq 0 -or $dnsBroken)) {
        return (& $verdict "Warning" (Get-TFToolkitText 'O Windows indica que a rede limita o acesso: em geral, um Wi-Fi que pede login numa página (hotel, aeroporto, café). Abra o navegador e entre na página da rede; o reparo não resolve isso.') (Get-TFToolkitText 'a rede limita o acesso (pode pedir login numa página)') `
                (Get-TFToolkitText 'A rede limita o acesso') (Get-TFToolkitText 'Comum em Wi-Fi de hotel, aeroporto e café: abra o navegador e entre na página de login da rede.'))
    }

    if ($answered.Count -eq 0) {
        return (& $verdict "Warning" (Get-TFToolkitText 'Nada respondeu: o PC está sem internet. Confira o Wi-Fi, o cabo e o roteador; se continuar, use Rede > Reparar rede e DNS.') (Get-TFToolkitText 'nada respondeu; o PC está sem internet') `
                (Get-TFToolkitText 'Sem internet') (Get-TFToolkitText 'Nada respondeu. Confira o Wi-Fi, o cabo e o roteador; se estiver tudo ligado, repare a rede.') "network.repair" (Get-TFToolkitText 'Reparar a rede'))
    }

    if ($dnsBroken) {
        return (& $verdict "Warning" (Get-TFToolkitText 'A internet responde, mas os sites não abrem pelo nome: o problema é o DNS. Use Rede > Reparar rede e DNS ou Rede > Trocar o servidor DNS.') (Get-TFToolkitText 'os sites não abrem pelo nome (problema de DNS)') `
                (Get-TFToolkitText 'Os sites não abrem pelo nome') (Get-TFToolkitText 'A internet responde, mas o DNS não. Reparar a rede costuma resolver; se não resolver, troque o servidor DNS.') "network.repair" (Get-TFToolkitText 'Reparar a rede'))
    }

    if ($lossy.Count -ge 2 -or $heavy.Count -gt 0) {
        return (& $verdict "Warning" (Get-TFToolkitText 'A conexão está instável, com perda de dados: aproxime o PC do roteador ou use cabo; se continuar, fale com a operadora.') (Get-TFToolkitText 'a conexão está instável, com perda de dados') `
                (Get-TFToolkitText 'Conexão instável') (Get-TFToolkitText 'Há perda de dados: aproxime o PC do roteador ou use cabo; se continuar, fale com a operadora.'))
    }

    if ($answered.Count -lt @($Results).Count) {
        return (& $verdict "Ok" (Get-TFToolkitText 'A internet está funcionando; alguns endereços não responderam, mas há servidores que ignoram o ping.') (Get-TFToolkitText 'a internet está funcionando; alguns endereços ignoram o ping') `
                (Get-TFToolkitText 'A internet está funcionando') (Get-TFToolkitText 'Alguns endereços não responderam, mas há servidores que ignoram o ping.'))
    }

    if ($lossy.Count -gt 0) {
        return (& $verdict "Ok" (Get-TFToolkitText 'A internet está respondendo bem; um dos testes perdeu um pouco de dados, o que é normal.') (Get-TFToolkitText 'a internet está respondendo bem') `
                (Get-TFToolkitText 'A internet está funcionando') (Get-TFToolkitText 'Um dos testes perdeu um pouco de dados, o que é normal.'))
    }

    return (& $verdict "Ok" (Get-TFToolkitText 'A internet está respondendo bem e sem perdas.') (Get-TFToolkitText 'a internet está respondendo bem e sem perdas') (Get-TFToolkitText 'A internet está funcionando') (Get-TFToolkitText 'Respondeu bem, sem perda de dados.'))
}


function Format-TFToolkitPingLine {
    # A linha de um alvo no resumo: "OK · média 12 ms (mín. 10, máx. 15)", "Instável · 25% de perda · média 30 ms" ou
    # "Sem resposta".
    param ([Parameter(Mandatory)]$Stats)

    $status = Get-TFToolkitPingStatusText -LossPercent ([int]$Stats.Loss)

    if ([int]$Stats.Loss -ge 100) { return $status }

    # Sem o tempo nas respostas ("-"), só a situação e a perda.
    $times = $(if ($Stats.Average -is [string]) { "" } else { (Get-TFToolkitText 'média {0} ms (mín. {1}, máx. {2})' "$(Format-TFToolkitNumber -Value $Stats.Average -Decimals 0)" "$(Format-TFToolkitNumber -Value $Stats.Minimum -Decimals 0)" "$(Format-TFToolkitNumber -Value $Stats.Maximum -Decimals 0)") })
    if (-not $times) { return $(if ([int]$Stats.Loss -gt 0) { (Get-TFToolkitText '{0} · {1}% de perda' "$status" "$($Stats.Loss)") } else { $status }) }

    if ([int]$Stats.Loss -gt 0) { return (Get-TFToolkitText '{0} · {1}% de perda · {2}' "$status" "$($Stats.Loss)" "$times") }

    return "$status · $times"
}


function Test-TFToolkitPing {
    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Testar conectividade (ping)')

    $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o teste não devolveu resultado')
    $targets = @(
        [PSCustomObject]@{ Name = (Get-TFToolkitText 'Cloudflare DNS'); Host = "1.1.1.1" },
        [PSCustomObject]@{ Name = "Google DNS"; Host = "8.8.8.8" },
        [PSCustomObject]@{ Name = (Get-TFToolkitText 'Quad9 DNS'); Host = "9.9.9.9" },
        [PSCustomObject]@{ Name = "Microsoft"; Host = "www.microsoft.com" },
        [PSCustomObject]@{ Name = "Google"; Host = "www.google.com" }
    )

    try {
        # Sem nenhuma rede (Wi-Fi desligado, cabo solto, modo avião), os cinco testes só confirmariam o óbvio, e o reparo, que a
        # faixa de "sem internet" oferece, não liga o Wi-Fi nem o cabo.
        if ($false -eq (Test-TFToolkitNetworkConnected)) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O PC não está ligado a nenhuma rede: ligue o Wi-Fi ou conecte o cabo (e confira o modo avião).')
            $final = Set-TFToolkitNoNetworkView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o PC não está ligado a nenhuma rede'))
            Exit-TFToolkitAction -Result $final
            return
        }

        # Os cinco endereços ao mesmo tempo, quatro pacotes cada; o andamento vai para a barra de progresso (uma linha por
        # alvo ficaria no resumo depois do fim).
        try {
            $replies = Get-TFToolkitPingReplies -ComputerName @($targets | ForEach-Object { $_.Host }) -Count 4 -Activity (Get-TFToolkitText 'Testando a conectividade')
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Testando a conectividade') -Completed
        }

        $results = @(
            foreach ($target in $targets) {
                $stats = ConvertTo-TFToolkitPingStats -Latencies @($replies[$target.Host]) -Sent 4
                [PSCustomObject]@{ Name = $target.Name; Host = $target.Host; Loss = $stats.Loss; Resolved = $false; Stats = $stats }
            }
        )

        # Um nome que não respondeu ao ping pode ser um ping bloqueado ou um DNS quebrado: só vale perguntar ao DNS quando algum
        # IP respondeu (sem nenhum, a conclusão é "nada responde" de qualquer jeito).
        if (@($results | Where-Object { (Test-TFToolkitIpAddressText -Text $_.Host) -and [int]$_.Loss -lt 100 }).Count -gt 0) {
            foreach ($row in @($results | Where-Object { -not (Test-TFToolkitIpAddressText -Text $_.Host) -and [int]$_.Loss -ge 100 })) {
                $row.Resolved = [bool](Test-TFToolkitDnsResolution -Name $row.Host)
            }
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Resultado')

        # A cor de cada linha diz o que ela significa: vermelho sem resposta, amarelo com perda, verde sem perda. Um site cujo
        # nome funciona e que só não responde ao ping não é problema (a conclusão diz o mesmo): sem vermelho.
        foreach ($row in $results) {
            $loss = [int]$row.Stats.Loss

            if ($loss -ge 100 -and $row.Resolved) {
                Write-TFToolkitKeyValue -Label "$($row.Name) ($($row.Host))" -Value (Get-TFToolkitText 'Não responde ao ping (normal em alguns servidores)') -LabelWidth 29
                continue
            }

            $level = $(if ($loss -ge 100) { "Bad" } elseif ($loss -gt 0) { "Warn" } else { "Ok" })
            Write-TFToolkitKeyValue -Label "$($row.Name) ($($row.Host))" -Value (Format-TFToolkitPingLine -Stats $row.Stats) -LabelWidth 29 -Level $level
        }

        Write-Host ""

        # Com algo sem resposta, o Windows pode saber o motivo: uma rede que limita o acesso (um Wi-Fi que pede login numa
        # página). O reparo não resolve isso, e a faixa não o oferece.
        $limited = $false
        if (@($results | Where-Object { [int]$_.Loss -ge 100 }).Count -gt 0) { $limited = ([string](Get-TFToolkitInternetConnection).Level -eq "Limited") }

        # A conclusão é a última linha da tela; a faixa diz o mesmo em poucas palavras. O teste rodou até o fim, então um
        # problema encontrado (sem internet, DNS, conexão instável) é uma ressalva, não um "não foi concluído".
        $verdict = Get-TFToolkitPingVerdict -Results $results -Limited:$limited
        Write-TFToolkitStatus -Type $verdict.Level -Message $verdict.Message
        $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind $verdict.Kind -Detail $verdict.Detail) -Headline $verdict.Headline -Note $verdict.Note `
            -Next $verdict.Next -NextLabel $verdict.NextLabel
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro no teste de ping: {0}' "$($_.Exception.Message)")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }

    Exit-TFToolkitAction -Result $final
}


# ---------------------------------------------------------------------------
# Reparo de rede e DNS
# ---------------------------------------------------------------------------

function Get-TFToolkitStaticIpConfiguration {
    <#
    Há configuração de IP feita à mão em algum adaptador? O "netsh int ip reset" apaga endereços fixos de TODOS os
    adaptadores, então todos contam: com ou sem gateway (uma segunda placa numa rede interna não tem), ligados ou não,
    IPv4 e IPv6. Um adaptador conta como fixo quando tem um endereço posto à mão (PrefixOrigin Manual, qualquer família)
    ou o DHCP do IPv4 desligado. O loopback fica de fora (o Windows o configura assim). Devolve Static (há configuração
    fixa, ou não deu para saber), Unknown (a consulta falhou), Interfaces (os nomes) e Dhcp (algum adaptador conectado
    pega o IPv4 do roteador).
    O "ipconfig /release" e o "/renew" só mexem nos adaptadores com IP automático (DHCP), como diz a documentação da
    Microsoft: um IP fixo em outro adaptador (o do VirtualBox, o do WSL) não os impede. Sem nenhum adaptador automático
    conectado, eles não teriam o que fazer.
    O IPv6 não entra pelo DHCP desligado: ele se configura sozinho pelo roteador mesmo sem DHCPv6.
    Os filtros ficam aqui, e não nos parâmetros dos cmdlets: um filtro que não acha nada (nenhum endereço manual) vira
    erro de "objeto não encontrado", e um PC só com DHCP pareceria um PC que não pôde ser consultado.
    #>
    $names = New-Object System.Collections.ArrayList
    $dhcp = $false

    try {
        foreach ($address in @(Get-NetIPAddress -ErrorAction Stop)) {
            if ($null -eq $address -or [string]$address.PrefixOrigin -ne "Manual") { continue }
            $alias = [string]$address.InterfaceAlias
            if ($alias -like "Loopback*" -or [string]$address.InterfaceIndex -eq "1") { continue }
            if (-not $names.Contains($alias)) { [void]$names.Add($alias) }
        }

        foreach ($interface in @(Get-NetIPInterface -ErrorAction Stop)) {
            if ($null -eq $interface -or [string]$interface.AddressFamily -ne "IPv4") { continue }
            $alias = [string]$interface.InterfaceAlias
            if ($alias -like "Loopback*" -or [string]$interface.InterfaceIndex -eq "1") { continue }

            # Um adaptador automático conectado (sem o estado da conexão, conta como conectado): há o que renovar.
            if ([string]$interface.Dhcp -eq "Enabled") {
                if ([string](Get-TFToolkitJsonValue -Object $interface -Name "ConnectionState" -Default "Connected") -ne "Disconnected") { $dhcp = $true }
                continue
            }

            if ([string]$interface.Dhcp -ne "Disabled") { continue }
            if (-not $names.Contains($alias)) { [void]$names.Add($alias) }
        }
    }
    catch {
        # Sem saber, vale o lado seguro: o reparo deixa de fora o que apagaria uma configuração fixa, e não renova o IP.
        return [PSCustomObject]@{ Static = $true; Unknown = $true; Interfaces = @(); Dhcp = $false }
    }

    return [PSCustomObject]@{ Static = ($names.Count -gt 0); Unknown = $false; Interfaces = @($names); Dhcp = $dhcp }
}


function Get-TFToolkitManualDnsAdapters {
    <#
    Os adaptadores (Ethernet e Wi-Fi ativos, como em Trocar o servidor DNS) com DNS posto à mão, mesmo com o DHCP ligado:
    um Pi-hole, um DNS de filtro para a família, o da empresa ou o que o próprio TF-Toolkit gravou. O "netsh int ip reset"
    refaz as chaves do TCP/IP em que esses servidores ficam, e eles se perderiam. Devolve Alias e Unknown (o DNS não pôde
    ser lido: conta junto, pelo lado seguro).
    #>
    return @(
        Get-TFToolkitDnsAdapters | Where-Object { $null -ne $_ -and [string]$_.Mode -in @("Static", "Unknown") } | ForEach-Object {
            [PSCustomObject]@{ Alias = [string]$_.Alias; Unknown = ([string]$_.Mode -eq "Unknown") }
        }
    )
}


function Invoke-TFToolkitNetworkDnsOnly {
    # O reparo de manutenção com a conexão em uso (Get-TFToolkitNetworkHoldReason): só limpa o DNS, que não corta nada, e
    # diz por que o resto ficou de fora. Devolve o TFToolkit.Result da etapa.
    param (
        [string]$Title = (Get-TFToolkitText 'Reparar rede e DNS'),
        [string]$Reason
    )

    try {
        $dns = Invoke-TFToolkitNetworkCommand -Title (Get-TFToolkitText 'Limpar cache DNS') -FilePath "ipconfig.exe" -Arguments @("/flushdns")
    }
    finally {
        Write-Progress -Activity (Get-TFToolkitText 'Reparando a rede') -Completed
    }

    if ($dns.Kind -eq "Failed") {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O DNS não foi limpo; o resto do reparo ficou de fora porque {0}.' "$Reason")
        return (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o DNS não foi limpo ({0})' "$Reason") -Title $Title)
    }

    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'DNS limpo. O resto do reparo ficou de fora porque {0}.' "$Reason")
    return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'só o DNS foi limpo: {0}' "$Reason") -Title $Title)
}


function Get-TFToolkitNetworkHoldReason {
    <#
    O motivo para o reparo de manutenção não derrubar a conexão: o PC usado pela Área de Trabalho Remota ou uma VPN
    ligada (as do Windows, por Get-VpnConnection, e as de programas, pelo adaptador de rede deles: OpenVPN, WireGuard,
    AnyConnect, GlobalProtect, FortiClient e outras). "" quando nada impede. Sem como ler, não impede.
    #>
    if ([string]$env:SESSIONNAME -like "RDP-*") { return (Get-TFToolkitText 'o PC está sendo usado pela Área de Trabalho Remota') }

    if (Get-Command Get-VpnConnection -ErrorAction SilentlyContinue) {
        foreach ($scope in @($false, $true)) {
            try {
                $connections = $(if ($scope) { @(Get-VpnConnection -AllUserConnection -ErrorAction Stop) } else { @(Get-VpnConnection -ErrorAction Stop) })
                if (@($connections | Where-Object { [string]$_.ConnectionStatus -eq "Connected" }).Count -gt 0) { return (Get-TFToolkitText 'há uma VPN ligada') }
            }
            catch {
                continue
            }
        }
    }

    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        try {
            $pattern = '(?i)TAP-Windows|Wintun|WireGuard|AnyConnect|OpenVPN|Fortinet|FortiClient|PANGP|GlobalProtect|Juniper|Pulse Secure|Ivanti|SonicWall|Check Point|Zscaler|NordLynx|ProtonVPN|Tailscale|ZeroTier|Hamachi|Cloudflare WARP|Cisco Secure Client'
            $vpn = @(Get-NetAdapter -ErrorAction Stop | Where-Object { [string]$_.Status -eq "Up" -and ([string]$_.InterfaceDescription -match $pattern -or [string]$_.Name -match $pattern) })
            if ($vpn.Count -gt 0) { return (Get-TFToolkitText 'há uma VPN ligada') }
        }
        catch {
            return ""
        }
    }

    return ""
}


function Get-TFToolkitNetworkRepairCommands {
    param (
        # IP fixo em algum adaptador (Get-TFToolkitStaticIpConfiguration): o reset de TCP/IP fica de fora.
        [switch]$HasStaticIp,

        # DNS posto à mão em algum adaptador (Get-TFToolkitManualDnsAdapters): o reset de TCP/IP fica de fora.
        [switch]$HasManualDns,

        # Nenhum adaptador conectado pega o IP do roteador, ou não deu para saber: liberar e renovar ficam de fora.
        [switch]$NoDhcp
    )

    # A ordem importa: o IP é liberado e renovado primeiro, a limpeza de DNS vem depois (já com o IP novo) e os
    # resets de Winsock/TCP-IP ficam por último porque só terminam de valer após reiniciar.
    # O release/renew só mexe nos adaptadores com IP automático (um IP fixo continua como está); o reset de TCP/IP apaga o
    # IP e o DNS postos à mão em todos os adaptadores.
    # Id diz qual é cada um (release, renew, flushdns, winsock, ipreset), sem depender do título traduzido.
    $commands = @()

    if (-not $NoDhcp) {
        $commands += [PSCustomObject]@{ Id = "release"; Title = (Get-TFToolkitText 'Liberar endereço IP'); FilePath = "ipconfig.exe"; Arguments = @("/release"); NeedsRestart = $false }
        $commands += [PSCustomObject]@{ Id = "renew"; Title = (Get-TFToolkitText 'Renovar endereço IP'); FilePath = "ipconfig.exe"; Arguments = @("/renew"); NeedsRestart = $false }
    }

    $commands += [PSCustomObject]@{ Id = "flushdns"; Title = (Get-TFToolkitText 'Limpar cache DNS'); FilePath = "ipconfig.exe"; Arguments = @("/flushdns"); NeedsRestart = $false }
    $commands += [PSCustomObject]@{ Id = "winsock"; Title = (Get-TFToolkitText 'Redefinir Winsock'); FilePath = "netsh.exe"; Arguments = @("winsock", "reset"); NeedsRestart = $true }

    if (-not $HasStaticIp -and -not $HasManualDns) {
        $commands += [PSCustomObject]@{ Id = "ipreset"; Title = (Get-TFToolkitText 'Redefinir TCP/IP'); FilePath = "netsh.exe"; Arguments = @("int", "ip", "reset"); NeedsRestart = $true }
    }

    return @($commands)
}


function Invoke-TFToolkitNetworkCommand {
    # Executa um comando de rede e devolve um TFToolkit.Result.
    param (
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    # O andamento vai para a barra de progresso; o resumo fica com uma linha por comando, a do resultado.
    Write-Progress -Activity (Get-TFToolkitText 'Reparando a rede') -Status $Title

    try {
        $exitCode = Invoke-TFToolkitNative -FilePath $FilePath -Arguments $Arguments -IgnoreExitCode -PassThru
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText '{0} falhou: {1}' "$Title" "$($_.Exception.Message)")
        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
        $result.Etapa = $Title
        return $result
    }

    $result = Get-TFToolkitExitCodeResult -ExitCode $exitCode
    $result.Etapa = $Title

    if ($result.Kind -eq "Ok") {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText '{0} concluído.' "$Title")
    }
    else {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não deu certo: {0} (código {1}).' "$Title" "$(Format-TFToolkitExitCode -ExitCode $exitCode)")
    }

    return $result
}


function Wait-TFToolkitInternet {
    # Depois do reset o adaptador demora a voltar: tenta algumas vezes antes de concluir que ainda está sem internet.
    param (
        [int]$Attempts = 4,
        [int]$DelaySeconds = 3
    )

    $connectivity = $null

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Start-Sleep -Seconds $DelaySeconds
        $connectivity = Test-TFToolkitInternetConnectivity

        if ($connectivity.Ok) {
            break
        }
    }

    return $connectivity
}


function Invoke-TFToolkitNetworkRepair {
    # -Embedded (dentro de um fluxo): não pergunta nada e só repara quando a rede não funciona. -Force (o Otimizar), junto
    # com -Embedded: com a rede funcionando, limpa o DNS, como manutenção; o resto do reparo (renovar o IP, redefinir o
    # Winsock e o TCP/IP) é para quando a internet falha, como a Microsoft indica: num PC que funciona ele não melhora
    # nada, pede reinício e pode desfazer uma VPN, um antivírus que filtra a rede ou configurações postas à mão. Sem
    # nenhuma rede conectada, o reparo continua de fora. Numa rede que limita o acesso (um Wi-Fi que pede login numa página),
    # nenhum comando do reparo faz o login: dentro de um fluxo, só o DNS é limpo; sozinho, a tela diz isso antes de perguntar.
    # Sozinho, quando o Winsock ou o TCP/IP foram refeitos, oferece reiniciar (Depois como padrão).
    param (
        [switch]$Embedded,
        [switch]$PassThru,
        [switch]$Force
    )

    $title = (Get-TFToolkitText 'Reparar rede e DNS')

    Enter-TFToolkitAction -Title $title -Embedded:$Embedded

    if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'O reparo de rede exige privilégios de Administrador.'))) {
        $early = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'sem privilégios de Administrador') -Title $title
        if ($PassThru) { $early }
        Exit-TFToolkitAction -Embedded:$Embedded -Result $early
        return
    }

    # IP fixo em algum adaptador (com os nomes, para o aviso).
    $staticIp = Get-TFToolkitStaticIpConfiguration
    $hasStaticIp = [bool]$staticIp.Static
    # Liberar e renovar o IP só quando algum adaptador conectado o pega do roteador (sem saber, não).
    $noDhcp = ([bool]$staticIp.Unknown -or -not [bool](Get-TFToolkitJsonValue -Object $staticIp -Name "Dhcp" -Default $true))
    # DNS posto à mão (com os nomes, para o aviso): o reset de TCP/IP o apagaria.
    $manualDns = @(Get-TFToolkitManualDnsAdapters)
    $hasManualDns = ($manualDns.Count -gt 0)
    $final = New-TFToolkitResult -Kind Ok -Title $title

    # O reparo refaz as configurações de rede do Windows, o que costuma resolver internet que não abre sites; o que ele faz
    # aparece em "O que o reparo faz", antes da pergunta.
    Write-TFToolkitSection -Title (Get-TFToolkitText 'Diagnóstico rápido')
    Write-Progress -Activity $title -Status (Get-TFToolkitText 'testando a conexão')

    try { $connectivity = Test-TFToolkitInternetConnectivity } finally { Write-Progress -Activity $title -Completed }
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Acesso por IP (sem DNS)') -Value (Get-TFToolkitIpReachText -Connectivity $connectivity) -LabelWidth 26
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Resolução de DNS') -Value $(if ($connectivity.DnsOk) { (Get-TFToolkitText 'Funciona') } else { (Get-TFToolkitText 'Falhou') }) -LabelWidth 26

    # Um proxy configurado (por um programa ou pela empresa) explica a internet que só funciona em alguns programas, e
    # nenhum dos comandos do reparo o muda.
    $proxy = Get-TFToolkitProxySettings
    if ($proxy.Text) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Proxy') -Value $proxy.Text -LabelWidth 26 }

    # Quando os testes diretos falham, o que o Windows diz da conexão também conta (numa rede com proxy, o acesso direto
    # a 1.1.1.1 e 8.8.8.8 é bloqueado, mas a internet funciona).
    $windowsInternet = $null
    $limited = $false

    if (-not $connectivity.Ok) {
        # O Windows sabe quando a rede limita o acesso (em geral, um Wi-Fi que pede login numa página).
        $limited = ([string](Get-TFToolkitInternetConnection).Level -eq "Limited")
        $windowsInternet = Get-TFToolkitWindowsInternetStatus

        if ($null -ne $windowsInternet) {
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Conexão segundo o Windows') -Value $(if ($windowsInternet) { (Get-TFToolkitText 'Com acesso à internet') } else { (Get-TFToolkitText 'Sem acesso à internet') }) -LabelWidth 26
        }
    }

    # Dentro de um fluxo, o reparo só roda se algo estiver quebrado; no Otimizar (-Force), com a rede funcionando, o DNS é
    # limpo (mais abaixo).
    if ($Embedded -and -not $Force -and $connectivity.Ok) {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'A conexão e o DNS funcionam; o reparo de rede não é necessário.')

        $early = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'rede funcionando') -Title $title
        if ($PassThru) { $early }
        Exit-TFToolkitAction -Embedded:$Embedded -Result $early
        return
    }

    # Sem ninguém olhando, o reparo (que derruba a conexão e redefine o Winsock) só roda quando nada indica que a rede
    # funciona: nomes que resolvem ou o Windows dizendo que há internet bastam para não mexer.
    if ($Embedded -and -not $Force -and ($connectivity.DnsOk -or $windowsInternet -eq $true)) {
        $evidence = $(if ($windowsInternet -eq $true) { (Get-TFToolkitText 'o Windows informa acesso à internet') } else { (Get-TFToolkitText 'os nomes de sites são resolvidos') })
        # Os servidores de teste não responderam direto: comum em redes com proxy ou firewall.
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'A rede funciona ({0}, comum em redes com proxy); o reparo não foi necessário.' "$evidence")
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Se a internet estiver com problema, use Rede > Reparar rede e DNS.')

        $early = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'a rede funciona ({0})' "$evidence") -Title $title
        if ($PassThru) { $early }
        Exit-TFToolkitAction -Embedded:$Embedded -Result $early
        return
    }

    # Sem nenhuma rede conectada, não há o que reparar: os resets não ligam o Wi-Fi nem o cabo, podem atrapalhar uma VPN
    # e só pediriam um reinício à toa.
    if ($Embedded -and $false -eq (Test-TFToolkitNetworkConnected)) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O PC não está ligado a nenhuma rede; o reparo de rede não foi executado.')

        $early = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nenhuma rede conectada') -Title $title
        if ($PassThru) { $early }
        Exit-TFToolkitAction -Embedded:$Embedded -Result $early
        return
    }

    # Como manutenção (o Otimizar), com a rede funcionando, só o DNS é limpo, o que não corta nada. Funciona quando os
    # testes passam, quando os nomes de sites resolvem ou quando o Windows diz que há internet (numa rede com proxy, o
    # acesso direto aos servidores de teste é bloqueado). Com a VPN ou a Área de Trabalho Remota, o motivo é esse.
    $hold = ""

    if ($Embedded -and $limited) {
        # Sem ninguém olhando, numa rede que pede login: renovar o IP e refazer o Winsock não fazem o login, e pediriam um
        # reinício à toa.
        $hold = (Get-TFToolkitText 'a rede limita o acesso (pode pedir login numa página)')
    }
    elseif ($Embedded -and $Force -and ($connectivity.Ok -or $connectivity.DnsOk -or $windowsInternet -eq $true)) {
        $hold = Get-TFToolkitNetworkHoldReason
        if ([string]::IsNullOrWhiteSpace($hold)) { $hold = (Get-TFToolkitText 'a internet funciona') }
    }
    elseif ($Embedded) {
        # Sem ninguém para confirmar, o reparo completo também não derruba a Área de Trabalho Remota (numa rede local, ela
        # funciona mesmo com a internet fora) nem uma VPN: fica a limpeza do DNS, e o motivo.
        $hold = Get-TFToolkitNetworkHoldReason
    }

    if (-not [string]::IsNullOrWhiteSpace($hold)) {
        $early = Invoke-TFToolkitNetworkDnsOnly -Title $title -Reason $hold

        if ($PassThru) { $early }
        Exit-TFToolkitAction -Embedded:$Embedded -Result $early
        return
    }

    # O que o reparo faz, em palavras; os comandos em si ficam nos detalhes técnicos.
    Write-TFToolkitSection -Title (Get-TFToolkitText 'O que o reparo faz')
    $repairCommands = @(Get-TFToolkitNetworkRepairCommands -HasStaticIp:$hasStaticIp -HasManualDns:$hasManualDns -NoDhcp:$noDhcp)
    $commandIds = @($repairCommands | ForEach-Object { [string]$_.Id })

    if ($commandIds -contains "renew") {
        Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'Pede um endereço novo ao roteador.')
    }

    Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'Apaga a memória de endereços de sites (DNS).')
    $resets = $(if ($commandIds -contains "ipreset") { (Get-TFToolkitText 'Winsock e TCP/IP') } else { "Winsock" })
    Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'Refaz as configurações de rede do Windows ({0}); pede reiniciar.' "$resets")

    foreach ($command in $repairCommands) {
        Write-TFToolkitCommand -Command "$($command.FilePath -replace '\.exe$', '') $($command.Arguments -join ' ')"
    }

    Write-Host ""

    if ($staticIp.Unknown) {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Não foi possível conferir se algum adaptador usa IP fixo: liberar/renovar IP e redefinir TCP/IP foram removidos para não apagar uma configuração manual.')
    }
    elseif ($hasStaticIp -and $noDhcp) {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'IP fixo em {0}: liberar/renovar IP e redefinir TCP/IP ficaram de fora (o IP fixo não vem do roteador, e o reset o apagaria).' "$(Join-TFToolkitList -Items @($staticIp.Interfaces))")
    }
    elseif ($hasStaticIp) {
        # O IP fixo de outro adaptador (o do VirtualBox, o do WSL) não impede renovar o IP dos automáticos.
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'IP fixo em {0}: redefinir TCP/IP ficou de fora para não apagar essa configuração; liberar e renovar o IP só mexem nos adaptadores automáticos.' "$(Join-TFToolkitList -Items @($staticIp.Interfaces))")
    }

    # Com IP estático, o reset de TCP/IP já saiu, e o aviso acima já diz isso.
    if ($hasManualDns -and -not $hasStaticIp) {
        $fixed = @($manualDns | Where-Object { -not $_.Unknown } | ForEach-Object { $_.Alias })
        $unread = @($manualDns | Where-Object { $_.Unknown } | ForEach-Object { $_.Alias })
        $where = @()
        if ($fixed.Count -gt 0) { $where += (Get-TFToolkitText 'DNS fixo em {0}' "$(Join-TFToolkitList -Items $fixed)") }
        if ($unread.Count -gt 0) { $where += (Get-TFToolkitText 'DNS que não pôde ser lido em {0}' "$(Join-TFToolkitList -Items $unread)") }
        # A frase começa pelo nome do que foi achado: em inglês ele vem em minúscula ("static DNS on Wi-Fi").
        $whereText = $where -join '; '
        $whereText = $whereText.Substring(0, 1).ToUpper() + $whereText.Substring(1)
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText '{0}: redefinir TCP/IP foi removido para não apagar esses servidores DNS.' "$whereText")
    }

    # Pela Área de Trabalho Remota ou por uma VPN, a pessoa perde justamente a conexão por onde está: o aviso vem antes da
    # pergunta.
    if (-not $Embedded) {
        if ([string]$env:SESSIONNAME -like "RDP-*") {
            Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Este PC está sendo usado pela Área de Trabalho Remota: o reparo derruba a conexão, e o acesso remoto pode não voltar sozinho.')
        }
        elseif (-not [string]::IsNullOrWhiteSpace((Get-TFToolkitNetworkHoldReason))) {
            Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Há uma VPN ligada: o reparo pode desconectá-la.')
        }
    }

    Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'A conexão pode cair por alguns instantes. O reset do Winsock pode afetar VPN e alguns antivírus.')

    # Com a internet funcionando, só a tela do reparo chega aqui (dentro de um fluxo, ele parou antes): a pergunta vem a seguir.
    if ($connectivity.Ok) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'A internet parece funcionar normalmente: só continue se tiver um problema de rede.')
    }
    elseif ($false -eq (Test-TFToolkitNetworkConnected)) {
        # Sem nenhuma rede, o problema é o Wi-Fi desligado, o cabo solto ou o modo avião, e nenhum comando do reparo liga isso.
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'O PC não está ligado a nenhuma rede: ligue o Wi-Fi ou conecte o cabo; o reparo não faz isso.')
    }
    elseif ($limited) {
        # Numa rede que pede login, "o reparo é indicado" mandaria a pessoa para o caminho errado.
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'O Windows indica que a rede limita o acesso (em geral, um Wi-Fi que pede login numa página, como o de hotel e aeroporto): o reparo não resolve isso. Abra o navegador e entre na página da rede.')
    }
    elseif ($windowsInternet -eq $true -or $connectivity.DnsOk) {
        # Os testes diretos falham numa rede com proxy ou firewall que os bloqueia, e a internet funciona assim mesmo: o
        # reparo não é indicado só por eles.
        $evidence = $(if ($windowsInternet -eq $true) { (Get-TFToolkitText 'o Windows informa acesso à internet') } else { (Get-TFToolkitText 'os nomes de sites são resolvidos') })
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Os testes diretos falharam, mas {0} (comum em redes com proxy ou firewall): só continue se os sites não abrirem.' "$evidence")
    }
    else {
        Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'A internet não está funcionando: o reparo é indicado.')
    }

    if ($proxy.Text) {
        # Um proxy que não é da empresa, com a internet funcionando só em alguns programas, pode ter sido posto por um programa.
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Há um proxy configurado, que o reparo não muda: confira em Configurações, Rede e Internet, Proxy.')
    }

    Write-Host ""

    # O reparo derruba a conexão e redefine o Winsock (o que pode afetar VPN e antivírus): a resposta padrão é sempre Não,
    # e o aviso acima diz quando ele é indicado. Na Manutenção, o usuário já confirmou.
    if (-not $Embedded -and -not (Confirm-TFToolkitAction (Get-TFToolkitText 'Reparar a rede agora?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Reparar') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
        Write-Host ""
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')

        $early = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title
        if ($PassThru) { $early }
        Exit-TFToolkitAction -Embedded:$Embedded -Result $early
        return
    }

    try {
        $steps = @()
        $needsRestart = $false

        try {
            foreach ($command in $repairCommands) {
                $step = Invoke-TFToolkitNetworkCommand -Title $command.Title -FilePath $command.FilePath -Arguments $command.Arguments
                $steps += $step

                # Só os resets de Winsock e TCP/IP pedem reinício, e só se tiverem funcionado.
                if ($command.NeedsRestart -and $step.Kind -ne "Failed") {
                    $needsRestart = $true
                }
            }
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Reparando a rede') -Completed
        }

        $failedSteps = @($steps | Where-Object { $_.Kind -eq "Failed" })
        $restart = @{ RebootRequired = $needsRestart }

        # O que rodou entra no Histórico de mudanças (o Winsock e o TCP/IP refeitos mudam a pilha de rede do Windows).
        $ran = @($steps | Where-Object { $_.Kind -ne "Failed" } | ForEach-Object { [string]$_.Etapa })
        if ($ran.Count -gt 0) { [void](Add-TFToolkitChange -Action $title -Text (Join-TFToolkitList -Items $ran)) }

        if ($steps.Count -gt 0 -and $failedSteps.Count -eq $steps.Count) {
            # Nada foi executado com sucesso: conferir a conexão só faria esperar, e não há o que reiniciar.
            $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nenhum dos comandos funcionou') -Title $title
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'O reparo não funcionou') -Note (Get-TFToolkitText 'Nenhum comando funcionou; o código de cada um está no resumo.'))
            Write-Host ""
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Nenhum comando do reparo funcionou.')
        }
        else {
            Write-Progress -Activity $title -Status (Get-TFToolkitText 'conferindo se a conexão voltou (pode levar até um minuto)')

            try { $after = Wait-TFToolkitInternet } finally { Write-Progress -Activity $title -Completed }

            Write-TFToolkitSection -Title (Get-TFToolkitText 'Depois do reparo')
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Acesso por IP (sem DNS)') -Value (Get-TFToolkitIpReachText -Connectivity $after) -LabelWidth 26
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Resolução de DNS') -Value $(if ($after.DnsOk) { (Get-TFToolkitText 'Funciona') } else { (Get-TFToolkitText 'Falhou') }) -LabelWidth 26
            Write-Host ""

            if ($failedSteps.Count -gt 0) {
                $failedText = $(if ($failedSteps.Count -eq 1) { (Get-TFToolkitText '1 comando falhou') } else { (Get-TFToolkitText '{0} comandos falharam' "$($failedSteps.Count)") })
                $final = New-TFToolkitResult -Kind Warning -Detail $failedText -Title $title -Data $restart
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Reparo concluído com alertas: {0}.' "$failedText")

                # Na janela, o título diz se a conexão voltou (o que a pessoa quer saber); a frase, o que não deu certo.
                $failedNames = Join-TFToolkitList -Items @($failedSteps | ForEach-Object { [string]$_.Etapa })
                [void](Set-TFToolkitResultView -Result $final -Headline $(if ($after.Ok) { (Get-TFToolkitText 'A conexão está funcionando') } else { (Get-TFToolkitText 'A conexão ainda não voltou') }) `
                        -Note $(if ($failedSteps.Count -eq 1) { (Get-TFToolkitText '{0} não deu certo; o código está no resumo.' "$failedNames") } else { (Get-TFToolkitText '{0} não deram certo; os códigos estão no resumo.' "$failedNames") }))
            }
            elseif (-not $after.Ok) {
                $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'a conexão ainda não voltou') -Title $title -Data $restart
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Os comandos foram executados, mas a conexão ainda não voltou.{0}' "$(if ($needsRestart) { (Get-TFToolkitText ' Depois de reiniciar, teste de novo.') } else { (Get-TFToolkitText ' Reinicie o PC e teste de novo.') })")

                # Na janela, o que fazer agora: sem nenhuma rede, ligar o Wi-Fi ou o cabo (o botão abre as configurações de
                # rede); com a rede, reiniciar e testar de novo (o pedido de reinício já está na frase).
                if ($false -eq (Test-TFToolkitNetworkConnected)) {
                    [void](Set-TFToolkitNoNetworkView -Result $final)
                }
                else {
                    [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'A conexão ainda não voltou') -Note (Get-TFToolkitText 'Reinicie o PC e teste de novo; se continuar, confira o roteador ou fale com a operadora.'))
                }
            }
            else {
                $final = New-TFToolkitResult -Kind Ok -Title $title -Data $restart
                Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Reparo concluído; a conexão está funcionando.')
                [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'Rede reparada') -Note (Get-TFToolkitText 'A conexão está funcionando.'))
            }

            if ($needsRestart -and $Embedded) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Reinicie o PC para o reparo terminar de valer.')
            }
            elseif ($needsRestart) {
                # O Winsock e o TCP/IP refeitos só terminam de valer depois de reiniciar, como a Microsoft indica: a tela oferece
                # ali mesmo (Depois como padrão), como o Corrigir o Windows Update.
                Request-TFToolkitRestartOffer -Reason (Get-TFToolkitText 'Reiniciar agora termina o reparo da rede.') `
                    -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit após o reparo de rede.') `
                    -DeclinedMessage (Get-TFToolkitText 'O PC não foi reiniciado. O reparo termina de valer quando você reiniciar.') `
                    -Fallback (Get-TFToolkitText 'Reinicie o PC para o reparo terminar de valer.')
            }
        }
    }
    catch {
        Write-Host ""
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Falha durante o reparo de rede: {0}' "$($_.Exception.Message)")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title $title
    }

    if ($PassThru) { $final }
    Exit-TFToolkitAction -Embedded:$Embedded -Result $final
}


# ---------------------------------------------------------------------------
# Teste de velocidade
# ---------------------------------------------------------------------------

function Measure-TFToolkitSpeedLatency {
    <#
    Latência até o servidor do teste, em ms: pedidos vazios na mesma conexão, e o primeiro só abre a conexão (resolver o
    nome, negociar o TLS) e não conta. De cada um sai o tempo que o próprio servidor gastou (cabeçalho Server-Timing do
    Cloudflare), como no teste dele: fica o tempo de ida e volta, o que pesa em jogos e chamadas de vídeo. Vale a mediana.
    Uma falha no meio encerra com as amostras que já havia; sem nenhuma, $null: a latência é um extra e nunca impede o
    download de seguir. Só o primeiro pedido, que abre a conexão, espera 10 s; os outros, 5 s.
    #>
    param (
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$BaseUrl,
        [int]$Samples = 3
    )

    $times = New-Object System.Collections.Generic.List[double]

    for ($i = 0; $i -le $Samples; $i++) {
        try {
            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $probe = $Client.GetAsync("${BaseUrl}?bytes=0", [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
            Wait-TFToolkitTask -Task $probe -TimeoutSeconds $(if ($i -eq 0) { 10 } else { 5 })
            $watch.Stop()
            $answer = $probe.Result

            try {
                Assert-TFToolkitSpeedResponse -Response $answer
                $serverMs = Get-TFToolkitServerTimingMs -Response $answer
            }
            finally {
                $answer.Dispose()
            }

            if ($i -gt 0) { $times.Add([Math]::Max(0.0, $watch.Elapsed.TotalMilliseconds - $serverMs)) }
        }
        catch {
            break
        }
    }

    if ($times.Count -eq 0) { return $null }

    $sorted = @($times | Sort-Object)
    return [Math]::Round($sorted[[int][Math]::Floor($sorted.Count / 2)], 0)
}


function Get-TFToolkitServerTimingMs {
    # O tempo que o servidor gastou com o pedido, em ms, do cabeçalho Server-Timing ("cfRequestDuration;dur=1.2"); 0 sem ele.
    param ([Parameter(Mandatory)]$Response)

    try {
        $values = $null

        if ($Response.Headers.TryGetValues("Server-Timing", [ref]$values)) {
            foreach ($value in @($values)) {
                $match = [regex]::Match([string]$value, 'cfRequestDuration;dur=([0-9]+(\.[0-9]+)?)')
                if ($match.Success) { return [double]::Parse($match.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture) }
            }
        }

        return 0
    }
    catch {
        return 0
    }
}


function Get-TFToolkitSteadyMbps {
    <#
    A velocidade de um download depois do arranque da conexão, em Mbps. Toda conexão TCP começa devagar e acelera nos
    primeiros instantes; numa internet rápida, os 25 MB do teste chegam em menos de um segundo, e esse começo sozinho
    derrubava o resultado. O arranque acaba na primeira amostra com WarmupSeconds de transferência ou WarmupBytes recebidos;
    a velocidade é a do que veio depois. Quando o que veio depois é curto demais (menos de 0,1 s), ou nada veio, vale a conta
    inteira, como antes. Samples: objetos com Seconds (desde o início da transferência) e Bytes (total recebido até ali),
    em ordem.
    #>
    param (
        [AllowEmptyCollection()][object[]]$Samples = @(),
        [double]$WarmupSeconds = 0.25,
        [int64]$WarmupBytes = 5000000
    )

    $list = @($Samples | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return 0.0 }

    $last = $list[$list.Count - 1]
    $warm = @($list | Where-Object { [double]$_.Seconds -ge $WarmupSeconds -or [int64]$_.Bytes -ge $WarmupBytes }) | Select-Object -First 1

    if ($null -ne $warm -and ([double]$last.Seconds - [double]$warm.Seconds) -ge 0.1 -and [int64]$last.Bytes -gt [int64]$warm.Bytes) {
        return (Get-TFToolkitMbps -Bytes ([int64]$last.Bytes - [int64]$warm.Bytes) -Seconds ([double]$last.Seconds - [double]$warm.Seconds))
    }

    return (Get-TFToolkitMbps -Bytes ([int64]$last.Bytes) -Seconds ([double]$last.Seconds))
}


function Measure-TFToolkitDownload {
    # Baixa dados do Cloudflare até o limite de bytes ou de tempo e devolve a velocidade em Mbps (a do trecho depois do
    # arranque da conexão: Get-TFToolkitSteadyMbps). Bytes e Seconds são os do download inteiro.
    param (
        [int64]$MaxBytes = 25000000,
        [int]$MaxSeconds = 12,
        [string]$BaseUrl = "https://speed.cloudflare.com/__down"
    )

    $client = New-TFToolkitSpeedHttpClient -TimeoutSeconds 30
    $response = $null
    $stream = $null

    try {
        $latency = Measure-TFToolkitSpeedLatency -Client $client -BaseUrl $BaseUrl
        $request = $client.GetAsync("${BaseUrl}?bytes=$MaxBytes", [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        Wait-TFToolkitTask -Task $request -TimeoutSeconds 30
        $response = $request.Result
        Assert-TFToolkitSpeedResponse -Response $response

        $streamTask = $response.Content.ReadAsStreamAsync()
        Wait-TFToolkitTask -Task $streamTask -TimeoutSeconds 30
        $stream = $streamTask.Result

        # O relógio só corre a partir daqui: o tempo de resolver o nome, abrir a conexão e negociar o TLS não é velocidade da
        # internet, e numa conexão rápida (25 MB em um segundo) ele sozinho derrubava o resultado em um quinto ou mais.
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        # Blocos de até 256 KB: numa internet rápida, menos voltas no laço, que no PowerShell custam tempo.
        $buffer = New-Object byte[] 262144
        [int64]$total = 0
        $samples = New-Object System.Collections.Generic.List[object]

        while ($total -lt $MaxBytes -and $stopwatch.Elapsed.TotalSeconds -lt $MaxSeconds) {
            try {
                # Nunca além do limite de bytes, mesmo que o servidor mande mais do que o pedido.
                $read = $stream.ReadAsync($buffer, 0, [int][Math]::Min([int64]$buffer.Length, $MaxBytes - $total))
                Wait-TFToolkitTask -Task $read -TimeoutSeconds 20
                $received = $read.Result
            }
            catch {
                # A conexão caiu no meio: o que já chegou vale como medição. Sem nenhum byte, é falha.
                if ($total -gt 0) { break }
                throw
            }

            if ($received -le 0) {
                break
            }

            $total += $received
            $samples.Add([PSCustomObject]@{ Seconds = $stopwatch.Elapsed.TotalSeconds; Bytes = $total })
        }

        $stopwatch.Stop()

        return [PSCustomObject]@{
            Bytes     = $total
            Seconds   = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
            Mbps      = Get-TFToolkitSteadyMbps -Samples $samples.ToArray() -WarmupBytes ([Math]::Max([int64]1, [int64]($MaxBytes / 5)))
            LatencyMs = $latency
        }
    }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        $client.Dispose()
    }
}


function Measure-TFToolkitUpload {
    # Envia blocos de 1 MB ao Cloudflare até o limite de tempo; conexões lentas fazem poucos envios, rápidas fazem vários.
    param (
        [int]$ChunkBytes = 1000000,
        [int]$MaxSeconds = 8,
        [int]$MaxChunks = 12,
        [string]$Url = "https://speed.cloudflare.com/__up",
        [string]$WarmupUrl = "https://speed.cloudflare.com/__down?bytes=0"
    )

    $client = New-TFToolkitSpeedHttpClient -TimeoutSeconds 40

    try {
        # A conexão abre antes do relógio, como no download: resolver o nome, abrir a conexão e negociar o TLS não é
        # velocidade de envio, e numa internet rápida esse tempo, todo no primeiro envio, derrubava o resultado. Um pedido
        # vazio ao mesmo servidor deixa a conexão aberta para os envios. Se ele falhar, os envios tentam do mesmo jeito
        # (e dizem o erro deles).
        try {
            $warm = $client.GetAsync($WarmupUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
            Wait-TFToolkitTask -Task $warm -TimeoutSeconds 10
            $warm.Result.Dispose()
        }
        catch {
            Write-Verbose "Abertura da conexão do upload: $($_.Exception.Message)"
        }

        $buffer = New-Object byte[] $ChunkBytes
        (New-Object System.Random).NextBytes($buffer)

        [int64]$total = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        for ($chunk = 0; $chunk -lt $MaxChunks -and $stopwatch.Elapsed.TotalSeconds -lt $MaxSeconds; $chunk++) {
            $content = [System.Net.Http.ByteArrayContent]::new($buffer)
            $response = $null

            try {
                $post = $client.PostAsync($Url, $content)
                Wait-TFToolkitTask -Task $post -TimeoutSeconds 40
                $response = $post.Result
                Assert-TFToolkitSpeedResponse -Response $response
                $total += $ChunkBytes
            }
            catch {
                # Um envio que falha depois de outros que deram certo encerra a medição com o que já foi enviado. Se o primeiro
                # já falha, o servidor não aceita o teste: é falha.
                if ($total -gt 0) { break }
                throw
            }
            finally {
                $content.Dispose()
                if ($response) { $response.Dispose() }
            }
        }

        $stopwatch.Stop()

        return [PSCustomObject]@{
            Bytes   = $total
            Seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
            Mbps    = Get-TFToolkitMbps -Bytes $total -Seconds $stopwatch.Elapsed.TotalSeconds
        }
    }
    finally {
        $client.Dispose()
    }
}


function Format-TFToolkitSpeedMbps {
    # "94 Mbps" a partir de 10, "8,5 Mbps" abaixo: casas decimais numa velocidade alta só atrapalham a leitura.
    param ([double]$Mbps)

    return "$(Format-TFToolkitNumber -Value $Mbps -Decimals $(if ($Mbps -ge 10) { 0 } else { 1 })) Mbps"
}


function Get-TFToolkitSpeedVerdict {
    <#
    O que a velocidade de download e a latência querem dizer no dia a dia. Devolve Lines: objetos com Type (Info ou
    Warning) e Message, na ordem da tela. A última linha sempre lembra que o teste com Wi-Fi mede menos que o contratado.
    #>
    param (
        [double]$DownloadMbps,
        $LatencyMs = $null
    )

    $lines = @()

    if ($DownloadMbps -lt 10) { $lines += [PSCustomObject]@{ Type = "Warning"; Message = (Get-TFToolkitText 'Internet lenta: vídeos em HD podem travar e downloads demoram.') } }
    elseif ($DownloadMbps -lt 50) { $lines += [PSCustomObject]@{ Type = "Info"; Message = (Get-TFToolkitText 'Boa para vídeo em HD, aulas e chamadas de vídeo.') } }
    elseif ($DownloadMbps -le 200) { $lines += [PSCustomObject]@{ Type = "Info"; Message = (Get-TFToolkitText 'Boa para vídeo em 4K e vários aparelhos ao mesmo tempo.') } }
    else { $lines += [PSCustomObject]@{ Type = "Info"; Message = (Get-TFToolkitText 'Internet rápida.') } }

    if ($null -ne $LatencyMs -and [double]$LatencyMs -gt 100) {
        $lines += [PSCustomObject]@{ Type = "Warning"; Message = (Get-TFToolkitText 'A latência está alta: jogos online e chamadas podem atrasar.') }
    }

    $lines += [PSCustomObject]@{ Type = "Info"; Message = (Get-TFToolkitText 'Se você contratou mais que isso, repita o teste com cabo, perto do roteador; se continuar abaixo, fale com a operadora.') }

    return [PSCustomObject]@{ Lines = @($lines) }
}


function Write-TFToolkitSpeedVerdict {
    # Escreve as linhas de Get-TFToolkitSpeedVerdict. São leitura do resultado, não o resultado: não mudam a faixa.
    param (
        [double]$DownloadMbps,
        $LatencyMs = $null
    )

    foreach ($line in (Get-TFToolkitSpeedVerdict -DownloadMbps $DownloadMbps -LatencyMs $LatencyMs).Lines) {
        Write-TFToolkitStatus -Type $line.Type -Notice -Message $line.Message
    }
}


function Test-TFToolkitInternetSpeed {
    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Testar velocidade da internet')

    # Sem nenhuma rede, perguntar e medir só terminaria num erro técnico ("host desconhecido"): a faixa diz o que fazer,
    # como no teste de conectividade.
    if ($false -eq (Test-TFToolkitNetworkConnected)) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O PC não está ligado a nenhuma rede: ligue o Wi-Fi ou conecte o cabo (e confira o modo avião).')
        Exit-TFToolkitAction -Result (Set-TFToolkitNoNetworkView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o PC não está ligado a nenhuma rede')))
        return
    }

    # Uma medida aproximada: não substitui o teste da operadora, mas mostra gargalos claros.
    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Mede a latência e a velocidade até o servidor da Cloudflare mais próximo.')

    # Numa conexão limitada (celular roteado, chip, rede marcada como limitada), os 35 MB saem da franquia: o padrão vira Não.
    $metered = Test-TFToolkitMeteredConnection

    if ($metered) {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'A conexão com a internet é limitada (plano de dados): o teste usa até cerca de 35 MB da sua franquia.')
    }
    else {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O teste usa até cerca de 35 MB de dados. Evite em conexões com franquia (4G/5G).')
    }

    Write-Host ""

    if (-not (Confirm-TFToolkitAction (Get-TFToolkitText 'Iniciar o teste agora?') -DefaultKey $(if ($metered) { "N" } else { "S" }) -YesLabel (Get-TFToolkitText 'Testar') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
        Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário'))
        return
    }

    $final = New-TFToolkitResult -Kind Ok

    try {
        Enable-TFToolkitTls12
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

        $download = $null
        $upload = $null
        $downloadProblem = ""
        $uploadProblem = ""

        # Cada medição tem a sua falha: um upload recusado pelo servidor não pode jogar fora um download que deu certo. O
        # andamento fica na barra de progresso; na tela, só as falhas e o resultado.
        try {
            Write-Progress -Activity (Get-TFToolkitText 'Testando a velocidade') -Status (Get-TFToolkitText 'latência e download (até 15 s)') -PercentComplete 0

            try {
                $download = Measure-TFToolkitDownload
            }
            catch {
                $downloadProblem = Get-TFToolkitSpeedProblem -Exception $_.Exception
                Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O download falhou: {0}' "$downloadProblem")
            }

            Write-Progress -Activity (Get-TFToolkitText 'Testando a velocidade') -Status (Get-TFToolkitText 'upload (até 8 s)') -PercentComplete 60

            try {
                $upload = Measure-TFToolkitUpload
            }
            catch {
                $uploadProblem = Get-TFToolkitSpeedProblem -Exception $_.Exception
                Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O upload falhou: {0}' "$uploadProblem")
            }
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Testando a velocidade') -Completed
        }

        if ($null -eq $download -and $null -eq $upload) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Verifique a conexão, o DNS, o firewall, a VPN ou um bloqueio do endereço de teste.')
            $final = Set-TFToolkitSpeedFailureView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível medir: {0}' "$downloadProblem")) -Problem $downloadProblem
        }
        else {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Resultado')

            $downloadText = (Get-TFToolkitText 'não foi possível medir')
            $uploadText = (Get-TFToolkitText 'não foi possível medir')
            $latency = $(if ($null -ne $download) { Get-TFToolkitJsonValue -Object $download -Name "LatencyMs" -Default $null } else { $null })
            $latencyText = ""

            if ($null -ne $latency) {
                $latencyText = "$(Format-TFToolkitNumber -Value $latency -Decimals 0) ms"
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Latência') -Value $latencyText
            }

            # Vírgula decimal, como no resto do TF-Toolkit ("94 Mbps", "8,5 Mbps"). Quanto foi baixado e em quanto tempo fica
            # numa linha à parte, que a janela deixa só nos detalhes técnicos.
            if ($null -ne $download) {
                $downloadText = Format-TFToolkitSpeedMbps -Mbps $download.Mbps
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Download') -Value $downloadText
                Write-Host (Get-TFToolkitText '      {0} baixados em {1} s' "$(Format-TFToolkitBytes -Bytes $download.Bytes)" "$(Format-TFToolkitNumber -Value $download.Seconds -Decimals 2)") -ForegroundColor DarkGray
            }
            else {
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Download') -Value $downloadText
            }

            if ($null -ne $upload) {
                $uploadText = Format-TFToolkitSpeedMbps -Mbps $upload.Mbps
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Upload') -Value $uploadText
                Write-Host (Get-TFToolkitText '      {0} enviados em {1} s' "$(Format-TFToolkitBytes -Bytes $upload.Bytes)" "$(Format-TFToolkitNumber -Value $upload.Seconds -Decimals 2)") -ForegroundColor DarkGray
            }
            else {
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Upload') -Value $uploadText
            }

            # O que os números querem dizer, para quem não sabe se 40 Mbps é muito ou pouco.
            if ($null -ne $download -and $download.Mbps -gt 0) {
                Write-Host ""
                Write-TFToolkitSpeedVerdict -DownloadMbps $download.Mbps -LatencyMs $latency
            }

            if ($null -eq $download) {
                # Na janela, o título diz que o download não foi medido; a frase, o upload e o motivo.
                $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o download falhou: {0}' "$downloadProblem")
                [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'O download não foi medido') `
                        -Note (Get-TFToolkitText 'Upload de {0}; o download falhou: {1}.' "$uploadText" "$(([string]$downloadProblem).Trim().TrimEnd('.'))"))
            }
            elseif ($null -eq $upload) {
                # O download, o número que mais importa, continua no título; a frase diz que o upload não foi medido.
                $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o upload falhou: {0}' "$uploadProblem")
                [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText '{0} de download' "$downloadText") `
                        -Note (Get-TFToolkitText 'O upload não foi medido: {0}.' "$(([string]$uploadProblem).Trim().TrimEnd('.'))"))
            }
            elseif ($download.Mbps -le 0 -or $upload.Mbps -le 0) {
                Write-Host ""
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Uma das medições retornou zero. Repita o teste ou verifique a conexão.')
                $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'uma das medições retornou zero')
            }
            else {
                # Na ordem da tela: latência, download e upload.
                $final = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText '{0}download {1}, upload {2}' "$(if ($latencyText) { (Get-TFToolkitText 'latência {0}, ' "$latencyText") })" "$downloadText" "$uploadText")

                # Na janela, o título traz o download; a frase, o upload, a latência e o que isso quer dizer (sem a dica de
                # repetir com cabo, que fica no resumo). Internet lenta ou latência alta deixam a faixa amarela.
                $reading = @((Get-TFToolkitSpeedVerdict -DownloadMbps $download.Mbps -LatencyMs $latency).Lines)
                $meaning = @($reading | Select-Object -First ($reading.Count - 1))
                $slow = @($meaning | Where-Object { $_.Type -eq "Warning" }).Count -gt 0
                [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText '{0} de download' "$downloadText") -Tone $(if ($slow) { "Warn" } else { "" }) `
                        -Note (Get-TFToolkitText 'Upload de {0}{1}. {2}' "$uploadText" "$(if ($latencyText) { (Get-TFToolkitText ' e latência de {0}' "$latencyText") })" "$(@($meaning | ForEach-Object { $_.Message }) -join ' ')"))
            }
        }
    }
    catch {
        Write-Host ""
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O teste de velocidade falhou: {0}' "$(Get-TFToolkitSpeedProblem -Exception $_.Exception)")
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Verifique a conexão, o DNS, o firewall, a VPN ou um bloqueio do endereço de teste.')
        $problem = Get-TFToolkitSpeedProblem -Exception $_.Exception
        $final = Set-TFToolkitSpeedFailureView -Result (New-TFToolkitResult -Kind Failed -Detail $problem) -Problem $problem
    }

    Exit-TFToolkitAction -Result $final
}


function Set-TFToolkitSpeedFailureView {
    # A faixa do teste que não mediu nada: o motivo e, quando ele não é o proxy que pede autenticação, o botão do teste de
    # conectividade, que diz se a internet responde. Devolve o próprio resultado.
    param (
        [Parameter(Mandatory)]$Result,
        [string]$Problem = ""
    )

    $reason = ([string]$Problem).Trim().TrimEnd('.')
    $headline = (Get-TFToolkitText 'Não foi possível medir a velocidade')

    if (-not $reason) {
        return (Set-TFToolkitResultView -Result $Result -Headline $headline -Note (Get-TFToolkitText 'Verifique a conexão, o DNS, o firewall, a VPN ou um bloqueio do endereço de teste.'))
    }

    $note = "$($reason.Substring(0, 1).ToUpper())$($reason.Substring(1))."

    if ($Problem -eq $script:TFToolkitProxyAuthProblem) {
        return (Set-TFToolkitResultView -Result $Result -Headline $headline -Note $note)
    }

    return (Set-TFToolkitResultView -Result $Result -Headline $headline -Note $note -Next "network.ping" -NextLabel (Get-TFToolkitText 'Testar a conexão'))
}


# ---------------------------------------------------------------------------
# Informações de rede
# ---------------------------------------------------------------------------

function ConvertFrom-TFToolkitWlanInterfaces {
    <#
    As interfaces Wi-Fi conectadas na saída de "netsh wlan show interfaces", em inglês, português ou espanhol. Cada linha
    é "Campo : valor" e uma interface começa no campo Name (Nome, Nombre); o SSID só aparece quando ela está conectada. Os acentos
    podem chegar trocados (página de código do console): por isso "r.{1,3}dio" e os campos comparados pelo começo.
    #>
    param ([string[]]$Lines = @())

    $interfaces = New-Object System.Collections.Generic.List[object]
    $current = $null

    foreach ($line in $Lines) {
        $match = [regex]::Match([string]$line, '^\s+([^:]+?)\s*:\s*(.*)$')
        if (-not $match.Success) { continue }

        $key = $match.Groups[1].Value.Trim()
        $value = $match.Groups[2].Value.Trim()

        if ($key -in @("Name", "Nome", "Nombre")) {
            $current = [ordered]@{ Name = $value; Ssid = ""; Signal = $null; Radio = ""; Band = ""; Channel = "" }
            $interfaces.Add($current)
            continue
        }

        if ($null -eq $current) { continue }

        switch -Regex ($key) {
            '^SSID$' { $current.Ssid = $value }
            '^(Signal|Sinal|Se.{1,3}al)$' { if ($value -match '^([0-9]+)\s*%') { $current.Signal = [int]$Matches[1] } }
            '^(Radio type|Tipo de r.{1,3}dio|Tipo de radio)$' { $current.Radio = $value }
            '^(Band|Banda)$' { $current.Band = $value }
            '^(Channel|Canal)$' { $current.Channel = $value }
        }
    }

    return @($interfaces | Where-Object { $_.Ssid } | ForEach-Object { [PSCustomObject]$_ })
}


function Get-TFToolkitWifiLinkText {
    # "802.11ax (Wi-Fi 6) · 5 GHz, canal 36", com o que o Windows informar (vazio sem nada).
    param ([Parameter(Mandatory)]$Wifi)

    $generation = switch -Regex ([string]$Wifi.Radio) {
        '802\.11be' { "Wi-Fi 7" }
        '802\.11ax' { $(if ([string]$Wifi.Band -match '^6') { (Get-TFToolkitText 'Wi-Fi 6E') } else { "Wi-Fi 6" }) }
        '802\.11ac' { "Wi-Fi 5" }
        '802\.11n' { "Wi-Fi 4" }
        default { "" }
    }

    $parts = @()
    if ($Wifi.Radio) { $parts += $(if ($generation) { "$($Wifi.Radio) ($generation)" } else { [string]$Wifi.Radio }) }

    $band = @(@([string]$Wifi.Band, $(if ($Wifi.Channel) { (Get-TFToolkitText 'canal {0}' "$($Wifi.Channel)") })) | Where-Object { $_ }) -join ", "
    if ($band) { $parts += $band }

    return ($parts -join " · ")
}


function Get-TFToolkitNetworkCategoryText {
    param ([string]$Category)

    switch ($Category) {
        # Com o que o Windows quer dizer com cada um: "pública" numa rede de casa assusta quem não sabe que é o mais seguro.
        "Public" { return (Get-TFToolkitText 'Pública (o PC não aparece para os outros aparelhos da rede)') }
        "Private" { return (Get-TFToolkitText 'Privada (o PC aparece para os outros aparelhos da rede)') }
        "DomainAuthenticated" { return (Get-TFToolkitText 'Domínio (rede da empresa)') }
        default { return "" }
    }
}


function Show-TFToolkitNetworkInfo {
    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Informações de rede')

    # Uma tela de informação não tem faixa; só a de quando não há rede nenhuma (o que fazer, com o botão das configurações).
    $final = $null

    try {
        $activeAdapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq "Up" })

        # A configuração IP pode falhar por uma interface só (uma VPN ou um adaptador virtual sem DNS): os adaptadores, o
        # Wi-Fi e o proxy aparecem mesmo assim, e as seções dizem que o IP não pôde ser lido.
        $ipUnreadable = $false

        try {
            $ipConfigurations = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4Address -or $_.IPv6Address })
        }
        catch {
            $ipConfigurations = @()
            $ipUnreadable = $true
        }

        # Os extras (perfil da rede e detalhes do Wi-Fi) nunca derrubam a tela: sem eles, só não aparecem.
        $profiles = @()
        $wifiList = @()
        $wifiNeedsLocation = $false

        if ($activeAdapters.Count -gt 0) {
            try { $profiles = @(Get-NetConnectionProfile -ErrorAction Stop) } catch { $profiles = @() }

            try {
                $wlan = Invoke-TFToolkitCapture -FilePath "netsh" -Arguments @("wlan", "show", "interfaces")
                $wifiList = @(ConvertFrom-TFToolkitWlanInterfaces -Lines @($wlan.Lines))

                # Nas versões recentes do Windows 11, com a Localização desligada, a consulta não traz nada do Wi-Fi e só pede a
                # permissão (a mensagem cita "ms-settings:privacy-location").
                $wifiNeedsLocation = ($wifiList.Count -eq 0 -and [string]$wlan.Text -match 'privacy-location|WlanQueryInterface')
            }
            catch {
                $wifiList = @()
            }
        }
        else {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Adaptadores')
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Nenhum adaptador ativo encontrado (Wi-Fi desligado, cabo solto ou modo avião).')
            $final = Set-TFToolkitNoNetworkView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o PC não está ligado a nenhuma rede'))
        }

        $shownConfigs = New-Object System.Collections.Generic.List[object]

        # Uma seção por adaptador ativo, com tudo o que é dele junto: a placa, o Wi-Fi, a rede, o IP e o DNS.
        foreach ($adapter in $activeAdapters) {
            $name = [string]$adapter.Name
            Write-TFToolkitSection -Title $name

            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Adaptador') -Value ([string](Get-TFToolkitJsonValue -Object $adapter -Name "InterfaceDescription" -Default "")) -LabelWidth 18
            # O Windows escreve "866.7 Mbps"; no TF-Toolkit, a vírgula decimal ("866,7 Mbps").
            $linkSpeed = ([string](Get-TFToolkitJsonValue -Object $adapter -Name "LinkSpeed" -Default "")) -replace '^([0-9]+)\.([0-9]+)(?= )', '$1,$2'
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Velocidade do link') -Value $linkSpeed -LabelWidth 18
            Write-TFToolkitKeyValue -Label "MAC" -Value ([string](Get-TFToolkitJsonValue -Object $adapter -Name "MacAddress" -Default "")) -LabelWidth 18

            $wifi = @($wifiList | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
            $weak = $false

            if ($null -ne $wifi) {
                $weak = $null -ne $wifi.Signal -and $wifi.Signal -lt 40
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Rede Wi-Fi') -Value $wifi.Ssid -LabelWidth 18
                if ($null -ne $wifi.Signal) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Sinal') -Value "$($wifi.Signal)%" -LabelWidth 18 -Level $(if ($weak) { "Warn" } else { "Normal" }) }
                $link = Get-TFToolkitWifiLinkText -Wifi $wifi
                if ($link) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Conexão Wi-Fi') -Value $link -LabelWidth 18 }
            }

            $netProfile = @($profiles | Where-Object { [string](Get-TFToolkitJsonValue -Object $_ -Name "InterfaceAlias" -Default "") -eq $name }) | Select-Object -First 1

            # Privada (o PC aparece para os outros da rede) ou pública (fica oculto): o que o Windows decidiu ao conectar.
            if ($null -ne $netProfile) {
                $category = Get-TFToolkitNetworkCategoryText -Category ([string](Get-TFToolkitJsonValue -Object $netProfile -Name "NetworkCategory" -Default ""))
                if ($category) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Tipo de rede') -Value $category -LabelWidth 18 }
            }

            $config = @($ipConfigurations | Where-Object { [string]$_.InterfaceAlias -eq $name }) | Select-Object -First 1

            if ($null -ne $config) {
                $shownConfigs.Add($config)
                Write-TFToolkitNetworkConfig -Config $config
            }
            else {
                Write-TFToolkitKeyValue -Label "IP" -Value $(if ($ipUnreadable) { (Get-TFToolkitText 'não foi possível ler') } else { (Get-TFToolkitText 'nenhum endereço') }) -LabelWidth 18
            }

            if ($weak) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O sinal do Wi-Fi está fraco: aproxime o PC do roteador ou use cabo.')
            }
        }

        # Interfaces com IP sem um adaptador ativo na lista (uma VPN, por exemplo) também aparecem.
        foreach ($config in @($ipConfigurations | Where-Object { -not $shownConfigs.Contains($_) })) {
            Write-TFToolkitSection -Title ([string]$config.InterfaceAlias)
            Write-TFToolkitNetworkConfig -Config $config
        }

        if ($ipUnreadable) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows não informou a configuração IP (endereços, gateway e DNS).')
        }

        if ($wifiNeedsLocation) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Para ver a rede Wi-Fi e o sinal, ative a Localização em Configurações, Privacidade e segurança, Localização.')
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Internet')

        $proxy = Get-TFToolkitProxySettings
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Proxy') -Value $(if ($proxy.Text) { $proxy.Text } else { (Get-TFToolkitText 'nenhum') }) -LabelWidth 18

        if ($activeAdapters.Count -eq 0) {
            # Sem adaptador ativo a consulta só esperaria o tempo limite.
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Sem adaptador de rede ativo; a consulta do IP público foi ignorada.')
        }
        else {
            try {
                Enable-TFToolkitTls12
                $publicIp = ([string](Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5)).Trim()

                # Rede com página de login (Wi-Fi de hotel ou de aeroporto) responde com HTML em vez do endereço.
                if (Test-TFToolkitIpAddressText -Text $publicIp) {
                    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'IP público') -Value (Get-TFToolkitText '{0} (consultado em api.ipify.org)' "$publicIp") -LabelWidth 18
                }
                else {
                    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A consulta do IP público devolveu algo que não é um endereço IP (comum em Wi-Fi com página de login, como o de hotel).')
                }
            }
            catch {
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não foi possível consultar o IP público (sem internet ou bloqueio).')
            }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro ao listar informações de rede: {0}' "$($_.Exception.Message)")
        $final = $null
    }

    Exit-TFToolkitAction -Result $final
}


function Test-TFToolkitDnsPlaceholder {
    # Os endereços que o Windows põe como DNS IPv6 quando não há nenhum (fec0:0:0:ffff::1, ::2 e ::3): não respondem a nada.
    param ([string]$Address)

    return ([string]$Address -match '^fec0:0:0:ffff::[1-3](%.*)?$')
}


function Write-TFToolkitNetworkConfig {
    # O IP, o gateway e o DNS de uma interface, nas linhas "Campo : valor" da seção dela.
    param ([Parameter(Mandatory)]$Config)

    $ipv4 = @(Get-TFToolkitJsonValue -Object $Config -Name "IPv4Address" -Default @()) | ForEach-Object { $_.IPAddress }
    $ipv6 = @(Get-TFToolkitJsonValue -Object $Config -Name "IPv6Address" -Default @()) | ForEach-Object { $_.IPAddress }
    $gateway = @(Get-TFToolkitJsonValue -Object $Config -Name "IPv4DefaultGateway" -Default @()) | ForEach-Object { $_.NextHop }

    if (@($ipv4).Count -gt 0) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'IPv4') -Value (@($ipv4) -join ", ") -LabelWidth 18 }
    if (@($ipv6).Count -gt 0) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'IPv6') -Value (@($ipv6) -join ", ") -LabelWidth 18 }
    if (@($gateway).Count -gt 0) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Gateway') -Value (@($gateway) -join ", ") -LabelWidth 18 }

    $index = Get-TFToolkitJsonValue -Object $Config -Name "InterfaceIndex" -Default $null
    if ($null -eq $index) { return }

    # Cada família só com os endereços dela (um IPv4 nunca na linha do IPv6), e o provedor quando é um conhecido ("1.1.1.1,
    # 1.0.0.1 (Cloudflare)"): depois de uma troca pelo TF-Toolkit, a pessoa reconhece o que escolheu.
    foreach ($family in @(@{ Name = "IPv4"; Label = (Get-TFToolkitText 'DNS IPv4') }, @{ Name = "IPv6"; Label = (Get-TFToolkitText 'DNS IPv6') })) {
        $servers = @(
            Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily $family.Name -ErrorAction SilentlyContinue |
            ForEach-Object { $_.ServerAddresses } |
            Where-Object { $_ -and (([string]$_).Contains(":") -eq ($family.Name -eq "IPv6")) -and -not (Test-TFToolkitDnsPlaceholder -Address $_) } |
            Select-Object -Unique
        )

        if ($servers.Count -eq 0) { continue }

        $provider = Get-TFToolkitDnsProviderName -Servers $servers
        Write-TFToolkitKeyValue -Label $family.Label -Value $(if ($provider) { "$($servers -join ', ') ($provider)" } else { $servers -join ", " }) -LabelWidth 18
    }
}


Export-ModuleMember -Function *
