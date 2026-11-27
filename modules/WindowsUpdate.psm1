# Windows Update dentro do TF-Toolkit: procurar, escolher, baixar e instalar as atualizações pendentes, com progresso.
#
# Usa a API COM do próprio Windows Update (Microsoft.Update.Session), a mesma de Get-TFToolkitPendingWindowsUpdates. O
# trabalho roda em outro runspace (as tarefas em segundo plano do Core: Invoke-TFToolkitInBackground na consulta,
# Start-TFToolkitInBackground e Stop-TFToolkitInBackground na instalação): enquanto ele baixa e instala, a tela acompanha
# o progresso e o botão Parar continua funcionando.
#
# As atualizações opcionais (BrowseOnly: drivers opcionais e prévias) não entram na instalação do Windows: o Windows só
# as oferece na página de atualizações opcionais. Os drivers (Criteria com Type='Driver', em Drivers.psm1) usam a mesma
# busca e a mesma instalação, com os opcionais incluídos e marcados como tal (BrowseOnly).
#
# Quando o Windows Update em si falha (cache corrompido, serviço desativado), Repair-TFToolkitWindowsUpdate refaz o cache
# como manda a Microsoft: para os serviços, põe de lado as pastas Download e DataStore e o catroot2, e liga tudo de novo.


# ---------------------------------------------------------------------------
# Acesso ao Windows Update (código que roda no outro runspace)
# ---------------------------------------------------------------------------

function Get-TFToolkitUpdateComFactoryCode {
    # Cria a sessão do Windows Update e a coleção de atualizações. É um texto para que os testes troquem o Windows
    # Update de verdade por um de mentira, sem mudar o restante do código.
    return @'
@{
    Session       = (New-Object -ComObject "Microsoft.Update.Session" -ErrorAction Stop)
    NewCollection = { New-Object -ComObject "Microsoft.Update.UpdateColl" -ErrorAction Stop }
}
'@
}


function Get-TFToolkitUpdateSessionCode {
    <#
    Abre a sessão do Windows Update ($com e $session), como texto para os dois scripts que rodam no outro runspace. Com o
    componente COM do Windows Update quebrado ou não registrado, New-Object falha e, sem esta parada, o script seguia com
    a sessão nula até "You cannot call a method on a null-valued expression". O erro sai com a marca TFToolkit.SemSessao e o
    código do Windows (0x...) quando houver; Get-TFToolkitWindowsUpdateProblem o traduz para a pessoa.
    A sessão leva o nome do TF-Toolkit (ClientApplicationID), como no exemplo da Microsoft: o histórico do Windows Update diz
    que programa instalou cada atualização, e sem o nome diz "Unknown".
    #>
    return @'
try {
    $com = & ([scriptblock]::Create($FactoryCode))
    $session = $null
    if ($null -ne $com) { $session = $com.Session }
    if ($null -eq $session) { throw "sem sessão" }
}
catch {
    $sessionCode = 0
    $problem = $_.Exception

    while ($null -ne $problem) {
        $codeMatch = [regex]::Match([string]$problem.Message, '0x[0-9A-Fa-f]{8}')

        if ($codeMatch.Success) { $sessionCode = [Convert]::ToInt32($codeMatch.Value.Substring(2), 16); break }

        # Os HResult genéricos do .NET e do PowerShell não dizem nada sobre a causa.
        if ($problem.HResult -lt 0 -and $problem.HResult -notin @(-2146233088, -2146233087, -2146233079, -2146232832)) { $sessionCode = $problem.HResult; break }

        $problem = $problem.InnerException
    }

    throw ("TFToolkit.SemSessao:0x{0:X8}" -f $sessionCode)
}

# Um Windows que recuse o nome não atrapalha a busca nem a instalação.
try { $session.ClientApplicationID = "TF-Toolkit" } catch { }
'@
}


function Get-TFToolkitUpdateSearchCode {
    <#
    A busca padrão das atualizações, como texto (roda no outro runspace, que não enxerga as funções do TF-Toolkit). Só um
    Windows Update que não conhece o critério BrowseOnly (WU_E_INVALID_CRITERIA, 0x80240032) ganha a busca sem ele; um
    erro de verdade (sem internet, serviço parado) volta como erro, em vez de virar uma segunda busca que traria também
    os opcionais (prévias e drivers) como se fossem atualizações comuns.
    #>
    return @'
if (-not [string]::IsNullOrEmpty($Criteria)) {
    $found = $searcher.Search($Criteria)
}
else {
    try {
        $found = $searcher.Search("IsInstalled=0 and IsHidden=0 and BrowseOnly=0")
    }
    catch {
        $invalidCriteria = $false
        $problem = $_.Exception

        while ($null -ne $problem) {
            # -2145124302 = 0x80240032 (WU_E_INVALID_CRITERIA).
            if ($problem.HResult -eq -2145124302 -or [string]$problem.Message -match '0x80240032') { $invalidCriteria = $true }
            $problem = $problem.InnerException
        }

        if (-not $invalidCriteria) { throw }

        $found = $searcher.Search("IsInstalled=0 and IsHidden=0")
    }
}
'@
}


function Get-TFToolkitUpdateSearchScript {
    # Com "Stop", o primeiro erro encerra a busca e é ele que volta para a tela (e não um erro posterior, consequência dele).
    $text = @'
param ($FactoryCode, $Criteria)

$ErrorActionPreference = "Stop"

__SESSION__

$searcher = $session.CreateUpdateSearcher()

__SEARCH__

foreach ($update in $found.Updates) {
    $kb = ""

    try {
        $firstKb = @($update.KBArticleIDs) | Select-Object -First 1

        if ($null -ne $firstKb) { $kb = [string]$firstKb }
    }
    catch {
        $kb = ""
    }

    $browseOnly = $false
    try { $browseOnly = [bool]$update.BrowseOnly } catch { $browseOnly = $false }

    # Type 2 = driver (IWindowsDriverUpdate): a classe (Display, Net...) e o aparelho dizem para que ele serve, o que o
    # título ("Intel - System - 10.1.1.44"), muitas vezes repetido para aparelhos diferentes, não diz.
    $driver = $false
    $driverClass = ""
    $driverModel = ""

    try { $driver = ([int]$update.Type -eq 2) } catch { $driver = $false }

    if ($driver) {
        try { $driverClass = [string]$update.DriverClass } catch { $driverClass = "" }
        try { $driverModel = [string]$update.DriverModel } catch { $driverModel = "" }
    }

    # Uma versão nova do Windows (a classificação Upgrades, pelo Id, que não muda com o idioma): o Otimizar a deixa de
    # fora, porque troca o Windows inteiro e leva horas.
    $upgrade = $false

    try {
        foreach ($category in $update.Categories) {
            if ([string]$category.CategoryID -eq "3689bdc8-b205-4af4-8d4a-a63924c5e9d5") { $upgrade = $true }
        }
    }
    catch {
        $upgrade = $false
    }

    [PSCustomObject]@{
        Id          = [string]$update.Identity.UpdateID
        Title       = [string]$update.Title
        Kb          = $kb
        Size        = [int64]$update.MaxDownloadSize
        Downloaded  = [bool]$update.IsDownloaded
        BrowseOnly  = $browseOnly
        Driver      = $driver
        DriverClass = $driverClass.Trim()
        DriverModel = $driverModel.Trim()
        Upgrade     = $upgrade
    }
}
'@

    return $text.Replace("__SESSION__", (Get-TFToolkitUpdateSessionCode)).Replace("__SEARCH__", (Get-TFToolkitUpdateSearchCode))
}


function Get-TFToolkitUpdateInstallScript {
    # Procura de novo (primeiro no que o Windows guardou da busca que montou a lista), separa as escolhidas pelo Id, baixa
    # e instala. Escreve o andamento em $State (tabela sincronizada) e nunca lança erro: qualquer falha vai para
    # $State.Error. $State.Done fica verdadeiro ao final.
    # Escolhidas que o Windows deixou de oferecer vão para $State.Missing (Ids) e as que não foram baixadas, para
    # $State.NotDownloaded (Ids): nenhuma some do resumo em silêncio. Junto do texto do erro vai o HRESULT de origem
    # ($State.ErrorHResult), para a tela dizer o código mesmo quando a mensagem não o traz. Quando nada chega a ser
    # instalado sem um erro do Windows (nenhuma escolhida ainda oferecida, nenhuma baixada), o script diz só o caso
    # ($State.Reason: Missing ou NotDownloaded): ele não enxerga as traduções, e a frase sai no idioma da tela.
    $text = @'
param ($State, $Ids, $FactoryCode, $Criteria)

$ErrorActionPreference = "Stop"

# BeginDownload e BeginInstall mostram o andamento; quando o Windows recusa o próprio pedido assíncrono (o tipo dos
# parâmetros), o método síncrono faz o mesmo sem o andamento. Um erro do Windows Update (0x8024xxxx) ou do Windows
# (0x8007xxxx: serviço parado, disco cheio, sem conexão) não melhora com uma segunda tentativa: volta como erro.
$isUpdateError = {
    param ($exception)

    $current = $exception

    while ($null -ne $current) {
        $code = "{0:X8}" -f [int]$current.HResult
        if (($code.StartsWith("8024") -or $code.StartsWith("8007")) -and $code -ne "80070057") { return $true }
        $current = $current.InnerException
    }

    return $false
}

try {
__SESSION__

    $State.Phase = "Procurando"
    $searcher = $session.CreateUpdateSearcher()

    # A busca (Get-TFToolkitUpdateSearchCode) deixa o resultado em $found.
    $runSearch = {
__SEARCH__

        return $found
    }

    # A lista que a pessoa acabou de ver veio de uma busca online, e o Windows guarda o resultado dela: a busca neste PC
    # (Online = falso) acha as mesmas em segundos. Só quando falta alguma escolhida a busca vai ao Windows Update de novo.
    $found = $null

    try {
        $searcher.Online = $false
        $local = & $runSearch
        $localIds = @(foreach ($update in $local.Updates) { [string]$update.Identity.UpdateID })

        if (@(@($Ids) | Where-Object { $localIds -notcontains [string]$_ }).Count -eq 0) { $found = $local }
    }
    catch {
        $found = $null
    }

    if ($null -eq $found) {
        try { $searcher.Online = $true } catch { }
        $found = & $runSearch
    }

    $selected = New-Object System.Collections.ArrayList

    foreach ($update in $found.Updates) {
        if (@($Ids) -contains [string]$update.Identity.UpdateID) {
            [void]$selected.Add($update)
        }
    }

    foreach ($id in @($Ids)) {
        $present = $false

        foreach ($update in $selected) {
            if ([string]$update.Identity.UpdateID -eq [string]$id) { $present = $true; break }
        }

        if (-not $present) {
            [void]$State.Missing.Add([string]$id)
        }
    }

    if ($selected.Count -eq 0) {
        $State.Reason = "Missing"
        return
    }

    $State.Total = $selected.Count

    foreach ($update in $selected) {
        if (-not $update.EulaAccepted) {
            $update.AcceptEula()
        }
    }

    # Baixar só o que ainda não foi baixado.
    $toDownload = & $com.NewCollection

    foreach ($update in $selected) {
        if (-not $update.IsDownloaded) {
            [void]$toDownload.Add($update)
        }
    }

    if ($toDownload.Count -gt 0) {
        $State.Phase = "Baixando"
        $State.Percent = 0
        $State.Index = 0
        $State.Total = $toDownload.Count
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $toDownload

        $job = $null

        try { $job = $downloader.BeginDownload($null, $null, $null) } catch { if (& $isUpdateError $_.Exception) { throw }; $job = $null }

        if ($null -ne $job) {
            while (-not $job.IsCompleted) {
                $progress = $job.GetProgress()
                $State.Percent = [int]$progress.PercentComplete
                $State.Index = [int]$progress.CurrentUpdateIndex + 1

                try { $State.Current = [string]$toDownload.Item([int]$progress.CurrentUpdateIndex).Title } catch { }

                Start-Sleep -Milliseconds 500
            }

            $downloadResult = $downloader.EndDownload($job)
        }
        else {
            $downloadResult = $downloader.Download()
        }

        $State.Percent = 100

        if ([int]$downloadResult.ResultCode -notin 2, 3) {
            # Só os códigos: a frase é montada do lado da tela (Get-TFToolkitUpdateDownloadError), que conhece os erros.
            $State.DownloadCode = [int]$downloadResult.ResultCode
            try { $State.DownloadHResult = [int]$downloadResult.HResult } catch { $State.DownloadHResult = 0 }
            return
        }

        # Com o código 3 o Windows baixou só parte: o que ficou sem baixar não pode ser instalado.
        foreach ($update in $selected) {
            if (-not $update.IsDownloaded) {
                [void]$State.NotDownloaded.Add([string]$update.Identity.UpdateID)
            }
        }
    }

    # Instalar o que está baixado.
    $toInstall = & $com.NewCollection

    foreach ($update in $selected) {
        if ($update.IsDownloaded) {
            [void]$toInstall.Add($update)
        }
    }

    if ($toInstall.Count -eq 0) {
        $State.Reason = "NotDownloaded"
        return
    }

    $State.Phase = "Instalando"
    $State.Percent = 0
    $State.Index = 0
    $State.Total = $toInstall.Count

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $toInstall

    try { $installer.AllowSourcePrompts = $false } catch { }

    $job = $null

    try { $job = $installer.BeginInstall($null, $null, $null) } catch { if (& $isUpdateError $_.Exception) { throw }; $job = $null }

    if ($null -ne $job) {
        while (-not $job.IsCompleted) {
            $progress = $job.GetProgress()
            $State.Percent = [int]$progress.PercentComplete
            $State.Index = [int]$progress.CurrentUpdateIndex + 1

            try { $State.Current = [string]$toInstall.Item([int]$progress.CurrentUpdateIndex).Title } catch { }

            Start-Sleep -Milliseconds 500
        }

        $installResult = $installer.EndInstall($job)
    }
    else {
        $installResult = $installer.Install()
    }

    $State.Percent = 100

    for ($i = 0; $i -lt $toInstall.Count; $i++) {
        $one = $installResult.GetUpdateResult($i)

        [void]$State.Results.Add([PSCustomObject]@{
                Title   = [string]$toInstall.Item($i).Title
                Code    = [int]$one.ResultCode
                HResult = [int]$one.HResult
            })
    }

    $State.RebootRequired = [bool]$installResult.RebootRequired
}
catch {
    $State.Error = [string]$_.Exception.Message

    try {
        $inner = $_.Exception
        while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
        $State.ErrorHResult = [int]$inner.HResult
    }
    catch {
        $State.ErrorHResult = 0
    }
}
finally {
    $State.Done = $true
}
'@

    return $text.Replace("__SESSION__", (Get-TFToolkitUpdateSessionCode)).Replace("__SEARCH__", (Get-TFToolkitUpdateSearchCode))
}


