# Reporting.psm1

# Variáveis Globais do Relatório
function Reset-PreventivaReportState {
    $global:Report = [ordered]@{
        Inventario    = @()
        Disco         = @()
        Servicos      = @()
        Limpeza       = @()
        Startup       = @()
        Drivers       = @()
        Seguranca     = @()
        Performance   = @()
        Otimizacao    = @()
        Software      = @()
        Varredura     = @()
        WindowsUpdate = @()
        Integridade   = @()
        Recovery      = @()
        Alertas       = @()
    }
}

Reset-PreventivaReportState

$global:PreventivaLogFile = ""
$global:PreventivaTranscript = ""
$global:PreventivaReportFile = ""
$global:PreventivaJsonFile = ""

function Initialize-PreventivaReporting {
    param([string]$BaseLogDir, [string]$Mode, [string]$SubModo)
    
    Reset-PreventivaReportState
    New-Item -ItemType Directory -Path $BaseLogDir -Force | Out-Null
    $Data = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $global:PreventivaLogFile = Join-Path $BaseLogDir "Preventiva_$Mode`_$SubModo`_$Data.log"
    $global:PreventivaTranscript = Join-Path $BaseLogDir "Transcript_$Mode`_$SubModo`_$Data.txt"
    $global:PreventivaReportFile = Join-Path $BaseLogDir "Relatorio_$Mode`_$SubModo`_$Data.html"
    $global:PreventivaJsonFile   = Join-Path $BaseLogDir "Relatorio_$Mode`_$SubModo`_$Data.json"
    
    try { Start-Transcript -Path $global:PreventivaTranscript -Force | Out-Null } catch {}
    Write-PreventivaLog "======================================"
    Write-PreventivaLog "INÍCIO PREVENTIVA - TECH FONTES"
    Write-PreventivaLog "Modo: $Mode | SubModo: $SubModo"
    Write-PreventivaLog "======================================"
}

function Write-PreventivaLog {
    param([string]$Mensagem, [string]$Secao = $null)
    $Linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Mensagem"
    if ($global:PreventivaLogFile) {
        $Linha | Tee-Object -FilePath $global:PreventivaLogFile -Append
    } else {
        Write-Output $Linha
    }
    if ($Secao -and $global:Report -and $global:Report.Contains($Secao)) {
        $global:Report[$Secao] += $Mensagem
    }
}

function Write-PreventivaAlerta {
    param([string]$Mensagem)
    Write-PreventivaLog "[ALERTA] $Mensagem" -Secao "Alertas"
}

