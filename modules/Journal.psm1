# Histórico de mudanças: o diário do que o TF-Toolkit mudou no PC, com o desfazer de cada mudança que dá para desfazer.
#
# Cada ação que muda o Windows anota uma linha (o que foi feito, quando e, quando existe, como desfazer) com
# Add-TFToolkitChange, que fica no Core: assim qualquer módulo anota sem depender deste. Aqui ficam o desfazer de cada
# tipo de mudança e a tela do histórico. O diário fica em %LOCALAPPDATA%\TF-Toolkit\changes.json (as 200 mais recentes).


# ---------------------------------------------------------------------------
# Desfazer
# ---------------------------------------------------------------------------

function Test-TFToolkitStartupUndoItem {
    <#
    Se um item guardado no diário pode ser ligado ou desligado pelo desfazer: tarefas agendadas só se forem uma das que
    a tela Gerenciar inicialização mostra hoje (de outros fabricantes, que rodam ao entrar no Windows ou ao ligar o PC);
    os demais só se o liga/desliga for numa das chaves StartupApproved que o Windows usa para isso.
    #>
    param (
        [Parameter(Mandatory)]$Item,

        # As tarefas de inicialização já lidas (Get-TFToolkitStartupTasks percorre o Agendador inteiro e leva segundos):
        # quem confere vários itens lê uma vez só.
        $Tasks = $null
    )

    $name = [string](Get-TFToolkitJsonValue -Object $Item -Name "Name" -Default "")
    $source = [string](Get-TFToolkitJsonValue -Object $Item -Name "Source" -Default "")

    if ([string]::IsNullOrWhiteSpace($name)) { return $false }

    if ($source -eq "Tarefa agendada") {
        $taskPath = [string](Get-TFToolkitJsonValue -Object $Item -Name "TaskPath" -Default "")
        $taskName = [string](Get-TFToolkitJsonValue -Object $Item -Name "TaskName" -Default "")

        if ([string]::IsNullOrWhiteSpace($taskName) -or $taskPath -like "\Microsoft\*") { return $false }

        if ($null -eq $Tasks) { $Tasks = @(Get-TFToolkitStartupTasks) }

        return (@($Tasks | Where-Object { [string]$_.TaskPath -eq $taskPath -and [string]$_.TaskName -eq $taskName }).Count -gt 0)
    }

    # Aplicativo da Store: o liga/desliga é o State da tarefa de inicialização dele, numa chave SystemAppData da conta.
    if ($source -eq "Aplicativo da Store") {
        return (Test-TFToolkitStartupAppPath -Path ([string](Get-TFToolkitJsonValue -Object $Item -Name "ApprovedPath" -Default "")))
    }

    $approvedRoot = "Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"
    $known = @(
        "HKCU:\Software\$approvedRoot\Run",
        "HKCU:\Software\$approvedRoot\StartupFolder",
        "HKLM:\SOFTWARE\$approvedRoot\Run",
        "HKLM:\SOFTWARE\$approvedRoot\Run32",
        "HKLM:\SOFTWARE\$approvedRoot\StartupFolder"
    )

    return ($known -contains [string](Get-TFToolkitJsonValue -Object $Item -Name "ApprovedPath" -Default ""))
}