# ---------------------------------------------------------------------------
# Lista, resultados e textos
# ---------------------------------------------------------------------------

function Get-TFToolkitWindowsUpdateHResultText {
    <#
    Uma frase para os códigos de erro mais comuns do Windows Update (os nomes e significados são os da tabela de
    códigos do Windows Update Agent e da página de erros comuns do Windows Update, da Microsoft; os 0x8007xxxx e
    0x800Fxxxx são erros do Windows). "" para os demais. Quando o caminho é refazer o cache do Windows Update ou reparar
    os arquivos do Windows, a frase aponta o item do TF-Toolkit que faz isso.
    #>
    param ([int]$HResult)

    $cache = (Get-TFToolkitText 'use Atualizações > Corrigir o Windows Update')
    $store = (Get-TFToolkitText 'use Reparo > Reparar o Windows (DISM + SFC)')

    switch ("0x{0:X8}" -f $HResult) {
        "0x80240016" { return (Get-TFToolkitText 'outra instalação estava em andamento ou falta reiniciar o PC') }
        "0x8024200D" { return (Get-TFToolkitText 'a atualização precisa ser baixada de novo; se o erro voltar, {0}' "$cache") }
        "0x80246007" { return (Get-TFToolkitText 'a atualização não foi baixada; se o erro voltar, {0}' "$cache") }
        "0x80242006" { return (Get-TFToolkitText 'os dados da atualização guardados no PC estão inválidos; {0}' "$cache") }
        "0x80248007" { return (Get-TFToolkitText 'falta informação no cache do Windows Update; {0}' "$cache") }
        "0x8007000D" { return (Get-TFToolkitText 'o que foi baixado veio corrompido; {0}' "$cache") }
        "0x80246008" { return (Get-TFToolkitText 'o serviço de transferência do Windows (BITS) não respondeu; {0}' "$cache") }
        "0x80240034" { return (Get-TFToolkitText 'o download falhou') }
        "0x8024001E" { return (Get-TFToolkitText 'o Windows estava desligando ou o serviço parou') }
        "0x8024000B" { return (Get-TFToolkitText 'a operação foi cancelada') }
        "0x8024001F" { return (Get-TFToolkitText 'sem conexão com a internet') }
        "0x8024402C" { return (Get-TFToolkitText 'não foi possível chegar ao servidor do Windows Update (endereço não encontrado)') }
        "0x80072EFD" { return (Get-TFToolkitText 'não foi possível conectar ao servidor do Windows Update') }
        "0x80072EFE" { return (Get-TFToolkitText 'a conexão com o Windows Update caiu no meio') }
        "0x80072EE2" { return (Get-TFToolkitText 'a conexão com o Windows Update esgotou o tempo') }
        "0x8024401C" { return (Get-TFToolkitText 'o servidor do Windows Update demorou demais para responder') }
        "0x80244017" { return (Get-TFToolkitText 'o servidor recusou o acesso (um proxy ou firewall pode estar bloqueando)') }
        "0x80244018" { return (Get-TFToolkitText 'o servidor recusou o acesso (um proxy ou firewall pode estar bloqueando)') }
        "0x80244022" { return (Get-TFToolkitText 'o servidor do Windows Update está sobrecarregado; tente mais tarde') }
        "0x8024002E" { return (Get-TFToolkitText 'uma política do Windows bloqueia o acesso ao Windows Update') }
        "0x80070422" { return (Get-TFToolkitText 'o serviço Windows Update está desativado; {0}' "$cache") }
        "0x80070070" { return (Get-TFToolkitText 'falta espaço no disco') }
        "0x80070020" { return (Get-TFToolkitText 'um arquivo estava em uso por outro programa, como um antivírus') }
        "0x80070BC9" { return (Get-TFToolkitText 'o Windows precisa reiniciar para desfazer uma instalação anterior; reinicie o PC e tente de novo') }
        "0x80073712" { return (Get-TFToolkitText 'a imagem do Windows está danificada; {0}' "$store") }
        "0x80073701" { return (Get-TFToolkitText 'faltam arquivos do Windows de que a atualização precisa; {0}' "$store") }
        "0x800F081F" { return (Get-TFToolkitText 'faltam arquivos do Windows de que a atualização precisa; {0}' "$store") }
        "0x800F0831" { return (Get-TFToolkitText 'faltam arquivos do Windows de que a atualização precisa; {0}' "$store") }
    }

    return ""
}


function Format-TFToolkitUpdateError {
    # "frase — erro 0x80240016", ou só "erro 0x8024XXXX" para um código sem frase. "" sem código.
    param ([int]$HResult)

    if ($HResult -eq 0) { return "" }

    $code = "0x{0:X8}" -f $HResult
    $text = Get-TFToolkitWindowsUpdateHResultText -HResult $HResult

    if ($text) { return (Get-TFToolkitText '{0} — erro {1}' "$text" "$code") }

    return (Get-TFToolkitText 'erro {0}' "$code")
}


function Get-TFToolkitWindowsUpdateProblem {
    <#
    O motivo de a consulta (ou a instalação) ter falhado, para a pessoa. A mensagem do PowerShell embrulha a do Windows
    ('Exception calling "Search" with "1" argument(s): "Exception from HRESULT: 0x80070422"'): sai o embrulho, e um
    código conhecido vira frase. HResult é o código da exceção de origem: vale quando a mensagem não traz código nenhum
    (uma mensagem do Windows em texto puro), e o código vai junto da frase, para a pessoa poder pesquisá-lo.
    #>
    param (
        [string]$Message,
        [int]$HResult = 0
    )

    $text = ([string]$Message).Trim()

    while ($text -match '^Exception calling "[^"]+" with "[0-9]+" argument\(s\): "(.*)"$') {
        $text = $Matches[1].Trim()
    }

    # A sessão do Windows Update não abriu (Get-TFToolkitUpdateSessionCode): componente COM quebrado, não registrado ou
    # serviço que não responde. A frase diz isso; um código conhecido acrescenta o motivo, e o código vai junto.
    if ($text -match 'TF-Toolkit\.SemSessao:0x([0-9A-Fa-f]{8})') {
        $sessionCode = [Convert]::ToInt32($Matches[1], 16)
        $base = (Get-TFToolkitText 'o Windows Update não abriu neste PC')

        if ($sessionCode -eq 0) { return (Get-TFToolkitText '{0} (o componente dele não respondeu)' "$base") }

        $phrase = Get-TFToolkitWindowsUpdateHResultText -HResult $sessionCode

        return (Get-TFToolkitText '{0} ({1}) — erro {2}' "$base" "$(if ($phrase) { $phrase } else { (Get-TFToolkitText 'o componente dele não respondeu') })" "$("0x{0:X8}" -f $sessionCode)")
    }

    if ($text -match '0x([0-9A-Fa-f]{8})') {
        return (Format-TFToolkitUpdateError -HResult ([Convert]::ToInt32($Matches[1], 16)))
    }

    # Os códigos genéricos do .NET e do PowerShell não dizem nada e ficam de fora (Get-TFToolkitErrorCode).
    $code = Get-TFToolkitErrorCode -HResult $HResult

    if ($code) {
        $phrase = Get-TFToolkitWindowsUpdateHResultText -HResult $HResult

        if ($phrase) { return (Get-TFToolkitText '{0} — erro {1}' "$phrase" "$code") }
        if ([string]::IsNullOrWhiteSpace($text)) { return (Get-TFToolkitText 'erro {0}' "$code") }

        return (Get-TFToolkitText '{0} — erro {1}' "$($text.TrimEnd('.'))" "$code")
    }

    if ([string]::IsNullOrWhiteSpace($text)) { return (Get-TFToolkitText 'o Windows Update devolveu um erro') }

    return $text.TrimEnd(".")
}


function Find-TFToolkitWindowsUpdates {
    <#
    Procura as atualizações pendentes. Devolve Updates (Id, Title, Kb, Size em bytes, Downloaded e BrowseOnly; lista vazia
    = o Windows está em dia) e Problem: "" quando a consulta funcionou, ou o motivo de não ter funcionado (Updates fica
    $null). Criteria troca a busca padrão (por exemplo, só drivers).
    #>
    param (
        [int]$TimeoutSeconds = 300,

        [string]$FactoryCode = (Get-TFToolkitUpdateComFactoryCode),

        [string]$Criteria = ""
    )

    try {
        $run = Invoke-TFToolkitInBackground -ScriptBlock ([scriptblock]::Create((Get-TFToolkitUpdateSearchScript))) -ArgumentList @($FactoryCode, $Criteria) -TimeoutSeconds $TimeoutSeconds
    }
    catch {
        return [PSCustomObject]@{ Updates = $null; Problem = (Get-TFToolkitWindowsUpdateProblem -Message $_.Exception.Message -HResult $_.Exception.HResult) }
    }

    if ($run.TimedOut) {
        $minutes = [int][math]::Ceiling($TimeoutSeconds / 60)
        return [PSCustomObject]@{ Updates = $null; Problem = (Get-TFToolkitText 'o Windows Update não respondeu em {0}' "$(Format-TFToolkitCount -Count $minutes -One (Get-TFToolkitText 'minuto') -Many (Get-TFToolkitText 'minutos'))") }
    }

    if (-not $run.Completed) {
        return [PSCustomObject]@{ Updates = $null; Problem = (Get-TFToolkitWindowsUpdateProblem -Message $run.Error) }
    }

    return [PSCustomObject]@{
        Updates = @($run.Output | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Id) })
        Problem = ""
    }
}


function Get-TFToolkitUpdateOutcome {
    # Traduz o código de resultado do Windows Update (0 e 1 = não terminou, 2 = instalada, 3 = com erros, 4 = falhou,
    # 5 = interrompida), com o código de erro de cada atualização quando houver. Uma falha sem código diz isso: a faixa
    # manda ver o motivo no resumo. -Driver: "instalado com erros", no masculino.
    param (
        [int]$Code,

        [int]$HResult = 0,

        [switch]$Driver
    )

    $errorText = Format-TFToolkitUpdateError -HResult $HResult

    switch ($Code) {
        2 { return (New-TFToolkitResult -Kind Ok) }
        3 {
            $text = $(
                if ($Driver) { $(if ($errorText) { (Get-TFToolkitText 'instalado com erros: {0}' "$errorText") } else { (Get-TFToolkitText 'instalado com erros') }) }
                else { $(if ($errorText) { (Get-TFToolkitText 'instalada com erros: {0}' "$errorText") } else { (Get-TFToolkitText 'instalada com erros') }) }
            )
            return (New-TFToolkitResult -Kind Warning -Detail $text)
        }
        5 { return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'interrompida')) }
        { $_ -in 0, 1 } { return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi concluída')) }
        default { return (New-TFToolkitResult -Kind Failed -Detail $(if ($errorText) { $errorText } else { (Get-TFToolkitText 'o Windows Update não informou o motivo') })) }
    }
}


function Get-TFToolkitUpdateDownloadError {
    # O motivo de o download inteiro ter falhado (código 4) ou parado (código 5), com o erro do Windows quando houver.
    param (
        [int]$Code,

        [int]$HResult = 0
    )

    $errorText = Format-TFToolkitUpdateError -HResult $HResult

    if ($Code -eq 5) { return (Get-TFToolkitText 'o download das atualizações foi interrompido') }
    if ($errorText) { return (Get-TFToolkitText 'o download das atualizações falhou: {0}' "$errorText") }

    return (Get-TFToolkitText 'o download das atualizações falhou')
}


function Get-TFToolkitUpdateRunDetail {
    <#
    A frase do resultado de uma instalação: quantas foram instaladas e o que deu errado. Ok = instaladas sem
    problema, Warned = instaladas com erros, Failed = não instaladas.
    #>
    param (
        [int]$Ok,

        [int]$Warned,

        [int]$Failed
    )

    $total = $Ok + $Warned + $Failed
    $installed = $Ok + $Warned

    if ($installed -eq 0) {
        if ($total -eq 1) { return (Get-TFToolkitText 'a atualização não foi instalada') }

        return (Get-TFToolkitText 'nenhuma das {0} atualizações foi instalada' "$total")
    }

    if ($Failed -eq 0 -and $Warned -eq 0) {
        return (Format-TFToolkitCount -Count $Ok -One (Get-TFToolkitText 'atualização instalada') -Many (Get-TFToolkitText 'atualizações instaladas'))
    }

    $text = $(if ($installed -eq 1) { (Get-TFToolkitText '1 de {0} instalada' "$total") } else { (Get-TFToolkitText '{0} de {1} instaladas' "$installed" "$total") })

    if ($Warned -gt 0) { $text += (Get-TFToolkitText ' ({0} com erros)' "$Warned") }
    if ($Failed -eq 1) { $text += (Get-TFToolkitText '; 1 falhou') }
    elseif ($Failed -gt 1) { $text += (Get-TFToolkitText '; {0} falharam' "$Failed") }

    return $text
}


function Get-TFToolkitUpdateTitleById {
    # O título da atualização com o Id dado, na lista que a pessoa viu; sem ela, o próprio Id.
    param (
        [object[]]$Updates,

        [Parameter(Mandatory)]
        [string]$Id
    )

    $match = @($Updates | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1

    if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace([string]$match.Title)) {
        return [string]$match.Title
    }

    return $Id
}


function Get-TFToolkitUpdateSizeText {
    # O tamanho para a pessoa: o Windows informa o máximo que o download pode ter (MaxDownloadSize); com as atualizações
    # expressas ele costuma ser menor, por isso "até".
    param ([Parameter(Mandatory)]$Update)

    if ($Update.Downloaded) { return (Get-TFToolkitText 'já baixada') }
    if ([int64]$Update.Size -gt 0) { return (Get-TFToolkitText 'até {0}' "$(Format-TFToolkitBytes -Bytes ([int64]$Update.Size))") }

    return (Get-TFToolkitText 'tamanho não informado')
}


