# Relatórios HTML e texto do estado do PC.


# ---------------------------------------------------------------------------
# Seções
# ---------------------------------------------------------------------------

function Get-TFToolkitReportSystemItems {
    $os = Get-TFToolkitCimOrNull -ClassName "Win32_OperatingSystem" | Select-Object -First 1

    $system = Get-TFToolkitCimOrNull -ClassName "Win32_ComputerSystem" | Select-Object -First 1

    @{ Label = (Get-TFToolkitText 'Computador'); Value = $(if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { [Environment]::MachineName } else { $env:COMPUTERNAME }) }
    @{ Label = (Get-TFToolkitText 'Usuário'); Value = $(if ([string]::IsNullOrWhiteSpace($env:USERNAME)) { [Environment]::UserName } else { $env:USERNAME }) }

    # Fabricante e modelo do PC, como em Sobre este PC: é o que um técnico pergunta primeiro (drivers, BIOS, garantia).
    $machine = Get-TFToolkitMachineModelText -System $system

    if ($machine) { @{ Label = (Get-TFToolkitText 'Fabricante e modelo'); Value = $machine } }

    # Numero de serie / Service Tag (essencial para garantia Dell/Lenovo/HP e inventario)
    $serial = ""
    try {
        $bios = Get-TFToolkitCimOrNull -ClassName "Win32_BIOS" | Select-Object -First 1
        if ($bios -and -not [string]::IsNullOrWhiteSpace($bios.SerialNumber)) {
            $s = $bios.SerialNumber.Trim()
            if ($s -notmatch '^(To Be Filled|Default string|System Serial|None|O\.E\.M\.|0+)$') {
                $serial = $s
            }
        }
    } catch {}
    if (-not [string]::IsNullOrWhiteSpace($serial)) {
        @{ Label = (Get-TFToolkitText 'Nº de Série / Service Tag'); Value = $serial }
    }

    if ($os) {
        # O mesmo texto do cartão Windows da tela inicial: "Windows 11 Pro 24H2 (build 26100)".
        $build = [int](Get-TFToolkitJsonValue -Object $os -Name "BuildNumber" -Default 0)
        $windows = Get-TFToolkitWindowsName -Caption ([string](Get-TFToolkitJsonValue -Object $os -Name "Caption" -Default "")) -Build $build
        $version = Get-TFToolkitWindowsDisplayVersion

        if ($version) { $windows += " $version" }
        if ($build -gt 0) { $windows += (Get-TFToolkitText ' (build {0})' "$build") }

        @{ Label = (Get-TFToolkitText 'Sistema operacional'); Value = $windows.Trim() }
        @{ Label = (Get-TFToolkitText 'Tempo ligado'); Value = (Get-TFToolkitUptimeText -LastBootTime $os.LastBootUpTime) }
    }
    else {
        @{ Label = (Get-TFToolkitText 'Sistema operacional'); Value = (Get-TFToolkitText 'Não foi possível ler') }
    }

    # O veredito da tela Suporte do Windows: num laudo, "este Windows ainda recebe correções?" é a primeira pergunta.
    try {
        $support = Get-TFToolkitWindowsSupportStatus
        @{ Label = (Get-TFToolkitText 'Suporte do Windows'); Value = $(if ($support.Text) { [string]$support.Text } else { (Get-TFToolkitText 'Não foi possível conferir') }) }
    }
    catch {
        @{ Label = (Get-TFToolkitText 'Suporte do Windows'); Value = (Get-TFToolkitText 'Não foi possível conferir') }
    }

    # A ativação, como em Sobre este PC: é a pergunta seguinte de quem recebe o laudo.
    @{ Label = (Get-TFToolkitText 'Ativação do Windows'); Value = (Get-TFToolkitWindowsActivationText -State (Get-TFToolkitWindowsActivation)) }

    # O mesmo veredito das telas: só os sinais fortes dizem "sim". Os fracos (arquivos esperando substituição) aparecem
    # em muitos PCs sem que o reinício seja necessário, e sozinhos não viram motivo.
    $pending = @(Get-TFToolkitPendingReboot)
    $strong = @($pending | Where-Object { $_.Strong })
    $rebootText = $(
        if ($strong.Count -gt 0) { ($strong | ForEach-Object { $_.Reason }) -join "; " }
        elseif ($pending.Count -gt 0) { (Get-TFToolkitText 'Não (só sinais que aparecem em quase todo PC; reiniciar não é obrigatório)') }
        else { (Get-TFToolkitText 'Não') }
    )
    @{ Label = (Get-TFToolkitText 'Reinício pendente'); Value = $rebootText }
}


function Get-TFToolkitReportHardwareItems {
    $items = @()
    $cpu = Get-TFToolkitCimOrNull -ClassName "Win32_Processor" | Select-Object -First 1
    $memory = @(Get-TFToolkitCimOrNull -ClassName "Win32_PhysicalMemory")
    $board = Get-TFToolkitCimOrNull -ClassName "Win32_BaseBoard" | Select-Object -First 1
    $bios = Get-TFToolkitCimOrNull -ClassName "Win32_BIOS" | Select-Object -First 1

    if ($cpu) {
        $items += @{ Label = (Get-TFToolkitText 'Processador'); Value = ([string]$cpu.Name).Trim() }
    }

    if ($memory.Count -gt 0) {
        $totalRam = Format-TFToolkitBytes -Bytes (($memory | Measure-Object -Property Capacity -Sum).Sum) -ZeroText "?"
        $memoryType = Convert-TFToolkitMemoryType -Type ([int]($memory | Select-Object -First 1).SMBIOSMemoryType)
        $modules = Get-TFToolkitMemoryModulesText -Modules $memory
        $items += @{ Label = (Get-TFToolkitText 'Memória'); Value = "$totalRam $memoryType$(if ($modules) { " ($modules)" })" }
    }

    if ($board) {
        $items += @{ Label = (Get-TFToolkitText 'Placa-mãe'); Value = "$($board.Manufacturer) $($board.Product)".Trim() }
    }

    if ($bios) {
        $items += @{ Label = "BIOS"; Value = $bios.SMBIOSBIOSVersion }
    }

    foreach ($gpu in @(Get-TFToolkitCimOrNull -ClassName "Win32_VideoController" | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) -and $_.Name -notmatch "Microsoft Basic|Remote|Parsec" })) {
        $items += @{ Label = (Get-TFToolkitText 'Vídeo'); Value = ([string]$gpu.Name).Trim() }
    }

    if ($items.Count -eq 0) {
        $items += @{ Label = (Get-TFToolkitText 'Hardware'); Value = (Get-TFToolkitText 'Não foi possível ler') }
    }

    return $items
}


function Get-TFToolkitReportDiskItems {
    $items = @()

    # As mesmas frases das telas Discos e espaço livre e Saúde dos discos. Uma leitura vazia vira uma linha que diz isso:
    # sem ela, o relatório parecia de um PC sem disco.
    $summary = @(Get-TFToolkitDiskSummary)
    $healthList = @(Get-TFToolkitDiskHealth)

    if ($summary.Count -eq 0) { $items += @{ Label = (Get-TFToolkitText 'Unidades'); Value = (Get-TFToolkitText 'Não foi possível ler') } }

    foreach ($disk in $summary) {
        $items += @{ Label = $disk.Unidade; Value = (Get-TFToolkitDiskSummaryText -Disk $disk) }
    }

    if ($healthList.Count -eq 0) { $items += @{ Label = (Get-TFToolkitText 'Saúde dos discos'); Value = (Get-TFToolkitText 'Não foi possível ler (em alguns PCs, requer Administrador)') } }

    foreach ($health in $healthList) {
        $status = Get-TFToolkitDiskHealthStatusText -Status $health.HealthStatus
        if ($status -eq (Get-TFToolkitText 'Desconhecido')) { $status = (Get-TFToolkitText 'Estado desconhecido') }

        $text = if ($health.Notes.Count -gt 0) { (Get-TFToolkitText '{0}. Alertas: {1}' "$status" "$($health.Notes -join '; ')") }
        elseif ($health.CountersAvailable) { (Get-TFToolkitText '{0}, sem alertas' "$status") }
        elseif ([bool](Get-TFToolkitJsonValue -Object $health -Name "CountersTimedOut" -Default $false)) { (Get-TFToolkitText '{0}; os contadores não vieram (o Windows não respondeu a tempo)' "$status") }
        else { (Get-TFToolkitText '{0}, sem contadores de confiabilidade' "$status") }
        $drives = @(Get-TFToolkitJsonValue -Object $health -Name "Drives" -Default @())
        $items += @{ Label = (Get-TFToolkitText 'Saúde: {0}{1}' "$($health.Name)" "$(if ($drives.Count -gt 0) { " ($($drives -join ', '))" })"); Value = $text }
    }

    return $items
}


function Get-TFToolkitReportTweakItems {
    $items = @()

    foreach ($tweak in @(Get-TFToolkitTweakOverview)) {
        # Como na janela: o recurso do Windows e se ele está ativado ou desativado agora.
        $items += @{ Label = $tweak.Name; Value = (Get-TFToolkitTweakSwitchState -Status $tweak.Status -Inverted ([bool]$tweak.Inverted)).Caption }
    }

    return $items
}


function Get-TFToolkitReportEventItems {
    $items = @()
    $summary = @(ConvertTo-TFToolkitEventSummary -Events @(Get-TFToolkitRecentCriticalEvents -Days 7) -Top 10)

    if ($summary.Count -eq 0) {
        $items += @{ Label = (Get-TFToolkitText 'Últimos 7 dias'); Value = (Get-TFToolkitText 'Nenhum evento crítico ou de erro') }
    }

    foreach ($entry in $summary) {
        $value = Format-TFToolkitEventOccurrences -Entry $entry
        if ($entry.Hint) { $value += " - $($entry.Hint)" }
        $items += @{ Label = (Get-TFToolkitText '{0} (ID {1})' "$(Get-TFToolkitEventProviderText -Provider $entry.Provider)" "$($entry.Id)"); Value = $value }
    }

    return $items
}


function Get-TFToolkitReportStabilityItems {
    # As telas azuis dos últimos 90 dias e o último teste de memória, como em Diagnóstico > Telas azuis e Teste de memória.
    $items = @()
    $label = (Get-TFToolkitText 'Telas azuis (90 dias)')

    try {
        $screens = @(Get-TFToolkitBlueScreens -Days 90)

        if ($screens.Count -eq 0) {
            $items += @{ Label = $label; Value = (Get-TFToolkitText 'Nenhuma') }
        }
        else {
            $about = Get-TFToolkitBugCheckCauseText -Cause (Get-TFToolkitBlueScreenMainCause -Screens $screens).Cause
            $latest = $screens[0]
            $code = "0x{0:X8}" -f [uint32]$latest.Code
            $count = Format-TFToolkitCount -Count $screens.Count -One (Get-TFToolkitText 'tela azul') -Many (Get-TFToolkitText 'telas azuis')

            $items += @{ Label = $label; Value = (Get-TFToolkitText '{0}; causa mais provável: {1}' "$count" "$($about.Cause)") }
            $items += @{ Label = (Get-TFToolkitText 'A mais recente'); Value = (Get-TFToolkitText '{0} ({1})' "$(Format-TFToolkitDateTime -When $latest.When)" "$(if ($latest.Info.Name) { "$code $($latest.Info.Name)" } else { $code })") }
        }
    }
    catch {
        $items += @{ Label = $label; Value = (Get-TFToolkitText 'Não foi possível ler') }
    }

    try {
        $memory = Get-TFToolkitMemoryTestResult
        $value = $(if ($null -eq $memory) { (Get-TFToolkitText 'nenhum no último ano') }
            elseif ($memory.Errors) { (Get-TFToolkitText '{0}: {1}' "$(Format-TFToolkitDateTime -When $memory.When)" "$(Get-TFToolkitText 'encontrou erros na memória')") }
            else { (Get-TFToolkitText '{0}: {1}' "$(Format-TFToolkitDateTime -When $memory.When)" "$(Get-TFToolkitText 'nenhum erro')") })

        $items += @{ Label = (Get-TFToolkitText 'Último teste de memória'); Value = $value }
    }
    catch {
        Write-Verbose "Teste de memória: $($_.Exception.Message)"
    }

    return $items
}


