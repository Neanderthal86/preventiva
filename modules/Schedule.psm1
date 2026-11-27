# Manutenção agendada: uma tarefa do Agendador de Tarefas do Windows que, uma vez por mês, faz só o que é seguro
# sem ninguém olhando (limpa os temporários do usuário com mais de 7 dias e salva um relatório). É opcional, começa
# desligada e some com um clique.
#
# Decisões de segurança:
#   - A tarefa roda SEM privilégios de Administrador, só com o usuário logado. Uma tarefa elevada que executa um
#     script numa pasta que o próprio usuário pode alterar (Downloads, Área de Trabalho) seria um atalho para qualquer
#     programa comum ganhar privilégios; sem elevação esse risco não existe, e não há pedido de UAC que travaria
#     uma tarefa em segundo plano.
#   - Não esvazia a Lixeira, não repara, não atualiza e não muda ajustes: isso exige a sua decisão na hora.

$script:TFToolkitSchedulePath = "\TF-Toolkit\"
$script:TFToolkitScheduleName = "Manutencao-Mensal"
$script:TFToolkitScheduleDays = @(1, 15, 28)
$script:TFToolkitScheduleHour = 12

# Na execução agendada, só sai dos temporários o que está lá há mais tempo que isto (a Limpeza de Disco do Windows também
# usa 7 dias).
$script:TFToolkitScheduleTempDays = 7

# Resultados do Agendador que não são falha: 0 (terminou bem), 0x41300 (pronta), 0x41301 (em execução), 0x41302
# (desativada) e 0x41303 (ainda não executou).
$script:TFToolkitScheduleOkResults = @(0, 267008, 267009, 267010, 267011)


# ---------------------------------------------------------------------------
# A tarefa
# ---------------------------------------------------------------------------