function Get-TFToolkitDriverClassText {
    # A classe do driver no Windows Update (a classe de instalação do aparelho) com o nome que a pessoa conhece. Uma classe
    # sem tradução aqui aparece como veio; vazio sem classe.
    param ([string]$Class)

    switch -Regex (([string]$Class).Trim()) {
        '^Display$' { return (Get-TFToolkitText 'vídeo') }
        '^Net$' { return (Get-TFToolkitText 'rede') }
        '^Bluetooth$' { return (Get-TFToolkitText 'Bluetooth') }
        '^(MEDIA|AudioEndpoint|AudioProcessingObject)$' { return (Get-TFToolkitText 'som') }
        '^(Camera|Image)$' { return (Get-TFToolkitText 'câmera') }
        '^USB$' { return "USB" }
        '^(HIDClass|Keyboard|Mouse)$' { return (Get-TFToolkitText 'teclado, mouse ou touchpad') }
        '^System$' { return (Get-TFToolkitText 'sistema') }
        '^Firmware$' { return (Get-TFToolkitText 'firmware (como a BIOS)') }
        '^(Printer|PrintQueue)$' { return (Get-TFToolkitText 'impressora') }
        '^SoftwareComponent$' { return (Get-TFToolkitText 'programa de apoio do aparelho') }
        '^Extension$' { return (Get-TFToolkitText 'extensão de outro driver') }
        '^Biometric$' { return (Get-TFToolkitText 'biometria') }
        '^(SCSIAdapter|HDC|DiskDrive)$' { return (Get-TFToolkitText 'disco') }
        '^Monitor$' { return (Get-TFToolkitText 'monitor') }
        '^SecurityDevices$' { return (Get-TFToolkitText 'segurança (TPM)') }
        '^Sensor$' { return (Get-TFToolkitText 'sensores') }
        '^Battery$' { return (Get-TFToolkitText 'bateria') }
        '^$' { return "" }
    }

    return ([string]$Class).Trim()
}


function Get-TFToolkitDriverPurposeText {
    <#
    Para que serve um driver da lista: "vídeo: Intel(R) UHD Graphics 620", só a classe ou só o aparelho; vazio sem nenhum
    dos dois. Prefix vai na frente quando há texto (" de " para "driver de vídeo: ...").
    #>
    param (
        [Parameter(Mandatory)]$Update,
        [string]$Prefix = ""
    )

    $class = Get-TFToolkitDriverClassText -Class ([string](Get-TFToolkitJsonValue -Object $Update -Name "DriverClass" -Default ""))
    $model = ([string](Get-TFToolkitJsonValue -Object $Update -Name "DriverModel" -Default "")).Trim()

    if ($model.Length -gt 60) { $model = $model.Substring(0, 57) + "..." }

    $text = $(if ($class -and $model) { "${class}: $model" } elseif ($class) { $class } else { $model })

    return $(if ($text) { "$Prefix$text" } else { "" })
}


function Test-TFToolkitFirmwareUpdate {
    # Se a atualização é de firmware (a BIOS/UEFI ou o de um componente): a que não pode ser interrompida de jeito nenhum.
    param ([Parameter(Mandatory)]$Update)

    return ([string](Get-TFToolkitJsonValue -Object $Update -Name "DriverClass" -Default "")).Trim() -eq "Firmware"
}


function Write-TFToolkitFirmwareWarning {
    # Um firmware entre as escolhidas: ele termina no reinício, e faltar energia no meio pode deixar o PC sem ligar.
    param ([AllowEmptyCollection()][object[]]$Updates = @())

    if (@($Updates | Where-Object { Test-TFToolkitFirmwareUpdate -Update $_ }).Count -gt 0) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Há uma atualização de firmware (como a BIOS): ela termina no reinício. Não desligue o PC e, num notebook, deixe-o na tomada.')
    }
}


function Write-TFToolkitMeteredWarning {
    # Numa conexão limitada (plano de dados), avisa antes de baixar: o próprio Windows não baixaria sozinho.
    param ([int64]$Bytes = 0)

    if (-not (Test-TFToolkitMeteredConnection)) { return }

    $what = $(if ($Bytes -gt 0) { (Get-TFToolkitText 'baixar até {0}' "$(Format-TFToolkitBytes -Bytes $Bytes)") } else { (Get-TFToolkitText 'baixar as atualizações') })
    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A conexão com a internet está marcada como limitada (plano de dados): {0} pode consumir a sua franquia.' "$what")
}


function Get-TFToolkitUpdateOptionLabel {
    param ([Parameter(Mandatory)]$Update)

    if ([string]::IsNullOrWhiteSpace($Update.Kb)) {
        return $Update.Title
    }

    if ($Update.Title -match "KB$([regex]::Escape($Update.Kb))") {
        return $Update.Title
    }

    return "$($Update.Title) (KB$($Update.Kb))"
}


function Get-TFToolkitWindowsUpdatePolicy {
    <#
    O que as políticas do Windows dizem sobre o Windows Update. Server: o servidor da empresa (WSUS) de onde as
    atualizações vêm, quando a política está ligada. Blocked: o acesso ao Windows Update desligado, por
    DisableWindowsUpdateAccess (nas duas chaves de política em que o Windows a lê) ou, sem servidor de empresa, por
    DoNotConnectToWindowsUpdateInternetLocations; as duas dão o erro 0x8024002E. Num PC de casa, quem costuma pôr essas
    políticas é um programa bloqueador de atualizações. Sem as chaves (o normal) ou sem leitura, nada.
    #>
    $key = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $server = ""
    $blocked = $false

    try {
        $values = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        $au = Get-ItemProperty -LiteralPath "$key\AU" -ErrorAction SilentlyContinue

        if ([string](Get-TFToolkitJsonValue -Object $au -Name "UseWUServer" -Default "0") -eq "1") {
            $server = ([string](Get-TFToolkitJsonValue -Object $values -Name "WUServer" -Default "")).Trim()
        }

        $blocked = ([string](Get-TFToolkitJsonValue -Object $values -Name "DisableWindowsUpdateAccess" -Default "0") -eq "1") -or
            (-not $server -and [string](Get-TFToolkitJsonValue -Object $values -Name "DoNotConnectToWindowsUpdateInternetLocations" -Default "0") -eq "1")

        foreach ($other in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate")) {
            $value = Get-ItemProperty -LiteralPath $other -ErrorAction SilentlyContinue
            if ([string](Get-TFToolkitJsonValue -Object $value -Name "DisableWindowsUpdateAccess" -Default "0") -eq "1") { $blocked = $true }
        }
    }
    catch {
        Write-Verbose "Políticas do Windows Update: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{ Server = $server; Blocked = $blocked }
}


function Get-TFToolkitWindowsUpdatePause {
    <#
    Se as atualizações do Windows estão pausadas (Configurações > Windows Update > Pausar atualizações, ou uma política
    da empresa). $null quando não estão, ou sem leitura; senão Until, o fim da pausa na hora local ($null quando o
    Windows não diz). A situação vem de PausedQualityStatus, que a Microsoft documenta em UpdatePolicy\Settings (1 =
    pausadas; 0 e 2, sem pausa ou retomadas sozinhas no fim do prazo); a data, de PauseUpdatesExpiryTime, que a página das
    Configurações grava em UTC. Sem a situação, a data no futuro basta. Now: a hora de agora (para os testes).
    #>
    param ([datetime]$Now = (Get-Date))

    try {
        $policy = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings" -ErrorAction SilentlyContinue
        $settings = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -ErrorAction SilentlyContinue
        $status = Get-TFToolkitJsonValue -Object $policy -Name "PausedQualityStatus" -Default $null
        $expiry = ([string](Get-TFToolkitJsonValue -Object $settings -Name "PauseUpdatesExpiryTime" -Default "")).Trim()
        $until = $null
        $parsed = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal

        if ($expiry -and [datetime]::TryParse($expiry, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
            $local = $parsed.ToLocalTime()
            if ($local -gt $Now) { $until = $local }
        }

        if ($null -ne $status) {
            if ([string]$status -ne "1") { return $null }
        }
        elseif ($null -eq $until) {
            return $null
        }

        return [PSCustomObject]@{ Until = $until }
    }
    catch {
        Write-Verbose "Pausa do Windows Update: $($_.Exception.Message)"
        return $null
    }
}


function Get-TFToolkitUpdatePauseText {
    # A pausa em palavras: a frase ("As atualizações do Windows estão pausadas até 05/12/2026."), o pedaço para o
    # resultado (-Detail: "pausadas até 05/12/2026") ou o da faixa do alto da página (-Status: "pausado até 05/12/2026").
    param (
        [Parameter(Mandatory)]$Pause,
        [switch]$Detail,
        [switch]$Status
    )

    $until = Get-TFToolkitJsonValue -Object $Pause -Name "Until" -Default $null
    $date = $(if ($until -is [datetime]) { Format-TFToolkitDateTime -When $until -Pattern 'dd/MM/yyyy' } else { "" })

    if ($Status) { return $(if ($date) { (Get-TFToolkitText 'pausado até {0}' "$date") } else { (Get-TFToolkitText 'pausado') }) }
    if ($Detail) { return $(if ($date) { (Get-TFToolkitText 'pausadas até {0}' "$date") } else { (Get-TFToolkitText 'pausadas nas Configurações') }) }

    return $(if ($date) { (Get-TFToolkitText 'As atualizações do Windows estão pausadas até {0}.' "$date") } else { (Get-TFToolkitText 'As atualizações do Windows estão pausadas.') })
}


function Test-TFToolkitMeteredUpdateDownload {
    <#
    Se o Windows baixa as atualizações numa conexão limitada: a chave "Baixar atualizações em conexões limitadas" das
    Configurações ou a política que a decide (AllowAutoWindowsUpdateDownloadOverMeteredNetwork, 1 = baixa). Com a
    política, vale ela; sem leitura, $false.
    #>
    $name = "AllowAutoWindowsUpdateDownloadOverMeteredNetwork"

    foreach ($key in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings")) {
        try {
            $value = Get-TFToolkitJsonValue -Object (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue) -Name $name -Default $null
            if ($null -ne $value) { return ([string]$value -eq "1") }
        }
        catch {
            Write-Verbose "Conexão limitada do Windows Update: $($_.Exception.Message)"
        }
    }

    return $false
}


function Write-TFToolkitWindowsUpdatePolicyNote {
    <#
    Quando uma política muda de onde vêm as atualizações, a tela diz isso: é a explicação mais provável de uma consulta
    que falha, e nenhum reparo do TF-Toolkit a muda. Devolve $true quando escreveu.
    #>
    $policy = Get-TFToolkitWindowsUpdatePolicy
    $who = (Get-TFToolkitText 'Num PC de empresa, fale com o suporte de TI; num PC de casa, um programa bloqueador de atualizações costuma fazer isso: desfaça a configuração por ele.')

    if ($policy.Blocked) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Uma política do Windows desliga o acesso ao Windows Update neste PC. {0}' "$who")
        return $true
    }

    if ($policy.Server) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Uma política do Windows manda buscar as atualizações num servidor da empresa ({0}), e não no Windows Update. {1}' "$($policy.Server)" "$who")
        return $true
    }

    return $false
}


function Write-TFToolkitWindowsUpdateSearchHelp {
    <#
    O que fazer quando a consulta ao Windows Update falha, depois do motivo: a política que muda de onde vêm as
    atualizações, quando há uma; senão, se o motivo não é a conexão nem já diz o caminho, o reparo do Windows Update.
    #>
    param ([string]$Problem)

    if (Write-TFToolkitWindowsUpdatePolicyNote) { return }
    # Palavras dos motivos nos três idiomas da interface, mais os nomes do item e da página no idioma de agora.
    $known = 'Corrigir o Windows Update|Reparo >|internet|conectar|conexão|servidor|proxy|firewall|política|espaço|connect|server|policy|space|conexión|directiva|espacio'
    $here = "$([regex]::Escape((Get-TFToolkitText 'Corrigir o Windows Update')))|$([regex]::Escape((Get-TFToolkitText 'Reparo'))) >"
    if ($Problem -match $known -or $Problem -match $here) { return }

    # O reparo refaz o cache de atualizações e religa os serviços.
    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Se o erro se repetir, use Atualizações > Corrigir o Windows Update.')
}


# ---------------------------------------------------------------------------
# Acompanhamento
# ---------------------------------------------------------------------------

