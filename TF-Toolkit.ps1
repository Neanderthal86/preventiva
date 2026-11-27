<#
.SYNOPSIS
    TF-Toolkit v3.0 - Central Modular de Preventiva Corporativa Windows (Tech Fontes).
    Carrega a interface WPF de gui\MainWindow.xaml com tema Auto / Claro / Escuro.
#>
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$BaseDir = $PSScriptRoot
if (-not $BaseDir) { $BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$ConfigFile = Join-Path $BaseDir "config\settings.json"
$Config = $null
$OutputFolder = "C:\ProgramData\Preventiva"
if (Test-Path -LiteralPath $ConfigFile) {
    try {
        $Config = Get-Content -LiteralPath $ConfigFile -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($Config.ReportSettings -and $Config.ReportSettings.OutputFolder) {
            $OutputFolder = $Config.ReportSettings.OutputFolder
        }
    } catch {}
}

$NetworkMod = Join-Path $BaseDir "modules\NetworkTools.psm1"
if (Test-Path -LiteralPath $NetworkMod) {
    try { Import-Module $NetworkMod -Force -ErrorAction SilentlyContinue } catch {}
}

$HostName = $env:COMPUTERNAME
$FreeGB = try { [math]::Round((Get-PSDrive C).Free / 1GB, 1) } catch { "?" }
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$XamlFile = Join-Path $BaseDir "gui\MainWindow.xaml"
if (-not (Test-Path -LiteralPath $XamlFile)) {
    Write-Host "[ERRO] Arquivo de interface nao encontrado: $XamlFile" -ForegroundColor Red
    return
}
[xml]$XAML = Get-Content -LiteralPath $XamlFile -Encoding UTF8 -Raw
$reader = (New-Object System.Xml.XmlNodeReader $XAML)
try {
    $Window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Host "Falha ao carregar XAML da interface." -ForegroundColor Red
    Write-Host $_.Exception.Message
    Read-Host "Pressione ENTER para sair"
    exit
}

# Bind de controles
$TitleBar                = $Window.FindName("TitleBar")
$btnThemeToggle          = $Window.FindName("btnThemeToggle")
$txtThemeIcon            = $Window.FindName("txtThemeIcon")
$txtThemeLabel           = $Window.FindName("txtThemeLabel")
$btnMinimize             = $Window.FindName("btnMinimize")
$btnClose                = $Window.FindName("btnClose")
$imgLogo                 = $Window.FindName("imgLogo")
$linkSite                = $Window.FindName("linkSite")
$txtHostName             = $Window.FindName("txtHostName")
$txtFreeSpace            = $Window.FindName("txtFreeSpace")
$txtAdmin                = $Window.FindName("txtAdmin")
$bdAdmin                 = $Window.FindName("bdAdmin")
$txtTasksCount           = $Window.FindName("txtTasksCount")
$btnPresetLight          = $Window.FindName("btnPresetLight")
$btnPresetModerate       = $Window.FindName("btnPresetModerate")
$btnPresetHeavy          = $Window.FindName("btnPresetHeavy")
$btnPresetRecovery       = $Window.FindName("btnPresetRecovery")
$btnPresetClear          = $Window.FindName("btnPresetClear")
$rbDiagnostico           = $Window.FindName("rbDiagnostico")
$rbExecucao              = $Window.FindName("rbExecucao")
$txtOutputFolderInfo     = $Window.FindName("txtOutputFolderInfo")
$btnAbrirUltimoRelatorio = $Window.FindName("btnAbrirUltimoRelatorio")
$btnAbrirPastaLogs       = $Window.FindName("btnAbrirPastaLogs")
$txtTweaksCount          = $Window.FindName("txtTweaksCount")
$btnTweakPresetCorp      = $Window.FindName("btnTweakPresetCorp")
$btnTweakPresetClear     = $Window.FindName("btnTweakPresetClear")
$btnAplicarTweaks        = $Window.FindName("btnAplicarTweaks")
$btnDesfazerTweaks       = $Window.FindName("btnDesfazerTweaks")
$btnAgendarSemanal       = $Window.FindName("btnAgendarSemanal")
$btnAbrirConfig          = $Window.FindName("btnAbrirConfig")
$pnlSoftwares            = $Window.FindName("pnlSoftwares")
$txtSoftwaresCount       = $Window.FindName("txtSoftwaresCount")
$btnSelectAllSoft        = $Window.FindName("btnSelectAllSoft")
$btnClearSoft            = $Window.FindName("btnClearSoft")
$pnlOnboardingProfiles   = $Window.FindName("pnlOnboardingProfiles")
$btnUpgradeAllSoft       = $Window.FindName("btnUpgradeAllSoft")
$btnRefreshNet           = $Window.FindName("btnRefreshNet")
$txtNetAdapter           = $Window.FindName("txtNetAdapter")
$txtNetLocalIP           = $Window.FindName("txtNetLocalIP")
$txtNetGateway           = $Window.FindName("txtNetGateway")
$txtNetDns               = $Window.FindName("txtNetDns")
$txtNetMac               = $Window.FindName("txtNetMac")
$txtNetPublicIP          = $Window.FindName("txtNetPublicIP")
$txtNetLatency           = $Window.FindName("txtNetLatency")
$btnDnsCloudflare        = $Window.FindName("btnDnsCloudflare")
$btnDnsGoogle            = $Window.FindName("btnDnsGoogle")
$btnDnsQuad9             = $Window.FindName("btnDnsQuad9")
$btnDnsDhcp              = $Window.FindName("btnDnsDhcp")
$btnQuickFlushDns        = $Window.FindName("btnQuickFlushDns")
$btnQuickRenewIp         = $Window.FindName("btnQuickRenewIp")
$btnQuickSpooler         = $Window.FindName("btnQuickSpooler")
$btnQuickNcpa            = $Window.FindName("btnQuickNcpa")
$btnQuickDevMgmt         = $Window.FindName("btnQuickDevMgmt")
$txtNetActionResult      = $Window.FindName("txtNetActionResult")
$btnInstalarSoftwares    = $Window.FindName("btnInstalarSoftwares")
$txtResumoSelecao        = $Window.FindName("txtResumoSelecao")
$txtStatus               = $Window.FindName("txtStatus")
$pbProgresso             = $Window.FindName("pbProgresso")
$btnExecutar             = $Window.FindName("btnExecutar")

$BrushConv = [System.Windows.Media.BrushConverter]::new()

# ============================================
# SISTEMA DE TEMAS (Auto / Claro / Escuro)
# ============================================
$ThemePalettes = @{
    "Dark" = @{
        BgWindow              = "#141419"
        BgHeader              = "#101015"
        BgCard                = "#1d1e26"
        BgSubCard             = "#161821"
        BgFooter              = "#191b24"
        BgControl             = "#171820"
        BgControlHover        = "#222430"
        BgControlSelected     = "#242026"
        BgControlCheckedGreen = "#1d2824"
        BgSecondaryBtn        = "#242736"
        BgSecondaryBtnHover   = "#30354a"
        BgTab                 = "#1b1d26"
        BgTabHover            = "#252836"
        BgPill                = "#1d1f2a"
        BgTitleHover          = "#2a2c38"
        BgBadgeAdmin          = "#1d2a23"
        BorderWindow          = "#2f3242"
        BorderSubtle          = "#2b2d3a"
        BorderControl         = "#2b2e3d"
        BorderControlHover    = "#484d66"
        BorderBadgeAdmin      = "#2f523e"
        TextPrimary           = "#f0f0f5"
        TextSecondary         = "#c9cde0"
        TextMuted             = "#8f93a8"
        TextWarning           = "#d99a7c"
        TextGood              = "#7ad19f"
        ScrollThumb           = "#383c52"
    }
    "Light" = @{
        BgWindow              = "#f4f5f8"
        BgHeader              = "#ffffff"
        BgCard                = "#ffffff"
        BgSubCard             = "#f7f8fc"
        BgFooter              = "#ffffff"
        BgControl             = "#f8f9fc"
        BgControlHover        = "#eef0f7"
        BgControlSelected     = "#fdf3ee"
        BgControlCheckedGreen = "#edf7f1"
        BgSecondaryBtn        = "#eef0f6"
        BgSecondaryBtnHover   = "#e2e6f0"
        BgTab                 = "#e7eaf2"
        BgTabHover            = "#dce0eb"
        BgPill                = "#f0f2f7"
        BgTitleHover          = "#e6e9f2"
        BgBadgeAdmin          = "#e8f6ee"
        BorderWindow          = "#cfd4e2"
        BorderSubtle          = "#e1e4ee"
        BorderControl         = "#d5dae6"
        BorderControlHover    = "#b3bad0"
        BorderBadgeAdmin      = "#9ed4b6"
        TextPrimary           = "#1a1d26"
        TextSecondary         = "#3c4257"
        TextMuted             = "#646b82"
        TextWarning           = "#a84a24"
        TextGood              = "#236b43"
        ScrollThumb           = "#bfc5d6"
    }
}

$ThemePrefFile = Join-Path $BaseDir "config\theme.pref"
$script:ThemeMode = "Auto"
if (Test-Path -LiteralPath $ThemePrefFile) {
    $saved = (Get-Content -LiteralPath $ThemePrefFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($saved -in @("Auto", "Claro", "Escuro")) { $script:ThemeMode = $saved }
}

function Get-WindowsIsLightTheme {
    try {
        $v = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop).AppsUseLightTheme
        return ($v -eq 1)
    } catch { return $false }
}

$ApplyTheme = {
    param([string]$ModeName)
    $script:ThemeMode = $ModeName
    try { Set-Content -LiteralPath $ThemePrefFile -Value $ModeName -Encoding ASCII -ErrorAction SilentlyContinue } catch {}

    $effective = "Dark"
    if ($ModeName -eq "Claro") { $effective = "Light" }
    elseif ($ModeName -eq "Escuro") { $effective = "Dark" }
    else { $effective = if (Get-WindowsIsLightTheme) { "Light" } else { "Dark" } }

    $pal = $ThemePalettes[$effective]
    foreach ($k in $pal.Keys) {
        $Window.Resources[$k] = $BrushConv.ConvertFromString($pal[$k])
    }

    if ($ModeName -eq "Auto") {
        $txtThemeLabel.Text = "Auto"
        $txtThemeIcon.Text = [string][char]0x25D0
        $txtThemeIcon.Foreground = $BrushConv.ConvertFromString($(if ($effective -eq "Light") { "#3D5270" } else { "#c9cde0" }))
    } elseif ($ModeName -eq "Claro") {
        $txtThemeLabel.Text = "Claro"
        $txtThemeIcon.Text = [string][char]0x2600
        $txtThemeIcon.Foreground = $BrushConv.ConvertFromString("#e68a00")
    } else {
        $txtThemeLabel.Text = "Escuro"
        $txtThemeIcon.Text = [string][char]0x263E
        $txtThemeIcon.Foreground = $BrushConv.ConvertFromString("#5b9dff")
    }

    if ($HighlightActivePreset) { & $HighlightActivePreset }
}

$btnThemeToggle.Add_Click({
    $next = switch ($script:ThemeMode) {
        "Auto"   { "Claro" }
        "Claro"  { "Escuro" }
        default  { "Auto" }
    }
    & $ApplyTheme $next
})

# ============================================
# CONTROLES DE TAREFAS, TWEAKS E SOFTWARES
# ============================================
$TaskCheckboxNames = @(
    "chkTaskInventory", "chkTaskDiskEvents", "chkTaskCriticalServices", "chkTaskCleanTemp",
    "chkTaskEmptyRecycleBin", "chkTaskFlushDns", "chkTaskFolderScan", "chkTaskSecurityAudit",
    "chkTaskWindowsUpdate", "chkTaskDefenderScan", "chkTaskTrim", "chkTaskIntegrity",
    "chkTaskWinSxS", "chkTaskFullFileScan", "chkTaskRestorePoint", "chkTaskRecovery"
)
$TaskCheckboxes = @($TaskCheckboxNames | ForEach-Object { $Window.FindName($_) })

$Presets = @{
    "Light"    = @("Inventory", "DiskEvents", "CriticalServices", "CleanTemp", "EmptyRecycleBin", "FlushDns", "FolderScan", "SecurityAudit")
    "Moderate" = @("Inventory", "DiskEvents", "CriticalServices", "CleanTemp", "EmptyRecycleBin", "FlushDns", "FolderScan", "SecurityAudit", "WindowsUpdate", "DefenderScan", "Trim")
    "Heavy"    = @("Inventory", "DiskEvents", "CriticalServices", "CleanTemp", "EmptyRecycleBin", "FlushDns", "FolderScan", "SecurityAudit", "WindowsUpdate", "DefenderScan", "Trim", "Integrity", "WinSxS", "FullFileScan", "RestorePoint")
    "Recovery" = @("Inventory", "DiskEvents", "CriticalServices", "CleanTemp", "EmptyRecycleBin", "FlushDns", "FolderScan", "SecurityAudit", "WindowsUpdate", "DefenderScan", "Trim", "Integrity", "WinSxS", "FullFileScan", "RestorePoint", "Recovery")
}
$script:ActivePresetName = "Light"
$script:IsApplyingPreset = $false

$TweakCheckboxNames = @(
    "chkTweakHighPerf", "chkTweakTelemetry", "chkTweakBGApps", "chkTweakVisualFX",
    "chkTweakDeliveryOpt", "chkTweakHibernation", "chkTweakLongPaths", "chkTweakEdgeDebloat",
    "chkTweakConsumer", "chkTweakBing", "chkTweakActivity", "chkTweakRightClick",
    "chkTweakEndTask", "chkTweakShowExt", "chkTweakWidgets", "chkTweakCopilot"
)
$TweakCheckboxes = @($TweakCheckboxNames | ForEach-Object { $Window.FindName($_) })
$CorpSafeTweaks = @(
    "DisableTelemetry", "DisableBGApps", "DisableDeliveryOpt", "EnableLongPaths",
    "EdgeDebloat", "DisableConsumerFeatures", "DisableBingSearch", "DisableActivityHistory",
    "EndTaskTaskbar", "ShowFileExtensions", "DisableWidgets", "DisableCopilotAI"
)

# Preencher informacoes da maquina
$txtHostName.Text = $HostName
$txtFreeSpace.Text = "$FreeGB GB"
$txtOutputFolderInfo.Text = $OutputFolder
if ($IsAdmin) {
    $txtAdmin.Text = "Administrador"
} else {
    $txtAdmin.Text = "Padr$([char]0x00E3)o"
    $txtAdmin.Foreground = $BrushConv.ConvertFromString("#C4613A")
}

# Arrastar janela e botoes de titulo
$TitleBar.Add_MouseLeftButtonDown({
    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        $Window.DragMove()
    }
})
$btnMinimize.Add_Click({ $Window.WindowState = "Minimized" })
$btnClose.Add_Click({ $Window.Close() })

