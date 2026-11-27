# Backup antes de formatar o PC e restauração depois da reinstalação do Windows.
#
# O backup guarda o que é difícil de lembrar: a lista de programas (para reinstalar pelo winget), os drivers de
# terceiros, os ajustes do TF-Toolkit e, se a pessoa quiser, as redes Wi-Fi salvas. Documentos, fotos e outros arquivos
# pessoais NÃO são copiados: o LEIA-ME do backup lista as pastas e os tamanhos para a pessoa copiar à parte.
#
# Nada aqui altera o Windows: o backup só lê e grava dentro da pasta escolhida. A restauração é quem instala.


# ---------------------------------------------------------------------------
# Nomes e pastas
# ---------------------------------------------------------------------------

function Get-TFToolkitBackupDefaultRoot {
    # Documentos\TF-Toolkit\Backups: fica no mesmo disco do Windows, então o fluxo avisa para copiar para fora dele.
    return (Join-Path (Get-TFToolkitTweakExportFolder) "Backups")
}


function Test-TFToolkitBackupInCloudFolder {
    # Se a pasta fica dentro do OneDrive (pessoal ou corporativo): o que é gravado ali vai para a nuvem.
    param (
        [AllowEmptyString()][string]$Path
    )

    return (Test-TFToolkitOneDrivePath -Path $Path)
}


function New-TFToolkitBackupFolderName {
    param (
        [datetime]$At = (Get-Date)
    )

    return "Backup-$([Environment]::MachineName)-$($At.ToString('yyyy-MM-dd-HHmm', [System.Globalization.CultureInfo]::InvariantCulture))"
}


function Get-TFToolkitBackupFileNames {
    # Onde cada coisa fica dentro da pasta do backup.
    return [PSCustomObject]@{
        Manifest     = "backup.json"
        Readme       = "LEIA-ME.txt"
        WingetList   = "programas-winget.json"
        ProgramsList = "programas-instalados.csv"
        Drivers      = "drivers"
        Tweaks       = "ajustes-TFToolkit.json"
        Wifi         = "wifi"
    }
}


function Get-TFToolkitBackupItems {
    # Os itens que o backup pode incluir. Admin: exige privilégios de Administrador.
    return @(
        @{ Id = "programs"; Label = (Get-TFToolkitText 'Programas instalados'); Description = (Get-TFToolkitText 'A lista para reinstalar pelo winget'); Selected = $true }
        @{ Id = "drivers"; Label = (Get-TFToolkitText 'Drivers de terceiros'); Description = (Get-TFToolkitText 'Vídeo, rede, som...; ocupa de centenas de MB a alguns GB'); Selected = $true }
        @{ Id = "tweaks"; Label = (Get-TFToolkitText 'Ajustes do TF-Toolkit'); Description = (Get-TFToolkitText 'Quais ajustes você aplicou, para repetir no Windows novo'); Selected = $true }
        @{ Id = "wifi"; Label = (Get-TFToolkitText 'Redes Wi-Fi salvas, com as senhas'); Description = (Get-TFToolkitText 'As senhas ficam em texto puro nos arquivos: guarde o backup em local seguro'); Selected = $false }
    )
}


# ---------------------------------------------------------------------------
# Leitura do que está instalado
# ---------------------------------------------------------------------------

function ConvertTo-TFToolkitInstalledProgram {
    <#
    Uma entrada da chave Uninstall do registro vira Name, Version e Publisher; $null para o que não é um programa de
    verdade (sem nome, componente do sistema, atualização ou parte de outro programa).
    #>
    param (
        $Properties
    )

    $name = [string](Get-TFToolkitJsonValue -Object $Properties -Name "DisplayName" -Default "")

    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    if ([int](Get-TFToolkitJsonValue -Object $Properties -Name "SystemComponent" -Default 0) -eq 1) { return $null }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-TFToolkitJsonValue -Object $Properties -Name "ParentKeyName" -Default ""))) { return $null }
    if ([string](Get-TFToolkitJsonValue -Object $Properties -Name "ReleaseType" -Default "") -match '^(Update|Hotfix|Security Update|Service Pack)') { return $null }
    if ($name -match '^(Update for|Security Update for|Hotfix for) ') { return $null }

    return [PSCustomObject]@{
        Name      = $name.Trim()
        Version   = [string](Get-TFToolkitJsonValue -Object $Properties -Name "DisplayVersion" -Default "")
        Publisher = [string](Get-TFToolkitJsonValue -Object $Properties -Name "Publisher" -Default "")
    }
}


function Get-TFToolkitInstalledProgramList {
    # Os programas que o Windows lista em "Aplicativos instalados", lidos do registro (sem winget). Ordenado por nome, sem repetições.
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $programs = @()

    foreach ($root in $roots) {
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $program = ConvertTo-TFToolkitInstalledProgram -Properties (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue)

            if ($null -ne $program) {
                $programs += $program
            }
        }
    }

    return @($programs | Sort-Object -Property Name, Version -Unique)
}


function Get-TFToolkitWingetExportCount {
    # Quantos pacotes há num arquivo de "winget export". $null quando o arquivo não existe ou não é um JSON do winget.
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        $document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }

    $sources = @(Get-TFToolkitJsonValue -Object $document -Name "Sources" -Default @())
    $count = 0

    foreach ($source in $sources) {
        $count += @(Get-TFToolkitJsonValue -Object $source -Name "Packages" -Default @()).Count
    }

    if ($sources.Count -eq 0) {
        return $null
    }

    return $count
}


# ---------------------------------------------------------------------------
# Itens do backup
# ---------------------------------------------------------------------------

function Export-TFToolkitBackupPrograms {
    param (
        [Parameter(Mandatory)]
        [string]$Folder
    )

    $names = Get-TFToolkitBackupFileNames
    $wingetFile = Join-Path $Folder $names.WingetList
    $csvFile = Join-Path $Folder $names.ProgramsList

    $wingetCount = $null
    $wingetNote = ""

    if (Test-TFToolkitWinget) {
        Write-Progress -Activity (Get-TFToolkitText 'Backup antes de formatar') -Status (Get-TFToolkitText 'exportando a lista de programas do winget (pode levar um minuto)')

        try {
            $run = Invoke-TFToolkitCapture -FilePath "winget" -Arguments @("export", "-o", $wingetFile, "--accept-source-agreements", "--disable-interactivity")
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Backup antes de formatar') -Completed
        }

        $wingetCount = Get-TFToolkitWingetExportCount -Path $wingetFile

        if ($null -eq $wingetCount) {
            $wingetNote = (Get-TFToolkitText 'o winget não gerou a lista ({0})' "$((Get-TFToolkitWingetExitResult -ExitCode $run.ExitCode).Detail)")
        }
    }
    else {
        $wingetNote = (Get-TFToolkitText 'o winget não foi encontrado')
    }

    $installed = @()

    try {
        $installed = @(Get-TFToolkitInstalledProgramList)

        if ($installed.Count -gt 0) {
            $installed | Select-Object Name, Version, Publisher | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Delimiter ";" -Encoding UTF8 -ErrorAction Stop
        }
    }
    catch {
        $installed = @()
    }

    $listed = Format-TFToolkitCount -Count $installed.Count -One (Get-TFToolkitText 'programa') -Many (Get-TFToolkitText 'programas')

    if ($null -ne $wingetCount) {
        # Quantos voltam sozinhos na restauração, e onde fica o resto: a lista completa é para o que se baixa à mão.
        $back = Format-TFToolkitCount -Count $wingetCount -One (Get-TFToolkitText 'programa vai ser reinstalado sozinho') -Many (Get-TFToolkitText 'programas vão ser reinstalados sozinhos')
        $rest = $(if ($installed.Count -gt 0) { (Get-TFToolkitText '; a lista completa ({0}) fica em {1}, para os que você precisa baixar à mão' "$($installed.Count)" "$($names.ProgramsList)") } else { "" })
        Write-TFToolkitStatus -Type Success -Message "$back$rest."

        return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText '{0} para reinstalar' "$(Format-TFToolkitCount -Count $wingetCount -One (Get-TFToolkitText 'programa') -Many (Get-TFToolkitText 'programas'))") -Data @{ Count = $wingetCount; Listed = $installed.Count })
    }

    if ($installed.Count -gt 0) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Só a lista completa foi salva ({0}): {1}.' "$listed" "$wingetNote")

        return (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'só a lista de consulta: {0}' "$wingetNote") -Data @{ Count = 0; Listed = $installed.Count })
    }

    Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível salvar a lista de programas: {0}.' "$wingetNote")

    return (New-TFToolkitResult -Kind Failed -Detail $wingetNote)
}