function Wait-TFToolkitUpdateJob {
    <#
    Espera o trabalho do outro runspace mostrando o andamento na barra de progresso. Devolve $true se terminou e $false
    se o tempo esgotou. A espera é em fatias de um segundo, então o botão Parar continua valendo; ao ser interrompida, o
    chamador cuida de parar o runspace (o serviço do Windows Update pode continuar a instalar por conta própria).
    #>
    param (
        [Parameter(Mandatory)]
        $Handle,

        [Parameter(Mandatory)]
        $State,

        [int]$TimeoutMinutes = 180
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastKey = ""

    while (-not $Handle.AsyncWaitHandle.WaitOne(1000)) {
        if ($stopwatch.Elapsed.TotalMinutes -ge $TimeoutMinutes) {
            return $false
        }

        $key = "$($State.Phase)|$($State.Index)|$($State.Percent)|$($State.Current)"

        if ($key -eq $lastKey) { continue }

        $lastKey = $key

        if ($State.Phase -in "Baixando", "Instalando") {
            $activity = $(if ($State.Phase -eq "Baixando") { (Get-TFToolkitText 'Baixando as atualizações') } else { (Get-TFToolkitText 'Instalando as atualizações') })
            $status = (Get-TFToolkitText '{0} de {1}' "$($State.Index)" "$($State.Total)")

            if (-not [string]::IsNullOrWhiteSpace([string]$State.Current)) { $status += ": $($State.Current)" }

            Write-Progress -Activity $activity -Status $status -PercentComplete ([math]::Max(0, [math]::Min(100, [int]$State.Percent)))
        }
        else {
            # Antes de baixar, o Windows Update confere de novo as escolhidas, o que pode demorar.
            Write-Progress -Activity (Get-TFToolkitText 'Preparando a instalação') -Status (Get-TFToolkitText 'o Windows Update confere as atualizações escolhidas')
        }
    }

    return $true
}


function Invoke-TFToolkitUpdateInstall {
    <#
    Baixa e instala as atualizações com os Ids dados, no outro runspace, acompanhando o progresso na tela. Devolve o
    estado final: Done, Error, Results (Title, Code, HResult), RebootRequired, TimedOut, Missing (Ids que o Windows
    deixou de oferecer) e NotDownloaded (Ids que não foram baixados).
    #>
    param (
        [Parameter(Mandatory)]
        [string[]]$Ids,

        [string]$FactoryCode = (Get-TFToolkitUpdateComFactoryCode),

        [int]$TimeoutMinutes = 180,

        [string]$Criteria = ""
    )

    $state = [hashtable]::Synchronized(@{
            Phase          = "Preparando"
            Percent        = 0
            Index          = 0
            Total          = 0
            Current        = ""
            Error          = ""
            ErrorHResult   = 0
            DownloadCode   = 0
            DownloadHResult = 0
            Done           = $false
            Reason         = ""
            RebootRequired = $false
            Results        = (New-Object System.Collections.ArrayList)
            Missing        = (New-Object System.Collections.ArrayList)
            NotDownloaded  = (New-Object System.Collections.ArrayList)
        })

    $task = Start-TFToolkitInBackground -ScriptBlock ([scriptblock]::Create((Get-TFToolkitUpdateInstallScript))) -ArgumentList @($state, $Ids, $FactoryCode, $Criteria)
    $timedOut = $false

    try {
        if (Wait-TFToolkitUpdateJob -Handle $task.Handle -State $state -TimeoutMinutes $TimeoutMinutes) {
            [void]$task.Shell.EndInvoke($task.Handle)
        }
        else {
            $timedOut = $true
        }
    }
    finally {
        Write-Progress -Activity (Get-TFToolkitText 'Instalando as atualizações') -Completed

        # Terminado, o runspace é liberado; interrompido (o Parar) ou sem resposta, o pedido de parar não espera uma
        # chamada COM presa.
        Stop-TFToolkitInBackground -Task $task
    }

    # O texto do erro passa pela mesma tradução da consulta: sem o embrulho do PowerShell, com a frase de um código
    # conhecido e sempre com o código. O download que falhou inteiro só deixa os códigos no estado (DownloadCode
    # diferente de zero), e os dois casos sem erro do Windows, só o nome (Reason).
    $errorText = [string]$state.Error
    if (-not [string]::IsNullOrWhiteSpace($errorText)) { $errorText = Get-TFToolkitWindowsUpdateProblem -Message $errorText -HResult ([int]$state.ErrorHResult) }
    if ([int]$state.DownloadCode -ne 0) { $errorText = Get-TFToolkitUpdateDownloadError -Code ([int]$state.DownloadCode) -HResult ([int]$state.DownloadHResult) }
    if ([string]$state.Reason -eq "Missing") { $errorText = (Get-TFToolkitText 'as atualizações escolhidas não estão mais disponíveis') }
    if ([string]$state.Reason -eq "NotDownloaded") { $errorText = (Get-TFToolkitText 'nenhuma das atualizações foi baixada, então nada foi instalado') }

    return [PSCustomObject]@{
        Done           = [bool]$state.Done
        Error          = $errorText
        Results        = @($state.Results)
        RebootRequired = [bool]$state.RebootRequired
        TimedOut       = $timedOut
        Missing        = @($state.Missing)
        NotDownloaded  = @($state.NotDownloaded)
    }
}


# ---------------------------------------------------------------------------
# Ação
# ---------------------------------------------------------------------------

function Get-TFToolkitUpdateSupportStatus {
    <#
    Até quando este Windows recebe atualizações de segurança (Get-TFToolkitWindowsSupportStatus), para a tela não dizer
    "em dia" a um Windows sem suporte: a versão nova do Windows é opcional no Windows Update e não entra na lista. $null
    quando não foi possível saber.
    #>
    try {
        return (Get-TFToolkitWindowsSupportStatus)
    }
    catch {
        Write-Verbose "Suporte do Windows: $($_.Exception.Message)"
        return $null
    }
}


function Test-TFToolkitWindowsSupportEnded {
    # Verdadeiro quando este Windows não recebe mais atualizações de segurança: fora do suporte, ou só com o ESU, que
    # deu para conferir e não está instalado.
    param ($Status)

    if ($null -eq $Status) { return $false }

    $state = [string](Get-TFToolkitJsonValue -Object $Status -Name "State" -Default "")

    return ($state -eq "Ended" -or ($state -eq "EsuAvailable" -and [bool](Get-TFToolkitJsonValue -Object $Status -Name "EsuChecked" -Default $false)))
}


function Get-TFToolkitSupportEndedText {
    # "o Windows 11 24H2 não recebe mais atualizações de segurança desde 13/10/2026" (sem a data quando ela não é conhecida).
    param ([Parameter(Mandatory)]$Status)

    $product = [string](Get-TFToolkitJsonValue -Object $Status -Name "Product" -Default "")
    if ([string]::IsNullOrWhiteSpace($product)) { $product = "Windows" }

    $text = (Get-TFToolkitText 'o {0} não recebe mais atualizações de segurança' "$product")
    $end = Get-TFToolkitJsonValue -Object $Status -Name "EndDate" -Default $null

    if ($end -is [datetime]) { $text += (Get-TFToolkitText ' desde {0}' "$(Format-TFToolkitDateTime -When $end -Pattern 'dd/MM/yyyy')") }

    return $text
}


function Write-TFToolkitUpdateSupportNote {
    <#
    O que a tela de atualizações diz sobre o suporte do Windows. Sem suporte: um aviso (com -NothingPending, no lugar do
    "em dia"), o que fazer e onde ver os detalhes. Perto do fim (ou sem conseguir conferir o ESU): uma linha de informação.
    Devolve $true quando o Windows está sem suporte.
    #>
    param (
        $Status,
        [switch]$NothingPending
    )

    if ($null -eq $Status) { return $false }

    $state = [string](Get-TFToolkitJsonValue -Object $Status -Name "State" -Default "")

    if (Test-TFToolkitWindowsSupportEnded -Status $Status) {
        $ended = Get-TFToolkitSupportEndedText -Status $Status

        if ($NothingPending) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não há atualizações pendentes, mas {0}.' "$ended")
        }
        else {
            Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText '{0}{1}: instalar as pendentes não muda isso.' "$($ended.Substring(0, 1).ToUpperInvariant())" "$($ended.Substring(1))")
        }

        $advice = [string](Get-TFToolkitJsonValue -Object $Status -Name "Advice" -Default "")
        if ($advice) { Write-TFToolkitStatus -Type Info -Message $advice }

        # A edição de longo prazo (LTSC) não recebe a versão nova pelo Windows Update.
        if ([string](Get-TFToolkitJsonValue -Object $Status -Name "Class" -Default "") -ne "Ltsc") {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Quando houver uma versão nova para este PC, ela aparece em Atualizações > Windows Update, no botão Baixar e instalar.')
        }

        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Detalhes em Diagnóstico > Suporte do Windows.')
        return $true
    }

    if ($state -in @("EndingSoon", "EsuAvailable")) {
        $text = ([string](Get-TFToolkitJsonValue -Object $Status -Name "Text" -Default "")).Trim()
        if ($text) { Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText '{0} Veja Diagnóstico > Suporte do Windows.' "$text") }
    }

    return $false
}


function Get-TFToolkitUpdatesPageStatus {
    <#
    O resumo no alto da página Atualizações (New-GuiPageStatus), de leituras rápidas, sem consultar o Windows Update: a
    versão do Windows e até quando ela recebe atualizações de segurança (o catálogo do TF-Toolkit, como no Início) e, só
    quando pede atenção, o Windows Update pausado nas Configurações ou parado numa atualização antiga. Cada linha tem
    Label, Text, Level (Normal | Warn) e Opens: o suporte que pede atenção abre Suporte do Windows; a pausa, o Windows
    Update das Configurações, onde se retoma; o atraso, Instalar atualizações do Windows.
    #>
    $rows = @()
    $support = Get-TFToolkitUpdateSupportStatus

    if ($null -ne $support -and [string]$support.Product) {
        $short = Get-TFToolkitWindowsSupportShortText -Status $support
        $issue = Get-TFToolkitWindowsSupportIssue -Status $support
        $rows += [PSCustomObject]@{
            Label = "Windows"
            Text  = $(if ($short) { "$([string]$support.Product) · $short" } else { [string]$support.Product })
            Level = $(if ($null -ne $issue) { "Warn" } else { "Normal" })
            Opens = $(if ($null -ne $issue) { "diagnostics.windows-support" } else { "" })
        }
    }

    $pause = Get-TFToolkitWindowsUpdatePause

    if ($null -ne $pause) {
        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Windows Update'); Text = (Get-TFToolkitUpdatePauseText -Pause $pause -Status); Level = "Warn"; Opens = "updates.windows" }
    }
    elseif ($null -ne $support -and [string]$support.State -in @("Supported", "EndingSoon", "Esu")) {
        # A mesma conta do Início: a revisão instalada contra a atualização de segurança de dois meses atrás.
        $lag = $null
        try { $lag = Get-TFToolkitWindowsUpdateLag -Build ([int]$support.Build) } catch { $lag = $null }

        if ($lag -eq $true) {
            $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Windows Update'); Text = (Get-TFToolkitText 'faltam atualizações de segurança'); Level = "Warn"; Opens = "updates.install" }
        }
    }

    return @($rows)
}


function Request-TFToolkitRestartOffer {
    <#
    Oferece reiniciar ali mesmo (Request-TFToolkitRestart, com Não como padrão), quando a tela pede um reinício. Um
    problema ao pedir o reinício não muda o resultado da ação: a tela só diz para reiniciar depois (Fallback).
    #>
    param (
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$Comment,
        [Parameter(Mandatory)][string]$DeclinedMessage,
        [string]$Fallback = (Get-TFToolkitText 'Reinicie o PC quando puder.')
    )

    try {
        [void](Request-TFToolkitRestart -Reason $Reason -Comment $Comment -DeclinedMessage $DeclinedMessage)
    }
    catch {
        Write-Verbose "Oferta de reinício: $($_.Exception.Message)"
        Write-TFToolkitStatus -Type Info -Message $Fallback
    }
}


function Request-TFToolkitInstallRestart {
    # O reinício que conclui uma instalação (atualizações, drivers). What: o que falta terminar ("as atualizações");
    # Later: a frase de quem não reiniciou agora.
    param (
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][string]$Later
    )

    Request-TFToolkitRestartOffer -Reason (Get-TFToolkitText 'Para terminar de instalar {0}, o Windows precisa reiniciar.' "$What") `
        -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit para terminar de instalar {0}.' "$What") `
        -DeclinedMessage (Get-TFToolkitText 'Reinicialização não iniciada. {0}' "$Later") `
        -Fallback (Get-TFToolkitText 'Reinicie o PC para terminar a instalação.')
}


function Confirm-TFToolkitUpdateConditions {
    <#
    Antes de procurar o que instalar pelo Windows Update (atualizações ou drivers): com as atualizações pausadas nas
    Configurações, com um reinício pendente ou com o notebook na bateria, a tela diz por que isso importa (Reboot,
    Battery) e pergunta. A pausa e a bateria perguntam com Cancelar como padrão; o reinício pendente é a escolha do
    Otimizar (Read-TFToolkitPendingRebootChoice), e Retry é o item para abrir de novo depois de reiniciar. Devolve $null
    para seguir; senão, o resultado com que a tela termina (a pessoa desistiu, ou o PC está reiniciando), com o que fazer
    já escrito.
    #>
    param (
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Reboot,
        [Parameter(Mandatory)][string]$Battery,
        [string]$Retry = (Get-TFToolkitText 'Atualizações > Instalar atualizações do Windows')
    )

    # Pausadas, o Windows não baixa nem instala nada até a data: procurar por aqui é uma escolha da pessoa.
    $pause = Get-TFToolkitWindowsUpdatePause

    if ($null -ne $pause) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitUpdatePauseText -Pause $pause)

        if (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Procurar mesmo assim?') -DefaultKey "N" -YesLabel (Get-TFToolkitText 'Procurar mesmo assim') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Para retomar, use Atualizações > Windows Update.')
            $paused = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitUpdatePauseText -Pause $pause -Detail) -Title $Title

            return (Set-TFToolkitResultView -Result $paused -Headline (Get-TFToolkitText 'As atualizações estão pausadas') -Note (Get-TFToolkitText 'Retome no Windows Update, nas Configurações.') `
                    -Next "updates.windows" -NextLabel (Get-TFToolkitText 'Abrir o Windows Update'))
        }
    }

    if (Test-TFToolkitPendingReboot) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Há um reinício pendente. {0}' "$Reboot")

        $answer = Read-TFToolkitPendingRebootChoice -Question (Get-TFToolkitText 'Reiniciar antes de atualizar?') -Then (Get-TFToolkitText 'Depois, abra {0} de novo' "$Retry") `
            -Reason (Get-TFToolkitText 'Reinicie agora e, depois, abra {0} de novo.' "$Retry") `
            -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit (reinício pendente antes de atualizar).') `
            -DeclinedMessage (Get-TFToolkitText 'Reinicialização não iniciada. Reinicie o PC e tente de novo.')

        if ($answer -eq "Restarting") { return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'o PC está reiniciando') -Title $Title) }

        if ($answer -ne "Continue") {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $Title)
        }
    }

    if (Test-TFToolkitOnBattery) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O notebook está na bateria. {0}' "$Battery")

        if (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Instalar mesmo assim?') -DefaultKey "N" -YesLabel (Get-TFToolkitText 'Instalar mesmo assim') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Ligue o carregador e tente de novo.')
            return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $Title)
        }
    }

    return $null
}


