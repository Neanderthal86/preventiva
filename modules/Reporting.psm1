# ============================================
# Reporting.psm1 - Relatorio Executivo HTML (Auto/Claro/Escuro) + JSON + Webhook
# ============================================

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

$global:PreventivaLogFile    = ""
$global:PreventivaTranscript = ""
$global:PreventivaReportFile = ""
$global:PreventivaJsonFile   = ""

function Initialize-PreventivaReporting {
    param([string]$BaseLogDir, [string]$Mode, [string]$SubModo)

    Reset-PreventivaReportState
    New-Item -ItemType Directory -Path $BaseLogDir -Force | Out-Null
    $Data = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $global:PreventivaLogFile    = Join-Path $BaseLogDir "Preventiva_$Mode`_$SubModo`_$Data.log"
    $global:PreventivaTranscript = Join-Path $BaseLogDir "Transcript_$Mode`_$SubModo`_$Data.txt"
    $global:PreventivaReportFile = Join-Path $BaseLogDir "Relatorio_$Mode`_$SubModo`_$Data.html"
    $global:PreventivaJsonFile   = Join-Path $BaseLogDir "Relatorio_$Mode`_$SubModo`_$Data.json"

    try { Start-Transcript -Path $global:PreventivaTranscript -Force | Out-Null } catch {}
    Write-PreventivaLog "======================================"
    Write-PreventivaLog "INICIO PREVENTIVA - TECH FONTES"
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

function Get-PreventivaHealthScore {
    param([array]$Alertas, [string]$AntivirusTexto, [bool]$PendingReboot)
    $score = 100
    foreach ($a in $Alertas) {
        if ($a -match 'Disco .* com sa')          { $score -= 30 }
        elseif ($a -match 'Nenhum antiv')         { $score -= 25 }
        elseif ($a -match 'Firewall.*DESATIVADO') { $score -= 20 }
        elseif ($a -match 'BSOD|Queda de energia'){ $score -= 15 }
        elseif ($a -match 'Espa.*abaixo')         { $score -= 15 }
        elseif ($a -match 'RDP \(3389\)')         { $score -= 10 }
        elseif ($a -match 'Bateria com sa')       { $score -= 10 }
        elseif ($a -match 'ativado')              { $score -= 10 }
        elseif ($a -match 'BitLocker')            { $score -= 5  }
        else                                      { $score -= 5  }
    }
    if ($AntivirusTexto -match 'Nenhum|Falha') { $score -= 15 }
    if ($PendingReboot) { $score -= 3 }
    if ($score -lt 0) { $score = 0 }

    $grade = if ($score -ge 90) { "Excelente" } elseif ($score -ge 75) { "Bom" } elseif ($score -ge 50) { "Atenção" } else { "Crítico" }
    $css   = if ($score -ge 90) { "ok" } elseif ($score -ge 75) { "info" } else { "alerta" }
    return [PSCustomObject]@{ Score = $score; Grade = $grade; Css = $css }
}

function Finalize-PreventivaReporting {
    param(
        [string]$Mode,
        [bool]$ExecutarAcoes,
        [string]$AntivirusTexto,
        [bool]$PendingReboot,
        [double]$EspacoAntes,
        [double]$EspacoDepois,
        [string]$WebhookUrl = "",
        [bool]$SendWebhookOnlyOnAlerts = $true
    )

    $health = Get-PreventivaHealthScore -Alertas $global:Report.Alertas -AntivirusTexto $AntivirusTexto -PendingReboot $PendingReboot

    # Gerar JSON para Integracoes
    try {
        $JsonData = @{
            Mode           = $Mode
            IsExecucao     = $ExecutarAcoes
            Date           = (Get-Date)
            Host           = $env:COMPUTERNAME
            HealthScore    = $health.Score
            HealthGrade    = $health.Grade
            Alertas        = $global:Report.Alertas
            EspacoAntesGB  = $EspacoAntes
            EspacoDepoisGB = $EspacoDepois
            Antivirus      = $AntivirusTexto
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

    # Gerar HTML Executivo
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

function ConvertTo-SafeHtml([string]$Text) {
    if ($null -eq $Text) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Format-ReportLineHtml([string]$Line) {
    $safe = ConvertTo-SafeHtml $Line
    # Destaca pares "Chave: Valor" (ignorando caminhos tipo C:\...)
    if ($Line -match '^([^:]{2,42}?)\s*:\s+(.+)$' -and $matches[1] -notmatch '^[A-Za-z]$') {
        $k = ConvertTo-SafeHtml ($matches[1].Trim())
        $vRaw = $matches[2].Trim()
        $v = ConvertTo-SafeHtml $vRaw

        $pillClass = ""
        if ($vRaw -match '^(Running|OK|Healthy|Ativo|Ativado|Desativado|Visíveis|Aplicado)\b' -or $vRaw -match 'sucesso|concluíd') {
            $pillClass = "val-ok"
        } elseif ($vRaw -match '^(Stopped|Error|Degraded|Unhealthy|Falha|NÃO)\b') {
            $pillClass = "val-warn"
        }
        return "<li class='kv-item'><span class='kv-key'>$k</span><span class='kv-val $pillClass'>$v</span></li>"
    }
    return "<li class='plain-item'>$safe</li>"
}

function New-HtmlReport {
    param($ReportData, $OutFile, $Mode, $ExecutarAcoes, $AntivirusTexto, $PendingReboot, $EspacoAntes, $EspacoDepois)

    # Tenta embutir Assets\logo.png em Base64 para relatorio 100% portatil
    $logoHtml = "<div class='brand-mark'>TF</div>"
    try {
        $logoCandidate = Join-Path $PSScriptRoot "..\assets\logo.png"
        if (Test-Path -LiteralPath $logoCandidate) {
            $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($logoCandidate))
            $logoHtml = "<img class='brand-logo' src='data:image/png;base64,$b64' alt='Tech Fontes'/>"
        }
    } catch {}

    $secaoConfig = [ordered]@{
        Inventario    = @{ Titulo = "Inventário da Máquina";     Icone = "&#128421;" }
        Disco         = @{ Titulo = "Disco e Armazenamento";     Icone = "&#128190;" }
        Servicos      = @{ Titulo = "Serviços Críticos";         Icone = "&#9881;"   }
        Limpeza       = @{ Titulo = "Limpeza e Manutenção";      Icone = "&#129529;" }
        Otimizacao    = @{ Titulo = "Otimização (Tweaks)";       Icone = "&#128640;" }
        Software      = @{ Titulo = "Softwares (Winget)";        Icone = "&#128230;" }
        Seguranca     = @{ Titulo = "Segurança & Auditoria";     Icone = "&#128737;" }
        Startup       = @{ Titulo = "Itens de Inicialização";    Icone = "&#9203;"   }
        Drivers       = @{ Titulo = "Drivers e Dispositivos";    Icone = "&#128268;" }
        Performance   = @{ Titulo = "Performance (SSD/WinSxS)";  Icone = "&#9889;"   }
        Varredura     = @{ Titulo = "Varredura de Espaço";       Icone = "&#128269;" }
        WindowsUpdate = @{ Titulo = "Windows Update";            Icone = "&#128260;" }
        Integridade   = @{ Titulo = "Integridade do Sistema";    Icone = "&#10003;"  }
        Recovery      = @{ Titulo = "Recovery / Emergência";     Icone = "&#128680;" }
    }

    $dataFormatada     = Get-Date -Format "dd/MM/yyyy 'às' HH:mm"
    $hostSeguro        = ConvertTo-SafeHtml $env:COMPUTERNAME
    $modeSeguro        = ConvertTo-SafeHtml $Mode
    $avSeguro          = ConvertTo-SafeHtml $AntivirusTexto
    $BadgeSubModoTexto = if ($ExecutarAcoes) { "Execução Completa" } else { "Diagnóstico (Somente Leitura)" }
    $BadgeSubModoCor   = if ($ExecutarAcoes) { "exec" } else { "diag" }

    $BannerDiagnostico = ""
    if (-not $ExecutarAcoes) {
        $BannerDiagnostico = "<div class='banner-info'><strong>&#128269; Modo Diagnóstico:</strong> Esta execução realizou apenas leitura e auditoria. Nenhuma alteração ou remoção foi aplicada ao sistema.</div>"
    }

    $qtdAlertas  = $ReportData.Alertas.Count
    $health      = Get-PreventivaHealthScore -Alertas $ReportData.Alertas -AntivirusTexto $AntivirusTexto -PendingReboot $PendingReboot
    $statusGeral = "$($health.Score) / 100"
    $statusSub   = "$($health.Grade) &middot; " + $(if ($qtdAlertas -eq 0) { "0 alertas" } else { "$qtdAlertas alerta(s)" })
    $statusCor   = $health.Css

    $deltaGB     = [math]::Round(($EspacoDepois - $EspacoAntes), 2)
    $deltaTexto  = if ($deltaGB -gt 0) { "+$deltaGB GB liberados (antes: $EspacoAntes GB)" } elseif ($EspacoAntes -gt 0) { "antes: $EspacoAntes GB" } else { "unidade C:" }
    $deltaCor    = if ($deltaGB -gt 0) { "ok" } else { "neutral" }

    $rebootTexto = if ($PendingReboot) { "Pendente" } else { "Não necessária" }
    $rebootSub   = if ($PendingReboot) { "Recomenda-se reiniciar a estação" } else { "Sistema sem pendências" }
    $rebootCor   = if ($PendingReboot) { "alerta" } else { "ok" }
    $avCor       = if ($AntivirusTexto -match "terceiro") { "info" } elseif ($AntivirusTexto -match "Nenhum|Falha") { "alerta" } else { "ok" }

    $alertasHtml = ""
    if ($qtdAlertas -gt 0) {
        $itens = ($ReportData.Alertas | ForEach-Object { "<li>$(ConvertTo-SafeHtml $_)</li>" }) -join "`n"
        $alertasHtml = @"
        <section class="alert-box warn">
            <div class="alert-head">
                <h2>&#9888; Pontos de Atenção</h2>
                <span class="pill warn">$qtdAlertas</span>
            </div>
            <ul>$itens</ul>
        </section>
"@
    } else {
        $alertasHtml = @"
        <section class="alert-box ok">
            <div class="alert-head">
                <h2>&#9989; Pontos de Atenção</h2>
                <span class="pill ok">Tudo certo</span>
            </div>
            <p>Nenhum alerta crítico foi identificado durante esta execução.</p>
        </section>
"@
    }

    $secoesHtml = ""
    $totalSecoes = 0
    foreach ($key in $secaoConfig.Keys) {
        $linhas = $ReportData[$key]
        if ($linhas -and $linhas.Count -gt 0) {
            $totalSecoes++
            $cfg = $secaoConfig[$key]
            $itens = ($linhas | ForEach-Object { Format-ReportLineHtml $_ }) -join "`n"
            $secoesHtml += @"
            <article class="secao" data-section="$($cfg.Titulo.ToLower())">
                <div class="secao-head">
                    <h2><span class="icone">$($cfg.Icone)</span>$($cfg.Titulo)</h2>
                    <span class="count-pill">$($linhas.Count)</span>
                </div>
                <ul class="kv-list">$itens</ul>
            </article>
"@
        }
    }

    if ($totalSecoes -eq 0) {
        $secoesHtml = "<article class='secao'><div class='secao-head'><h2>Resumo</h2></div><p class='empty-msg'>Nenhum detalhe adicional registrado nesta execução.</p></article>"
    }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR" data-theme="auto">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Relatório de Preventiva &middot; $hostSeguro &middot; Tech Fontes</title>
<style>
  :root {
    --bg: #f4f5f8;
    --surface: #ffffff;
    --surface-sub: #f7f8fc;
    --border: #e1e4ee;
    --border-strong: #cfd4e2;
    --text: #1a1d26;
    --text-sec: #3c4257;
    --muted: #646b82;
    --accent: #C4613A;
    --blue: #3D5270;
    --ok: #236b43;
    --ok-bg: #edf7f1;
    --ok-border: #a7d9bc;
    --warn: #b34722;
    --warn-bg: #fdf3ee;
    --warn-border: #ebc0ad;
    --info: #2d5a8c;
    --info-bg: #eef4fb;
    --info-border: #b8d1ec;
    --shadow: 0 2px 10px rgba(18, 22, 33, 0.05);
  }

  [data-theme="dark"] {
    --bg: #13141a;
    --surface: #1c1d26;
    --surface-sub: #16171f;
    --border: #2b2d3b;
    --border-strong: #3a3d50;
    --text: #f0f1f6;
    --text-sec: #c9cde0;
    --muted: #8c91a8;
    --accent: #C4613A;
    --blue: #5c7ea8;
    --ok: #6fd19a;
    --ok-bg: #17261f;
    --ok-border: #2a4d3b;
    --warn: #ee9b78;
    --warn-bg: #291d18;
    --warn-border: #593527;
    --info: #8cb7e8;
    --info-bg: #182330;
    --info-border: #2b425c;
    --shadow: 0 4px 16px rgba(0, 0, 0, 0.25);
  }

  * { box-sizing: border-box; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    margin: 0;
    padding: 0 0 64px 0;
    transition: background 0.2s ease, color 0.2s ease;
  }

  .topbar {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    position: sticky;
    top: 0;
    z-index: 20;
    padding: 12px 24px;
  }
  .topbar-inner {
    max-width: 1080px;
    margin: 0 auto;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .brand-logo { width: 34px; height: 34px; object-fit: contain; }
  .brand-mark {
    width: 34px; height: 34px; border-radius: 8px;
    background: var(--accent); color: #fff; font-weight: 800; font-size: 14px;
    display: flex; align-items: center; justify-content: center;
  }
  .brand-name { font-size: 18px; font-weight: 800; letter-spacing: -0.3px; }
  .brand-name span { color: var(--accent); }
  .brand-sub { font-size: 11px; color: var(--muted); display: block; margin-top: -2px; }

  .toolbar { display: flex; align-items: center; gap: 8px; }
  .btn {
    background: var(--surface-sub);
    color: var(--text);
    border: 1px solid var(--border-strong);
    border-radius: 999px;
    padding: 6px 14px;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    transition: all 0.15s ease;
  }
  .btn:hover { border-color: var(--accent); }
  .btn-primary {
    background: var(--accent);
    border-color: var(--accent);
    color: #fff;
  }
  .btn-primary:hover { opacity: 0.92; }

  .container { max-width: 1080px; margin: 0 auto; padding: 28px 24px 0 24px; }

  .hero {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: flex-end;
    gap: 16px;
    margin-bottom: 24px;
  }
  .hero h1 { font-size: 26px; font-weight: 800; margin: 0 0 6px 0; letter-spacing: -0.4px; }
  .hero-meta { font-size: 13px; color: var(--muted); display: flex; flex-wrap: wrap; gap: 14px; }
  .hero-meta strong { color: var(--text); }
  .badges { display: flex; flex-wrap: wrap; gap: 8px; }
  .badge {
    padding: 5px 13px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 700;
    background: var(--surface);
    border: 1px solid var(--border-strong);
    color: var(--text);
  }
  .badge.exec { background: var(--accent); border-color: var(--accent); color: #fff; }
  .badge.diag { background: var(--info-bg); border-color: var(--info-border); color: var(--info); }

  .banner-info {
    background: var(--info-bg);
    border: 1px solid var(--info-border);
    color: var(--info);
    border-radius: 10px;
    padding: 13px 18px;
    font-size: 13px;
    margin-bottom: 22px;
  }

  .cards {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 14px;
    margin-bottom: 22px;
  }
  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-top: 3px solid var(--blue);
    border-radius: 12px;
    padding: 16px 18px;
    box-shadow: var(--shadow);
  }
  .card.ok { border-top-color: var(--ok); }
  .card.alerta { border-top-color: var(--accent); }
  .card.info { border-top-color: var(--info); }
  .card-label { font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.6px; color: var(--muted); margin-bottom: 8px; }
  .card-value { font-size: 21px; font-weight: 800; color: var(--text); line-height: 1.2; }
  .card-value-sm { font-size: 15px; font-weight: 700; color: var(--text); line-height: 1.3; }
  .card-sub { font-size: 11.5px; color: var(--muted); margin-top: 6px; }
  .card-sub.ok { color: var(--ok); font-weight: 600; }

  .alert-box {
    border-radius: 12px;
    padding: 16px 20px;
    margin-bottom: 22px;
    border: 1px solid var(--border);
  }
  .alert-box.warn { background: var(--warn-bg); border-color: var(--warn-border); }
  .alert-box.ok { background: var(--ok-bg); border-color: var(--ok-border); }
  .alert-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; }
  .alert-head h2 { font-size: 15px; margin: 0; font-weight: 700; }
  .alert-box.warn h2 { color: var(--warn); }
  .alert-box.ok h2 { color: var(--ok); }
  .alert-box p { margin: 0; font-size: 13px; color: var(--text-sec); }
  .alert-box ul { margin: 6px 0 0 0; padding-left: 20px; font-size: 13px; line-height: 1.75; color: var(--text); }

  .pill { font-size: 11px; font-weight: 700; padding: 3px 10px; border-radius: 999px; }
  .pill.warn { background: var(--accent); color: #fff; }
  .pill.ok { background: var(--ok); color: #fff; }

  .filter-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 16px;
  }
  .filter-input {
    width: 100%;
    max-width: 360px;
    background: var(--surface);
    color: var(--text);
    border: 1px solid var(--border-strong);
    border-radius: 8px;
    padding: 9px 14px;
    font-size: 13px;
    outline: none;
  }
  .filter-input:focus { border-color: var(--accent); }
  .filter-hint { font-size: 12px; color: var(--muted); }

  .grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 16px;
  }
  .secao {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 16px 18px;
    box-shadow: var(--shadow);
  }
  .secao-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    border-bottom: 1px solid var(--border);
    padding-bottom: 10px;
    margin-bottom: 12px;
  }
  .secao-head h2 {
    font-size: 14px;
    font-weight: 700;
    margin: 0;
    color: var(--text);
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .count-pill {
    font-size: 11px;
    font-weight: 700;
    background: var(--surface-sub);
    border: 1px solid var(--border);
    color: var(--muted);
    padding: 2px 9px;
    border-radius: 999px;
  }

  .kv-list { list-style: none; margin: 0; padding: 0; }
  .kv-item {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 12px;
    padding: 6px 0;
    border-bottom: 1px dashed var(--border);
    font-size: 12.5px;
  }
  .kv-item:last-child, .plain-item:last-child { border-bottom: none; }
  .kv-key { color: var(--muted); font-weight: 600; flex-shrink: 0; }
  .kv-val { color: var(--text); text-align: right; word-break: break-word; font-weight: 500; }
  .kv-val.val-ok { color: var(--ok); font-weight: 700; }
  .kv-val.val-warn { color: var(--warn); font-weight: 700; }
  .plain-item {
    padding: 6px 0;
    border-bottom: 1px dashed var(--border);
    font-size: 12.5px;
    color: var(--text-sec);
    line-height: 1.5;
    word-break: break-word;
  }
  .empty-msg { font-size: 13px; color: var(--muted); margin: 0; }

  .footer {
    margin-top: 38px;
    padding-top: 18px;
    border-top: 1px solid var(--border);
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    gap: 10px;
    font-size: 12px;
    color: var(--muted);
  }
  .footer a { color: var(--accent); text-decoration: none; font-weight: 600; }

  @media (max-width: 820px) {
    .cards { grid-template-columns: repeat(2, 1fr); }
    .grid { grid-template-columns: 1fr; }
  }
  @media print {
    :root, [data-theme="dark"] {
      --bg: #ffffff; --surface: #ffffff; --surface-sub: #f7f8fc;
      --border: #d8dce6; --text: #111111; --text-sec: #333333; --muted: #555555; --shadow: none;
    }
    .topbar { position: static; }
    .toolbar, .filter-bar { display: none !important; }
    .secao, .card, .alert-box { break-inside: avoid; }
    body { padding-bottom: 0; }
  }
</style>
</head>
<body>
  <header class="topbar">
    <div class="topbar-inner">
      <div class="brand">
        $logoHtml
        <div>
          <div class="brand-name">Tech <span>Fontes</span></div>
          <span class="brand-sub">TF-Toolkit &middot; Relatório de Preventiva Windows</span>
        </div>
      </div>
      <div class="toolbar">
        <button id="themeBtn" class="btn" type="button" title="Alternar tema: Auto, Claro ou Escuro">
          <span id="themeIcon">&#9680;</span>
          <span id="themeLabel">Auto</span>
        </button>
        <button class="btn btn-primary" type="button" onclick="window.print()">&#128424; Imprimir / PDF</button>
      </div>
    </div>
  </header>

  <main class="container">
    <section class="hero">
      <div>
        <h1>Relatório de Manutenção Preventiva</h1>
        <div class="hero-meta">
          <span>Estação: <strong>$hostSeguro</strong></span>
          <span>Data: <strong>$dataFormatada</strong></span>
          <span>Seções registradas: <strong>$totalSecoes</strong></span>
        </div>
      </div>
      <div class="badges">
        <span class="badge">Modo: $modeSeguro</span>
        <span class="badge $BadgeSubModoCor">$BadgeSubModoTexto</span>
      </div>
    </section>

    $BannerDiagnostico

    <section class="cards">
      <div class="card $statusCor">
        <div class="card-label">Índice de Saúde</div>
        <div class="card-value">$statusGeral</div>
        <div class="card-sub">$statusSub</div>
      </div>
      <div class="card $deltaCor">
        <div class="card-label">Espaço Livre (C:)</div>
        <div class="card-value">$EspacoDepois GB</div>
        <div class="card-sub $deltaCor">$deltaTexto</div>
      </div>
      <div class="card $avCor">
        <div class="card-label">Proteção / Antivírus</div>
        <div class="card-value-sm">$avSeguro</div>
        <div class="card-sub">Windows Security Center</div>
      </div>
      <div class="card $rebootCor">
        <div class="card-label">Reinicialização</div>
        <div class="card-value-sm">$rebootTexto</div>
        <div class="card-sub">$rebootSub</div>
      </div>
    </section>

    $alertasHtml

    <div class="filter-bar">
      <input id="searchInput" class="filter-input" type="search" placeholder="Filtrar itens no relatório (ex.: DNS, disco, BitLocker, Chrome)..." />
      <span id="filterStats" class="filter-hint">Exibindo todas as $totalSecoes seções</span>
    </div>

    <section class="grid" id="sectionsGrid">
      $secoesHtml
    </section>

    <footer class="footer">
      <div>Gerado pelo <strong>TF-Toolkit</strong> &middot; Tech Fontes &middot; <a href="https://techfontes.com.br" target="_blank">techfontes.com.br</a></div>
      <div>Suporte: suporte@techfontes.com.br &middot; $dataFormatada</div>
    </footer>
  </main>

<script>
(function() {
  const modes = ['auto', 'light', 'dark'];
  const labels = { auto: 'Auto', light: 'Claro', dark: 'Escuro' };
  const icons  = { auto: '\u25D0', light: '\u2600', dark: '\u263E' };
  const root = document.documentElement;
  const btn = document.getElementById('themeBtn');
  const lbl = document.getElementById('themeLabel');
  const ico = document.getElementById('themeIcon');

  let current = localStorage.getItem('tf-report-theme') || 'auto';
  if (!modes.includes(current)) current = 'auto';

  function applyTheme(mode) {
    current = mode;
    localStorage.setItem('tf-report-theme', mode);
    const sysDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    const effective = mode === 'auto' ? (sysDark ? 'dark' : 'light') : mode;
    root.setAttribute('data-theme', effective);
    lbl.textContent = labels[mode];
    ico.textContent = icons[mode];
  }

  btn.addEventListener('click', () => {
    const next = modes[(modes.indexOf(current) + 1) % modes.length];
    applyTheme(next);
  });

  if (window.matchMedia) {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
      if (current === 'auto') applyTheme('auto');
    });
  }
  applyTheme(current);

  const input = document.getElementById('searchInput');
  const stats = document.getElementById('filterStats');
  const cards = Array.from(document.querySelectorAll('#sectionsGrid .secao'));
  input.addEventListener('input', () => {
    const q = input.value.trim().toLowerCase();
    let visible = 0;
    cards.forEach(card => {
      const items = Array.from(card.querySelectorAll('li'));
      let cardMatch = false;
      if (!q) {
        items.forEach(li => li.style.display = '');
        card.style.display = '';
        visible++;
        return;
      }
      const titleMatch = (card.dataset.section || '').includes(q);
      items.forEach(li => {
        const hit = titleMatch || li.textContent.toLowerCase().includes(q);
        li.style.display = hit ? '' : 'none';
        if (hit) cardMatch = true;
      });
      card.style.display = cardMatch ? '' : 'none';
      if (cardMatch) visible++;
    });
    stats.textContent = q ? ('Exibindo ' + visible + ' de ' + cards.length + ' seções') : ('Exibindo todas as ' + cards.length + ' seções');
  });
})();
</script>
</body>
</html>
"@
    $html | Out-File -FilePath $OutFile -Encoding UTF8
}

Export-ModuleMember -Function Initialize-PreventivaReporting, Write-PreventivaLog, Write-PreventivaAlerta, Finalize-PreventivaReporting