function Get-TFToolkitReportBatteryItems {
    $items = @()
    $info = Get-TFToolkitBatteryInfo

    if (-not $info.Present) {
        return @(@{ Label = (Get-TFToolkitText 'Bateria'); Value = (Get-TFToolkitText 'Nenhuma bateria encontrada') })
    }

    $now = @()
    if ($null -ne $info.State.ChargePercent) { $now += "$($info.State.ChargePercent)%" }
    if ($info.State.State) { $now += $info.State.State }
    if ($now.Count -gt 0) { $items += @{ Label = (Get-TFToolkitText 'Agora'); Value = ($now -join ", ") } }

    foreach ($reading in @($info.Readings)) {
        $label = $(if ($reading.Name) { $reading.Name } else { (Get-TFToolkitText 'Bateria') })
        $assessment = Get-TFToolkitBatteryAssessment -HealthPercent $reading.HealthPercent -Missing $(if ($null -ne $reading.DesignMwh -and $null -eq $reading.FullMwh) { "full" } else { "design" })

        $capacity = @()
        if ($null -ne $reading.FullMwh -and $null -ne $reading.DesignMwh -and -not [bool](Get-TFToolkitJsonValue -Object $reading -Name "Relative" -Default $false)) {
            $capacity += (Get-TFToolkitText '{0} de {1} de fábrica' "$(Format-TFToolkitWattHours -MilliwattHours $reading.FullMwh)" "$(Format-TFToolkitWattHours -MilliwattHours $reading.DesignMwh)")
        }
        if ($null -ne $reading.Cycles) { $capacity += (Format-TFToolkitCount -Count ([int]$reading.Cycles) -One (Get-TFToolkitText 'ciclo') -Many (Get-TFToolkitText 'ciclos')) }

        $parts = @($assessment.Text) + @($capacity)
        $items += @{ Label = $label; Value = ($parts -join " | ") }
    }

    if (@($info.Readings).Count -eq 0) {
        $items += @{ Label = (Get-TFToolkitText 'Capacidade'); Value = (Get-TFToolkitText 'O Windows não informou a capacidade da bateria') }
    }

    return $items
}


function Get-TFToolkitReportSecurityItems {
    # Sem a consulta ao Windows Update (a tela a faz à parte): ela vai até o serviço e deixaria o relatório lento.
    $status = Get-TFToolkitSecurityStatus
    $antivirus = $status.Antivirus
    $items = @()

    # As mesmas linhas da tela Estado da proteção (sem a última verificação completa); "Situação" vira "Antivírus".
    foreach ($row in @(Get-TFToolkitAntivirusRows -Antivirus $antivirus -Threats $status.Threats -Brief)) {
        $items += @{ Label = $(if ($row.Label -eq (Get-TFToolkitText 'Situação')) { (Get-TFToolkitText 'Antivírus') } else { $row.Label }); Value = $row.Value }
    }

    if ($null -eq $status.Firewall) {
        $items += @{ Label = (Get-TFToolkitText 'Firewall'); Value = (Get-TFToolkitText 'Não foi possível ler') }
    }
    else {
        $items += @{ Label = (Get-TFToolkitText 'Firewall'); Value = ((@($status.Firewall) | ForEach-Object { $product = [string](Get-TFToolkitJsonValue -Object $_ -Name "Product" -Default ""); "$(Get-TFToolkitFirewallProfileName -Name $_.Name): $(if ($product) { (Get-TFToolkitText 'protegido por {0}' "$product") } elseif ($_.Enabled) { (Get-TFToolkitText 'ligado') } elseif (-not [bool](Get-TFToolkitJsonValue -Object $_ -Name 'Applies' -Default $true)) { (Get-TFToolkitText 'desligado (não vale para este PC, que não está num domínio)') } else { (Get-TFToolkitText 'desligado') })" }) -join "; ") }
    }

    foreach ($finding in @($status.Findings | Where-Object { $_.Level -eq "Warning" })) {
        $items += @{ Label = (Get-TFToolkitText 'Atenção'); Value = $finding.Text }
    }

    return $items
}


function Get-TFToolkitReportMaintenanceItems {
    param (
        [Parameter(Mandatory)]
        $Maintenance
    )

    $items = @()

    foreach ($result in @($Maintenance.Results)) {
        $value = [string]$result.Status
        if ($result.PSObject.Properties.Name -contains "Duracao" -and $result.Duracao) { $value += " ($($result.Duracao))" }
        $items += @{ Label = $result.Etapa; Value = $value }
    }

    # Antes e depois (manutenções gravadas por versões antigas não têm as fotos).
    $before = $(if ($null -ne $Maintenance.PSObject.Properties["Before"]) { $Maintenance.Before } else { $null })
    $after = $(if ($null -ne $Maintenance.PSObject.Properties["After"]) { $Maintenance.After } else { $null })

    foreach ($row in @(Get-TFToolkitSnapshotComparison -Before $before -After $after)) {
        $items += @{ Label = $row.Label; Value = $row.Text }
    }

    if ($null -ne $after -and $null -ne $Maintenance.PSObject.Properties["StartedAt"]) {
        $span = $after.At - $Maintenance.StartedAt

        if ($span.Ticks -gt 0) {
            $items += @{ Label = (Get-TFToolkitText 'Duração'); Value = (Get-TFToolkitText '{0} (das {1} às {2})' "$(Format-TFToolkitDuration -Span $span)" "$(Format-TFToolkitDateTime -When $Maintenance.StartedAt -Pattern 'HH:mm')" "$(Format-TFToolkitDateTime -When $after.At -Pattern 'HH:mm')") }
        }
    }

    return $items
}


function New-TFToolkitReportSection {
    # Uma seção que falha vira uma linha de aviso: o resto do relatório continua sendo gerado e salvo.
    param (
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [scriptblock]$Build
    )

    try {
        $items = @(& $Build)
    }
    catch {
        $items = @(@{ Label = (Get-TFToolkitText 'Não foi possível ler esta seção'); Value = $_.Exception.Message })
    }

    return @{ Title = $Title; Items = $items }
}


function Get-TFToolkitReportAttentionItems {
    # O resumo do que pede atenção, no topo do relatório: a nota de saúde do Início e os pontos que descontam dela, para
    # quem vai ajudar ver o problema antes de ler as seções técnicas.
    $status = Get-TFToolkitHomeStatus
    $health = $status.Health
    $items = @()

    if (Test-TFToolkitHealthKnown -Health $health) {
        $items += @{ Label = (Get-TFToolkitText 'Saúde do PC'); Value = (Get-TFToolkitText '{0} de 100 ({1})' "$($health.Score)" "$($health.Label)") }
    }
    else {
        $items += @{ Label = (Get-TFToolkitText 'Saúde do PC'); Value = (Get-TFToolkitText 'Não foi possível avaliar') }
    }

    $issues = @($health.Issues | Where-Object { $null -ne $_ })

    foreach ($issue in $issues) {
        $items += @{ Label = $(if ($issue.Severe) { (Get-TFToolkitText 'Grave') } else { (Get-TFToolkitText 'Atenção') }); Value = [string]$issue.Text }
    }

    if ($issues.Count -eq 0) {
        $items += @{ Label = (Get-TFToolkitText 'Pontos de atenção'); Value = (Get-TFToolkitText 'Nenhum') }
    }

    $unread = @(Get-TFToolkitJsonValue -Object $health -Name "Unread" -Default @())

    if ($unread.Count -gt 0) {
        $items += @{ Label = (Get-TFToolkitText 'Não foi possível ler'); Value = ($unread -join ", ") }
    }

    foreach ($notice in @($status.Notices | Where-Object { $null -ne $_ })) {
        $items += @{ Label = (Get-TFToolkitText 'Aviso'); Value = [string]$notice.Text }
    }

    return $items
}


function Get-TFToolkitReportSections {
    $sections = @()

    $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Pontos de atenção') -Build { Get-TFToolkitReportAttentionItems }
    $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Sistema') -Build { Get-TFToolkitReportSystemItems }
    $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Hardware') -Build { Get-TFToolkitReportHardwareItems }
    $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Discos') -Build { Get-TFToolkitReportDiskItems }
    $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Ajustes do Windows e Personalização') -Build { Get-TFToolkitReportTweakItems }
    $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Eventos críticos (7 dias)') -Build { Get-TFToolkitReportEventItems }
    $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Telas azuis e memória') -Build { Get-TFToolkitReportStabilityItems }

    $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Segurança') -Build { Get-TFToolkitReportSecurityItems }

    if (Test-TFToolkitLaptop) {
        $sections += New-TFToolkitReportSection -Title (Get-TFToolkitText 'Bateria') -Build { Get-TFToolkitReportBatteryItems }
    }

    $maintenance = Get-TFToolkitLastMaintenance

    if ($null -ne $maintenance) {
        $title = (Get-TFToolkitText 'Última manutenção')

        try { $title += " ($(Format-TFToolkitDateTime -When $maintenance.StartedAt))" } catch { }

        $sections += New-TFToolkitReportSection -Title $title -Build { Get-TFToolkitReportMaintenanceItems -Maintenance $maintenance }
    }

    return @($sections)
}


# ---------------------------------------------------------------------------
# Formatos
# ---------------------------------------------------------------------------