function Get-TFToolkitUpdateRunResult {
    <#
    O desfecho de uma instalação pelo Windows Update (Invoke-TFToolkitUpdateInstall), das atualizações ou, com -Drivers, dos
    drivers: a tabela com cada uma, a anotação no Histórico de mudanças e o TFToolkit.Result, com as contas e os motivos
    para a faixa (Set-TFToolkitInstallView) e Data.RebootRequired quando alguma instalada pede o reinício. Chosen: o que a
    pessoa viu (para dar nome ao que não chegou a ser instalado). Um erro no meio, depois de alguns resultados, vai em
    Data.Interrupted.
    #>
    param (
        [Parameter(Mandatory)]$Run,
        [AllowEmptyCollection()][object[]]$Chosen = @(),
        [string]$Title = "",
        [string]$SectionTitle = (Get-TFToolkitText 'Resumo'),
        [switch]$Drivers
    )

    $chosen = @($Chosen)
    $final = $null

    if ($run.TimedOut) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O TF-Toolkit parou de acompanhar depois de muito tempo. O Windows pode continuar instalando: veja o andamento em Atualizações > Windows Update.')
        $final = Set-TFToolkitUpdateTimeoutView -Result (New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'tempo esgotado; a instalação pode continuar') -Title $Title)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($run.Error) -and $run.Results.Count -eq 0) {
        $why = $run.Error.TrimEnd('.')
        Write-TFToolkitStatus -Type Error -Message $(if ($Drivers) { (Get-TFToolkitText 'Não foi possível instalar os drivers: {0}.' "$why") } else { (Get-TFToolkitText 'Não foi possível instalar as atualizações: {0}.' "$why") })
        $final = New-TFToolkitResult -Kind Failed -Detail $run.Error -Title $Title
    }
    else {
        $results = @()

        foreach ($item in $run.Results) {
            $outcome = Get-TFToolkitUpdateOutcome -Code $item.Code -HResult $item.HResult -Driver:$Drivers
            $outcome.Etapa = $item.Title
            $results += $outcome
        }

        # As escolhidas que não chegaram a ser instaladas também entram no resumo, com o nome que a pessoa viu.
        foreach ($id in @($run.NotDownloaded)) {
            $outcome = New-TFToolkitResult -Kind Failed -Detail $(if ($Drivers) { (Get-TFToolkitText 'não foi baixado') } else { (Get-TFToolkitText 'não foi baixada') })
            $outcome.Etapa = Get-TFToolkitUpdateTitleById -Updates $chosen -Id $id
            $results += $outcome
        }

        foreach ($id in @($run.Missing)) {
            $outcome = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não está mais disponível')
            $outcome.Etapa = Get-TFToolkitUpdateTitleById -Updates $chosen -Id $id
            $results += $outcome
        }

        Write-TFToolkitSection -Title $SectionTitle
        Write-TFToolkitResultTable -Results $results

        $failed = @($results | Where-Object { $_.Kind -eq "Failed" })
        $warned = @($results | Where-Object { $_.Kind -eq "Warning" })
        $installed = @($run.Results | Where-Object { [int]$_.Code -in 2, 3 })

        # O Histórico de mudanças anota o que foi instalado: as atualizações pelo número KB quando houver (os títulos são
        # longos), os drivers pelo nome.
        if ($installed.Count -gt 0 -and $Drivers) {
            [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Drivers instalados') -Text (Join-TFToolkitList -Items @($installed | ForEach-Object { [string]$_.Title })))
        }
        elseif ($installed.Count -gt 0) {
            $installedNames = @(
                foreach ($item in $installed) {
                    $match = @($chosen | Where-Object { [string]$_.Title -eq [string]$item.Title }) | Select-Object -First 1
                    if ($null -ne $match -and $match.Kb) { "KB$($match.Kb)" } else { [string]$item.Title }
                }
            )

            [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Atualizações do Windows') -Text "$(Format-TFToolkitCount -Count $installedNames.Count -One (Get-TFToolkitText 'instalada') -Many (Get-TFToolkitText 'instaladas')): $(Join-TFToolkitList -Items $installedNames)")
        }

        # "Reinicie para concluir" só faz sentido se alguma foi instalada; sem nenhuma, o motivo de cada uma diz o que fazer.
        $reboot = [bool]$run.RebootRequired -and $failed.Count -lt $results.Count

        $okCount = $results.Count - $failed.Count - $warned.Count
        $detail = $(if ($Drivers) { Get-TFToolkitDriverRunDetail -Ok $okCount -Warned $warned.Count -Failed $failed.Count } else { Get-TFToolkitUpdateRunDetail -Ok $okCount -Warned $warned.Count -Failed $failed.Count })

        # As contas e os motivos, para a faixa da janela (Set-TFToolkitInstallView).
        $data = @{
            RebootRequired = $reboot
            Installed      = ($results.Count - $failed.Count)
            Failed         = $failed.Count
            Warned         = $warned.Count
            Problems       = @(@($failed) + @($warned) | ForEach-Object { [string]$_.Detail } | Where-Object { $_ })
        }

        # Um erro depois de algumas atualizações já terem resultado (por exemplo, ao ler o resultado das outras) deixa o
        # resumo incompleto: ele não pode sumir nem terminar como "Tudo certo", e a faixa diz que a instalação parou.
        $cutShort = -not [string]::IsNullOrWhiteSpace($run.Error)

        if ($cutShort) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'A instalação foi interrompida por um erro: {0}.' "$($run.Error.TrimEnd('.'))")
            $detail = (Get-TFToolkitText '{0}; erro durante a instalação: {1}' "$detail" "$($run.Error)")
            $data.Interrupted = [string]$run.Error
        }

        if ($failed.Count -eq $results.Count) {
            $final = New-TFToolkitResult -Kind Failed -Detail $detail -Title $Title -Data $data
        }
        elseif ($failed.Count -gt 0 -or $warned.Count -gt 0 -or $cutShort) {
            $final = New-TFToolkitResult -Kind Warning -Detail $detail -Title $Title -Data $data
        }
        else {
            $final = New-TFToolkitResult -Kind Ok -Detail $detail -Title $Title -Data $data
        }
    }

    return $final
}