function Export-TFToolkitBackupDrivers {
    param (
        [Parameter(Mandatory)]
        [string]$Folder
    )

    $names = Get-TFToolkitBackupFileNames
    $target = Join-Path $Folder $names.Drivers
    [void](New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop)

    $firstError = ""

    Write-Progress -Activity (Get-TFToolkitText 'Backup antes de formatar') -Status (Get-TFToolkitText 'copiando os drivers de terceiros (pode levar alguns minutos)')

    try {
        try {
            [void](Export-WindowsDriver -Online -Destination $target -ErrorAction Stop)
        }
        catch {
            # O pnputil faz a mesma cópia: a tentativa fica só nos detalhes técnicos, e o resumo diz o resultado.
            $firstError = (ConvertTo-TFToolkitReadableError -Text $_.Exception.Message).TrimEnd('.')
            Write-Host (Get-TFToolkitText 'O Export-WindowsDriver não funcionou ({0}); tentando o pnputil...' "$firstError") -ForegroundColor DarkGray

            $run = Invoke-TFToolkitCapture -FilePath "pnputil" -Arguments @("/export-driver", "*", $target)

            if ($run.ExitCode -ne 0) {
                $firstError = (Get-TFToolkitText '{0}; a segunda tentativa do Windows também falhou (código {1})' "$firstError" "$($run.ExitCode)")
            }
        }
    }
    finally {
        Write-Progress -Activity (Get-TFToolkitText 'Backup antes de formatar') -Completed
    }

    $infs = @(Get-ChildItem -LiteralPath $target -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue)

    if ($infs.Count -eq 0) {
        $reason = if ($firstError) { $firstError } else { (Get-TFToolkitText 'o Windows não devolveu nenhum driver') }
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Nenhum driver foi copiado: {0}.' "$reason")

        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nenhum driver copiado'))
    }

    $bytes = [int64](Get-TFToolkitPathStats -Path $target).Size
    $size = Format-TFToolkitBytes -Bytes $bytes
    $count = Format-TFToolkitCount -Count $infs.Count -One (Get-TFToolkitText 'driver') -Many (Get-TFToolkitText 'drivers')
    Write-TFToolkitStatus -Type Success -Message "$(Format-TFToolkitCount -Count $infs.Count -One (Get-TFToolkitText 'driver copiado') -Many (Get-TFToolkitText 'drivers copiados')) ($size)."

    return (New-TFToolkitResult -Kind Ok -Detail "$count, $size" -Data @{ Count = $infs.Count; Size = $bytes })
}


function Export-TFToolkitBackupTweaks {
    param (
        [Parameter(Mandatory)]
        [string]$Folder
    )

    $names = Get-TFToolkitBackupFileNames
    $ids = @(Get-TFToolkitAppliedTweakIds)

    if ($ids.Count -eq 0) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhum ajuste do TF-Toolkit está aplicado neste PC; nada a guardar.')

        return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nenhum ajuste aplicado'))
    }

    Set-Content -LiteralPath (Join-Path $Folder $names.Tweaks) -Value (New-TFToolkitTweakExport -Ids $ids | ConvertTo-Json -Depth 4) -Encoding UTF8 -ErrorAction Stop
    Write-TFToolkitStatus -Type Success -Message "$(Format-TFToolkitCount -Count $ids.Count -One (Get-TFToolkitText 'ajuste do TF-Toolkit guardado') -Many (Get-TFToolkitText 'ajustes do TF-Toolkit guardados'))."

    return (New-TFToolkitResult -Kind Ok -Detail (Format-TFToolkitCount -Count $ids.Count -One (Get-TFToolkitText 'ajuste') -Many (Get-TFToolkitText 'ajustes')) -Data @{ Count = $ids.Count })
}


function Export-TFToolkitBackupWifi {
    param (
        [Parameter(Mandatory)]
        [string]$Folder
    )

    $names = Get-TFToolkitBackupFileNames
    $target = Join-Path $Folder $names.Wifi
    [void](New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop)

    Write-Progress -Activity (Get-TFToolkitText 'Backup antes de formatar') -Status (Get-TFToolkitText 'exportando as redes Wi-Fi salvas')

    # Sem o argumento folder=, o netsh grava na pasta atual: assim um caminho com espaços não vira problema de aspas.
    Push-Location -LiteralPath $target

    try {
        $run = Invoke-TFToolkitCapture -FilePath "netsh" -Arguments @("wlan", "export", "profile", "key=clear")
    }
    finally {
        Pop-Location
        Write-Progress -Activity (Get-TFToolkitText 'Backup antes de formatar') -Completed
    }

    $files = @(Get-ChildItem -LiteralPath $target -Filter "*.xml" -File -ErrorAction SilentlyContinue)

    # Com o Wi-Fi desligado (ou o serviço de rede sem fio parado), o netsh falha e não exporta nada: isso não é "nenhuma
    # rede salva", e o backup não pode terminar como se as redes estivessem guardadas.
    if ($run.ExitCode -ne 0) {
        $reason = @($run.Lines | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) | Select-Object -First 2
        $reasonText = $(if (@($reason).Count -gt 0) { (@($reason) -join " ").TrimEnd('.') } else { (Get-TFToolkitText 'código {0}' "$($run.ExitCode)") })
        $saved = $(if ($files.Count -gt 0) { (Get-TFToolkitText '; só {0}' "$(Format-TFToolkitCount -Count $files.Count -One (Get-TFToolkitText 'rede foi exportada') -Many (Get-TFToolkitText 'redes foram exportadas'))") } else { "" })

        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O Windows não exportou as redes Wi-Fi ({0}){1}. Se o PC tem Wi-Fi, ligue-o e faça o backup de novo para guardá-las.' "$reasonText" "$saved")

        return (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o Windows não exportou as redes Wi-Fi: {0}' "$reasonText") -Data @{ Count = $files.Count })
    }

    if ($files.Count -eq 0) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhuma rede Wi-Fi salva foi encontrada (ou este PC não tem Wi-Fi).')

        return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nenhuma rede Wi-Fi salva'))
    }

    Write-TFToolkitStatus -Type Success -Message "$(Format-TFToolkitCount -Count $files.Count -One (Get-TFToolkitText 'rede Wi-Fi exportada') -Many (Get-TFToolkitText 'redes Wi-Fi exportadas'))."
    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'As senhas estão em texto puro na pasta ''{0}'': não deixe este backup em nuvem pública nem em pendrive sem proteção.' "$($names.Wifi)")

    return (New-TFToolkitResult -Kind Ok -Detail (Format-TFToolkitCount -Count $files.Count -One (Get-TFToolkitText 'rede') -Many (Get-TFToolkitText 'redes')) -Data @{ Count = $files.Count })
}


# ---------------------------------------------------------------------------
# LEIA-ME e manifesto
# ---------------------------------------------------------------------------

function Get-TFToolkitBackupUserFolders {
    # As pastas pessoais com tamanho, para o LEIA-ME. Fora AppData e pastas ocultas de configuração.
    param (
        [string]$ProfilePath = $env:USERPROFILE
    )

    return @(
        Get-TFToolkitUserFolderSizes -ProfilePath $ProfilePath -Top 60 |
            Where-Object { $_.Name -notmatch '^(AppData|Application Data|Local Settings|Cookies|NetHood|PrintHood|Recent|SendTo|Start Menu|Templates|My Documents)$' -and -not $_.Name.StartsWith(".") -and $_.Size -gt 0 } |
            Sort-Object -Property Name
    )
}


function New-TFToolkitBackupReadme {
    param (
        [Parameter(Mandatory)]
        $Manifest,

        [object[]]$UserFolders = @()
    )

    $names = Get-TFToolkitBackupFileNames
    $ids = @($Manifest.Items | Where-Object { $_.Ok } | ForEach-Object { $_.Id })
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add((Get-TFToolkitText 'BACKUP DO WINFORGE'))
    $lines.Add("==================")
    $lines.Add("")
    $lines.Add((Get-TFToolkitText 'Criado em : {0}' "$(Format-TFToolkitDateTime -When ([datetime]$Manifest.CreatedAt))"))
    $lines.Add("Computador: $($Manifest.Computer)")
    $lines.Add("Windows   : $($Manifest.Windows)")
    $lines.Add("")
    $lines.Add((Get-TFToolkitText 'O QUE HÁ NESTA PASTA'))
    $lines.Add("--------------------")

    if ($ids -contains "programs") {
        $lines.Add((Get-TFToolkitText '- {0}: programas que o winget sabe reinstalar.' "$($names.WingetList)"))
        $lines.Add((Get-TFToolkitText '- {0}: lista completa dos programas, para consulta. Programas que não estão no winget (jogos,' "$($names.ProgramsList)"))
        $lines.Add((Get-TFToolkitText '  programas de empresas, instaladores antigos) precisam ser baixados à mão por esta lista.'))
    }

    if ($ids -contains "drivers") { $lines.Add((Get-TFToolkitText '- {0}\: cópia dos drivers de terceiros (placa de vídeo, rede, som, touchpad...).' "$($names.Drivers)")) }
    if ($ids -contains "tweaks") { $lines.Add((Get-TFToolkitText '- {0}: os ajustes do TF-Toolkit que estavam aplicados.' "$($names.Tweaks)")) }
    if ($ids -contains "wifi") { $lines.Add((Get-TFToolkitText '- {0}\: redes Wi-Fi salvas, COM AS SENHAS em texto puro. Guarde este backup em local seguro.' "$($names.Wifi)")) }

    $lines.Add((Get-TFToolkitText '- {0}: usado pelo TF-Toolkit para reconhecer o backup. Não apague.' "$($names.Manifest)"))
    $lines.Add("")
    $lines.Add((Get-TFToolkitText 'COMO RESTAURAR'))
    $lines.Add("--------------")
    $lines.Add((Get-TFToolkitText '1. Instale o Windows, conecte à internet e rode o Windows Update.'))
    $lines.Add((Get-TFToolkitText '2. Copie esta pasta para o PC novo (ou ligue o pendrive ou HD externo).'))
    $lines.Add((Get-TFToolkitText '3. Abra o TF-Toolkit como Administrador, vá em Programas > Restaurar a partir de um backup e escolha esta pasta.'))
    $lines.Add((Get-TFToolkitText '4. Marque o que quer restaurar. Ao final, reinicie o PC.'))
    $lines.Add("")
    $lines.Add((Get-TFToolkitText 'O QUE NÃO ESTÁ NO BACKUP (copie à parte antes de formatar)'))
    $lines.Add("---------------------------------------------------------")
    $lines.Add((Get-TFToolkitText 'Estas são as suas pastas pessoais e o tamanho de cada uma. O TF-Toolkit NÃO copiou nenhuma delas:'))

    if (@($UserFolders).Count -eq 0) {
        $lines.Add((Get-TFToolkitText '  (não foi possível listar as pastas)'))
    }
    else {
        foreach ($folder in $UserFolders) {
            $lines.Add(("  {0,-28} {1}" -f $folder.Name, (Format-TFToolkitBytes -Bytes $folder.Size)))
        }
    }

    $lines.Add("")
    $lines.Add((Get-TFToolkitText 'Lembre-se também de:'))
    $lines.Add((Get-TFToolkitText '- Favoritos e senhas do navegador: entre na conta do navegador (Edge, Chrome ou Firefox) para sincronizar, ou exporte-os.'))
    $lines.Add((Get-TFToolkitText '- Chaves e licenças de programas pagos, e contas de jogos e de lojas.'))
    $lines.Add((Get-TFToolkitText '- Arquivos que estão só em pastas fora do perfil (outros discos, C:\Dados, etc.).'))
    $lines.Add((Get-TFToolkitText '- Se usa BitLocker, a chave de recuperação.'))

    return ($lines -join "`r`n")
}