function Undo-TFToolkitChange {
    # Desfaz uma mudança anotada e devolve um TFToolkit.Result (Etapa = o nome da mudança). Não marca como desfeita: quem
    # chama marca só o que deu certo.
    param (
        [Parameter(Mandatory)]$Change
    )

    $undo = $Change.Undo
    $kind = [string](Get-TFToolkitJsonValue -Object $undo -Name "Kind" -Default "")

    # O diário fica em %LOCALAPPDATA%, onde qualquer programa da conta grava sem Administrador, e o desfazer pode rodar
    # como Administrador: o que vem dele é conferido antes de virar uma mudança no Windows (só os backups da pasta do
    # TF-Toolkit, só os itens de inicialização que o TF-Toolkit gerencia, só os recursos do catálogo).
    # Recursos do Windows e o DNS dos adaptadores só voltam com Administrador: sem ele, o motivo é dito com as palavras do
    # TF-Toolkit (e não com o texto cru do Windows), e a mudança continua na lista para depois.
    if ($kind -in @("feature", "dns") -and -not (Test-TFToolkitAdministrator)) {
        return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'pede Administrador: abra o TF-Toolkit como Administrador e desfaça de novo'))
    }

    switch ($kind) {
        "registry" {
            $file = [string](Get-TFToolkitJsonValue -Object $undo -Name "File" -Default "")
            $values = [string](Get-TFToolkitJsonValue -Object $undo -Name "Values" -Default "")

            if ([string]::IsNullOrWhiteSpace($file) -and [string]::IsNullOrWhiteSpace($values)) {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o backup do registro não foi encontrado'))
            }

            foreach ($backup in @(@{ Path = $file; Extension = ".reg" }, @{ Path = $values; Extension = ".json" })) {
                # Um arquivo que não existe mais não é lido (vira um problema logo abaixo, só na parte dele).
                if ([string]::IsNullOrWhiteSpace($backup.Path) -or -not (Test-Path -LiteralPath $backup.Path)) { continue }

                # Um caminho fora da pasta de backups do TF-Toolkit recusa o desfazer inteiro: o diário pode ter sido mexido.
                if (-not (Test-TFToolkitRegistryBackupFile -Path $backup.Path -Extension $backup.Extension)) {
                    return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o backup do registro não está na pasta de backups do TF-Toolkit e não foi usado'))
                }
            }

            if ($file -and (Test-Path -LiteralPath $file -PathType Leaf) -and -not (Test-TFToolkitRegistryBackupKeys -Path $file)) {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o backup do registro mexe em chaves que a limpeza não toca e não foi usado'))
            }

            # As duas partes rodam sempre, cada uma por si: um arquivo que sumiu ou estragou (um corte de energia no meio
            # da gravação) não impede a outra parte de voltar. Com qualquer falha, o desfazer não é dado como feito e
            # continua na lista: repetir é seguro (o .reg volta igual e só os valores que ainda faltam são recriados).
            $kept = 0
            $done = 0
            $problems = @()
            $gone = @()
            $admin = Test-TFToolkitAdministrator

            if ($values) {
                if (-not (Test-Path -LiteralPath $values -PathType Leaf)) {
                    $gone += "values"
                }
                else {
                    try {
                        $restore = Restore-TFToolkitRegistryValues -Path $values
                        $kept = [int]$restore.Kept
                        $done++

                        if (@($restore.Failed).Count -gt 0) {
                            $total = @($restore.Failed).Count + [int]$restore.Restored + $kept
                            $problems += (Get-TFToolkitText '{0} de {1} valores não voltaram ({2})' "$(@($restore.Failed).Count)" "$total" "$(Join-TFToolkitList -Items @($restore.Failed))")
                        }
                    }
                    catch {
                        $problems += (Get-TFToolkitText 'o backup dos valores não pôde ser lido ({0})' "$(([string]$_.Exception.Message).TrimEnd('.'))")
                    }
                }
            }

            if ($file) {
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                    $gone += "keys"
                }
                else {
                    $run = Invoke-TFToolkitCapture -FilePath "reg" -Arguments @("import", $file)

                    if ($run.ExitCode -ne 0) {
                        $problems += $(if ($admin) { (Get-TFToolkitText 'o reg import terminou com o código {0}' "$($run.ExitCode)") } else { (Get-TFToolkitText 'as chaves do backup não voltaram') })
                    }
                    else {
                        $done++
                    }
                }
            }

            # Um backup que não existe mais não volta tentando de novo: sem nenhuma parte restaurada, é falha; com a outra
            # parte de volta, a mudança é dada como desfeita, com o aviso do que não tinha como voltar.
            $goneText = $(
                if ($gone.Count -eq 0) { "" }
                elseif ($gone.Count -eq 2) { (Get-TFToolkitText 'o backup do registro não existe mais') }
                elseif ($gone[0] -eq "values") { (Get-TFToolkitText 'o backup dos valores não existe mais') }
                else { (Get-TFToolkitText 'o backup das chaves não existe mais') }
            )

            if ($problems.Count -gt 0 -or $done -eq 0) {
                $all = @($problems) + @($(if ($goneText) { $goneText }))
                $detail = (Join-TFToolkitList -Items $all) + $(if ($problems.Count -gt 0 -and -not $admin) { (Get-TFToolkitText '; abra o TF-Toolkit como Administrador e tente de novo') } else { "" })
                return (New-TFToolkitResult -Kind $(if ($done -gt 0) { "Warning" } else { "Failed" }) -Detail $detail)
            }

            # Um valor que já existe de novo (o programa voltou a gravá-lo) fica como está, com o dado de hoje.
            $detail = $(if ($kept -gt 0) { (Get-TFToolkitText 'entradas do registro devolvidas; {0} como está' "$(Format-TFToolkitCount -Count $kept -One (Get-TFToolkitText 'valor já existia de novo e ficou') -Many (Get-TFToolkitText 'valores já existiam de novo e ficaram'))") } else { (Get-TFToolkitText 'entradas do registro devolvidas') })
            if ($goneText) { $detail += $(if ($gone[0] -eq "values") { (Get-TFToolkitText '; {0}, então os valores não têm como voltar' "$goneText") } else { (Get-TFToolkitText '; {0}, então as chaves não têm como voltar' "$goneText") }) }

            return (New-TFToolkitResult -Kind Ok -Detail $detail)
        }
        "startup" {
            $failed = 0
            $reason = ""
            $items = @(Get-TFToolkitJsonValue -Object $undo -Name "Items" -Default @())
            $tasks = $null
            $tasksProblem = ""

            foreach ($item in $items) {
                try {
                    $isTask = ([string](Get-TFToolkitJsonValue -Object $item -Name "Source" -Default "") -eq "Tarefa agendada")

                    if ($null -eq $tasks -and $isTask) {
                        $tasks = @(Get-TFToolkitStartupTasks)
                        $tasksProblem = Get-TFToolkitStartupTasksProblem
                    }

                    if (-not (Test-TFToolkitStartupUndoItem -Item $item -Tasks $tasks)) {
                        # Sem a leitura do Agendador, a tarefa não é "desconhecida": o motivo é o Agendador.
                        if ($isTask -and $tasksProblem) { throw (Get-TFToolkitText 'as tarefas agendadas não puderam ser lidas: {0}' "$tasksProblem") }
                        throw (Get-TFToolkitText 'item de inicialização desconhecido')
                    }

                    Set-TFToolkitStartupItemEnabled -Item $item -Enabled ([bool](Get-TFToolkitJsonValue -Object $item -Name "Enabled" -Default $true))
                }
                catch {
                    $failed++

                    # O primeiro motivo vai junto (por exemplo, o item de todos os usuários que exige Administrador): sem
                    # ele, a pessoa não sabe o que fazer para desfazer.
                    if (-not $reason) { $reason = ([string]$_.Exception.Message).TrimEnd('.') }
                }
            }

            if ($failed -gt 0) {
                $what = $(if ($items.Count -eq 1) { (Get-TFToolkitText 'o item não voltou ao estado anterior') } elseif ($failed -eq 1) { (Get-TFToolkitText '1 de {0} itens não voltou ao estado anterior' "$($items.Count)") } else { (Get-TFToolkitText '{0} de {1} itens não voltaram ao estado anterior' "$failed" "$($items.Count)") })
                return (New-TFToolkitResult -Kind $(if ($failed -lt $items.Count) { "Warning" } else { "Failed" }) -Detail $(if ($reason) { "${what}: $reason" } else { $what }))
            }

            return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'inicialização como estava antes'))
        }
        "tweak" {
            $tweak = Get-TFToolkitTweakById -Id ([string](Get-TFToolkitJsonValue -Object $undo -Name "Id" -Default ""))

            if ($null -eq $tweak) {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'ajuste desconhecido'))
            }

            # Com os valores originais guardados, o desfazer sempre os devolve: "não aplicado" pode ser parcial (uma atualização
            # do Windows voltou só um dos valores do ajuste), e "já estava desfeito" deixaria o resto como o TF-Toolkit pôs.
            $backup = Read-TFToolkitTweakBackup -Status
            $saved = ($backup.Status -ne "Unreadable" -and $backup.Backup.Contains([string]$tweak.Id))

            if (-not $saved -and (Get-TFToolkitTweakStatus -Tweak $tweak) -ne "Aplicado") {
                return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'o ajuste já estava desfeito'))
            }

            try {
                $report = Invoke-TFToolkitTweakRevert -Tweak $tweak -Detailed
            }
            catch {
                # Uma configuração que o Windows protege (UCPD): a mesma explicação de Ajustes do Windows, com onde desfazer.
                $help = Get-TFToolkitTweakProtectedHelp -Tweak $tweak -Undo

                if ($null -ne $help -and (Test-TFToolkitAccessDenied -Exception $_.Exception)) {
                    Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitTweakProtectedText -Help $help)
                    return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o Windows protege esta configuração e não deixa o TF-Toolkit desfazê-la'))
                }

                throw
            }

            # Como em Ajustes do Windows: o que só aparece com o Explorador reiniciado pede o reinício dele (a tela do
            # histórico oferece, uma vez, no fim), e o que só vale depois de reiniciar o PC põe o pedido na faixa.
            $changed = ([int]$report.Restored -gt 0)
            $data = @{
                RestartExplorer = ([bool]$tweak.RestartExplorer -and $changed)
                RebootRequired  = ([bool](Get-TFToolkitTweakField -Entry $tweak -Name "NeedsReboot" -Default $false) -and $changed)
            }

            return (New-TFToolkitResult -Kind Ok -Detail $(if ($report.HadBackup) { (Get-TFToolkitText 'ajuste desfeito') } else { (Get-TFToolkitText 'ajuste desfeito com os padrões do Windows (os valores de antes não estavam guardados)') }) -Data $data)
        }
        "dns" {
            $read = Read-TFToolkitDnsBackup -Status

            # Um backup que existe, mas não abriu agora (em uso, sem permissão), não é "nada a desfazer": fica para depois.
            if ($read.Status -eq "Unreadable") {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o backup do DNS de antes não pôde ser lido agora; tente de novo em instantes'))
            }

            $backup = @($read.Entries)

            if ($backup.Count -eq 0) {
                return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'o DNS já estava como antes'))
            }

            $undo = Restore-TFToolkitDnsFromBackup -Backup $backup -Adapters @(Get-TFToolkitDnsAdapters)
            $unknown = @(Get-TFToolkitJsonValue -Object $undo -Name "Unknown" -Default @())

            if ($undo.Failed.Count -gt 0 -or $undo.Missing.Count -gt 0 -or $unknown.Count -gt 0) {
                return (New-TFToolkitResult -Kind $(if ($undo.Restored -gt 0) { "Warning" } else { "Failed" }) -Detail (Get-TFToolkitText 'nem todos os adaptadores voltaram ao DNS de antes; use Rede > Desfazer a troca de DNS'))
            }

            Remove-TFToolkitDnsBackup
            Clear-DnsClientCache -ErrorAction SilentlyContinue

            # O backup guarda o DNS de antes da primeira troca: todas as trocas anotadas foram desfeitas de uma vez (como
            # em Rede > Desfazer a troca de DNS), e nenhuma fica na lista prometendo voltar a um DNS intermediário.
            Set-TFToolkitChangesUndone -Kind "dns" -Key "Kind" -Value "dns"

            return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'DNS de antes da primeira troca restaurado'))
        }
        "feature" {
            $name = [string](Get-TFToolkitJsonValue -Object $undo -Name "Name" -Default "")
            $action = [string](Get-TFToolkitJsonValue -Object $undo -Name "Action" -Default "")

            if ($action -notin @("Enable", "Disable")) {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'mudança de recurso desconhecida'))
            }

            # Só os recursos que a tela Recursos do Windows oferece: o nome vem do diário e não pode ligar qualquer recurso.
            if (@(Get-TFToolkitFeatureCatalog | Where-Object { [string]$_.Name -eq $name }).Count -eq 0) {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'recurso desconhecido'))
            }

            $applied = Set-TFToolkitOptionalFeature -Name $name -Action $action

            return (New-TFToolkitResult -Kind Ok -Detail $(if ($action -eq "Enable") { (Get-TFToolkitText 'recurso ligado de novo') } else { (Get-TFToolkitText 'recurso desligado de novo') }) -Data @{ RebootRequired = [bool]$applied.RestartNeeded })
        }
        "keyboard-hotkeys" {
            # As teclas do idioma (Ajustes do Windows): os valores de antes voltam, se a escolha de agora ainda é a que o
            # TF-Toolkit gravou.
            return (Undo-TFToolkitChoiceChange -Kind $kind -Undo $undo)
        }
        "winget-pin" {
            # Os marcadores do winget ficam no perfil da conta: elevado com outra conta, o desfazer mexeria nos dela.
            if (-not (Test-TFToolkitWinget)) {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitWingetMissingDetail))
            }

            if (Test-TFToolkitUserContextMismatch) {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'o TF-Toolkit está elevado com outra conta; desfaça com a conta de quem usa o PC'))
            }

            $items = @(Get-TFToolkitJsonValue -Object $undo -Name "Items" -Default @() | Where-Object { $null -ne $_ })

            if ($items.Count -eq 0) {
                return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'esta mudança não tem como ser desfeita'))
            }

            $failed = 0
            $reason = ""

            foreach ($item in $items) {
                # O que vem do diário é conferido antes de ir para o winget: um ID que não é de pacote, um tipo de
                # marcador desconhecido ou uma faixa de versões estranha não viram uma linha de comando.
                $id = [string](Get-TFToolkitJsonValue -Object $item -Name "Id" -Default "")
                $pin = [string](Get-TFToolkitJsonValue -Object $item -Name "Pin" -Default "")
                $source = [string](Get-TFToolkitJsonValue -Object $item -Name "Source" -Default "")
                $gated = [string](Get-TFToolkitJsonValue -Object $item -Name "Gated" -Default "")

                if (-not (Test-TFToolkitWingetPinId -Id $id) -or $pin -notin @("None", "Pinning", "Blocking", "Gating")) {
                    $failed++
                    if (-not $reason) { $reason = (Get-TFToolkitText 'programa desconhecido') }
                    continue
                }

                $run = $(if ($pin -eq "None") { Invoke-TFToolkitWingetPin -Operation Remove -Id $id } else { Invoke-TFToolkitWingetPin -Operation Add -Id $id -Source $source -Pin $pin -Gated $gated })

                if ($run.Kind -ne "Ok") {
                    $failed++
                    if (-not $reason) { $reason = ([string]$run.Detail).TrimEnd('.') }
                }
            }

            if ($failed -gt 0) {
                $what = $(if ($items.Count -eq 1) { (Get-TFToolkitText 'o programa não voltou ao estado anterior') } elseif ($failed -eq 1) { (Get-TFToolkitText '1 de {0} programas não voltou ao estado anterior' "$($items.Count)") } else { (Get-TFToolkitText '{0} de {1} programas não voltaram ao estado anterior' "$failed" "$($items.Count)") })
                return (New-TFToolkitResult -Kind $(if ($failed -lt $items.Count) { "Warning" } else { "Failed" }) -Detail $(if ($reason) { "${what}: $reason" } else { $what }))
            }

            return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'programas marcados como estavam antes'))
        }
    }

    return (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'esta mudança não tem como ser desfeita'))
}