# Logo
$LogoPath = Join-Path $BaseDir "assets\logo.png"
if (Test-Path -LiteralPath $LogoPath) {
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = [System.Uri]::new($LogoPath)
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.EndInit()
        $imgLogo.Source = $bitmap
    } catch {}
}

if ($linkSite) {
    $linkSite.Add_Click({ Start-Process "https://techfontes.com.br" })
}

$PresetButtons = @{
    "Light"    = $btnPresetLight
    "Moderate" = $btnPresetModerate
    "Heavy"    = $btnPresetHeavy
    "Recovery" = $btnPresetRecovery
}

$HighlightActivePreset = {
    foreach ($kv in $PresetButtons.GetEnumerator()) {
        if ($kv.Key -eq $script:ActivePresetName) {
            $kv.Value.Background = $BrushConv.ConvertFromString("#C4613A")
            $kv.Value.BorderBrush = $BrushConv.ConvertFromString("#d97248")
            $kv.Value.Foreground = [System.Windows.Media.Brushes]::White
        } else {
            $kv.Value.Background = $Window.Resources["BgSecondaryBtn"]
            $kv.Value.BorderBrush = $Window.Resources["BorderControl"]
            $kv.Value.Foreground = $Window.Resources["TextSecondary"]
        }
    }
}