function Get-TFToolkitPcModel {
    <#
    Fabricante e modelo deste PC ("Dell Inc. Inspiron 15 3520"), para o backup lembrar de que PC ele veio: depois de
    formatar, o nome do computador costuma mudar, e o modelo, não. A Lenovo põe no modelo o tipo de máquina com a
    configuração ("20QDS00K00"): vale a família ("ThinkPad T490") ou, sem ela, o tipo de máquina (os 4 primeiros). Vazio
    sem leitura, com os textos genéricos das placas montadas ("To Be Filled By O.E.M."), que não distinguem um PC de
    outro, e numa máquina virtual, onde todas se chamam igual.
    #>
    try {
        $system = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop
    }
    catch {
        return ""
    }

    $maker = ([string](Get-TFToolkitJsonValue -Object $system -Name "Manufacturer" -Default "")).Trim()
    $model = ([string](Get-TFToolkitJsonValue -Object $system -Name "Model" -Default "")).Trim()
    $family = ([string](Get-TFToolkitJsonValue -Object $system -Name "SystemFamily" -Default "")).Trim()

    if (-not (Test-TFToolkitVendorText -Text $maker) -or -not (Test-TFToolkitVendorText -Text $model)) { return "" }
    if ($model -match '(?i)virtual machine|vmware|virtualbox|kvm|qemu') { return "" }

    if ($maker -match '(?i)lenovo') {
        if (Test-TFToolkitVendorText -Text $family) { return "$maker $family" }
        if ($model.Length -gt 4) { return "$maker $($model.Substring(0, 4))" }
    }

    return "$maker $model"
}


function New-TFToolkitBackupManifest {
    # Complete: falso enquanto o backup está em andamento (o manifesto é gravado a cada item, para que um backup
    # interrompido continue restaurável com o que já foi salvo). Backups de versões anteriores não têm o campo.
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [object[]]$UserFolders = @(),

        [datetime]$At = (Get-Date),

        [bool]$Complete = $true,

        [string]$Model = ""
    )

    $session = Get-TFToolkitSessionInfo

    return [ordered]@{
        Format      = "TFToolkit.Backup"
        Version     = 1
        Build       = (Get-TFToolkitBuild)
        CreatedAt   = $At.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        Computer    = [Environment]::MachineName
        Model       = $Model
        Windows     = "$($session.WindowsLabel) ($($session.WindowsBuild))"
        Complete    = $Complete
        Items       = @($Items)
        UserFolders = @($UserFolders | ForEach-Object { [ordered]@{ Name = $_.Name; Size = [int64]$_.Size } })
    }
}


# ---------------------------------------------------------------------------
# Fazer o backup
# ---------------------------------------------------------------------------

function Get-TFToolkitBackupDrives {
    <#
    As unidades onde vale guardar o backup: pendrives, HDs externos e outras partições prontas, menos a do Windows (a que
    vai ser formatada). Root ("E:\"), Label ("Pendrive (E:)", ou o nome que a unidade tem) e FreeBytes. Só unidades com
    letra: unidades de rede e de CD ficam de fora.
    #>
    $system = ([string]$env:SystemDrive).TrimEnd('\').ToUpperInvariant()
    $found = @()

    try {
        $all = @([System.IO.DriveInfo]::GetDrives())
    }
    catch {
        return @()
    }

    foreach ($drive in $all) {
        try {
            $root = [string]$drive.Name
            $type = [string]$drive.DriveType

            if ($root -notmatch '^[A-Za-z]:\\$' -or $type -notin @("Removable", "Fixed") -or -not $drive.IsReady) { continue }

            $letter = $root.Substring(0, 2).ToUpperInvariant()
            if ($letter -eq $system) { continue }

            $name = ([string]$drive.VolumeLabel).Trim()
            if (-not $name) { $name = $(if ($type -eq "Removable") { (Get-TFToolkitText 'Pendrive') } else { (Get-TFToolkitText 'Disco') }) }

            $found += [PSCustomObject]@{ Root = $root; Label = "$name ($letter)"; FreeBytes = [int64]$drive.AvailableFreeSpace }
        }
        catch {
            # Uma unidade que some no meio da leitura (pendrive retirado) só fica fora da lista.
            continue
        }
    }

    return @($found)
}


function Read-TFToolkitBackupDestination {
    <#
    Pergunta onde guardar. As unidades fora a do Windows (pendrive, HD externo) vêm primeiro, a primeira em destaque: o
    backup existe para sobreviver à formatação. Documentos vem sem destaque, avisando que fica no disco que vai ser
    formatado. Sem nenhuma unidade, a tela pede para conectar uma e oferece procurar de novo. Devolve Path (a pasta onde o
    backup será criado; vazio se a pessoa desistiu), OnSystemDrive (a pasta fica no disco do Windows, o que vai ser
    formatado: Documentos ou outra pasta digitada nele) e Missing (a pasta informada, quando ela não existe).
    #>
    $defaultRoot = Get-TFToolkitBackupDefaultRoot
    $none = [PSCustomObject]@{ Path = ""; OnSystemDrive = $false; Missing = "" }
    $rounds = 5
    $answer = ""
    $drives = @()

    for ($round = 1; $round -le $rounds; $round++) {
        $drives = @(Get-TFToolkitBackupDrives | Select-Object -First 9)
        $rescan = ($drives.Count -eq 0 -and $round -lt $rounds)
        $options = @()

        if ($drives.Count -eq 0) {
            $notice = $(if ($round -eq 1) { (Get-TFToolkitText 'Conecte um pendrive ou HD externo agora para guardar o backup direto nele.') } else { (Get-TFToolkitText 'Nenhum pendrive ou HD externo foi encontrado. Confira se ele aparece no Explorador de Arquivos.') })
            Write-TFToolkitStatus -Type Info -Notice -Message $notice
            Write-Host ""
        }

        if ($rescan) {
            $options += @{ Key = "P"; Label = (Get-TFToolkitText 'Procurar de novo'); Description = (Get-TFToolkitText 'Depois de conectar o pendrive ou HD externo'); Accent = $true }
        }

        for ($i = 0; $i -lt $drives.Count; $i++) {
            $options += @{ Key = [string]($i + 1); Label = $drives[$i].Label; Description = (Get-TFToolkitText '{0} livres' "$(Format-TFToolkitBytes -Bytes $drives[$i].FreeBytes)"); Accent = ($i -eq 0) }
        }

        $options += @{ Key = "D"; Label = (Get-TFToolkitText 'Documentos'); Description = (Get-TFToolkitText 'Fica no disco que vai ser formatado: copie a pasta para fora dele antes de formatar') }
        $options += @{ Key = "O"; Label = (Get-TFToolkitText 'Outra pasta ou unidade'); Description = (Get-TFToolkitText 'Uma pasta de outro disco, da rede ou do OneDrive') }
        $options += @{ Key = "X"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }

        if ($drives.Count -gt 0) {
            $defaultKey = "1"
            $prompt = (Get-TFToolkitText 'Destino (número = unidade, D = Documentos, O = outra pasta, X = cancelar; ENTER = {0})' "$($drives[0].Label)")
        }
        elseif ($rescan) {
            $defaultKey = "P"
            $prompt = (Get-TFToolkitText 'Destino (P = procurar de novo, D = Documentos, O = outra pasta, X = cancelar; ENTER = procurar de novo)')
        }
        else {
            $defaultKey = "X"
            $prompt = (Get-TFToolkitText 'Destino (D = Documentos, O = outra pasta, X = cancelar; ENTER = cancelar)')
        }

        $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Onde guardar o backup?') -DefaultKey $defaultKey -ShowMenu -TextPrompt $prompt -Options $options

        if (-not ($rescan -and $answer -ieq "P")) { break }
    }

    if ($answer -match '^[0-9]$' -and [int]$answer -ge 1 -and [int]$answer -le $drives.Count) {
        return [PSCustomObject]@{ Path = $drives[[int]$answer - 1].Root; OnSystemDrive = $false; Missing = "" }
    }

    if ($answer -ieq "D") {
        return [PSCustomObject]@{ Path = $defaultRoot; OnSystemDrive = (Test-TFToolkitBackupOnSystemDrive -Path $defaultRoot); Missing = "" }
    }

    if ($answer -ine "O") {
        return $none
    }

    $path = (Read-TFToolkitText -Message (Get-TFToolkitText 'Pasta ou unidade de destino (ex.: E:\)')).Trim().Trim('"')

    if ([string]::IsNullOrWhiteSpace($path)) {
        return $none
    }

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        return [PSCustomObject]@{ Path = ""; OnSystemDrive = $false; Missing = $path }
    }

    return [PSCustomObject]@{ Path = $path; OnSystemDrive = (Test-TFToolkitBackupOnSystemDrive -Path $path); Missing = "" }
}


function Test-TFToolkitBackupOnSystemDrive {
    # Se a pasta fica na unidade do Windows (a que vai ser formatada), pela letra do caminho inteiro (um caminho relativo
    # vale a partir da pasta de agora). Um caminho de rede (\\servidor\pasta) não fica.
    param ([Parameter(Mandatory)][string]$Path)

    $full = [string]$Path

    if ($full -notmatch '^[A-Za-z]:' -and $full -notmatch '^[\\/]{2}') {
        try { $full = [IO.Path]::GetFullPath($full) } catch { return $false }
    }

    if ($full -notmatch '^([A-Za-z]:)') { return $false }

    return [string]::Equals($Matches[1], ([string]$env:SystemDrive).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
}


function Write-TFToolkitBackupUserFolders {
    # As pastas pessoais que o backup não copia, as maiores primeiro, no resumo: a pessoa vê ali o que precisa levar à parte.
    # Até $Limit pastas; a lista completa fica no LEIA-ME.
    param (
        [AllowEmptyCollection()][object[]]$Folders = @(),
        [int]$Limit = 8
    )

    if (@($Folders).Count -eq 0) {
        return
    }

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Copie à parte (não estão no backup)')

    foreach ($folder in @($Folders | Sort-Object -Property Size -Descending | Select-Object -First $Limit)) {
        Write-TFToolkitKeyValue -Label $folder.Name -Value (Format-TFToolkitBytes -Bytes ([int64]$folder.Size))
    }

    $rest = @($Folders).Count - $Limit

    if ($rest -gt 0) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'E mais {0}; a lista completa está no LEIA-ME.' "$(Format-TFToolkitCount -Count $rest -One (Get-TFToolkitText 'pasta') -Many (Get-TFToolkitText 'pastas'))")
    }

    Write-Host ""
}


