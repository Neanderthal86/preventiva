# Instalação do TF-Toolkit: copiar os arquivos de uma versão para a pasta do TF-Toolkit (instalar e atualizar, com volta
# ao que era se algo falhar), a entrada em Aplicativos instalados e a desinstalação. Quem usa: o TF-Toolkit.Setup.ps1
# (instalar, desinstalar e a troca de arquivos da atualização) e Sobre o TF-Toolkit > Verificar nova versão.
#
# Os arquivos do TF-Toolkit são os da raiz (TF-Toolkit*.cmd, TF-Toolkit.*.ps1, README*.md, CHANGELOG.md, LICENSE e o
# SHA256SUMS.txt do zip) e os das pastas modules, gui, lang e assets. Só eles são trocados ou apagados: o que a pessoa
# puser na pasta fica. O tools\New-TFToolkitPackage.ps1 monta o zip da versão com esta mesma lista.

$script:TFToolkitUninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TF-Toolkit"
$script:TFToolkitPackageFolders = @("modules", "gui", "lang", "assets")
$script:TFToolkitPackageRootFiles = @("TF-Toolkit*.cmd", "TF-Toolkit.*.ps1", "README*.md", "CHANGELOG.md", "LICENSE", "SHA256SUMS.txt")
$script:TFToolkitPublisher = "Tech Fontes"
# Quanto esperar o TF-Toolkit fechar antes de trocar os arquivos (segundos).
$script:TFToolkitUpdateWaitSeconds = 120
# Um resultado de atualização mais velho que isto não é mostrado (a janela abriu muito depois, por outro caminho).
$script:TFToolkitUpdateResultHours = 6


# ---------------------------------------------------------------------------
# O pacote
# ---------------------------------------------------------------------------

function Get-TFToolkitFullPath {
    # O caminho completo, sem a barra do fim: duas grafias da mesma pasta ("C:\TF-Toolkit\" e "C:\tf-toolkit") comparam iguais.
    param ([Parameter(Mandatory)][string]$Path)

    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd([char[]]@('\', '/'))
}


function Test-TFToolkitSamePath {
    param ([string]$Path, [string]$Other)

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Other)) { return $false }

    return ((Get-TFToolkitFullPath -Path $Path) -ieq (Get-TFToolkitFullPath -Path $Other))
}


function Test-TFToolkitPathInside {
    # Se Path está dentro de Folder (ou é a própria pasta).
    param ([string]$Path, [string]$Folder)

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Folder)) { return $false }

    $full = Get-TFToolkitFullPath -Path $Path
    $base = Get-TFToolkitFullPath -Path $Folder

    return ($full -ieq $base -or $full.StartsWith($base + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))
}


function Get-TFToolkitPackageFiles {
    # Os arquivos do TF-Toolkit numa pasta, como caminhos relativos a ela (modules\Core.psm1). Lista vazia se a pasta não existe.
    param ([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }

    $base = Get-TFToolkitFullPath -Path $Root
    $files = New-Object System.Collections.Generic.List[string]

    foreach ($pattern in $script:TFToolkitPackageRootFiles) {
        # O -like confirma o nome: o -Filter do Windows também compara com o nome curto (8.3) do arquivo.
        foreach ($file in @(Get-ChildItem -LiteralPath $base -Filter $pattern -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern })) {
            if (-not $files.Contains($file.Name)) { $files.Add($file.Name) }
        }
    }

    foreach ($folder in $script:TFToolkitPackageFolders) {
        $path = Join-Path $base $folder

        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }

        foreach ($file in @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction Stop)) {
            $files.Add($file.FullName.Substring($base.Length + 1))
        }
    }

    return @($files | Sort-Object -Unique)
}


function Get-TFToolkitPackageBuild {
    # A versão escrita no Core.psm1 de uma pasta do TF-Toolkit ("" quando não dá para ler).
    param ([Parameter(Mandatory)][string]$Root)

    try {
        $core = Join-Path (Join-Path $Root "modules") "Core.psm1"
        $match = [regex]::Match([System.IO.File]::ReadAllText($core, [System.Text.Encoding]::UTF8), '\$script:TFToolkitBuild\s*=\s*"([0-9.]+)"')

        if ($match.Success) { return $match.Groups[1].Value }
    }
    catch {
        Write-Verbose "Versão do pacote: $($_.Exception.Message)"
    }

    return ""
}


function Test-TFToolkitPackageFolder {
    # Se a pasta tem um TF-Toolkit inteiro (os scripts de entrada e os módulos): só uma pasta assim vira instalação.
    param ([Parameter(Mandatory)][string]$Root)

    foreach ($name in @("TF-Toolkit.Gui.ps1", "TF-Toolkit.Console.ps1", "TF-Toolkit.cmd", "modules\Modules.psd1", "modules\Core.psm1", "gui\MainWindow.xaml")) {
        $path = $Root

        foreach ($part in ($name -split '\\')) { $path = Join-Path $path $part }

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    }

    return $true
}


function Expand-TFToolkitReleasePackage {
    <#
    Extrai o zip de uma versão numa pasta vazia e devolve a pasta que tem os arquivos (a "TF-Toolkit" de dentro do zip).
    Cada arquivo é conferido: nenhum nome do zip sai da pasta de destino ("..\", caminho absoluto).
    #>
    param (
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Root = ""
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $base = Get-TFToolkitFullPath -Path $Destination

    Remove-TFToolkitFolder -Path $base

    [void](New-Item -ItemType Directory -Path $base -Force -ErrorAction Stop)

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

    try {
        foreach ($entry in $zip.Entries) {
            $name = ([string]$entry.FullName).Replace('\', '/')

            if ($name.EndsWith("/") -or $name.Length -eq 0) { continue }

            $relative = $name.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $path = [System.IO.Path]::GetFullPath((Join-Path $base $relative))

            if (-not $path.StartsWith($base + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw (Get-TFToolkitText 'o pacote tem um arquivo fora da pasta do TF-Toolkit ({0}) e não foi usado' "$name")
            }

            $folder = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop) }

            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $path, $true)
        }
    }
    finally {
        $zip.Dispose()
    }

    $folder = $(if ($Root) { Join-Path $base $Root } else { $base })

    if (-not (Test-TFToolkitPackageFolder -Root $folder)) {
        throw (Get-TFToolkitText 'o pacote não tem todos os arquivos do TF-Toolkit')
    }

    return $folder
}


# ---------------------------------------------------------------------------
# A troca dos arquivos
# ---------------------------------------------------------------------------

function Copy-TFToolkitFile {
    # Copia um arquivo por cima de outro, criando a pasta; um arquivo somente leitura no destino não impede a troca.
    param ([Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To)

    $folder = Split-Path -Parent $To
    if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop) }

    if ([System.IO.File]::Exists($To)) { [System.IO.File]::SetAttributes($To, [System.IO.FileAttributes]::Normal) }

    [System.IO.File]::Copy($From, $To, $true)
}


