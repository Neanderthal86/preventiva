# ============================================
# NetworkTools.psm1 - Diagnostico de Rede & Acoes Rapidas de Suporte
# ============================================

function Get-PreventivaActiveAdapter {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
        if ($route) {
            return Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue
        }
        return Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    } catch { return $null }
}

function Get-PreventivaNetworkSummary {
    $result = [PSCustomObject]@{
        Adapter  = "Não detectado"
        LocalIP  = "-"
        Gateway  = "-"
        DnsList  = "-"
        Mac      = "-"
        PublicIP = "-"
        Latency  = "-"
    }

    try {
        $nic = Get-PreventivaActiveAdapter
        if ($nic) {
            $result.Adapter = "$($nic.Name) ($($nic.LinkSpeed))"
            $result.Mac     = $nic.MacAddress

            $ipCfg = Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex -ErrorAction SilentlyContinue
            if ($ipCfg) {
                $ipv4 = $ipCfg.IPv4Address | Select-Object -First 1
                if ($ipv4) { $result.LocalIP = $ipv4.IPAddress }
                $gw = $ipCfg.IPv4DefaultGateway | Select-Object -First 1
                if ($gw) { $result.Gateway = $gw.NextHop }
                $dns = ($ipCfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 }).ServerAddresses
                if ($dns) { $result.DnsList = ($dns -join ", ") }
            }
        }
    } catch {}

    try {
        $ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -ErrorAction SilentlyContinue
        if ($ping) { $result.Latency = "$($ping.ResponseTime) ms" }
        else { $result.Latency = "Sem resposta" }
    } catch { $result.Latency = "Erro" }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $pub = $wc.DownloadString("https://api.ipify.org")
        if ($pub) { $result.PublicIP = $pub.Trim() }
        $wc.Dispose()
    } catch { $result.PublicIP = "Indisponível" }

    return $result
}

function Set-PreventivaDns {
    param(
        [ValidateSet("Cloudflare", "Google", "Quad9", "DHCP")]
        [string]$Provider = "Cloudflare"
    )
    $nic = Get-PreventivaActiveAdapter
    if (-not $nic) { throw "Nenhum adaptador de rede ativo encontrado." }

    switch ($Provider) {
        "Cloudflare" { Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses @("1.1.1.1", "1.0.0.1") }
        "Google"     { Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses @("8.8.8.8", "8.8.4.4") }
        "Quad9"      { Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses @("9.9.9.9", "149.112.112.112") }
        "DHCP"       { Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ResetServerAddresses }
    }
    ipconfig /flushdns | Out-Null
    return "DNS alterado para $Provider no adaptador '$($nic.Name)'."
}

function Restart-PreventivaPrintSpooler {
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    $spoolDir = "C:\Windows\System32\spool\PRINTERS"
    $removed = 0
    if (Test-Path -LiteralPath $spoolDir) {
        $items = Get-ChildItem -LiteralPath $spoolDir -Force -ErrorAction SilentlyContinue
        $removed = ($items | Measure-Object).Count
        $items | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
    return "Spooler reiniciado com sucesso ($removed arquivo(s) removido(s) da fila)."
}

function Invoke-PreventivaRenewIp {
    ipconfig /flushdns | Out-Null
    ipconfig /release  | Out-Null
    ipconfig /renew    | Out-Null
    return "Flush DNS + IP renovado (release/renew) com sucesso."
}

Export-ModuleMember -Function Get-PreventivaNetworkSummary, Set-PreventivaDns, Restart-PreventivaPrintSpooler, Invoke-PreventivaRenewIp
