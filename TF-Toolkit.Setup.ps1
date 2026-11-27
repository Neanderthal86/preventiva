#requires -Version 5.1
<#
.SYNOPSIS
    Instala, atualiza ou desinstala o TF-Toolkit.

.DESCRIPTION
    Aberto pelo TF-Toolkit-Setup.cmd, na pasta extraída do zip: instala o TF-Toolkit em Arquivos de Programas, com o atalho no
    Menu Iniciar e a entrada em Aplicativos instalados (de onde ele se desinstala). Com o TF-Toolkit já instalado, atualiza
    a mesma pasta, guardando os arquivos anteriores para voltar ao que era se algo falhar. Aberto da pasta instalada,
    oferece desinstalar.

.PARAMETER Uninstall
    Desinstala o TF-Toolkit (é o que Configurações > Aplicativos roda).

.PARAMETER Update
    Uso interno (Sobre o TF-Toolkit > Verificar nova versão): espera o TF-Toolkit fechar (-WaitProcessId, números separados
    por vírgula), troca os arquivos da pasta -Target pelos desta pasta e abre o TF-Toolkit de novo (-Reopen Gui ou
    Console). Sem janela e sem perguntas; o resultado fica para o TF-Toolkit mostrar ao abrir.

.PARAMETER Target
    A pasta do TF-Toolkit. Ao instalar, o padrão é a pasta já instalada ou, sem ela, Arquivos de Programas\TF-Toolkit.
#>
[CmdletBinding()]
param (
    [switch]$Uninstall,

    [switch]$Update,

    [string]$Target = "",

    [string]$WaitProcessId = "",

    [ValidateSet("", "Gui", "Console")]
    [string]$Reopen = "",

    [switch]$Relaunched,

    [switch]$FromTemp
)

$ErrorActionPreference = "Continue"

