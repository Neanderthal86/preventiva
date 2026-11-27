# Nova versão do TF-Toolkit: consulta a última versão publicada no GitHub, baixa o TF-Toolkit.zip para a pasta Downloads e
# confere o SHA-256 do arquivo antes de dizer que ele está pronto.
#
# Instalar é com a janela fechada: o TF-Toolkit.Setup.ps1 da versão nova espera o TF-Toolkit fechar, troca os arquivos
# (voltando ao que era se algo falhar; Install.psm1) e abre o TF-Toolkit de novo. O hash vem do "digest" que o GitHub
# publica para cada arquivo de um release; sem ele, nada é baixado (um arquivo que não pode ser conferido não deve virar
# instalação).


# ---------------------------------------------------------------------------
# Versão e endereços
# ---------------------------------------------------------------------------

function Get-TFToolkitRepository {
    return "Neanderthal86/tf-toolkit"
}


function Get-TFToolkitWebsiteUrl {
    # O site do TF-Toolkit, na página de um idioma (sem -Language, o da janela): o português na raiz, o inglês em /en/ e o
    # espanhol em /es/. O download e a atualização continuam no GitHub (Get-TFToolkitRepository).
    param (
        [string]$Language = ""
    )

    $site = "https://techfontes.com.br"

    if ([string]::IsNullOrEmpty($Language)) { $Language = [string](Get-TFToolkitLanguage) }

    switch ($Language) {
        "en" { return "$site/en/" }
        "es" { return "$site/es/" }
    }

    return $site
}


function ConvertTo-TFToolkitVersion {
    # "v3.7", "Build 3.7" e "3.7.0" viram o mesmo [version] (sem componentes -1, que fariam 3.7 ser menor que 3.7.0).
    # Texto sem número vira $null.
    param (
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    # O primeiro número com ponto que não é pedaço de outro: em "TF-Toolkit 2026 v3.45" é 3.45 (e não 2026), e ".44"
    # sozinho não é versão. Sem ponto, só um número que é o texto inteiro ("v4", "Build 4").
    $match = [regex]::Match($Text, '(?<![0-9.])v?([0-9]+\.[0-9]+(?:\.[0-9]+){0,2})(?![0-9.])')

    if ($match.Success) {
        $value = $match.Groups[1].Value
    }
    elseif ($Text -match '^\s*(?:v|Build\s+)?([0-9]+)\s*$') {
        $value = "$($Matches[1]).0"
    }
    else {
        return $null
    }

    $parsed = $null

    if (-not [version]::TryParse($value, [ref]$parsed)) {
        return $null
    }

    return (New-Object System.Version -ArgumentList $parsed.Major, $parsed.Minor, ([Math]::Max($parsed.Build, 0)), ([Math]::Max($parsed.Revision, 0)))
}


function Format-TFToolkitVersion {
    # 3.7.0.0 volta a ser "3.7"; só mostra Build e Revision quando existem.
    param (
        [Parameter(Mandatory)]
        [version]$Version
    )

    if ($Version.Revision -gt 0) {
        return $Version.ToString(4)
    }

    if ($Version.Build -gt 0) {
        return $Version.ToString(3)
    }

    return $Version.ToString(2)
}


function Test-TFToolkitReleaseDownloadUrl {
    # O arquivo só é baixado se o endereço for https e apontar para um release do próprio repositório. Um nome de
    # arquivo vindo da internet nunca é usado como caminho: quem escolhe o nome do arquivo local é o TF-Toolkit.
    param (
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -ne $Url.Trim()) {
        return $false
    }

    # "/../", "/./", as formas codificadas ("%2e") e barras codificadas ("%2f", "%5c") sairiam da pasta de downloads do
    # repositório depois que o endereço fosse normalizado; nenhum endereço de release legítimo tem isso.
    if ($Url -match '(?i)(^|[/\\])(\.|%2e){1,2}([/\\?#]|$)' -or $Url -match '(?i)%2f|%5c' -or $Url.Contains("\")) {
        return $false
    }

    $uri = $null

    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) {
        return $false
    }

    if ($uri.Scheme -ne "https" -or $uri.Host -ne "github.com" -or -not $uri.IsDefaultPort -or $uri.UserInfo) {
        return $false
    }

    $folder = "/$(Get-TFToolkitRepository)/releases/download/"

    return ($uri.AbsolutePath.Length -gt $folder.Length -and $uri.AbsolutePath.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase))
}


# ---------------------------------------------------------------------------
# Consulta
# ---------------------------------------------------------------------------