function Get-TFToolkitScheduleUser {
    # Quem vai executar a tarefa: o usuário que está usando o PC. Se o TF-Toolkit foi elevado com outra conta, é o
    # usuário logado que importa (é a Área de Trabalho e os temporários dele que a limpeza deve tratar).
    $interactive = Get-TFToolkitInteractiveUser

    if (-not [string]::IsNullOrWhiteSpace($interactive)) {
        return $interactive
    }

    try {
        return [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    catch {
        return ""
    }
}


function Get-TFToolkitHiddenPowerShellCommand {
    <#
    O programa e os argumentos para uma tarefa rodar o PowerShell do TF-Toolkit.cmd sem janela, com os Arguments dados (que
    já devem trazer o -WindowStyle Hidden). No Windows 11 (build 22000 em diante), o Terminal do Windows pode ser o
    programa padrão de console, e ele ignora o -WindowStyle Hidden: a janela apareceria, e fechá-la pararia o que a
    tarefa faz. Lá o PowerShell é aberto pelo console clássico sem janela (conhost.exe --headless), quando ele existe. O
    conhost não devolve o código de saída do PowerShell: quem precisa dele o lê de outro jeito.
    #>
    param (
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [int]$Build = (Get-TFToolkitWindowsBuild),
        [AllowEmptyString()][string]$SystemRoot = $env:SystemRoot
    )

    $powershell = Get-TFToolkitPowerShellPath
    $conhost = $(if (-not [string]::IsNullOrWhiteSpace($SystemRoot)) { Join-Path (Join-Path $SystemRoot "System32") "conhost.exe" } else { "" })

    if ($Build -ge 22000 -and $conhost -and (Test-Path -LiteralPath $conhost -PathType Leaf)) {
        return [PSCustomObject]@{
            Executable       = $conhost
            Arguments        = "--headless $(ConvertTo-TFToolkitCommandLineArgument -Value $powershell) $Arguments"
            WorkingDirectory = $WorkingDirectory
        }
    }

    return [PSCustomObject]@{
        Executable       = $powershell
        Arguments        = $Arguments
        WorkingDirectory = $WorkingDirectory
    }
}


function Get-TFToolkitScheduleCommand {
    <#
    O programa e os argumentos que a tarefa executa: o mesmo PowerShell do TF-Toolkit.cmd, com o script do terminal, sem
    janela (Get-TFToolkitHiddenPowerShellCommand).
    #>
    param (
        [string]$Root = (Get-TFToolkitAppRoot),
        [int]$Build = (Get-TFToolkitWindowsBuild),
        [AllowEmptyString()][string]$SystemRoot = $env:SystemRoot
    )

    $script = Join-Path $Root "TF-Toolkit.Console.ps1"

    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        throw (Get-TFToolkitText 'O arquivo TF-Toolkit.Console.ps1 não foi encontrado em ''{0}''. Extraia a pasta inteira do TF-Toolkit antes de agendar.' "$Root")
    }

    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $(ConvertTo-TFToolkitCommandLineArgument -Value $script) -Action ScheduledMaintenance"

    return (Get-TFToolkitHiddenPowerShellCommand -Arguments $arguments -WorkingDirectory $Root -Build $Build -SystemRoot $SystemRoot)
}


function New-TFToolkitScheduleTaskXml {
    <#
    O XML da tarefa (esquema do Agendador de Tarefas): todo mês no dia escolhido, às 12h, com o usuário logado e sem
    elevação. Se o PC estiver desligado na hora, roda assim que for possível; não começa na bateria e para se passar
    a usar a bateria. A primeira execução é a partir de amanhã, para não disparar na hora em que é criada.
    #>
    param (
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$UserId,

        [ValidateRange(1, 28)]
        [int]$DayOfMonth = 1,

        [datetime]$Start = ((Get-Date).Date.AddDays(1).AddHours($script:TFToolkitScheduleHour))
    )

    $escape = { param ($text) [System.Security.SecurityElement]::Escape($text) }
    $startBoundary = $Start.ToString("yyyy-MM-dd'T'HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    $months = (@("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December") | ForEach-Object { "<$_ />" }) -join ""
    $description = (Get-TFToolkitText 'Manutenção mensal do TF-Toolkit: limpa os temporários do usuário com mais de 7 dias e salva um relatório. Não esvazia a Lixeira nem altera o sistema. Para remover, use o TF-Toolkit (Manutenção > Manutenção agendada) ou apague esta tarefa.')

    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>TF-Toolkit</Author>
    <Description>$(& $escape $description)</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByMonth>
        <DaysOfMonth><Day>$DayOfMonth</Day></DaysOfMonth>
        <Months>$months</Months>
      </ScheduleByMonth>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$(& $escape $UserId)</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$(& $escape $Executable)</Command>
      <Arguments>$(& $escape $Arguments)</Arguments>
      <WorkingDirectory>$(& $escape $WorkingDirectory)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
}


function ConvertTo-TFToolkitScheduleResultCode {
    # O código de resultado como número sem sinal (o Agendador às vezes o entrega negativo: -196608 é 0xFFFD0000).
    param ($Code)

    $value = [int64]$Code
    if ($value -lt 0) { $value += 4294967296 }

    return $value
}


function ConvertTo-TFToolkitScheduleResultText {
    # O código de resultado da última execução, em português.
    param ($Code)

    if ($null -eq $Code) {
        return ""
    }

    $value = ConvertTo-TFToolkitScheduleResultCode -Code $Code

    switch ($value) {
        0          { return (Get-TFToolkitText 'terminou bem') }
        267009     { return (Get-TFToolkitText 'em execução agora') }
        267011     { return (Get-TFToolkitText 'ainda não executou') }
        267014     { return (Get-TFToolkitText 'foi interrompida') }
        # O código que o PowerShell devolve quando o script passado em -File não existe (o TF-Toolkit mudou de pasta ou foi
        # apagado).
        4294770688 { return (Get-TFToolkitText 'não encontrou o TF-Toolkit na pasta de antes') }
        default    { return (Get-TFToolkitText 'terminou com erro (código 0x{0})' "$($value.ToString('X'))") }
    }
}


function Get-TFToolkitScheduleTaskScript {
    # O script que a tarefa executa: o caminho depois de -File nos argumentos dela, ou "" quando não há como saber.
    param ([string]$Arguments)

    if ($Arguments -match '(?i)(^|\s)-File\s+"([^"]+)"') { return $Matches[2] }
    if ($Arguments -match '(?i)(^|\s)-File\s+([^\s"]+)') { return $Matches[2] }

    return ""
}


function Test-TFToolkitSchedulePathSame {
    # Os dois caminhos levam ao mesmo arquivo? Compara o caminho completo, sem diferenciar maiúsculas (como o Windows).
    param (
        [string]$Path,
        [string]$Other
    )

    try {
        $first = [System.IO.Path]::GetFullPath($Path)
        $second = [System.IO.Path]::GetFullPath($Other)
    }
    catch {
        return $false
    }

    return [string]::Equals($first, $second, [StringComparison]::OrdinalIgnoreCase)
}


function Get-TFToolkitScheduleStatus {
    <#
    O estado da tarefa no Agendador de Tarefas. Installed é falso quando ela não existe (ou quando o Agendador não pôde
    ser consultado, ou não respondeu no prazo: aí QueryFailed é verdadeiro, e a tela não diz "não agendada" sem saber).
    Day é o dia do mês; LastRun e NextRun são $null quando não houve/não há execução marcada. Cada consulta ao Agendador
    passa por Invoke-TFToolkitCimCommand, com prazo: um Agendador travado não prende a tela, a leitura do Início, o
    instalador nem a desinstalação.
    A tarefa guarda o caminho do script; extrair uma versão nova em outra pasta e apagar a antiga a deixa falhando todo
    mês, ainda "ativa" no Agendador. Por isso:
      ScriptPath     - o script que a tarefa executa ("" quando não deu para ler);
      ScriptMissing  - esse script não existe mais (a tarefa vai falhar até ser recriada);
      Stale          - o script é de outra pasta, não do TF-Toolkit que está aberto;
      LastRunFailed  - o Agendador registrou que a última execução terminou mal (LastResult fora dos códigos normais);
      RecordFailed   - o registro que o próprio TF-Toolkit gravou na última execução diz que nada funcionou. No Windows 11 a
                       tarefa abre o PowerShell pelo conhost, que não devolve o código de saída dele: sem o registro, o
                       Agendador diria "terminou bem" de uma execução que falhou;
      NeedsAttention - instalada e com algum dos problemas acima; Problem diz qual, numa frase curta.
    #>
    $status = [PSCustomObject]@{
        Installed      = $false
        Enabled        = $false
        Day            = $null
        LastRun        = $null
        LastResult     = $null
        NextRun        = $null
        ScriptPath     = ""
        ScriptMissing  = $false
        Stale          = $false
        LastRunFailed  = $false
        RecordFailed   = $false
        NeedsAttention = $false
        Problem        = ""
        Owner          = ""
        OtherUser      = $false
        QueryFailed    = $false
    }

    $task = $null
    $names = @{ TaskPath = $script:TFToolkitSchedulePath; TaskName = $script:TFToolkitScheduleName }

    try {
        $task = @(Invoke-TFToolkitCimCommand -Name "Get-ScheduledTask" -Parameters $names) | Select-Object -First 1
    }
    catch {
        # Tarefa que não existe é "não agendada"; o Agendador que não respondeu (serviço parado, acesso negado, RPC
        # indisponível, o prazo esgotado) é não saber, e a tela diz isso em vez de "não agendada".
        $category = [string]$_.CategoryInfo.Category
        $status.QueryFailed = ($_.Exception -is [System.TimeoutException] -or $category -in @("PermissionDenied", "ResourceUnavailable", "ConnectionError", "OpenError") -or [string]$_.Exception.Message -match '(?i)0x80070005|0x800706BA|0x80070422|access is denied|acesso negado')
        return $status
    }

    if ($null -eq $task) {
        return $status
    }

    $status.Installed = $true
    $status.Enabled = ([string]$task.State -ne "Disabled")

    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.LoadXml([string](@(Invoke-TFToolkitCimCommand -Name "Export-ScheduledTask" -Parameters $names) | Select-Object -First 1))
        $day = $xml.SelectSingleNode("//*[local-name()='DaysOfMonth']/*[local-name()='Day']")

        if ($null -ne $day) { $status.Day = [int]$day.InnerText }

        $arguments = $xml.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='Arguments']")

        if ($null -ne $arguments) { $status.ScriptPath = Get-TFToolkitScheduleTaskScript -Arguments $arguments.InnerText }

        # O TF-Toolkit usa uma tarefa só por PC (um nome fixo no Agendador), com a conta de quem agendou: a de outra conta
        # limpa os temporários dela, e criar ou remover aqui mexeria no agendamento dela.
        $owner = $xml.SelectSingleNode("//*[local-name()='Principal']/*[local-name()='UserId']")

        if ($null -ne $owner -and -not [string]::IsNullOrWhiteSpace($owner.InnerText)) {
            $status.Owner = ConvertTo-TFToolkitScheduleAccountName -Account $owner.InnerText
            $status.OtherUser = -not (Test-TFToolkitScheduleSameAccount -Account $status.Owner -Other (Get-TFToolkitScheduleUser))
        }
    }
    catch {
        # O dia e o script são informação extra; a tarefa continua instalada.
    }

    if ($status.ScriptPath) {
        $status.ScriptMissing = -not (Test-Path -LiteralPath $status.ScriptPath -PathType Leaf)

        try {
            $root = [string](Get-TFToolkitAppRoot)

            if ($root) {
                $status.Stale = -not (Test-TFToolkitSchedulePathSame -Path $status.ScriptPath -Other (Join-Path $root "TF-Toolkit.Console.ps1"))
            }
        }
        catch {
            # Sem saber onde o TF-Toolkit está, não dá para comparar; o script que falta continua sendo conferido acima.
        }
    }

    try {
        $info = @(Invoke-TFToolkitCimCommand -Name "Get-ScheduledTaskInfo" -Parameters $names) | Select-Object -First 1

        # O Agendador usa datas antigas (1999/2000) para "nunca".
        if ($info.LastRunTime -is [datetime] -and $info.LastRunTime.Year -ge 2001) { $status.LastRun = $info.LastRunTime }
        if ($info.NextRunTime -is [datetime] -and $info.NextRunTime.Year -ge 2001) { $status.NextRun = $info.NextRunTime }

        $status.LastResult = $info.LastTaskResult
    }
    catch {
        # Sem os detalhes da execução, mostra só que está agendada.
    }

    if ($null -ne $status.LastRun -and $null -ne $status.LastResult) {
        try {
            $status.LastRunFailed = ((ConvertTo-TFToolkitScheduleResultCode -Code $status.LastResult) -notin $script:TFToolkitScheduleOkResults)
        }
        catch {
            $status.LastRunFailed = $false
        }
    }

    # O registro do TF-Toolkit vale para a execução que o Agendador diz ter sido a última (a tarefa começa um pouco antes do
    # script: a margem de um minuto é a da tela). Um registro mais velho que ela é de outra execução; o de uma tarefa de
    # outra conta fica na pasta dessa conta.
    if (-not $status.OtherUser -and $null -ne $status.LastRun) {
        $record = Get-TFToolkitScheduledRun

        if ($null -ne $record -and [string]$record.Kind -eq "Failed" -and $status.LastRun -le $record.RunAt.AddMinutes(1)) {
            $status.RecordFailed = $true
        }
    }

    if ($status.ScriptMissing) {
        $status.Problem = (Get-TFToolkitText 'a tarefa usa um TF-Toolkit que não existe mais; recrie o agendamento')
    }
    elseif ($status.Stale) {
        $status.Problem = (Get-TFToolkitText 'a tarefa usa o TF-Toolkit de outra pasta; recrie o agendamento')
    }
    elseif ($status.LastRunFailed) {
        $status.Problem = (Get-TFToolkitText 'a última execução {0}' "$(ConvertTo-TFToolkitScheduleResultText -Code $status.LastResult)")
    }
    elseif ($status.RecordFailed) {
        $status.Problem = (Get-TFToolkitText 'a última execução não funcionou')
    }

    $status.NeedsAttention = [bool]$status.Problem

    return $status
}


function ConvertTo-TFToolkitScheduleAccountName {
    # O nome de uma conta ("PC\ana") a partir do que a tarefa guarda, que pode ser o nome ou o SID (S-1-5-21-...).
    param ([AllowEmptyString()][string]$Account)

    $text = $Account.Trim()

    if ($text -match '^S-1-[0-9-]+$') {
        try { return (New-Object System.Security.Principal.SecurityIdentifier $text).Translate([System.Security.Principal.NTAccount]).Value }
        catch { return $text }
    }

    return $text
}