function Get-TFToolkitBackupProblemText {
    # "problemas em Drivers de terceiros e Redes Wi-Fi": os itens que falharam ou ficaram pela metade, na ordem em que rodaram.
    param (
        [AllowEmptyCollection()][object[]]$Results = @()
    )

    $names = @($Results | Where-Object { $_.Kind -in "Failed", "Warning" } | ForEach-Object { [string]$_.Etapa })

    return (Get-TFToolkitText 'problemas em {0}' "$(Join-TFToolkitList -Items $names)")
}


function Get-TFToolkitBackupBitLockerDrives {
    # Os discos com BitLocker que não são o do Windows (a formatação apaga o do Windows; os outros ficam e pedem a chave
    # no Windows novo). Sem o BitLocker neste Windows, ou sem leitura, nenhum.
    if ($null -eq (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) { return @() }

    try {
        return @(Get-TFToolkitBitLockerVolumes | Where-Object { -not $_.System -and $_.State -in @("On", "Suspended", "Encrypting") } | ForEach-Object { [string]$_.MountPoint })
    }
    catch {
        Write-Verbose "BitLocker: $($_.Exception.Message)"
        return @()
    }
}


function Invoke-TFToolkitBackupBeforeFormat {
    $title = (Get-TFToolkitText 'Backup antes de formatar')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'O backup dos drivers e das redes Wi-Fi exige privilégios de Administrador.'))) {
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador') -Title $title)
            return
        }

        # O que o backup guarda aparece na lista de marcar; o que importa saber antes é o que fica de fora.
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Seus arquivos pessoais não entram no backup: o LEIA-ME lista as pastas para copiar à parte.')

        # Um disco de dados com BitLocker abre sozinho neste Windows; no Windows novo, só com a chave de recuperação.
        $locked = @(Get-TFToolkitBackupBitLockerDrives)

        if ($locked.Count -gt 0) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Com BitLocker: {0}. No Windows novo, o disco só abre com a chave de recuperação; guarde-a antes de formatar, em Segurança > Chave de recuperação do BitLocker.' "$(Join-TFToolkitList -Items $locked)")
        }

        Write-Host ""

        $destination = Read-TFToolkitBackupDestination

        if ($destination.Missing) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'A pasta ''{0}'' não existe. Conecte o pendrive ou HD e tente de novo.' "$($destination.Missing)")
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'a pasta ''{0}'' não existe' "$($destination.Missing)") -Title $title)
            return
        }

        if ([string]::IsNullOrWhiteSpace($destination.Path)) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $options = @(Get-TFToolkitBackupItems | ForEach-Object { @{ Key = $_.Id; Label = $_.Label; Description = $_.Description; Selected = $_.Selected } })
        $picked = Read-TFToolkitMultiSelect -Message (Get-TFToolkitText 'O que incluir no backup?') -Options $options -ConfirmLabel (Get-TFToolkitText 'Fazer o backup')

        if ($null -eq $picked -or @($picked).Count -eq 0) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        # Com o backup das pastas do OneDrive ligado, Documentos (o destino padrão) fica no OneDrive, e tudo o que for
        # gravado lá sobe para a nuvem, inclusive as senhas do Wi-Fi em texto puro. Só entram se a pessoa confirmar.
        if (@($picked) -contains "wifi" -and (Test-TFToolkitBackupInCloudFolder -Path $destination.Path)) {
            Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Esta pasta fica no OneDrive: os arquivos das redes Wi-Fi, com as senhas em texto puro, seriam enviados para a nuvem.')

            if (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Incluir as redes Wi-Fi mesmo assim?') -DefaultKey "N" -YesLabel (Get-TFToolkitText 'Incluir') -NoLabel (Get-TFToolkitText 'Deixar de fora'))) {
                $picked = @(@($picked) | Where-Object { $_ -ne "wifi" })
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'As redes Wi-Fi ficaram fora deste backup. Para guardá-las, faça outro backup só com elas, num pendrive ou HD externo.')

                if ($picked.Count -eq 0) {
                    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
                    Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
                    return
                }
            }
        }

        $root = $destination.Path
        $folder = Join-Path $root (New-TFToolkitBackupFolderName)
        $suffix = 1

        while (Test-Path -LiteralPath $folder) {
            $suffix++
            $folder = Join-Path $root "$(New-TFToolkitBackupFolderName)-$suffix"
        }

        [void](New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop)

        # O backup.json é gravado já no começo e de novo a cada item: parar no meio (a soma das pastas pessoais, no fim, leva
        # minutos) não pode deixar uma pasta que a restauração recusa por falta dele. Complete só fica verdadeiro no fim.
        $names = Get-TFToolkitBackupFileNames
        $startedAt = Get-Date
        $manifestPath = Join-Path $folder $names.Manifest
        $pcModel = Get-TFToolkitPcModel
        Set-Content -LiteralPath $manifestPath -Value (New-TFToolkitBackupManifest -Items @() -At $startedAt -Complete $false -Model $pcModel | ConvertTo-Json -Depth 5) -Encoding UTF8 -ErrorAction Stop

        $steps = @(
            @(
                @{ Id = "programs"; Label = (Get-TFToolkitText 'Programas instalados'); Command = "Export-TFToolkitBackupPrograms" },
                @{ Id = "drivers"; Label = (Get-TFToolkitText 'Drivers de terceiros'); Command = "Export-TFToolkitBackupDrivers" },
                @{ Id = "tweaks"; Label = (Get-TFToolkitText 'Ajustes do TF-Toolkit'); Command = "Export-TFToolkitBackupTweaks" },
                @{ Id = "wifi"; Label = (Get-TFToolkitText 'Redes Wi-Fi'); Command = "Export-TFToolkitBackupWifi" }
            ) | Where-Object { @($picked) -contains $_.Id }
        )

        $results = @()
        $manifestItems = @()

        foreach ($step in $steps) {
            Write-TFToolkitSection -Title $step.Label

            try {
                $result = & $step.Command -Folder $folder
            }
            catch {
                Write-TFToolkitStatus -Type Error -Message "$($step.Label): $($_.Exception.Message)"
                $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
            }

            $result.Etapa = $step.Label
            $results += $result
            $manifestItems += [ordered]@{ Id = $step.Id; Ok = ($result.Kind -in "Ok", "Warning"); Detail = $result.Detail }
            Set-Content -LiteralPath $manifestPath -Value (New-TFToolkitBackupManifest -Items $manifestItems -At $startedAt -Complete $false -Model $pcModel | ConvertTo-Json -Depth 5) -Encoding UTF8 -ErrorAction Stop
        }

        $failed = @($results | Where-Object { $_.Kind -eq "Failed" })
        $warned = @($results | Where-Object { $_.Kind -eq "Warning" })
        $done = @($results | Where-Object { $_.Kind -eq "Ok" })

        if ($done.Count -eq 0 -and $warned.Count -eq 0) {
            # Nada foi salvo (tudo falhou, ou o que foi marcado estava vazio): a pasta criada agora, só com o backup.json, não
            # fica para trás, nem aparece na lista da restauração, e a tela não manda copiá-la.
            Remove-TFToolkitFolder -Path $folder -Quiet

            if (-not (Test-TFToolkitGuiMode)) {
                Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')
                Write-TFToolkitResultTable -Results $results
            }

            # Algo falhou e nada foi salvo: Não foi concluído. Tudo o que foi marcado estava vazio (nenhum ajuste aplicado,
            # nenhuma rede salva): Nada a fazer.
            $final = $(if ($failed.Count -gt 0) { New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nenhum item foi salvo') -Title $title } else { New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nada a guardar nos itens marcados') -Title $title })

            if ($failed.Count -gt 0) {
                [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'O backup não foi salvo') -Note (Get-TFToolkitText 'Nenhum item foi salvo; o motivo de cada um está no resumo.'))
            }

            Exit-TFToolkitAction -Result $final
            return
        }

        Write-Progress -Activity (Get-TFToolkitText 'Backup antes de formatar') -Status (Get-TFToolkitText 'somando o tamanho das pastas pessoais para o LEIA-ME (pode levar alguns minutos)')

        try {
            $userFolders = @(Get-TFToolkitBackupUserFolders)
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Backup antes de formatar') -Completed
        }

        $manifest = New-TFToolkitBackupManifest -Items $manifestItems -UserFolders $userFolders -At $startedAt -Model $pcModel

        Set-Content -LiteralPath $manifestPath -Value ($manifest | ConvertTo-Json -Depth 5) -Encoding UTF8 -ErrorAction Stop
        Set-Content -LiteralPath (Join-Path $folder $names.Readme) -Value (New-TFToolkitBackupReadme -Manifest $manifest -UserFolders $userFolders) -Encoding UTF8 -ErrorAction Stop

        # No console, a tabela junta tudo no fim; na janela, cada item já tem a sua seção no resumo.
        if (-not (Test-TFToolkitGuiMode)) {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')
            Write-TFToolkitResultTable -Results $results
            Write-Host ""
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Onde está o backup')
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Pasta do backup') -Value $folder
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Leia primeiro') -Value (Join-Path $folder $names.Readme)
        Write-Host ""
        Write-TFToolkitBackupUserFolders -Folders $userFolders

        # Documentos e qualquer pasta da unidade do Windows somem ao formatar: a tela manda copiar, e não só conferir.
        if ($destination.OnSystemDrive) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Copie esta pasta para um pendrive ou HD externo ANTES de formatar, junto com as suas pastas pessoais (a lista está no LEIA-ME).')
        }
        else {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Antes de formatar, confira que esta pasta não está no disco que será formatado, e copie também as suas pastas pessoais (a lista está no LEIA-ME).')
        }

        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'No Windows novo, use Programas > Restaurar a partir de um backup.')

        if ($failed.Count -gt 0 -or $warned.Count -gt 0) {
            $problems = Get-TFToolkitBackupProblemText -Results $results
            $final = New-TFToolkitResult -Kind Warning -Detail $problems -Title $title

            # Na janela, o título diz que só parte foi salva; a frase, onde ele está (o que importa antes de formatar) e o que
            # não foi.
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'Backup salvo em parte') `
                    -Note (Get-TFToolkitText 'Está em {0}. {1}; o motivo está no resumo.' "$folder" "$($problems.Substring(0, 1).ToUpper())$($problems.Substring(1))"))
        }
        else {
            $final = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'backup salvo na pasta {0}' "$(Split-Path -Path $folder -Leaf)") -Title $title

            # Na janela, o título diz que deu certo; a frase, onde está e o que falta fazer antes de formatar.
            $copy = $(if ($destination.OnSystemDrive) { (Get-TFToolkitText 'copie essa pasta e as suas pastas pessoais para um pendrive ou HD externo') } else { (Get-TFToolkitText 'copie também as suas pastas pessoais') })
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'Backup salvo') -Note (Get-TFToolkitText 'Está em {0}. Antes de formatar, {1}.' "$folder" "$copy"))
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível fazer o backup: {0}' "$($_.Exception.Message)")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


# ---------------------------------------------------------------------------
# Restaurar
# ---------------------------------------------------------------------------

function Read-TFToolkitBackupFolder {
    <#
    Lê e valida uma pasta de backup. Devolve Folder, CreatedAt, Computer, Windows e Available (os itens que existem
    de fato na pasta: programs, drivers, tweaks, wifi). Pasta que não é um backup do TF-Toolkit gera um erro com mensagem clara,
    escrita para entrar no meio de uma frase ("Não foi possível restaurar: a pasta não é um backup do TF-Toolkit...").
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw (Get-TFToolkitText 'a pasta não foi encontrada: {0}' "$Path")
    }

    $names = Get-TFToolkitBackupFileNames
    $manifestPath = Join-Path $Path $names.Manifest
    $document = $null

    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $document = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw (Get-TFToolkitText 'o arquivo {0} está corrompido' "$($names.Manifest)")
        }

        if ([string](Get-TFToolkitJsonValue -Object $document -Name "Format") -ne "TFToolkit.Backup") {
            throw (Get-TFToolkitText 'a pasta não é um backup do TF-Toolkit')
        }
    }
    else {
        # Quem informa a pasta de fora (a raiz do pendrive, a pasta Backups) quer o backup que está nela: com um só, é ele;
        # com vários, a mensagem diz o mais novo.
        $inside = @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $names.Manifest) -PathType Leaf } | Sort-Object -Property LastWriteTime -Descending)

        if ($inside.Count -eq 1) { return (Read-TFToolkitBackupFolder -Path $inside[0].FullName) }

        if ($inside.Count -gt 1) {
            throw (Get-TFToolkitText 'a pasta não é um backup do TF-Toolkit, mas tem {0} backups dentro; informe a pasta de um deles (o mais novo é {1})' "$($inside.Count)" "$($inside[0].Name)")
        }

        throw (Get-TFToolkitText 'a pasta não é um backup do TF-Toolkit (falta o arquivo {0})' "$($names.Manifest)")
    }

    $available = @()

    # A lista do winget só serve se for um "winget export" legível e com algum pacote: um arquivo vazio ou cortado (backup
    # interrompido, cópia danificada) faria o winget import falhar inteiro. DamagedPrograms avisa a tela desse caso (uma
    # lista legível sem nenhum pacote só não tem o que reinstalar).
    $wingetFile = Join-Path $Path $names.WingetList
    $wingetCount = Get-TFToolkitWingetExportCount -Path $wingetFile
    $damagedPrograms = (Test-Path -LiteralPath $wingetFile -PathType Leaf) -and $null -eq $wingetCount

    if ($null -ne $wingetCount -and $wingetCount -gt 0) { $available += "programs" }

    if (@(Get-ChildItem -LiteralPath (Join-Path $Path $names.Drivers) -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0) { $available += "drivers" }

    if (Test-Path -LiteralPath (Join-Path $Path $names.Tweaks) -PathType Leaf) { $available += "tweaks" }

    if (@(Get-ChildItem -LiteralPath (Join-Path $Path $names.Wifi) -Filter "*.xml" -File -ErrorAction SilentlyContinue).Count -gt 0) { $available += "wifi" }

    return [PSCustomObject]@{
        Folder          = $Path
        CreatedAt       = [string](Get-TFToolkitJsonValue -Object $document -Name "CreatedAt" -Default "")
        Computer        = [string](Get-TFToolkitJsonValue -Object $document -Name "Computer" -Default "")
        Model           = [string](Get-TFToolkitJsonValue -Object $document -Name "Model" -Default "")
        Windows         = [string](Get-TFToolkitJsonValue -Object $document -Name "Windows" -Default "")
        Available       = @($available)
        DamagedPrograms = $damagedPrograms
        Complete        = [bool](Get-TFToolkitJsonValue -Object $document -Name "Complete" -Default $true)
    }
}


function Find-TFToolkitBackups {
    <#
    Os backups mais recentes, do mais novo ao mais antigo: os de Documentos\TF-Toolkit\Backups e os da raiz de cada unidade
    fora a do Windows (Get-TFToolkitBackupDrives: o pendrive, o HD externo, outra partição), onde o próprio backup os grava
    quando a pessoa escolhe a unidade (Backup-<PC>-<data>). Cada pasta ganha CreatedAt (a data do backup.json; sem ela, a
    da pasta, que muda quando a pasta é copiada) e Where (onde está: Documentos ou o nome da unidade). Na mesma data,
    vale a da pasta.
    #>
    param (
        [int]$Top = 6
    )

    $names = Get-TFToolkitBackupFileNames
    $places = @()
    $root = Get-TFToolkitBackupDefaultRoot

    if (Test-Path -LiteralPath $root -PathType Container) { $places += [PSCustomObject]@{ Path = $root; Where = (Get-TFToolkitText 'Documentos'); Filter = "*" } }

    foreach ($drive in @(Get-TFToolkitBackupDrives)) {
        $places += [PSCustomObject]@{ Path = [string]$drive.Root; Where = [string]$drive.Label; Filter = "Backup-*" }
    }

    $found = @(
        foreach ($place in $places) {
            foreach ($folder in @(Get-ChildItem -LiteralPath $place.Path -Directory -Filter $place.Filter -ErrorAction SilentlyContinue)) {
                $manifest = Join-Path $folder.FullName $names.Manifest

                if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }

                $created = $folder.LastWriteTime
                $parsed = [datetime]::MinValue

                try {
                    $text = [string](Get-TFToolkitJsonValue -Object (Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) -Name "CreatedAt" -Default "")
                    if ($text -and [datetime]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { $created = $parsed }
                }
                catch {
                    Write-Verbose "backup.json ilegível: $manifest"
                }

                $folder | Add-Member -NotePropertyName CreatedAt -NotePropertyValue $created -Force
                $folder | Add-Member -NotePropertyName Where -NotePropertyValue $place.Where -Force
                $folder
            }
        }
    )

    return @($found | Sort-Object -Property @{ Expression = "CreatedAt"; Descending = $true }, @{ Expression = "LastWriteTime"; Descending = $true } | Select-Object -First $Top)
}


function Format-TFToolkitBackupDate {
    # A data do backup.json ("2026-10-20T18:30:00-03:00") como a tela mostra, no horário deste PC; vazio quando o campo
    # falta ou não é uma data (um backup.json editado à mão não derruba a tela).
    param (
        [string]$Text
    )

    $parsed = [datetime]::MinValue

    if ([string]::IsNullOrWhiteSpace($Text) -or -not [datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return ""
    }

    return (Format-TFToolkitDateTime -When $parsed)
}


function Get-TFToolkitBackupChoiceDescription {
    # A linha de apoio de um backup na escolha: "criado em 20/10/2026 18:30 · ANA-PC · Pendrive (E:)", lida do backup.json,
    # com onde ele está (Where, de Find-TFToolkitBackups). Sem o backup.json legível, a data da pasta, que muda quando a
    # pasta é copiada.
    param (
        [Parameter(Mandatory)]
        $Folder
    )

    $names = Get-TFToolkitBackupFileNames
    $parts = @()

    try {
        $document = Get-Content -LiteralPath (Join-Path $Folder.FullName $names.Manifest) -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $created = Format-TFToolkitBackupDate -Text ([string](Get-TFToolkitJsonValue -Object $document -Name "CreatedAt" -Default ""))
        $computer = [string](Get-TFToolkitJsonValue -Object $document -Name "Computer" -Default "")

        if ($created) { $parts += (Get-TFToolkitText 'criado em {0}' "$created") }
        if ($computer) { $parts += $computer }
        if ($parts.Count -gt 0 -and -not [bool](Get-TFToolkitJsonValue -Object $document -Name "Complete" -Default $true)) { $parts += (Get-TFToolkitText 'interrompido antes do fim') }
    }
    catch {
        $parts = @()
    }

    if ($parts.Count -eq 0) {
        $parts += (Get-TFToolkitText 'pasta de {0}' "$(Format-TFToolkitDateTime -When $Folder.LastWriteTime)")
    }

    $where = [string](Get-TFToolkitJsonValue -Object $Folder -Name "Where" -Default "")
    if ($where) { $parts += $where }

    return ($parts -join " · ")
}


function Get-TFToolkitRestoreOptions {
    # As opções de "O que restaurar?", com o que cada uma faz neste PC e quanto há no backup. Tudo o que está no backup vem
    # marcado: a pessoa já escolheu o que guardar quando fez o backup.
    param (
        [Parameter(Mandatory)]
        $Backup,

        # O backup veio de outro modelo de PC: os drivers dele são para aquele PC e vêm desmarcados.
        [switch]$OtherModel
    )

    $names = Get-TFToolkitBackupFileNames
    $folder = $Backup.Folder

    return @(
        foreach ($id in @("programs", "drivers", "tweaks", "wifi")) {
            if (@($Backup.Available) -notcontains $id) { continue }

            switch ($id) {
                "programs" {
                    # Sem o winget (o comum logo depois de formatar, antes de a Microsoft Store se atualizar), a reinstalação
                    # falharia: a opção aparece, mas desmarcada, dizendo o que falta.
                    if (-not (Test-TFToolkitWinget)) {
                        @{ Key = $id; Label = (Get-TFToolkitText 'Reinstalar os programas'); Description = (Get-TFToolkitText 'Precisa do Instalador de Aplicativo, que ainda não está neste Windows'); Selected = $false }
                    }
                    else {
                        $count = Get-TFToolkitWingetExportCount -Path (Join-Path $folder $names.WingetList)
                        $what = $(if ($null -ne $count) { (Get-TFToolkitText 'Reinstala pelo winget {0}' "$(Format-TFToolkitCount -Count $count -One (Get-TFToolkitText 'programa') -Many (Get-TFToolkitText 'programas'))") } else { (Get-TFToolkitText 'Reinstala pelo winget os programas da lista') })
                        @{ Key = $id; Label = (Get-TFToolkitText 'Reinstalar os programas'); Description = (Get-TFToolkitText '{0}; os que não estão no winget ficam em {1}' "$what" "$($names.ProgramsList)"); Selected = $true }
                    }
                }
                "drivers" {
                    $count = @(Get-ChildItem -LiteralPath (Join-Path $folder $names.Drivers) -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue).Count
                    $origin = $(if ($OtherModel) { (Get-TFToolkitText ' (são de outro modelo de PC)') } else { "" })
                    @{ Key = $id; Label = (Get-TFToolkitText 'Instalar os drivers'); Description = (Get-TFToolkitText 'Adiciona {0} e instala os que servirem neste PC{1}' "$(Format-TFToolkitCount -Count $count -One (Get-TFToolkitText 'driver') -Many (Get-TFToolkitText 'drivers'))" "$origin"); Selected = (-not $OtherModel) }
                }
                "tweaks" {
                    @{ Key = $id; Label = (Get-TFToolkitText 'Reaplicar os ajustes do TF-Toolkit'); Description = (Get-TFToolkitText 'Os ajustes que estavam aplicados no PC de origem'); Selected = $true }
                }
                "wifi" {
                    $count = @(Get-ChildItem -LiteralPath (Join-Path $folder $names.Wifi) -Filter "*.xml" -File -ErrorAction SilentlyContinue).Count
                    @{ Key = $id; Label = (Get-TFToolkitText 'Restaurar as redes Wi-Fi'); Description = (Get-TFToolkitText 'Recria {0}, com as senhas' "$(Format-TFToolkitCount -Count $count -One (Get-TFToolkitText 'rede salva') -Many (Get-TFToolkitText 'redes salvas'))"); Selected = $true }
                }
            }
        }
    )
}


function Restore-TFToolkitBackupPrograms {
    param (
        [Parameter(Mandatory)]
        [string]$Folder
    )

    $names = Get-TFToolkitBackupFileNames
    $file = Join-Path $Folder $names.WingetList

    if (-not (Test-TFToolkitWinget)) {
        Write-TFToolkitWingetMissing

        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitWingetMissingDetail))
    }

    # --ignore-versions: uma lista com versões (de um export com --include-versions, ou feita por outro programa) faria o
    # winget procurar as versões de antes; a restauração quer as atuais, como o resto do TF-Toolkit instala.
    $arguments = @("import", "-i", $file, "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity", "--ignore-unavailable", "--ignore-versions")

    Write-TFToolkitCommand -Command "winget $($arguments -join ' ')"
    Write-Host ""
    Write-Progress -Activity (Get-TFToolkitText 'Reinstalando os programas') -Status (Get-TFToolkitText 'o winget instala um programa por vez; pode levar bastante tempo')

    try {
        $exitCode = Invoke-TFToolkitNative -FilePath "winget" -Arguments $arguments -IgnoreExitCode -PassThru
    }
    finally {
        Write-Progress -Activity (Get-TFToolkitText 'Reinstalando os programas') -Completed
    }

    # Os mesmos códigos das outras telas de programas: "já estava instalado" não é problema.
    $exitResult = Get-TFToolkitWingetExitResult -ExitCode $exitCode
    # A marca de "já instalado" das telas de instalar é lida de novo.
    Clear-TFToolkitInstalledWingetIdsCache

    if ($exitResult.Kind -eq "Ok") {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O winget reinstalou os programas da lista.')

        return (New-TFToolkitResult -Kind Ok)
    }

    # Um instalador que só termina ao reiniciar (ou que reinicia o PC sozinho) não é problema da reinstalação: a
    # restauração pede o reinício no fim.
    if ($exitResult.Kind -eq "Warning" -and (Test-TFToolkitResultFlag -Result $exitResult -Name "RebootRequired")) {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O winget reinstalou os programas da lista; algum termina de instalar quando o PC reiniciar.')

        return (New-TFToolkitResult -Kind Ok -Data @{ RebootRequired = $true; RebootStarted = (Test-TFToolkitResultFlag -Result $exitResult -Name "RebootStarted") })
    }

    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O winget terminou com problemas: {0}.' "$($exitResult.Detail)")
    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Para o que faltar, use Programas > Buscar e instalar programas; a lista completa está em {0}.' "$($names.ProgramsList)")

    return (New-TFToolkitResult -Kind Warning -Detail $exitResult.Detail)
}


function Restore-TFToolkitBackupDrivers {
    param (
        [Parameter(Mandatory)]
        [string]$Folder
    )

    $names = Get-TFToolkitBackupFileNames
    $source = Join-Path $Folder $names.Drivers

    Write-Progress -Activity (Get-TFToolkitText 'Instalando os drivers do backup') -Status (Get-TFToolkitText 'pode levar alguns minutos')

    try {
        $run = Invoke-TFToolkitCapture -FilePath "pnputil" -Arguments @("/add-driver", (Join-Path $source "*.inf"), "/subdirs", "/install")
    }
    finally {
        Write-Progress -Activity (Get-TFToolkitText 'Instalando os drivers do backup') -Completed
    }

    # Códigos do pnputil (Microsoft): 3010 = instalado, falta reiniciar; 259 = nenhum dispositivo precisava destes drivers
    # (ou já usa um igual ou mais novo, o comum depois do Windows Update). Nenhum dos dois é falha.
    if ($run.ExitCode -in 0, 3010) {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Drivers instalados.')

        if ($run.ExitCode -eq 3010) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Reinicie o PC para concluir a instalação dos drivers.')
        }

        return (New-TFToolkitResult -Kind Ok -Data @{ RebootRequired = ($run.ExitCode -eq 3010) })
    }

    if ($run.ExitCode -eq 259) {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Drivers adicionados ao Windows; os dispositivos deste PC já usam drivers iguais ou mais novos.')

        return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'os dispositivos já usam drivers iguais ou mais novos'))
    }

    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Alguns drivers podem não ter sido instalados (código {0}).' "$($run.ExitCode)")

    return (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'alguns drivers não foram instalados'))
}


function Get-TFToolkitWifiProfileName {
    # O nome da rede guardado no perfil exportado (o <name> do WLANProfile). Sem ele, o nome do arquivo, que o netsh monta
    # como "<adaptador>-<rede>.xml".
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        [xml]$document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop

        # O indexador procura o filho pelo nome, com ou sem o namespace do perfil; ".name" devolveria o nome do elemento.
        $node = $document.DocumentElement["name"]
        $name = $(if ($null -ne $node) { [string]$node.InnerText } else { "" })

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            return $name.Trim()
        }
    }
    catch {
        Write-Verbose "Perfil Wi-Fi ilegível: $Path"
    }

    return [IO.Path]::GetFileNameWithoutExtension($Path)
}


function Restore-TFToolkitBackupWifi {
    param (
        [Parameter(Mandatory)]
        [string]$Folder
    )

    $names = Get-TFToolkitBackupFileNames
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Folder $names.Wifi) -Filter "*.xml" -File -ErrorAction SilentlyContinue)

    # O netsh recebe o nome do arquivo sem caminho (a cópia de trabalho tem nome simples): nomes de rede com espaços
    # e caracteres acentuados não viram problema de aspas. A cópia tem as senhas em texto e é apagada no final.
    $scratch = Join-Path ([IO.Path]::GetTempPath()) "tf-toolkit-wifi-$([guid]::NewGuid().ToString('N'))"
    [void](New-Item -ItemType Directory -Path $scratch -Force -ErrorAction Stop)

    $added = 0
    $position = 0
    $firstReason = ""

    try {
        Push-Location -LiteralPath $scratch

        try {
            foreach ($file in $files) {
                $position++
                $network = Get-TFToolkitWifiProfileName -Path $file.FullName
                Write-Progress -Activity (Get-TFToolkitText 'Restaurando as redes Wi-Fi') -Status (Get-TFToolkitText '{0} de {1}: {2}' "$position" "$($files.Count)" "$network") -PercentComplete ([int](($position - 1) * 100 / $files.Count))

                $workName = "perfil$position.xml"
                Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $scratch $workName) -Force -ErrorAction Stop

                $run = Invoke-TFToolkitCapture -FilePath "netsh" -Arguments @("wlan", "add", "profile", "filename=$workName", "user=all")

                if ($run.ExitCode -eq 0) {
                    $added++
                    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Rede restaurada: {0}' "$network")
                }
                else {
                    # O motivo do netsh (serviço de rede sem fio parado, PC sem Wi-Fi) vai junto, como no backup.
                    $why = @($run.Lines | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) | Select-Object -First 1
                    $why = $(if ($why) { ([string]$why).TrimEnd('.') } else { "" })
                    if (-not $firstReason) { $firstReason = $why }

                    Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível restaurar a rede: {0}{1}' "$network" "$(if ($why) { " ($why)" })")
                }
            }
        }
        finally {
            Pop-Location
            Write-Progress -Activity (Get-TFToolkitText 'Restaurando as redes Wi-Fi') -Completed
        }
    }
    finally {
        Remove-TFToolkitFolder -Path $scratch -Quiet
    }

    if ($added -eq $files.Count) {
        return (New-TFToolkitResult -Kind Ok -Detail (Format-TFToolkitCount -Count $added -One (Get-TFToolkitText 'rede') -Many (Get-TFToolkitText 'redes')) -Data @{ Count = $added })
    }

    if ($added -eq 0) {
        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nenhuma rede restaurada{0}' "$(if ($firstReason) { ": $firstReason" })"))
    }

    return (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0} de {1}' "$added" "$(Format-TFToolkitCount -Count $files.Count -One (Get-TFToolkitText 'rede') -Many (Get-TFToolkitText 'redes'))") -Data @{ Count = $added })
}


function Restore-TFToolkitFromBackup {
    $title = (Get-TFToolkitText 'Restaurar a partir de um backup')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Instalar programas, drivers e redes Wi-Fi exige privilégios de Administrador.'))) {
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador') -Title $title)
            return
        }

        # Os backups de Documentos e da raiz dos pendrives e HDs conectados (Find-TFToolkitBackups), onde o próprio backup
        # os grava. Sem nenhum, a tela pede para conectar o do backup e oferece procurar de novo, como na escolha de onde
        # guardar o backup.
        $rounds = 5
        $backups = @()
        $answer = ""

        for ($round = 1; $round -le $rounds; $round++) {
            $backups = @(Find-TFToolkitBackups)
            $rescan = ($backups.Count -eq 0 -and $round -lt $rounds)
            $options = @()
            $position = 0

            # Antes da pergunta: durante uma escolha, a janela mostra o resumo, e os detalhes técnicos ficam recolhidos.
            if ($backups.Count -eq 0) {
                $notice = $(if ($round -eq 1) { (Get-TFToolkitText 'Nenhum backup foi encontrado em Documentos nem nos pendrives e HDs conectados. Conecte o do backup e procure de novo.') } else { (Get-TFToolkitText 'Nenhum backup foi encontrado. Confira se o pendrive ou HD aparece no Explorador de Arquivos, ou escolha Outra pasta.') })
                Write-TFToolkitStatus -Type Info -Notice -Message $notice
                Write-Host ""
            }

            if ($rescan) {
                $options += @{ Key = "P"; Label = (Get-TFToolkitText 'Procurar de novo'); Description = (Get-TFToolkitText 'Depois de conectar o pendrive ou HD externo'); Accent = $true }
            }

            # O mais novo vem primeiro, em destaque e como padrão: é o que se restaura quase sempre, e a escolha só lê o
            # backup (o que restaurar e a confirmação vêm depois).
            foreach ($backup in $backups) {
                $position++
                $options += @{ Key = [string]$position; Label = $backup.Name; Description = (Get-TFToolkitBackupChoiceDescription -Folder $backup); Accent = ($position -eq 1) }
            }

            $options += @{ Key = "O"; Label = (Get-TFToolkitText 'Outra pasta'); Description = (Get-TFToolkitText 'Informar a pasta do backup (um pendrive, um HD externo...)') }
            $options += @{ Key = "X"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }

            if ($backups.Count -gt 0) {
                $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Qual backup restaurar?') -Options $options -DefaultKey "1" -ShowMenu `
                    -TextPrompt (Get-TFToolkitText 'Backup (número, O = outra pasta, X = cancelar; ENTER = o mais recente)')
            }
            elseif ($rescan) {
                $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Qual backup restaurar?') -Options $options -DefaultKey "P" -ShowMenu `
                    -TextPrompt (Get-TFToolkitText 'Backup (P = procurar de novo, O = outra pasta, X = cancelar; ENTER = procurar de novo)')
            }
            else {
                $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Qual backup restaurar?') -Options $options -DefaultKey "X" -ShowMenu `
                    -TextPrompt (Get-TFToolkitText 'Backup (O = outra pasta, X = cancelar; ENTER = cancelar)')
            }

            if (-not ($rescan -and $answer -ieq "P")) { break }
        }

        $path = ""

        if ($answer -ieq "O") {
            $path = (Read-TFToolkitText -Message (Get-TFToolkitText 'Pasta do backup (a que tem o arquivo backup.json)')).Trim().Trim('"')
        }
        elseif ($answer -match "^[0-9]+$" -and [int]$answer -ge 1 -and [int]$answer -le $backups.Count) {
            $path = $backups[[int]$answer - 1].FullName
        }

        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        # Quem cola o caminho do próprio backup.json (ou de outro arquivo da pasta) quer a pasta dele.
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $path = Split-Path -Path $path -Parent
        }

        $backup = Read-TFToolkitBackupFolder -Path $path

        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Pasta') -Value $backup.Folder
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Criado em') -Value $(Format-TFToolkitBackupDate -Text $backup.CreatedAt)
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Computador de origem') -Value $(if ($backup.Computer) { $backup.Computer } else { $null })
        $backupModel = [string](Get-TFToolkitJsonValue -Object $backup -Name "Model" -Default "")
        if ($backupModel) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Modelo de origem') -Value $backupModel }
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Windows de origem') -Value $(if ($backup.Windows) { $backup.Windows } else { $null })
        Write-Host ""

        # O nome do computador muda ao formatar; o modelo, não. Drivers de outro modelo vêm desmarcados.
        $currentModel = Get-TFToolkitPcModel
        $otherModel = ($backupModel -and $currentModel -and $backupModel -ne $currentModel -and @($backup.Available) -contains "drivers")

        if ($otherModel) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Este backup é de outro modelo de PC ({0}; este é {1}). Os drivers dele são para aquele PC e vêm desmarcados.' "$backupModel" "$currentModel")
            Write-Host ""
        }

        if (-not [bool](Get-TFToolkitJsonValue -Object $backup -Name "Complete" -Default $true)) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Este backup foi interrompido antes do fim: só o que chegou a ser salvo aparece na lista.')
            Write-Host ""
        }

        if ([bool](Get-TFToolkitJsonValue -Object $backup -Name "DamagedPrograms" -Default $false)) {
            $names = Get-TFToolkitBackupFileNames
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A lista de programas do winget neste backup está danificada e ficou de fora. A lista completa, para reinstalar à mão, está em {0}.' "$($names.ProgramsList)")
            Write-Host ""
        }

        # Logo depois de formatar, o Instalador de Aplicativo costuma não estar registrado ainda, e sem ele os programas não
        # voltam: a restauração oferece repará-lo ali mesmo (Register-TFToolkitWinget), como Reparar o Instalador de
        # Aplicativo. Elevado com outra conta, não oferece: o registro valeria para ela, e não para quem usa o PC.
        if (@($backup.Available) -contains "programs" -and -not (Test-TFToolkitWinget) -and -not (Test-TFToolkitUserContextMismatch)) {
            Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Para reinstalar os programas, falta o Instalador de Aplicativo (winget), que o Windows recém-instalado costuma registrar só depois de atualizar a Microsoft Store.')

            if (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Reparar o Instalador de Aplicativo agora?') -DefaultKey S -YesLabel (Get-TFToolkitText 'Reparar') -NoLabel (Get-TFToolkitText 'Agora não')) {
                $registration = Register-TFToolkitWinget -Activity $title

                if ($registration.Version) {
                    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O Instalador de Aplicativo voltou a funcionar ({0}).' "$($registration.Version)")
                }
                else {
                    if ($registration.Problem) { Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O registro não resolveu: {0}.' "$($registration.Problem)") }
                    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A reinstalação dos programas fica desmarcada. Depois de atualizar o Instalador de Aplicativo pela Microsoft Store, restaure só os programas.')
                }
            }

            Write-Host ""
        }

        $restoreOptions = @(Get-TFToolkitRestoreOptions -Backup $backup -OtherModel:$otherModel)

        if ($restoreOptions.Count -eq 0) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Este backup não tem nada a restaurar.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'o backup não tem nada a restaurar') -Title $title)
            return
        }

        $picked = Read-TFToolkitMultiSelect -Message (Get-TFToolkitText 'O que restaurar?') -Options $restoreOptions -ConfirmLabel (Get-TFToolkitText 'Restaurar')

        if ($null -eq $picked -or @($picked).Count -eq 0) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $chosen = @($restoreOptions | Where-Object { @($picked) -contains $_.Key })

        if (@($picked) -contains "programs") {
            # O winget baixa e instala um programa por vez.
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Reinstalar os programas pode levar bastante tempo.')
            Write-Host ""
        }

        $question = $(if ($chosen.Count -eq 1) { (Get-TFToolkitText '{0} neste PC?' "$($chosen[0].Label)") } else { (Get-TFToolkitText 'Restaurar os {0} itens marcados neste PC?' "$($chosen.Count)") })

        if (-not (Confirm-TFToolkitAction -Message $question -DefaultKey "S" -YesLabel (Get-TFToolkitText 'Restaurar') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $names = Get-TFToolkitBackupFileNames
        $results = @()

        foreach ($option in $chosen) {
            $id = $option.Key
            $label = $option.Label
            Write-TFToolkitSection -Title $label

            try {
                $result = switch ($id) {
                    "programs" { Restore-TFToolkitBackupPrograms -Folder $backup.Folder }
                    "drivers"  { Restore-TFToolkitBackupDrivers -Folder $backup.Folder }
                    "tweaks"   { Invoke-TFToolkitTweakImportFile -Path (Join-Path $backup.Folder $names.Tweaks) -Title $label }
                    "wifi"     { Restore-TFToolkitBackupWifi -Folder $backup.Folder }
                }
            }
            catch {
                Write-TFToolkitStatus -Type Error -Message "${label}: $($_.Exception.Message)"
                $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
            }

            $result.Etapa = $label
            $results += $result
        }

        # No console, a tabela junta tudo no fim; na janela, cada item já tem a sua seção no resumo.
        if (-not (Test-TFToolkitGuiMode)) {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')
            Write-TFToolkitResultTable -Results $results
        }

        $failed = @($results | Where-Object { $_.Kind -eq "Failed" })
        $warned = @($results | Where-Object { $_.Kind -eq "Warning" })
        $skipped = @($results | Where-Object { $_.Kind -eq "Skipped" })
        $restart = @($results | Where-Object { Test-TFToolkitResultFlag -Result $_ -Name "RebootRequired" }).Count -gt 0
        $started = @($results | Where-Object { Test-TFToolkitResultFlag -Result $_ -Name "RebootStarted" }).Count -gt 0

        # O que voltou do backup entra no Histórico de mudanças (os ajustes já entram um a um, pela importação).
        $back = @($results | Where-Object { $_.Kind -in @("Ok", "Warning") } | ForEach-Object { [string]$_.Etapa })
        if ($back.Count -gt 0) { [void](Add-TFToolkitChange -Action $title -Text (Join-TFToolkitList -Items $back)) }

        # O que fazer ao terminar só vale quando algo voltou.
        if ($failed.Count + $skipped.Count -lt $results.Count) {
            Write-Host ""
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Ao terminar, reinicie o PC e copie de volta as suas pastas pessoais (a lista está no LEIA-ME do backup).')
        }

        if ($failed.Count -eq $results.Count) {
            $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nada foi restaurado') -Title $title
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'Nada foi restaurado') -Note (Get-TFToolkitText 'O motivo de cada item está no resumo.'))
        }
        elseif ($skipped.Count -eq $results.Count) {
            $final = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nada a restaurar nos itens marcados') -Title $title
        }
        elseif ($failed.Count -gt 0 -or $warned.Count -gt 0) {
            $problems = Get-TFToolkitBackupProblemText -Results $results
            $final = New-TFToolkitResult -Kind Warning -Detail $problems -Title $title -Data @{ RebootRequired = $restart }

            # Na janela, o título diz que só parte voltou; a frase, o que pediu atenção.
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'Backup restaurado em parte') `
                    -Note (Get-TFToolkitText '{0}; o motivo está no resumo.' "$($problems.Substring(0, 1).ToUpper())$($problems.Substring(1))"))
        }
        else {
            $done = @($results | Where-Object { $_.Kind -eq "Ok" }).Count
            $final = New-TFToolkitResult -Kind Ok -Detail (Format-TFToolkitCount -Count $done -One (Get-TFToolkitText 'item restaurado') -Many (Get-TFToolkitText 'itens restaurados')) -Title $title -Data @{ RebootRequired = $restart }
            [void](Set-TFToolkitResultView -Result $final -Headline (Format-TFToolkitCount -Count $done -One (Get-TFToolkitText 'item restaurado') -Many (Get-TFToolkitText 'itens restaurados')) `
                    -Note (Get-TFToolkitText 'Reinicie o PC e copie de volta as suas pastas pessoais (a lista está no LEIA-ME do backup).'))

            # A lista do winget danificada ficou de fora: o que foi marcado deu certo, mas o backup não voltou inteiro.
            if ([bool](Get-TFToolkitJsonValue -Object $backup -Name "DamagedPrograms" -Default $false)) {
                $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0}; a lista de programas do winget do backup está danificada' "$($final.Detail)") -Title $title -Data @{ RebootRequired = $restart }
            }
        }

        # Um driver ou um programa que só termina ao reiniciar: o reinício é oferecido ali mesmo (Depois como padrão), como
        # nos recursos opcionais; quando um instalador já reinicia o PC sozinho, não.
        if ($restart -and -not $started -and $final.Kind -in @("Ok", "Warning")) {
            Request-TFToolkitRestartOffer -Reason (Get-TFToolkitText 'Para terminar a restauração, o Windows precisa reiniciar.') `
                -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit para terminar a restauração de um backup.') `
                -DeclinedMessage (Get-TFToolkitText 'Reinicialização não iniciada. A restauração termina quando você reiniciar o PC.') `
                -Fallback (Get-TFToolkitText 'Reinicie o PC para terminar a restauração.')
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível restaurar: {0}.' "$($_.Exception.Message.TrimEnd('.'))")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message.TrimEnd('.') -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
