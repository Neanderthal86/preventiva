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
        foreach ($a in ($apps | Select-Object -First 35)) {
            $ver = if ($a.DisplayVersion) { "v$($a.DisplayVersion)" } else { "-" }
            $pub = if ($a.Publisher) { " · $($a.Publisher)" } else { "" }
            $items += [PSCustomObject]@{ Label = "$($a.DisplayName)"; Value = "$ver$pub" }
        }
        if ($apps.Count -gt 35) {
            $items += [PSCustomObject]@{ Label = "Demais programas"; Value = "+$($apps.Count - 35) aplicativos adicionais instalados" }
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
    $logoHtml = "<div class='brand-badge'>TF</div>"
    try {
        $logoFile = Join-Path (Split-Path -Parent $PSScriptRoot) "assets\logo.png"
        if (Test-Path -LiteralPath $logoFile -PathType Leaf) {
            $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($logoFile))
            $logoHtml = "<img class='brand-logo' src='data:image/png;base64,$b64' alt='Tech Fontes'/>"
        }
    } catch {}

    $nowText = Get-Date -Format "dd/MM/yyyy 'às' HH:mm"
    $hostName = & $encode $env:COMPUTERNAME
    $userName = & $encode $env:USERNAME
    $scoreBadge = ""
    if ($HealthScore -ge 0) {
        $scoreCls = if ($HealthScore -ge 85) { "ok" } elseif ($HealthScore -ge 65) { "warn" } else { "bad" }
        $scoreBadge = "<div class='score-box $scoreCls'><div class='score-num'>$HealthScore<span>/100</span></div><div class='score-lbl'>$(& $encode $HealthLabel)</div></div>"
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(@"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Relatório de Diagnóstico - $hostName - Tech Fontes</title>
<style>
  @page { size: A4; margin: 13mm 12mm; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: 'Segoe UI', Arial, sans-serif; color: #1a1d26; background: #ffffff; font-size: 11.5px; line-height: 1.45; }
  .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2.5px solid #C4613A; padding-bottom: 12px; margin-bottom: 16px; }
  .brand { display: flex; align-items: center; gap: 12px; }
  .brand-logo { width: 42px; height: 42px; object-fit: contain; }
  .brand-badge { width: 42px; height: 42px; border-radius: 8px; background: #C4613A; color: #fff; font-weight: 800; font-size: 18px; display: flex; align-items: center; justify-content: center; }
  .brand h1 { margin: 0; font-size: 20px; font-weight: 800; color: #1a1d26; }
  .brand h1 span { color: #C4613A; }
  .brand p { margin: 2px 0 0; font-size: 11px; color: #5a6275; }
  .score-box { text-align: right; padding: 8px 14px; border-radius: 8px; border: 1px solid #d5dae6; background: #f7f8fc; }
  .score-box.ok { border-color: #9ad4b3; background: #edf7f1; }
  .score-box.warn { border-color: #e8c78a; background: #fdf6e7; }
  .score-box.bad { border-color: #e5a3a3; background: #fdf0f0; }
  .score-num { font-size: 22px; font-weight: 800; line-height: 1.1; }
  .score-num span { font-size: 11px; font-weight: 600; color: #646b82; }
  .score-lbl { font-size: 10px; font-weight: 700; text-transform: uppercase; color: #3c4257; margin-top: 2px; }
  .meta-bar { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; background: #f5f7fb; border: 1px solid #e1e4ee; border-radius: 8px; padding: 10px 14px; margin-bottom: 16px; }
  .meta-item span { display: block; font-size: 9.5px; font-weight: 700; text-transform: uppercase; color: #646b82; }
  .meta-item strong { font-size: 12px; color: #1a1d26; }
  section { border: 1px solid #dfe3ed; border-radius: 8px; padding: 11px 14px; margin-bottom: 12px; break-inside: avoid; page-break-inside: avoid; }
  section h2 { margin: 0 0 8px; font-size: 13px; font-weight: 700; color: #C4613A; border-bottom: 1px solid #eef0f6; padding-bottom: 5px; display: flex; justify-content: space-between; }
  section h2 span { font-size: 10px; font-weight: 600; color: #646b82; background: #f2f4f8; padding: 1px 7px; border-radius: 99px; }
  table { width: 100%; border-collapse: collapse; }
  tr { border-bottom: 1px dashed #eceff5; }
  tr:last-child { border-bottom: none; }
  td { padding: 4px 4px; vertical-align: top; }
  td.k { width: 34%; font-weight: 600; color: #4d5568; padding-right: 10px; }
  td.v { color: #1a1d26; word-break: break-word; }
  .footer { margin-top: 18px; padding-top: 10px; border-top: 1px solid #dfe3ed; display: flex; justify-content: space-between; font-size: 10px; color: #646b82; }
</style>
</head>
<body>
  <div class="header">
    <div class="brand">
      $logoHtml
      <div>
        <h1>Tech <span>Fontes</span> · Relatório de Diagnóstico</h1>
        <p>TF-Toolkit v$(& $encode $Build) · Levantamento Técnico Completo para Análise</p>
      </div>
    </div>
    $scoreBadge
  </div>

  <div class="meta-bar">
    <div class="meta-item"><span>Estação</span><strong>$hostName</strong></div>
    <div class="meta-item"><span>Usuário</span><strong>$userName</strong></div>
    <div class="meta-item"><span>Data / Hora</span><strong>$nowText</strong></div>
    <div class="meta-item"><span>Seções Coletadas</span><strong>$($Sections.Count)</strong></div>
  </div>
"@)

    foreach ($sec in $Sections) {
        if (-not $sec.Items -or $sec.Items.Count -eq 0) { continue }
        [void]$sb.AppendLine("<section><h2>$(& $encode $sec.Title)<span>$($sec.Items.Count)</span></h2><table>")
        foreach ($it in $sec.Items) {
            [void]$sb.AppendLine("<tr><td class='k'>$(& $encode $it.Label)</td><td class='v'>$(& $encode $it.Value)</td></tr>")
        }
        [void]$sb.AppendLine("</table></section>")
    }

    [void]$sb.AppendLine(@"
  <div class="footer">
    <div>Tech Fontes · techfontes.com.br · fontes@techfontes.com.br</div>
    <div>Relatório gerado automaticamente pelo TF-Toolkit v$(& $encode $Build) em $nowText</div>
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