function ConvertTo-TFToolkitTextReport {
    param (
        [Parameter(Mandatory)]
        [object[]]$Sections,

        [string]$Build = ""
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine((Get-TFToolkitText 'TF-Toolkit - Relatório (versão {0})' "$Build"))
    [void]$builder.AppendLine((Get-TFToolkitText 'Gerado em {0}' "$(Format-TFToolkitDateTime -When (Get-Date))"))

    foreach ($section in $Sections) {
        [void]$builder.AppendLine("")
        [void]$builder.AppendLine($section.Title)
        [void]$builder.AppendLine(("-" * $section.Title.Length))

        foreach ($item in $section.Items) {
            [void]$builder.AppendLine(("{0,-34} {1}" -f $item.Label, $item.Value))
        }
    }

    return $builder.ToString()
}


function ConvertTo-TFToolkitHtmlReport {
    param (
        [Parameter(Mandatory)]
        [object[]]$Sections,

        [string]$Build = ""
    )

    $encode = { param($text) [System.Net.WebUtility]::HtmlEncode([string]$text) }
    $builder = New-Object System.Text.StringBuilder

    # O idioma da página é o da interface (o leitor de tela e o tradutor do navegador usam o atributo lang).
    $htmlLanguage = switch (Get-TFToolkitLanguage) { "en" { "en" } "es" { "es" } default { "pt-BR" } }
    [void]$builder.AppendLine("<!doctype html><html lang=`"$htmlLanguage`"><head><meta charset=`"utf-8`">")
    [void]$builder.AppendLine("<meta name=`"viewport`" content=`"width=device-width, initial-scale=1`">")
    [void]$builder.AppendLine("<title>$(& $encode (Get-TFToolkitText 'TF-Toolkit - Relatório'))</title><style>")
    [void]$builder.AppendLine(":root{--bg:#f6f8fa;--card:#fff;--text:#1f2328;--muted:#656d76;--line:#d8dee4;--accent:#0969da}")
    [void]$builder.AppendLine("@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--card:#161b22;--text:#e6edf3;--muted:#8b949e;--line:#30363d;--accent:#58a6ff}}")
    [void]$builder.AppendLine("body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 Segoe UI,system-ui,sans-serif}")
    [void]$builder.AppendLine("main{max-width:860px;margin:0 auto;padding:24px 16px}h1{margin:0 0 4px;font-size:24px}")
    [void]$builder.AppendLine(".meta{color:var(--muted);margin-bottom:20px}section{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 18px;margin-bottom:14px}")
    [void]$builder.AppendLine("h2{margin:0 0 8px;font-size:16px;color:var(--accent)}dl{display:grid;grid-template-columns:minmax(140px,30%) 1fr;gap:4px 14px;margin:0}")
    [void]$builder.AppendLine("dt{color:var(--muted)}dd{margin:0;overflow-wrap:anywhere}@media (max-width:560px){dl{grid-template-columns:1fr}}")
    [void]$builder.AppendLine("</style></head><body><main>")
    [void]$builder.AppendLine("<h1>TF-Toolkit</h1><div class=`"meta`">$(& $encode (Get-TFToolkitText 'Relatório gerado em {0} · versão {1}' "$(Format-TFToolkitDateTime -When (Get-Date))" "$Build"))</div>")

    foreach ($section in $Sections) {
        [void]$builder.AppendLine("<section><h2>$(& $encode $section.Title)</h2><dl>")

        foreach ($item in $section.Items) {
            [void]$builder.AppendLine("<dt>$(& $encode $item.Label)</dt><dd>$(& $encode $item.Value)</dd>")
        }

        [void]$builder.AppendLine("</dl></section>")
    }

    [void]$builder.AppendLine("</main></body></html>")
    return $builder.ToString()
}


# ---------------------------------------------------------------------------
# Ações
# ---------------------------------------------------------------------------

function Export-TFToolkitReport {
    param (
        [string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $Directory = Join-Path (Get-TFToolkitDataPath) "reports"
    }

    # Um erro de disco aqui (pasta que não pode ser criada, sem permissão, disco cheio) interrompe a exportação: sem o
    # -ErrorAction Stop o Set-Content só escreveria o erro e quem chama diria "relatório salvo" sobre arquivos que não existem.
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        try {
            [void](New-Item -Path $Directory -ItemType Directory -Force -ErrorAction Stop)
        }
        catch {
            throw (Get-TFToolkitText 'não foi possível criar a pasta dos relatórios ({0}): {1}' "$Directory" "$($_.Exception.Message.TrimEnd('.'))")
        }
    }

    $sections = @(Get-TFToolkitReportSections)
    $build = Get-TFToolkitBuild

    # O nome vem do horário de quando a coleta terminou; dois relatórios no mesmo segundo (o segundo clique enquanto o
    # primeiro salvava, ou o agendamento) ganham "-2", "-3": sem isso, um apagaria o outro.
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $base = "tf-toolkit-relatorio-$stamp"
    $suffix = 1

    while ((Test-Path -LiteralPath (Join-Path $Directory "$base.html")) -or (Test-Path -LiteralPath (Join-Path $Directory "$base.txt"))) {
        $suffix++
        $base = "tf-toolkit-relatorio-$stamp-$suffix"
    }

    $htmlPath = Join-Path $Directory "$base.html"
    $textPath = Join-Path $Directory "$base.txt"

    try {
        Set-Content -LiteralPath $htmlPath -Value (ConvertTo-TFToolkitHtmlReport -Sections $sections -Build $build) -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        throw (Get-TFToolkitText 'não foi possível gravar o relatório em {0}: {1}' "${Directory}" "$($_.Exception.Message.TrimEnd('.'))")
    }

    # O HTML é o relatório; o texto é a cópia para colar num e-mail. Se só ele falhar, o HTML salvo continua valendo.
    $textProblem = ""

    try {
        Set-Content -LiteralPath $textPath -Value (ConvertTo-TFToolkitTextReport -Sections $sections -Build $build) -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        $textProblem = $_.Exception.Message.TrimEnd(".")
        $textPath = $null
    }

    return [PSCustomObject]@{ Html = $htmlPath; Text = $textPath; TextProblem = $textProblem }
}


function Open-TFToolkitSavedReport {
    <#
    Pergunta o que fazer com um relatório que acabou de ser salvo (abrir, mostrar na pasta ou nada) e faz. Devolve "" ou,
    quando o Windows recusou, o que não foi possível com o motivo ("abrir o relatório: ..."); a mensagem já apareceu.
    #>
    param ([Parameter(Mandatory)][string]$Path)

    $next = Read-TFToolkitChoice -Message (Get-TFToolkitText 'O que deseja fazer com o relatório?') -DefaultKey "A" -ShowMenu -TextPrompt (Get-TFToolkitText 'Opção (ENTER = abrir)') -Options @(
        @{ Key = "A"; Label = (Get-TFToolkitText 'Abrir o relatório'); Accent = $true },
        @{ Key = "P"; Label = (Get-TFToolkitText 'Mostrar na pasta') },
        @{ Key = "X"; Label = (Get-TFToolkitText 'Agora não'); Exit = $true }
    )

    if ($next -notin @("A", "P")) { return "" }

    try {
        # Pelo Explorer, e não direto: com o TF-Toolkit como Administrador, o navegador abriria elevado também. O
        # Explorer já está aberto na sessão da pessoa e abre o arquivo no navegador padrão, sem privilégios.
        $arguments = $(if ($next -eq "P") { "/select,`"$Path`"" } else { "`"$Path`"" })
        Start-Process -FilePath "explorer.exe" -ArgumentList $arguments -ErrorAction Stop
    }
    catch {
        $what = $(if ($next -eq "P") { (Get-TFToolkitText 'mostrar a pasta') } else { (Get-TFToolkitText 'abrir o relatório') })
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não foi possível {0}: {1}' "${what}" "$($_.Exception.Message)")
        return "${what}: $($_.Exception.Message)"
    }

    return ""
}


function Invoke-TFToolkitReport {
    $title = (Get-TFToolkitText 'Exportar relatório')
    Enter-TFToolkitAction -Title $title

    $result = $null

    try {
        # O andamento vai na barra: uma linha "Coletando..." ficaria no resumo depois do fim.
        Write-Progress -Activity $title -Status (Get-TFToolkitText 'coletando sistema, discos, eventos e segurança')

        try {
            $report = Export-TFToolkitReport
        }
        finally {
            Write-Progress -Activity $title -Completed
        }

        $textProblem = [string](Get-TFToolkitJsonValue -Object $report -Name "TextProblem" -Default "")

        Write-Host ""

        if ($textProblem) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Relatório HTML salvo; a cópia em texto não pôde ser gravada: {0}.' "${textProblem}")
            Write-TFToolkitKeyValue -Label "HTML" -Value $report.Html
            $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'relatório salvo em HTML; a cópia em texto não pôde ser gravada')
        }
        else {
            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Relatório salvo.')
            Write-TFToolkitKeyValue -Label "HTML" -Value $report.Html
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Texto') -Value $report.Text
            $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'relatório salvo em HTML e em texto')
        }

        Write-Host ""
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O relatório traz o nome do PC e do usuário, o hardware e a segurança: confira antes de enviar a alguém.')

        $problem = Open-TFToolkitSavedReport -Path $report.Html

        if ($problem) {
            $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'relatório salvo, mas não foi possível {0}' "$problem")
        }
    }
    catch {
        Write-Host ""
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O relatório não foi salvo: {0}.' "$($_.Exception.Message.TrimEnd('.'))")
        $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o relatório não foi salvo')
    }

    Exit-TFToolkitAction -Result $result
}


# ---------------------------------------------------------------------------
# Relatorio Completo em PDF (para envio ao Analista)
# ---------------------------------------------------------------------------

function Get-TFToolkitReportNetworkItems {
    $items = @()
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
        $nic = if ($route) { Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue } else { Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1 }
        if ($nic) {
            $items += [PSCustomObject]@{ Label = "Adaptador ativo"; Value = "$($nic.Name) ($($nic.InterfaceDescription)) · $($nic.LinkSpeed)" }
            $items += [PSCustomObject]@{ Label = "Endereço MAC"; Value = "$($nic.MacAddress)" }
            $ipCfg = Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex -ErrorAction SilentlyContinue
            if ($ipCfg) {
                $ipv4 = $ipCfg.IPv4Address | Select-Object -First 1
                if ($ipv4) { $items += [PSCustomObject]@{ Label = "IP Local (IPv4)"; Value = "$($ipv4.IPAddress)/$($ipv4.PrefixLength)" } }
                $gw = $ipCfg.IPv4DefaultGateway | Select-Object -First 1
                if ($gw) { $items += [PSCustomObject]@{ Label = "Gateway padrão"; Value = "$($gw.NextHop)" } }
                $dns = ($ipCfg.DNSServer | Where-Object { $_.AddressFamily -eq 2 }).ServerAddresses
                if ($dns) { $items += [PSCustomObject]@{ Label = "Servidores DNS"; Value = ($dns -join ", ") } }
            }
            try {
                $wlan = (& netsh wlan show interfaces 2>$null) -join "`n"
                if ($wlan -match '(?m)^\s*SSID\s*:\s*(.+)$') {
                    $ssid = $Matches[1].Trim()
                    if (-not [string]::IsNullOrWhiteSpace($ssid)) {
                        $items += [PSCustomObject]@{ Label = "Rede Wi-Fi (SSID)"; Value = $ssid }
                    }
                }
            } catch {}
        }
    } catch {}

    try {
        $ping = Test-Connection -ComputerName 8.8.8.8 -Count 2 -ErrorAction SilentlyContinue
        if ($ping) {
            $avg = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)
            $items += [PSCustomObject]@{ Label = "Conectividade (8.8.8.8)"; Value = "OK · latência média $avg ms" }
        } else {
            $items += [PSCustomObject]@{ Label = "Conectividade (8.8.8.8)"; Value = "Sem resposta" }
        }
    } catch {}

    if ($items.Count -eq 0) {
        $items += [PSCustomObject]@{ Label = "Rede"; Value = "Informações de rede indisponíveis" }
    }
    return $items
}


function Get-TFToolkitReportDriversAndStartupItems {
    $items = @()
    try {
        $bad = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -notin @("OK", "Unknown") })
        if ($bad.Count -eq 0) {
            $items += [PSCustomObject]@{ Label = "Dispositivos / Drivers"; Value = "Nenhum dispositivo com erro encontrado" }
        } else {
            $items += [PSCustomObject]@{ Label = "Dispositivos com erro"; Value = "$($bad.Count) encontrado(s)" }
            foreach ($d in ($bad | Select-Object -First 8)) {
                $items += [PSCustomObject]@{ Label = "Driver ($($d.Status))"; Value = "$($d.FriendlyName)" }
            }
        }
    } catch {}

    try {
        $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
        $items += [PSCustomObject]@{ Label = "Itens na inicialização"; Value = "$($startup.Count) registro(s)" }
        $names = @($startup | Select-Object -ExpandProperty Name -Unique | Sort-Object | Select-Object -First 12)
        if ($names.Count -gt 0) {
            $items += [PSCustomObject]@{ Label = "Principais itens"; Value = ($names -join ", ") }
        }
    } catch {}

    return $items
}


function Get-TFToolkitReportInstalledAppsItems {
    $items = @()
    try {
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $apps = @(Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.DisplayName) -and -not $_.SystemComponent } |
            Sort-Object DisplayName -Unique)

        $items += [PSCustomObject]@{ Label = "Total de programas"; Value = "$($apps.Count) instalado(s)" }
        foreach ($a in $apps) {
            $ver = if ($a.DisplayVersion) { "v$($a.DisplayVersion)" } else { "-" }
            $pub = if ($a.Publisher) { " · $($a.Publisher)" } else { "" }
            $items += [PSCustomObject]@{ Label = "$($a.DisplayName)"; Value = "$ver$pub" }
        }
    } catch {}

    return $items
}