function Set-TFToolkitUpdateTimeoutView {
    # A faixa de quando o TF-Toolkit parou de acompanhar a instalação (atualizações ou drivers): o Windows pode continuar
    # instalando sozinho, e o botão abre o andamento nas Configurações. Devolve o próprio resultado.
    param ([Parameter(Mandatory)]$Result)

    return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'O TF-Toolkit parou de acompanhar') `
            -Note (Get-TFToolkitText 'O Windows pode continuar instalando; veja o andamento no Windows Update.') -Next "updates.windows" -NextLabel (Get-TFToolkitText 'Ver o andamento'))
}


function Get-TFToolkitUpdateFixStep {
    <#
    O item do TF-Toolkit que resolve um erro do Windows Update, para o botão da faixa: os motivos (Get-TFToolkitWindowsUpdateHResultText)
    já dizem "use Atualizações > Corrigir o Windows Update" ou "use Reparo > Reparar o Windows (DISM + SFC)" quando é o
    caso; "falta espaço no disco" leva a liberar espaço. Next e Label vazios quando nenhum motivo aponta um item.
    #>
    param ([AllowEmptyCollection()][string[]]$Texts = @())

    $all = (@($Texts) | Where-Object { $_ }) -join " | "

    # Os motivos citam o item com o nome do idioma da tela (e, gravados antes, em português).
    if ($all -match 'Corrigir o Windows Update' -or $all -match [regex]::Escape((Get-TFToolkitText 'Corrigir o Windows Update'))) { return [PSCustomObject]@{ Next = "updates.repair"; Label = (Get-TFToolkitText 'Corrigir o Windows Update') } }
    if ($all -match 'Reparar o Windows \(DISM \+ SFC\)' -or $all -match [regex]::Escape((Get-TFToolkitText 'Reparar o Windows (DISM + SFC)'))) { return [PSCustomObject]@{ Next = "repair.dism-sfc"; Label = (Get-TFToolkitText 'Reparar o Windows') } }
    if ($all -match 'falta espaço no disco' -or $all -match [regex]::Escape((Get-TFToolkitText 'falta espaço no disco'))) { return [PSCustomObject]@{ Next = "cleanup.custom"; Label = (Get-TFToolkitText 'Liberar espaço') } }

    return [PSCustomObject]@{ Next = ""; Label = "" }
}


function Set-TFToolkitInstallView {
    <#
    A faixa de uma instalação pelo Windows Update (atualizações ou drivers, Get-TFToolkitUpdateRunResult e a dos drivers):
    o título diz quantas foram instaladas; a frase, se falta reiniciar (ou como voltar atrás, nos drivers) ou que o motivo
    de cada falha está no resumo; e, quando um motivo aponta um item do TF-Toolkit, o botão para ele. Um, Many e None são
    os textos do que foi instalado ("atualização instalada", "atualizações instaladas", "Nenhuma atualização instalada"); Partial, o
    de quando só parte foi instalada, com {0} e {1} ("{0} de {1} atualizações instaladas"). OkNote: a
    frase de quando deu tudo certo sem reinício. Devolve o próprio resultado.
    #>
    param (
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$One,
        [Parameter(Mandatory)][string]$Many,
        [Parameter(Mandatory)][string]$None,
        [string]$OkNote = (Get-TFToolkitText 'Não precisa reiniciar.'),
        [string]$Each = (Get-TFToolkitText 'cada uma'),
        # O título de quando só parte deu certo: {0} instaladas de {1} ("{0} de {1} atualizações instaladas").
        [string]$Partial = (Get-TFToolkitText '{0} de {1} atualizações instaladas')
    )

    $installed = Get-TFToolkitResultData -Result $Result -Name "Installed"
    if ($null -eq $installed) { return $Result }

    $installed = [int]$installed
    $failed = [int](Get-TFToolkitResultData -Result $Result -Name "Failed")
    $warned = [int](Get-TFToolkitResultData -Result $Result -Name "Warned")
    $total = $installed + $failed
    $reboot = Test-TFToolkitResultFlag -Result $Result -Name "RebootRequired"
    $interrupted = ([string](Get-TFToolkitResultData -Result $Result -Name "Interrupted")).Trim().TrimEnd(".")
    $fix = Get-TFToolkitUpdateFixStep -Texts @(@($interrupted) + @(Get-TFToolkitResultData -Result $Result -Name "Problems"))

    # Parada por um erro no meio, as contas não dizem o que houve (todas as lidas podiam estar certas): a faixa diz que a
    # instalação parou e por quê.
    if ($interrupted -and $Result.Kind -eq "Warning") {
        return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'A instalação foi interrompida') -Note "$(ConvertTo-TFToolkitHeadline -Text $interrupted)." -Next $fix.Next -NextLabel $fix.Label)
    }

    if ($Result.Kind -eq "Ok") {
        return (Set-TFToolkitResultView -Result $Result -Headline (Format-TFToolkitCount -Count $installed -One $One -Many "$Many") `
                -Note $(if ($reboot) { (Get-TFToolkitText 'Reinicie o PC para terminar a instalação.') } else { $OkNote }))
    }

    # O que deu errado, em números: o motivo de cada um fica no resumo, na linha dele.
    $parts = @()
    if ($failed -gt 0) { $parts += $(if ($failed -eq 1) { (Get-TFToolkitText '1 falhou') } else { (Get-TFToolkitText '{0} falharam' "$failed") }) }
    if ($warned -gt 0) { $parts += (Get-TFToolkitText '{0} com erros' "$warned") }
    $reason = $(if ($total -eq 1 -or ($failed + $warned) -eq 1) { (Get-TFToolkitText 'o motivo está no resumo') } else { (Get-TFToolkitText 'o motivo de {0} está no resumo' "$Each") })

    if ($Result.Kind -eq "Failed") {
        return (Set-TFToolkitResultView -Result $Result -Headline $None -Note "$($reason.Substring(0, 1).ToUpper())$($reason.Substring(1))." -Next $fix.Next -NextLabel $fix.Label)
    }

    if ($Result.Kind -eq "Warning" -and $total -gt 0) {
        return (Set-TFToolkitResultView -Result $Result -Headline ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $Partial, $installed, $total)) `
                -Note "$(Join-TFToolkitList -Items $parts); $reason." -Next $fix.Next -NextLabel $fix.Label)
    }

    return $Result
}


function Set-TFToolkitInstallErrorView {
    # A instalação que nem chegou a dar resultado (o Windows Update recusou antes, sem as contas de Set-TFToolkitInstallView):
    # o título diz que não foi possível instalar, a frase traz o motivo e, quando ele aponta um item, o botão. Devolve o
    # próprio resultado.
    param ([Parameter(Mandatory)]$Result)

    $why = ([string]$Result.Detail).Trim().TrimEnd(".")

    if ($Result.Kind -ne "Failed" -or -not $why -or $null -ne (Get-TFToolkitResultData -Result $Result -Name "Installed")) { return $Result }

    $fix = Get-TFToolkitUpdateFixStep -Texts @($why)

    return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'Não foi possível instalar') -Note ($why.Substring(0, 1).ToUpper() + $why.Substring(1) + ".") -Next $fix.Next -NextLabel $fix.Label)
}


function Set-TFToolkitUpdateSearchView {
    # A faixa de quando o Windows Update não respondeu à consulta: o título diz isso, a frase traz o motivo e, quando ele
    # aponta um item do TF-Toolkit, o botão. Devolve o próprio resultado.
    param (
        [Parameter(Mandatory)]$Result,
        [string]$Problem = ""
    )

    $text = ([string]$Problem).Trim().TrimEnd(".")
    $note = $(if ($text) { $text.Substring(0, 1).ToUpper() + $text.Substring(1) + "." } else { "" })
    $fix = Get-TFToolkitUpdateFixStep -Texts @($text)

    return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'O Windows Update não respondeu') -Note $note -Next $fix.Next -NextLabel $fix.Label)
}


function Install-TFToolkitWindowsUpdates {
    $title = (Get-TFToolkitText 'Instalar atualizações do Windows')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Instalar atualizações do Windows exige privilégios de Administrador.'))) {
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador') -Title $title)
            return
        }

        $stop = Confirm-TFToolkitUpdateConditions -Title $title -Reboot (Get-TFToolkitText 'Reiniciar antes evita que as novas atualizações falhem.') -Battery (Get-TFToolkitText 'Atualizar gasta bastante energia e não deve ser interrompido.')

        if ($null -ne $stop) {
            Exit-TFToolkitAction -Result $stop
            return
        }

        # O andamento vai para a barra de progresso: uma linha "procurando..." ficaria no resumo depois do fim.
        Write-Progress -Activity (Get-TFToolkitText 'Procurando atualizações') -Status (Get-TFToolkitText 'o Windows Update pode levar alguns minutos para responder')

        try {
            $search = Find-TFToolkitWindowsUpdates
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Procurando atualizações') -Completed
        }

        if ($null -eq $search.Updates) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível consultar o Windows Update: {0}.' "$($search.Problem)")
            Write-TFToolkitWindowsUpdateSearchHelp -Problem $search.Problem
            Exit-TFToolkitAction -Result (Set-TFToolkitUpdateSearchView -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível consultar o Windows Update: {0}' "$($search.Problem)") -Title $title) -Problem $search.Problem)
            return
        }

        $updates = @($search.Updates)

        # A versão nova do Windows é opcional e não entra na lista: num Windows sem suporte, "em dia" seria falso.
        $support = Get-TFToolkitUpdateSupportStatus

        if ($updates.Count -eq 0) {
            if (Test-TFToolkitWindowsSupportEnded -Status $support) {
                [void](Write-TFToolkitUpdateSupportNote -Status $support -NothingPending)
                $ended = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'nada pendente, mas este Windows não recebe mais atualizações de segurança') -Title $title
                Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result $ended -Headline (Get-TFToolkitText 'Este Windows não recebe mais atualizações') `
                        -Note (Get-TFToolkitText 'Não há nada pendente, mas o suporte deste Windows terminou.') -Next "diagnostics.windows-support" -NextLabel (Get-TFToolkitText 'Ver o suporte do Windows'))
                return
            }

            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O Windows está em dia: não há atualizações pendentes.')
            [void](Write-TFToolkitUpdateSupportNote -Status $support)
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Drivers ficam em Atualizações > Atualizar drivers.')
            Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'o Windows está em dia') -Title $title) -Headline (Get-TFToolkitText 'O Windows está em dia') -Note (Get-TFToolkitText 'Não há atualizações pendentes.'))
            return
        }

        [void](Write-TFToolkitUpdateSupportNote -Status $support)

        # As opcionais (BrowseOnly: prévias e drivers opcionais) só aparecem quando o Windows Update não conhece o critério
        # que as deixa de fora; o Windows não as instala sozinho, então elas vêm desmarcadas e com o aviso. Uma versão nova
        # do Windows (Upgrade) também vem desmarcada, mesmo quando o Windows Update a oferece como comum: mudar de versão é
        # uma decisão à parte das atualizações do mês (o Otimizar nem a instala); quem quer, marca.
        $options = @(
            foreach ($update in $updates) {
                $optional = [bool](Get-TFToolkitJsonValue -Object $update -Name "BrowseOnly" -Default $false)
                $upgrade = [bool](Get-TFToolkitJsonValue -Object $update -Name "Upgrade" -Default $false)
                $parts = @()
                if ($upgrade) { $parts += (Get-TFToolkitText 'versão nova do Windows') } elseif ($optional) { $parts += (Get-TFToolkitText 'opcional') }
                if ([bool](Get-TFToolkitJsonValue -Object $update -Name "Driver" -Default $false)) { $purpose = Get-TFToolkitDriverPurposeText -Update $update; $parts += $(if ($purpose) { (Get-TFToolkitText 'driver de {0}' "$purpose") } else { (Get-TFToolkitText 'driver') }) }
                $parts += Get-TFToolkitUpdateSizeText -Update $update
                @{ Key = $update.Id; Label = (Get-TFToolkitUpdateOptionLabel -Update $update); Description = ($parts -join " · "); Selected = (-not $optional -and -not $upgrade) }
            }
        )

        if (@($updates | Where-Object { [bool](Get-TFToolkitJsonValue -Object $_ -Name "BrowseOnly" -Default $false) -and -not [bool](Get-TFToolkitJsonValue -Object $_ -Name "Upgrade" -Default $false) }).Count -gt 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'As opcionais (prévias e drivers opcionais) vêm desmarcadas.')
        }

        if (@($updates | Where-Object { [bool](Get-TFToolkitJsonValue -Object $_ -Name "Upgrade" -Default $false) }).Count -gt 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'A versão nova do Windows vem desmarcada: marque-a só se quiser mudar de versão agora.')
        }

        # Na janela, Confirmar só fica disponível com algo marcado: voltar sem escolha é o Cancelar.
        $picked = Read-TFToolkitMultiSelect -Message (Get-TFToolkitText 'Quais atualizações instalar?') -Options $options

        if ($null -eq $picked -or @($picked).Count -eq 0) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $chosen = @($updates | Where-Object { @($picked) -contains $_.Id })
        $download = [int64]0

        foreach ($pending in @($chosen | Where-Object { -not $_.Downloaded })) {
            $download += [int64]$pending.Size
        }

        $countText = Format-TFToolkitCount -Count $chosen.Count -One (Get-TFToolkitText 'atualização') -Many (Get-TFToolkitText 'atualizações')
        $needsDownload = @($chosen | Where-Object { -not $_.Downloaded }).Count -gt 0

        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Atualizações escolhidas') -Value $chosen.Count
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'A baixar') -Value $(if (-not $needsDownload) { (Get-TFToolkitText 'nada (já estão baixadas)') } elseif ($download -gt 0) { (Get-TFToolkitText 'até {0}' "$(Format-TFToolkitBytes -Bytes $download)") } else { (Get-TFToolkitText 'tamanho não informado') })
        Write-TFToolkitFirmwareWarning -Updates $chosen
        if ($needsDownload) { Write-TFToolkitMeteredWarning -Bytes $download }
        # Parado no meio, o Windows pode continuar instalando por conta própria.
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Não desligue o PC durante a instalação.')
        Write-Host ""

        $question = $(if ($needsDownload) { (Get-TFToolkitText 'Baixar e instalar {0}?' "${countText}") } else { (Get-TFToolkitText 'Instalar {0}?' "${countText}") })
        $verb = $(if ($needsDownload) { (Get-TFToolkitText 'Baixar e instalar') } else { (Get-TFToolkitText 'Instalar') })

        if (-not (Confirm-TFToolkitAction -Message $question -DefaultKey "S" -YesLabel $verb -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        $keepAwake = Set-TFToolkitKeepAwake -Enabled $true

        try {
            $run = Invoke-TFToolkitUpdateInstall -Ids @($chosen | ForEach-Object { $_.Id })
        }
        finally {
            if ($keepAwake) {
                [void](Set-TFToolkitKeepAwake -Enabled $false)
            }
        }

        Write-Host ""

        $final = Get-TFToolkitUpdateRunResult -Run $run -Chosen $chosen -Title $title
        [void](Set-TFToolkitInstallView -Result $final -One (Get-TFToolkitText 'atualização instalada') -Many (Get-TFToolkitText 'atualizações instaladas') `
                -None $(if ($chosen.Count -eq 1) { (Get-TFToolkitText 'A atualização não foi instalada') } else { (Get-TFToolkitText 'Nenhuma atualização instalada') }))

        [void](Set-TFToolkitInstallErrorView -Result $final)

        if (Test-TFToolkitResultFlag -Result $final -Name "RebootRequired") {
            Request-TFToolkitInstallRestart -What (Get-TFToolkitText 'as atualizações') -Later (Get-TFToolkitText 'As atualizações terminam de instalar quando você reiniciar o PC.')
        }
    }
    catch {
        $problem = Get-TFToolkitWindowsUpdateProblem -Message $_.Exception.Message -HResult $_.Exception.HResult
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível instalar as atualizações: {0}.' "$problem")
        $final = New-TFToolkitResult -Kind Failed -Detail $problem -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


function Get-TFToolkitAllUpdatesCriteria {
    # A busca do Otimizar: tudo o que não está instalado nem escondido, inclusive as opcionais (BrowseOnly: prévias e
    # drivers opcionais), que a busca padrão deixa de fora: o Otimizar não as instala, mas diz quais ficaram de fora.
    return "IsInstalled=0 and IsHidden=0"
}


function Install-TFToolkitPendingUpdates {
    <#
    A etapa do Windows Update do Otimizar: procura e instala, sem perguntar, as atualizações que o Windows Update instalaria
    sozinho (as de segurança, as do mês e os drivers que ele traz por conta própria). Ficam de fora uma versão nova do
    Windows (troca o Windows inteiro e leva horas) e as opcionais: os drivers opcionais (a Microsoft só os indica para
    resolver um problema específico; num PC que funciona, um deles pode trazer um driver pior que o do fabricante), um
    firmware opcional (como a BIOS: só com o Windows pedindo) e as prévias (as atualizações antes da hora, que o Otimizar
    desliga; o que elas trazem chega na atualização normal do mês seguinte). Os drivers opcionais continuam em
    Atualizações > Atualizar drivers, desmarcados. O reinício fica para o fim do Otimizar (Data.RebootRequired).
    Sem ninguém olhando, a etapa segue as escolhas que a pessoa fez no Windows: com as atualizações pausadas nas
    Configurações, ela nem procura (o Windows não baixa nem instala nada até o fim da pausa); numa conexão limitada (plano
    de dados), instala só o que já foi baixado, como o Windows, a menos que "Baixar atualizações em conexões limitadas"
    esteja ligado.
    #>
    param (
        [switch]$Embedded,
        [switch]$PassThru
    )

    $title = (Get-TFToolkitText 'Atualizar o Windows')

    Enter-TFToolkitAction -Title $title -Embedded:$Embedded

    $final = $null
    $pause = Get-TFToolkitWindowsUpdatePause

    if ($null -ne $pause) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitUpdatePauseText -Pause $pause)
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Para retomar, use Atualizações > Windows Update.')
        $final = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitUpdatePauseText -Pause $pause -Detail) -Title $title

        if ($PassThru) { $final }
        Exit-TFToolkitAction -Embedded:$Embedded -Result $final
        return
    }

    try {
        Write-Progress -Activity (Get-TFToolkitText 'Procurando atualizações') -Status (Get-TFToolkitText 'o Windows Update pode levar alguns minutos para responder')

        try {
            # Sem ninguém esperando (a parte automática do Otimizar), a busca tem mais tempo: a primeira num PC que passou
            # meses sem atualizar pode levar mais de 5 minutos. O Parar continua funcionando durante a espera.
            $search = Find-TFToolkitWindowsUpdates -Criteria (Get-TFToolkitAllUpdatesCriteria) -TimeoutSeconds $(if ($Embedded) { 1200 } else { 300 })
        }
        finally {
            Write-Progress -Activity (Get-TFToolkitText 'Procurando atualizações') -Completed
        }

        if ($null -eq $search.Updates) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível consultar o Windows Update: {0}.' "$($search.Problem)")
            Write-TFToolkitWindowsUpdateSearchHelp -Problem $search.Problem
            $final = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível consultar o Windows Update: {0}' "$($search.Problem)") -Title $title
        }
        else {
            $updates = @($search.Updates)
            $upgrades = @($updates | Where-Object { [bool](Get-TFToolkitJsonValue -Object $_ -Name "Upgrade" -Default $false) })
            $optional = @($updates | Where-Object { -not [bool](Get-TFToolkitJsonValue -Object $_ -Name "Upgrade" -Default $false) -and [bool](Get-TFToolkitJsonValue -Object $_ -Name "BrowseOnly" -Default $false) })
            $firmware = @($optional | Where-Object { Test-TFToolkitFirmwareUpdate -Update $_ })
            $drivers = @($optional | Where-Object { [bool](Get-TFToolkitJsonValue -Object $_ -Name "Driver" -Default $false) -and -not (Test-TFToolkitFirmwareUpdate -Update $_) })
            $previews = @($optional | Where-Object { -not [bool](Get-TFToolkitJsonValue -Object $_ -Name "Driver" -Default $false) -and -not (Test-TFToolkitFirmwareUpdate -Update $_) })
            $left = @(@($upgrades) + @($optional) | ForEach-Object { [string]$_.Id })
            $chosen = @($updates | Where-Object { $left -notcontains [string]$_.Id })

            # O que fica de fora, numa linha só (o porquê de cada um está no comentário da função).
            $leftNames = @(
                @($upgrades | ForEach-Object { (Get-TFToolkitText '{0} (versão nova do Windows)' "$($_.Title)") })
                @($firmware | ForEach-Object { (Get-TFToolkitText '{0} (firmware opcional)' "$($_.Title)") })
                @($drivers | ForEach-Object { (Get-TFToolkitText '{0} (driver opcional)' "$(Get-TFToolkitUpdateOptionLabel -Update $_)") })
                @($previews | ForEach-Object { (Get-TFToolkitText '{0} (prévia)' "$(Get-TFToolkitUpdateOptionLabel -Update $_)") })
            )

            if ($leftNames.Count -gt 0) {
                Write-TFToolkitStatus -Type Info -Message $(if ($leftNames.Count -eq 1) { Get-TFToolkitText 'Ficou de fora: {0}.' "$(Join-TFToolkitList -Items $leftNames)" } else { Get-TFToolkitText 'Ficaram de fora: {0}.' "$(Join-TFToolkitList -Items $leftNames)" })
            }

            if ($drivers.Count -gt 0) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Os drivers opcionais servem para um problema específico; se precisar de um, use Atualizações > Atualizar drivers.')
            }

            # Numa conexão limitada, o Windows Update baixa só as atualizações prioritárias, a menos que a pessoa permita
            # baixar nela; o Otimizar não sabe quais são prioritárias e instala só o que já foi baixado.
            $waiting = @()

            if ($chosen.Count -gt 0 -and (Test-TFToolkitMeteredConnection) -and -not (Test-TFToolkitMeteredUpdateDownload)) {
                $waiting = @($chosen | Where-Object { -not $_.Downloaded })
                $chosen = @($chosen | Where-Object { $_.Downloaded })
            }

            if ($waiting.Count -gt 0) {
                Write-TFToolkitStatus -Type Info -Message $(if ($waiting.Count -eq 1) { (Get-TFToolkitText 'A conexão é limitada (plano de dados): 1 atualização ficou para baixar numa conexão sem limite.') } else { (Get-TFToolkitText 'A conexão é limitada (plano de dados): {0} atualizações ficaram para baixar numa conexão sem limite.' "$($waiting.Count)") })
            }

            $support = Get-TFToolkitUpdateSupportStatus

            if ($chosen.Count -eq 0 -and $waiting.Count -gt 0) {
                [void](Write-TFToolkitUpdateSupportNote -Status $support)
                $final = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'conexão limitada: as atualizações ficam para uma conexão sem limite') -Title $title
            }
            elseif ($chosen.Count -eq 0) {
                if (Test-TFToolkitWindowsSupportEnded -Status $support) {
                    [void](Write-TFToolkitUpdateSupportNote -Status $support -NothingPending)
                    $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'nada pendente, mas este Windows não recebe mais atualizações de segurança') -Title $title
                }
                else {
                    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O Windows está em dia: não há atualizações pendentes.')
                    [void](Write-TFToolkitUpdateSupportNote -Status $support)
                    $final = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'o Windows está em dia') -Title $title
                }
            }
            else {
                [void](Write-TFToolkitUpdateSupportNote -Status $support)

                $download = [int64]0
                foreach ($pending in @($chosen | Where-Object { -not $_.Downloaded })) { $download += [int64]$pending.Size }

                $countText = Format-TFToolkitCount -Count $chosen.Count -One (Get-TFToolkitText 'atualização') -Many (Get-TFToolkitText 'atualizações')

                # Os nomes aparecem uma vez só, no fim, entre as instaladas.
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'A instalar') -Value $countText

                Write-TFToolkitFirmwareWarning -Updates $chosen
                if (@($chosen | Where-Object { -not $_.Downloaded }).Count -gt 0) { Write-TFToolkitMeteredWarning -Bytes $download }
                Write-Host ""

                $run = Invoke-TFToolkitUpdateInstall -Ids @($chosen | ForEach-Object { $_.Id }) -Criteria (Get-TFToolkitAllUpdatesCriteria)

                Write-Host ""
                $final = Get-TFToolkitUpdateRunResult -Run $run -Chosen $chosen -Title $title -SectionTitle (Get-TFToolkitText 'Atualizações instaladas')
            }
        }
    }
    catch {
        $problem = Get-TFToolkitWindowsUpdateProblem -Message $_.Exception.Message -HResult $_.Exception.HResult
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível instalar as atualizações: {0}.' "$problem")
        $final = New-TFToolkitResult -Kind Failed -Detail $problem -Title $title
    }

    if ($PassThru) { $final }
    Exit-TFToolkitAction -Embedded:$Embedded -Result $final
}


# ---------------------------------------------------------------------------
# Corrigir o Windows Update
# ---------------------------------------------------------------------------

function Get-TFToolkitWindowsUpdateServices {
    <#
    Os serviços de que o Windows Update depende, com o tipo de inicialização padrão do Windows. Stop: os que o reparo
    para e liga de novo (na ordem de parar); o orquestrador de atualizações só volta ao padrão se estiver desativado.
    Label vai depois de "o serviço" e de "Serviço" nas frases e no resumo: é o nome sem a palavra "Serviço".
    #>
    return @(
        [PSCustomObject]@{ Name = "wuauserv"; Label = (Get-TFToolkitText 'Windows Update'); Default = "Manual"; Stop = $true },
        [PSCustomObject]@{ Name = "bits"; Label = (Get-TFToolkitText 'Transferência Inteligente de Plano de Fundo (BITS)'); Default = "Manual"; Stop = $true },
        [PSCustomObject]@{ Name = "cryptsvc"; Label = (Get-TFToolkitText 'Criptografia (CryptSvc)'); Default = "Automatic"; Stop = $true },
        [PSCustomObject]@{ Name = "UsoSvc"; Label = (Get-TFToolkitText 'Orquestrador de atualizações (UsoSvc)'); Default = "Automatic"; Stop = $false }
    )
}


function Get-TFToolkitWindowsUpdateCacheFolders {
    <#
    As pastas que a Microsoft manda pôr de lado para o Windows Update refazer o cache (página de erros comuns do Windows
    Update): os downloads, o banco de dados e o catálogo de assinaturas. Keep: a cópia fica guardada (.bak); os downloads
    são só cache, e a cópia é apagada para não ficar ocupando o disco.
    #>
    $windows = [string]$env:SystemRoot
    if ([string]::IsNullOrWhiteSpace($windows)) { $windows = [string]$env:windir }
    if ([string]::IsNullOrWhiteSpace($windows)) { $windows = "C:\Windows" }

    return @(
        [PSCustomObject]@{ Name = "Download"; Label = (Get-TFToolkitText 'Downloads do Windows Update'); Path = (Join-Path $windows "SoftwareDistribution\Download"); Keep = $false },
        [PSCustomObject]@{ Name = "DataStore"; Label = (Get-TFToolkitText 'Banco de dados do Windows Update'); Path = (Join-Path $windows "SoftwareDistribution\DataStore"); Keep = $true },
        [PSCustomObject]@{ Name = "catroot2"; Label = (Get-TFToolkitText 'Catálogo de assinaturas do Windows'); Path = (Join-Path $windows "System32\catroot2"); Keep = $true }
    )
}


function Test-TFToolkitWindowsUpdateBusy {
    <#
    Se o Windows Update está instalando alguma coisa agora (IUpdateInstaller.IsBusy). Parar os serviços no meio de uma
    instalação a interromperia. A pergunta vai ao serviço, que pode estar travado (é por isso que a pessoa veio): sem
    resposta em 15 segundos, ou sem leitura, $false.
    #>
    try {
        $run = Invoke-TFToolkitInBackground -ScriptBlock { [bool](New-Object -ComObject "Microsoft.Update.Installer" -ErrorAction Stop).IsBusy } -TimeoutSeconds 15
        return ($run.Completed -and @($run.Output | Where-Object { $_ -eq $true }).Count -gt 0)
    }
    catch {
        return $false
    }
}


function Get-TFToolkitServiceState {
    <#
    Situação, tipo de inicialização e dependentes ligados de um serviço. Missing: o serviço não existe (um script de
    "limpeza" pode tê-lo removido); $null quando o Windows não respondeu.
    #>
    param ([Parameter(Mandatory)][string]$Name)

    try {
        $service = Get-Service -Name $Name -ErrorAction Stop

        return [PSCustomObject]@{
            Name       = $Name
            Missing    = $false
            Status     = [string]$service.Status
            StartType  = [string]$service.StartType
            Dependents = @($service.DependentServices | Where-Object { [string]$_.Status -eq "Running" } | ForEach-Object { [string]$_.Name })
        }
    }
    catch {
        if ($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound) {
            return [PSCustomObject]@{ Name = $Name; Missing = $true; Status = ""; StartType = ""; Dependents = @() }
        }

        return $null
    }
}


function Stop-TFToolkitServices {
    <#
    Para os serviços (e os que dependem deles) todos de uma vez e espera até TimeoutSeconds: a espera é a do mais lento,
    e não a soma. Devolve os que não pararam (vazio quando todos pararam). Um serviço "parando" ou "iniciando" recusa o
    pedido de parar: a espera continua e o pedido é repetido, em vez de virar erro; um serviço preso não segura a tela
    para sempre.
    #>
    param (
        [Parameter(Mandatory)][string[]]$Name,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $pending = @($Name)

    while ($true) {
        $running = @()

        foreach ($one in $pending) {
            $status = [string](Get-Service -Name $one -ErrorAction Stop).Status

            if ($status -eq "Stopped") { continue }

            $running += $one

            if ($status -in @("Running", "Paused")) {
                try { Stop-Service -Name $one -Force -NoWait -ErrorAction Stop } catch { Write-Verbose "Parar ${one}: $($_.Exception.Message)" }
            }
        }

        $pending = $running

        if ($pending.Count -eq 0 -or (Get-Date) -ge $deadline) { return @($pending) }

        Start-Sleep -Milliseconds 500
    }
}


function Stop-TFToolkitService {
    # Para um serviço (Stop-TFToolkitServices). $true quando parou.
    param (
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutSeconds = 30
    )

    return (@(Stop-TFToolkitServices -Name @($Name) -TimeoutSeconds $TimeoutSeconds).Count -eq 0)
}


function Start-TFToolkitService {
    <#
    Liga o serviço e espera até TimeoutSeconds que ele fique "Em execução"; um já ligado fica como está. Erro quando o
    Windows recusa, quando o serviço cai logo depois de ligar ou quando o prazo acaba. O Start-Service esperava sem fim por
    um serviço preso em "Iniciando" (o Spooler de Impressão fica assim com um driver de impressora com defeito), e a tela
    parava em "ligando o Spooler de Impressão" até alguém clicar em Parar. Um serviço ainda "Parando" (o pedido de parar
    passou do prazo de quem o parou) recusa o pedido de ligar: o pedido espera ele parar, dentro do mesmo prazo, em vez de
    deixá-lo desligado.
    #>
    param (
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutSeconds = 30
    )

    $service = Get-Service -Name $Name -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $askedAt = $null

    while ($true) {
        $status = [string]$service.Status

        if ($status -eq "Running") { return }

        if ($null -eq $askedAt -and $status -in @("Stopped", "Paused")) {
            if ($status -eq "Stopped") { $service.Start() } else { $service.Continue() }
            $askedAt = Get-Date
        }
        elseif ($null -ne $askedAt -and $status -eq "Stopped" -and (Get-Date) -ge $askedAt.AddSeconds(3)) {
            # Parado de novo passados uns segundos: o serviço caiu ao ligar, e esperar o prazo inteiro não muda isso.
            throw (Get-TFToolkitText 'parou logo depois de ligar')
        }

        if ((Get-Date) -ge $deadline) {
            throw $(if ($status -eq "StopPending") { (Get-TFToolkitText 'continua parando depois de {0} segundos' "$TimeoutSeconds") } else { (Get-TFToolkitText 'continua ligando depois de {0} segundos' "$TimeoutSeconds") })
        }

        Start-Sleep -Milliseconds 250
        $service.Refresh()
    }
}


function Set-TFToolkitServiceStartType {
    param (
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("Manual", "Automatic")][string]$StartType
    )

    Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop
}


function Move-TFToolkitUpdateCacheFolder {
    <#
    Põe uma pasta do cache de lado (Nome.bak), apagando antes a cópia de uma vez anterior. Devolve um TFToolkit.Result:
    Ok (Data.Backup = o caminho da cópia), Skipped (a pasta não existe; ou, com Data.Linked, é atalho para outro lugar)
    ou Failed (em uso, sem permissão). Uma pasta que é atalho (junção, de um programa que mudou o cache de disco) fica
    como está: apagar por ela apagaria o que está do outro lado.
    #>
    param ([Parameter(Mandatory)]$Folder)

    $path = [string]$Folder.Path

    if (-not (Test-Path -LiteralPath $path)) { return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'a pasta não existia')) }

    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop

        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'a pasta aponta para outro lugar e ficou como está') -Data @{ Linked = $true })
        }

        $backupName = "$($Folder.Name).bak"
        $backup = Join-Path (Split-Path -Parent $path) $backupName

        # A cópia de uma vez anterior sai; se ela não sair (em uso, ou é atalho), a nova ganha a data no nome.
        if (Test-Path -LiteralPath $backup) {
            [void](Remove-TFToolkitUpdateCacheBackup -Path $backup)

            if (Test-Path -LiteralPath $backup) {
                $backupName = "$($Folder.Name).bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                $backup = Join-Path (Split-Path -Parent $path) $backupName
            }
        }

        Rename-Item -LiteralPath $path -NewName $backupName -ErrorAction Stop
    }
    catch {
        $reason = $(if ($_.Exception -is [System.IO.IOException]) { (Get-TFToolkitText 'está em uso') } elseif ($_.Exception -is [System.UnauthorizedAccessException]) { (Get-TFToolkitText 'o Windows não deixou mexer') } else { $_.Exception.Message.TrimEnd(".") })
        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText '{0}; ficou como estava' "$reason"))
    }

    return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'guardado como {0}' "$backupName") -Data @{ Backup = $backup })
}


function Remove-TFToolkitUpdateCacheBackup {
    <#
    Apaga uma cópia posta de lado. Directory.Delete não entra em atalhos (junções) que estejam dentro dela, ao contrário
    de Remove-Item -Recurse no Windows PowerShell 5.1, que apagaria o que está do outro lado. Uma cópia que é ela mesma
    um atalho não é apagada. $true quando apagou.
    #>
    param ([Parameter(Mandatory)][string]$Path)

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }

        [System.IO.Directory]::Delete($item.FullName, $true)
        return $true
    }
    catch {
        Write-Verbose "Cópia $Path ficou: $($_.Exception.Message)"
        return $false
    }
}


function Get-TFToolkitServiceNamesText {
    # "o serviço Windows Update" ou "os serviços Windows Update e BITS", com o verbo que vem depois concordando.
    param (
        [Parameter(Mandatory)][string[]]$Labels,
        [string]$One = "",
        [string]$Many = ""
    )

    $list = Join-TFToolkitList -Items $Labels

    if ($Labels.Count -eq 1) { return ((Get-TFToolkitText 'o serviço {0} {1}' "$list" "$One")).TrimEnd() }

    return ((Get-TFToolkitText 'os serviços {0} {1}' "$list" "$Many")).TrimEnd()
}


function Repair-TFToolkitWindowsUpdate {
    <#
    O reparo do Windows Update que a Microsoft indica quando as atualizações falham ou travam: para os serviços, põe de
    lado o cache (Get-TFToolkitWindowsUpdateCacheFolders) e liga os serviços de novo. Um serviço desativado (por um
    "otimizador" ou bloqueador) volta antes para o tipo de inicialização padrão do Windows; se não voltar, nada mais é
    feito, porque o cache refeito não adiantaria. Políticas não são mudadas: a tela só diz quando há uma. Os serviços
    voltam a ligar mesmo se algo falhar no meio (finally), e os downloads postos de lado só são apagados depois disso.
    #>
    $title = (Get-TFToolkitText 'Corrigir o Windows Update')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Corrigir o Windows Update exige privilégios de Administrador.'))) {
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador') -Title $title)
            return
        }

        Write-Progress -Activity $title -Status (Get-TFToolkitText 'lendo os serviços do Windows Update')

        try {
            $services = @(
                foreach ($service in Get-TFToolkitWindowsUpdateServices) {
                    [PSCustomObject]@{ Name = $service.Name; Label = $service.Label; Default = $service.Default; Stop = $service.Stop; State = (Get-TFToolkitServiceState -Name $service.Name) }
                }
            )
            $medic = Get-TFToolkitServiceState -Name "WaaSMedicSvc"
            $pending = Test-TFToolkitPendingReboot
            $busy = Test-TFToolkitWindowsUpdateBusy
        }
        finally {
            Write-Progress -Activity $title -Completed
        }

        # Parar os serviços no meio interromperia a instalação.
        $busyText = (Get-TFToolkitText 'O Windows Update está instalando atualizações agora: espere terminar.')
        $busyHint = (Get-TFToolkitText 'O andamento fica em Atualizações > Windows Update; se o problema continuar, volte aqui.')
        $busyResult = (Get-TFToolkitText 'o Windows Update está instalando atualizações agora; espere terminar')

        # A faixa de quando o Windows Update está instalando: o botão abre o andamento dele.
        $busyView = {
            Set-TFToolkitResultView -Result (New-TFToolkitResult -Kind Skipped -Detail $busyResult -Title $title) -Headline (Get-TFToolkitText 'O Windows Update está instalando agora') `
                -Note (Get-TFToolkitText 'Espere terminar; se o problema continuar, volte aqui.') -Next "updates.windows" -NextLabel (Get-TFToolkitText 'Ver o andamento')
        }

        if ($busy) {
            Write-TFToolkitStatus -Type Warning -Message $busyText
            Write-TFToolkitStatus -Type Info -Message $busyHint
            Exit-TFToolkitAction -Result (& $busyView)
            return
        }

        # Um serviço que não existe mais (removido por um script de "limpeza") não volta com este reparo.
        $missing = @($services | Where-Object { [bool](Get-TFToolkitJsonValue -Object $_.State -Name "Missing" -Default $false) })
        $unread = @($services | Where-Object { $null -eq $_.State })

        if ($missing.Count -gt 0) {
            $names = Get-TFToolkitServiceNamesText -Labels @($missing | ForEach-Object { $_.Label }) -One (Get-TFToolkitText 'não existe') -Many (Get-TFToolkitText 'não existem')
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText '{0}{1} neste Windows, e este reparo não o recria.' "$($names.Substring(0, 1).ToUpper())" "$($names.Substring(1))")
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Reparo > Recuperação pode reinstalar o Windows mantendo os seus arquivos.')
            $gone = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText '{0} neste Windows' "$names") -Title $title
            Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result $gone -Headline $(if ($missing.Count -eq 1) { (Get-TFToolkitText 'Falta um serviço do Windows Update') } else { (Get-TFToolkitText 'Faltam serviços do Windows Update') }) `
                    -Note (Get-TFToolkitText 'A Recuperação pode reinstalar o Windows mantendo os seus arquivos.') -Next "repair.recovery" -NextLabel (Get-TFToolkitText 'Abrir a Recuperação'))
            return
        }

        if ($unread.Count -gt 0) {
            $names = Get-TFToolkitServiceNamesText -Labels @($unread | ForEach-Object { $_.Label })
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'O Windows não respondeu sobre {0}.' "$names")
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Isso costuma ser dano nos arquivos do Windows: use Reparo > Reparar o Windows (DISM + SFC).')
            $silent = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o Windows não respondeu sobre {0}' "$names") -Title $title
            Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result $silent -Headline (Get-TFToolkitText 'Os serviços do Windows Update não responderam') `
                    -Note (Get-TFToolkitText 'Isso costuma ser dano nos arquivos do Windows.') -Next "repair.dism-sfc" -NextLabel (Get-TFToolkitText 'Reparar o Windows'))
            return
        }

        # O reparo desliga os serviços, põe de lado o cache (os downloads, o banco de dados e o catálogo de assinaturas) e
        # liga os serviços de novo, como a Microsoft indica. O que a pessoa precisa saber antes: o histórico some.
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Refaz o cache do Windows Update: as atualizações instaladas ficam, mas o histórico delas recomeça vazio.')

        $disabled = @($services | Where-Object { $_.State.StartType -eq "Disabled" })

        foreach ($service in $disabled) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O serviço {0} está desativado: ele volta para o padrão do Windows ({1}).' "$($service.Label)" "$(if ($service.Default -eq 'Manual') { (Get-TFToolkitText 'manual') } else { (Get-TFToolkitText 'automático') })")
        }

        if ([string](Get-TFToolkitJsonValue -Object $medic -Name "StartType" -Default "") -eq "Disabled") {
            # O Medic conserta o Windows Update sozinho; o Windows o protege, e o TF-Toolkit não mexe nele.
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O serviço Windows Update Medic (WaaSMedicSvc) está desativado: desfaça pelo programa que o desativou.')
        }

        if (Write-TFToolkitWindowsUpdatePolicyNote) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O reparo não muda políticas.')
        }

        Write-Host ""

        if ($pending) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Há um reinício pendente: reinicie antes, muitas vezes isso já resolve.')

            $answer = Read-TFToolkitPendingRebootChoice -Question (Get-TFToolkitText 'Reiniciar antes de corrigir?') -Then (Get-TFToolkitText 'Se o problema continuar, volte aqui') `
                -Reason (Get-TFToolkitText 'Reinicie agora e, se o problema continuar, abra Atualizações > Corrigir o Windows Update de novo.') `
                -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit (reinício pendente antes de corrigir o Windows Update).') `
                -DeclinedMessage (Get-TFToolkitText 'Reinicialização não iniciada. Reinicie o PC e, se o problema continuar, volte aqui.')

            if ($answer -eq "Restarting") {
                Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'o PC está reiniciando') -Title $title)
                return
            }

            if ($answer -ne "Continue") {
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
                Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
                return
            }
        }
        elseif (-not (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Corrigir o Windows Update agora?') -DefaultKey "S" -YesLabel (Get-TFToolkitText 'Corrigir') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Operação cancelada.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'cancelado pelo usuário') -Title $title)
            return
        }

        # A pergunta pode ter ficado aberta enquanto o Windows começava a instalar sozinho.
        if (Test-TFToolkitWindowsUpdateBusy) {
            Write-TFToolkitStatus -Type Warning -Message $busyText
            Write-TFToolkitStatus -Type Info -Message $busyHint
            Exit-TFToolkitAction -Result (& $busyView)
            return
        }

        $rows = @()
        $restored = @()
        $stillDisabled = @()

        # 1. Os serviços desativados voltam ao padrão. Se algum não voltar, o Windows Update continua sem funcionar, e
        # refazer o cache (que esvazia o histórico das Configurações) não adiantaria: para aqui.
        foreach ($service in $disabled) {
            try {
                Set-TFToolkitServiceStartType -Name $service.Name -StartType $service.Default
                $restored += $service.Label
                $row = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'voltou para {0}' "$(if ($service.Default -eq 'Manual') { (Get-TFToolkitText 'manual') } else { (Get-TFToolkitText 'automático') })")
            }
            catch {
                $stillDisabled += $service.Label
                $row = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'continua desativado: {0}' "$($_.Exception.Message.TrimEnd('.'))")
            }

            $row.Etapa = (Get-TFToolkitText 'Serviço {0}' "$($service.Label)")
            $rows += $row
        }

        if ($restored.Count -gt 0) {
            [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Corrigir o Windows Update') -Text (Get-TFToolkitText '{0} ao padrão do Windows' "$(Get-TFToolkitServiceNamesText -Labels $restored -One (Get-TFToolkitText 'voltou') -Many (Get-TFToolkitText 'voltaram'))"))
        }

        if ($stillDisabled.Count -gt 0) {
            $names = Get-TFToolkitServiceNamesText -Labels $stillDisabled -One (Get-TFToolkitText 'continua desativado') -Many (Get-TFToolkitText 'continuam desativados')
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')
            Write-TFToolkitResultTable -Results $rows
            Write-TFToolkitStatus -Type Warning -Message $(if ($stillDisabled.Count -eq 1) { (Get-TFToolkitText '{0}{1}, e sem ele o Windows Update não funciona; um bloqueador de atualizações pode estar travando isso.' "$($names.Substring(0, 1).ToUpper())" "$($names.Substring(1))") } else { (Get-TFToolkitText '{0}{1}, e sem eles o Windows Update não funciona; um bloqueador de atualizações pode estar travando isso.' "$($names.Substring(0, 1).ToUpper())" "$($names.Substring(1))") })
            $blocked = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0}; o cache não foi mexido' "$names") -Title $title
            Exit-TFToolkitAction -Result (Set-TFToolkitResultView -Result $blocked -Headline $(if ($stillDisabled.Count -eq 1) { (Get-TFToolkitText 'Um serviço do Windows Update continua desativado') } else { (Get-TFToolkitText 'Serviços do Windows Update continuam desativados') }) `
                    -Note (Get-TFToolkitText 'Um bloqueador de atualizações pode estar travando isso. O cache não foi mexido.'))
            return
        }

        # 2. Para os serviços e põe o cache de lado; 3. liga tudo de novo (finally); 4. apaga os downloads postos de lado.
        $stopping = @($services | Where-Object { $_.Stop })
        $restart = New-Object System.Collections.ArrayList
        $moved = @()
        $stopProblem = ""

        try {
            Write-Progress -Activity $title -Status (Get-TFToolkitText 'desligando os serviços do Windows Update')

            # Quem depende de um serviço para junto com ele (Stop-Service -Force): esses voltam a ligar no fim.
            foreach ($service in $stopping) {
                foreach ($dependent in @($service.State.Dependents)) { if (-not $restart.Contains($dependent)) { [void]$restart.Add($dependent) } }
            }

            # Os três param juntos: a espera é a do mais lento, e não a soma.
            $stoppingNames = @($stopping | ForEach-Object { [string]$_.Name })
            $notStopped = @(Stop-TFToolkitServices -Name $stoppingNames)

            if ($notStopped.Count -gt 0) {
                $stuck = @($stopping | Where-Object { $_.Name -eq $notStopped[0] }) | Select-Object -First 1
                $stopProblem = (Get-TFToolkitText 'o serviço {0} não parou em 30 segundos' "$($stuck.Label)")
            }

            if (-not $stopProblem) {
                foreach ($folder in @(Get-TFToolkitWindowsUpdateCacheFolders)) {
                    Write-Progress -Activity $title -Status (Get-TFToolkitText 'pondo de lado: {0}' "$($folder.Label)")

                    # Outro serviço (o orquestrador de atualizações) pode religar o Windows Update a qualquer momento.
                    try { [void](Stop-TFToolkitServices -Name $stoppingNames -TimeoutSeconds 10) } catch { Write-Verbose "Parar os serviços: $($_.Exception.Message)" }

                    $row = Move-TFToolkitUpdateCacheFolder -Folder $folder
                    $row.Etapa = $folder.Label
                    $rows += $row

                    if ($row.Kind -eq "Ok") { $moved += [PSCustomObject]@{ Folder = $folder; Row = $row } }
                }
            }
        }
        catch {
            $stopProblem = (Get-TFToolkitText 'não foi possível desligar os serviços: {0}' "$($_.Exception.Message.TrimEnd('.'))")
        }
        finally {
            Write-Progress -Activity $title -Status (Get-TFToolkitText 'ligando os serviços de novo')
            $notStarted = @()
            $toStart = @(@("cryptsvc", "bits", "wuauserv") + @($restart))
            if (@($services | Where-Object { $_.Name -eq "UsoSvc" -and $restored -contains $_.Label }).Count -gt 0) { $toStart += "UsoSvc" }

            foreach ($name in $toStart) {
                try { Start-TFToolkitService -Name $name } catch { $notStarted += $name }
            }

            Write-Progress -Activity $title -Completed
        }

        # Os downloads são só cache: a cópia sai depois que os serviços já estão ligados de novo.
        foreach ($entry in @($moved | Where-Object { -not $_.Folder.Keep })) {
            $backup = [string](Get-TFToolkitResultData -Result $entry.Row -Name "Backup")
            $text = $(if (Remove-TFToolkitUpdateCacheBackup -Path $backup) { (Get-TFToolkitText 'apagados; o Windows baixa de novo o que precisar') } else { (Get-TFToolkitText 'postos de lado em {0}' "$(Split-Path -Leaf $backup)") })
            $entry.Row.Detail = $text
            $entry.Row.Status = "OK ($text)"
        }

        $movedNames = @($moved | ForEach-Object { [string]$_.Folder.Name })

        if ($movedNames.Count -gt 0) {
            [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Corrigir o Windows Update') -Text (Get-TFToolkitText 'cache refeito ({0})' "$(Join-TFToolkitList -Items $movedNames)"))
        }

        $labels = @{}
        foreach ($service in $services) { $labels[$service.Name] = $service.Label }
        $notStartedText = Join-TFToolkitList -Items @($notStarted | ForEach-Object { if ($labels.ContainsKey($_)) { $labels[$_] } else { $_ } })

        if ($rows.Count -gt 0) {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')
            Write-TFToolkitResultTable -Results $rows
        }

        $folderFailed = @($rows | Where-Object { $_.Kind -eq "Failed" -and $_.Etapa -notlike (Get-TFToolkitText 'Serviço {0}' '*') })
        $linked = @($rows | Where-Object { Test-TFToolkitResultFlag -Result $_ -Name "Linked" })

        if ($stopProblem) {
            $touched = $(if ($movedNames.Count -gt 0) { (Get-TFToolkitText 'Só parte do cache foi refeita ({0}).' "$(Join-TFToolkitList -Items $movedNames)") } else { (Get-TFToolkitText 'Nada do cache foi mexido.') })
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível terminar a correção: {0}. {1}' "$stopProblem" "$touched")
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Reinicie o PC e tente de novo.')
            $final = New-TFToolkitResult -Kind Failed -Detail "$stopProblem; $($touched.TrimEnd('.').ToLower())" -Title $title
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'O Windows Update não foi corrigido') -Note "$touched $(Get-TFToolkitText 'Reinicie o PC e tente de novo.')")
        }
        elseif ($notStarted.Count -gt 0) {
            Write-TFToolkitStatus -Type Warning -Message $(if ($notStarted.Count -eq 1) { (Get-TFToolkitText 'Não foi possível ligar de novo: {0}. Reinicie o PC para o Windows ligá-lo.' "$notStartedText") } else { (Get-TFToolkitText 'Não foi possível ligar de novo: {0}. Reinicie o PC para o Windows ligá-los.' "$notStartedText") })
            $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'cache refeito, mas não ligou de novo: {0}; reinicie o PC' "$notStartedText") -Title $title -Data @{ RebootRequired = $true }
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'Reinicie para terminar a correção') -Note (Get-TFToolkitText 'O cache foi refeito; os serviços voltam a ligar quando o PC reiniciar.'))
            Request-TFToolkitRestartOffer -Reason (Get-TFToolkitText 'Reiniciar liga de novo os serviços do Windows Update.') `
                -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit para ligar os serviços do Windows Update.') `
                -DeclinedMessage (Get-TFToolkitText 'Reinicialização não iniciada. Os serviços voltam a ligar quando você reiniciar o PC.')
        }
        elseif ($folderFailed.Count -gt 0) {
            $names = Join-TFToolkitList -Items @($folderFailed | ForEach-Object { $_.Etapa })
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Reinicie o PC e rode a correção de novo.')
            $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'ficou como estava: {0}' "$names") -Title $title
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'O cache foi refeito só em parte') -Note (Get-TFToolkitText 'Reinicie o PC e rode a correção de novo.'))
        }
        elseif ($linked.Count -gt 0) {
            $names = Join-TFToolkitList -Items @($linked | ForEach-Object { $_.Etapa })
            # Quase sempre um programa que mudou o cache de disco; o TF-Toolkit não mexe do outro lado.
            $linkedText = $(if ($linked.Count -eq 1) { (Get-TFToolkitText '{0} aponta para outra pasta: desfaça pelo programa que mudou isso.' "$names") } else { (Get-TFToolkitText '{0} apontam para outra pasta: desfaça pelo programa que mudou isso.' "$names") })
            Write-TFToolkitStatus -Type Info -Message $linkedText
            $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'cache refeito em parte; {0} aponta para outro lugar e ficou como está' "$names") -Title $title
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'O cache foi refeito só em parte') -Note $linkedText)
        }
        else {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Agora use Atualizações > Instalar atualizações do Windows; a primeira busca demora mais.')
            $final = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'cache do Windows Update refeito e serviços ligados de novo') -Title $title
            [void](Set-TFToolkitResultView -Result $final -Headline (Get-TFToolkitText 'Cache do Windows Update refeito') -Note (Get-TFToolkitText 'Os serviços estão ligados de novo. A primeira busca por atualizações demora mais.') `
                    -Next "updates.install" -NextLabel (Get-TFToolkitText 'Procurar atualizações'))
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível corrigir o Windows Update: {0}.' "$($_.Exception.Message.TrimEnd('.'))")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message.TrimEnd(".") -Title $title
    }

    Exit-TFToolkitAction -Result $final
}

Export-ModuleMember -Function *
