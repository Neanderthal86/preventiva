#requires -Version 5.1
<#
.SYNOPSIS
    TF-Toolkit no terminal: menus de texto para manutenção, diagnóstico e ajustes do Windows.

.DESCRIPTION
    A versão com janela é TF-Toolkit.Gui.ps1 (abra pelo TF-Toolkit.cmd). As duas usam os mesmos módulos e a mesma
    tabela de navegação (modules\Navigation.psm1), então oferecem as mesmas ações na mesma ordem.

.PARAMETER Action
    Menu     - abre o menu interativo (padrão).
    Report   - gera o relatório HTML/TXT e termina.
    Shortcut - cria o atalho do TF-Toolkit (com o ícone) na Área de Trabalho e termina. Não pede Administrador.
    ScheduledMaintenance - o que a tarefa da Manutenção agendada executa: limpa os temporários do usuário com mais de
               7 dias, salva o relatório e termina, sem perguntas e sem pedir Administrador (uma tarefa em segundo plano não pode
               esperar por um pedido de elevação).
    Check    - verificação rápida e só de leitura: nota de saúde e nota de segurança (sem a consulta ao Windows Update).
               Não pede Administrador, não grava log e não pergunta nada, então serve para tarefas e scripts. O código
               de saída diz o resultado: 0 tudo em dia, 1 pontos de atenção, 2 algo crítico, 3 não foi possível avaliar.

.PARAMETER Json
    Somente com -Action Check: escreve o resultado como JSON (UTF-8) em vez do texto, e nada mais na saída.

.PARAMETER ReportDirectory
    Pasta de saída do relatório (somente com -Action Report). Padrão: %LOCALAPPDATA%\TF-Toolkit\reports.

.PARAMETER Language
    O idioma do menu: pt (português), en (inglês) ou es (espanhol). Sem ele, vale a escolha em Sobre o TF-Toolkit > Idioma
    ou, sem escolha, o idioma do Windows (português, inglês ou espanhol; qualquer outro, inglês).

.PARAMETER PauseAtEnd
    Espera uma tecla antes de fechar. É passado automaticamente quando o script se reabre como Administrador,
    para que a janela nova não suma antes de o resultado ser lido.
#>
[CmdletBinding()]
param (
    [string]$Action = "Menu",

    [string]$ReportDirectory,

    [switch]$Json,

    [string]$Language,

    [switch]$PauseAtEnd
)

$ErrorActionPreference = "Continue"

function Get-TFToolkitStartupText {
    # As mensagens de antes dos módulos (ou de quando eles não carregaram). Com o Core carregado, valem Get-TFToolkitText e
    # o idioma do TF-Toolkit; sem ele, estas poucas mensagens trazem a tradução aqui mesmo, pelo idioma do Windows.
    param ([string]$Text)

    $command = Get-Command -Name Get-TFToolkitText -CommandType Function -ErrorAction SilentlyContinue

    if ($null -ne $command) { return (& $command $Text @args) }

    $table = @{
        "Não foi possível abrir a janela do TF-Toolkit. Abra o TF-Toolkit de novo." = @("The TF-Toolkit window could not be opened. Open TF-Toolkit again.", "No se pudo abrir la ventana de TF-Toolkit. Abre TF-Toolkit de nuevo.")
        "Módulo obrigatório não encontrado: {0}" = @("Required module not found: {0}", "No se encontró un módulo necesario: {0}")
        "Arquivo da janela não encontrado: {0}" = @("Window file not found: {0}", "No se encontró el archivo de la ventana: {0}")
        "Extraia de novo o TF-Toolkit.zip inteiro (Extrair tudo), numa pasta sem colchetes no nome, e abra o TF-Toolkit da pasta extraída." = @("Extract the whole TF-Toolkit.zip again (Extract all) to a folder without brackets in its name, and open TF-Toolkit from the extracted folder.", "Vuelve a extraer todo TF-Toolkit.zip (Extraer todo) en una carpeta sin corchetes en el nombre y abre TF-Toolkit desde la carpeta extraída.")
        "O TF-Toolkit não abriu porque falta um arquivo dele: {0}.`n`n{1} Se o arquivo sumir outra vez, veja se o antivírus o pôs em quarentena." = @("TF-Toolkit did not open because one of its files is missing: {0}.`n`n{1} If the file disappears again, check whether the antivirus quarantined it.", "TF-Toolkit no se abrió porque falta uno de sus archivos: {0}.`n`n{1} Si el archivo vuelve a desaparecer, revisa si el antivirus lo puso en cuarentena.")
        "O TF-Toolkit não abriu.`n`n{0} Se continuar, mande este detalhe ao suporte:`n`n{1}" = @("TF-Toolkit did not open.`n`n{0} If it keeps happening, send this detail to support:`n`n{1}", "TF-Toolkit no se abrió.`n`n{0} Si sigue pasando, envía este detalle al soporte:`n`n{1}")
        "Ação desconhecida: '{0}'. Use -Action Menu, Report, Shortcut, ScheduledMaintenance ou Check." = @("Unknown action: '{0}'. Use -Action Menu, Report, Shortcut, ScheduledMaintenance or Check.", "Acción desconocida: '{0}'. Usa -Action Menu, Report, Shortcut, ScheduledMaintenance o Check.")
        "O -Json só vale com -Action Check (a verificação rápida)." = @("-Json only works with -Action Check (the quick check).", "-Json solo funciona con -Action Check (la verificación rápida).")
        "Idioma desconhecido: '{0}'. Use -Language pt, en ou es." = @("Unknown language: '{0}'. Use -Language pt, en or es.", "Idioma desconocido: '{0}'. Usa -Language pt, en o es.")
        "Arquivo de módulos não encontrado: {0}" = @("Module list not found: {0}", "No se encontró la lista de módulos: {0}")
        "Extraia o TF-Toolkit por completo antes de executar." = @("Extract all of TF-Toolkit before running it.", "Extrae TF-Toolkit por completo antes de ejecutarlo.")
        "Não foi possível carregar o TF-Toolkit: {0}" = @("TF-Toolkit could not be loaded: {0}", "No se pudo cargar TF-Toolkit: {0}")
    }

    $language = ""

    try { $language = [string][System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName } catch { $language = "" }

    if ($env:WINFORGE_LANG) { $language = ([string]$env:WINFORGE_LANG).Trim().ToLowerInvariant() }

    if ($language -ne "pt" -and $table.ContainsKey($Text)) { $Text = $table[$Text][$(if ($language -eq "es") { 1 } else { 0 })] }

    if ($args.Count -gt 0) { return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $Text, [object[]]$args) }

    return $Text
}