# --- Atualização sem os módulos -------------------------------------------------------------------------
function Invoke-TFToolkitSetupUpdateFallback {
    <#
    O modo -Update quando os módulos da versão nova não carregam (um arquivo bloqueado pelo antivírus, por exemplo) ou
    quando a troca nem chega a começar (Cause = Error, um erro inesperado): nada foi trocado. Espera o TF-Toolkit fechar,
    grava o resultado que ele mostra ao abrir (sem os textos traduzidos, a frase vem daqui, na língua escolhida no
    TF-Toolkit ou na do Windows) e abre de novo a cópia de sempre, na mesma versão.
    #>
    param ([ValidateSet("Load", "Error")][string]$Cause = "Load")

    $ids = @("$WaitProcessId" -split ',' | ForEach-Object { $number = 0; if ([int]::TryParse(([string]$_).Trim(), [ref]$number) -and $number -gt 0) { $number } })
    $deadline = (Get-Date).AddSeconds(120)

    while ((Get-Date) -lt $deadline -and @($ids | Where-Object { $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue) }).Count -gt 0) {
        Start-Sleep -Milliseconds 500
    }

    $readBuild = {
        param ([string]$Folder)

        try {
            $match = [regex]::Match([System.IO.File]::ReadAllText((Join-Path (Join-Path $Folder "modules") "Core.psm1")), '\$script:TFToolkitBuild\s*=\s*"([0-9.]+)"')
            if ($match.Success) { return $match.Groups[1].Value }
        }
        catch {
            Write-Verbose "Versão: $($_.Exception.Message)"
        }

        return ""
    }

    $data = Join-Path $env:LOCALAPPDATA "TF-Toolkit"

    try {
        $language = ""

        try {
            $settings = [System.IO.File]::ReadAllText((Join-Path $data "settings.json")) | ConvertFrom-Json
            $language = [string]$settings.Language
        }
        catch {
            $language = ""
        }

        if ($language -notin @("pt", "en", "es")) { $language = [string][System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName }

        $reason = switch ($language) {
            "pt" { if ($Cause -eq "Error") { "o instalador da versão nova parou com um erro inesperado" } else { "o instalador da versão nova não conseguiu carregar os arquivos dele" } }
            "es" { if ($Cause -eq "Error") { "el instalador de la versión nueva se detuvo por un error inesperado" } else { "el instalador de la versión nueva no pudo cargar sus archivos" } }
            default { if ($Cause -eq "Error") { "the new version's installer stopped with an unexpected error" } else { "the new version's installer could not load its files" } }
        }

        $folder = Join-Path $data "update"
        if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop) }

        $document = [ordered]@{ From = (& $readBuild $Target); To = (& $readBuild $PSScriptRoot); Ok = $false; Error = $reason; RollbackFailed = $false; At = (Get-Date).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
        [System.IO.File]::WriteAllText((Join-Path $folder "result.json"), (ConvertTo-Json -InputObject $document), (New-Object System.Text.UTF8Encoding($true)))
    }
    catch {
        Write-Verbose "Resultado: $($_.Exception.Message)"
    }

    try {
        if ($Reopen -eq "Console" -and (Test-Path -LiteralPath (Join-Path $Target "TF-Toolkit-Console.cmd") -PathType Leaf)) {
            Start-Process -FilePath (Join-Path $Target "TF-Toolkit-Console.cmd") -WorkingDirectory $Target -ErrorAction Stop
        }
        elseif ($Reopen -eq "Gui" -and (Test-Path -LiteralPath (Join-Path $Target "TF-Toolkit.Gui.ps1") -PathType Leaf)) {
            $gui = Join-Path $Target "TF-Toolkit.Gui.ps1"
            Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$gui`" -Page app" -WindowStyle Hidden -WorkingDirectory $Target -ErrorAction Stop
        }
    }
    catch {
        Write-Verbose "Abrir o TF-Toolkit: $($_.Exception.Message)"
    }
}


# --- Módulos -------------------------------------------------------------------------------------------
$moduleRoot = Join-Path $PSScriptRoot "modules"

try {
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot "Modules.psd1") -ErrorAction Stop

    foreach ($name in @($manifest.Common)) {
        $modulePath = Join-Path $moduleRoot "$name.psm1"

        try {
            Import-Module -Name $modulePath -Force -DisableNameChecking -Global -ErrorAction Stop
        }
        catch {
            # Caminhos com colchetes são lidos como curinga pelo Import-Module; escapar resolve.
            Import-Module -Name ([System.Management.Automation.WildcardPattern]::Escape($modulePath)) -Force -DisableNameChecking -Global -ErrorAction Stop
        }
    }
}
catch {
    # Na atualização, sem janela: o TF-Toolkit de antes abre de novo, com o motivo.
    if ($Update) {
        Invoke-TFToolkitSetupUpdateFallback
        exit 1
    }

    # Ainda sem os textos traduzidos: o aviso sai nos três idiomas do TF-Toolkit.
    Write-Host ""
    Write-Host "  Faltam arquivos do TF-Toolkit nesta pasta. Extraia o TF-Toolkit.zip inteiro (Extrair tudo) e abra o"
    Write-Host "  TF-Toolkit-Setup.cmd da pasta nova."
    Write-Host ""
    Write-Host "  Some TF-Toolkit files are missing from this folder. Extract the whole TF-Toolkit.zip (Extract all) and"
    Write-Host "  open TF-Toolkit-Setup.cmd from the new folder."
    Write-Host ""
    Write-Host "  Faltan archivos de TF-Toolkit en esta carpeta. Extrae todo el TF-Toolkit.zip (Extraer todo) y abre"
    Write-Host "  TF-Toolkit-Setup.cmd en la carpeta nueva."
    Write-Host ""
    [void](Read-Host "  Enter")

    exit 1
}

Set-TFToolkitConsoleEncoding


# --- Atualização (sem janela) ----------------------------------------------------------------------------
if ($Update) {
    [void](Start-TFToolkitLogging)

    $ids = @($WaitProcessId -split ',' | ForEach-Object { $number = 0; if ([int]::TryParse(([string]$_).Trim(), [ref]$number)) { $number } })
    $ok = $false

    try {
        $ok = Install-TFToolkitUpdatePackage -Source $PSScriptRoot -Target $Target -WaitProcessId $ids -Reopen $Reopen
    }
    catch {
        # A troca trata os próprios erros e sempre abre o TF-Toolkit de novo; um erro que chega aqui veio antes dela começar.
        # Sem isto, o TF-Toolkit que fechou para a atualização não voltava a abrir.
        Write-Verbose "Atualização: $($_.Exception.Message)"
        Stop-TFToolkitLogging
        Invoke-TFToolkitSetupUpdateFallback -Cause Error
        exit 1
    }

    Stop-TFToolkitLogging
    exit $(if ($ok) { 0 } else { 1 })
}


# --- Administrador -------------------------------------------------------------------------------------
function Wait-TFToolkitSetupKey {
    Write-Host ""
    Wait-TFToolkitKey -Message (Get-TFToolkitText 'Pressione qualquer tecla para fechar...')
}

if (-not (Test-TFToolkitAdministrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File $(ConvertTo-TFToolkitCommandLineArgument -Value $PSCommandPath) -Relaunched"
    if ($Uninstall) { $arguments += " -Uninstall" }
    if ($Target) { $arguments += " -Target $(ConvertTo-TFToolkitCommandLineArgument -Value $Target)" }

    $elevated = $false

    if (-not $Relaunched) {
        try {
            Start-Process -FilePath (Get-TFToolkitPowerShellPath) -ArgumentList $arguments -Verb RunAs -ErrorAction Stop
            $elevated = $true
        }
        catch {
            $elevated = $false
        }
    }

    if ($elevated) { exit 0 }

    Write-Host ""
    Write-TFToolkitStatus -Type Error -Message $(if ($Uninstall) { (Get-TFToolkitText 'Desinstalar o TF-Toolkit pede a permissão de Administrador, e o pedido do Windows foi recusado.') } else { (Get-TFToolkitText 'Instalar o TF-Toolkit pede a permissão de Administrador, e o pedido do Windows foi recusado.') })
    Wait-TFToolkitSetupKey
    exit 1
}

[void](Start-TFToolkitLogging)

try { $Host.UI.RawUI.WindowTitle = "TF-Toolkit" } catch { Write-Verbose "Título da janela: $($_.Exception.Message)" }


function Wait-TFToolkitSetupCopiesClosed {
    # Antes de mexer nos arquivos, a janela e o menu desta pasta precisam estar fechados (o monitor o Setup fecha sozinho).
    param ([Parameter(Mandatory)][string]$Root)

    while ($true) {
        $open = @(Get-TFToolkitRunningCopies -Root $Root | Where-Object { $_.Kind -ne "Agent" })
        if ($open.Count -eq 0) { return $true }

        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O TF-Toolkit está aberto. Feche a janela (ou o menu) do TF-Toolkit para continuar.')

        if (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Já fechou?') -DefaultKey S)) { return $false }
    }
}


function Invoke-TFToolkitSetupUninstall {
    param ([Parameter(Mandatory)][string]$Root)

    Show-TFToolkitHeader (Get-TFToolkitText 'Desinstalar o TF-Toolkit')

    if (-not (Test-TFToolkitPackageFolder -Root $Root)) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não há um TF-Toolkit nesta pasta: {0}' "$Root")
        return 1
    }

    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Pasta') -Value $Root
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Versão') -Value "$(Get-TFToolkitPackageBuild -Root $Root)"
    Write-Host ""
    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Os ajustes do Windows que o TF-Toolkit aplicou continuam. Para voltar ao que era antes, use Ajustes do Windows > Desfazer ajustes do TF-Toolkit antes de desinstalar.')
    Write-Host ""

    if (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Desinstalar o TF-Toolkit?') -DefaultKey N)) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nada foi desinstalado.')
        return 0
    }

    # A mesma pasta que a desinstalação apaga (Uninstall-TFToolkit).
    $data = "%LOCALAPPDATA%\TF-Toolkit"
    try { $data = Join-Path (Get-TFToolkitLocalAppDataPath) "TF-Toolkit" } catch { Write-Verbose "Pasta de dados: $($_.Exception.Message)" }

    $removeData = Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Apagar também os dados do TF-Toolkit (históricos, relatórios, logs e backups em {0})?' "$data") -DefaultKey N

    if (-not (Wait-TFToolkitSetupCopiesClosed -Root $Root)) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nada foi desinstalado.')
        return 0
    }

    Write-TFToolkitStatus -Type Running -Message (Get-TFToolkitText 'Desinstalando...')
    $outcome = Uninstall-TFToolkit -Root $Root -RemoveData:$removeData
    Write-Host ""

    foreach ($step in @($outcome.Steps)) { Write-TFToolkitStatus -Type Success -Message $step }
    foreach ($problem in @($outcome.Problems)) { Write-TFToolkitStatus -Type Warning -Message $problem }

    Write-Host ""

    if ($outcome.Ok) {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'TF-Toolkit desinstalado.')
        return 0
    }

    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O TF-Toolkit foi desinstalado em parte; o que ficou está acima.')
    return 1
}


function Invoke-TFToolkitSetupInstall {
    param ([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Root)

    Show-TFToolkitHeader (Get-TFToolkitText 'Instalar o TF-Toolkit')

    $build = Get-TFToolkitPackageBuild -Root $Source
    $current = $(if (Test-TFToolkitPackageFolder -Root $Root) { Get-TFToolkitPackageBuild -Root $Root } else { "" })

    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Versão') -Value "$build"
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Pasta') -Value $Root
    if ($current) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Instalada agora') -Value "$current" }
    Write-Host ""

    $newVersion = ConvertTo-TFToolkitVersion -Text $build
    $oldVersion = ConvertTo-TFToolkitVersion -Text $current

    if ($null -ne $newVersion -and $null -ne $oldVersion -and $oldVersion -gt $newVersion) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A pasta já tem uma versão mais nova ({0}).' "$current")
        $go = Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Instalar a versão {0} por cima mesmo assim?' "$build") -DefaultKey N
    }
    elseif ($current) {
        $go = Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Atualizar o TF-Toolkit para a versão {0}?' "$build") -DefaultKey S
    }
    else {
        $go = Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Instalar o TF-Toolkit?') -DefaultKey S
    }

    if (-not $go) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nada foi instalado.')
        return 0
    }

    if (-not (Wait-TFToolkitSetupCopiesClosed -Root $Root)) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nada foi instalado.')
        return 0
    }

    Write-TFToolkitStatus -Type Running -Message (Get-TFToolkitText 'Copiando os arquivos...')

    $agentWasOpen = (@(Get-TFToolkitRunningCopies -Root $Root | Where-Object { $_.Kind -eq "Agent" }).Count -gt 0)
    if ($agentWasOpen) { [void](Stop-TFToolkitAgent) }

    $outcome = Install-TFToolkitFiles -Source $Source -Target $Root -BackupFolder (Join-Path (Get-TFToolkitUpdateFolder) "anterior")

    if (-not $outcome.Ok) {
        if ($outcome.RollbackFailed) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível instalar ({0}), e alguns arquivos não voltaram sozinhos. A cópia dos arquivos anteriores está em {1}.' "$($outcome.Error)" "$($outcome.BackupFolder)")
        }
        elseif ($current) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível instalar ({0}). Nada mudou: o TF-Toolkit continua na versão {1}.' "$($outcome.Error)" "$current")
        }
        else {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível instalar: {0}.' "$($outcome.Error)")
        }

        if ($agentWasOpen) { try { [void](Start-TFToolkitAgent -Root $Root) } catch { Write-Verbose "Monitor: $($_.Exception.Message)" } }
        return 1
    }

    try {
        Register-TFToolkitInstall -Root $Root -Build $build
    }
    catch {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O TF-Toolkit não entrou em Aplicativos instalados: {0}' "$(([string]$_.Exception.Message).TrimEnd('.'))")
    }

    # O atalho do Menu Iniciar sempre; o da Área de Trabalho na primeira instalação, se a pessoa quiser (numa
    # atualização, o que já existe é regravado, para continuar abrindo esta pasta).
    foreach ($place in @(Get-TFToolkitCommonShortcutPaths)) {
        $exists = Test-Path -LiteralPath $place.Path -PathType Leaf

        if ($place.Id -eq "Desktop" -and -not $exists) {
            if ($current) { continue }
            if (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Criar também um atalho na Área de Trabalho?') -DefaultKey S)) { continue }
        }

        try {
            Save-TFToolkitInstallShortcut -Path $place.Path -Root $Root
        }
        catch {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não foi possível criar o atalho {0}: {1}' "$(if ($place.Id -eq 'Desktop') { (Get-TFToolkitText 'na Área de Trabalho') } else { (Get-TFToolkitText 'no Menu Iniciar') })" "$(([string]$_.Exception.Message).TrimEnd('.'))")
        }
    }

    # Os atalhos desta conta que abriam a pasta extraída passam a abrir a instalada; onde o instalador já pôs o atalho para
    # todos os usuários, o desta conta sai (ficaria repetido no Menu Iniciar ou na Área de Trabalho).
    foreach ($place in @(Get-TFToolkitShortcutLocation)) {
        if (Test-TFToolkitShortcutOpens -Path $place.Path -Root $Source) {
            try {
                if (Test-TFToolkitInstallerShortcut -Id $place.Id -Root $Root) { Remove-Item -LiteralPath $place.Path -Force -ErrorAction Stop }
                else { Save-TFToolkitInstallShortcut -Path $place.Path -Root $Root }
            }
            catch {
                Write-Verbose "Atalho: $($_.Exception.Message)"
            }
        }
    }

    # O monitor e a manutenção mensal que abriam outra pasta do TF-Toolkit (a extraída do zip) passam a abrir a instalada:
    # as atualizações trocam só ela, e a outra pasta pode ser apagada. Com a conta de outro Administrador, o monitor é o
    # da conta de quem usa o PC (a entrada dele não está aqui) e fica como está.
    if (-not (Test-TFToolkitUserContextMismatch)) {
        try {
            if (Move-TFToolkitAgentEntry -Root $Root) {
                Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O monitor na bandeja passa a abrir da pasta instalada.')
                $agentScript = Get-TFToolkitAgentScriptPath -Root $Root

                if (@(Get-TFToolkitAgentProcesses | Where-Object { ([string]$_.CommandLine).IndexOf($agentScript, [StringComparison]::OrdinalIgnoreCase) -lt 0 }).Count -gt 0) {
                    [void](Stop-TFToolkitAgent)
                    $agentWasOpen = $true
                }
            }
        }
        catch {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O monitor na bandeja continua abrindo da pasta antiga ({0}); para trocar, use Sobre o TF-Toolkit > Monitor na bandeja.' "$(([string]$_.Exception.Message).TrimEnd('.'))")
        }
    }

    try {
        $schedule = Get-TFToolkitScheduleStatus
        $console = Join-Path $Root "TF-Toolkit.Console.ps1"

        if ($schedule.Installed -and $schedule.Enabled -and -not $schedule.OtherUser -and $schedule.ScriptPath -and
            (Split-Path -Leaf $schedule.ScriptPath) -ieq "TF-Toolkit.Console.ps1" -and -not (Test-TFToolkitSchedulePathSame -Path $schedule.ScriptPath -Other $console)) {
            $day = $(if ($null -ne $schedule.Day -and [int]$schedule.Day -ge 1 -and [int]$schedule.Day -le 28) { [int]$schedule.Day } else { 1 })
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'A manutenção mensal rodava o TF-Toolkit de outra pasta; ela passa a rodar o da pasta instalada.')
            [void](Register-TFToolkitScheduledMaintenance -Day $day -Root $Root)
        }
    }
    catch {
        Write-Verbose "Manutenção mensal: $($_.Exception.Message)"
    }

    if ($agentWasOpen) { try { [void](Start-TFToolkitAgent -Root $Root) } catch { Write-Verbose "Monitor: $($_.Exception.Message)" } }

    Write-Host ""
    Write-TFToolkitStatus -Type Success -Message $(if ($current) { (Get-TFToolkitText 'TF-Toolkit atualizado para a versão {0}.' "$build") } else { (Get-TFToolkitText 'TF-Toolkit instalado em {0}.' "$Root") })
    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Ele está no Menu Iniciar e em Configurações > Aplicativos, de onde também se desinstala.')

    if (-not (Test-TFToolkitPathInside -Path $Source -Folder $Root)) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'A pasta extraída do zip já pode ser apagada: {0}' "$Source")
    }

    Write-Host ""

    if (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Abrir o TF-Toolkit agora?') -DefaultKey S) {
        # Pelo Explorador, o TF-Toolkit abre na sessão da pessoa (e pede o Administrador ele mesmo), e não herda a elevação
        # deste instalador, que pode ser de outra conta.
        try { Start-Process -FilePath "explorer.exe" -ArgumentList "`"$(Join-Path $Root 'TF-Toolkit.cmd')`"" -ErrorAction Stop } catch { Open-TFToolkitCopy -Root $Root -Kind Gui }
        return -1
    }

    return 0
}