function Test-TFToolkitScheduleSameAccount {
    # Se dois nomes de conta são a mesma conta ("PC\Ana" e "ana" também são; sem saber a conta de um dos lados, sim).
    param ([AllowEmptyString()][string]$Account, [AllowEmptyString()][string]$Other)

    if ([string]::IsNullOrWhiteSpace($Account) -or [string]::IsNullOrWhiteSpace($Other)) { return $true }

    $a = $Account.Trim().ToLowerInvariant()
    $b = $Other.Trim().ToLowerInvariant()

    if ($a -eq $b) { return $true }
    if ($a.Contains('\') -and $b.Contains('\')) { return $false }

    return (($a -split '\\')[-1] -eq ($b -split '\\')[-1])
}


function Get-TFToolkitPathWriteRules {
    # As permissões de um arquivo ou pasta, do jeito que a conferência de quem pode alterá-lo precisa: o dono (Owner e
    # OwnerSid) e cada regra (Identity, Sid, Rights, Allow e InheritOnly, a regra que só vale para o que for criado dentro).
    param ([Parameter(Mandatory)][string]$Path)

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $toSid = {
        param ($identity)
        try { return $identity.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { return [string]$identity }
    }

    $rules = @(
        foreach ($rule in @($acl.Access)) {
            [PSCustomObject]@{
                Identity    = [string]$rule.IdentityReference
                Sid         = (& $toSid $rule.IdentityReference)
                Rights      = [int64]$rule.FileSystemRights
                Allow       = ([string]$rule.AccessControlType -eq "Allow")
                InheritOnly = (([int]$rule.PropagationFlags -band 2) -ne 0)
            }
        }
    )

    $ownerSid = ""
    try { $ownerSid = (New-Object System.Security.Principal.NTAccount ([string]$acl.Owner)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { $ownerSid = [string]$acl.Owner }

    return [PSCustomObject]@{ Owner = [string]$acl.Owner; OwnerSid = $ownerSid; Rules = $rules }
}


function Get-TFToolkitScheduleUntrustedWriters {
    <#
    Quem, além da conta do agendamento, dos Administradores, do SYSTEM e do TrustedInstaller, pode alterar o que a tarefa
    executa: a pasta do TF-Toolkit, o script do terminal, os módulos e as traduções (os textos que ela escreve). A tarefa
    roda esses arquivos todo mês com a conta da pessoa; numa pasta que outras contas alteram (C:\TF-Toolkit criada direto
    no disco, por exemplo, onde os "Usuários autenticados" podem modificar), qualquer conta do PC passaria a rodar código
    como ela. Devolve os nomes (vazio = só contas de confiança); permissões que não puderam ser lidas também entram,
    como um aviso.
    #>
    param (
        [string]$Root = (Get-TFToolkitAppRoot),
        [string]$User = (Get-TFToolkitScheduleUser)
    )

    # SYSTEM, Administradores e TrustedInstaller.
    $trusted = @("S-1-5-18", "S-1-5-32-544", "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464")

    try { $trusted += (New-Object System.Security.Principal.NTAccount $User).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }

    # Gravar, acrescentar, apagar o que está dentro, apagar, trocar as permissões, tomar posse, e os genéricos de gravação.
    $writeMask = [int64](0x2 -bor 0x4 -bor 0x40 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000)

    $modules = Join-Path $Root "modules"
    $lang = Join-Path $Root "lang"
    $paths = @($Root, (Join-Path $Root "TF-Toolkit.Console.ps1"), $modules, $lang) + @(Get-ChildItem -LiteralPath $modules, $lang -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $writers = @()

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }

        # Sem conseguir ler as permissões, não dá para dizer que só contas de confiança alteram o arquivo (nas pastas
        # comuns, a conta e os Administradores sempre leem).
        try { $acl = Get-TFToolkitPathWriteRules -Path $path }
        catch {
            $writers += (Get-TFToolkitText 'não foi possível conferir as permissões de {0}' "$path")
            continue
        }

        if ($acl.OwnerSid -and $trusted -notcontains $acl.OwnerSid -and -not (Test-TFToolkitScheduleSameAccount -Account $acl.Owner -Other $User)) { $writers += $acl.Owner }

        foreach ($rule in @($acl.Rules)) {
            if (-not $rule.Allow -or $rule.InheritOnly) { continue }
            if (([int64]$rule.Rights -band $writeMask) -eq 0) { continue }
            if ($trusted -contains [string]$rule.Sid) { continue }
            if (Test-TFToolkitScheduleSameAccount -Account ([string]$rule.Identity) -Other $User) { continue }

            $writers += [string]$rule.Identity
        }
    }

    return @($writers | Where-Object { $_ } | Select-Object -Unique)
}


function Register-TFToolkitScheduledMaintenance {
    # Cria (ou troca) a tarefa mensal. Devolve um TFToolkit.Result.
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, 28)]
        [int]$Day,

        # A pasta do TF-Toolkit que a tarefa roda (o instalador passa a instalada).
        [string]$Root = (Get-TFToolkitAppRoot)
    )

    if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Criar a tarefa agendada exige privilégios de Administrador.'))) {
        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador'))
    }

    try {
        $user = Get-TFToolkitScheduleUser

        if ([string]::IsNullOrWhiteSpace($user)) {
            throw (Get-TFToolkitText 'Não foi possível descobrir qual usuário está usando o PC.')
        }

        $command = Get-TFToolkitScheduleCommand -Root $Root
        $writers = @(Get-TFToolkitScheduleUntrustedWriters -Root $command.WorkingDirectory -User $user)

        if ($writers.Count -gt 0) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'A pasta do TF-Toolkit ({0}) pode ser alterada por outras contas deste PC ({1}). A tarefa rodaria o que estiver nela todo mês com a conta {2}.' "$($command.WorkingDirectory)" "$(Join-TFToolkitList -Items $writers)" "$user")
            # Mover a pasta de agora não basta: ela leva junto as permissões de onde está.
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Extraia o TF-Toolkit de novo em Arquivos de Programas (C:\Program Files) e agende de lá.')
            return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'a pasta do TF-Toolkit pode ser alterada por outras contas'))
        }

        $xml = New-TFToolkitScheduleTaskXml -Executable $command.Executable -Arguments $command.Arguments -WorkingDirectory $command.WorkingDirectory -UserId $user -DayOfMonth $Day

        [void](Invoke-TFToolkitCimCommand -Name "Register-ScheduledTask" -Parameters @{ Xml = $xml; TaskPath = $script:TFToolkitSchedulePath; TaskName = $script:TFToolkitScheduleName; Force = $true })
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível criar a tarefa agendada: {0}' "$($_.Exception.Message)")
        return (New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message)
    }

    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Manutenção agendada para todo dia {0}, às {1}h, com a conta {2}.' "$Day" "$($script:TFToolkitScheduleHour)" "$user")

    $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'agendada para todo dia {0}, às {1}h' "$Day" "$($script:TFToolkitScheduleHour)") -Data @{ Day = $Day }
    [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Manutenção agendada') -Text (Get-TFToolkitText 'todo dia {0}, às {1}h' "$Day" "$($script:TFToolkitScheduleHour)"))

    return $result
}


function Remove-TFToolkitScheduleFolder {
    # Tira do Agendador de Tarefas a pasta \TF-Toolkit\, se ela ficou vazia (sem a tarefa, ela só sobraria na lista). Uma
    # pasta com outra tarefa dentro fica; uma falha aqui não muda nada no que a pessoa pediu.
    try {
        $service = New-Object -ComObject "Schedule.Service"
        $service.Connect()
        $folder = $service.GetFolder($script:TFToolkitSchedulePath.TrimEnd('\'))

        if ($folder.GetTasks(1).Count -eq 0 -and $folder.GetFolders(0).Count -eq 0) {
            $service.GetFolder("\").DeleteFolder($script:TFToolkitSchedulePath.Trim('\'), 0)
        }
    }
    catch {
        Write-Verbose "Pasta do Agendador: $($_.Exception.Message)"
    }
}


function Unregister-TFToolkitScheduledMaintenance {
    # Apaga a tarefa. Devolve um TFToolkit.Result.
    if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'Remover a tarefa agendada exige privilégios de Administrador.'))) {
        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador'))
    }

    $task = $null
    $missing = $false
    $names = @{ TaskPath = $script:TFToolkitSchedulePath; TaskName = $script:TFToolkitScheduleName }

    try {
        $task = @(Invoke-TFToolkitCimCommand -Name "Get-ScheduledTask" -Parameters $names) | Select-Object -First 1
        $missing = ($null -eq $task)
    }
    catch {
        # Um Agendador que não respondeu no prazo também não responderia à remoção: o motivo vai direto, sem esperar de novo.
        if ($_.Exception -is [System.TimeoutException]) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível remover a tarefa agendada: {0}' "$($_.Exception.Message)")
            return (New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message)
        }

        # Só "nenhuma tarefa com esse nome" quer dizer que ela já não existe; outro erro (o serviço parado, acesso negado)
        # segue para a remoção, que diz o motivo.
        $missing = ([string]$_.Exception.Message -match 'MSFT_ScheduledTask|0x80070002|não existe|cannot find|not found|no existe|no se encuentra|no se puede encontrar')
    }

    if ($missing) {
        # Já removida (pelo Agendador de Tarefas, por exemplo): o que a pessoa queria já está feito.
        Remove-TFToolkitScheduleFolder
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'A manutenção agendada já não existia. Nada vai rodar sozinho.')
        return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'o agendamento já não existia; nada roda sozinho'))
    }

    try {
        [void](Invoke-TFToolkitCimCommand -Name "Unregister-ScheduledTask" -Parameters ($names + @{ Confirm = $false }))
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível remover a tarefa agendada: {0}' "$($_.Exception.Message)")
        return (New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message)
    }

    Remove-TFToolkitScheduleFolder
    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Manutenção agendada removida. Nada mais vai rodar sozinho.')

    $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'agendamento removido; nada mais roda sozinho')
    [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Manutenção agendada') -Text (Get-TFToolkitText 'removida; nada mais roda sozinho'))

    return $result
}