# ---------------------------------------------------------------------------
# Tela
# ---------------------------------------------------------------------------

function Show-TFToolkitChangeHistory {
    $title = (Get-TFToolkitText 'Histórico de mudanças')

    Enter-TFToolkitAction -Title $title

    $final = New-TFToolkitResult -Kind Ok -Title $title

    try {
        $read = Get-TFToolkitChanges -Status
        $changes = @($read.Changes)

        # Um diário que existe, mas não abriu agora (preso por outro programa, sem permissão), não é "nada mudou": a
        # pessoa perderia de vista o que tem desfazer.
        if ($read.Status -eq "Unreadable") {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível ler o Histórico de mudanças agora (arquivo em uso ou sem permissão): tente de novo em instantes.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'não foi possível ler o histórico agora; tente de novo em instantes') -Title $title)
            return
        }

        # Só olhar o histórico não tem veredito: a tela termina sem a faixa de resultado (sem "Tudo certo" nem "Nada a
        # fazer"); a faixa fica para o que foi desfeito.
        if ($changes.Count -eq 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O TF-Toolkit ainda não mudou nada neste PC (ou o histórico foi apagado).')
            Exit-TFToolkitAction
            return
        }

        # O desfazer vale para todas as mudanças guardadas: uma mudança antiga continua com o seu desfazer (a lista de
        # marcar mostra a data de cada uma). A lista de cima traz só as outras (sem volta por aqui, ou já desfeitas), para
        # nenhuma mudança aparecer duas vezes na tela.
        $undoable = @($changes | Where-Object { Test-TFToolkitChangeUndoable -Change $_ })
        $others = @($changes | Where-Object { -not (Test-TFToolkitChangeUndoable -Change $_) })
        $shown = @($others | Select-Object -First 30)

        if ($shown.Count -gt 0) {
            Write-TFToolkitSection -Title $(if ($undoable.Count -gt 0) { (Get-TFToolkitText 'Mudanças sem desfazer por aqui') } else { (Get-TFToolkitText 'Últimas mudanças') })

            foreach ($change in $shown) {
                $suffix = $(if ($change.Undone) { (Get-TFToolkitText ' (desfeita)') } else { "" })
                Write-TFToolkitKeyValue -Label (Format-TFToolkitDateTime -When $change.At -Pattern 'dd/MM HH:mm') -Value "$(Get-TFToolkitText ([string]$change.Action)): $($change.Text)$suffix" -LabelWidth 12
            }

            if ($others.Count -gt $shown.Count) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'E mais {0}.' "$(Format-TFToolkitCount -Count ($others.Count - $shown.Count) -One (Get-TFToolkitText 'mudança mais antiga') -Many (Get-TFToolkitText 'mudanças mais antigas'))")
            }

            Write-Host ""
        }

        if ($undoable.Count -eq 0) {
            # Limpezas e desinstalações não têm volta.
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhuma das mudanças anotadas pode ser desfeita por aqui; os ajustes saem em Ajustes do Windows > Desfazer ajustes do TF-Toolkit.')
            Exit-TFToolkitAction
            return
        }

        $options = @(
            foreach ($change in $undoable) {
                @{ Key = $change.Id; Label = "$(Get-TFToolkitText ([string]$change.Action)): $($change.Text)"; Description = (Format-TFToolkitDateTime -When $change.At); Selected = $false }
            }
        )

        # Direto na lista: desfazer não apaga nada (volta ao que era), então marcar e confirmar basta, sem um Sim/Não a
        # mais. Cancelar (ou não marcar nada) é só ter olhado: a tela termina sem faixa de resultado.
        # Sem "marcar todos": desfazer tudo de uma vez, sem outra pergunta, inclui recursos do Windows e programas.
        $picked = Read-TFToolkitMultiSelect -Message (Get-TFToolkitText 'O que desfazer?') -Options $options -NoSelectAll -ConfirmLabel (Get-TFToolkitText 'Desfazer')

        if ($null -eq $picked -or @($picked).Count -eq 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nada foi desfeito.')
            Exit-TFToolkitAction
            return
        }

        $chosen = @($undoable | Where-Object { @($picked) -contains $_.Id })

        $results = @()
        $reboot = $false

        foreach ($change in $chosen) {
            # Um desfazer anterior desta mesma lista pode já ter coberto esta mudança: o DNS volta ao de antes da primeira
            # troca, e todas as trocas saem da lista juntas. Ela não é desfeita de novo, nem contada, nem anotada outra vez.
            if (@(Get-TFToolkitChanges | Where-Object { $null -ne $_ -and [string]$_.Id -eq [string]$change.Id -and $_.Undone }).Count -gt 0) { continue }

            try {
                $result = Undo-TFToolkitChange -Change $change
            }
            catch {
                $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message.TrimEnd('.')
            }

            # O nome da ação foi gravado no idioma da época: em português, a tabela de agora o traduz.
            $result.Etapa = (Get-TFToolkitContextText 'mudança' '{0} de {1}' "$(Get-TFToolkitText ([string]$change.Action))" "$(Format-TFToolkitDateTime -When $change.At -Pattern 'dd/MM HH:mm')")

            if ($result.Kind -eq "Failed") {
                Write-TFToolkitStatus -Type Error -Message "$($result.Etapa): $($result.Detail)."
            }
            elseif ($result.Kind -eq "Warning") {
                # Deu certo só em parte (um item da inicialização, um adaptador): a mudança continua na lista para tentar
                # de novo, o que é seguro (o que já voltou fica como está).
                Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText '{0}: {1}; a mudança continua na lista para tentar de novo.' "$($result.Etapa)" "$($result.Detail)")
            }
            else {
                Set-TFToolkitChangeUndone -Id $change.Id
                [void](Add-TFToolkitChange -Action (Get-TFToolkitText 'Desfeito') -Text "$($change.Action): $($change.Text)")
                Write-TFToolkitStatus -Type Success -Message "$($result.Etapa): $($result.Detail)."
            }

            if (Test-TFToolkitResultFlag -Result $result -Name "RebootRequired") { $reboot = $true }

            $results += $result
        }

        $failed = @($results | Where-Object { $_.Kind -eq "Failed" })
        # Desfeitas só em parte: não contam como desfeitas (continuam na lista), mas também não são falha completa.
        $partial = @($results | Where-Object { $_.Kind -eq "Warning" })
        $data = @{ RebootRequired = $reboot }

        if ($failed.Count -eq 0 -and $partial.Count -eq 0) {
            $final = New-TFToolkitResult -Kind Ok -Detail (Format-TFToolkitCount -Count $results.Count -One (Get-TFToolkitText 'mudança desfeita') -Many (Get-TFToolkitText 'mudanças desfeitas')) -Title $title -Data $data
        }
        elseif ($failed.Count -eq $results.Count) {
            $final = New-TFToolkitResult -Kind Failed -Detail $(if ($results.Count -eq 1) { $failed[0].Detail } else { (Get-TFToolkitText 'nenhuma mudança foi desfeita') }) -Title $title
        }
        elseif ($results.Count -eq 1) {
            $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0}; a mudança continua na lista para tentar de novo' "$($partial[0].Detail)") -Title $title -Data $data
        }
        else {
            $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText '{0} de {1} não foram desfeitas por completo' "$($failed.Count + $partial.Count)" "$($results.Count)") -Title $title -Data $data
        }

        # Um ajuste desfeito que só aparece com o Explorador reiniciado (a barra de tarefas, o menu do clique direito): uma
        # pergunta só, no fim, como em Ajustes do Windows. Um Explorador que não reinicia é uma ressalva: o ajuste já voltou.
        $explorer = @($results | Where-Object { Test-TFToolkitResultFlag -Result $_ -Name "RestartExplorer" })

        if ($explorer.Count -gt 0) {
            Write-Host ""
            $question = $(if ($explorer.Count -eq 1) { (Get-TFToolkitText 'Reiniciar o Explorador de Arquivos agora para ver a mudança?') } else { (Get-TFToolkitText 'Reiniciar o Explorador de Arquivos agora para ver as mudanças?') })
            $restart = Request-TFToolkitExplorerRestart -Question $question -Many:($explorer.Count -gt 1)

            if ($restart -eq "Failed" -and $final.Kind -eq "Ok") {
                $final = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'o Explorador não reiniciou') -Title $title -Data $data
            }
        }
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível ler o histórico: {0}' "$($_.Exception.Message)")
        $final = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message -Title $title
    }

    Exit-TFToolkitAction -Result $final
}


Export-ModuleMember -Function *