function Finalize-PreventivaReporting {
    param([string]$Mode, [bool]$ExecutarAcoes, [string]$AntivirusTexto, [bool]$PendingReboot, [double]$EspacoAntes, [double]$EspacoDepois, [string]$WebhookUrl = "", [bool]$SendWebhookOnlyOnAlerts = $true)
    
    # Gerar JSON para Integrações
    try {
        $JsonData = @{
            Mode = $Mode
            IsExecucao = $ExecutarAcoes
            Date = (Get-Date)
            Host = $env:COMPUTERNAME
            Alertas = $global:Report.Alertas
            EspacoAntesGB = $EspacoAntes
            EspacoDepoisGB = $EspacoDepois
            Antivirus = $AntivirusTexto
            RebootPendente = $PendingReboot
        }
        $JsonString = $JsonData | ConvertTo-Json -Depth 4
        $JsonString | Out-File $global:PreventivaJsonFile -Encoding UTF8
        Write-Host "Relatório JSON exportado para $global:PreventivaJsonFile"

        if ($WebhookUrl) {
            $temAlertas = ($global:Report.Alertas.Count -gt 0)
            if (-not $SendWebhookOnlyOnAlerts -or $temAlertas) {
                Write-PreventivaLog "Enviando dados JSON via Webhook..." -Secao "Alertas"
                Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $JsonString -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } catch {}

    # Gerar HTML
    try {
        New-HtmlReport -ReportData $global:Report -OutFile $global:PreventivaReportFile `
            -Mode $Mode -ExecutarAcoes $ExecutarAcoes `
            -AntivirusTexto $AntivirusTexto -PendingReboot $PendingReboot `
            -EspacoAntes $EspacoAntes -EspacoDepois $EspacoDepois
        Write-Host "Relatório HTML gerado em: $global:PreventivaReportFile"
    } catch {
        Write-Host "Falha ao gerar relatório HTML: $_"
    }
    
    Write-PreventivaLog "FINALIZADO"
    try { Stop-Transcript | Out-Null } catch {}
}

function New-HtmlReport {
    param($ReportData, $OutFile, $Mode, $ExecutarAcoes, $AntivirusTexto, $PendingReboot, $EspacoAntes, $EspacoDepois)

    $secaoConfig = [ordered]@{
        Inventario    = @{ Titulo = "Inventário da Máquina";     Icone = "&#128421;" }
        Disco         = @{ Titulo = "Disco e Armazenamento";     Icone = "&#128190;" }
        Servicos      = @{ Titulo = "Serviços Críticos";         Icone = "&#9881;"   }
        Limpeza       = @{ Titulo = "Limpeza e Manutenção";      Icone = "&#129529;" }
        Startup       = @{ Titulo = "Itens de Inicialização";    Icone = "&#9203;"   }
        Drivers       = @{ Titulo = "Drivers e Dispositivos";    Icone = "&#128268;" }
        Seguranca     = @{ Titulo = "Segurança (Antivírus)";     Icone = "&#128737;" }
        Performance   = @{ Titulo = "Performance (SSD/WinSxS)";  Icone = "&#9889;"   }
        Otimizacao    = @{ Titulo = "Otimização (Tweaks)";       Icone = "&#128640;" }
        Software      = @{ Titulo = "Softwares (Winget)";        Icone = "&#128230;" }
        Varredura     = @{ Titulo = "Varredura de Espaço";       Icone = "&#128269;" }
        WindowsUpdate = @{ Titulo = "Windows Update";            Icone = "&#128260;" }
        Integridade   = @{ Titulo = "Integridade do Sistema";    Icone = "&#10003;"  }
        Recovery      = @{ Titulo = "Recovery / Emergência";     Icone = "&#128680;" }
    }

    $BadgeSubModoTexto = if ($ExecutarAcoes) { "Execução Completa" } else { "Diagnóstico (somente leitura)" }
    $BadgeSubModoCor   = if ($ExecutarAcoes) { "" } else { "info" }
    $BannerDiagnostico = ""
    if (-not $ExecutarAcoes) {
        $BannerDiagnostico = "<div class='alertas info'><h2>&#128269; Modo Diagnóstico</h2><p>Esta execução só leu e analisou o sistema. Nenhuma alteração foi feita.</p></div>"
    }

    $qtdAlertas = $ReportData.Alertas.Count
    $statusGeral = if ($qtdAlertas -eq 0) { "Sistema OK" } else { "Requer Atenção" }
    $statusCor   = if ($qtdAlertas -eq 0) { "ok" } else { "alerta" }
    $rebootTexto = if ($PendingReboot) { "Pendente" } else { "Não necessário" }
    $rebootCor   = if ($PendingReboot) { "alerta" } else { "ok" }
    $avCor       = if ($AntivirusTexto -match "terceiro") { "info" } elseif ($AntivirusTexto -match "Nenhum|Falha") { "alerta" } else { "ok" }

    $cardsHtml = @"
    <div class="cards">
      <div class="card $statusCor">
        <div class="card-label">Status Geral</div>
        <div class="card-value">$statusGeral</div>
      </div>
      <div class="card">
        <div class="card-label">Espaço em Disco</div>
        <div class="card-value">$EspacoDepois GB</div>
        <div class="card-sub">antes: $EspacoAntes GB</div>
      </div>
      <div class="card $avCor">
        <div class="card-label">Antivírus</div>
        <div class="card-value-sm">$AntivirusTexto</div>
      </div>
      <div class="card $rebootCor">
        <div class="card-label">Reinicialização</div>
        <div class="card-value-sm">$rebootTexto</div>
      </div>
    </div>
"@

    $alertasHtml = ""
    if ($qtdAlertas -gt 0) {
        $itens = ($ReportData.Alertas | ForEach-Object { "<li>$_</li>" }) -join "`n"
        $alertasHtml = "<div class='alertas'><h2>&#9888; Pontos de Atenção ($qtdAlertas)</h2><ul>$itens</ul></div>"
    } else {
        $alertasHtml = "<div class='alertas ok'><h2>&#9989; Pontos de Atenção</h2><p>Nenhum alerta identificado.</p></div>"
    }

    $secoesHtml = ""
    foreach ($key in $secaoConfig.Keys) {
        $linhas = $ReportData[$key]
        if ($linhas -and $linhas.Count -gt 0) {
            $cfg = $secaoConfig[$key]
            $itens = ($linhas | ForEach-Object { "<li>$_</li>" }) -join "`n"
            $secoesHtml += "<div class='secao'><h2><span class='icone'>$($cfg.Icone)</span>$($cfg.Titulo)</h2><ul>$itens</ul></div>`n"
        }
    }

    $Data = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Relatório de Preventiva - Tech Fontes</title>
<style>
  * { box-sizing:border-box; }
  body {
    background:#1a1a1f; color:#e8e8ea; font-family:'Segoe UI',Arial,sans-serif; margin:0; padding:0 0 60px 0;
  }
  .container { max-width:980px; margin:0 auto; padding:0 24px; }
  .topbar { background:#111114; border-bottom:1px solid #2a2a30; padding:18px 24px; margin-bottom:32px; }
  .topbar-inner { max-width:980px; margin:0 auto; display:flex; align-items:center; justify-content:space-between; }
  .logo { font-style:italic; font-weight:800; font-size:20px; color:#ffffff; }
  .logo .accent { color:#C4613A; }
  .header { padding-top:8px; margin-bottom:28px; }
  .header h1 { font-style:italic; font-weight:700; font-size:24px; margin:0 0 10px 0; color:#ffffff; }
  .badge { display:inline-block; background:#3D5270; color:#fff; padding:5px 16px; border-radius:20px; font-size:12px; font-weight:700; margin-top:8px; margin-right:8px; }
  .badge.info { background:#5a7ba8; }
  .cards { display:grid; grid-template-columns:repeat(4, 1fr); gap:14px; margin-bottom:28px; }
  .card { background:#212127; border:1px solid #2c2c33; border-radius:10px; padding:16px 18px; border-top:3px solid #3D5270; }
  .card.ok { border-top-color:#4a7a5c; }
  .card.alerta { border-top-color:#C4613A; }
  .card.info { border-top-color:#5a7ba8; }
  .card-label { font-size:11px; text-transform:uppercase; color:#8a8a92; margin-bottom:8px; }
  .card-value { font-size:22px; font-weight:700; color:#ffffff; }
  .card-value-sm { font-size:14px; font-weight:600; color:#ffffff; }
  .alertas { background:#2b1f1a; border:1px solid #4a3226; border-radius:10px; padding:18px 22px; margin-bottom:24px; }
  .alertas.ok { border-color:#26332c; background:#1a2420; }
  .alertas.info { border-color:#2c3a4a; background:#1a2430; }
  .alertas h2 { color:#e0a184; font-size:15px; margin:0 0 12px 0; font-weight:700; }
  .alertas.ok h2 { color:#7fb894; }
  .alertas ul { margin:0; padding-left:20px; font-size:13px; color:#f0d5c8; line-height:1.8; }
  .grid { display:grid; grid-template-columns:1fr 1fr; gap:16px; }
  .secao { background:#212127; border:1px solid #2c2c33; border-radius:10px; padding:18px 22px; margin-bottom:0; }
  .secao h2 { font-size:14px; color:#ffffff; margin:0 0 12px 0; border-bottom:1px solid #2c2c33; padding-bottom:10px; }
  .secao ul { margin:0; padding-left:18px; font-size:12.5px; line-height:1.7; color:#c5c5cc; }
  .footer { margin-top:40px; padding-top:20px; border-top:1px solid #2a2a30; color:#5a5a62; font-size:11px; text-align:center; }
  @media (max-width: 700px) { .cards { grid-template-columns:1fr 1fr; } .grid { grid-template-columns:1fr; } }
</style>
</head>
<body>
  <div class="topbar">
    <div class="topbar-inner">
      <div class="logo">Tech<span class="accent">Fontes</span></div>
    </div>
  </div>
  <div class="container">
    <div class="header">
      <h1>Relatório de Manutenção Preventiva</h1>
      <div class="badge">Modo: $Mode</div>
      <div class="badge $BadgeSubModoCor">$BadgeSubModoTexto</div>
    </div>
    $BannerDiagnostico
    $cardsHtml
    $alertasHtml
    <div class="grid">$secoesHtml</div>
    <div class="footer">Gerado pela Preventiva Corporativa &middot; Tech Fontes</div>
  </div>
</body>
</html>
"@
    $html | Out-File -FilePath $OutFile -Encoding UTF8
}

Export-ModuleMember -Function Initialize-PreventivaReporting, Write-PreventivaLog, Write-PreventivaAlerta, Finalize-PreventivaReporting