# ---------------------------------------------------------------------------
# A execução (chamada pela tarefa, sem ninguém olhando)
# ---------------------------------------------------------------------------

function Get-TFToolkitScheduledRunPath {
    return (Join-Path (Get-TFToolkitDataPath) "scheduled-maintenance.json")
}


function Get-TFToolkitScheduledRun {
    # O registro da última execução automática (quando, quanto liberou, onde está o relatório). $null se nunca rodou.
    try {
        # Um registro estragado volta da cópia anterior (.bak), como os outros arquivos de estado.
        $document = (Read-TFToolkitStateFile -Path (Get-TFToolkitScheduledRunPath)).Document

        if ($null -eq $document) {
            return $null
        }

        return [PSCustomObject]@{
            RunAt      = [datetime]::Parse([string]$document.RunAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            Kind       = [string]$document.Kind
            FreedBytes = [int64]$document.FreedBytes
            Report     = [string]$document.Report
        }
    }
    catch {
        return $null
    }
}


function Clear-TFToolkitScheduledTempFolder {
    <#
    A limpeza de uma pasta de temporários na execução agendada: só o que está lá há mais de 7 dias, como faz a Limpeza
    de Disco do Windows. Sem ninguém olhando, um arquivo recente pode ser de um instalador que espera o PC reiniciar ou
    de um programa aberto que ainda vai lê-lo. A limpeza pedida na hora (Limpeza) continua levando tudo o que não está
    em uso. As travas são as da Limpeza: pasta não localizada, recusada por segurança ou ilegível não é tocada.
    Um item conta como antigo pela última atividade dele, olhando dentro das pastas (Measure-TFToolkitFolderItems): uma
    pasta antiga com um arquivo novo dentro fica. Devolve um TFToolkit.Result com FreedBytes.
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [int]$Days = $script:TFToolkitScheduleTempDays
    )

    Write-TFToolkitSection -Title $Title

    $result = $null

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível localizar a pasta a limpar: a variável de ambiente que a indica não está definida.')
            $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'pasta não localizada')
        }
        # As duas pastas daqui vêm das variáveis TEMP: só uma pasta chamada Temp (ou Tmp) é esvaziada, como na limpeza feita
        # na hora. Sem essa trava, uma TEMP apontando para D:\Dados teria tudo o que tem mais de 7 dias apagado todo mês,
        # sem ninguém olhando.
        elseif (-not (Test-TFToolkitTempFolderSafe -Path $Path -RequireTempName)) {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Pasta recusada por segurança: {0}' "$Path")
            $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'pasta recusada por segurança')
        }
        elseif (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Pasta não encontrada: {0}' "$Path")
            $result = New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'pasta não encontrada') -Data @{ FreedBytes = [int64]0 }
        }
        else {
            $listing = Get-TFToolkitFolderListing -Path $Path

            if (-not $listing.Readable) {
                Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível ler a pasta: {0}' "$($listing.Reason)")
                $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'pasta ilegível')
            }
            else {
                $entries = @(Measure-TFToolkitFolderItems -Items $listing.Items)
                $old = @(Select-TFToolkitItemsOlderThan -Entries $entries -Cutoff (Get-Date).AddDays(-$Days))

                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Pasta') -Value $Path
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Com mais de {0} dias' "$Days") -Value (Get-TFToolkitText '{0} de {1}' "$($old.Count)" "$(Format-TFToolkitCount -Count $entries.Count -One (Get-TFToolkitText 'item') -Many (Get-TFToolkitText 'itens'))")

                if ($old.Count -eq 0) {
                    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Nada com mais de {0} dias para limpar.' "$Days")
                    $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'nada com mais de {0} dias' "$Days") -Data @{ FreedBytes = [int64]0 }
                }
                else {
                    $outcome = Clear-TFToolkitFolderContents -Path $Path -Activity $Title -Entries $old

                    # Itens em uso são esperados; mas se NADA saiu, a limpeza não aconteceu.
                    $nothingRemoved = ($outcome.Removed -eq 0 -and $outcome.Skipped -gt 0)
                    $detail = (Get-TFToolkitText 'liberou {0}' "$(Format-TFToolkitBytes -Bytes $outcome.Freed)")
                    if ($outcome.Skipped -gt 0) { $detail += (Get-TFToolkitText '; {0} em uso' "$($outcome.Skipped)") }
                    if ($nothingRemoved) { $detail = (Get-TFToolkitText 'nenhum item removido; {0} em uso' "$($outcome.Skipped)") }

                    Write-TFToolkitStatus -Type $(if ($nothingRemoved) { "Warning" } else { "Success" }) -Message (Get-TFToolkitText 'Temporários com mais de {0} dias: {1}.' "$Days" "$detail")
                    $result = New-TFToolkitResult -Kind $(if ($nothingRemoved) { "Warning" } else { "Ok" }) -Detail $detail -Data @{ FreedBytes = [int64]$outcome.Freed }
                }
            }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Falha na limpeza ({0}): {1}' "$Title" "$($_.Exception.Message)")
        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }

    $result.Etapa = $Title

    return $result
}


function Invoke-TFToolkitScheduledMaintenance {
    <#
    O que a tarefa agendada executa: limpa os temporários do usuário com mais de 7 dias (e os do Windows, se por acaso
    estiver com privilégios de Administrador) e salva o relatório. Nunca pergunta nada, nunca esvazia a Lixeira. Devolve
    um TFToolkit.Result e grava o registro da execução.
    #>
    $runAt = Get-Date
    $parts = @()

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Manutenção agendada')

    # Uma limpeza que lança uma exceção não pode levar junto o relatório e o registro da execução: vira uma parte que falhou.
    try {
        $parts += @(Clear-TFToolkitScheduledTempFolder -Title (Get-TFToolkitText 'Temporários do usuário') -Path (Get-TFToolkitUserTempPath) | Where-Object { $null -ne $_ -and $_.PSObject.TypeNames -contains "TFToolkit.Result" })
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Falha na limpeza dos temporários do usuário: {0}' "$($_.Exception.Message)")
        $parts += New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title (Get-TFToolkitText 'Temporários do usuário')
    }

    if (Test-TFToolkitAdministrator) {
        try {
            $parts += @(Clear-TFToolkitScheduledTempFolder -Title (Get-TFToolkitText 'Temporários do Windows') -Path (Get-TFToolkitWindowsTempPath) | Where-Object { $null -ne $_ -and $_.PSObject.TypeNames -contains "TFToolkit.Result" })
        }
        catch {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Falha na limpeza dos temporários do Windows: {0}' "$($_.Exception.Message)")
            $parts += New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title (Get-TFToolkitText 'Temporários do Windows')
        }
    }

    $freed = [int64]0

    foreach ($part in $parts) {
        $partFreed = Get-TFToolkitResultData -Result $part -Name "FreedBytes"
        if ($null -ne $partFreed) { $freed += [int64]$partFreed }
    }

    $reportPath = ""
    $reportFailed = $false

    try {
        $report = Export-TFToolkitReport
        $html = [string]$report.Html

        # A gravação do relatório não para num erro de disco: o arquivo é conferido aqui, para o registro e o resultado
        # não dizerem "salvo" sobre um relatório que não existe ou ficou vazio.
        $saved = $null
        if (-not [string]::IsNullOrWhiteSpace($html)) { $saved = Get-Item -LiteralPath $html -Force -ErrorAction SilentlyContinue }

        if ($null -eq $saved -or $saved.PSIsContainer -or [int64]$saved.Length -le 0) {
            throw (Get-TFToolkitText 'o arquivo do relatório não foi gravado ({0})' "$(if ($html) { $html } else { (Get-TFToolkitText 'sem caminho') })")
        }

        $reportPath = $html
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Relatório salvo em: {0}' "$reportPath")
    }
    catch {
        $reportFailed = $true
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Não foi possível salvar o relatório: {0}' "$($_.Exception.Message)")
    }

    $failed = @($parts | Where-Object { $_.Kind -eq "Failed" })

    if ($failed.Count -eq 0 -and -not $reportFailed) {
        $result = New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'liberou {0}' "$(Format-TFToolkitBytes -Bytes $freed)") -Data @{ FreedBytes = $freed; Report = $reportPath }
    }
    elseif ($failed.Count -eq $parts.Count -and $reportFailed) {
        # Nada funcionou: a tarefa termina com código de erro, e o Agendador de Tarefas mostra que falhou.
        $result = New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'nada foi feito') -Data @{ FreedBytes = $freed; Report = $reportPath }
    }
    else {
        $result = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'parte do trabalho falhou') -Data @{ FreedBytes = $freed; Report = $reportPath }
    }

    try {
        $document = [ordered]@{
            RunAt      = $runAt.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
            Kind       = $result.Kind
            FreedBytes = $freed
            Report     = $reportPath
        }

        # Gravação atômica: a tela pode estar lendo o registro enquanto a tarefa grava.
        Write-TFToolkitStateJson -Path (Get-TFToolkitScheduledRunPath) -InputObject $document
    }
    catch {
        # O registro é um complemento da tela; a limpeza e o relatório já foram feitos.
    }

    $result.Etapa = (Get-TFToolkitText 'Manutenção agendada')

    return $result
}