$DynamicCheckboxes = @()
$UpdateSummary = {
    $selectedTasks = @($TaskCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $taskCount = $selectedTasks.Count
    $txtTasksCount.Text = "$taskCount selecionada(s)"

    if (-not $script:IsApplyingPreset) {
        $matched = "Personalizado"
        foreach ($pName in @("Light", "Moderate", "Heavy", "Recovery")) {
            $pTasks = $Presets[$pName]
            if ($taskCount -eq $pTasks.Count -and (@($selectedTasks | Where-Object { $pTasks -notcontains $_ }).Count -eq 0)) {
                $matched = $pName
                break
            }
        }
        $script:ActivePresetName = $matched
    }
    & $HighlightActivePreset

    $subText = if ($rbExecucao.IsChecked) { "Execu$([char]0x00E7)$([char]0x00E3)o" } else { "Diagn$([char]0x00F3)stico" }
    $softCount = @($DynamicCheckboxes | Where-Object { $_.IsChecked }).Count
    $txtSoftwaresCount.Text = "$softCount software(s) selecionado(s) $([char]0x2014) clique em 'Instalar Selecionados' para instalar agora"

    $extras = @()
    $tweakCount = @($TweakCheckboxes | Where-Object { $_.IsChecked }).Count
    if ($txtTweaksCount) { $txtTweaksCount.Text = "$tweakCount selecionado(s)" }
    if ($rbExecucao.IsChecked -and $tweakCount -gt 0) { $extras += "$tweakCount tweak(s)" }
    if ($rbExecucao.IsChecked -and $softCount -gt 0) { $extras += "$softCount app(s) Winget" }

    $resumo = "Selecionado: $($script:ActivePresetName) ($taskCount tarefas)  $([char]0x2022)  $subText"
    if ($extras.Count -gt 0) { $resumo += "  $([char]0x2022)  " + ($extras -join " + ") }
    $txtResumoSelecao.Text = $resumo
}

$ApplyPreset = {
    param([string]$PresetName)
    $script:IsApplyingPreset = $true
    $targetTasks = if ($Presets.ContainsKey($PresetName)) { $Presets[$PresetName] } else { @() }
    foreach ($cb in $TaskCheckboxes) {
        $cb.IsChecked = ($targetTasks -contains $cb.Tag)
    }
    $script:ActivePresetName = if ($targetTasks.Count -gt 0) { $PresetName } else { "Personalizado" }
    $script:IsApplyingPreset = $false
    & $UpdateSummary
}

$btnPresetLight.Add_Click({ # Popular Perfis Pos-Formatacao (settings.json)
$SecondaryBtnStyle = $Window.FindResource("SecondaryButton")
if ($Config -and $Config.OnboardingProfiles -and $pnlOnboardingProfiles) {
    foreach ($prof in $Config.OnboardingProfiles) {
        $btnP = New-Object System.Windows.Controls.Button
        $btnP.Style = $SecondaryBtnStyle
        $btnP.Content = "Perfil: $($prof.Name)"
        $btnP.ToolTip = $prof.Description
        $btnP.HorizontalAlignment = "Stretch"
        $btnP.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
        $btnP.Padding = New-Object System.Windows.Thickness(12, 9, 12, 9)
        $btnP.Tag = $prof
        $btnP.Add_Click({
            $p = $this.Tag
            if ($p.Preset) { & $ApplyPreset $p.Preset }
            foreach ($tcb in $TweakCheckboxes) {
                $tcb.IsChecked = ($p.Tweaks -contains $tcb.Tag)
            }
            foreach ($scb in $DynamicCheckboxes) {
                $scb.IsChecked = ($p.Softwares -contains $scb.Tag)
            }
            $rbExecucao.IsChecked = $true
            & $UpdateSummary
            $txtStatus.Text = "Perfil '$($p.Name)' carregado! Clique em INICIAR PREVENTIVA para aplicar."
        })
        $pnlOnboardingProfiles.Children.Add($btnP) | Out-Null
    }
}

# Botao Atualizar Todos os Apps (winget upgrade --all)
if ($btnUpgradeAllSoft) {
    $btnUpgradeAllSoft.Add_Click({
        $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
        if (-not (Test-Path -LiteralPath $ScriptFile)) { return }
        $ArgsList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"",
            "-Mode", "`"WingetUpgrade`"", "-SubModo", "`"Execucao`"",
            "-Tasks", "`"None`"", "-UpgradeAllSoftware"
        )
        try {
            $btnExecutar.IsEnabled = $false
            $btnInstalarSoftwares.IsEnabled = $false
            $btnUpgradeAllSoft.IsEnabled = $false
            $btnAplicarTweaks.IsEnabled = $false
            $btnDesfazerTweaks.IsEnabled = $false
            $btnExecutar.Content = "ATUALIZANDO..."
            $pbProgresso.Visibility = "Visible"
            $txtStatus.Text = "Atualizando todos os apps instalados via Winget... Acompanhe no console."
            $script:StartTime = Get-Date
            $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
            $script:PollTimer.Start()
        } catch {
            $btnExecutar.IsEnabled = $true
            $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
            $btnUpgradeAllSoft.IsEnabled = $true
            $btnAplicarTweaks.IsEnabled = $true
            $btnDesfazerTweaks.IsEnabled = $true
            $btnExecutar.Content = "INICIAR PREVENTIVA"
            $pbProgresso.Visibility = "Collapsed"
            $txtStatus.Text = "Erro ao iniciar atualiza$([char]0x00E7)$([char]0x00E3)o Winget: $_"
        }
    })
}

# Aba Rede & Suporte Rapido
$RefreshNetworkUI = {
    try {
        if (Get-Command Get-PreventivaNetworkSummary -ErrorAction SilentlyContinue) {
            $info = Get-PreventivaNetworkSummary
            $txtNetAdapter.Text  = $info.Adapter
            $txtNetLocalIP.Text  = $info.LocalIP
            $txtNetGateway.Text  = $info.Gateway
            $txtNetDns.Text      = $info.DnsList
            $txtNetMac.Text      = $info.Mac
            $txtNetPublicIP.Text = $info.PublicIP
            $txtNetLatency.Text  = $info.Latency
            $txtNetActionResult.Text = "Informa$([char]0x00E7)$([char]0x00F5)es de rede atualizadas ($(Get-Date -Format 'HH:mm:ss'))."
        }
    } catch {
        $txtNetActionResult.Text = "Falha ao ler rede: $_"
    }
}

$btnRefreshNet.Add_Click($RefreshNetworkUI)
$btnDnsCloudflare.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Cloudflare"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsGoogle.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Google"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsQuad9.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Quad9"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsDhcp.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "DHCP"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickFlushDns.Add_Click({
    try { ipconfig /flushdns | Out-Null; $txtNetActionResult.Text = "Flush DNS executado com sucesso ($(Get-Date -Format 'HH:mm:ss'))." } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickRenewIp.Add_Click({
    try { $txtNetActionResult.Text = (Invoke-PreventivaRenewIp); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickSpooler.Add_Click({
    try { $txtNetActionResult.Text = (Restart-PreventivaPrintSpooler) } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickNcpa.Add_Click({ Start-Process "ncpa.cpl" })
$btnQuickDevMgmt.Add_Click({ Start-Process "devmgmt.msc" })

& $ApplyPreset "Light" })
$btnPresetModerate.Add_Click({ & $ApplyPreset "Moderate" })
$btnPresetHeavy.Add_Click({ & $ApplyPreset "Heavy" })
$btnPresetRecovery.Add_Click({ & $ApplyPreset "Recovery" })
$btnPresetClear.Add_Click({ & $ApplyPreset "None" })

foreach ($cb in $TaskCheckboxes) {
    $cb.Add_Checked($UpdateSummary)
    $cb.Add_Unchecked($UpdateSummary)
}

# Popular lista de softwares em Cards (com DynamicResource para suportar Claro/Escuro)
$CardCheckStyle = $Window.FindResource("CardCheck")
if ($Config -and $Config.SoftwareList) {
    foreach ($soft in $Config.SoftwareList) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Style = $CardCheckStyle
        $cb.Tag = $soft.Id
        $cb.IsChecked = $false

        $sp = New-Object System.Windows.Controls.StackPanel
        $tbName = New-Object System.Windows.Controls.TextBlock
        $tbName.Text = $soft.Name
        $tbName.FontSize = 13
        $tbName.FontWeight = "SemiBold"
        $tbName.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextPrimary")

        $tbId = New-Object System.Windows.Controls.TextBlock
        $tbId.Text = $soft.Id
        $tbId.FontSize = 10.5
        $tbId.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMuted")

        $sp.Children.Add($tbName) | Out-Null
        $sp.Children.Add($tbId) | Out-Null
        $cb.Content = $sp

        $cb.Add_Checked($UpdateSummary)
        $cb.Add_Unchecked($UpdateSummary)
        $DynamicCheckboxes += $cb
        $pnlSoftwares.Children.Add($cb) | Out-Null
    }
}

foreach ($ctrl in @($rbDiagnostico, $rbExecucao)) {
    $ctrl.Add_Checked($UpdateSummary)
}
foreach ($tcb in $TweakCheckboxes) {
    $tcb.Add_Checked($UpdateSummary)
    $tcb.Add_Unchecked($UpdateSummary)
}

$btnTweakPresetCorp.Add_Click({
    foreach ($tcb in $TweakCheckboxes) {
        $tcb.IsChecked = ($CorpSafeTweaks -contains $tcb.Tag)
    }
    & $UpdateSummary
})
$btnTweakPresetClear.Add_Click({
    foreach ($tcb in $TweakCheckboxes) { $tcb.IsChecked = $false }
    & $UpdateSummary
})

$RunTweaksAction = {
    param([bool]$IsUndo)
    $SelectedTweaks = @($TweakCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($SelectedTweaks.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Selecione pelo menos um tweak na lista.", "Nenhum tweak selecionado", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
    if (-not (Test-Path -LiteralPath $ScriptFile)) {
        [System.Windows.MessageBox]::Show("Script base n$([char]0x00E3)o encontrado:`n$ScriptFile", "Erro", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    $modeLabel = if ($IsUndo) { "TweaksUndo" } else { "Tweaks" }
    $ArgsList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"",
        "-Mode", "`"$modeLabel`"", "-SubModo", "`"Execucao`"",
        "-Tasks", "`"None`"",
        "-Tweaks", "`"$($SelectedTweaks -join ',')`""
    )
    if ($IsUndo) { $ArgsList += "-UndoTweaks" }

    try {
        $btnExecutar.IsEnabled = $false
        $btnInstalarSoftwares.IsEnabled = $false
        $btnAplicarTweaks.IsEnabled = $false
        $btnDesfazerTweaks.IsEnabled = $false
        $btnExecutar.Content = if ($IsUndo) { "DESFAZENDO..." } else { "APLICANDO..." }
        $pbProgresso.Visibility = "Visible"
        $acaoTxt = if ($IsUndo) { "Desfazendo" } else { "Aplicando" }
        $txtStatus.Text = "$acaoTxt $($SelectedTweaks.Count) tweak(s)... Acompanhe na janela do console."

        $script:StartTime = Get-Date
        $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
        $script:PollTimer.Start()
    } catch {
        $btnExecutar.IsEnabled = $true
        $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
        $btnAplicarTweaks.IsEnabled = $true
        $btnDesfazerTweaks.IsEnabled = $true
        $btnExecutar.Content = "INICIAR PREVENTIVA"
        $pbProgresso.Visibility = "Collapsed"
        $txtStatus.Text = "Erro ao executar tweaks: $_"
    }
}

$btnAplicarTweaks.Add_Click({ & $RunTweaksAction $false })
$btnDesfazerTweaks.Add_Click({ & $RunTweaksAction $true })

$btnSelectAllSoft.Add_Click({
    foreach ($cb in $DynamicCheckboxes) { $cb.IsChecked = $true }
    & $UpdateSummary
})
$btnClearSoft.Add_Click({
    foreach ($cb in $DynamicCheckboxes) { $cb.IsChecked = $false }
    & $UpdateSummary
})

$btnInstalarSoftwares.Add_Click({
    $Softs = @($DynamicCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($Softs.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Selecione pelo menos um software na lista para instalar.", "Nenhum software selecionado", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
    if (-not (Test-Path -LiteralPath $ScriptFile)) {
        [System.Windows.MessageBox]::Show("Script base n$([char]0x00E3)o encontrado:`n$ScriptFile", "Erro", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    $ArgsList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"",
        "-Mode", "`"Softwares`"", "-SubModo", "`"Execucao`"",
        "-Tasks", "`"None`"",
        "-SoftwareToInstall", "`"$($Softs -join ',')`""
    )

    try {
        $btnExecutar.IsEnabled = $false
        $btnInstalarSoftwares.IsEnabled = $false
        $btnAplicarTweaks.IsEnabled = $false
        $btnDesfazerTweaks.IsEnabled = $false
        $btnExecutar.Content = "INSTALANDO..."
        $pbProgresso.Visibility = "Visible"
        $txtStatus.Text = "Instalando $($Softs.Count) software(s) via Winget... Acompanhe na janela do console."

        $script:StartTime = Get-Date
        $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
        $script:PollTimer.Start()
    } catch {
        $btnExecutar.IsEnabled = $true
        $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
        $btnAplicarTweaks.IsEnabled = $true
        $btnDesfazerTweaks.IsEnabled = $true
        $btnExecutar.Content = "INICIAR PREVENTIVA"
        $pbProgresso.Visibility = "Collapsed"
        $txtStatus.Text = "Erro ao iniciar instala$([char]0x00E7)$([char]0x00E3)o: $_"
    }
})

# Atalhos de Relatorios e Ferramentas
$btnAbrirPastaLogs.Add_Click({
    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    Start-Process explorer.exe -ArgumentList "`"$OutputFolder`""
})

$btnAbrirUltimoRelatorio.Add_Click({
    $latest = Get-ChildItem -LiteralPath $OutputFolder -Filter "Relatorio_*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Start-Process $latest.FullName
    } else {
        [System.Windows.MessageBox]::Show("Nenhum relat$([char]0x00F3)rio HTML encontrado ainda em:`n$OutputFolder", "Relat$([char]0x00F3)rios", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    }
})

$btnAgendarSemanal.Add_Click({
    $sched = Join-Path $BaseDir "Install-Agendamento.ps1"
    if (Test-Path -LiteralPath $sched) {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$sched`"" -Verb RunAs
    } else {
        [System.Windows.MessageBox]::Show("Script Install-Agendamento.ps1 n$([char]0x00E3)o encontrado.", "Aviso", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
    }
})

$btnAbrirConfig.Add_Click({
    if (Test-Path -LiteralPath $ConfigFile) {
        Start-Process notepad.exe -ArgumentList "`"$ConfigFile`""
    }
})

# Execucao Assincrona
$script:CurrentProcess = $null
$script:StartTime = $null
$script:PollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:PollTimer.Interval = [TimeSpan]::FromMilliseconds(500)

$script:PollTimer.Add_Tick({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $elapsed = (Get-Date) - $script:StartTime
        $txtStatus.Text = "Executando... tempo decorrido: $($elapsed.ToString('mm\:ss'))"
    } else {
        $script:PollTimer.Stop()
        $pbProgresso.Visibility = "Collapsed"
        $btnExecutar.IsEnabled = $true
        $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
        $btnAplicarTweaks.IsEnabled = $true
        $btnDesfazerTweaks.IsEnabled = $true
        $btnExecutar.Content = "INICIAR PREVENTIVA"

        $exitCode = if ($script:CurrentProcess) { $script:CurrentProcess.ExitCode } else { 0 }
        $script:CurrentProcess = $null

        if ($exitCode -eq 0) {
            $txtStatus.Text = "Conclu$([char]0x00ED)do! Relat$([char]0x00F3)rio salvo em $OutputFolder"
            $res = [System.Windows.MessageBox]::Show(
                "Opera$([char]0x00E7)$([char]0x00E3)o finalizada com sucesso!`n`nDeseja abrir o relat$([char]0x00F3)rio HTML gerado agora?",
                "Tech Fontes - Conclu$([char]0x00ED)do",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Information
            )
            if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                $latest = Get-ChildItem -LiteralPath $OutputFolder -Filter "Relatorio_*.html" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latest) { Start-Process $latest.FullName }
            }
        } else {
            $txtStatus.Text = "Finalizado com c$([char]0x00F3)digo $exitCode. Verifique os logs em $OutputFolder"
        }
    }
})

$btnExecutar.Add_Click({
    $Mode = if ($script:ActivePresetName) { $script:ActivePresetName } else { "Personalizado" }
    $SubModo = if ($rbExecucao.IsChecked) { "Execucao" } else { "Diagnostico" }

    $SelectedTasks = @($TaskCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $SelectedTweaks = @($TweakCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $Softs = @($DynamicCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $HasPowerOpt = ($SelectedTweaks.Count -gt 0 -and $SubModo -eq "Execucao")

    if ($SelectedTasks.Count -eq 0 -and $Softs.Count -eq 0 -and -not $HasPowerOpt) {
        [System.Windows.MessageBox]::Show("Selecione pelo menos uma tarefa, tweak ou software para executar.", "Nenhuma a$([char]0x00E7)$([char]0x00E3)o selecionada", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
    if (-not (Test-Path -LiteralPath $ScriptFile)) {
        [System.Windows.MessageBox]::Show("Script base n$([char]0x00E3)o encontrado:`n$ScriptFile", "Erro", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    $ArgsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"", "-Mode", "`"$Mode`"", "-SubModo", "`"$SubModo`"")
    $TasksArg = if ($SelectedTasks.Count -gt 0) { $SelectedTasks -join ',' } else { "None" }
    $ArgsList += "-Tasks"
    $ArgsList += "`"$TasksArg`""
    if ($SelectedTweaks.Count -gt 0) {
        $ArgsList += "-Tweaks"
        $ArgsList += "`"$($SelectedTweaks -join ',')`""
    }
    if ($Softs.Count -gt 0) {
        $ArgsList += "-SoftwareToInstall"
        $ArgsList += "`"$($Softs -join ',')`""
    }

    try {
        $btnExecutar.IsEnabled = $false
        $btnInstalarSoftwares.IsEnabled = $false
        $btnAplicarTweaks.IsEnabled = $false
        $btnDesfazerTweaks.IsEnabled = $false
        $btnExecutar.Content = "EXECUTANDO..."
        $pbProgresso.Visibility = "Visible"
        $txtStatus.Text = "Iniciando $Mode ($SubModo)... Acompanhe na janela do console."

        $script:StartTime = Get-Date
        $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
        $script:PollTimer.Start()
    } catch {
        $btnExecutar.IsEnabled = $true
        $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
        $btnAplicarTweaks.IsEnabled = $true
        $btnDesfazerTweaks.IsEnabled = $true
        $btnExecutar.Content = "INICIAR PREVENTIVA"
        $pbProgresso.Visibility = "Collapsed"
        $txtStatus.Text = "Erro ao iniciar o processo: $_"
    }
})

# Popular Perfis Pos-Formatacao (settings.json)
$SecondaryBtnStyle = $Window.FindResource("SecondaryButton")
if ($Config -and $Config.OnboardingProfiles -and $pnlOnboardingProfiles) {
    foreach ($prof in $Config.OnboardingProfiles) {
        $btnP = New-Object System.Windows.Controls.Button
        $btnP.Style = $SecondaryBtnStyle
        $btnP.Content = "Perfil: $($prof.Name)"
        $btnP.ToolTip = $prof.Description
        $btnP.HorizontalAlignment = "Stretch"
        $btnP.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
        $btnP.Padding = New-Object System.Windows.Thickness(12, 9, 12, 9)
        $btnP.Tag = $prof
        $btnP.Add_Click({
            $p = $this.Tag
            if ($p.Preset) { & $ApplyPreset $p.Preset }
            foreach ($tcb in $TweakCheckboxes) {
                $tcb.IsChecked = ($p.Tweaks -contains $tcb.Tag)
            }
            foreach ($scb in $DynamicCheckboxes) {
                $scb.IsChecked = ($p.Softwares -contains $scb.Tag)
            }
            $rbExecucao.IsChecked = $true
            & $UpdateSummary
            $txtStatus.Text = "Perfil '$($p.Name)' carregado! Clique em INICIAR PREVENTIVA para aplicar."
        })
        $pnlOnboardingProfiles.Children.Add($btnP) | Out-Null
    }
}

# Botao Atualizar Todos os Apps (winget upgrade --all)
if ($btnUpgradeAllSoft) {
    $btnUpgradeAllSoft.Add_Click({
        $ScriptFile = Join-Path $BaseDir "Invoke-Preventiva.ps1"
        if (-not (Test-Path -LiteralPath $ScriptFile)) { return }
        $ArgsList = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptFile`"",
            "-Mode", "`"WingetUpgrade`"", "-SubModo", "`"Execucao`"",
            "-Tasks", "`"None`"", "-UpgradeAllSoftware"
        )
        try {
            $btnExecutar.IsEnabled = $false
            $btnInstalarSoftwares.IsEnabled = $false
            $btnUpgradeAllSoft.IsEnabled = $false
            $btnAplicarTweaks.IsEnabled = $false
            $btnDesfazerTweaks.IsEnabled = $false
            $btnExecutar.Content = "ATUALIZANDO..."
            $pbProgresso.Visibility = "Visible"
            $txtStatus.Text = "Atualizando todos os apps instalados via Winget... Acompanhe no console."
            $script:StartTime = Get-Date
            $script:CurrentProcess = Start-Process powershell -ArgumentList ($ArgsList -join " ") -WindowStyle Normal -PassThru
            $script:PollTimer.Start()
        } catch {
            $btnExecutar.IsEnabled = $true
            $btnInstalarSoftwares.IsEnabled = $true
        if ($btnUpgradeAllSoft) { $btnUpgradeAllSoft.IsEnabled = $true }
            $btnUpgradeAllSoft.IsEnabled = $true
            $btnAplicarTweaks.IsEnabled = $true
            $btnDesfazerTweaks.IsEnabled = $true
            $btnExecutar.Content = "INICIAR PREVENTIVA"
            $pbProgresso.Visibility = "Collapsed"
            $txtStatus.Text = "Erro ao iniciar atualiza$([char]0x00E7)$([char]0x00E3)o Winget: $_"
        }
    })
}

# Aba Rede & Suporte Rapido
$RefreshNetworkUI = {
    try {
        if (Get-Command Get-PreventivaNetworkSummary -ErrorAction SilentlyContinue) {
            $info = Get-PreventivaNetworkSummary
            $txtNetAdapter.Text  = $info.Adapter
            $txtNetLocalIP.Text  = $info.LocalIP
            $txtNetGateway.Text  = $info.Gateway
            $txtNetDns.Text      = $info.DnsList
            $txtNetMac.Text      = $info.Mac
            $txtNetPublicIP.Text = $info.PublicIP
            $txtNetLatency.Text  = $info.Latency
            $txtNetActionResult.Text = "Informa$([char]0x00E7)$([char]0x00F5)es de rede atualizadas ($(Get-Date -Format 'HH:mm:ss'))."
        }
    } catch {
        $txtNetActionResult.Text = "Falha ao ler rede: $_"
    }
}

$btnRefreshNet.Add_Click($RefreshNetworkUI)
$btnDnsCloudflare.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Cloudflare"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsGoogle.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Google"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsQuad9.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "Quad9"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnDnsDhcp.Add_Click({
    try { $txtNetActionResult.Text = (Set-PreventivaDns -Provider "DHCP"); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickFlushDns.Add_Click({
    try { ipconfig /flushdns | Out-Null; $txtNetActionResult.Text = "Flush DNS executado com sucesso ($(Get-Date -Format 'HH:mm:ss'))." } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickRenewIp.Add_Click({
    try { $txtNetActionResult.Text = (Invoke-PreventivaRenewIp); & $RefreshNetworkUI } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickSpooler.Add_Click({
    try { $txtNetActionResult.Text = (Restart-PreventivaPrintSpooler) } catch { $txtNetActionResult.Text = "Erro: $_" }
})
$btnQuickNcpa.Add_Click({ Start-Process "ncpa.cpl" })
$btnQuickDevMgmt.Add_Click({ Start-Process "devmgmt.msc" })

& $ApplyPreset "Light"
& $ApplyTheme $script:ThemeMode
$Window.ShowDialog() | Out-Null