function Install-TFToolkitFiles {
    <#
    Troca os arquivos do TF-Toolkit da pasta Target pelos da pasta Source, como uma coisa só: primeiro guarda em
    BackupFolder uma cópia de cada arquivo do TF-Toolkit que está em Target; depois copia os novos, apaga os que a versão
    nova não tem e confere cada um pelo SHA-256. Se qualquer passo falha, tudo volta ao que era (os arquivos novos saem,
    os guardados voltam). Devolve Ok, Copied, Removed, Error, RolledBack e RollbackFailed (algum arquivo não voltou: a
    cópia guardada continua em BackupFolder).
    #>
    param (
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$BackupFolder
    )

    $result = [PSCustomObject]@{ Ok = $false; Copied = 0; Removed = 0; Error = ""; RolledBack = $false; RollbackFailed = $false; BackupFolder = $BackupFolder }

    $from = Get-TFToolkitFullPath -Path $Source
    $to = Get-TFToolkitFullPath -Path $Target
    $backup = Get-TFToolkitFullPath -Path $BackupFolder

    if ($from -ieq $to) {
        $result.Error = (Get-TFToolkitText 'a versão nova já está nesta pasta')
        return $result
    }

    if (-not (Test-TFToolkitPackageFolder -Root $from)) {
        $result.Error = (Get-TFToolkitText 'a pasta da versão nova não tem todos os arquivos do TF-Toolkit')
        return $result
    }

    if ((Test-TFToolkitPathInside -Path $backup -Folder $to) -or (Test-TFToolkitPathInside -Path $backup -Folder $from)) {
        $result.Error = (Get-TFToolkitText 'a pasta da cópia de segurança não pode ficar dentro da pasta do TF-Toolkit')
        return $result
    }

    $newFiles = @()
    $oldFiles = @()
    $written = New-Object System.Collections.Generic.List[string]
    $removed = New-Object System.Collections.Generic.List[string]

    try {
        $newFiles = @(Get-TFToolkitPackageFiles -Root $from)
        $oldFiles = @(Get-TFToolkitPackageFiles -Root $to)

        if (-not (Test-Path -LiteralPath $to)) { [void](New-Item -ItemType Directory -Path $to -Force -ErrorAction Stop) }
        Remove-TFToolkitFolder -Path $backup
        [void](New-Item -ItemType Directory -Path $backup -Force -ErrorAction Stop)

        foreach ($relative in $oldFiles) { Copy-TFToolkitFile -From (Join-Path $to $relative) -To (Join-Path $backup $relative) }

        foreach ($relative in $newFiles) {
            Copy-TFToolkitFile -From (Join-Path $from $relative) -To (Join-Path $to $relative)
            $written.Add($relative)
        }

        foreach ($relative in @($oldFiles | Where-Object { $newFiles -notcontains $_ })) {
            $path = Join-Path $to $relative
            [System.IO.File]::SetAttributes($path, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($path)
            $removed.Add($relative)
        }

        foreach ($relative in $newFiles) {
            $expected = (Get-FileHash -LiteralPath (Join-Path $from $relative) -Algorithm SHA256 -ErrorAction Stop).Hash
            $actual = (Get-FileHash -LiteralPath (Join-Path $to $relative) -Algorithm SHA256 -ErrorAction Stop).Hash

            if ($expected -ne $actual) { throw (Get-TFToolkitText 'o arquivo {0} não foi gravado como devia' "$relative") }
        }

        # A marca de "baixado da internet" faria o Windows perguntar antes de cada script.
        foreach ($relative in $newFiles) {
            try { Unblock-File -LiteralPath (Join-Path $to $relative) -ErrorAction Stop } catch { Write-Verbose "Desbloqueio: $($_.Exception.Message)" }
        }

        $result.Ok = $true
        $result.Copied = $written.Count
        $result.Removed = $removed.Count
    }
    catch {
        $result.Error = (ConvertTo-TFToolkitReadableError -Text ([string]$_.Exception.Message)).TrimEnd('.')
        $result.RolledBack = $true

        foreach ($relative in @($written) + @($removed)) {
            $path = Join-Path $to $relative
            $saved = Join-Path $backup $relative

            try {
                if ($oldFiles -contains $relative) {
                    Copy-TFToolkitFile -From $saved -To $path
                }
                elseif ([System.IO.File]::Exists($path)) {
                    [System.IO.File]::SetAttributes($path, [System.IO.FileAttributes]::Normal)
                    [System.IO.File]::Delete($path)
                }
            }
            catch {
                $result.RollbackFailed = $true
            }
        }
    }

    return $result
}


# ---------------------------------------------------------------------------
# Aplicativos instalados
# ---------------------------------------------------------------------------

function Get-TFToolkitInstallRegistration {
    # A entrada do TF-Toolkit em Aplicativos instalados: Location (a pasta) e Version, ou $null quando não está instalado.
    try {
        if (-not (Test-Path -LiteralPath $script:TFToolkitUninstallKey)) { return $null }

        $key = Get-ItemProperty -LiteralPath $script:TFToolkitUninstallKey -ErrorAction Stop
        $location = [string](Get-TFToolkitJsonValue -Object $key -Name "InstallLocation" -Default "")

        if ([string]::IsNullOrWhiteSpace($location)) { return $null }

        return [PSCustomObject]@{ Location = $location.TrimEnd('\'); Version = [string](Get-TFToolkitJsonValue -Object $key -Name "DisplayVersion" -Default "") }
    }
    catch {
        return $null
    }
}


function Test-TFToolkitInstalledHere {
    # Se esta cópia do TF-Toolkit é a que está em Aplicativos instalados.
    param ([string]$Root = (Get-TFToolkitAppRoot))

    $registration = Get-TFToolkitInstallRegistration

    return ($null -ne $registration -and (Test-TFToolkitSamePath -Path $registration.Location -Other $Root))
}


function Get-TFToolkitFolderSizeKb {
    param ([Parameter(Mandatory)][string]$Root)

    $bytes = 0L

    foreach ($relative in @(Get-TFToolkitPackageFiles -Root $Root)) {
        try { $bytes += (Get-Item -LiteralPath (Join-Path $Root $relative) -Force).Length } catch { Write-Verbose "Tamanho: $($_.Exception.Message)" }
    }

    return [int][Math]::Ceiling($bytes / 1KB)
}


function Get-TFToolkitInstallLinks {
    # Os endereços da entrada em Aplicativos instalados: o site (sobre o TF-Toolkit), as issues do GitHub (ajuda) e a página
    # de versões (atualização). A entrada é do PC, e não de um idioma: o site vai pela raiz.
    return [ordered]@{
        URLInfoAbout  = (Get-TFToolkitWebsiteUrl -Language "pt")
        HelpLink      = "https://github.com/$(Get-TFToolkitRepository)/issues"
        URLUpdateInfo = "https://github.com/$(Get-TFToolkitRepository)/releases"
    }
}


function Register-TFToolkitInstall {
    # Grava a entrada em Aplicativos instalados (Configurações > Aplicativos), de onde o TF-Toolkit se desinstala.
    param (
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Build
    )

    $setup = Join-Path $Root "TF-Toolkit.Setup.ps1"
    $uninstall = "$(ConvertTo-TFToolkitCommandLineArgument -Value (Get-TFToolkitPowerShellPath)) -NoProfile -ExecutionPolicy Bypass -File $(ConvertTo-TFToolkitCommandLineArgument -Value $setup) -Uninstall"

    if (-not (Test-Path -LiteralPath $script:TFToolkitUninstallKey)) { [void](New-Item -Path $script:TFToolkitUninstallKey -Force -ErrorAction Stop) }

    $links = Get-TFToolkitInstallLinks

    $values = [ordered]@{
        DisplayName     = "TF-Toolkit"
        DisplayVersion  = $Build
        Publisher       = $script:TFToolkitPublisher
        InstallLocation = $Root
        DisplayIcon     = (Join-Path (Join-Path $Root "assets") "TF-Toolkit.ico")
        UninstallString = $uninstall
        URLInfoAbout    = $links.URLInfoAbout
        HelpLink        = $links.HelpLink
        URLUpdateInfo   = $links.URLUpdateInfo
        InstallDate     = (Get-Date).ToString("yyyyMMdd", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    foreach ($name in $values.Keys) {
        Set-ItemProperty -LiteralPath $script:TFToolkitUninstallKey -Name $name -Value ([string]$values[$name]) -Type String -ErrorAction Stop
    }

    foreach ($flag in @("NoModify", "NoRepair")) {
        Set-ItemProperty -LiteralPath $script:TFToolkitUninstallKey -Name $flag -Value 1 -Type DWord -ErrorAction Stop
    }

    Set-ItemProperty -LiteralPath $script:TFToolkitUninstallKey -Name "EstimatedSize" -Value (Get-TFToolkitFolderSizeKb -Root $Root) -Type DWord -ErrorAction Stop
}


function Update-TFToolkitInstallVersion {
    # Depois de atualizar a pasta que está em Aplicativos instalados, a versão, os endereços e o tamanho de lá acompanham.
    # Sem entrada (uma pasta extraída, não instalada), nada muda.
    param (
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Build
    )

    $registration = Get-TFToolkitInstallRegistration

    if ($null -eq $registration -or -not (Test-TFToolkitSamePath -Path $registration.Location -Other $Root)) { return $false }

    try {
        Set-ItemProperty -LiteralPath $script:TFToolkitUninstallKey -Name "DisplayVersion" -Value $Build -Type String -ErrorAction Stop

        # Uma entrada gravada por uma versão anterior passa a levar ao site e às issues de agora.
        $links = Get-TFToolkitInstallLinks
        foreach ($name in $links.Keys) {
            Set-ItemProperty -LiteralPath $script:TFToolkitUninstallKey -Name $name -Value ([string]$links[$name]) -Type String -ErrorAction Stop
        }

        Set-ItemProperty -LiteralPath $script:TFToolkitUninstallKey -Name "EstimatedSize" -Value (Get-TFToolkitFolderSizeKb -Root $Root) -Type DWord -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}


function Unregister-TFToolkitInstall {
    if (Test-Path -LiteralPath $script:TFToolkitUninstallKey) { Remove-Item -LiteralPath $script:TFToolkitUninstallKey -Recurse -Force -ErrorAction Stop }
}


# ---------------------------------------------------------------------------
# Atalhos e processos de uma pasta do TF-Toolkit
# ---------------------------------------------------------------------------

function Get-TFToolkitCommonShortcutPaths {
    # Os atalhos para todos os usuários que o instalador cria: Menu Iniciar e Área de Trabalho.
    $paths = @()

    foreach ($special in @("CommonPrograms", "CommonDesktopDirectory")) {
        try {
            $folder = [string][Environment]::GetFolderPath($special)
            if ($folder) { $paths += [PSCustomObject]@{ Id = $(if ($special -eq "CommonPrograms") { "StartMenu" } else { "Desktop" }); Folder = $folder; Path = (Join-Path $folder "TFToolkit.lnk") } }
        }
        catch {
            Write-Verbose "Pasta comum: $($_.Exception.Message)"
        }
    }

    return @($paths)
}


function Test-TFToolkitInstallerShortcut {
    # Se o atalho do instalador (para todos os usuários) no lugar Id (Desktop ou StartMenu) abre o TF-Toolkit da pasta Root.
    param (
        [Parameter(Mandatory)][string]$Id,
        [string]$Root = (Get-TFToolkitAppRoot)
    )

    $place = @(Get-TFToolkitCommonShortcutPaths | Where-Object { $_.Id -eq $Id })[0]
    if ($null -eq $place) { return $false }

    return (Test-TFToolkitShortcutOpens -Path $place.Path -Root $Root)
}


function Get-TFToolkitInstallStateText {
    # Como esta cópia está, numa frase: instalada (com a entrada em Aplicativos, de onde se desinstala) ou aberta direto
    # da pasta extraída (com o TF-Toolkit-Setup.cmd para instalar). Level: Normal ou Muted.
    $root = Get-TFToolkitAppRoot

    if (Test-TFToolkitInstalledHere -Root $root) {
        return [PSCustomObject]@{ Text = (Get-TFToolkitText 'instalado; para desinstalar, use Configurações > Aplicativos'); Level = "Normal" }
    }

    if (Test-Path -LiteralPath (Join-Path $root "TF-Toolkit-Setup.cmd") -PathType Leaf) {
        return [PSCustomObject]@{ Text = (Get-TFToolkitText 'sem instalar; para instalar, abra o TF-Toolkit-Setup.cmd desta pasta'); Level = "Muted" }
    }

    return [PSCustomObject]@{ Text = (Get-TFToolkitText 'sem instalar'); Level = "Muted" }
}


function Test-TFToolkitShortcutOpens {
    # Se o atalho abre o TF-Toolkit desta pasta (um atalho que não pôde ser lido não conta).
    param ([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    try {
        $target = Get-TFToolkitShortcutTarget -Path $Path
        $script = Join-Path $Root "TF-Toolkit.Gui.ps1"

        return ($null -ne $target -and ([string]$target.Arguments).IndexOf($script, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    }
    catch {
        return $false
    }
}


function Save-TFToolkitInstallShortcut {
    # Grava (ou regrava) um atalho que abre o TF-Toolkit da pasta Root.
    param ([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)

    $launch = Get-TFToolkitLaunchDefinition -Root $Root

    [void](Save-TFToolkitShortcutFile -Path $Path -Target $launch.Executable -Arguments $launch.Arguments -WorkingDirectory $launch.WorkingDirectory `
            -IconLocation $launch.IconLocation -Description $launch.Description -AppId $launch.AppId)
}


function Get-TFToolkitRunningCopies {
    <#
    Os processos que rodam o TF-Toolkit da pasta Root (a janela, o menu de texto e o monitor), pela linha de comando. Cada
    um: ProcessId e Kind (Gui, Console ou Agent). Lista vazia quando não dá para ler. O próprio processo não entra.
    #>
    param ([Parameter(Mandatory)][string]$Root)

    $found = @()

    try {
        $processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -OperationTimeoutSec 15 -ErrorAction Stop)
    }
    catch {
        return @()
    }

    foreach ($process in $processes) {
        if ([int]$process.ProcessId -eq $PID) { continue }

        $line = [string]$process.CommandLine

        foreach ($kind in @("Gui", "Console", "Agent")) {
            $script = Join-Path $Root "TF-Toolkit.$kind.ps1"

            if ($line.IndexOf($script, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $found += [PSCustomObject]@{ ProcessId = [int]$process.ProcessId; Kind = $kind }
                break
            }
        }
    }

    return @($found)
}


function Wait-TFToolkitProcessExit {
    # Espera os processos fecharem (até Seconds). Devolve os que continuam abertos.
    param ([int[]]$ProcessId = @(), [int]$Seconds = $script:TFToolkitUpdateWaitSeconds)

    $deadline = (Get-Date).AddSeconds($Seconds)

    do {
        $open = @($ProcessId | Where-Object { $_ -gt 0 -and $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue) })
        if ($open.Count -eq 0) { return @() }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return @($open)
}


# ---------------------------------------------------------------------------
# Atualizar com um clique (Verificar nova versão)
# ---------------------------------------------------------------------------

function Get-TFToolkitUpdateFolder {
    return (Join-Path (Get-TFToolkitDataPath) "update")
}


function Test-TFToolkitFolderWritable {
    # Se esta conta consegue gravar na pasta (um arquivo de teste, criado e apagado na hora).
    param ([Parameter(Mandatory)][string]$Root)

    $probe = Join-Path $Root (".tf-toolkit-gravar-{0}.tmp" -f [guid]::NewGuid().ToString("N"))

    try {
        [System.IO.File]::WriteAllText($probe, "")
        [System.IO.File]::Delete($probe)
        return $true
    }
    catch {
        return $false
    }
}


function Test-TFToolkitMenuBatchHost {
    <#
    Se o cmd foi aberto só para rodar o TF-Toolkit-Console.cmd (cmd /c: dois cliques, o PowerShell, o próprio instalador):
    ele fecha logo depois do menu, e a troca espera por ele. O cmd de um Prompt de Comando aberto à mão (sem /c) roda o
    .cmd por dentro e só fecha quando a pessoa fecha o prompt: esperar por ele travaria a atualização.
    #>
    param ([AllowEmptyString()][string]$CommandLine)

    return ($CommandLine -match '(?i)(^|\s)/c(\s|")' -and $CommandLine -match '(?i)TF-Toolkit-Console\.cmd')
}


function Start-TFToolkitUpdateInstall {
    <#
    Prepara a troca de arquivos da atualização e devolve se ela começou. O zip conferido é extraído em
    %LOCALAPPDATA%\TF-Toolkit\update\pacote, e o TF-Toolkit.Setup.ps1 da versão nova é aberto com -Update: ele espera este
    TF-Toolkit fechar (este processo e, no menu de texto, o cmd que o abriu), troca os arquivos, volta ao que era se algo
    falhar e abre o TF-Toolkit de novo. Quem chama fecha o TF-Toolkit (Request-TFToolkitAppExit). Sem conseguir gravar na
    pasta do TF-Toolkit, o Setup pede o Administrador (o aviso do Windows; recusado, a função lança erro).
    #>
    param (
        [Parameter(Mandatory)][string]$ZipPath,
        [string]$PackageRoot = "TF-Toolkit",
        [ValidateSet("Gui", "Console")][string]$Reopen = "Gui"
    )

    $source = Expand-TFToolkitReleasePackage -ZipPath $ZipPath -Destination (Join-Path (Get-TFToolkitUpdateFolder) "pacote") -Root $PackageRoot
    $setup = Join-Path $source "TF-Toolkit.Setup.ps1"

    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw (Get-TFToolkitText 'a versão nova não tem o instalador (TF-Toolkit.Setup.ps1)') }

    $wait = @($PID)

    # No menu de texto, o cmd que abriu o PowerShell continua lendo o TF-Toolkit-Console.cmd até o fim: a troca espera ele,
    # quando ele foi aberto só para isso (Test-TFToolkitMenuBatchHost).
    try {
        $parent = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $PID" -OperationTimeoutSec 15 -ErrorAction Stop
        $parentId = [int](Get-TFToolkitJsonValue -Object $parent -Name "ParentProcessId" -Default 0)

        if ($parentId -gt 0) {
            $parentProcess = Get-Process -Id $parentId -ErrorAction SilentlyContinue

            if ($null -ne $parentProcess -and $parentProcess.ProcessName -ieq "cmd") {
                $parentInfo = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $parentId" -OperationTimeoutSec 15 -ErrorAction Stop
                if (Test-TFToolkitMenuBatchHost -CommandLine ([string](Get-TFToolkitJsonValue -Object $parentInfo -Name "CommandLine" -Default ""))) { $wait += $parentId }
            }
        }
    }
    catch {
        Write-Verbose "Processo pai: $($_.Exception.Message)"
    }

    $root = Get-TFToolkitAppRoot
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $(ConvertTo-TFToolkitCommandLineArgument -Value $setup) -Update -Target $(ConvertTo-TFToolkitCommandLineArgument -Value $root) -WaitProcessId $($wait -join ',') -Reopen $Reopen"

    # O resultado anterior sairia como se fosse desta atualização.
    Remove-Item -LiteralPath (Join-Path (Get-TFToolkitUpdateFolder) "result.json") -Force -ErrorAction SilentlyContinue

    if ((Test-TFToolkitAdministrator) -or (Test-TFToolkitFolderWritable -Root $root)) {
        Start-Process -FilePath (Get-TFToolkitPowerShellPath) -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory (Get-TFToolkitUpdateFolder) -ErrorAction Stop
    }
    else {
        try {
            Start-Process -FilePath (Get-TFToolkitPowerShellPath) -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -WorkingDirectory (Get-TFToolkitUpdateFolder) -ErrorAction Stop
        }
        catch {
            throw (Get-TFToolkitText 'trocar os arquivos desta pasta pede o Administrador, e o pedido do Windows foi recusado')
        }
    }

    return $true
}


function Save-TFToolkitUpdateResult {
    param (
        [string]$From = "",
        [string]$To = "",
        [bool]$Ok = $false,
        [string]$ErrorText = "",
        [bool]$RollbackFailed = $false
    )

    $folder = Get-TFToolkitUpdateFolder
    if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force) }

    $document = [ordered]@{ From = $From; To = $To; Ok = $Ok; Error = $ErrorText; RollbackFailed = $RollbackFailed; At = (Get-Date).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    Write-TFToolkitStateJson -Path (Join-Path $folder "result.json") -InputObject $document
}


function Read-TFToolkitUpdateResult {
    <#
    O resultado da última atualização, uma vez só (o arquivo é apagado ao ler): From, To, Ok, Error e RollbackFailed. $null
    quando não há, ou quando é velho demais para ser desta abertura. Depois de uma atualização que deu certo, a pasta do
    pacote extraído sai também.
    #>
    $folder = Get-TFToolkitUpdateFolder
    $path = Join-Path $folder "result.json"

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }

    $read = Read-TFToolkitStateFile -Path $path
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$path.bak" -Force -ErrorAction SilentlyContinue

    if ($read.Status -notin @("Ok", "Recovered") -or $null -eq $read.Document) { return $null }

    $document = $read.Document
    $at = [datetime]::MinValue

    if (-not [datetime]::TryParse([string](Get-TFToolkitJsonValue -Object $document -Name "At" -Default ""), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$at)) { return $null }
    if (((Get-Date) - $at).TotalHours -gt $script:TFToolkitUpdateResultHours) { return $null }

    $ok = [bool](Get-TFToolkitJsonValue -Object $document -Name "Ok" -Default $false)

    if ($ok) { Remove-TFToolkitFolder -Path (Join-Path $folder "pacote") -Quiet }

    return [PSCustomObject]@{
        From           = [string](Get-TFToolkitJsonValue -Object $document -Name "From" -Default "")
        To             = [string](Get-TFToolkitJsonValue -Object $document -Name "To" -Default "")
        Ok             = $ok
        Error          = [string](Get-TFToolkitJsonValue -Object $document -Name "Error" -Default "")
        RollbackFailed = [bool](Get-TFToolkitJsonValue -Object $document -Name "RollbackFailed" -Default $false)
    }
}


function Get-TFToolkitUpdateResultText {
    # A mensagem que a janela (ou o menu) mostra ao abrir depois de uma atualização: Title e Text.
    param ([Parameter(Mandatory)]$Result)

    if ($Result.Ok) {
        return [PSCustomObject]@{ Ok = $true; Title = (Get-TFToolkitText 'TF-Toolkit atualizado'); Text = (Get-TFToolkitText 'O TF-Toolkit foi atualizado para a versão {0}.' "$($Result.To)") }
    }

    $text = $(if ($Result.RollbackFailed) {
            (Get-TFToolkitText 'A atualização para a versão {0} não foi concluída ({1}), e alguns arquivos não voltaram sozinhos. A cópia dos arquivos anteriores está em {2}; se o TF-Toolkit não abrir direito, extraia de novo o TF-Toolkit.zip na pasta dele.' "$($Result.To)" "$($Result.Error)" "$(Join-Path (Get-TFToolkitUpdateFolder) 'anterior')")
        }
        else {
            (Get-TFToolkitText 'A atualização para a versão {0} não foi concluída ({1}). Nada mudou: o TF-Toolkit continua na versão {2}.' "$($Result.To)" "$($Result.Error)" "$($Result.From)")
        })

    return [PSCustomObject]@{ Ok = $false; Title = (Get-TFToolkitText 'Atualização não concluída'); Text = $text }
}


function Install-TFToolkitUpdatePackage {
    <#
    O lado do Setup na atualização (TF-Toolkit.Setup.ps1 -Update): roda da pasta da versão nova, sem janela. Espera o
    TF-Toolkit fechar, fecha o monitor desta pasta, troca os arquivos (com a volta ao que era), atualiza a versão em
    Aplicativos instalados, abre o monitor de novo se ele estava aberto e grava o resultado para o TF-Toolkit mostrar ao
    abrir. Abre o TF-Toolkit de novo em qualquer caso: na versão nova, ou na mesma, com o motivo.
    #>
    param (
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [int[]]$WaitProcessId = @(),
        [ValidateSet("", "Gui", "Console")][string]$Reopen = ""
    )

    $from = Get-TFToolkitPackageBuild -Root $Target
    $to = Get-TFToolkitPackageBuild -Root $Source
    $agentWasOpen = $false
    $outcome = $null
    $errorText = ""

    try {
        $still = @(Wait-TFToolkitProcessExit -ProcessId $WaitProcessId)

        # Um instante a mais: o cmd de um Prompt de Comando aberto à mão (que a troca não espera) ainda lê as últimas
        # linhas do TF-Toolkit-Console.cmd depois que o menu fecha.
        if ($still.Count -eq 0) { Start-Sleep -Seconds 2 }

        if (-not (Test-TFToolkitPackageFolder -Root $Target)) {
            # Só uma pasta que já tem o TF-Toolkit é atualizada: o Setup nunca troca arquivos de uma pasta qualquer.
            $errorText = (Get-TFToolkitText 'a pasta {0} não tem o TF-Toolkit' "$Target")
        }
        elseif ($still.Count -gt 0) {
            $errorText = (Get-TFToolkitText 'o TF-Toolkit não fechou a tempo')
        }
        elseif (@(Get-TFToolkitRunningCopies -Root $Target | Where-Object { $_.Kind -ne "Agent" }).Count -gt 0) {
            # Outra janela ou outro menu desta pasta continua aberto: trocar os arquivos por baixo dele não é seguro.
            $errorText = (Get-TFToolkitText 'outra janela do TF-Toolkit continua aberta')
        }
        else {
            $agentWasOpen = (@(Get-TFToolkitRunningCopies -Root $Target | Where-Object { $_.Kind -eq "Agent" }).Count -gt 0)
            if ($agentWasOpen) { [void](Stop-TFToolkitAgent) }

            $outcome = Install-TFToolkitFiles -Source $Source -Target $Target -BackupFolder (Join-Path (Get-TFToolkitUpdateFolder) "anterior")

            if ($outcome.Ok) { [void](Update-TFToolkitInstallVersion -Root $Target -Build $to) } else { $errorText = $outcome.Error }
        }
    }
    catch {
        $errorText = ([string]$_.Exception.Message).TrimEnd('.')
    }

    $ok = ($null -ne $outcome -and $outcome.Ok)

    # Sem conseguir gravar o resultado, o TF-Toolkit abre do mesmo jeito (só sem a mensagem).
    try { Save-TFToolkitUpdateResult -From $from -To $to -Ok $ok -ErrorText $errorText -RollbackFailed ($null -ne $outcome -and $outcome.RollbackFailed) } catch { Write-Verbose "Resultado: $($_.Exception.Message)" }

    if ($agentWasOpen) {
        try { [void](Start-TFToolkitAgent -Root $Target) } catch { Write-Verbose "Monitor: $($_.Exception.Message)" }
    }

    if ($Reopen) { Open-TFToolkitCopy -Root $Target -Kind $Reopen -Page "app" }

    return $ok
}


function Open-TFToolkitCopy {
    # Abre a janela (ou o menu de texto) do TF-Toolkit da pasta Root, numa execução nova.
    param (
        [Parameter(Mandatory)][string]$Root,
        [ValidateSet("Gui", "Console")][string]$Kind = "Gui",
        [string]$Page = ""
    )

    try {
        if ($Kind -eq "Console") {
            Start-Process -FilePath (Join-Path $Root "TF-Toolkit-Console.cmd") -WorkingDirectory $Root -ErrorAction Stop
            return
        }

        $arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File $(ConvertTo-TFToolkitCommandLineArgument -Value (Join-Path $Root 'TF-Toolkit.Gui.ps1'))"
        if ($Page -match '^[a-z]+$') { $arguments += " -Page $Page" }

        Start-Process -FilePath (Get-TFToolkitPowerShellPath) -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $Root -ErrorAction Stop
    }
    catch {
        Write-Verbose "Abrir o TF-Toolkit: $($_.Exception.Message)"
    }
}


# ---------------------------------------------------------------------------
# Desinstalar
# ---------------------------------------------------------------------------

function Remove-TFToolkitEmptyFolders {
    # Apaga as pastas do TF-Toolkit que ficaram vazias (de dentro para fora) e, vazia, a própria pasta Root.
    param ([Parameter(Mandatory)][string]$Root)

    foreach ($folder in $script:TFToolkitPackageFolders) {
        $path = Join-Path $Root $folder
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }

        foreach ($child in @(Get-ChildItem -LiteralPath $path -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
            if (@(Get-ChildItem -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue }
        }

        if (@(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }

    if ((Test-Path -LiteralPath $Root -PathType Container) -and @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue
    }
}


function Get-TFToolkitSetupFiles {
    <#
    Os arquivos de que o TF-Toolkit.Setup.ps1 precisa para desinstalar desta pasta, como caminhos relativos: ele mesmo, os
    scripts que mostram que a pasta é do TF-Toolkit (Test-TFToolkitPackageFolder), os módulos que ele carrega, as traduções e
    o ícone da entrada em Aplicativos instalados.
    #>
    param ([Parameter(Mandatory)][string]$Root)

    $files = @("TF-Toolkit.Setup.ps1", "TF-Toolkit-Setup.cmd", "TF-Toolkit.Gui.ps1", "TF-Toolkit.Console.ps1", "TF-Toolkit.cmd",
        (Join-Path "modules" "Modules.psd1"), (Join-Path "modules" "Core.psm1"), (Join-Path "gui" "MainWindow.xaml"), (Join-Path "assets" "TF-Toolkit.ico"))

    try {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path (Join-Path $Root "modules") "Modules.psd1") -ErrorAction Stop
        foreach ($name in @($manifest.Common)) { $files += (Join-Path "modules" "$name.psm1") }
    }
    catch {
        Write-Verbose "Módulos do Setup: $($_.Exception.Message)"
    }

    foreach ($file in @(Get-TFToolkitPackageFiles -Root $Root)) {
        if (($file -split '[\\/]')[0] -eq "lang") { $files += $file }
    }

    return @($files | Select-Object -Unique)
}


function Remove-TFToolkitPackageFileList {
    # Apaga arquivos do TF-Toolkit (caminhos relativos a Root). O que não sai na primeira vez (preso por um instante, pelo
    # antivírus ou pelo indexador) ganha mais uma tentativa um segundo depois. Devolve os que ficaram.
    param (
        [Parameter(Mandatory)][string]$Root,
        [string[]]$Files = @()
    )

    $left = @($Files)

    for ($attempt = 0; $attempt -lt 2 -and $left.Count -gt 0; $attempt++) {
        if ($attempt -gt 0) { Start-Sleep -Seconds 1 }

        $failed = @()

        foreach ($relative in $left) {
            $path = Join-Path $Root $relative

            try {
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    [System.IO.File]::SetAttributes($path, [System.IO.FileAttributes]::Normal)
                    [System.IO.File]::Delete($path)
                }
            }
            catch {
                $failed += $relative
            }
        }

        $left = @($failed)
    }

    return @($left)
}


function Get-TFToolkitInteractiveUserPlaces {
    <#
    Com o TF-Toolkit elevado pela conta de outro Administrador: onde ficam o monitor e os atalhos da conta de quem usa o PC
    (a chave Run dela e as pastas Área de Trabalho e Menu Iniciar\Programas), para o desinstalar alcançá-los. $null fora
    desse caso ou sem leitura (a conta precisa estar com a sessão aberta).
    #>
    if (-not (Test-TFToolkitUserContextMismatch)) { return $null }

    try {
        $account = Get-TFToolkitInteractiveUser
        $sid = (New-Object System.Security.Principal.NTAccount($account)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $hive = "Registry::HKEY_USERS\$sid"

        if (-not (Test-Path -LiteralPath $hive)) { return $null }

        $folders = Get-ItemProperty -LiteralPath "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -ErrorAction Stop
        $shortcutFolders = @(@([string](Get-TFToolkitJsonValue -Object $folders -Name "Desktop" -Default ""), [string](Get-TFToolkitJsonValue -Object $folders -Name "Programs" -Default "")) |
                Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })

        return [PSCustomObject]@{ Account = $account; RunKey = "$hive\Software\Microsoft\Windows\CurrentVersion\Run"; ShortcutFolders = @($shortcutFolders) }
    }
    catch {
        Write-Verbose "Conta de quem usa o PC: $($_.Exception.Message)"
        return $null
    }
}


function Uninstall-TFToolkit {
    <#
    Tira o TF-Toolkit da pasta Root e do Windows: fecha o monitor e tira a entrada que o abre com o Windows, apaga a
    manutenção agendada desta pasta, os atalhos que abrem esta pasta (os do instalador e os criados pelo TF-Toolkit), a
    entrada em Aplicativos instalados e os arquivos do TF-Toolkit (o que a pessoa pôs na pasta fica). -RemoveData apaga
    também %LOCALAPPDATA%\TF-Toolkit (históricos, relatórios, logs e backups). Os ajustes do Windows aplicados continuam.
    Devolve Ok, Steps (o que foi feito) e Problems (o que não deu).
    #>
    param (
        [Parameter(Mandatory)][string]$Root,
        [switch]$RemoveData
    )

    $steps = @()
    $problems = @()

    # Elevado pela conta de outro Administrador, o monitor e os atalhos da conta de quem usa o PC também saem.
    $person = Get-TFToolkitInteractiveUserPlaces

    # O monitor: fecha e não abre mais com o Windows (se a entrada é desta pasta).
    try {
        if (@(Get-TFToolkitRunningCopies -Root $Root | Where-Object { $_.Kind -eq "Agent" }).Count -gt 0) { [void](Stop-TFToolkitAgent) }

        $agentScript = Join-Path $Root "TF-Toolkit.Agent.ps1"
        $removedEntry = Remove-TFToolkitAgentStaleEntry -ScriptPath $agentScript
        if ($null -ne $person -and (Remove-TFToolkitAgentStaleEntry -ScriptPath $agentScript -RunKey $person.RunKey)) { $removedEntry = $true }
        if ($removedEntry) { $steps += (Get-TFToolkitText 'monitor na bandeja desligado') }
    }
    catch {
        $problems += (Get-TFToolkitText 'monitor na bandeja: {0}' "$(([string]$_.Exception.Message).TrimEnd('.'))")
    }

    # A manutenção agendada, se ela roda esta pasta.
    try {
        $schedule = Get-TFToolkitScheduleStatus

        if ($schedule.Installed -and $schedule.ScriptPath -and (Test-TFToolkitPathInside -Path $schedule.ScriptPath -Folder $Root)) {
            $removed = Unregister-TFToolkitScheduledMaintenance
            if ($removed.Kind -eq "Ok") { $steps += (Get-TFToolkitText 'manutenção agendada removida') } else { $problems += (Get-TFToolkitText 'manutenção agendada: {0}' "$($removed.Detail)") }
        }
    }
    catch {
        $problems += (Get-TFToolkitText 'manutenção agendada: {0}' "$(([string]$_.Exception.Message).TrimEnd('.'))")
    }

    # O que sobrou de uma execução sem Administrador interrompida (uma tarefa de uma vez só, sem horário): nunca dá erro.
    Remove-TFToolkitLimitedRunLeftovers -All

    # Os atalhos que abrem esta pasta: os do instalador (todos os usuários) e os que o TF-Toolkit criou para esta conta (e
    # para a de quem usa o PC).
    $links = @(Get-TFToolkitCommonShortcutPaths | ForEach-Object { $_.Path })
    $names = @("TFToolkit.lnk")

    foreach ($place in @(Get-TFToolkitShortcutLocation)) {
        $links += $place.Path
        $names += (Split-Path -Leaf $place.Path)
    }

    if ($null -ne $person) {
        foreach ($folder in @($person.ShortcutFolders)) {
            foreach ($name in @($names | Select-Object -Unique)) { $links += (Join-Path $folder $name) }
        }
    }

    $linkCount = 0

    foreach ($link in @($links | Select-Object -Unique)) {
        if (-not (Test-TFToolkitShortcutOpens -Path $link -Root $Root)) { continue }

        try {
            Remove-Item -LiteralPath $link -Force -ErrorAction Stop
            $linkCount++
        }
        catch {
            $problems += (Get-TFToolkitText 'atalho {0}: {1}' "$link" "$(([string]$_.Exception.Message).TrimEnd('.'))")
        }
    }

    if ($linkCount -gt 0) { $steps += (Format-TFToolkitCount -Count $linkCount -One (Get-TFToolkitText 'atalho removido') -Many (Get-TFToolkitText 'atalhos removidos')) }

    # Os arquivos do TF-Toolkit (e as pastas que ficarem vazias). Os de que desinstalar precisa (Get-TFToolkitSetupFiles)
    # saem por último, só quando todos os outros saíram: com algum arquivo preso, o TF-Toolkit continua em Aplicativos
    # instalados, e desinstalar de novo por lá termina o serviço.
    $files = @(Get-TFToolkitPackageFiles -Root $Root)
    $setupFiles = @(Get-TFToolkitSetupFiles -Root $Root)
    $failed = @(Remove-TFToolkitPackageFileList -Root $Root -Files @($files | Where-Object { $setupFiles -notcontains $_ }))
    $keepEntry = ($failed.Count -gt 0)

    if (-not $keepEntry) { $failed = @(Remove-TFToolkitPackageFileList -Root $Root -Files @($files | Where-Object { $setupFiles -contains $_ })) }

    Remove-TFToolkitEmptyFolders -Root $Root

    # Aplicativos instalados: a entrada sai com os arquivos.
    if (-not $keepEntry) {
        try {
            $registration = Get-TFToolkitInstallRegistration

            if ($null -ne $registration -and (Test-TFToolkitSamePath -Path $registration.Location -Other $Root)) {
                Unregister-TFToolkitInstall
                $steps += (Get-TFToolkitText 'saiu de Aplicativos instalados')
            }
        }
        catch {
            $problems += (Get-TFToolkitText 'Aplicativos instalados: {0}' "$(([string]$_.Exception.Message).TrimEnd('.'))")
        }
    }

    if ($failed.Count -gt 0) {
        $problems += $(if ($failed.Count -eq 1) { (Get-TFToolkitText '1 arquivo não pôde ser apagado de {0}' "$Root") }
            else { (Get-TFToolkitText '{0} não puderam ser apagados de {1}' "$(Format-TFToolkitCount -Count $failed.Count -One (Get-TFToolkitText 'arquivo') -Many (Get-TFToolkitText 'arquivos'))" "$Root") })
        if ($keepEntry -and (Test-TFToolkitInstalledHere -Root $Root)) { $problems += (Get-TFToolkitText 'o TF-Toolkit continua em Configurações > Aplicativos: desinstale de novo por lá para terminar') }
    }
    else {
        $steps += (Get-TFToolkitText 'arquivos do TF-Toolkit apagados')
    }

    if (Test-Path -LiteralPath $Root -PathType Container) { $steps += (Get-TFToolkitText 'a pasta {0} ficou, com o que não é do TF-Toolkit' "$Root") }

    if ($RemoveData) {
        try {
            # Sempre um caminho completo: um "TF-Toolkit" relativo apagaria a pasta de mesmo nome do diretório atual.
            $data = Join-Path (Get-TFToolkitLocalAppDataPath) "TF-Toolkit"

            # O log desta desinstalação fica aberto até o fim: tudo o mais sai.
            Stop-TFToolkitLogging
            Remove-TFToolkitFolder -Path $data
            $steps += (Get-TFToolkitText 'dados do TF-Toolkit apagados')
        }
        catch {
            $problems += (Get-TFToolkitText 'dados do TF-Toolkit: {0}' "$(([string]$_.Exception.Message).TrimEnd('.'))")
        }
    }

    return [PSCustomObject]@{ Ok = ($problems.Count -eq 0); Steps = @($steps); Problems = @($problems) }
}


Export-ModuleMember -Function *