# ---------------------------------------------------------------------------
# A tela
# ---------------------------------------------------------------------------

function Show-TFToolkitScheduledMaintenance {
    $title = (Get-TFToolkitText 'Manutenção agendada')
    Enter-TFToolkitAction -Title $title

    # Voltar sem escolher só foi olhar: a tela termina sem faixa de resultado. Criar, trocar o dia ou remover dizem o que
    # ficou valendo. Por isso os avisos sobre a tarefa saem como avisos à vista (-Notice), e não como um desfecho.
    $final = $null

    try {
        # Mensagens de informação: na janela elas ficam visíveis no resumo enquanto a pessoa escolhe (a saída completa fica
        # recolhida durante a pergunta). O que roda todo mês, e quando, numa linha: com o PC desligado ao meio-dia, a
        # tarefa roda depois que você entrar no Windows (o Agendador espera uns 10 minutos); Lixeira, reparo, programas e
        # ajustes ficam de fora.
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Uma vez por mês, às {0}h (ou depois que você entrar no Windows, se o PC estava desligado), apaga os temporários com mais de {1} dias e salva um relatório. Nada mais muda; no notebook, só na tomada.' "$($script:TFToolkitScheduleHour)" "$($script:TFToolkitScheduleTempDays)")

        $status = Get-TFToolkitScheduleStatus
        $recreate = ($status.Installed -and ($status.ScriptMissing -or $status.Stale))
        $unknown = [bool]$status.QueryFailed

        if ($unknown) {
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Tarefa mensal') -Value (Get-TFToolkitText 'não foi possível consultar o Agendador de Tarefas') -Level Warn
        }
        elseif (-not $status.Installed) {
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Tarefa mensal') -Value (Get-TFToolkitText 'Não agendada')
        }
        else {
            $when = $(if ($null -ne $status.Day) { (Get-TFToolkitText 'todo dia {0}, às {1}h' "$($status.Day)" "$($script:TFToolkitScheduleHour)") } else { (Get-TFToolkitText 'mensal') })
            $state = $(if (-not $status.Enabled) { (Get-TFToolkitText 'Desligada no Agendador de Tarefas ({0})' "$when") } elseif ($status.ScriptMissing) { (Get-TFToolkitText 'Ativa, mas a tarefa não vai funcionar ({0})' "$when") } else { (Get-TFToolkitText 'Ativa ({0})' "$when") })
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Tarefa mensal') -Value $state -Level $(if (-not $status.Enabled -or $status.ScriptMissing) { "Warn" } else { "Normal" })

            if ($null -ne $status.NextRun) {
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Próxima execução') -Value (Format-TFToolkitDateTime -When $status.NextRun)
            }

            if ($status.OtherUser) {
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Conta') -Value $status.Owner
                # O Windows guarda um agendamento só por PC: criar um aqui substitui o da outra conta, e remover tira o dela.
                Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Este agendamento é da conta {0} e limpa os temporários dela: criar ou remover aqui mexe no dela.' "$($status.Owner)")
            }

            if ($status.ScriptMissing) {
                Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'A tarefa roda o TF-Toolkit de uma pasta que não existe mais ({0}). Até ser recriada, ela falha todo mês.' "$($status.ScriptPath)")
            }
            elseif ($status.Stale) {
                Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'A tarefa roda o TF-Toolkit de outra pasta ({0}), não deste. Se aquela pasta for apagada, a tarefa passa a falhar.' "$($status.ScriptPath)")
            }

            if ($recreate) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Para recriar a tarefa com esta pasta do TF-Toolkit, escolha o dia abaixo.')
            }
            elseif (-not $status.Enabled) {
                # Desligada no Agendador (por alguém, ou por um programa de "otimização"): escolher o dia cria a tarefa de
                # novo, já ligada.
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Para religar, escolha o dia abaixo: a tarefa é criada de novo, ligada.')
            }
            elseif ($status.ScriptPath -and -not $status.OtherUser) {
                # Uma tarefa criada antes desta conferência, de uma pasta que outras contas alteram, continua rodando o que
                # estiver nela: a tela avisa, e recriar daqui é recusado até o TF-Toolkit estar numa pasta só da pessoa.
                $writers = @(Get-TFToolkitScheduleUntrustedWriters -Root (Split-Path -Path $status.ScriptPath -Parent))

                if ($writers.Count -gt 0) {
                    Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'A pasta que a tarefa roda pode ser alterada por outras contas deste PC ({0}). Remova o agendamento, ou extraia o TF-Toolkit de novo em Arquivos de Programas (C:\Program Files) e agende de lá.' "$(Join-TFToolkitList -Items $writers)")
                }
            }
        }

        $lastRun = Get-TFToolkitScheduledRun

        # O registro do TF-Toolkit só existe quando o script chegou a rodar: uma execução que falhou antes disso (o script não
        # existe mais) só aparece no Agendador. Vale a mais nova; e o resultado do Agendador também vale quando diz que a
        # execução terminou mal. A tarefa começa um pouco antes do script: a margem de um minuto separa as duas coisas.
        $fromScheduler = $false

        if ($status.Installed -and $null -ne $status.LastRun) {
            if ($null -eq $lastRun -or $status.LastRun -gt $lastRun.RunAt.AddMinutes(1)) { $fromScheduler = $true }
            elseif ($status.LastRunFailed -and $status.LastRun -ge $lastRun.RunAt.AddMinutes(-1)) { $fromScheduler = $true }
        }

        if ($fromScheduler) {
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Última execução') -Value "$(Format-TFToolkitDateTime -When $status.LastRun), $(ConvertTo-TFToolkitScheduleResultText -Code $status.LastResult)"
        }
        elseif ($null -ne $lastRun) {
            $outcome = $(switch ($lastRun.Kind) { "Warning" { (Get-TFToolkitText '; terminou com ressalvas') } "Failed" { (Get-TFToolkitText '; não funcionou') } default { "" } })

            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Última execução') -Value (Get-TFToolkitText '{0} ({1}), liberou {2}{3}' "$(Format-TFToolkitDateTime -When $lastRun.RunAt)" "$(Format-TFToolkitRelativeTime -When $lastRun.RunAt)" "$(Format-TFToolkitBytes -Bytes $lastRun.FreedBytes)" "$outcome")

            if (-not [string]::IsNullOrWhiteSpace($lastRun.Report)) {
                Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Relatório') -Value $lastRun.Report
            }
        }
        elseif ($status.Installed) {
            Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Última execução') -Value (Get-TFToolkitText 'Ainda não executou')
        }

        Write-Host ""

        $options = @()

        foreach ($day in $script:TFToolkitScheduleDays) {
            $current = ($status.Installed -and $status.Day -eq $day)
            $label = $(if ($current) { (Get-TFToolkitText 'Dia {0} (atual)' "$day") } else { (Get-TFToolkitText 'Dia {0}' "$day") })

            # O horário e o que acontece com o PC desligado estão na linha do alto: aqui, só o que muda de um dia a outro.
            $description = ""
            if ($current) { $description = $(if ($recreate) { (Get-TFToolkitText 'recria a tarefa com esta pasta do TF-Toolkit') } else { (Get-TFToolkitText 'o dia de agora; escolher de novo recria a tarefa') }) }

            # Em destaque: o primeiro dia, quando não há tarefa; o dia atual (ou o primeiro, sem dia lido), quando a tarefa
            # precisa ser recriada. Sem resposta do Agendador, não se sabe se há tarefa: nenhum dia em destaque.
            $accent = ($day -eq $script:TFToolkitScheduleDays[0] -and -not $unknown -and (-not $status.Installed -or ($recreate -and $null -eq $status.Day))) -or ($current -and $recreate)

            $options += @{
                Key         = "D$day"
                Label       = $label
                Description = $description
                Accent      = $accent
            }
        }

        if ($status.Installed) {
            $options += @{ Key = "R"; Label = (Get-TFToolkitText 'Remover o agendamento'); Description = (Get-TFToolkitText 'a tarefa sai do Agendador de Tarefas; nada mais roda sozinho') }
        }

        $options += @{ Key = "V"; Label = (Get-TFToolkitText 'Voltar'); Exit = $true }

        $message = $(if ($status.Installed) { (Get-TFToolkitText 'Trocar o dia ou remover?') } else { (Get-TFToolkitText 'Em que dia do mês?') })
        $choice = Read-TFToolkitChoice -Message $message -Options $options -DefaultKey "V" -ShowMenu

        Write-Host ""

        # Mexer no agendamento de outra conta só com a confirmação, com Não como padrão.
        if ($choice -match '^D([0-9]+)$|^R$' -and $status.OtherUser) {
            $question = $(if ($choice -eq "R") { (Get-TFToolkitText 'Remover o agendamento da conta {0}?' "$($status.Owner)") } else { (Get-TFToolkitText 'Substituir o agendamento da conta {0} pelo seu?' "$($status.Owner)") })

            if (-not (Confirm-TFToolkitAction $question -DefaultKey N)) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O agendamento da conta {0} ficou como estava.' "$($status.Owner)")
                $choice = "V"
            }
        }

        if ($choice -match '^D([0-9]+)$') {
            $final = Register-TFToolkitScheduledMaintenance -Day ([int]$Matches[1])
        }
        elseif ($choice -eq "R") {
            $final = Unregister-TFToolkitScheduledMaintenance
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Ocorreu um erro na manutenção agendada: {0}' "$($_.Exception.Message)")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


# ---------------------------------------------------------------------------
# Rodar com a conta de quem usa o PC, sem Administrador
# ---------------------------------------------------------------------------
#
# O TF-Toolkit aberto como Administrador às vezes precisa rodar algo sem elevação: o winget recusa, de um processo elevado,
# desinstalar e atualizar o que foi instalado só para a conta da pessoa (erro 0x8A15007D). O caminho documentado pelo
# Windows para isso é uma tarefa do Agendador com a conta da pessoa, o token interativo dela (só roda com ela logada, na
# sessão dela) e os menores privilégios (RunLevel LeastPrivilege: com o UAC ligado, a versão da conta sem Administrador).
# A tarefa é de uma vez só: sem horário, roda o TF-Toolkit.Unelevated.ps1 e é apagada quando ele termina.
#
# Decisões de segurança:
#   - Nada roda elevado: a tarefa e o que ela abre têm os direitos de qualquer programa que a pessoa abre. Rodar como
#     Administrador o desinstalador gravado no registro da conta (HKCU), que qualquer programa da conta altera, seria
#     justamente o que o winget bloqueia.
#   - O TF-Toolkit elevado não grava na pasta da execução (em %LOCALAPPDATA%, que qualquer programa da conta altera): o
#     pedido vai na linha de comando da tarefa, e quem cria a pasta e grava nela é o script, sem elevação. O TF-Toolkit só
#     lê arquivos comuns de lá (nem atalhos de pasta, nem links) cuja dona é a conta da pessoa, conferida também no
#     arquivo já aberto, e apaga a pasta com o Remove-TFToolkitFolder, que não segue atalhos de pasta.
#   - O limite: um programa que já roda na conta da pessoa e troca a pasta por um atalho no meio da limpeza não é coberto
#     por inteiro, como nas outras pastas do TF-Toolkit em %LOCALAPPDATA%. A Microsoft trata o UAC como defesa em
#     profundidade, e não como fronteira de segurança, entre a conta e a versão dela como Administrador.

$script:TFToolkitLimitedTaskPrefix = "SemAdministrador-"
# Quanto o Agendador pode levar para começar o script. Uma tarefa ou pasta que sobrou de um TF-Toolkit fechado à força só
# sai depois de TFToolkitLimitedStaleHours: mais que o limite da própria tarefa (2 horas), para nunca tirar uma que ainda
# roda (de outra janela do TF-Toolkit, por exemplo).
$script:TFToolkitLimitedStartSeconds = 60
$script:TFToolkitLimitedStaleHours = 3
$script:TFToolkitLimitedPollMilliseconds = 400
# Até quanto da saída é lido; o que passar disso fica fora da tela (o código de saída continua valendo).
$script:TFToolkitLimitedOutputLimit = 4MB


function Get-TFToolkitLimitedRunState {
    <#
    Se este TF-Toolkit consegue rodar algo com a conta de quem usa o PC, sem Administrador (Invoke-TFToolkitLimited):
    - "Available": elevado, com a conta de quem usa o PC e com o UAC ligado (a conta tem a versão sem Administrador);
    - "NotElevated": já está sem Administrador, e não há o que trocar;
    - "OtherAccount": elevado com a conta de outro Administrador. O programa é dessa conta, e não de quem usa o PC, e a
      tarefa precisaria dela logada;
    - "NoLimitedToken": a conta não tem a versão sem Administrador (o UAC desligado, ou o Administrador embutido do
      Windows).
    Sem conseguir ler o tipo do token, tenta ("Available"): se a tarefa não rodar, quem chama fica sabendo por quê.
    #>
    if (-not (Test-TFToolkitAdministrator)) { return "NotElevated" }
    if (Test-TFToolkitUserContextMismatch) { return "OtherAccount" }
    if ((Get-TFToolkitTokenElevationType) -eq "Default") { return "NoLimitedToken" }

    return "Available"
}


function ConvertTo-TFToolkitLimitedRunRequest {
    # O pedido ao TF-Toolkit.Unelevated.ps1 (a pasta da execução, o programa e os argumentos), em JSON e Base64: vai inteiro
    # na linha de comando da tarefa, sem aspas para proteger.
    param (
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $json = ConvertTo-Json -InputObject ([ordered]@{ Folder = $Folder; FilePath = $FilePath; Arguments = @($Arguments) }) -Compress

    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
}


function New-TFToolkitLimitedRunTaskXml {
    <#
    O XML da tarefa de uma vez só (esquema do Agendador de Tarefas): sem horário (roda quando o TF-Toolkit pede), com a
    conta de quem usa o PC (UserId: o SID dela), o token interativo e os menores privilégios. Roda também na bateria, com
    a prioridade normal (a pessoa está esperando) e para sozinha depois de 2 horas.
    #>
    param (
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$UserId
    )

    $escape = { param ($text) [System.Security.SecurityElement]::Escape($text) }
    $description = (Get-TFToolkitText 'Tarefa de uma vez só do TF-Toolkit: roda um comando com a sua conta, sem Administrador, e é apagada quando ele termina.')

    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>TF-Toolkit</Author>
    <Description>$(& $escape $description)</Description>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$(& $escape $UserId)</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Priority>5</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$(& $escape $Executable)</Command>
      <Arguments>$(& $escape $Arguments)</Arguments>
      <WorkingDirectory>$(& $escape $WorkingDirectory)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
}


function Test-TFToolkitLimitedRunFile {
    <#
    Se um arquivo da pasta da execução pode ser lido pelo TF-Toolkit elevado: um arquivo comum (nem atalho de pasta, nem
    link), numa pasta que também não é atalho, com a conta de quem usa o PC como dona. O que o script grava sem elevação é
    dela; um arquivo de outra conta ou do sistema, posto ali por um link, não é. OwnerSid: o SID dessa conta.
    #>
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerSid
    )

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

        if ($item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }

        $parent = Get-Item -LiteralPath $item.DirectoryName -Force -ErrorAction Stop

        if (($parent.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }

        $owner = (Get-Acl -LiteralPath $Path -ErrorAction Stop).GetOwner([System.Security.Principal.SecurityIdentifier])

        return ($null -ne $owner -and [string]$owner.Value -eq $OwnerSid)
    }
    catch {
        return $false
    }
}


function Get-TFToolkitLimitedRunStreamOwner {
    <#
    A dona (o SID) do arquivo que a Stream abriu, lida no próprio arquivo aberto e não pelo caminho: um link posto no
    lugar do arquivo entre a conferência (Test-TFToolkitLimitedRunFile) e a abertura leva a um arquivo de outra dona, e
    não passa. "" quando não foi possível ler.
    #>
    param ([Parameter(Mandatory)][System.IO.FileStream]$Stream)

    try {
        # O .NET Framework (Windows PowerShell 5.1) tem o GetAccessControl na própria FileStream; o .NET novo, como extensão.
        $security = $(if ($null -ne $Stream.PSObject.Methods["GetAccessControl"]) { $Stream.GetAccessControl() } else { [System.IO.FileSystemAclExtensions]::GetAccessControl($Stream) })
        $owner = $security.GetOwner([System.Security.Principal.SecurityIdentifier])

        return $(if ($null -ne $owner) { [string]$owner.Value } else { "" })
    }
    catch {
        return ""
    }
}


function Open-TFToolkitLimitedRunFile {
    <#
    Abre para leitura um arquivo da pasta da execução que passa por Test-TFToolkitLimitedRunFile e cuja dona, conferida
    de novo no arquivo aberto, é a conta (OwnerSid). O arquivo continua podendo ser gravado e apagado pelo script. $null
    quando não existe, não passa ou não abriu.
    #>
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerSid
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    if (-not (Test-TFToolkitLimitedRunFile -Path $Path -OwnerSid $OwnerSid)) { return $null }

    $stream = $null

    try {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $stream = New-Object System.IO.FileStream ($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
    }
    catch {
        # Apagado ou trocado entre a conferência e a abertura.
        return $null
    }

    if ((Get-TFToolkitLimitedRunStreamOwner -Stream $stream) -ne $OwnerSid) {
        $stream.Dispose()
        return $null
    }

    return $stream
}


function Read-TFToolkitLimitedRunText {
    # O texto curto (o número do processo, o código de saída) de um arquivo da pasta da execução, se ele passa por
    # Open-TFToolkitLimitedRunFile; $null quando não existe, não passa ou é grande demais para ser um desses.
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerSid
    )

    $stream = Open-TFToolkitLimitedRunFile -Path $Path -OwnerSid $OwnerSid

    if ($null -eq $stream) { return $null }

    try {
        if ($stream.Length -gt 4096) { return $null }

        $reader = New-Object System.IO.StreamReader ($stream, (New-Object System.Text.UTF8Encoding $false), $true)

        return $reader.ReadToEnd().Trim()
    }
    catch {
        return $null
    }
    finally {
        $stream.Dispose()
    }
}


function Read-TFToolkitLimitedRunOutput {
    <#
    Lê o que chegou na saída da execução (output.txt) desde a última leitura e mostra as linhas inteiras na tela, como
    Invoke-TFToolkitNative (Test-TFToolkitEchoLine: as barras de progresso resumidas). State: o estado da leitura (Path,
    OwnerSid, Stream, Decoder, Pending, Read, Lines, Echo, Refused). Com -Final, mostra também a última linha sem o fim.
    O arquivo é conferido uma vez (Open-TFToolkitLimitedRunFile), ao abrir, e fica aberto até o fim.
    #>
    param (
        [Parameter(Mandatory)][hashtable]$State,
        [switch]$Final
    )

    if ($State.Refused) { return }

    if ($null -eq $State.Stream) {
        if (-not (Test-Path -LiteralPath $State.Path -PathType Leaf)) { return }

        $State.Stream = Open-TFToolkitLimitedRunFile -Path $State.Path -OwnerSid $State.OwnerSid

        # O arquivo existe e não passou: nada dele é lido.
        if ($null -eq $State.Stream) {
            $State.Refused = $true
            return
        }
    }

    $buffer = New-Object byte[] 65536

    while ([long]$State.Read -lt $script:TFToolkitLimitedOutputLimit) {
        $count = $State.Stream.Read($buffer, 0, $buffer.Length)

        if ($count -le 0) { break }

        $State.Read = [long]$State.Read + $count
        # O decodificador guarda uma letra cortada no fim de uma leitura para a próxima.
        $chars = New-Object char[] ($State.Decoder.GetCharCount($buffer, 0, $count))
        [void]$State.Decoder.GetChars($buffer, 0, $count, $chars, 0)
        [void]$State.Pending.Append($chars)
    }

    $text = $State.Pending.ToString()
    $cut = $(if ($Final) { $text.Length } else { $text.LastIndexOf("`n") })

    if ($cut -lt 0 -or $text.Length -eq 0) { return }

    [void]$State.Pending.Clear()
    if ($cut -lt $text.Length) { [void]$State.Pending.Append($text.Substring($cut + 1)) }

    # No fim, um texto que termina com a quebra de linha não tem uma linha vazia depois dela.
    $body = $text.Substring(0, $cut)
    if ($Final -and $body.EndsWith("`n")) { $body = $body.Substring(0, $body.Length - 1) }

    foreach ($line in ($body -split "`n")) {
        $line = $line.TrimEnd("`r") -replace "`0", ""
        $State.Lines.Add($line)

        if (Test-TFToolkitEchoLine -Line $line -State $State.Echo) { Write-Host $line }
    }
}


function Get-TFToolkitLimitedRunProcess {
    # O processo do script (pelo pid.txt), quando ele já começou: é o PowerShell que a tarefa abriu depois de Since. $null
    # enquanto ele não gravou o número, ou se o número não é de um PowerShell aberto depois disso.
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OwnerSid,
        [Parameter(Mandatory)][datetime]$Since
    )

    $text = Read-TFToolkitLimitedRunText -Path $Path -OwnerSid $OwnerSid
    $id = 0

    if (-not $text -or -not [int]::TryParse($text, [ref]$id) -or $id -le 0) { return $null }

    try {
        $process = Get-Process -Id $id -ErrorAction Stop

        if ($process.ProcessName -notin @("powershell", "pwsh")) { return $null }
        if ($process.StartTime -lt $Since.AddSeconds(-5)) { return $null }

        return $process
    }
    catch {
        return $null
    }
}