function Find-TFToolkitPdfBrowser {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Leaf)) {
            return $c
        }
    }
    return $null
}


function ConvertTo-TFToolkitAnalystHtmlReport {
    param (
        [Parameter(Mandatory)][object[]]$Sections,
        [string]$Build = "4.0",
        [int]$HealthScore = -1,
        [string]$HealthLabel = ""
    )

    $encode = { param($text) [System.Net.WebUtility]::HtmlEncode([string]$text) }
    $logoDataUri = ""
    $logoHtml = "<div class='brand-badge'>TF</div>"
    try {
        $logoFile = Join-Path (Split-Path -Parent $PSScriptRoot) "assets\logo.png"
        if (Test-Path -LiteralPath $logoFile -PathType Leaf) {
            $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($logoFile))
            $logoDataUri = "data:image/png;base64,$b64"
            $logoHtml = "<div class='logo-wrap'><img class='brand-logo' src='$logoDataUri' alt='Tech Fontes'/></div>"
        }
    } catch {}

    $nowDate = Get-Date -Format "dd/MM/yyyy"
    $nowText = Get-Date -Format "dd/MM/yyyy 'às' HH:mm"
    $protocolId = "TF-" + (Get-Date -Format "yyyyMMdd-HHmm")
    $hostName = & $encode $env:COMPUTERNAME
    $userName = & $encode $env:USERNAME

    # Reordenar secoes por prioridade de analise tecnica (Anexos extensos no final)
    $priorityOrder = @(
        'Pontos de aten',
        'Sistema',
        'Hardware',
        'Discos',
        'Seguran',
        'Bateria',
        'Rede',
        'Eventos cr',
        'Telas azuis',
        'Drivers',
        'Programas',
        'Ajustes'
    )
    $orderedSections = New-Object System.Collections.Generic.List[object]
    $usedIdx = @{}
    foreach ($pat in $priorityOrder) {
        for ($i = 0; $i -lt $Sections.Count; $i++) {
            if ($usedIdx.ContainsKey($i)) { continue }
            if ([string]$Sections[$i].Title -match $pat) {
                $orderedSections.Add($Sections[$i])
                $usedIdx[$i] = $true
            }
        }
    }
    for ($i = 0; $i -lt $Sections.Count; $i++) {
        if (-not $usedIdx.ContainsKey($i)) { $orderedSections.Add($Sections[$i]) }
    }

    # Extrair destaques para os cards executivos (KPIs) e Recomendacoes Automaticas
    $kpiModel = $env:COMPUTERNAME
    $kpiSerial = ""
    $kpiOs = "Windows"
    $kpiOsSub = ""
    $kpiCpu = "-"
    $kpiRam = ""
    $kpiDiskText = "-"
    $kpiDiskPct = -1
    $kpiSecText = "Verificado"
    $kpiSecSub = ""
    $kpiSecTone = "ok"

    $recs = New-Object System.Collections.Generic.List[object]
    $hasUnexpectedShutdown = $false
    $hasWuErrors = $false
    $hasServiceErrors = $false

    foreach ($sec in $orderedSections) {
        $t = [string]$sec.Title
        foreach ($it in @($sec.Items)) {
            $lbl = [string]$it.Label
            $val = [string]$it.Value
            if ($t -match 'Sistema') {
                if ($lbl -match 'Fabricante') { $kpiModel = $val }
                elseif ($lbl -match 'Service Tag|Série') { $kpiSerial = $val }
                elseif ($lbl -match 'Sistema operacional') { $kpiOs = ($val -replace '\s*\(build.*$', '') }
                elseif ($lbl -match 'Ativa') {
                    $kpiOsSub = $val
                    if ($val -match 'Não ativado|Expirad') {
                        $recs.Add(@{ Level = "alta"; Tag = "Licenciamento"; Text = "Windows sem ativação válida — regularizar licença do sistema operacional." })
                    }
                }
                elseif ($lbl -match 'Reinício pendente' -and $val -notmatch '^Não') {
                    $recs.Add(@{ Level = "media"; Tag = "Sistema"; Text = "Há reinício pendente — reiniciar a estação para concluir atualizações e ajustes." })
                }
            } elseif ($t -match 'Hardware') {
                if ($lbl -match 'Processador') { $kpiCpu = ($val -replace '\(R\)|\(TM\)|CPU\s*@.*$', '').Trim() }
                elseif ($lbl -match 'Mem') { $kpiRam = $val }
            } elseif ($t -match 'Discos') {
                if ($lbl -eq 'C:') {
                    $kpiDiskText = ($val -replace '\s*·.*$', '')
                    if ($val -match '\((\d+)%\s*usado\)') {
                        $kpiDiskPct = [int]$Matches[1]
                        if ($kpiDiskPct -ge 85) {
                            $recs.Add(@{ Level = "alta"; Tag = "Armazenamento"; Text = "Disco C: com $kpiDiskPct% de ocupação — executar limpeza de arquivos ou expandir armazenamento." })
                        }
                    }
                }
                if ($lbl -match '^Saúde:' -and $val -notmatch 'Saudável') {
                    $recs.Add(@{ Level = "alta"; Tag = "Disco (SMART)"; Text = "Alerta de confiabilidade detectado no disco ($lbl) — realizar backup imediato e avaliar substituição." })
                }
            } elseif ($t -match 'Seguran') {
                if ($lbl -match 'Antiv') {
                    $kpiSecText = ($val -replace '^Outro antivírus em uso:\s*', '')
                    if ($val -match 'Nenhum|Desativado|desligado') {
                        $kpiSecTone = "bad"
                        $recs.Add(@{ Level = "alta"; Tag = "Segurança"; Text = "Antivírus inativo ou ausente — ativar proteção contra ameaças imediatamente." })
                    }
                } elseif ($lbl -match 'Firewall') {
                    $kpiSecSub = if ($val -match 'desligado') { "Firewall parcialmente desligado" } else { "Firewall ativo" }
                    if ($val -match 'desligado') {
                        if ($kpiSecTone -eq 'ok') { $kpiSecTone = "warn" }
                        $recs.Add(@{ Level = "media"; Tag = "Firewall"; Text = "Um ou mais perfis do Firewall do Windows estão desativados — revisar política de rede." })
                    }
                }
            } elseif ($t -match 'Bateria' -and $val -match 'Desgaste alto') {
                $recs.Add(@{ Level = "media"; Tag = "Bateria"; Text = "Bateria com desgaste avançado ($($val -replace '\s*\|.*$', '')) — avaliar substituição preventiva." })
            } elseif ($t -match 'Eventos') {
                if ($lbl -match 'Kernel-Power|EventLog \(ID 6008\)') { $hasUnexpectedShutdown = $true }
                if ($lbl -match 'WindowsUpdateClient') { $hasWuErrors = $true }
                if ($lbl -match 'Service Control Manager') { $hasServiceErrors = $true }
            } elseif ($t -match 'Drivers' -and $lbl -match 'Dispositivos com erro') {
                $recs.Add(@{ Level = "media"; Tag = "Drivers"; Text = "$val no Gerenciador de Dispositivos — reinstalar ou atualizar drivers afetados." })
            } elseif ($t -match 'Pontos de aten' -and $val -match 'não foi verificado nem passou por uma manutenção') {
                $recs.Add(@{ Level = "info"; Tag = "Preventiva"; Text = "Estação sem registro de manutenção recente — agendar rotina preventiva pelo TF-Toolkit." })
            }
        }
    }

    if ($hasUnexpectedShutdown) {
        $recs.Add(@{ Level = "media"; Tag = "Estabilidade"; Text = "Desligamentos/reinícios inesperados registrados nos últimos 7 dias (Kernel-Power 41 / EventLog 6008) — verificar fonte, bateria, energia ou temperatura." })
    }
    if ($hasWuErrors) {
        $recs.Add(@{ Level = "info"; Tag = "Atualizações"; Text = "Falhas recentes no Windows Update — executar o reparo do Windows Update no TF-Toolkit." })
    }
    if ($hasServiceErrors -and -not $hasUnexpectedShutdown) {
        $recs.Add(@{ Level = "info"; Tag = "Serviços"; Text = "Falhas de inicialização de serviços detectadas no log de eventos — revisar serviços afetados." })
    }
    if ($recs.Count -eq 0) {
        $recs.Add(@{ Level = "ok"; Tag = "Saudável"; Text = "Nenhum ponto crítico identificado — manter a rotina preventiva periódica." })
    }

    $recsHtmlSb = New-Object System.Text.StringBuilder
    [void]$recsHtmlSb.AppendLine("<div class='rec-box'><div class='rec-head'><span>Recomendações Técnicas Automáticas</span><span class='rec-cnt'>$($recs.Count) item(ns)</span></div><ul class='rec-list'>")
    foreach ($r in $recs) {
        $pillCls = switch ($r.Level) {
            "alta"  { "pill-bad" }
            "media" { "pill-warn" }
            "ok"    { "pill-ok" }
            default { "pill-info" }
        }
        [void]$recsHtmlSb.AppendLine("<li><span class='pill $pillCls'>$(& $encode $r.Tag)</span><span>$(& $encode $r.Text)</span></li>")
    }
    [void]$recsHtmlSb.AppendLine("</ul></div>")
    $recsBlockHtml = $recsHtmlSb.ToString()

    $metaModelText = if (-not [string]::IsNullOrWhiteSpace($kpiSerial)) { "$kpiModel · S/N: $kpiSerial" } else { $kpiModel }

    $scoreBadge = ""
    if ($HealthScore -ge 0) {
        $scoreRingColor = if ($HealthScore -ge 85) { "#22c55e" } elseif ($HealthScore -ge 65) { "#f59e0b" } else { "#ef4444" }
        $dashOffset = [math]::Round(138.2 - (138.2 * [math]::Min(100, [math]::Max(0, $HealthScore)) / 100.0), 1)
        $scoreBadge = @"
<div class='score-card'>
  <svg class='score-ring' viewBox='0 0 52 52' width='52' height='52'>
    <circle cx='26' cy='26' r='22' fill='none' stroke='rgba(255,255,255,0.16)' stroke-width='4.5'/>
    <circle cx='26' cy='26' r='22' fill='none' stroke='$scoreRingColor' stroke-width='4.5' stroke-linecap='round' stroke-dasharray='138.2' stroke-dashoffset='$dashOffset' transform='rotate(-90 26 26)'/>
    <text x='26' y='31' text-anchor='middle' fill='#ffffff' font-size='14.5' font-weight='800' font-family='Segoe UI, Arial, sans-serif'>$HealthScore</text>
  </svg>
  <div class='score-info'>
    <div class='score-tag'>Índice de Saúde</div>
    <div class='score-lbl'>$(& $encode $HealthLabel)</div>
    <div class='score-sub'>$HealthScore / 100 pontos</div>
  </div>
</div>
"@
    }

    $diskBarHtml = ""
    if ($kpiDiskPct -ge 0) {
        $dCls = if ($kpiDiskPct -ge 90) { "bad" } elseif ($kpiDiskPct -ge 75) { "warn" } else { "ok" }
        $diskBarHtml = "<div class='mini-bar'><div class='mini-fill $dCls' style='width:$kpiDiskPct%'></div></div>"
    }

    $runningHeaderLogoCss = ""
    if (-not [string]::IsNullOrWhiteSpace($logoDataUri)) {
        $runningHeaderLogoCss = "background-image: url('$logoDataUri'); background-repeat: no-repeat; background-size: 15px 15px; background-position: 0 calc(100% - 5px); padding-left: 21px;"
    }

    # Helper para badges visuais de valor
    $formatValue = {
        param([string]$secTitle, [string]$label, [string]$val)
        $safe = & $encode $val

        if ($secTitle -match 'Ajustes') {
            if ($val -eq 'Ativado') { return "<span class='pill pill-ok'>Ativado</span>" }
            if ($val -eq 'Desativado') { return "<span class='pill pill-muted'>Desativado</span>" }
            return "<span class='pill pill-info'>$safe</span>"
        }

        if ($secTitle -match 'Discos' -and $val -match '\((\d+)%\s*usado\)') {
            $pct = [int]$Matches[1]
            $barCls = if ($pct -ge 90) { "bad" } elseif ($pct -ge 75) { "warn" } else { "ok" }
            return "<div>$safe</div><div class='disk-bar'><div class='disk-fill $barCls' style='width:$pct%'></div></div>"
        }

        if ($label -match '^Grave$') { return "<span class='pill pill-bad'>Crítico</span> $safe" }
        if ($label -match '^Aten') { return "<span class='pill pill-warn'>Atenção</span> $safe" }
        if ($val -match 'Desgaste alto|Crítico|Nenhum antivírus|Falha|Kernel-Power|Reinício inesperado') {
            return "<span class='val-warn'>$safe</span>"
        }
        if ($val -match '^(Ativado|Saudável|OK\b|Nenhuma|Nenhum dispositivo com erro|Nenhum$)') {
            return "<span class='val-ok'>$safe</span>"
        }
        return $safe
    }

    # Icones SVG inline por secao
    $getSectionIcon = {
        param([string]$title)
        if ($title -match 'aten') { return "<svg viewBox='0 0 24 24'><path d='M12 3L2 20h20L12 3zm0 6v5m0 3h.01'/></svg>" }
        if ($title -match 'Sistema') { return "<svg viewBox='0 0 24 24'><rect x='3' y='4' width='18' height='12' rx='2'/><path d='M8 20h8M12 16v4'/></svg>" }
        if ($title -match 'Hardware') { return "<svg viewBox='0 0 24 24'><rect x='6' y='6' width='12' height='12' rx='2'/><path d='M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4'/></svg>" }
        if ($title -match 'Disco') { return "<svg viewBox='0 0 24 24'><rect x='3' y='13' width='18' height='7' rx='2'/><path d='M4 13l2.5-8h11L20 13M16.5 16.5h.01'/></svg>" }
        if ($title -match 'Seguran') { return "<svg viewBox='0 0 24 24'><path d='M12 3l8 3v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6l8-3z'/><path d='M9 12l2 2 4-4'/></svg>" }
        if ($title -match 'Rede') { return "<svg viewBox='0 0 24 24'><path d='M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M12 19.5h.01M2 9a15 15 0 0 1 20 0'/></svg>" }
        if ($title -match 'Bateria') { return "<svg viewBox='0 0 24 24'><rect x='2' y='7' width='18' height='10' rx='2'/><path d='M22 10v4M6 10v4M10 10v4'/></svg>" }
        if ($title -match 'Evento') { return "<svg viewBox='0 0 24 24'><circle cx='12' cy='12' r='9'/><path d='M12 8v5M12 16h.01'/></svg>" }
        if ($title -match 'Telas azuis') { return "<svg viewBox='0 0 24 24'><path d='M3 12h4l3-7 4 14 3-7h4'/></svg>" }
        if ($title -match 'Driver') { return "<svg viewBox='0 0 24 24'><path d='M14.7 6.3a4 4 0 0 0-5.4 5.4L4 17a2 2 0 1 0 2.8 2.8l5.3-5.3a4 4 0 0 0 5.4-5.4l-2.3 2.3-2.8-.8-.8-2.8z'/></svg>" }
        if ($title -match 'Programa') { return "<svg viewBox='0 0 24 24'><rect x='3' y='3' width='8' height='8' rx='1.5'/><rect x='13' y='3' width='8' height='8' rx='1.5'/><rect x='3' y='13' width='8' height='8' rx='1.5'/><rect x='13' y='13' width='8' height='8' rx='1.5'/></svg>" }
        return "<svg viewBox='0 0 24 24'><path d='M4 7h10M18 7h2M4 17h4M12 17h8'/><circle cx='16' cy='7' r='2'/><circle cx='10' cy='17' r='2'/></svg>"
    }

    $safeHostCss = ($env:COMPUTERNAME -replace '["\\]', '')

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(@"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Relatório Técnico de Diagnóstico - $hostName - Tech Fontes</title>
<style>
  /* Configuração Editorial A4 com Cabeçalho e Rodapé Fixos em Todas as Páginas */
  @page {
    size: A4;
    margin: 22mm 14mm 19mm 14mm;
    @top-left {
      content: "TECH FONTES  ·  Relatório Técnico de Diagnóstico";
      font-family: 'Segoe UI', Arial, sans-serif;
      font-size: 8.5px;
      font-weight: 700;
      color: #334155;
      letter-spacing: 0.3px;
      vertical-align: bottom;
      padding-bottom: 6px;
      margin-bottom: 8px;
      border-bottom: 1.5px solid #C4613A;
      $runningHeaderLogoCss
    }
    @top-center {
      content: "";
      margin-bottom: 8px;
      border-bottom: 1.5px solid #e2e8f0;
    }
    @top-right {
      content: "Estação: $safeHostCss  ·  $nowDate";
      font-family: 'Segoe UI', Arial, sans-serif;
      font-size: 8.5px;
      font-weight: 600;
      color: #64748b;
      vertical-align: bottom;
      padding-bottom: 6px;
      margin-bottom: 8px;
      border-bottom: 1.5px solid #e2e8f0;
    }
    @bottom-left {
      content: "Tech Fontes Informática  ·  techfontes.com.br  ·  fontes@techfontes.com.br";
      font-family: 'Segoe UI', Arial, sans-serif;
      font-size: 8.2px;
      color: #64748b;
      vertical-align: top;
      padding-top: 6px;
      border-top: 1px solid #cbd5e1;
    }
    @bottom-center {
      content: "";
      border-top: 1px solid #cbd5e1;
    }
    @bottom-right {
      content: "Página " counter(page) " de " counter(pages);
      font-family: 'Segoe UI', Arial, sans-serif;
      font-size: 8.5px;
      font-weight: 700;
      color: #334155;
      vertical-align: top;
      padding-top: 6px;
      border-top: 1px solid #cbd5e1;
    }
  }

  /* Página 1 sem o cabeçalho corrido (usa o banner corporativo completo) */
  @page :first {
    margin-top: 12mm;
    @top-left { content: none; border-bottom: none; background-image: none; }
    @top-center { content: none; border-bottom: none; }
    @top-right { content: none; border-bottom: none; }
  }

  * { box-sizing: border-box; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
  body { margin: 0; font-family: 'Segoe UI', -apple-system, Arial, sans-serif; color: #1e293b; background: #ffffff; font-size: 10.2px; line-height: 1.48; }

  /* Banner Corporativo Editorial (Página 1) */
  .hero {
    background: linear-gradient(135deg, #16202c 0%, #243447 62%, #2f4358 100%);
    color: #ffffff;
    border-radius: 10px;
    padding: 18px 22px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 14px;
    border-bottom: 4px solid #C4613A;
  }
  .brand { display: flex; align-items: center; gap: 15px; }
  .logo-wrap { background: #ffffff; border-radius: 10px; padding: 6px; width: 54px; height: 54px; display: flex; align-items: center; justify-content: center; box-shadow: 0 3px 10px rgba(0,0,0,0.22); }
  .brand-logo { width: 42px; height: 42px; object-fit: contain; }
  .brand-badge { width: 52px; height: 52px; border-radius: 10px; background: #C4613A; color: #fff; font-weight: 800; font-size: 20px; display: flex; align-items: center; justify-content: center; }
  .brand-kicker { font-size: 8.8px; font-weight: 700; letter-spacing: 1.4px; text-transform: uppercase; color: #f5aa89; margin-bottom: 3px; }
  .brand h1 { margin: 0; font-size: 20px; font-weight: 800; color: #ffffff; letter-spacing: -0.3px; }
  .brand p { margin: 3px 0 0; font-size: 10px; color: #cbd5e1; }

  /* Índice de Saúde no Banner */
  .score-card { display: flex; align-items: center; gap: 11px; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.18); border-radius: 10px; padding: 8px 14px; }
  .score-ring { flex-shrink: 0; }
  .score-tag { font-size: 8.2px; text-transform: uppercase; letter-spacing: 0.8px; color: #cbd5e1; font-weight: 600; }
  .score-lbl { font-size: 14px; font-weight: 800; color: #ffffff; line-height: 1.15; }
  .score-sub { font-size: 9.2px; color: #cbd5e1; }

  /* Faixa de Identificação do Laudo */
  .meta-strip {
    display: grid;
    grid-template-columns: 1.3fr 1fr 1.1fr 1fr;
    gap: 10px;
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 9px 14px;
    margin-bottom: 14px;
  }
  .meta-cell span { display: block; font-size: 8px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.6px; color: #64748b; }
  .meta-cell strong { font-size: 10.8px; color: #0f172a; font-weight: 700; }

  /* KPIs Executivos */
  .kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-bottom: 16px; }
  .kpi { background: #ffffff; border: 1px solid #e2e8f0; border-top: 3px solid #2a3b4c; border-radius: 8px; padding: 10px 12px; }
  .kpi.accent { border-top-color: #C4613A; }
  .kpi.ok { border-top-color: #16a34a; }
  .kpi.warn { border-top-color: #d97706; }
  .kpi.bad { border-top-color: #dc2626; }
  .kpi-lbl { font-size: 8.2px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; color: #64748b; margin-bottom: 3px; }
  .kpi-val { font-size: 11.2px; font-weight: 700; color: #0f172a; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .kpi-sub { font-size: 9.2px; color: #475569; margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .mini-bar { height: 5px; background: #e2e8f0; border-radius: 99px; overflow: hidden; margin-top: 6px; }
  .mini-fill { height: 100%; border-radius: 99px; }
  .mini-fill.ok { background: #16a34a; }
  .mini-fill.warn { background: #d97706; }
  .mini-fill.bad { background: #dc2626; }

  /* Divisória Editorial de Anexo */
  .appendix-banner {
    margin: 18px 0 12px;
    padding: 7px 12px;
    background: #f1f5f9;
    border-left: 4px solid #243447;
    border-radius: 0 6px 6px 0;
    font-size: 9.5px;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: #334155;
    break-after: avoid;
    page-break-after: avoid;
  }

  /* Seções Editoriais Numeradas */
  section {
    border: 1px solid #e2e8f0;
    border-radius: 9px;
    margin-bottom: 13px;
    overflow: hidden;
    break-inside: avoid;
    page-break-inside: avoid;
    background: #ffffff;
  }
  section.flow { break-inside: auto; page-break-inside: auto; }
  .sec-head {
    background: #f8fafc;
    border-bottom: 1px solid #e2e8f0;
    padding: 8px 14px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    break-after: avoid;
    page-break-after: avoid;
  }
  .sec-title { display: flex; align-items: center; gap: 8px; font-size: 11.2px; font-weight: 800; color: #0f172a; text-transform: uppercase; letter-spacing: 0.4px; }
  .sec-num { font-size: 9.5px; font-weight: 800; color: #ffffff; background: #C4613A; padding: 1px 6px; border-radius: 4px; letter-spacing: 0.3px; }
  .sec-title svg { width: 14px; height: 14px; stroke: #243447; fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; flex-shrink: 0; }
  .sec-count { font-size: 8.8px; font-weight: 700; color: #475569; background: #e2e8f0; padding: 2px 8px; border-radius: 99px; }
  .sec-body { padding: 8px 14px 10px; }

  /* Tabela Editorial Padrão */
  table.kv { width: 100%; border-collapse: collapse; }
  table.kv tr { border-bottom: 1px solid #f1f5f9; break-inside: avoid; }
  table.kv tr:nth-child(even) { background: #fafbfd; }
  table.kv tr:last-child { border-bottom: none; }
  table.kv td { padding: 5.5px 7px; vertical-align: top; }
  table.kv td.k { width: 30%; font-weight: 600; color: #475569; }
  table.kv td.v { color: #0f172a; word-break: break-word; }

  /* Grade Compacta de 2 Colunas (Anexos: Programas e Ajustes) */
  .grid-2 { display: grid; grid-template-columns: 1fr 1fr; column-gap: 18px; row-gap: 0; }
  .g-item { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; padding: 4px 4px; border-bottom: 1px solid #f1f5f9; break-inside: avoid; }
  .g-k { font-weight: 600; color: #334155; font-size: 9.4px; }
  .g-v { color: #475569; font-size: 9.2px; text-align: right; flex-shrink: 0; max-width: 50%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  /* Barras de Disco e Selos de Status */
  .disk-bar { height: 5px; width: 190px; background: #e2e8f0; border-radius: 99px; overflow: hidden; margin-top: 5px; }
  .disk-fill { height: 100%; border-radius: 99px; }
  .disk-fill.ok { background: #16a34a; }
  .disk-fill.warn { background: #d97706; }
  .disk-fill.bad { background: #dc2626; }
  .pill { display: inline-block; padding: 1.5px 7px; border-radius: 99px; font-size: 8.5px; font-weight: 700; letter-spacing: 0.2px; }
  .pill-ok { background: #dcfce7; color: #166534; border: 1px solid #bbf7d0; }
  .pill-warn { background: #fef3c7; color: #92400e; border: 1px solid #fde68a; }
  .pill-bad { background: #fee2e2; color: #991b1b; border: 1px solid #fecaca; }
  .pill-muted { background: #f1f5f9; color: #64748b; border: 1px solid #e2e8f0; }
  .pill-info { background: #e0f2fe; color: #075985; border: 1px solid #bae6fd; }
  .val-ok { color: #15803d; font-weight: 600; }
  .val-warn { color: #b45309; font-weight: 600; }

  /* Bloco de Recomendações Técnicas Automáticas */
  .rec-box {
    background: #fffaf7;
    border: 1px solid #f0d4c6;
    border-left: 4px solid #C4613A;
    border-radius: 8px;
    padding: 9px 13px;
    margin-bottom: 14px;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  .rec-head { display: flex; justify-content: space-between; align-items: center; font-size: 9.8px; font-weight: 800; text-transform: uppercase; letter-spacing: 0.5px; color: #9a3e1b; margin-bottom: 6px; }
  .rec-cnt { font-size: 8.5px; font-weight: 700; color: #9a3e1b; background: #fae4d8; padding: 1px 7px; border-radius: 99px; }
  .rec-list { list-style: none; margin: 0; padding: 0; }
  .rec-list li { display: flex; align-items: baseline; gap: 8px; padding: 2.8px 0; font-size: 9.8px; color: #1e293b; border-bottom: 1px dashed #f3dfd4; }
  .rec-list li:last-child { border-bottom: none; }
  .rec-list .pill { flex-shrink: 0; min-width: 74px; text-align: center; }

  /* Quadro Editorial de Parecer Técnico */
  .analyst-box {
    margin-top: 16px;
    border: 1px solid #cbd5e1;
    border-top: 3px solid #243447;
    background: #f8fafc;
    border-radius: 8px;
    padding: 13px 16px;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  .analyst-title { font-size: 10px; font-weight: 800; text-transform: uppercase; letter-spacing: 0.6px; color: #1e293b; margin-bottom: 8px; }
  .analyst-notes { border: 1px dashed #cbd5e1; background: #ffffff; border-radius: 6px; height: 54px; margin-bottom: 12px; padding: 6px 10px; font-size: 8.8px; color: #94a3b8; }
  .analyst-grid { display: grid; grid-template-columns: 1.2fr 1fr 0.8fr 1fr; gap: 14px; font-size: 8.8px; font-weight: 600; color: #475569; }
  .analyst-line { border-bottom: 1px solid #94a3b8; height: 20px; margin-top: 2px; }
</style>
</head>
<body>
  <div class="hero">
    <div class="brand">
      $logoHtml
      <div>
        <div class="brand-kicker">Tech Fontes Informática · Laudo Técnico Preventivo</div>
        <h1>Relatório de Diagnóstico da Estação</h1>
        <p>Levantamento técnico completo gerado pelo TF-Toolkit v$(& $encode $Build) para análise especializada</p>
      </div>
    </div>
    $scoreBadge
  </div>

  <div class="meta-strip">
    <div class="meta-cell"><span>Equipamento / Service Tag</span><strong>$(& $encode $metaModelText)</strong></div>
    <div class="meta-cell"><span>Estação / Usuário</span><strong>$hostName · $userName</strong></div>
    <div class="meta-cell"><span>Data de Emissão</span><strong>$nowText</strong></div>
    <div class="meta-cell"><span>Protocolo do Laudo</span><strong>$protocolId</strong></div>
  </div>

  <div class="kpi-grid">
    <div class="kpi accent">
      <div class="kpi-lbl">Sistema Operacional</div>
      <div class="kpi-val">$(& $encode $kpiOs)</div>
      <div class="kpi-sub">$(& $encode $kpiOsSub)</div>
    </div>
    <div class="kpi">
      <div class="kpi-lbl">Processador &amp; Memória</div>
      <div class="kpi-val">$(& $encode $kpiCpu)</div>
      <div class="kpi-sub">$(& $encode $kpiRam)</div>
    </div>
    <div class="kpi">
      <div class="kpi-lbl">Disco Principal (C:)</div>
      <div class="kpi-val">$(& $encode $kpiDiskText)</div>
      $diskBarHtml
    </div>
    <div class="kpi $kpiSecTone">
      <div class="kpi-lbl">Proteção &amp; Segurança</div>
      <div class="kpi-val">$(& $encode $kpiSecText)</div>
      <div class="kpi-sub">$(& $encode $kpiSecSub)</div>
    </div>
  </div>

  $recsBlockHtml
"@)

    $secNum = 0
    $appendixPrinted = $false
    foreach ($sec in $orderedSections) {
        if (-not $sec.Items -or $sec.Items.Count -eq 0) { continue }
        $secNum++
        $numTxt = "{0:D2}" -f $secNum
        $secTitle = [string]$sec.Title
        $iconSvg = & $getSectionIcon $secTitle
        $isCompactGrid = ($secTitle -match 'Ajustes do Windows|Programas Instalados')

        if ($isCompactGrid -and -not $appendixPrinted) {
            [void]$sb.AppendLine("<div class='appendix-banner'>Anexos Técnicos · Inventário de Softwares e Configurações do Sistema</div>")
            $appendixPrinted = $true
        }

        $secCls = if ($isCompactGrid -or $sec.Items.Count -gt 10) { " class='flow'" } else { "" }

        [void]$sb.AppendLine("<section$secCls><div class='sec-head'><div class='sec-title'><span class='sec-num'>$numTxt</span>$iconSvg<span>$(& $encode $secTitle)</span></div><span class='sec-count'>$($sec.Items.Count) itens</span></div><div class='sec-body'>")

        if ($isCompactGrid) {
            [void]$sb.AppendLine("<div class='grid-2'>")
            foreach ($it in $sec.Items) {
                $vHtml = & $formatValue $secTitle ([string]$it.Label) ([string]$it.Value)
                [void]$sb.AppendLine("<div class='g-item'><span class='g-k'>$(& $encode $it.Label)</span><span class='g-v'>$vHtml</span></div>")
            }
            [void]$sb.AppendLine("</div>")
        } else {
            [void]$sb.AppendLine("<table class='kv'>")
            foreach ($it in $sec.Items) {
                $vHtml = & $formatValue $secTitle ([string]$it.Label) ([string]$it.Value)
                [void]$sb.AppendLine("<tr><td class='k'>$(& $encode $it.Label)</td><td class='v'>$vHtml</td></tr>")
            }
            [void]$sb.AppendLine("</table>")
        }

        [void]$sb.AppendLine("</div></section>")
    }

    [void]$sb.AppendLine(@"
  <div class="analyst-box">
    <div class="analyst-title">Parecer Técnico e Registro do Analista</div>
    <div class="analyst-notes">Observações, diagnóstico complementar e recomendações técnicas:</div>
    <div class="analyst-grid">
      <div>Analista Responsável<div class="analyst-line"></div></div>
      <div>Cliente / Empresa<div class="analyst-line"></div></div>
      <div>Chamado / OS<div class="analyst-line"></div></div>
      <div>Data / Assinatura<div class="analyst-line"></div></div>
    </div>
  </div>
</body>
</html>
"@)

    return $sb.ToString()
}


function Export-TFToolkitDiagnosticPdf {
    param (
        [string]$OutputDirectory = ""
    )

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $desktop = [Environment]::GetFolderPath("Desktop")
        if (-not [string]::IsNullOrWhiteSpace($desktop) -and (Test-Path -LiteralPath $desktop -PathType Container)) {
            $OutputDirectory = $desktop
        } else {
            $OutputDirectory = Join-Path (Get-TFToolkitDataPath) "reports"
        }
    }
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        [void](New-Item -Path $OutputDirectory -ItemType Directory -Force -ErrorAction Stop)
    }

    $reportsDir = Join-Path (Get-TFToolkitDataPath) "reports"
    if (-not (Test-Path -LiteralPath $reportsDir -PathType Container)) {
        [void](New-Item -Path $reportsDir -ItemType Directory -Force -ErrorAction SilentlyContinue)
    }

    # Coleta todas as secoes padrao + Rede + Drivers/Startup + Programas Instalados
    $sections = New-Object System.Collections.Generic.List[object]
    foreach ($s in @(Get-TFToolkitReportSections)) { $sections.Add($s) }

    $sections.Add((New-TFToolkitReportSection -Title (Get-TFToolkitText 'Rede e Conectividade') -Build { Get-TFToolkitReportNetworkItems }))
    $sections.Add((New-TFToolkitReportSection -Title (Get-TFToolkitText 'Drivers e Inicialização') -Build { Get-TFToolkitReportDriversAndStartupItems }))
    $sections.Add((New-TFToolkitReportSection -Title (Get-TFToolkitText 'Programas Instalados') -Build { Get-TFToolkitReportInstalledAppsItems }))

    # Nota de saude se disponivel
    $score = -1
    $scoreLabel = ""
    try {
        if (Get-Command Get-TFToolkitHomeStatus -ErrorAction SilentlyContinue) {
            $status = Get-TFToolkitHomeStatus
            if ($null -ne $status -and $null -ne $status.Health -and (Test-TFToolkitHealthKnown -Health $status.Health)) {
                $score = [int]$status.Health.Score
                $scoreLabel = [string]$status.Health.Label
            }
        }
    } catch {}

    $build = Get-TFToolkitBuild
    $stamp = Get-Date -Format "yyyyMMdd-HHmm"
    $safeHost = ($env:COMPUTERNAME -replace '[^A-Za-z0-9_-]', '_')
    $baseName = "Relatorio_Diagnostico_${safeHost}_${stamp}"
    $htmlPath = Join-Path $reportsDir "$baseName.html"
    $pdfPath  = Join-Path $OutputDirectory "$baseName.pdf"

    $html = ConvertTo-TFToolkitAnalystHtmlReport -Sections $sections.ToArray() -Build $build -HealthScore $score -HealthLabel $scoreLabel
    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8 -ErrorAction Stop

    $browser = Find-TFToolkitPdfBrowser
    $pdfCreated = $false
    $pdfNote = ""

    if ($browser) {
        $fileUri = ([System.Uri]$htmlPath).AbsoluteUri
        foreach ($modeArg in @("--headless=new", "--headless")) {
            try {
                if (Test-Path -LiteralPath $pdfPath) { Remove-Item -LiteralPath $pdfPath -Force -ErrorAction SilentlyContinue }
                $argStr = "$modeArg --disable-gpu --no-pdf-header-footer --print-to-pdf=`"$pdfPath`" `"$fileUri`""
                $p = Start-Process -FilePath $browser -ArgumentList $argStr -WindowStyle Hidden -PassThru
                if ($p.WaitForExit(30000) -and (Test-Path -LiteralPath $pdfPath -PathType Leaf) -and (Get-Item -LiteralPath $pdfPath).Length -gt 1024) {
                    $pdfCreated = $true
                    break
                }
            } catch {}
        }
        if (-not $pdfCreated) { $pdfNote = "Não foi possível converter automaticamente para PDF; relatório HTML salvo pronto para impressão." }
    } else {
        $pdfNote = "Edge/Chrome não encontrado para gerar PDF automático; relatório HTML salvo pronto para impressão."
    }

    if ($pdfCreated -and $OutputDirectory -ne $reportsDir) {
        try { Copy-Item -LiteralPath $pdfPath -Destination (Join-Path $reportsDir "$baseName.pdf") -Force -ErrorAction SilentlyContinue } catch {}
    }

    return [PSCustomObject]@{
        Pdf        = $(if ($pdfCreated) { $pdfPath } else { $null })
        Html       = $htmlPath
        PdfCreated = $pdfCreated
        Note       = $pdfNote
        Sections   = $sections.Count
    }
}


function Invoke-TFToolkitPdfReport {
    $title = (Get-TFToolkitText 'Relatório em PDF (para analista)')
    Enter-TFToolkitAction -Title $title

    $result = $null
    try {
        Write-Progress -Activity $title -Status (Get-TFToolkitText 'coletando hardware, discos, rede, segurança, drivers, eventos e programas...')
        try {
            $out = Export-TFToolkitDiagnosticPdf
        } finally {
            Write-Progress -Activity $title -Completed
        }

        Write-Host ""
        if ($out.PdfCreated) {
            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Relatório completo em PDF gerado com sucesso! Pronto para encaminhar ao analista.')
            Write-TFToolkitKeyValue -Label "PDF" -Value $out.Pdf
            Write-TFToolkitKeyValue -Label "HTML" -Value $out.Html
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Seções incluídas') -Value "$($out.Sections)"
            $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'relatório completo salvo em PDF na Área de Trabalho')
            $openTarget = $out.Pdf
        } else {
            Write-TFToolkitStatus -Type Warning -Message $out.Note
            Write-TFToolkitKeyValue -Label "HTML" -Value $out.Html
            $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'relatório salvo em HTML (use Ctrl+P para salvar em PDF)')
            $openTarget = $out.Html
        }

        Write-Host ""
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Você pode anexar este arquivo no chamado, WhatsApp ou e-mail para fontes@techfontes.com.br.')

        $problem = Open-TFToolkitSavedReport -Path $openTarget
        if ($problem) {
            $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'relatório salvo, mas não foi possível {0}' "$problem")
        }
    } catch {
        Write-Host ""
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Falha ao gerar relatório em PDF: {0}' "$($_.Exception.Message.TrimEnd('.'))")
        $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível gerar o relatório em PDF')
    }

    Exit-TFToolkitAction -Result $result
}


# ---------------------------------------------------------------------------
# Verificação rápida (TF-Toolkit.Console.ps1 -Action Check)
# ---------------------------------------------------------------------------

function Get-TFToolkitCheckLevel {
    <#
    O resultado único da verificação rápida. Critical: nota de saúde abaixo de 50, algum ponto de saúde de peso 25 ou
    mais (disco quase cheio, nenhum antivírus, ameaça ativa) ou um ponto grave da auditoria (Critical + Bad). Attention:
    qualquer outro ponto de saúde ou algum ponto da auditoria com risco real (Bad). Os pontos "Atenção" (Warn) da
    auditoria aparecem no relatório, mas não mudam o resultado: um PC com Área de Trabalho Remota ligada de propósito
    não deveria ficar sempre em Attention.
    #>
    param (
        $Health = $null,

        [object[]]$Attention = @()
    )

    $issues = @()
    $score = 100

    if ($null -ne $Health) {
        $issues = @($Health.Issues | Where-Object { $null -ne $_ })
        $score = [int]$Health.Score
    }

    $items = @($Attention | Where-Object { $null -ne $_ })

    if ($score -lt 50 -or @($issues | Where-Object { [int]$_.Weight -ge 25 }).Count -gt 0 -or @($items | Where-Object { $_.Status -eq "Bad" -and $_.Critical }).Count -gt 0) {
        return "Critical"
    }

    if ($issues.Count -gt 0 -or @($items | Where-Object { $_.Status -eq "Bad" }).Count -gt 0) {
        return "Attention"
    }

    return "Ok"
}


function Get-TFToolkitCheckExitCode {
    # 0 = tudo em dia, 1 = há pontos de atenção, 2 = há algo crítico, 3 = não foi possível avaliar.
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Ok", "Attention", "Critical", "Unknown")]
        [string]$Status
    )

    switch ($Status) {
        "Ok"        { return 0 }
        "Attention" { return 1 }
        "Critical"  { return 2 }
        default     { return 3 }
    }
}


function Get-TFToolkitCheckReport {
    <#
    Uma leitura rápida e só de leitura do PC: a nota de saúde da tela inicial e a nota da auditoria de segurança, sem
    a consulta ao Windows Update (que leva até um minuto). Nunca lança erro: se a leitura inteira falhar, devolve
    Status Unknown e ExitCode 3 com o motivo em Error.
    #>
    $notes = @()

    try {
        $status = Get-TFToolkitHomeStatus
        $health = $status.Health

        $facts = @()

        foreach ($fact in @($status.Facts | Where-Object { $_.Visible })) {
            $facts += [PSCustomObject]@{ Id = $fact.Id; Label = $fact.Label; Text = $fact.Text; Level = $fact.Level }
        }

        $issues = @()

        foreach ($issue in @($health.Issues)) {
            $issues += [PSCustomObject]@{ Id = $issue.Id; Text = $issue.Text; Weight = [int]$issue.Weight }
        }

        # O que entraria na nota de saúde, mas não pôde ser lido: a nota vale para o resto (como diz o Início).
        $unread = @(Get-TFToolkitJsonValue -Object $health -Name "Unread" -Default @())

        if ($unread.Count -gt 0) {
            $notes += (Get-TFToolkitText 'A nota de saúde não inclui o que não pôde ser lido: {0}.' "$($unread -join ', ')")
        }

        $security = $null
        $attention = @()

        try {
            $auditChecks = @(Get-TFToolkitSecurityAuditChecks -Facts (Get-TFToolkitSecurityAuditFacts))
            $grade = Get-TFToolkitSecurityGrade -Checks $auditChecks

            foreach ($check in @($auditChecks | Where-Object { $_.Weight -gt 0 -and $_.Status -in "Warn", "Bad" })) {
                $attention += [PSCustomObject]@{
                    Id       = $check.Id
                    Title    = $check.Title
                    Status   = $check.Status
                    Critical = [bool]$check.Critical
                    Detail   = $check.Detail
                    Advice   = $check.Advice
                }
            }

            $security = [PSCustomObject]@{
                Grade         = $grade.Grade
                Score         = $grade.Score
                NoGradeReason = [string](Get-TFToolkitJsonValue -Object $grade -Name "NoGradeReason" -Default "")
                Capped        = [bool]$grade.Capped
                Unverified    = @($auditChecks | Where-Object { $_.Weight -gt 0 -and $_.Status -eq "Unknown" }).Count
                Attention     = $attention
            }

            $notes += (Get-TFToolkitText 'A consulta ao Windows Update foi pulada para a verificação ser rápida; rode Segurança > Auditoria de segurança para incluí-la.')
        }
        catch {
            $notes += (Get-TFToolkitText 'Não foi possível fazer a auditoria de segurança: {0}' "$($_.Exception.Message)")
        }

        if (-not (Test-TFToolkitAdministrator)) {
            $notes += (Get-TFToolkitText 'Sem Administrador: pontos como a criptografia do disco não são verificados.')
        }

        $level = Get-TFToolkitCheckLevel -Health $health -Attention $attention
        $problem = ""

        # Nada do que forma a nota foi lido: a nota 100 não quer dizer "tudo em dia". Sem nada grave vindo da auditoria, o
        # resultado é "não foi possível avaliar".
        if ($level -eq "Ok" -and -not (Test-TFToolkitHealthKnown -Health $health)) {
            $level = "Unknown"
            $problem = (Get-TFToolkitText 'nenhuma leitura da nota de saúde respondeu ({0})' "$($unread -join ', ')")
        }
        elseif ($level -eq "Ok" -and $unread.Count -gt 0) {
            # Parte da nota sem leitura (a nota já diz qual): "em dia" (código 0) prometeria o que não foi conferido.
            $level = "Attention"
        }
        elseif ($level -eq "Ok" -and $null -ne $security -and $security.NoGradeReason -eq "Antivirus") {
            # O antivírus não pôde ser verificado: a auditoria fica sem nota, e "em dia" também prometeria demais.
            $level = "Attention"
        }

        # As telas azuis dos últimos 30 dias (Diagnóstico > Telas azuis): informam, sem mudar o Status nem o ExitCode.
        $stability = $null

        try {
            $screens = @(Get-TFToolkitBlueScreens -Days 30)
            $latest = $(if ($screens.Count -gt 0) {
                    [PSCustomObject]@{ At = $screens[0].When.ToString("o"); Code = ("0x{0:X8}" -f [uint32]$screens[0].Code); Name = [string]$screens[0].Info.Name; Cause = [string]$screens[0].Info.Cause }
                })
            $stability = [PSCustomObject]@{ Days = 30; BlueScreens = $screens.Count; Latest = $latest }
        }
        catch {
            Write-Verbose "Telas azuis: $($_.Exception.Message)"
        }

        return [PSCustomObject]@{
            Format        = "TFToolkit.Check"
            Version       = 2
            Build         = [string](Get-TFToolkitBuild)
            CheckedAt     = (Get-Date).ToString("o")
            Administrator = [bool](Test-TFToolkitAdministrator)
            Status        = $level
            ExitCode      = (Get-TFToolkitCheckExitCode -Status $level)
            Health        = [PSCustomObject]@{ Score = [int]$health.Score; Label = $health.Label; Level = $health.Level; Issues = $issues; Unread = @($unread) }
            Security      = $security
            Stability     = $stability
            Facts         = $facts
            Notes         = $notes
            Error         = $problem
        }
    }
    catch {
        return [PSCustomObject]@{
            Format        = "TFToolkit.Check"
            Version       = 2
            Build         = [string](Get-TFToolkitBuild)
            CheckedAt     = (Get-Date).ToString("o")
            Administrator = $false
            Status        = "Unknown"
            ExitCode      = (Get-TFToolkitCheckExitCode -Status "Unknown")
            Health        = $null
            Security      = $null
            Stability     = $null
            Facts         = @()
            Notes         = @()
            Error         = $_.Exception.Message
        }
    }
}


function ConvertTo-TFToolkitCheckJson {
    param (
        [Parameter(Mandatory)]
        $Report
    )

    return ($Report | ConvertTo-Json -Depth 6)
}


function Show-TFToolkitCheckReport {
    param (
        [Parameter(Mandatory)]
        $Report
    )

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Verificação rápida do TF-Toolkit (versão {0})' "$($Report.Build)")

    if ($Report.Status -eq "Unknown") {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível avaliar o PC: {0}' "$($Report.Error)")
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Código de saída') -Value ([string]$Report.ExitCode)
        return
    }

    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Saúde do PC') -Value (Get-TFToolkitText '{0} de 100 ({1})' "$($Report.Health.Score)" "$($Report.Health.Label)")

    foreach ($issue in @($Report.Health.Issues)) {
        Write-TFToolkitStatus -Type $(if ($issue.Weight -ge 25) { "Error" } else { "Warning" }) -Message $issue.Text
    }

    if (@($Report.Health.Issues).Count -eq 0) {
        $unread = @(Get-TFToolkitJsonValue -Object $Report.Health -Name "Unread" -Default @())
        Write-TFToolkitStatus -Type Success -Message $(if ($unread.Count -gt 0) { (Get-TFToolkitText 'Nenhum ponto de atenção no que foi lido.') } else { (Get-TFToolkitText 'Nenhum ponto de atenção na saúde do PC.') })
    }

    if ($null -ne $Report.Security) {
        if ($null -eq $Report.Security.Score) {
            $reason = [string](Get-TFToolkitJsonValue -Object $Report.Security -Name "NoGradeReason" -Default "")
            $why = switch ($reason) {
                "Antivirus" { (Get-TFToolkitText 'sem nota: o antivírus não pôde ser verificado') }
                "Coverage" { (Get-TFToolkitText 'sem nota: menos da metade dos pontos pôde ser verificada') }
                default { (Get-TFToolkitText 'sem nota: não foi possível calcular') }
            }

            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Segurança') -Value $why -Level Warn
        }
        else {
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Segurança') -Value (Get-TFToolkitText '{0} de 100 · {1}' "$($Report.Security.Score)" "$($Report.Security.Grade)")
        }

        foreach ($item in @($Report.Security.Attention)) {
            Write-TFToolkitStatus -Type $(if ($item.Status -eq "Bad") { "Error" } else { "Warning" }) -Message "$($item.Title): $($item.Detail)"
        }
    }

    foreach ($note in @($Report.Notes)) {
        Write-Host "  $note" -ForegroundColor DarkGray
    }

    $text = switch ($Report.Status) {
        "Ok"        { (Get-TFToolkitText 'Tudo em dia') }
        "Attention" { (Get-TFToolkitText 'Há pontos de atenção') }
        default     { (Get-TFToolkitText 'Há algo crítico') }
    }

    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Resultado') -Value (Get-TFToolkitText '{0} (código de saída {1})' "$text" "$($Report.ExitCode)")
}


# ---------------------------------------------------------------------------
# Pacote de suporte (Sobre o TF-Toolkit > Pacote de suporte)
# ---------------------------------------------------------------------------

function Copy-TFToolkitSharedFile {
    # Copia um arquivo que outro processo pode estar gravando (o log da janela aberta): lê com o compartilhamento total.
    param ([Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To)

    $folder = Split-Path -Parent $To
    if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop) }

    $source = New-Object System.IO.FileStream ($From, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))

    try {
        $target = [System.IO.File]::Create($To)
        try { $source.CopyTo($target) } finally { $target.Dispose() }
    }
    finally {
        $source.Dispose()
    }
}


function Get-TFToolkitSupportInfoText {
    # As versões, em texto, para quem vai ajudar: TF-Toolkit, Windows, PowerShell, .NET, idioma e se abriu como Administrador.
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $lines = New-Object System.Collections.Generic.List[string]
    $windows = ""
    $netRelease = ""

    try {
        $current = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        $windows = "$(Get-TFToolkitWindowsName -Caption ([string](Get-TFToolkitJsonValue -Object $current -Name 'ProductName' -Default '')) -Build (Get-TFToolkitWindowsBuild)) $(Get-TFToolkitWindowsDisplayVersion) (build $(Get-TFToolkitWindowsBuild).$([string](Get-TFToolkitJsonValue -Object $current -Name 'UBR' -Default '')))"
    }
    catch {
        $windows = "?"
    }

    try { $netRelease = [string](Get-TFToolkitRegistryValueOrNull -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -Name "Release") } catch { $netRelease = "" }

    $installed = $(try { if (Test-TFToolkitInstalledHere) { "yes" } else { "no" } } catch { "?" })

    # Em inglês e sem tradução: é para quem dá suporte, e o arquivo é o mesmo em qualquer idioma da tela.
    $lines.Add("TF-Toolkit Build $(Get-TFToolkitBuild)")
    $lines.Add("Created: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $culture))")
    $lines.Add("Folder: $(Get-TFToolkitAppRoot)")
    $lines.Add("Installed (Apps): $installed")
    $lines.Add("Language: $(Get-TFToolkitLanguage) (preference $(Get-TFToolkitLanguagePreference); Windows $([System.Globalization.CultureInfo]::CurrentUICulture.Name))")
    $lines.Add("Windows: $windows")
    $lines.Add("64-bit Windows: $([Environment]::Is64BitOperatingSystem); 64-bit process: $([Environment]::Is64BitProcess)")
    $lines.Add("PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))")
    $lines.Add(".NET Framework release: $netRelease")
    $lines.Add("Administrator: $(Test-TFToolkitAdministrator)")
    $lines.Add("Window: $(Test-TFToolkitGuiMode)")

    return ($lines -join "`r`n")
}


function New-TFToolkitSupportPackage {
    <#
    Junta num zip, na pasta Downloads, o que ajuda alguém a entender um problema do TF-Toolkit: as versões (info.txt), os
    logs mais recentes e o tempo de abertura, a verificação rápida do PC (check.json), o último relatório, o histórico de
    mudanças e de manutenção e as preferências. Não entram backups (que podem ter senhas de Wi-Fi), cópias de ajustes nem
    arquivos pessoais. Devolve um TFToolkit.Result.
    #>
    $title = (Get-TFToolkitText 'Pacote de suporte')

    Enter-TFToolkitAction -Title $title

    $final = $null
    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ("TF-Toolkit-support-{0}" -f [guid]::NewGuid().ToString("N"))

    try {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Junta num zip os logs, a verificação rápida do PC, o último relatório e as versões. Não leva backups, senhas nem arquivos pessoais.')
        Write-Host ""

        # Elevado com a conta de outro Administrador, a pasta Downloads seria a dessa conta.
        $folder = $(if (Test-TFToolkitUserContextMismatch) { Join-Path (Get-TFToolkitDataPath) "support" } else { Get-TFToolkitDownloadsPath })
        if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop) }

        [void](New-Item -ItemType Directory -Path $staging -Force -ErrorAction Stop)
        $data = Get-TFToolkitDataPath
        $included = @()

        Write-TFToolkitStatus -Type Running -Message (Get-TFToolkitText 'Lendo as versões e conferindo o PC...')
        [System.IO.File]::WriteAllText((Join-Path $staging "info.txt"), (Get-TFToolkitSupportInfoText), (New-Object System.Text.UTF8Encoding $true))
        $included += (Get-TFToolkitText 'versões')

        try {
            [System.IO.File]::WriteAllText((Join-Path $staging "check.json"), (ConvertTo-TFToolkitCheckJson -Report (Get-TFToolkitCheckReport)), (New-Object System.Text.UTF8Encoding $false))
            $included += (Get-TFToolkitText 'verificação rápida do PC')
        }
        catch {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A verificação rápida do PC ficou de fora: {0}' "$(([string]$_.Exception.Message).TrimEnd('.'))")
        }

        # Os 10 logs mais recentes, o tempo de abertura e as partes da janela que não puderam ser mostradas.
        $logs = Join-Path $data "logs"
        $logFiles = @()

        if (Test-Path -LiteralPath $logs -PathType Container) {
            $logFiles = @(Get-ChildItem -LiteralPath $logs -Filter "tf-toolkit-*.log" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10)
            $logFiles += @(Get-ChildItem -LiteralPath $logs -Filter "abertura.log" -File -ErrorAction SilentlyContinue)
            $logFiles += @(Get-ChildItem -LiteralPath $logs -Filter "janela.log" -File -ErrorAction SilentlyContinue)
        }

        # A linha "Leva" conta só o que foi copiado (um log em uso por outro programa fica de fora).
        $copied = 0

        foreach ($file in $logFiles) {
            try { Copy-TFToolkitSharedFile -From $file.FullName -To (Join-Path (Join-Path $staging "logs") $file.Name); $copied++ } catch { Write-Verbose "Log: $($_.Exception.Message)" }
        }

        if ($copied -gt 0) { $included += (Format-TFToolkitCount -Count $copied -One (Get-TFToolkitText 'log') -Many (Get-TFToolkitText 'logs')) }

        # O último relatório (HTML e texto), se houver.
        $reports = Join-Path $data "reports"

        if (Test-Path -LiteralPath $reports -PathType Container) {
            $latest = @(Get-ChildItem -LiteralPath $reports -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @(".html", ".txt") } | Sort-Object LastWriteTime -Descending | Select-Object -First 2)

            $copied = 0

            foreach ($file in $latest) {
                try { Copy-TFToolkitSharedFile -From $file.FullName -To (Join-Path (Join-Path $staging "report") $file.Name); $copied++ } catch { Write-Verbose "Relatório: $($_.Exception.Message)" }
            }

            if ($copied -gt 0) { $included += (Get-TFToolkitText 'último relatório') }
        }

        # Os históricos (mudanças e manutenções) e as preferências (as da janela e as do monitor), quando existem.
        $state = @{ History = $false; Settings = $false }

        foreach ($entry in @(
                @{ Path = (Get-TFToolkitChangeJournalPath); Kind = "History" },
                @{ Path = (Get-TFToolkitMaintenanceHistoryPath); Kind = "History" },
                @{ Path = (Get-TFToolkitSettingsPath); Kind = "Settings" },
                @{ Path = (Join-Path $data "agent.json"); Kind = "Settings" }
            )) {
            if (Test-Path -LiteralPath $entry.Path -PathType Leaf) {
                try { Copy-TFToolkitSharedFile -From $entry.Path -To (Join-Path (Join-Path $staging "state") (Split-Path -Leaf $entry.Path)); $state[$entry.Kind] = $true } catch { Write-Verbose "Estado: $($_.Exception.Message)" }
            }
        }

        if ($state.History) { $included += (Get-TFToolkitText 'históricos') }
        if ($state.Settings) { $included += (Get-TFToolkitText 'preferências') }

        $stamp = (Get-Date).ToString("yyyyMMdd-HHmm", [System.Globalization.CultureInfo]::InvariantCulture)
        $path = Join-Path $folder (Get-TFToolkitText 'TF-Toolkit-suporte-{0}.zip' "$stamp")

        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $path)

        Write-Host ""
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Pacote de suporte salvo: {0}' "$path")
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Leva') -Value (Join-TFToolkitList -Items $included)
        Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'Os logs mostram o nome do PC e caminhos de pastas; confira o zip antes de mandar.')

        $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'pacote salvo em {0}' "$path") -Title $title) `
            -Headline (Get-TFToolkitText 'Pacote de suporte salvo') -Note (Get-TFToolkitText '{0} está em {1}. Mande esse arquivo a quem vai ajudar.' "$(Split-Path -Leaf $path)" "$folder")

        if (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Mostrar o arquivo na pasta?') -DefaultKey S -YesLabel (Get-TFToolkitText 'Mostrar') -NoLabel (Get-TFToolkitText 'Agora não')) {
            try { Start-Process -FilePath "explorer.exe" -ArgumentList "/select,`"$path`"" -ErrorAction Stop } catch { Write-Verbose "Explorador: $($_.Exception.Message)" }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível criar o pacote de suporte: {0}' "$(([string]$_.Exception.Message).TrimEnd('.'))")
        $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail ([string]$_.Exception.Message).TrimEnd('.') -Title $title) `
            -Headline (Get-TFToolkitText 'O pacote de suporte não foi criado') -Note (Format-TFToolkitReasonNote -Text $_.Exception.Message)
    }
    finally {
        Remove-TFToolkitFolder -Path $staging -Quiet
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