# --- Execução ------------------------------------------------------------------------------------------
$exitCode = 0
$source = Get-TFToolkitFullPath -Path $PSScriptRoot

try {
    $registration = Get-TFToolkitInstallRegistration

    if ($Uninstall) {
        $root = $(if ($Target) { Get-TFToolkitFullPath -Path $Target } elseif ($null -ne $registration) { $registration.Location } else { $source })

        # O Setup da pasta instalada não apaga a própria pasta enquanto roda dela: uma cópia na pasta temporária continua.
        if (-not $FromTemp -and (Test-TFToolkitPathInside -Path $source -Folder $root)) {
            $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("TF-Toolkit-uninstall-{0}" -f [guid]::NewGuid().ToString("N"))

            foreach ($relative in @(Get-TFToolkitPackageFiles -Root $source)) { Copy-TFToolkitFile -From (Join-Path $source $relative) -To (Join-Path $temp $relative) }

            $arguments = "-NoProfile -ExecutionPolicy Bypass -File $(ConvertTo-TFToolkitCommandLineArgument -Value (Join-Path $temp 'TF-Toolkit.Setup.ps1')) -Uninstall -Target $(ConvertTo-TFToolkitCommandLineArgument -Value $root) -FromTemp -Relaunched"
            Start-Process -FilePath (Get-TFToolkitPowerShellPath) -ArgumentList $arguments -WorkingDirectory $temp -ErrorAction Stop
            Stop-TFToolkitLogging
            exit 0
        }

        $exitCode = Invoke-TFToolkitSetupUninstall -Root $root
    }
    else {
        $root = $(if ($Target) { Get-TFToolkitFullPath -Path $Target } elseif ($null -ne $registration -and (Test-TFToolkitPackageFolder -Root $registration.Location)) { $registration.Location } else { Join-Path $env:ProgramFiles "TF-Toolkit" })

        if (Test-TFToolkitSamePath -Path $source -Other $root) {
            # Aberto da pasta instalada: não há o que copiar; a única coisa a fazer daqui é desinstalar.
            Show-TFToolkitHeader "TF-Toolkit"
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O TF-Toolkit já está instalado nesta pasta. Para atualizar, use Sobre o TF-Toolkit > Verificar nova versão.')
            Write-Host ""

            if (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Desinstalar o TF-Toolkit?') -DefaultKey N) {
                $arguments = "-NoProfile -ExecutionPolicy Bypass -File $(ConvertTo-TFToolkitCommandLineArgument -Value $PSCommandPath) -Uninstall -Relaunched"
                Start-Process -FilePath (Get-TFToolkitPowerShellPath) -ArgumentList $arguments -ErrorAction Stop
                Stop-TFToolkitLogging
                exit 0
            }
        }
        else {
            $exitCode = Invoke-TFToolkitSetupInstall -Source $source -Root $root
        }
    }
}
catch {
    $exitCode = 1
    Write-Host ""
    Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O instalador encontrou um erro: {0}' "$(ConvertTo-TFToolkitReadableError -Text $_.Exception.Message)")
}

Stop-TFToolkitLogging

# A cópia da pasta temporária que desinstalou sai depois que este processo fechar.
if ($FromTemp -and $source -like "$([System.IO.Path]::GetTempPath().TrimEnd('\'))*") {
    try {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c timeout /t 3 /nobreak >nul & rmdir /s /q `"$source`"" -WindowStyle Hidden -ErrorAction Stop
    }
    catch {
        Write-Verbose "Pasta temporária: $($_.Exception.Message)"
    }
}

# -1: o TF-Toolkit foi aberto; a janela do instalador fecha sem esperar.
if ($exitCode -ne -1) { Wait-TFToolkitSetupKey }

exit $(if ($exitCode -eq -1) { 0 } else { $exitCode })