function Stop-TFToolkitLimitedRunProcess {
    # Encerra o script e o que ele abriu (o winget, o desinstalador): o Parar vale também para o que roda sem
    # Administrador. Pelo taskkill do Windows, que segue a árvore de processos; sem ele, ao menos o script.
    param ([Parameter(Mandatory)]$Process)

    try {
        if ($Process.HasExited) { return }

        $taskkill = $(if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) { Join-Path (Join-Path $env:SystemRoot "System32") "taskkill.exe" } else { "" })

        if ($taskkill -and (Test-Path -LiteralPath $taskkill -PathType Leaf)) {
            & $taskkill /PID ([string]$Process.Id) /T /F 2>&1 | Out-Null
        }
        else {
            Stop-Process -Id $Process.Id -Force -ErrorAction Stop
        }
    }
    catch {
        Write-Verbose "A execução sem Administrador não foi encerrada: $($_.Exception.Message)"
    }
}


function Remove-TFToolkitLimitedRunLeftovers {
    <#
    Tira o que sobrou de execuções sem Administrador interrompidas (um TF-Toolkit fechado à força no meio): as tarefas
    \TF-Toolkit\SemAdministrador-* e as pastas de %LOCALAPPDATA%\TF-Toolkit\run com mais de TFToolkitLimitedStaleHours. Com
    -All (ao desinstalar), todas. Uma pasta run que é atalho de pasta sai como atalho, sem olhar o que há do outro lado.
    Nunca dá erro.
    #>
    param ([switch]$All)

    $limit = (Get-Date).AddHours(-$script:TFToolkitLimitedStaleHours)

    try {
        foreach ($task in @(Invoke-TFToolkitCimCommand -Name "Get-ScheduledTask" -Parameters @{ TaskPath = $script:TFToolkitSchedulePath })) {
            $name = [string]$task.TaskName

            if (-not $name.StartsWith($script:TFToolkitLimitedTaskPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

            if (-not $All) {
                $stamp = [datetime]::MinValue
                $text = $name.Substring($script:TFToolkitLimitedTaskPrefix.Length).Split('-')[0]
                $parsed = [datetime]::TryParseExact($text, "yyyyMMddHHmmss", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$stamp)

                if (-not $parsed -or $stamp -gt $limit) { continue }
            }

            try {
                [void](Invoke-TFToolkitCimCommand -Name "Unregister-ScheduledTask" -Parameters @{ TaskPath = $script:TFToolkitSchedulePath; TaskName = $name; Confirm = $false })
            }
            catch {
                Write-Verbose "Tarefa que sobrou ($name): $($_.Exception.Message)"
            }
        }
    }
    catch {
        # Nenhuma tarefa na pasta \TF-Toolkit\ (o Agendador responde com erro) ou o Agendador sem resposta.
        Write-Verbose "Tarefas que sobraram: $($_.Exception.Message)"
    }

    try {
        $root = Join-Path (Get-TFToolkitDataPath) "run"
        $folder = Get-Item -LiteralPath $root -Force -ErrorAction Stop

        if (($folder.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Remove-TFToolkitFolder -Path $root -Quiet
            return
        }

        foreach ($run in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)) {
            if ($All -or $run.LastWriteTime -lt $limit) { Remove-TFToolkitFolder -Path $run.FullName -Quiet }
        }

        if ($All) { Remove-TFToolkitFolder -Path $root -Quiet }
    }
    catch {
        # Sem a pasta run (nenhuma execução até hoje), não há o que tirar.
        Write-Verbose "Pastas que sobraram: $($_.Exception.Message)"
    }
}


function Invoke-TFToolkitLimited {
    <#
    Roda um programa com a conta de quem usa o PC, sem Administrador, e espera por ele: uma tarefa de uma vez só
    (New-TFToolkitLimitedRunTaskXml) roda o TF-Toolkit.Unelevated.ps1, que roda o programa e grava a saída e o código de
    saída. A saída aparece na tela enquanto chega, como em Invoke-TFToolkitNative. Só faz sentido com
    Get-TFToolkitLimitedRunState = "Available".
    Devolve Ran ($true quando o programa rodou até o fim), ExitCode, Lines e, quando ele não rodou, Reason (o motivo, numa
    frase). O Parar (ou a janela fechada no meio) encerra o script e o que ele abriu; a tarefa e a pasta sempre saem.
    #>
    param (
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $outcome = [PSCustomObject]@{ Ran = $false; ExitCode = $null; Lines = @(); Reason = "" }
    $root = [string](Get-TFToolkitAppRoot)
    $runner = Join-Path $root "TF-Toolkit.Unelevated.ps1"

    if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
        $outcome.Reason = (Get-TFToolkitText 'falta o arquivo TF-Toolkit.Unelevated.ps1 na pasta do TF-Toolkit')
        return $outcome
    }

    # A tarefa roda com esta conta (pelo SID), e só o que é dela é lido da pasta da execução.
    $sid = Get-TFToolkitCurrentUserSid

    if (-not $sid) {
        $outcome.Reason = (Get-TFToolkitText 'não foi possível ler a conta que abriu o TF-Toolkit')
        return $outcome
    }

    Remove-TFToolkitLimitedRunLeftovers

    $id = "$((Get-Date).ToString('yyyyMMddHHmmss', [System.Globalization.CultureInfo]::InvariantCulture))-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $taskName = "$($script:TFToolkitLimitedTaskPrefix)$id"
    $folder = Join-Path (Join-Path (Get-TFToolkitDataPath) "run") $id
    $request = ConvertTo-TFToolkitLimitedRunRequest -Folder $folder -FilePath $FilePath -Arguments $Arguments
    $command = Get-TFToolkitHiddenPowerShellCommand -Arguments "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $(ConvertTo-TFToolkitCommandLineArgument -Value $runner) -Request $request" -WorkingDirectory $root
    $xml = New-TFToolkitLimitedRunTaskXml -Executable $command.Executable -Arguments $command.Arguments -WorkingDirectory $command.WorkingDirectory -UserId $sid

    $state = @{
        Path     = (Join-Path $folder "output.txt")
        OwnerSid = $sid
        Stream   = $null
        Decoder  = (New-Object System.Text.UTF8Encoding $false).GetDecoder()
        Pending  = (New-Object System.Text.StringBuilder)
        Read     = [long]0
        Lines    = (New-Object System.Collections.Generic.List[string])
        Echo     = @{ Last = -1.0 }
        Refused  = $false
    }
    $exitPath = Join-Path $folder "exitcode.txt"
    $pidPath = Join-Path $folder "pid.txt"
    $registered = $false
    $finished = $false
    $process = $null
    $since = Get-Date

    try {
        try {
            [void](Invoke-TFToolkitCimCommand -Name "Register-ScheduledTask" -Parameters @{ Xml = $xml; TaskPath = $script:TFToolkitSchedulePath; TaskName = $taskName; Force = $true })
            $registered = $true
            [void](Invoke-TFToolkitCimCommand -Name "Start-ScheduledTask" -Parameters @{ TaskPath = $script:TFToolkitSchedulePath; TaskName = $taskName })
        }
        catch {
            $outcome.Reason = (Get-TFToolkitText 'o Agendador de Tarefas não aceitou a tarefa: {0}' "$(([string]$_.Exception.Message).Trim().TrimEnd('.'))")
            return $outcome
        }

        $clock = [System.Diagnostics.Stopwatch]::StartNew()

        while ($true) {
            Read-TFToolkitLimitedRunOutput -State $state

            if (Test-Path -LiteralPath $exitPath -PathType Leaf) {
                $finished = $true
                Read-TFToolkitLimitedRunOutput -State $state -Final
                $text = Read-TFToolkitLimitedRunText -Path $exitPath -OwnerSid $sid
                $code = 0

                if ($null -eq $text) {
                    $outcome.Reason = (Get-TFToolkitText 'o resultado da execução não pôde ser conferido')
                }
                elseif ($text.StartsWith("!")) {
                    $outcome.Reason = (Get-TFToolkitText 'o programa não abriu: {0}' "$($text.Substring(1).Trim().TrimEnd('.'))")
                }
                elseif ([int]::TryParse($text, [ref]$code)) {
                    $outcome.Ran = $true
                    $outcome.ExitCode = $code
                }
                else {
                    $outcome.Reason = (Get-TFToolkitText 'o resultado da execução não pôde ser conferido')
                }

                break
            }

            if ($null -eq $process) {
                $process = Get-TFToolkitLimitedRunProcess -Path $pidPath -OwnerSid $sid -Since $since

                if ($null -eq $process -and $clock.Elapsed.TotalSeconds -ge $script:TFToolkitLimitedStartSeconds) {
                    # O Agendador que não começou a tarefa, ou o script que não abriu (uma política do PowerShell, por
                    # exemplo): nos dois casos, nada começou.
                    $outcome.Reason = (Get-TFToolkitText 'a execução sem Administrador não começou em {0} segundos' "$($script:TFToolkitLimitedStartSeconds)")
                    break
                }
            }
            elseif ($process.HasExited) {
                # O código de saída é a última coisa que o script grava: uma volta a mais para ele aparecer.
                Start-Sleep -Milliseconds $script:TFToolkitLimitedPollMilliseconds

                if (Test-Path -LiteralPath $exitPath -PathType Leaf) { continue }

                $finished = $true
                Read-TFToolkitLimitedRunOutput -State $state -Final
                $outcome.Reason = (Get-TFToolkitText 'a execução terminou sem dizer o resultado')
                break
            }

            Start-Sleep -Milliseconds $script:TFToolkitLimitedPollMilliseconds
        }
    }
    finally {
        if ($null -ne $state.Stream) { $state.Stream.Dispose() }

        if (-not $finished -and $registered) {
            # Parada no meio (o Parar, a janela fechada) ou o prazo para começar vencido: o que a tarefa abriu não pode
            # continuar rodando escondido, nem começar depois. Primeiro a árvore do script (o winget e o desinstalador, que
            # o taskkill só acha enquanto o script existe), mesmo que ele tenha começado agora; depois a tarefa, que o
            # Agendador encerra, e que apagada não roda mais.
            if ($null -eq $process) { $process = Get-TFToolkitLimitedRunProcess -Path $pidPath -OwnerSid $sid -Since $since }
            if ($null -ne $process) { Stop-TFToolkitLimitedRunProcess -Process $process }

            try {
                [void](Invoke-TFToolkitCimCommand -Name "Stop-ScheduledTask" -Parameters @{ TaskPath = $script:TFToolkitSchedulePath; TaskName = $taskName })
            }
            catch {
                Write-Verbose "Tarefa sem Administrador não encerrada ($taskName): $($_.Exception.Message)"
            }
        }

        if ($registered) {
            try {
                [void](Invoke-TFToolkitCimCommand -Name "Unregister-ScheduledTask" -Parameters @{ TaskPath = $script:TFToolkitSchedulePath; TaskName = $taskName; Confirm = $false })
                Remove-TFToolkitScheduleFolder
            }
            catch {
                # A tarefa não tem horário e não roda sozinha; a próxima execução a tira (Remove-TFToolkitLimitedRunLeftovers).
                Write-Verbose "Tarefa sem Administrador não apagada ($taskName): $($_.Exception.Message)"
            }
        }

        Remove-TFToolkitFolder -Path $folder -Quiet
    }

    $outcome.Lines = @($state.Lines)

    return $outcome
}


Export-ModuleMember -Function *