function ConvertTo-TFToolkitWebErrorText {
    <#
    Uma falha de rede, do GitHub ou do disco em português, com o que fazer: o .NET escreve a mensagem em inglês na
    maioria dos Windows em português. Devolve "" quando a falha não é de um tipo conhecido (quem chama usa a mensagem
    original). O limite de consultas do GitHub (60 por hora por conexão) diz a hora em que libera. -NotFound: o que dizer
    quando o endereço não existe (404), conforme o que se buscava.
    #>
    param (
        $Exception,
        [string]$NotFound = (Get-TFToolkitText 'o GitHub não encontrou uma versão publicada do TF-Toolkit')
    )

    $code = 0
    $status = ""
    $reset = ""
    $remaining = ""
    $retryAfter = ""

    for ($current = $Exception; $null -ne $current; $current = $current.InnerException) {
        if ($current -is [System.IO.IOException] -and (($current.HResult -band 0xFFFF) -in 39, 112)) {
            return (Get-TFToolkitText 'falta espaço em disco')
        }

        if ($current -is [System.Net.WebException] -and -not $status) { $status = [string]$current.Status }

        $response = $null
        if ($null -ne $current.PSObject.Properties["Response"]) { $response = $current.Response }

        if ($null -ne $response -and $code -eq 0) {
            try { $code = [int]$response.StatusCode } catch { $code = 0 }

            foreach ($name in "X-RateLimit-Reset", "X-RateLimit-Remaining", "Retry-After") {
                $value = ""

                try {
                    if ($response.Headers -is [System.Net.WebHeaderCollection]) {
                        $value = [string]$response.Headers[$name]
                    }
                    else {
                        $values = $null
                        if ($response.Headers.TryGetValues($name, [ref]$values)) { $value = [string]@($values)[0] }
                    }
                }
                catch {
                    $value = ""
                }

                if ($name -eq "X-RateLimit-Reset") { $reset = $value } elseif ($name -eq "Retry-After") { $retryAfter = $value } else { $remaining = $value }
            }
        }
    }

    # O limite secundário (consultas demais em pouco tempo) vem como 403 com Retry-After, em segundos.
    if (($code -eq 403 -or $code -eq 429) -and $retryAfter) {
        return (Get-TFToolkitText 'o GitHub limitou por um tempo as consultas vindas desta conexão; tente de novo em alguns minutos')
    }

    if ($code -eq 429 -or ($code -eq 403 -and $remaining -eq "0")) {
        $text = (Get-TFToolkitText 'o GitHub limitou por um tempo as consultas vindas desta conexão')
        $epoch = 0L

        if ([int64]::TryParse($reset, [ref]$epoch) -and $epoch -gt 0) {
            $when = [DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime
            $text = (Get-TFToolkitText '{0}; tente de novo depois das {1}' "$text" "$(Format-TFToolkitDateTime -When $when -Pattern 'HH:mm')")
        }
        else {
            $text = (Get-TFToolkitText '{0}; tente de novo em uma hora' "$text")
        }

        return $text
    }

    if ($code -eq 404) { return $NotFound }
    if ($code -ge 500) { return (Get-TFToolkitText 'o GitHub está com problemas agora (erro {0}); tente de novo mais tarde' "$code") }
    if ($code -ge 400) { return (Get-TFToolkitText 'o GitHub recusou a consulta (erro {0}); tente de novo mais tarde' "$code") }

    switch -Regex ($status) {
        '^(NameResolutionFailure|ProxyNameResolutionFailure|ConnectFailure)$' { return (Get-TFToolkitText 'sem conexão com o GitHub: confira a internet ou se esta rede bloqueia o github.com') }
        '^Timeout$' { return (Get-TFToolkitText 'o GitHub não respondeu a tempo; tente de novo mais tarde') }
        '^(TrustFailure|SecureChannelFailure)$' { return (Get-TFToolkitText 'a conexão segura com o GitHub falhou; confira se a data e a hora do PC estão certas') }
        '^(ConnectionClosed|ReceiveFailure|SendFailure|KeepAliveFailure)$' { return (Get-TFToolkitText 'a conexão com o GitHub caiu no meio; tente de novo') }
    }

    return ""
}


function Get-TFToolkitLatestRelease {
    <#
    Lê a última versão publicada (não conta rascunho nem pré-lançamento). Devolve Tag, Version, PageUrl, Published,
    Notes e Asset (Url, Size, Digest; $null quando o release não tem o TF-Toolkit.zip). Lança erro quando o GitHub não
    responde ou a resposta não faz sentido; quem chama decide como avisar.
    #>
    $uri = "https://api.github.com/repos/$(Get-TFToolkitRepository)/releases/latest"

    Enable-TFToolkitTls12

    $headers = @{
        "User-Agent" = "TF-Toolkit/$(Get-TFToolkitBuild)"
        "Accept"     = "application/vnd.github+json"
    }

    $release = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 15 -ErrorAction Stop

    $tag = [string](Get-TFToolkitJsonValue -Object $release -Name "tag_name" -Default "")
    $version = ConvertTo-TFToolkitVersion -Text $tag

    if ($null -eq $version) {
        throw (Get-TFToolkitText 'A resposta do GitHub não trouxe uma versão reconhecível.')
    }

    $asset = $null

    foreach ($candidate in @(Get-TFToolkitJsonValue -Object $release -Name "assets" -Default @())) {
        if ([string](Get-TFToolkitJsonValue -Object $candidate -Name "name" -Default "") -ieq "TF-Toolkit.zip") {
            $asset = [PSCustomObject]@{
                Url    = [string](Get-TFToolkitJsonValue -Object $candidate -Name "browser_download_url" -Default "")
                Size   = [int64](Get-TFToolkitJsonValue -Object $candidate -Name "size" -Default 0)
                Digest = [string](Get-TFToolkitJsonValue -Object $candidate -Name "digest" -Default "")
            }
            break
        }
    }

    # A data do GitHub é ISO 8601 em UTC; vira a hora local (uma publicação às 01:30 UTC do dia 30 ainda é dia 29 no
    # Brasil). A leitura não depende do idioma do Windows.
    $published = $null
    $publishedText = [string](Get-TFToolkitJsonValue -Object $release -Name "published_at" -Default "")
    $parsed = [datetime]::MinValue

    if ($publishedText -and [datetime]::TryParse($publishedText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
        $published = $parsed.ToLocalTime()
    }

    return [PSCustomObject]@{
        Tag       = $tag
        Version   = $version
        PageUrl   = [string](Get-TFToolkitJsonValue -Object $release -Name "html_url" -Default "")
        Published = $published
        Notes     = [string](Get-TFToolkitJsonValue -Object $release -Name "body" -Default "")
        Asset     = $asset
    }
}


function Get-TFToolkitUpdateStatus {
    <#
    Compara a versão instalada com a última publicada. Status: UpdateAvailable, UpToDate, Ahead (a instalada é mais
    nova que a publicada, comum em quem testa uma versão antes do release) ou Unreachable (sem internet, bloqueio ou
    resposta inválida; Error leva o motivo em português quando ele é conhecido). Current e Release vêm preenchidos
    quando foi possível ler.
    #>
    $current = ConvertTo-TFToolkitVersion -Text ([string](Get-TFToolkitBuild))

    try {
        $release = Get-TFToolkitLatestRelease
    }
    catch {
        $friendly = ConvertTo-TFToolkitWebErrorText -Exception $_.Exception

        return [PSCustomObject]@{
            Status  = "Unreachable"
            Current = $current
            Release = $null
            Error   = $(if ($friendly) { $friendly } else { $_.Exception.Message })
            Known   = [bool]$friendly
        }
    }

    $status = "UpToDate"

    if ($release.Version -gt $current) {
        $status = "UpdateAvailable"
    }
    elseif ($release.Version -lt $current) {
        $status = "Ahead"
    }

    return [PSCustomObject]@{
        Status  = $status
        Current = $current
        Release = $release
        Error   = ""
        Known   = $true
    }
}


function Save-TFToolkitUpdateCheck {
    <#
    Guarda a última versão publicada que uma consulta ao GitHub leu (Verificar nova versão ou o monitor), com a hora: o
    resumo de Sobre o TF-Toolkit e o monitor dizem dela sem consultar de novo. Uma consulta que não chegou ao GitHub não
    apaga o que já se sabia.
    #>
    param ([Parameter(Mandatory)]$Check)

    $release = Get-TFToolkitJsonValue -Object $Check -Name "Release" -Default $null
    $version = $(if ($null -ne $release) { Get-TFToolkitJsonValue -Object $release -Name "Version" -Default $null } else { $null })

    if ($version -isnot [version]) { return }

    [void](Set-TFToolkitSetting -Name "UpdateLatest" -Value (Format-TFToolkitVersion -Version $version))
    [void](Set-TFToolkitSetting -Name "UpdateCheckedAt" -Value ((Get-Date).ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)))
}


function Get-TFToolkitKnownUpdate {
    <#
    O que o TF-Toolkit sabe da última versão publicada, sem consultar a internet (Save-TFToolkitUpdateCheck): Latest (o
    número), Newer (mais nova que esta), Current (esta é a última), CheckedAt e Fresh (a consulta tem até 30 dias: depois
    disso, "a mais recente" já não se pode dizer). $null sem nenhuma consulta guardada, ou com uma que não se entende. A
    comparação é com a versão aberta agora: depois de atualizar, a versão guardada deixa de ser nova sozinha.
    #>
    param ([datetime]$Now = (Get-Date))

    $latest = ConvertTo-TFToolkitVersion -Text ([string](Get-TFToolkitSetting -Name "UpdateLatest" -Default ""))
    $current = ConvertTo-TFToolkitVersion -Text ([string](Get-TFToolkitBuild))

    if ($null -eq $latest -or $null -eq $current) { return $null }

    $checkedAt = Get-TFToolkitSettingDate -Name "UpdateCheckedAt"

    # Uma data no futuro (o relógio estava adiantado) não vale como consulta recente.
    $fresh = ($null -ne $checkedAt -and $checkedAt -le $Now.AddDays(1) -and ($Now - $checkedAt).TotalDays -le 30)

    return [PSCustomObject]@{
        Latest    = (Format-TFToolkitVersion -Version $latest)
        Newer     = ($latest -gt $current)
        Current   = ($latest -eq $current)
        CheckedAt = $checkedAt
        Fresh     = $fresh
    }
}


# ---------------------------------------------------------------------------
# Integridade
# ---------------------------------------------------------------------------

function Get-TFToolkitFileSha256 {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    return ([string](Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash).ToLowerInvariant()
}


function Get-TFToolkitExpectedHash {
    <#
    O SHA-256 que o arquivo deve ter: o "digest" que o GitHub publica para cada arquivo de um release (sha256:...).
    Devolve "" quando o release não traz nenhum (quem chama não baixa). Um digest estragado lança erro: é um hash
    publicado que não pôde ser lido, e não "sem hash".
    #>
    param (
        [Parameter(Mandatory)]
        $Release
    )

    $asset = Get-TFToolkitJsonValue -Object $Release -Name "Asset"
    if ($null -eq $asset) { return "" }

    $digest = [string](Get-TFToolkitJsonValue -Object $asset -Name "Digest" -Default "")
    if (-not $digest) { return "" }

    if ($digest -notmatch "(?i)^sha256:") {
        throw (Get-TFToolkitText 'O GitHub publicou um hash que não é SHA-256 para o TF-Toolkit.zip.')
    }

    $hash = $digest.Substring(7).Trim()

    if ($hash -notmatch '^[0-9a-fA-F]{64}$') {
        throw (Get-TFToolkitText 'O hash publicado pelo GitHub para o TF-Toolkit.zip não é um SHA-256 reconhecível.')
    }

    return $hash.ToLowerInvariant()
}


function Save-TFToolkitRelease {
    <#
    Baixa o TF-Toolkit.zip do release para a pasta de destino com um nome que o TF-Toolkit escolhe (TF-Toolkit-<versão>.zip)
    e confere tamanho e SHA-256. Integrity: Verified (hash igual; Reused quando o arquivo já estava lá, conferido),
    Mismatch (o download é apagado), NoHash (o release não publica hash; nada é baixado) ou Failed (Error leva o
    motivo). O download parcial (.download) nunca fica na pasta, nem quando a ação é interrompida.
    #>
    param (
        [Parameter(Mandatory)]
        $Release,

        [Parameter(Mandatory)]
        [string]$DestinationFolder
    )

    $asset = Get-TFToolkitJsonValue -Object $Release -Name "Asset"

    $result = [PSCustomObject]@{
        Integrity = "Failed"
        Path      = ""
        Hash      = ""
        Expected  = ""
        Reused    = $false
        Error     = ""
    }

    if ($null -eq $asset -or -not (Test-TFToolkitReleaseDownloadUrl -Url ([string](Get-TFToolkitJsonValue -Object $asset -Name "Url" -Default "")))) {
        $result.Error = (Get-TFToolkitText 'o release não tem um TF-Toolkit.zip num endereço confiável do repositório')
        return $result
    }

    try {
        $result.Expected = Get-TFToolkitExpectedHash -Release $Release
    }
    catch {
        $result.Error = $_.Exception.Message
        return $result
    }

    if (-not $result.Expected) {
        $result.Integrity = "NoHash"
        return $result
    }

    $finalPath = Join-Path $DestinationFolder ("TF-Toolkit-{0}.zip" -f (Format-TFToolkitVersion -Version $Release.Version))
    $partialPath = "$finalPath.download"

    # A mesma versão já baixada e conferida não é baixada de novo.
    if (Test-Path -LiteralPath $finalPath -PathType Leaf) {
        try {
            if ((Get-TFToolkitFileSha256 -Path $finalPath) -eq $result.Expected) {
                $result.Hash = $result.Expected
                $result.Path = $finalPath
                $result.Reused = $true
                $result.Integrity = "Verified"
                return $result
            }
        }
        catch {
            # Não deu para ler o arquivo antigo: baixa de novo.
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $DestinationFolder -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $DestinationFolder -Force)
        }

        Enable-TFToolkitTls12

        $previous = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"

        try {
            Invoke-WebRequest -Uri ([string]$asset.Url) -OutFile $partialPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        }
        finally {
            $ProgressPreference = $previous
        }

        if (-not (Test-Path -LiteralPath $partialPath -PathType Leaf)) {
            throw (Get-TFToolkitText 'o download terminou sem gravar o arquivo')
        }

        $size = (Get-Item -LiteralPath $partialPath).Length

        if ($size -le 0) {
            throw (Get-TFToolkitText 'o arquivo baixado está vazio')
        }

        if ([int64]$asset.Size -gt 0 -and $size -ne [int64]$asset.Size) {
            throw (Get-TFToolkitText 'o arquivo chegou incompleto ({0} de {1} bytes); tente de novo' "$size" "$($asset.Size)")
        }

        $result.Hash = Get-TFToolkitFileSha256 -Path $partialPath

        if ($result.Hash -ne $result.Expected) {
            $result.Integrity = "Mismatch"
            return $result
        }

        # Um arquivo antigo de mesmo nome, com outro conteúdo e em uso (aberto num programa de zip, sendo lido pelo
        # antivírus), não derruba o download conferido: ele fica com outro nome.
        $target = $finalPath
        $moved = $false

        for ($attempt = 1; $attempt -le 9 -and -not $moved; $attempt++) {
            try {
                Move-Item -LiteralPath $partialPath -Destination $target -Force -ErrorAction Stop
                $moved = $true
            }
            catch {
                $target = Join-Path $DestinationFolder ("TF-Toolkit-{0} ({1}).zip" -f (Format-TFToolkitVersion -Version $Release.Version), ($attempt + 1))
            }
        }

        if (-not $moved) {
            throw (Get-TFToolkitText 'o arquivo {0} já existe na pasta Downloads e está em uso; feche o programa que o abriu e tente de novo' "$(Split-Path -Leaf $finalPath)")
        }

        $result.Path = $target
        $result.Integrity = "Verified"
    }
    catch {
        $friendly = ConvertTo-TFToolkitWebErrorText -Exception $_.Exception
        $result.Integrity = "Failed"
        $result.Error = $(if ($friendly) { $friendly } else { $_.Exception.Message })
    }
    finally {
        # Também quando a ação é interrompida (Parar), em que o catch não roda.
        Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
    }

    return $result
}


function Get-TFToolkitReleasePackageInfo {
    <#
    Confere que o zip é um pacote do TF-Toolkit e lê dele: Root (a pasta de dentro do zip que tem os arquivos, "TF-Toolkit"
    no pacote publicado, ou "" quando os arquivos estão na raiz) e Build (a versão escrita no Core.psm1 do pacote, ou "").
    $null quando o zip não abre ou não tem o TF-Toolkit.Gui.ps1.
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $zip = $null

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)

        $root = $null

        foreach ($entry in $zip.Entries) {
            $name = ([string]$entry.FullName).Replace("\", "/")

            if ($name -ieq "TF-Toolkit.Gui.ps1") { $root = ""; break }
            if ($name -match '^([^/]+)/TF-Toolkit\.Gui\.ps1$') { $root = $Matches[1]; break }
        }

        if ($null -eq $root) { return $null }

        $build = ""
        $corePath = $(if ($root) { "$root/modules/Core.psm1" } else { "modules/Core.psm1" })
        $core = @($zip.Entries | Where-Object { ([string]$_.FullName).Replace("\", "/") -ieq $corePath })[0]

        if ($null -ne $core) {
            $reader = New-Object System.IO.StreamReader ($core.Open())

            try {
                $match = [regex]::Match($reader.ReadToEnd(), '\$script:TFToolkitBuild\s*=\s*"([0-9.]+)"')
                if ($match.Success) { $build = $match.Groups[1].Value }
            }
            finally {
                $reader.Dispose()
            }
        }

        return [PSCustomObject]@{ Root = $root; Build = $build }
    }
    catch {
        return $null
    }
    finally {
        if ($null -ne $zip) { $zip.Dispose() }
    }
}


# ---------------------------------------------------------------------------
# Tela
# ---------------------------------------------------------------------------

function Format-TFToolkitReleaseNotes {
    <#
    As primeiras linhas úteis das notas do release, sem Markdown nem HTML, para caber na tela: um link vira o texto
    dele, tabelas, blocos de código, comentários e marcações HTML somem. Truncated diz se havia mais linhas.
    #>
    param (
        [string]$Notes,
        [int]$MaxLines = 8
    )

    $lines = @()
    $truncated = $false

    if (-not [string]::IsNullOrWhiteSpace($Notes)) {
        $text = [regex]::Replace($Notes, '(?s)<!--.*?-->', '')
        $inCode = $false

        foreach ($line in ($text -split "\r?\n")) {
            if ($line -match '^\s*(```|~~~)') { $inCode = -not $inCode; continue }
            if ($inCode -or $line -match '^\s*\|') { continue }

            $clean = $line -replace '!?\[([^\]]*)\]\([^)]*\)', '$1'
            $clean = $clean -replace '<[^>]+>', ''
            # Os marcadores de ênfase (**negrito**, _itálico_) saem; o "_" dentro de uma palavra (tweak_backup.json) fica.
            $clean = $clean -replace '^\s*[#>*+\-]+\s*', '' -replace '`', ''
            $clean = ($clean -replace '(?<![\p{L}0-9])[*_]{1,3}|[*_]{1,3}(?![\p{L}0-9])', '').Trim()

            if (-not $clean) { continue }

            if ($lines.Count -ge $MaxLines) {
                $truncated = $true
                break
            }

            $lines += $clean
        }
    }

    return [PSCustomObject]@{ Lines = @($lines); Truncated = $truncated }
}


function Show-TFToolkitDownloadedRelease {
    # Onde o arquivo ficou, como instalar (com a pasta de dentro do zip) e a oferta de mostrar o arquivo na pasta. O
    # Explorador abre a pasta na sessão da pessoa, sem o Administrador da janela.
    param (
        [Parameter(Mandatory)]$Saved,
        $Package
    )

    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Arquivo') -Value $Saved.Path
    Write-Host ""

    $appRoot = Get-TFToolkitAppRoot
    $what = $(if ($null -ne $Package -and $Package.Root) { (Get-TFToolkitText 'entre na pasta {0} dentro do zip e copie tudo o que está nela' "$($Package.Root)") } else { (Get-TFToolkitText 'copie tudo o que está no zip') })
    Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'Para instalar à mão: feche o TF-Toolkit, abra o zip, {0} para {1}, substituindo os arquivos, e abra o TF-Toolkit de novo.' "$what" "$appRoot")
    Write-Host ""

    if (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Mostrar o arquivo na pasta Downloads?') -DefaultKey S -YesLabel (Get-TFToolkitText 'Mostrar') -NoLabel (Get-TFToolkitText 'Agora não')) {
        try {
            Start-Process -FilePath "explorer.exe" -ArgumentList "/select,`"$($Saved.Path)`"" -ErrorAction Stop
        }
        catch {
            Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Não foi possível abrir a pasta: {0}' "$($_.Exception.Message)")
        }
    }
}


function Invoke-TFToolkitSelfUpdate {
    <#
    Oferece instalar agora a versão baixada e conferida. Started: a troca começou (o instalador da versão nova espera o
    TF-Toolkit fechar) e Result é o resultado da ação; Reason: não deu para começar (a instalação à mão continua valendo);
    os dois vazios: a pessoa preferiu instalar depois.
    #>
    param (
        [Parameter(Mandatory)]$Saved,
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$Published,
        [Parameter(Mandatory)][string]$Title
    )

    $answer = [PSCustomObject]@{ Started = $false; Result = $null; Reason = "" }

    Write-Host ""

    # Com outra janela ou outro menu desta pasta aberto, o instalador recusaria a troca só depois de fechar este: o que
    # fechar fica dito agora, sem o fecha e abre à toa.
    $others = @()
    try { $others = @(Get-TFToolkitRunningCopies -Root (Get-TFToolkitAppRoot) | Where-Object { $_.Kind -ne "Agent" }) } catch { $others = @() }

    if ($others.Count -gt 0) {
        $answer.Reason = (Get-TFToolkitText 'outra janela do TF-Toolkit continua aberta')
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Outra janela ou outro menu do TF-Toolkit está aberto. Feche-o e verifique de novo para instalar com um clique.')
        return $answer
    }

    if (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Instalar a versão {0} agora? O TF-Toolkit fecha, troca os arquivos e abre de novo em alguns segundos.' "$Published") -DefaultKey S -YesLabel (Get-TFToolkitText 'Instalar agora') -NoLabel (Get-TFToolkitText 'Depois'))) {
        return $answer
    }

    Write-TFToolkitStatus -Type Running -Notice -Message (Get-TFToolkitText 'Preparando a instalação...')

    try {
        [void](Start-TFToolkitUpdateInstall -ZipPath $Saved.Path -PackageRoot ([string]$Package.Root) -Reopen $(if (Test-TFToolkitGuiMode) { "Gui" } else { "Console" }))
    }
    catch {
        $answer.Reason = ([string]$_.Exception.Message).TrimEnd('.')
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não foi possível instalar sozinho: {0}. A instalação à mão continua valendo.' "$($answer.Reason)")
        return $answer
    }

    Request-TFToolkitAppExit -Reason "update"
    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O TF-Toolkit vai fechar e abrir de novo na versão {0}.' "$Published")

    $answer.Started = $true
    $answer.Result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'instalando a versão {0}; o TF-Toolkit fecha e abre de novo' "$Published") -Title $Title) `
        -Headline (Get-TFToolkitText 'Instalando a versão {0}' "$Published") -Note (Get-TFToolkitText 'O TF-Toolkit fecha agora e abre de novo na versão nova, em alguns segundos.')

    return $answer
}


function Invoke-TFToolkitUpdateFlow {
    # O roteiro de Verificar nova versão. Devolve o resultado; quem chama abre e fecha a ação uma vez só.
    param ([Parameter(Mandatory)][string]$Title)

    Write-Host (Get-TFToolkitText '  Consulta o GitHub para ver a última versão publicada.') -ForegroundColor DarkGray
    Write-Host ""

    $check = Get-TFToolkitUpdateStatus
    Save-TFToolkitUpdateCheck -Check $check
    $installed = $(if ($null -ne $check.Current) { "$(Format-TFToolkitVersion -Version $check.Current)" } else { "$(Get-TFToolkitBuild)" })

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Versões')
    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Instalada') -Value $installed

    if ($check.Status -eq "Unreachable") {
        # A faixa: o que não deu no título; o motivo conhecido (sem internet, limite do GitHub...) na frase.
        $unreachable = (Get-TFToolkitText 'Não foi possível consultar o GitHub')

        if ($check.Known) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não foi possível consultar o GitHub agora: {0}.' "$($check.Error)")
            return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail $check.Error -Title $Title) -Headline $unreachable -Note (Format-TFToolkitReasonNote -Text $check.Error))
        }

        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não foi possível consultar o GitHub agora; tente de novo mais tarde.')
        Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'Detalhe: {0}' "$($check.Error)")
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'não foi possível consultar o GitHub agora; tente de novo mais tarde') -Title $Title) `
                -Headline $unreachable -Note (Get-TFToolkitText 'Tente de novo mais tarde.'))
    }

    $release = $check.Release
    # O número da versão; as frases dizem "a versão {0}" (no inglês, "version {0}").
    $published = "$(Format-TFToolkitVersion -Version $release.Version)"

    Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Última publicada') -Value $published

    if ($release.Published -is [datetime]) {
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Publicada em') -Value (Format-TFToolkitDateTime -When $release.Published -Pattern "dd/MM/yyyy")
    }

    Write-Host ""

    if ($check.Status -eq "UpToDate") {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Você já está na versão mais recente.')
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'versão {0} em dia' "$published") -Title $Title) `
                -Headline (Get-TFToolkitText 'Você está na versão mais recente') -Note (Get-TFToolkitText 'A versão {0} é a última publicada no GitHub.' "$published"))
    }

    if ($check.Status -eq "Ahead") {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'A versão instalada é mais nova que a última publicada; não há o que atualizar.')
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'esta cópia é mais nova que a última publicada ({0})' "$published") -Title $Title) `
                -Headline (Get-TFToolkitText 'Esta cópia é mais nova que a publicada') -Note (Get-TFToolkitText 'A última publicada é a versão {0}; não há o que atualizar.' "$published"))
    }

    Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Há uma versão mais nova: {0}.' "$published")

    # Sem o endereço da página na resposta do GitHub, a lista de releases do projeto é o caminho seguro.
    $pageUrl = $(if ([string]::IsNullOrWhiteSpace($release.PageUrl)) { "https://github.com/$(Get-TFToolkitRepository)/releases" } else { [string]$release.PageUrl })
    $notes = Format-TFToolkitReleaseNotes -Notes $release.Notes

    if ($notes.Lines.Count -gt 0) {
        Write-TFToolkitSection -Title (Get-TFToolkitText 'O que mudou')

        foreach ($note in $notes.Lines) {
            Write-TFToolkitStatus -Type Info -Notice -Message $note
        }

        if ($notes.Truncated) { Write-TFToolkitStatus -Type Info -Notice -Message (Get-TFToolkitText 'Notas completas: {0}' "$pageUrl") }
    }

    # Os títulos da faixa: a versão nova que existe, ou a que não foi baixada.
    $available = (Get-TFToolkitText 'Versão {0} disponível' "$published")
    $notDownloaded = (Get-TFToolkitText 'A versão {0} não foi baixada' "$published")

    if ($null -eq $release.Asset) {
        $why = (Get-TFToolkitText 'Esse release não tem o TF-Toolkit.zip anexado; baixe pela página do projeto: {0}' "$pageUrl")
        Write-TFToolkitStatus -Type Warning -Message $why
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'a versão {0} está publicada, mas sem o TF-Toolkit.zip' "$published") -Title $Title) -Headline $available -Note $why)
    }

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Download')

    # Elevado com a conta de outro Administrador, a pasta Downloads seria a dessa conta, fora do alcance de quem usa o
    # PC. Sem elevação (o aviso do Windows recusado), o download vai para a pasta certa.
    if (Test-TFToolkitUserContextMismatch) {
        $why = (Get-TFToolkitText 'O TF-Toolkit está aberto com a conta de outro Administrador: o arquivo iria para a pasta Downloads dessa conta. Para baixar, {0}, ou baixe pela página do projeto: {1}' "$(Get-TFToolkitUnelevatedHint)" "$pageUrl")
        Write-TFToolkitStatus -Type Warning -Message $why
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'a versão {0} está disponível; com a conta de outro Administrador, o download não foi feito' "$published") -Title $Title) -Headline $available -Note $why)
    }

    if (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Baixar o TF-Toolkit.zip da versão {0} para a pasta Downloads?' "$published") -DefaultKey S -YesLabel (Get-TFToolkitText 'Baixar') -NoLabel (Get-TFToolkitText 'Agora não'))) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nada foi baixado.')
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'a versão {0} está disponível, mas o download foi recusado' "$published") -Title $Title) `
                -Headline $available -Note (Get-TFToolkitText 'Nada foi baixado.'))
    }

    Write-TFToolkitStatus -Type Running -Notice -Message (Get-TFToolkitText 'Baixando e conferindo o arquivo...')
    $saved = Save-TFToolkitRelease -Release $release -DestinationFolder (Get-TFToolkitDownloadsPath)

    if ($saved.Integrity -eq "NoHash") {
        $why = (Get-TFToolkitText 'Esta versão não publica um SHA-256 para conferir o arquivo, então o TF-Toolkit não a baixou. Baixe pela página do projeto: {0}' "$pageUrl")
        Write-TFToolkitStatus -Type Error -Message $why
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'a versão {0} não publica um hash para conferir; nada foi baixado' "$published") -Title $Title) -Headline $notDownloaded -Note $why)
    }

    if ($saved.Integrity -eq "Mismatch") {
        $why = (Get-TFToolkitText 'O arquivo baixado chegou diferente do publicado (corrompido no caminho ou alterado) e foi apagado. Tente de novo; se repetir, baixe pela página do projeto: {0}' "$pageUrl")
        Write-TFToolkitStatus -Type Error -Message $why
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o arquivo baixado não confere com o publicado e foi apagado') -Title $Title) -Headline $notDownloaded -Note $why)
    }

    if ($saved.Integrity -ne "Verified") {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível baixar: {0}.' "$($saved.Error)")
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail $saved.Error -Title $Title) -Headline $notDownloaded -Note (Format-TFToolkitReasonNote -Text $saved.Error))
    }

    $package = Get-TFToolkitReleasePackageInfo -Path $saved.Path

    if ($null -eq $package) {
        # O arquivo é o publicado (o hash confere), mas não é um pacote do TF-Toolkit: erro do release.
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O arquivo baixado confere com o publicado, mas não é um pacote do TF-Toolkit; baixe pela página do projeto: {0}' "$pageUrl")
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Arquivo') -Value $saved.Path
        return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'a versão {0} foi baixada, mas o arquivo não é um pacote do TF-Toolkit' "$published") -Title $Title) `
                -Headline (Get-TFToolkitText 'O arquivo baixado não é um pacote do TF-Toolkit') -Note (Get-TFToolkitText 'Ele é idêntico ao publicado, então o problema está no release. Baixe pela página do projeto: {0}' "$pageUrl"))
    }

    $how = $(if ($saved.Reused) { (Get-TFToolkitText 'já estava na pasta Downloads e foi conferido') } else { (Get-TFToolkitText 'foi baixado e conferido') })
    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O TF-Toolkit.zip da versão {0} {1}: é idêntico ao publicado no GitHub (SHA-256).' "$published" "$($how)")

    # Atualizar com um clique: só um pacote que diz a mesma versão da página vira instalação.
    if (-not $package.Build -or $package.Build -eq (Format-TFToolkitVersion -Version $release.Version)) {
        $installed = Invoke-TFToolkitSelfUpdate -Saved $saved -Package $package -Published $published -Title $Title

        if ($installed.Started) { return $installed.Result }

        if ($installed.Reason) {
            Show-TFToolkitDownloadedRelease -Saved $saved -Package $package
            return (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'a versão {0} foi baixada e conferida, mas não foi instalada sozinha: {1}' "$published" "$($installed.Reason)") -Title $Title) `
                    -Headline (Get-TFToolkitText 'Versão {0} baixada, mas não instalada' "$published") -Note (Get-TFToolkitText 'Não foi possível instalar sozinho: {0}. A instalação à mão continua valendo.' "$($installed.Reason)"))
        }
    }

    # A faixa da janela: a versão no título e, na frase, o passo que falta (a pessoa preferiu instalar depois).
    $from = $(if ($package.Root) { (Get-TFToolkitText 'o que está na pasta {0} do zip' "$($package.Root)") } else { (Get-TFToolkitText 'o que está no zip') })
    $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'versão {0} baixada e conferida; falta instalar' "$published") -Title $Title) `
        -Headline $(if ($saved.Reused) { (Get-TFToolkitText 'Versão {0} já baixada e conferida' "$published") } else { (Get-TFToolkitText 'Versão {0} baixada e conferida' "$published") }) `
        -Note (Get-TFToolkitText 'Para instalar, feche o TF-Toolkit e copie {0} para {1}, substituindo os arquivos.' "$from" "$(Get-TFToolkitAppRoot)")

    if ($package.Build -and $package.Build -ne (Format-TFToolkitVersion -Version $release.Version)) {
        $why = (Get-TFToolkitText 'O pacote é da versão {0}, diferente da {1} anunciada na página.' "$($package.Build)" "$published")
        Write-TFToolkitStatus -Type Warning -Message $why
        $result = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'a versão {0} foi baixada, mas o pacote é da {1}' "$published" "$($package.Build)") -Title $Title) `
            -Headline (Get-TFToolkitText 'O pacote baixado não é da versão anunciada') -Note $why
    }

    Show-TFToolkitDownloadedRelease -Saved $saved -Package $package

    return $result
}


function Invoke-TFToolkitUpdateCheck {
    $title = (Get-TFToolkitText 'Verificar nova versão')

    Enter-TFToolkitAction -Title $title

    try {
        $final = Invoke-TFToolkitUpdateFlow -Title $title
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível verificar a versão: {0}' "$($_.Exception.Message)")
        $final = Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title $title) `
            -Headline (Get-TFToolkitText 'Não foi possível verificar a versão') -Note (Format-TFToolkitReasonNote -Text $_.Exception.Message)
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