# O idioma pedido vale para este processo (e para a reabertura como Administrador, que o recebe de novo).
if (-not [string]::IsNullOrWhiteSpace($Language)) {
    if ($Language.Trim().ToLowerInvariant() -notin @("pt", "en", "es")) {
        Write-Host (Get-TFToolkitStartupText 'Idioma desconhecido: ''{0}''. Use -Language pt, en ou es.' "$Language") -ForegroundColor Red
        exit 1
    }

    $Language = $Language.Trim().ToLowerInvariant()
    $env:WINFORGE_LANG = $Language
}

# A ação é conferida aqui, e não com ValidateSet: um nome errado ("-Action Relatorio") recebe a lista em português, e
# não o erro em inglês do PowerShell. Maiúsculas e minúsculas não importam.
$knownActions = @("Menu", "Report", "Shortcut", "ScheduledMaintenance", "Check")
$matchedAction = @($knownActions | Where-Object { $_ -ieq $Action })

if ($matchedAction.Count -eq 0) {
    Write-Host (Get-TFToolkitStartupText 'Ação desconhecida: ''{0}''. Use -Action Menu, Report, Shortcut, ScheduledMaintenance ou Check.' "$Action") -ForegroundColor Red
    exit 1
}

$Action = $matchedAction[0]

if ($Json -and $Action -ne "Check") {
    Write-Host (Get-TFToolkitStartupText 'O -Json só vale com -Action Check (a verificação rápida).') -ForegroundColor Red
    exit 1
}

# --- Módulos (lista em modules\Modules.psd1) ---------------------------------------------------------
$moduleRoot = Join-Path $PSScriptRoot "modules"
$manifestPath = Join-Path $moduleRoot "Modules.psd1"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Host (Get-TFToolkitStartupText 'Arquivo de módulos não encontrado: {0}' "$manifestPath") -ForegroundColor Red
    Write-Host (Get-TFToolkitStartupText 'Extraia o TF-Toolkit por completo antes de executar.') -ForegroundColor Yellow
    exit 1
}

try {
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath -ErrorAction Stop

    foreach ($name in (@($manifest.Common) + @($manifest.Console))) {
        $modulePath = Join-Path $moduleRoot "$name.psm1"

        if (-not (Test-Path -LiteralPath $modulePath)) {
            throw (Get-TFToolkitStartupText 'Módulo obrigatório não encontrado: {0}' "$modulePath")
        }

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
    Write-Host (Get-TFToolkitStartupText 'Não foi possível carregar o TF-Toolkit: {0}' "$($_.Exception.Message)") -ForegroundColor Red
    exit 1
}

Initialize-TFToolkitEnvironment

# --- Administrador -----------------------------------------------------------------------------------
# Uma pasta de relatório relativa ("-ReportDirectory .\saida") vale a partir de onde o comando foi digitado: o .cmd
# entra na pasta do TF-Toolkit e a reabertura como Administrador começa em System32, então o caminho vira absoluto aqui.
if (-not [string]::IsNullOrWhiteSpace($ReportDirectory) -and -not [System.IO.Path]::IsPathRooted($ReportDirectory)) {
    $callerFolder = $(if ($env:WINFORGE_CALLER_DIR) { $env:WINFORGE_CALLER_DIR } else { (Get-Location).ProviderPath })
    $ReportDirectory = [System.IO.Path]::GetFullPath((Join-Path $callerFolder $ReportDirectory))
}

$relaunchArguments = @()

if ($Action -ne "Menu") {
    $relaunchArguments += "-Action $Action"
}

if (-not [string]::IsNullOrWhiteSpace($Language)) {
    $relaunchArguments += "-Language $Language"
}

if (-not [string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $relaunchArguments += "-ReportDirectory $(ConvertTo-TFToolkitCommandLineArgument -Value $ReportDirectory)"
}

if ($Action -eq "Report") {
    $relaunchArguments += "-PauseAtEnd"
}

# O atalho é criado pela pessoa que executa (a Área de Trabalho dela); elevar poderia usar o perfil de outro usuário.
# A manutenção agendada roda em segundo plano com o usuário logado e sem elevação, então não há quem aprove o pedido.
# A verificação rápida só lê e é feita para scripts: reabrir como Administrador abriria outra janela e perderia a saída.
if ($Action -notin "Shortcut", "ScheduledMaintenance", "Check") {
    Restart-TFToolkitAsAdministrator -ScriptPath $PSCommandPath -ExtraArguments $relaunchArguments
}

# --- Execução ----------------------------------------------------------------------------------------
$exitCode = 0

# A verificação rápida não grava log: a saída precisa ficar limpa e uma tarefa que roda sempre não deve encher a pasta.
if ($Action -ne "Check") {
    [void](Start-TFToolkitLogging)
}

try {
    if ($Action -eq "Report") {
        Write-Host (Get-TFToolkitText 'Gerando relatório...') -ForegroundColor Cyan

        $report = Export-TFToolkitReport -Directory $ReportDirectory
        Write-Host (Get-TFToolkitText 'HTML : {0}' "$($report.Html)") -ForegroundColor Green

        # O HTML vale sozinho; a cópia em texto que não pôde ser gravada é avisada, sem esconder o HTML salvo.
        if ($report.Text) { Write-Host (Get-TFToolkitText 'Texto: {0}' "$($report.Text)") -ForegroundColor Green }
        else { Write-Host (Get-TFToolkitText 'Texto: não foi gravado ({0})' "$($report.TextProblem)") -ForegroundColor Yellow }

        if ($PauseAtEnd) {
            Write-Host ""
            Wait-TFToolkitKey -Message (Get-TFToolkitText 'Pressione qualquer tecla para fechar...')
        }
    }
    elseif ($Action -eq "ScheduledMaintenance") {
        $scheduled = @(Invoke-TFToolkitScheduledMaintenance) | Select-Object -Last 1

        if ($scheduled.Kind -eq "Failed") {
            $exitCode = 1
        }
    }
    elseif ($Action -eq "Check") {
        $check = Get-TFToolkitCheckReport

        if ($Json) {
            Write-Output (ConvertTo-TFToolkitCheckJson -Report $check)
        }
        else {
            Show-TFToolkitCheckReport -Report $check
        }

        $exitCode = [int]$check.ExitCode
    }
    elseif ($Action -eq "Shortcut") {
        $shortcut = New-TFToolkitAppShortcut -Location Desktop -Embedded -PassThru

        if ($shortcut.Kind -eq "Failed") {
            $exitCode = 1
        }
    }
    else {
        # Sem isto, a janela do terminal se chamaria "Administrador: C:\Windows\System32\...\powershell.exe".
        try { $Host.UI.RawUI.WindowTitle = "TF-Toolkit" } catch { Write-Verbose "Título da janela: $($_.Exception.Message)" }

        try { Add-TFToolkitOpenTime -Kind "Console" -Seconds ((Get-Date) - (Get-Process -Id $PID).StartTime).TotalSeconds } catch { Write-Verbose "Tempo de abertura: $($_.Exception.Message)" }

        # Aberto pelo instalador depois de uma atualização: diz como ela terminou, uma vez.
        try {
            $update = Read-TFToolkitUpdateResult

            if ($null -ne $update) {
                $message = Get-TFToolkitUpdateResultText -Result $update
                Write-Host ""
                Write-TFToolkitStatus -Type $(if ($message.Ok) { "Success" } else { "Warning" }) -Message $message.Text
                Write-Host ""
                Wait-TFToolkitKey
            }
        }
        catch {
            Write-Verbose "Resultado da atualização: $($_.Exception.Message)"
        }

        Show-TFToolkitMainMenu
    }
}
catch {
    $exitCode = 1
    Write-Host ""
    $failure = $_.Exception.Message
    try { $failure = ConvertTo-TFToolkitReadableError -Text $failure } catch { }
    Write-Host (Get-TFToolkitText 'O TF-Toolkit encontrou um erro e precisa fechar: {0}' "$failure") -ForegroundColor Red

    # Aberto pelo TF-Toolkit-Console.cmd (WINFORGE_FROM_CMD), quem pausa é o .cmd, uma vez só.
    if (($PauseAtEnd -or $Action -eq "Menu") -and $env:WINFORGE_FROM_CMD -ne "1") {
        Wait-TFToolkitKey -Message (Get-TFToolkitText 'Pressione qualquer tecla para fechar...')
    }
}
finally {
    Stop-TFToolkitLogging
}

exit $exitCode
