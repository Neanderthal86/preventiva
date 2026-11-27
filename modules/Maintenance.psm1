# Otimizar: a manutenção completa do PC, num fluxo guiado em que as perguntas vêm antes da parte demorada.
#
#   1. Preparação          os avisos que importam e a sugestão forte de fechar os programas (com a lista dos abertos)
#   2. Plano               sempre o inteiro, na ordem da lista abaixo, sem perguntar o que fazer
#   3. Com você, no começo ponto de restauração, programas, o que abre com o Windows e as pastas pessoais (telas do TF-Toolkit);
#                          depois dos programas, a lista do winget começa em segundo plano, para a pergunta dela não esperar
#   4. Perguntas           o que a parte automática precisa saber (numa conexão limitada, se baixa os programas; o que
#                          atualizar no winget, que restos apagar, a Lixeira)
#   5. Automática          sem perguntas: antivírus, reparo do Windows, atualizações, navegadores, limpeza, rede e disco;
#                          no fim dela, o resultado já fica gravado (se a janela fechar na revisão dos ajustes, não se perde)
#   6. Com você, no fim    a revisão dos ajustes do Windows, já marcados conforme o Windows está agora
#   7. Encerramento        resumo, CHKDSK offline e, sempre, a sugestão de reiniciar (com a parte automática cancelada,
#                          só quando o Windows precisa)
#
# Na tela, o mínimo de texto: uma linha por aviso, perguntas curtas; o porquê de cada coisa fica nestes comentários. Na
# janela, o alto da tela diz a etapa ("Etapa 3 de 20") e, nas perguntas e no encerramento, a parte (Write-TFToolkitPhase).

# A lista das janelas abertas (Get-TFToolkitTopLevelWindows): as que a barra de tarefas mostra, como ela decide (visível,
# sem dono, que não é janela de ferramenta) e sem as encobertas pelo Windows (aplicativos suspensos, outras áreas de
# trabalho virtuais).
$script:TFToolkitOpenWindowsSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace TFToolkit
{
    public static class OpenWindows
    {
        private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr hwnd, uint command);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLength(IntPtr hwnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
        private static extern int GetWindowLong(IntPtr hwnd, int index);

        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);

        public sealed class Entry
        {
            public int ProcessId;
            public string Title;
        }

        public static Entry[] List()
        {
            List<Entry> found = new List<Entry>();

            EnumWindows(delegate (IntPtr hwnd, IntPtr lParam)
            {
                try
                {
                    if (!IsWindowVisible(hwnd)) { return true; }
                    // GW_OWNER = 4: uma janela com dono (diálogo, paleta) não tem botão próprio na barra de tarefas.
                    if (GetWindow(hwnd, 4) != IntPtr.Zero) { return true; }
                    // GWL_EXSTYLE = -20; WS_EX_TOOLWINDOW = 0x80.
                    if ((GetWindowLong(hwnd, -20) & 0x80) != 0) { return true; }

                    // DWMWA_CLOAKED = 14.
                    int cloaked = 0;
                    if (DwmGetWindowAttribute(hwnd, 14, out cloaked, 4) == 0 && cloaked != 0) { return true; }

                    int length = GetWindowTextLength(hwnd);
                    if (length <= 0) { return true; }

                    StringBuilder text = new StringBuilder(length + 1);
                    GetWindowText(hwnd, text, text.Capacity);

                    uint processId;
                    GetWindowThreadProcessId(hwnd, out processId);

                    Entry entry = new Entry();
                    entry.ProcessId = (int)processId;
                    entry.Title = text.ToString();
                    found.Add(entry);
                }
                catch
                {
                    // Uma janela que fechou no meio da conta fica de fora.
                }

                return true;
            }, IntPtr.Zero);

            return found.ToArray();
        }
    }
}
'@

$script:TFToolkitWindowListFailed = $false
$script:TFToolkitWindowNativeFailed = $false


# ---------------------------------------------------------------------------
# Plano
# ---------------------------------------------------------------------------

function New-TFToolkitPlanItem {
    # Uma etapa do Otimizar. Phase: Before (antes da parte automática), Auto ou After (depois dela). -WithYou: a etapa
    # mostra uma tela do TF-Toolkit e espera a pessoa escolher; sem ele, roda sozinha. Title é o nome na tela, no resumo e no
    # histórico. O plano não aparece como lista (o Otimizar é sempre o inteiro): o que cada etapa faz fica no comentário
    # dela, em Get-TFToolkitMaintenancePlanItems.
    param (
        [string]$Id,
        [ValidateSet("Before", "Auto", "After")]
        [string]$Phase,
        [string]$Title,
        [switch]$WithYou
    )

    return [PSCustomObject]@{
        Id      = $Id
        Phase   = $Phase
        WithYou = [bool]$WithYou
        Title   = $Title
    }
}


function Get-TFToolkitMaintenancePlanItems {
    # A ordem desta lista é a ordem de execução. Antes: o ponto de restauração e o que precisa da pessoa (enxugar o PC).
    # Automático: proteger; limpar os componentes e reparar o Windows ANTES do Windows Update (uma atualização instalada
    # deixa o Windows esperando o reinício, e aí o DISM recusa a limpeza e o reparo, 0x800F0806, e o SFC também); atualizar
    # (Windows, drivers, programas, navegadores e Store, já com a internet de antes do reparo de rede); limpar; reparar a
    # rede; conferir o disco e otimizar por último. Depois: os ajustes, com a pessoa de volta.
    # O registro não entra: a Microsoft não dá suporte a limpadores de registro, e a limpeza não deixa o PC mais rápido
    # (KB 2563254). Ele fica em Limpeza > Limpar o registro e no Verificar o PC, desmarcado, para quem quiser.
    # As atualizações antecipadas ("Receba as atualizações mais recentes assim que estiverem disponíveis") também não: são
    # uma escolha da pessoa, e não manutenção. A Microsoft diz que, ligada ou não, as atualizações de segurança chegam do
    # mesmo jeito, e que ligada o PC pode reiniciar mais vezes por mês. Desligá-la a cada Otimizar desfazia a escolha de
    # quem a ligou; ela aparece na revisão dos ajustes, no fim, marcada conforme o Windows está.
    # A limpeza (que esvazia a Lixeira, quando a pessoa pede) vem ANTES dos atalhos quebrados e dos restos de programas,
    # que vão para a Lixeira: depois deles, ela apagaria de vez o que acabou de ir para lá, e a promessa de "vão para a
    # Lixeira" seria falsa.
    return @(
        # Antes de qualquer mudança, para poder voltar atrás.
        (New-TFToolkitPlanItem -Id "restore-point" -Phase Before -Title (Get-TFToolkitText 'Criar ponto de restauração')),
        # A lista do winget; a pessoa marca o que não usa.
        (New-TFToolkitPlanItem -Id "uninstall" -Phase Before -WithYou -Title (Get-TFToolkitText 'Desinstalar programas')),
        # Os que vêm com o PC; a pessoa marca o que remover.
        (New-TFToolkitPlanItem -Id "windows-apps" -Phase Before -WithYou -Title (Get-TFToolkitText 'Remover aplicativos do Windows')),
        # Uma lista só: marcado abre com o Windows.
        (New-TFToolkitPlanItem -Id "startup" -Phase Before -WithYou -Title (Get-TFToolkitText 'Revisar o que abre com o Windows')),
        # Uma pasta por vez: limpar, abrir no Explorador ou procurar duplicados.
        (New-TFToolkitPlanItem -Id "folders" -Phase Before -WithYou -Title (Get-TFToolkitText 'Organizar Downloads, Documentos e Imagens')),

        # Atualiza o antivírus e faz a verificação rápida do Windows Defender.
        (New-TFToolkitPlanItem -Id "security" -Phase Auto -Title (Get-TFToolkitText 'Verificar vírus')),
        # Só sem reinício pendente; com ele, fica para a próxima vez.
        (New-TFToolkitPlanItem -Id "components" -Phase Auto -Title (Get-TFToolkitText 'Limpar componentes do Windows (WinSxS)')),
        # O reparo completo, mesmo sem sinal de dano, antes das atualizações; não mexe nos arquivos da pessoa.
        (New-TFToolkitPlanItem -Id "repair" -Phase Auto -Title (Get-TFToolkitText 'Reparar o Windows (DISM + SFC)')),
        # As atualizações do Windows; drivers opcionais, prévias e uma versão nova ficam de fora.
        (New-TFToolkitPlanItem -Id "windows-update" -Phase Auto -Title (Get-TFToolkitText 'Atualizar o Windows')),
        # Procura hardware novo; o Windows instala o driver que já tiver para ele.
        (New-TFToolkitPlanItem -Id "drivers" -Phase Auto -Title (Get-TFToolkitText 'Detectar dispositivos e drivers')),
        # A pessoa escolhe o que atualizar antes da parte automática.
        (New-TFToolkitPlanItem -Id "winget" -Phase Auto -Title (Get-TFToolkitText 'Atualizar programas (winget)')),
        # Edge, Chrome e Firefox, os que estiverem instalados.
        (New-TFToolkitPlanItem -Id "browsers" -Phase Auto -Title (Get-TFToolkitText 'Atualizar os navegadores')),
        # O mesmo pedido do botão Obter atualizações; a Store instala em segundo plano.
        (New-TFToolkitPlanItem -Id "store" -Phase Auto -Title (Get-TFToolkitText 'Atualizar aplicativos da Microsoft Store')),
        # Temporários do usuário e do Windows; a Lixeira, só se a pessoa confirmar.
        (New-TFToolkitPlanItem -Id "cleanup" -Phase Auto -Title (Get-TFToolkitText 'Limpeza rápida')),
        # Vão para a Lixeira; os de pastas do OneDrive ficam.
        (New-TFToolkitPlanItem -Id "shortcuts" -Phase Auto -Title (Get-TFToolkitText 'Remover atalhos quebrados')),
        # Pastas de programas desinstalados pelo TF-Toolkit; a pessoa escolhe antes da parte automática.
        (New-TFToolkitPlanItem -Id "leftovers" -Phase Auto -Title (Get-TFToolkitText 'Restos de programas desinstalados')),
        # Limpa o DNS; refaz as configurações de rede só se a internet estiver falhando.
        (New-TFToolkitPlanItem -Id "network" -Phase Auto -Title (Get-TFToolkitText 'Reparar rede e DNS')),
        # Confere o disco com o Windows aberto; se precisar de reparo ao reiniciar, o Otimizar pergunta no fim.
        (New-TFToolkitPlanItem -Id "chkdsk" -Phase Auto -Title (Get-TFToolkitText 'Verificar o sistema de arquivos (CHKDSK)')),
        # Deixa o disco em ordem (TRIM no SSD, desfragmentação no HD).
        (New-TFToolkitPlanItem -Id "optimize" -Phase Auto -Title (Get-TFToolkitText 'Otimizar a unidade do sistema')),

        # Cada ajuste vem marcado se já está em uso; a pessoa marca o que aplicar.
        (New-TFToolkitPlanItem -Id "tweaks" -Phase After -WithYou -Title (Get-TFToolkitText 'Revisar os ajustes do Windows'))
    )
}


function Get-TFToolkitMaintenanceProfileLabel {
    # O nome do jeito como uma manutenção do histórico rodou: as da 3.50 e anteriores tinham perfil (Rápida, Completa,
    # Profunda); o Otimizar é um só. "" para um Id que esta versão não conhece.
    param ([AllowEmptyString()][string]$Id)

    $labels = @{ quick = (Get-TFToolkitText 'Rápida'); full = (Get-TFToolkitText 'Completa'); deep = (Get-TFToolkitText 'Profunda'); optimize = (Get-TFToolkitText 'Otimizar') }

    if ([string]::IsNullOrWhiteSpace($Id) -or -not $labels.ContainsKey($Id)) { return "" }

    return [string]$labels[$Id]
}


# ---------------------------------------------------------------------------
# Fase 1: preparação
# ---------------------------------------------------------------------------

function Test-TFToolkitWindowCloaked {
    <#
    Se a janela está "encoberta" (cloaked) pelo Windows: os aplicativos da Store pré-carregados ou suspensos e as janelas
    de outras áreas de trabalho virtuais têm janela e título, mas a pessoa não as vê nem tem o que fechar. Sem poder
    perguntar ao Windows, devolve falso (a janela conta).
    #>
    param ([IntPtr]$Handle)

    # A ponte que já falhou uma vez (fora do Windows, por exemplo) não é compilada de novo a cada processo da lista.
    if ($script:TFToolkitWindowNativeFailed) { return $false }

    try {
        if (-not ("TFToolkit.WindowNative" -as [type])) {
            Add-Type -namespace TFToolkit -Name WindowNative -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmGetWindowAttribute(System.IntPtr hwnd, int attribute, out int value, int size);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindowVisible(System.IntPtr hwnd);
'@ -ErrorAction Stop
        }

        if (-not [TFToolkit.WindowNative]::IsWindowVisible($Handle)) { return $true }

        $cloaked = 0
        # DWMWA_CLOAKED = 14
        if ([TFToolkit.WindowNative]::DwmGetWindowAttribute($Handle, 14, [ref]$cloaked, 4) -eq 0 -and $cloaked -ne 0) { return $true }
    }
    catch {
        $script:TFToolkitWindowNativeFailed = $true
        return $false
    }

    return $false
}


function Get-TFToolkitTopLevelWindows {
    <#
    As janelas que a barra de tarefas mostra (visíveis, sem dono, que não são janelas de ferramenta nem estão encobertas),
    com o processo e o título, numa passada só pelo Windows (EnumWindows): os aplicativos da Store, que aparecem pela
    janela do ApplicationFrameHost, entram pelo título. $null quando não dá para perguntar ao Windows (a ponte não
    compila ou a chamada falha): quem chama usa o caminho do Get-Process. A falha fica guardada, para não ser tentada de
    novo a cada conferência.
    #>
    if ($script:TFToolkitWindowListFailed) { return $null }

    try {
        if (-not ("TFToolkit.OpenWindows" -as [type])) {
            Add-Type -TypeDefinition $script:TFToolkitOpenWindowsSource -ErrorAction Stop
        }

        return , @([TFToolkit.OpenWindows]::List())
    }
    catch {
        $script:TFToolkitWindowListFailed = $true
        return $null
    }
}


function Get-TFToolkitFrameAppName {
    # O nome de um aplicativo da Store pelo título da janela que o ApplicationFrameHost desenha: "Calculadora", ou o fim de
    # "IMG_0042.jpg - Fotos". "" para as partes do Windows que usam a mesma moldura (as Configurações).
    param ([AllowEmptyString()][string]$Title)

    $name = ([string]$Title).Trim()
    $parts = @($name -split '\s+[-–—]\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -gt 1) { $name = ([string]$parts[$parts.Count - 1]).Trim() }

    # O título de alguns aplicativos começa com uma marca invisível de direção do texto.
    $name = $name.Trim([char]0x200E, [char]0x200F, ' ')

    if ($name -in @("Configurações", "Settings", "Configuración")) { return "" }

    return $name
}


function Get-TFToolkitOwnProcessIds {
    <#
    O próprio TF-Toolkit e a cadeia de quem o abriu (o PowerShell, o cmd). Um pai só conta se foi criado antes do filho: o
    número de um processo que já fechou (o PowerShell que pediu o Administrador e saiu) pode ter sido reaproveitado por
    um programa de verdade, que não pode sumir da lista.
    #>
    $own = New-Object System.Collections.Generic.HashSet[int]
    $id = [int]$PID
    $childStart = $null

    for ($i = 0; $i -lt 6 -and $id -gt 0; $i++) {
        try {
            # Com o serviço de WMI travado, a pergunta não pode segurar o Otimizar: 5 segundos e segue sem o pai.
            $row = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $id" -OperationTimeoutSec 5 -ErrorAction Stop
        }
        catch {
            break
        }

        if ($null -eq $row) { break }

        $start = Get-TFToolkitJsonValue -Object $row -Name "CreationDate" -Default $null
        if ($null -ne $childStart -and $null -ne $start -and [datetime]$start -gt [datetime]$childStart) { break }
        if (-not $own.Add($id)) { break }

        $childStart = $start
        $id = [int](Get-TFToolkitJsonValue -Object $row -Name "ParentProcessId" -Default 0)
    }

    [void]$own.Add([int]$PID)
    return , $own
}


function Get-TFToolkitOpenPrograms {
    <#
    Os programas com janela aberta na sessão de quem usa o PC, pelo nome que o Windows mostra (a descrição do arquivo,
    como "Google Chrome"; sem ela, o nome do processo), sem repetir e em ordem alfabética. Ficam de fora o próprio
    TF-Toolkit e quem o abriu, os terminais (no Windows 11, o Terminal que mostra o TF-Toolkit não é pai dele: fechá-lo
    fecharia o TF-Toolkit), as janelas encobertas (aplicativos da Store suspensos) e as partes do Windows e de drivers que
    sempre têm janela (Explorador, Iniciar, busca, teclado virtual, Configurações, Gerenciador de Tarefas, a sobreposição
    da NVIDIA). Sem poder ler os processos, devolve uma lista vazia.
    #>
    $shell = @("explorer", "ApplicationFrameHost", "TextInputHost", "ShellExperienceHost", "StartMenuExperienceHost", "SearchHost",
        "SearchApp", "SearchUI", "LockApp", "SystemSettings", "Taskmgr", "dwm", "ctfmon", "WidgetBoard", "Widgets", "PhoneExperienceHost",
        "WindowsTerminal", "OpenConsole", "conhost", "NVIDIA Overlay", "nvcontainer", "NVIDIA Share")

    $own = Get-TFToolkitOwnProcessIds

    try {
        $session = [int](Get-Process -Id $PID -ErrorAction Stop).SessionId
        $processes = @(Get-Process -ErrorAction Stop)
    }
    catch {
        return @()
    }

    $names = New-Object System.Collections.Generic.List[string]

    # O nome que o Windows mostra para um processo: a descrição do arquivo ("Google Chrome"); sem ela, o nome do processo.
    $displayName = {
        param ($Process)
        $text = ""
        try { $text = [string]$Process.Description } catch { $text = "" }
        if ([string]::IsNullOrWhiteSpace($text)) { $text = [string]$Process.ProcessName }
        return $text.Trim()
    }

    # O caminho principal: as janelas da barra de tarefas, numa passada só. Os filtros baratos (sessão, o próprio TF-Toolkit,
    # as partes do Windows) vêm antes de ler a descrição do arquivo.
    $windows = Get-TFToolkitTopLevelWindows

    if ($null -ne $windows) {
        $byId = @{}
        foreach ($process in $processes) { $byId[[int]$process.Id] = $process }

        foreach ($window in $windows) {
            try {
                $process = $byId[[int]$window.ProcessId]

                if ($null -eq $process) { continue }
                if ([int]$process.SessionId -ne $session -or $own.Contains([int]$process.Id)) { continue }

                $processName = [string]$process.ProcessName

                if ($processName -eq "ApplicationFrameHost") { $name = Get-TFToolkitFrameAppName -Title ([string]$window.Title) }
                elseif ($shell -contains $processName) { continue }
                else { $name = & $displayName $process }

                if (-not [string]::IsNullOrWhiteSpace($name) -and -not $names.Contains($name)) { $names.Add($name) }
            }
            catch {
                continue
            }
        }

        return @($names | Sort-Object)
    }

    # Sem a ponte com o Windows: a janela principal de cada processo, como o Gerenciador de Tarefas antigo.
    foreach ($process in $processes) {
        try {
            if ([int]$process.SessionId -ne $session -or $own.Contains([int]$process.Id)) { continue }
            if ($shell -contains [string]$process.ProcessName) { continue }
            if ($process.MainWindowHandle -eq [IntPtr]::Zero -or [string]::IsNullOrWhiteSpace([string]$process.MainWindowTitle)) { continue }
            if (Test-TFToolkitWindowCloaked -Handle $process.MainWindowHandle) { continue }

            $name = & $displayName $process

            if (-not $names.Contains($name)) { $names.Add($name) }
        }
        catch {
            continue
        }
    }

    return @($names | Sort-Object)
}


function Format-TFToolkitOpenPrograms {
    # "Google Chrome, Microsoft Word e Spotify"; com mais de seis, os seis primeiros e "e mais N".
    param ([string[]]$Names)

    $list = @($Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($list.Count -le 6) { return (Join-TFToolkitList -Items $list) }

    return (Get-TFToolkitText '{0} e mais {1}' "$(@($list[0..5]) -join ', ')" "$($list.Count - 6)")
}


function Confirm-TFToolkitProgramsClosed {
    # A sugestão forte de fechar tudo antes de começar: o Otimizar atualiza e repara o Windows, e um programa aberto
    # atrapalha (arquivo em uso, atualização que não instala) e pode perder o que não foi salvo no reinício do fim. A
    # lista do que está aberto deixa a pergunta concreta (numa linha só com o aviso); começar com algo ainda aberto pede
    # uma segunda resposta.
    $open = @(Get-TFToolkitOpenPrograms)

    if ($open.Count -gt 0) {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Salve seu trabalho e feche os programas abertos: {0}.' "$(Format-TFToolkitOpenPrograms -Names $open)")
    }
    else {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Salve seu trabalho e feche todos os programas antes de otimizar.')
    }

    # Uma entrada que terminou (Ctrl+Z, entrada redirecionada) faz a pergunta desistir: conta como cancelar, sem derrubar
    # o Otimizar. Por isso o "começar" só é a resposta do Enter na janela, onde a entrada não termina: lá, o Enter faz o
    # mesmo que o botão em destaque.
    try {
        $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Fechou todos os programas?') -ShowMenu -DefaultKey $(if (Test-TFToolkitGuiMode) { "S" } else { "" }) -TextPrompt (Get-TFToolkitText 'Opção (S = já fechei, começar; X = cancelar)') -Options @(
            @{ Key = "S"; Label = (Get-TFToolkitText 'Já fechei, começar'); Accent = $true },
            @{ Key = "X"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }
        )

        while ($answer -ieq "S" -or $answer -ieq "V") {
            $open = @(Get-TFToolkitOpenPrograms)

            if ($open.Count -eq 0) { return $true }

            Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Ainda abertos: {0}.' "$(Format-TFToolkitOpenPrograms -Names $open)")

            $answer = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Fechar esses programas antes?') -ShowMenu -TextPrompt (Get-TFToolkitText 'Opção (V = verificar de novo, C = começar assim mesmo, X = cancelar)') -Options @(
                @{ Key = "V"; Label = (Get-TFToolkitText 'Já fechei, verificar de novo'); Accent = $true },
                @{ Key = "C"; Label = (Get-TFToolkitText 'Começar assim mesmo') },
                @{ Key = "X"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }
            )

            if ($answer -ieq "C") { return $true }
        }
    }
    catch {
        return $false
    }

    return $false
}


function Confirm-TFToolkitMaintenancePreflight {
    # O que pode atrapalhar, em uma linha cada: outra conta, reinício pendente, bateria, pouco espaço e, por último, os
    # programas abertos. Devolve verdadeiro para começar, falso para cancelar ou "Restarting".
    $session = Get-TFToolkitSessionInfo

    if ($session.UserMismatch) {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'O TF-Toolkit foi aberto com a senha de outra conta: pastas, inicialização e ajustes vão valer para aquela conta.')

        if (-not (Confirm-TFToolkitAction (Get-TFToolkitText 'Continuar mesmo assim?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Continuar') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            return $false
        }
    }

    if (Test-TFToolkitPendingReboot) {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'O Windows está esperando um reinício.')

        $answer = Read-TFToolkitPendingRebootChoice -Question (Get-TFToolkitText 'Reiniciar antes de otimizar?') -Then (Get-TFToolkitText 'Depois, clique em Otimizar de novo') `
            -Reason (Get-TFToolkitText 'Depois de reiniciar, clique em Otimizar de novo.') -Comment (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit antes do Otimizar.') `
            -DeclinedMessage (Get-TFToolkitText 'O PC não foi reiniciado; o Otimizar não começou.')

        if ($answer -eq "Restarting") {
            return "Restarting"
        }

        if ($answer -ne "Continue") {
            return $false
        }
    }

    if (Test-TFToolkitOnBattery) {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Ligue o carregador: o Otimizar pode levar mais de uma hora.')

        if (-not (Confirm-TFToolkitAction (Get-TFToolkitText 'Continuar na bateria?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Continuar') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            return $false
        }
    }

    $freeBytes = Get-TFToolkitSystemDriveFreeBytes

    if ((Get-TFToolkitDiskSpaceLevel -FreeBytes $freeBytes) -eq "Critical") {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Pouco espaço livre no disco do Windows ({0}): as atualizações podem falhar.' "$(Format-TFToolkitBytes -Bytes $freeBytes)")
    }

    return (Confirm-TFToolkitProgramsClosed)
}


# ---------------------------------------------------------------------------
# Fase 4: as perguntas da parte automática
# ---------------------------------------------------------------------------

function New-TFToolkitMaintenanceDetails {
    # As respostas que a parte automática usa, ainda sem nenhuma (Read-TFToolkitMaintenanceDetails as preenche): o que
    # atualizar no winget, se a Lixeira é esvaziada, os restos escolhidos (e o resultado da busca deles) e se as etapas
    # que baixam programas ficam para depois (numa conexão limitada).
    return [PSCustomObject]@{ WingetPlan = $null; EmptyRecycleBin = $false; Leftovers = @(); LeftoversResult = $null; SkipDownloads = $false }
}


function Read-TFToolkitMaintenanceDetails {
    # Tudo o que as etapas automáticas precisam saber, perguntado de uma vez, para a parte demorada rodar sem ninguém por
    # perto: numa conexão limitada, se baixa os programas; o que atualizar no winget, que restos de programas mandar para
    # a Lixeira e se a Lixeira é esvaziada.
    param (
        [string[]]$AutoIds,

        # A consulta do winget já começada em segundo plano (Start-TFToolkitWingetUpgradeRead), enquanto a pessoa estava
        # nas telas do começo: a lista chega sem espera, com o prazo da consulta. Sem ela, a consulta roda aqui.
        $WingetRead = $null
    )

    $details = New-TFToolkitMaintenanceDetails

    # Numa conexão limitada (plano de dados), o Windows baixa só as atualizações prioritárias e pode pausar as da
    # Microsoft Store: baixar os programas, os navegadores e os aplicativos da Store é decisão da pessoa, com Deixar para
    # depois como padrão. O Windows Update segue, na etapa dele, a regra do próprio Windows (Install-TFToolkitPendingUpdates).
    if (@($AutoIds | Where-Object { $_ -in @("winget", "browsers", "store") }).Count -gt 0 -and (Test-TFToolkitMeteredConnection)) {
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'A conexão com a internet está marcada como limitada (plano de dados): {0} pode consumir a sua franquia.' "$(Get-TFToolkitText 'atualizar os programas, os navegadores e os aplicativos da Store')")
        $details.SkipDownloads = -not [bool](Confirm-TFToolkitAction (Get-TFToolkitText 'Atualizar os programas mesmo assim?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Atualizar mesmo assim') -NoLabel (Get-TFToolkitText 'Deixar para depois'))
    }

    if ($AutoIds -contains "winget" -and -not $details.SkipDownloads) {
        if (-not (Test-TFToolkitWinget)) {
            # Sem o winget, o começo do Otimizar já ofereceu o reparo e disse que as etapas dele ficam de fora: a etapa
            # diz isso de novo na vez dela, sem repetir aqui a falta dele.
            $details.WingetPlan = [PSCustomObject]@{ Action = "Unavailable"; Ids = @(); Packages = @() }
        }
        else {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Atualizar programas (winget)')

            # Edge, Chrome e Firefox ficam com a etapa dos navegadores, pelo atualizador de cada um: na lista do winget,
            # um "Não atualizar" ou um Firefox desmarcado seria desfeito por ela, e "Atualizar todos" os atualizaria duas
            # vezes.
            try {
                $details.WingetPlan = Get-TFToolkitWingetUpgradePlan -SkipBrowsers -Read $WingetRead
            }
            catch {
                $why = ([string]$_.Exception.Message).Trim().TrimEnd('.')
                Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível consultar o winget: {0}.' "$why")
                $details.WingetPlan = [PSCustomObject]@{ Action = "Error"; Detail = $why; Ids = @(); Packages = @() }
            }
        }
    }

    # Os restos são procurados agora, depois das desinstalações do começo: os programas que acabaram de sair entram.
    if ($AutoIds -contains "leftovers") {
        Write-TFToolkitSection -Title (Get-TFToolkitText 'Restos de programas desinstalados')

        try {
            $selection = Select-TFToolkitProgramLeftovers
            $details.Leftovers = @($selection.Chosen)
            $details.LeftoversResult = $selection.Result
        }
        catch {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível procurar os restos: {0}.' "$($_.Exception.Message.TrimEnd('.'))")
            $details.LeftoversResult = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message.TrimEnd('.')
        }
    }

    # A Lixeira é a última chance de recuperar um arquivo apagado por engano: esvaziá-la é uma decisão da pessoa, com o
    # que há nela à vista, e não um efeito da limpeza automática.
    if ($AutoIds -contains "cleanup") {
        $bin = $null
        try { $bin = Get-TFToolkitRecycleBinContents } catch { $bin = $null }

        if ($null -eq $bin -or [int]$bin.Count -gt 0) {
            Write-TFToolkitSection -Title (Get-TFToolkitText 'Lixeira')

            if ($null -ne $bin) { Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Na Lixeira') -Value (Format-TFToolkitRecycleBinText -Contents $bin) }

            # Na janela, os botões dizem o que fazem; "Manter" é a saída segura e a resposta do Enter.
            $details.EmptyRecycleBin = [bool](Confirm-TFToolkitAction (Get-TFToolkitText 'Esvaziar a Lixeira? O que está nela é apagado de vez.') -DefaultKey N -YesLabel (Get-TFToolkitText 'Esvaziar') -NoLabel (Get-TFToolkitText 'Manter'))
        }
    }

    return $details
}


function Confirm-TFToolkitAutomaticPhase {
    # O último clique antes da parte demorada: ela roda sem perguntas, e a pessoa pode sair de perto até a revisão dos
    # ajustes, no fim.
    Write-Host ""
    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'A parte automática segue sozinha e pode levar mais de uma hora. No fim, falta revisar os ajustes.')

    # Uma entrada que terminou (Ctrl+Z, entrada redirecionada) conta como "não": as telas com você já mudaram o PC, e o
    # resumo e o fim do Otimizar ainda têm de aparecer. Na janela, o Enter faz o mesmo que o botão em destaque.
    try {
        $start = Read-TFToolkitChoice -Message (Get-TFToolkitText 'Começar a parte automática?') -ShowMenu -DefaultKey $(if (Test-TFToolkitGuiMode) { "S" } else { "" }) -TextPrompt (Get-TFToolkitText 'Opção (S = começar, X = cancelar)') -Options @(
            @{ Key = "S"; Label = (Get-TFToolkitText 'Começar'); Accent = $true },
            @{ Key = "X"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }
        )
    }
    catch {
        return $false
    }

    return ($start -ieq "S")
}


# ---------------------------------------------------------------------------
# As etapas
# ---------------------------------------------------------------------------

function ConvertTo-TFToolkitStepResult {
    # O resultado de uma tela com você no resumo do Otimizar: desistir da lista ("cancelado pelo usuário") não é uma
    # operação cancelada, é escolher não mudar nada naquela etapa.
    param ([Parameter(Mandatory)]$Result)

    if ([string]$Result.Kind -eq "Skipped" -and (Test-TFToolkitCanceledText -Text ([string](Get-TFToolkitJsonValue -Object $Result -Name "Detail" -Default "")))) {
        return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nada mudou') -Data $Result.Data)
    }

    return $Result
}


function Invoke-TFToolkitMaintenanceShortcuts {
    # A etapa dos atalhos quebrados: a mesma correção de Verificar o PC (para a Lixeira, anotada no Histórico de
    # mudanças). Os de pastas do OneDrive ficam de fora: o atalho apagado aqui some também dos outros PCs da pessoa.
    $title = (Get-TFToolkitText 'Remover atalhos quebrados')

    Write-Progress -Activity $title -Status (Get-TFToolkitText 'conferindo os atalhos')

    try { $broken = @(Find-TFToolkitBrokenShortcuts | Where-Object { -not [bool](Get-TFToolkitJsonValue -Object $_ -Name "Synced" -Default $false) }) }
    finally { Write-Progress -Activity $title -Completed }

    if ($broken.Count -eq 0) {
        Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Nenhum atalho quebrado.')
        return (New-TFToolkitResult -Kind Ok -Detail (Get-TFToolkitText 'nenhum atalho quebrado'))
    }

    foreach ($shortcut in $broken) {
        Write-TFToolkitKeyValue -Label $shortcut.Name -Value (Get-TFToolkitText 'aponta para {0}, que não existe mais' "$($shortcut.Target)")
    }

    $finding = New-TFToolkitCheckupFinding -Id "shortcuts" -Label (Get-TFToolkitText 'Atalhos') -Value (Format-TFToolkitCount -Count $broken.Count -One (Get-TFToolkitText 'atalho quebrado') -Many (Get-TFToolkitText 'atalhos quebrados')) -Fix "shortcuts" -FixLabel $title -Data $broken
    $result = Invoke-TFToolkitCheckupFix -Finding $finding
    $detail = [string]$result.Detail

    if ($result.Kind -eq "Ok" -and $detail) { Write-TFToolkitStatus -Type Success -Message "$($detail.Substring(0, 1).ToUpper())$($detail.Substring(1))." }

    return $result
}


function Repair-TFToolkitMaintenanceWinget {
    <#
    O começo do Otimizar sem o Instalador de Aplicativo (o winget), comum logo depois de formatar: desinstalar e atualizar
    os programas dependem dele. Com a pessoa presente, ele oferece repará-lo ali mesmo, com Reparar como padrão, pelo
    mesmo registro de Programas > Reparar o Instalador de Aplicativo e da restauração de um backup (Register-TFToolkitWinget).
    Elevado com outra conta, não oferece: o registro valeria para ela, e não para quem usa o PC. Devolve verdadeiro quando
    ele passou a responder; sem ele, diz uma vez que as etapas dele ficam de fora e onde repará-lo depois.
    #>
    Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Falta o Instalador de Aplicativo (winget), que o TF-Toolkit usa para desinstalar e atualizar os programas.')

    if (-not (Test-TFToolkitUserContextMismatch) -and (Confirm-TFToolkitAction -Message (Get-TFToolkitText 'Reparar o Instalador de Aplicativo agora?') -DefaultKey S -YesLabel (Get-TFToolkitText 'Reparar') -NoLabel (Get-TFToolkitText 'Agora não'))) {
        $registration = Register-TFToolkitWinget

        if ($registration.Version) {
            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O Instalador de Aplicativo voltou a funcionar ({0}).' "$($registration.Version)")
            return $true
        }

        Write-TFToolkitStatus -Type Warning -Message $(if ($registration.Problem) { (Get-TFToolkitText 'O registro não resolveu: {0}.' "$($registration.Problem)") } else { (Get-TFToolkitText 'O registro terminou, mas o winget continua sem responder.') })
    }

    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Desinstalar e atualizar os programas ficam de fora. Para reparar o Instalador de Aplicativo depois, use Programas > Reparar o Instalador de Aplicativo.')

    return $false
}


function Skip-TFToolkitMeteredStep {
    # Uma etapa que baixaria programas, numa conexão limitada em que a pessoa escolheu Deixar para depois: ela diz isso
    # e fica de fora, sem baixar nada.
    param ([Parameter(Mandatory)][string]$Title)

    Enter-TFToolkitAction -Title $Title -Embedded
    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'A conexão é limitada (plano de dados): a etapa fica para uma conexão sem limite.')

    return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'conexão limitada: fica para uma conexão sem limite'))
}


function Invoke-TFToolkitMaintenanceStepAction {
    param (
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        $Details
    )

    switch ($Id) {
        # A pessoa está presente no começo: sem a Proteção do Sistema, o ponto oferece ligá-la (Não como padrão).
        "restore-point" { Invoke-TFToolkitRestorePoint -Embedded -PassThru -OfferProtection -Description (Get-TFToolkitText 'TF-Toolkit - antes do Otimizar') }
        "uninstall" {
            # Sem o winget, o reparo vem antes (Repair-TFToolkitMaintenanceWinget): a tela de desinstalar, sem ele, diria em
            # vermelho que ele falta e perguntaria se abre a Microsoft Store, no meio do Otimizar.
            if (-not (Test-TFToolkitWinget) -and -not (Repair-TFToolkitMaintenanceWinget)) {
                New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'winget não encontrado')
            }
            else {
                $uninstall = Invoke-TFToolkitNestedAction -Command "Uninstall-TFToolkitSoftware"

                # Sem o winget mesmo assim (ele sumiu, ou não respondeu), a tela não tem como rodar: não é uma falha do
                # Otimizar, como na etapa do winget.
                if ($null -ne $uninstall -and [string]$uninstall.Kind -eq "Failed" -and [string]$uninstall.Detail -eq (Get-TFToolkitWingetMissingDetail)) {
                    New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'winget não encontrado')
                }
                else {
                    ConvertTo-TFToolkitStepResult -Result $uninstall
                }
            }
        }
        "windows-apps"  { ConvertTo-TFToolkitStepResult -Result (Invoke-TFToolkitNestedAction -Command "Remove-TFToolkitPreinstalledApps") }
        "startup"       { ConvertTo-TFToolkitStepResult -Result (Invoke-TFToolkitNestedAction -Command "Set-TFToolkitStartupItems" -Arguments @{ Review = $true }) }
        "folders"       { Invoke-TFToolkitFolderReview -Embedded -PassThru }
        "security"      { Invoke-TFToolkitSecurityCheck -Embedded -PassThru }
        "windows-update" { Install-TFToolkitPendingUpdates -Embedded -PassThru }
        "drivers"       { Invoke-TFToolkitDeviceScan -Embedded -PassThru }
        "winget" {
            if ([bool](Get-TFToolkitJsonValue -Object $Details -Name "SkipDownloads" -Default $false)) { return (Skip-TFToolkitMeteredStep -Title (Get-TFToolkitText 'Atualizar programas (winget)')) }

            Enter-TFToolkitAction -Title (Get-TFToolkitText 'Atualizar programas (winget)') -Embedded

            if ($null -eq $Details.WingetPlan) {
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'As atualizações do winget não foram revisadas nesta execução.')
                New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'não revisado')
            }
            elseif ([string]$Details.WingetPlan.Action -eq "Unavailable") {
                # Sem o winget no PC, a etapa não tem como rodar: não é uma falha do Otimizar (nem um "problema repetido"
                # no histórico a cada mês). Onde repará-lo, o começo do Otimizar já disse.
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Falta o Instalador de Aplicativo (winget): a etapa foi ignorada.')
                New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'winget não encontrado')
            }
            else {
                # "Não atualizar" é escolher não mudar nada nesta etapa, como desistir de uma tela com você.
                ConvertTo-TFToolkitStepResult -Result (Invoke-TFToolkitWingetUpgradePlan -Plan $Details.WingetPlan)
            }
        }
        "browsers" {
            if ([bool](Get-TFToolkitJsonValue -Object $Details -Name "SkipDownloads" -Default $false)) { Skip-TFToolkitMeteredStep -Title (Get-TFToolkitText 'Atualizar os navegadores') }
            else { Update-TFToolkitBrowsers -Embedded -PassThru }
        }
        "store" {
            if ([bool](Get-TFToolkitJsonValue -Object $Details -Name "SkipDownloads" -Default $false)) { Skip-TFToolkitMeteredStep -Title (Get-TFToolkitText 'Atualizar aplicativos da Microsoft Store') }
            else { Update-TFToolkitStoreApps -Embedded -PassThru }
        }
        "shortcuts"     { Invoke-TFToolkitMaintenanceShortcuts }
        "leftovers" {
            $chosen = @(Get-TFToolkitJsonValue -Object $Details -Name "Leftovers" -Default @() | Where-Object { $null -ne $_ })
            $earlier = Get-TFToolkitJsonValue -Object $Details -Name "LeftoversResult" -Default $null

            if ($chosen.Count -gt 0) {
                Remove-TFToolkitProgramLeftovers -Items $chosen
            }
            elseif ($null -ne $earlier) {
                # A busca já disse o que houve (nenhum programa, nenhum resto, desistência): esse é o resultado da etapa.
                ConvertTo-TFToolkitStepResult -Result $earlier
            }
            else {
                New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nenhuma pasta escolhida')
            }
        }
        "components" {
            # Com a manutenção dos componentes esperando o reinício (uma atualização que o Windows instalou sozinho), o DISM
            # recusa a limpeza (0x800F0806): ela fica para a próxima vez, sem virar uma falha. Os outros motivos de reinício
            # (um driver, um nome novo do PC) não atrapalham o DISM e não seguram a etapa.
            if (Test-TFToolkitServicingRebootPending) {
                Enter-TFToolkitAction -Title (Get-TFToolkitText 'Limpar componentes do Windows (WinSxS)') -Embedded
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Há um reinício pendente: o Windows só limpa os componentes depois de reiniciar. A limpeza fica para o próximo Otimizar.')
                New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'reinício pendente; fica para depois de reiniciar')
            }
            else {
                Invoke-TFToolkitComponentCleanup -Embedded -PassThru
            }
        }
        "cleanup" {
            if ([bool](Get-TFToolkitJsonValue -Object $Details -Name "EmptyRecycleBin" -Default $false)) { Invoke-TFToolkitQuickCleanup -Embedded -PassThru }
            else { Invoke-TFToolkitQuickCleanup -Embedded -PassThru -SkipRecycleBin }
        }
        "network"       { Invoke-TFToolkitNetworkRepair -Embedded -PassThru -Force }
        # Sem -CheckFirst: o Otimizar roda o DISM /RestoreHealth sempre, mesmo sem sinal de dano. Com a manutenção dos
        # componentes esperando o reinício, o DISM recusa o reparo (0x800F0806) e o SFC também: a etapa fica para depois de
        # reiniciar, sem virar uma falha.
        "repair" {
            if (Test-TFToolkitServicingRebootPending) {
                Enter-TFToolkitAction -Title (Get-TFToolkitText 'Reparar o Windows (DISM + SFC)') -Embedded
                Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Há um reinício pendente: o DISM e o SFC só reparam depois de reiniciar. Depois do reinício, use Reparo > Reparar o Windows (DISM + SFC).')
                New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'reinício pendente; rode depois de reiniciar')
            }
            else {
                Invoke-TFToolkitDismAndSfc -Embedded -PassThru
            }
        }
        "chkdsk"        { Start-TFToolkitChkdsk -DeferRepairPrompt -Embedded -PassThru }
        "optimize"      { Start-TFToolkitDriveOptimization -Embedded -PassThru }
        "tweaks"        { Invoke-TFToolkitTweakReview -Embedded -PassThru }
        default         { throw "Etapa desconhecida: $Id" }
    }
}


function Invoke-TFToolkitMaintenanceStep {
    # Roda uma etapa e devolve exatamente um TFToolkit.Result, aconteça o que acontecer dentro dela.
    param (
        [Parameter(Mandatory)]
        $Step,

        [Parameter(Mandatory)]
        $Details,

        [int]$Position,
        [int]$Total
    )

    Write-Host ""

    if (Test-TFToolkitGuiMode) {
        # Na janela, "Etapa 3 de 21: ..." fica em destaque no alto da tela de execução e vira um subtítulo do resumo.
        Write-TFToolkitSubStep -Title (Get-TFToolkitText 'Etapa {0} de {1}: {2}' "$Position" "${Total}" "$($Step.Title)")
    }
    else {
        Write-TFToolkitProgress -Current ($Position - 1) -Total $Total -Label (Get-TFToolkitText 'Próxima: {0}' "$($Step.Title)")
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = $null

    try {
        $output = @(Invoke-TFToolkitMaintenanceStepAction -Id $Step.Id -Details $Details)

        $results = @($output | Where-Object { $null -ne $_ -and $_.PSObject.TypeNames -contains "TFToolkit.Result" })
        $others = @($output | Where-Object { $null -ne $_ -and -not ($_.PSObject.TypeNames -contains "TFToolkit.Result") })

        # Texto ou objetos soltos de uma etapa aparecem na tela, mas nunca entram no resumo.
        if ($others.Count -gt 0) {
            $others | Out-Host
        }

        if ($results.Count -gt 0) {
            $result = $results[$results.Count - 1]
        }
        else {
            $result = New-TFToolkitResult -Kind Ok
        }
    }
    catch {
        Write-Host ""
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Falha nesta etapa ({0}): {1}' "$($Step.Title)" "$($_.Exception.Message)")

        # Na última etapa não há "próxima": a frase prometeria uma etapa que não vem.
        if ($Position -lt $Total) { Write-Host (Get-TFToolkitText '      O TF-Toolkit continuará para a próxima etapa.') -ForegroundColor DarkGray }

        $result = New-TFToolkitResult -Kind Failed -Detail $_.Exception.Message
    }

    $stopwatch.Stop()

    $result.Etapa = $Step.Title
    $result.Duracao = Format-TFToolkitDuration -Span $stopwatch.Elapsed
    Add-Member -InputObject $result -NotePropertyName "StepId" -NotePropertyValue $Step.Id -Force

    return $result
}


function Invoke-TFToolkitMaintenancePhase {
    # Roda as etapas pedidas de uma fase (StepIds), na ordem do plano. Start: a posição da primeira (a numeração "Etapa N
    # de M" corre pelo Otimizar inteiro); Total: quantas etapas o Otimizar tem ao todo. A parte automática (-KeepAwake)
    # impede o Windows de suspender o PC no meio das atualizações, do DISM e do CHKDSK.
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Before", "Auto", "After")]
        [string]$Phase,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$StepIds,

        [Parameter(Mandatory)]
        $Details,

        [int]$Start = 1,
        [int]$Total = 0,

        [switch]$KeepAwake
    )

    $catalog = @(Get-TFToolkitMaintenancePlanItems | Where-Object { $_.Phase -eq $Phase })
    $steps = @($catalog | Where-Object { $StepIds -contains $_.Id })
    $results = @()

    if ($Total -lt ($Start + $steps.Count - 1)) { $Total = $Start + $steps.Count - 1 }

    if ($KeepAwake) { [void](Set-TFToolkitKeepAwake -Enabled $true) }

    try {
        $position = $Start - 1

        foreach ($step in $steps) {
            $position++
            $results += @(Invoke-TFToolkitMaintenanceStep -Step $step -Details $Details -Position $position -Total $Total)
        }
    }
    finally {
        if ($KeepAwake) { [void](Set-TFToolkitKeepAwake -Enabled $false) }
    }

    return @($results)
}


# ---------------------------------------------------------------------------
# Antes e depois
# ---------------------------------------------------------------------------

function Get-TFToolkitMaintenanceSnapshot {
    # Uma foto do PC para comparar o começo com o fim da manutenção: espaço livre no disco do sistema e quantos
    # programas abrem junto com o Windows. O que não puder ser lido fica $null e some da comparação.
    $freeBytes = $null
    $startupItems = $null

    try {
        $space = Get-TFToolkitSystemDriveSpace
        if ($null -ne $space) { $freeBytes = [int64]$space.FreeBytes }
    }
    catch {
        $freeBytes = $null
    }

    try {
        $startupItems = [int]@(Get-TFToolkitStartupItems | Where-Object { $_.Enabled }).Count
    }
    catch {
        $startupItems = $null
    }

    return [PSCustomObject]@{ At = (Get-Date); FreeBytes = $freeBytes; StartupItems = $startupItems }
}


function Format-TFToolkitSignedBytes {
    # "+11,5 GB" / "-2 GB"; menos de 1 MB de diferença conta como "sem mudança".
    param ([int64]$Delta)

    if ([math]::Abs($Delta) -lt 1MB) {
        return (Get-TFToolkitText 'sem mudança')
    }

    $sign = $(if ($Delta -gt 0) { "+" } else { "-" })

    return "$sign$(Format-TFToolkitBytes -Bytes ([math]::Abs($Delta)))"
}


function Get-TFToolkitSnapshotComparison {
    # As linhas "antes e depois" (Label e Text) entre duas fotos. Linha cujo dado falta em uma das fotos não aparece.
    param (
        $Before,
        $After
    )

    $rows = @()

    if ($null -eq $Before -or $null -eq $After) {
        return @()
    }

    if ($null -ne $Before.FreeBytes -and $null -ne $After.FreeBytes) {
        $rows += [PSCustomObject]@{
            Label = (Get-TFToolkitText 'Espaço livre no disco do sistema')
            Text  = (Get-TFToolkitText 'de {0} para {1} ({2})' "$(Format-TFToolkitBytes -Bytes $Before.FreeBytes)" "$(Format-TFToolkitBytes -Bytes $After.FreeBytes)" "$(Format-TFToolkitSignedBytes -Delta ([int64]$After.FreeBytes - [int64]$Before.FreeBytes))")
        }
    }

    if ($null -ne $Before.StartupItems -and $null -ne $After.StartupItems) {
        $delta = [int]$After.StartupItems - [int]$Before.StartupItems
        $change = $(if ($delta -eq 0) { (Get-TFToolkitText 'sem mudança') } elseif ($delta -gt 0) { "+$delta" } else { "$delta" })

        $rows += [PSCustomObject]@{
            Label = (Get-TFToolkitText 'Programas que abrem com o Windows')
            Text  = (Get-TFToolkitText 'de {0} para {1} ({2})' "$($Before.StartupItems)" "$($After.StartupItems)" "$change")
        }
    }

    return @($rows)
}


# ---------------------------------------------------------------------------
# Resumo e encerramento
# ---------------------------------------------------------------------------

function Show-TFToolkitMaintenanceSummary {
    param (
        [object[]]$Results,
        [datetime]$StartedAt,

        # Fotos do PC no começo e no fim (Get-TFToolkitMaintenanceSnapshot); sem elas não há comparação.
        $Before = $null,
        $After = $null,

        # Como rodou (optimize; as manutenções antigas guardavam quick, full ou deep), para o histórico.
        [string]$ProfileId = "optimize",

        # O desfecho já calculado por quem chama (com a parte automática cancelada, por exemplo); sem ele, a conta é a de
        # Get-TFToolkitMaintenanceResult, a mesma da faixa de resultado.
        $Verdict = $null,

        # Não grava no histórico nem como última manutenção (a parte automática foi cancelada: segurança, atualizações e
        # reparos não rodaram, e o Início deve continuar lembrando do Otimizar).
        [switch]$NoRecord,

        # A execução, para a gravação do fim substituir a do meio (Set-TFToolkitLastMaintenance -RunId).
        [string]$RunId = ""
    )

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Resumo')

    # Só resultados formais de etapa compõem a tabela.
    $summaryResults = @($Results | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["Etapa"] -and $null -ne $_.PSObject.Properties["Status"] })

    Write-TFToolkitResultTable -Results $summaryResults

    if (-not $NoRecord) {
        Set-TFToolkitLastMaintenance -Results $summaryResults -StartedAt $StartedAt -Before $Before -After $After -ProfileId $ProfileId -RunId $RunId
    }

    $comparison = @(Get-TFToolkitSnapshotComparison -Before $Before -After $After)

    if ($comparison.Count -gt 0) {
        Write-TFToolkitSection -Title (Get-TFToolkitText 'Antes e depois')

        foreach ($row in $comparison) {
            Write-TFToolkitKeyValue -Label $row.Label -Value $row.Text -LabelWidth 34
        }
    }

    # Na janela, o desfecho e a duração ficam na faixa de resultado e ao lado do título: repetidos no resumo, eram três
    # vezes a mesma informação na mesma tela.
    if (Test-TFToolkitGuiMode) { return }

    Write-Host ""

    # A mesma conta da faixa de resultado (Get-TFToolkitMaintenanceResult): tudo ignorado não é "tudo concluído".
    if ($null -eq $Verdict) { $Verdict = Get-TFToolkitMaintenanceResult -Results $summaryResults -Before $Before -After $After }
    $detail = [string]$Verdict.Detail
    $sentence = $(if ($detail) { $detail.Substring(0, 1).ToUpper() + $detail.Substring(1) } else { "" })

    switch ([string]$Verdict.Kind) {
        "Ok" { Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Otimização concluída: {0}.' "$detail") }
        "Skipped" { Write-TFToolkitStatus -Type Info -Message "$sentence." }
        "Failed" { Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText '{0}. Veja acima o que cada etapa disse.' "$sentence") }
        default { Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText '{0}. Veja acima o que cada etapa disse.' "$sentence") }
    }

    # O caminho do log fica no botão "Abrir log" dos detalhes técnicos (e no Sobre): o resumo diz só a duração.
    Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Duração: {0}.' "$(Format-TFToolkitDuration -Span ((Get-Date) - $StartedAt))")
}


function Test-TFToolkitMaintenanceNeedsRestart {
    param (
        [object[]]$Results,
        [bool]$ChkdskScheduled
    )

    if ($ChkdskScheduled) {
        return $true
    }

    if (Test-TFToolkitPendingReboot) {
        return $true
    }

    foreach ($result in @($Results)) {
        if ($null -eq $result) { continue }

        # Cada etapa avisa por Data quando uma mudança só termina depois de reiniciar: as atualizações do Windows, o
        # reparo de rede (quando os resets de Winsock e TCP/IP funcionaram), o DISM e o SFC, quando o reparo pede, e um
        # ajuste que só vale depois de reiniciar.
        if (Test-TFToolkitResultFlag -Result $result -Name "RebootRequired") {
            return $true
        }
    }

    return $false
}


function Read-TFToolkitPendingRebootChoice {
    <#
    Com o Windows esperando um reinício, antes do que ele atrapalha (o Otimizar, as atualizações, os drivers e o reparo do
    Windows Update): uma escolha só, com a saída que resolve à mão (Reiniciar agora, Continuar sem reiniciar ou Cancelar).
    Um Sim/Não terminaria em "cancelada" sem oferecer o reinício. Reiniciar agora ainda pede a confirmação do reinício
    (Request-TFToolkitRestart, com Depois como padrão). Then: a descrição de Reiniciar agora; Reason, Comment e
    DeclinedMessage vão para Request-TFToolkitRestart. Devolve "Restarting" (o reinício começou), "Continue" ou
    "Cancelled" (a pessoa desistiu, ou não confirmou o reinício).
    #>
    param (
        [Parameter(Mandatory)][string]$Question,
        [Parameter(Mandatory)][string]$Then,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$Comment,
        [Parameter(Mandatory)][string]$DeclinedMessage
    )

    $answer = Read-TFToolkitChoice -Message $Question -DefaultKey "R" -ShowMenu `
        -TextPrompt (Get-TFToolkitText 'Opção (R = reiniciar agora, C = continuar sem reiniciar, X = cancelar; ENTER = reiniciar agora)') -Options @(
        @{ Key = "R"; Label = (Get-TFToolkitText 'Reiniciar agora'); Description = $Then; Accent = $true },
        @{ Key = "C"; Label = (Get-TFToolkitText 'Continuar sem reiniciar') },
        @{ Key = "X"; Label = (Get-TFToolkitText 'Cancelar'); Exit = $true }
    )

    if ($answer -ieq "C") { return "Continue" }
    if ($answer -ine "R") { return "Cancelled" }

    if (Request-TFToolkitRestart -Reason $Reason -Comment $Comment -DeclinedMessage $DeclinedMessage) { return "Restarting" }

    return "Cancelled"
}


function Request-TFToolkitRestart {
    <#
    Oferece reiniciar o Windows (Não como padrão) e, com o sim, reinicia na hora, sem fechar nada à força: com um prazo
    (shutdown /t 30, por exemplo), o Windows fecha os programas à força (o /f vem junto) e um arquivo sem salvar se perde.
    Sem prazo, um programa com algo por salvar segura o reinício e o Windows pergunta antes de fechá-lo, com a opção de
    cancelar. Devolve verdadeiro quando o reinício começou. -Reason: a frase do porquê; -Comment: o motivo que fica
    registrado no Windows.
    #>
    param (
        [switch]$ChkdskScheduled,
        [string]$Reason = (Get-TFToolkitText 'Reinicie para concluir a otimização.'),
        [string]$Comment = (Get-TFToolkitText 'Reinicialização solicitada pelo TF-Toolkit após o Otimizar.'),
        [string]$DeclinedMessage = (Get-TFToolkitText 'O PC não foi reiniciado. Reinicie quando puder.')
    )

    Write-TFToolkitSection -Title (Get-TFToolkitText 'Reiniciar o PC')
    Write-TFToolkitStatus -Type Info -Message $Reason

    if ($ChkdskScheduled) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O reparo do disco roda antes de o Windows abrir e pode demorar.')
    }

    Write-Host ""

    if (-not (Confirm-TFToolkitAction (Get-TFToolkitText 'Reiniciar o Windows agora? Salve o que estiver aberto antes.') -DefaultKey N -YesLabel (Get-TFToolkitText 'Reiniciar agora') -NoLabel (Get-TFToolkitText 'Depois'))) {
        Write-TFToolkitStatus -Type Info -Message $DeclinedMessage
        return $false
    }

    # O shutdown.exe bloqueado (por uma política da empresa, por exemplo) não pode derrubar o fim do Otimizar: o reinício
    # volta a ser pendência, como quando o Windows o recusa.
    try {
        $run = Invoke-TFToolkitCapture -FilePath "shutdown.exe" -Arguments @("/r", "/t", "0", "/c", $Comment)
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível reiniciar: {0}. Reinicie pelo menu Iniciar.' "$(([string]$_.Exception.Message).Trim().TrimEnd('.'))")
        return $false
    }

    if ($run.ExitCode -ne 0) {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível reiniciar (código {0}): {1}' "$($run.ExitCode)" "$($run.Text.Trim())")
        return $false
    }

    Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'O Windows está reiniciando. Se algum programa tiver arquivo sem salvar, o Windows pergunta antes de fechá-lo.')

    return $true
}


function Invoke-TFToolkitMaintenanceClosing {
    # O fim do Otimizar: o reparo offline do CHKDSK (se a verificação achou problema), o relatório e, sempre, a sugestão
    # de reiniciar; sem reiniciar, o Explorador, quando algum ajuste só aparece depois dele. Devolve verdadeiro quando o
    # Windows ainda precisa reiniciar para concluir (a faixa lembra disso). -OnlyWhenNeeded (a parte automática
    # cancelada): sem nada que peça o reinício, não sugere reiniciar; quem acabou de cancelar não quer recomeçar o PC.
    param (
        [object[]]$Results,
        [string[]]$StepIds,
        [switch]$OnlyWhenNeeded
    )

    # O reparo offline do CHKDSK só é oferecido se a verificação rodou nesta otimização.
    $chkdskScheduled = $false

    if ($StepIds -contains "chkdsk" -and (Test-TFToolkitChkdskRepairPending)) {
        Write-TFToolkitSection -Title "CHKDSK"
        # Na janela, as mensagens ficam no resumo, à vista durante a pergunta. Erro no disco pode ser o disco falhando.
        # O código 3 do CHKDSK também é "não deu para verificar tudo com o Windows aberto": a frase não afirma que há erro.
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'O CHKDSK pede um reparo que só roda ao reiniciar.')
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Ele roda antes de o Windows abrir e pode levar horas; não desligue o PC até o Windows abrir.')
        Write-Host ""

        if (Confirm-TFToolkitAction (Get-TFToolkitText 'Agendar o reparo do disco para a próxima reinicialização?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Agendar') -NoLabel (Get-TFToolkitText 'Agora não')) {
            $chkdskScheduled = [bool](Invoke-TFToolkitScheduleChkdskRepair)
        }
    }

    # Sem a pergunta do relatório: ele continua em Diagnóstico > Exportar relatório, e o histórico guarda o Otimizar.
    Write-Host ""

    # O Otimizar sempre sugere reiniciar: o Windows começa do zero, com tudo o que mudou já valendo. Quando alguma etapa
    # só termina com o reinício, a frase diz isso, e a faixa lembra dele se a pessoa não reiniciar.
    $needed = Test-TFToolkitMaintenanceNeedsRestart -Results $Results -ChkdskScheduled $chkdskScheduled

    if ($OnlyWhenNeeded -and -not $needed) {
        Invoke-TFToolkitExplorerRestartOffer -Results $Results
        return $false
    }

    $reason = $(if ($needed) { (Get-TFToolkitText 'Reinicie para concluir: algumas mudanças só valem depois do reinício.') } else { (Get-TFToolkitText 'Reinicie para o Windows começar do zero, com tudo o que mudou valendo.') })
    $declined = $(if ($needed) { (Get-TFToolkitText 'O PC não foi reiniciado. Reinicie quando puder para concluir.') } else { (Get-TFToolkitText 'O PC não foi reiniciado. Reinicie quando puder.') })

    $restarting = Request-TFToolkitRestart -ChkdskScheduled:$chkdskScheduled -Reason $reason -DeclinedMessage $declined

    if (-not $restarting) {
        Invoke-TFToolkitExplorerRestartOffer -Results $Results
    }

    # Mesmo com o reinício pedido, a faixa lembra dele quando ele é necessário: um programa com arquivo sem salvar pode
    # segurá-lo, e a pessoa pode cancelar na tela do Windows.
    return [bool]$needed
}


function Invoke-TFToolkitExplorerRestartOffer {
    # Alguns ajustes (as extensões dos arquivos, os itens ocultos) só aparecem quando o Explorador reinicia: sem o
    # reinício do Windows, o Otimizar oferece só isso.
    param (
        [object[]]$Results
    )

    $needsExplorer = @($Results | Where-Object { $null -ne $_ -and $_.Kind -in @("Ok", "Warning") -and (Test-TFToolkitResultFlag -Result $_ -Name "ExplorerRestart") }).Count -gt 0

    if (-not $needsExplorer) {
        return
    }

    Write-Host ""

    # Reiniciar o Explorador fecha as janelas de pastas abertas: no fim de uma execução longa, sem ninguém para responder,
    # nada acontece sozinho (Não como padrão).
    if (Confirm-TFToolkitAction (Get-TFToolkitText 'Reiniciar o Explorador de Arquivos agora para ver os ajustes?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Reiniciar o Explorador') -NoLabel (Get-TFToolkitText 'Depois')) {
        try {
            Restart-TFToolkitExplorerShell
            Write-TFToolkitStatus -Type Success -Message (Get-TFToolkitText 'Explorador reiniciado.')
        }
        catch {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível reiniciar o Explorador: {0}' "$($_.Exception.Message)")
        }
    }
}


# ---------------------------------------------------------------------------
# Desfecho
# ---------------------------------------------------------------------------

function Format-TFToolkitMaintenanceGain {
    # "; 2 GB a mais de espaço livre", entre as fotos do começo e do fim (Get-TFToolkitMaintenanceSnapshot), com 100 MB ou
    # mais a mais: é o que a pessoa percebe da manutenção. "" sem uma das fotos ou com menos que isso.
    param (
        $Before = $null,
        $After = $null
    )

    if ($null -eq $Before -or $null -eq $After) { return "" }

    $beforeFree = Get-TFToolkitJsonValue -Object $Before -Name "FreeBytes" -Default $null
    $afterFree = Get-TFToolkitJsonValue -Object $After -Name "FreeBytes" -Default $null

    if ($null -eq $beforeFree -or $null -eq $afterFree -or ([int64]$afterFree - [int64]$beforeFree) -lt 100MB) { return "" }

    return (Get-TFToolkitText '; {0} a mais de espaço livre' "$(Format-TFToolkitBytes -Bytes ([int64]$afterFree - [int64]$beforeFree))")
}


function Get-TFToolkitMaintenanceStepTarget {
    # A tela que roda sozinha uma etapa do Otimizar (o Id dela na navegação), para o botão da faixa. "" para as que só
    # existem dentro do Otimizar (as pastas pessoais e os navegadores). Um teste confere que cada uma existe e que leva ao
    # mesmo lugar que o "rode de novo em" do histórico (Get-TFToolkitMaintenanceStepReference).
    param ([AllowEmptyString()][string]$Id)

    $targets = @{
        "restore-point"  = "maintenance.restore-point"
        "uninstall"      = "software.uninstall"
        "windows-apps"   = "software.remove-apps"
        "startup"        = "performance.startup"
        "security"       = "security.scan"
        "components"     = "cleanup.components"
        "repair"         = "repair.dism-sfc"
        "windows-update" = "updates.install"
        "drivers"        = "repair.device-scan"
        "winget"         = "updates.winget"
        "store"          = "updates.store"
        "cleanup"        = "cleanup.quick"
        "shortcuts"      = "cleanup.shortcuts"
        "leftovers"      = "cleanup.leftovers"
        "network"        = "network.repair"
        "chkdsk"         = "repair.chkdsk"
        "optimize"       = "repair.optimize"
        "tweaks"         = "tweaks.recommended"
    }

    if (-not [string]::IsNullOrEmpty($Id) -and $targets.ContainsKey($Id)) { return [string]$targets[$Id] }

    return ""
}


function Set-TFToolkitMaintenanceView {
    <#
    Como a janela mostra o fim do Otimizar, quando o genérico ("Concluído com ressalvas: 1 etapa falhou e 2 terminaram com
    ressalvas") não basta. O título diz o que aconteceu: "PC otimizado", "2 etapas pedem atenção", "Atualizar o Windows
    falhou", "Nenhuma etapa funcionou" ou "Parte automática cancelada". A frase embaixo diz qual etapa e por quê (com uma
    só) ou quais (com mais, as que falharam antes das que terminaram com ressalvas), e o espaço ganho. O botão leva à tela
    que roda sozinha a primeira delas. Tudo ignorado, cancelado e reiniciando ficam com a faixa genérica, que já diz isso.
    O console e o histórico continuam com o Detail de Get-TFToolkitMaintenanceResult. Devolve o próprio resultado.
    -AutoCancelled: a parte automática foi cancelada; Results são as etapas que rodaram antes dela.
    #>
    param (
        [Parameter(Mandatory)]$Result,
        [object[]]$Results = @(),
        $Before = $null,
        $After = $null,
        [switch]$AutoCancelled
    )

    $steps = @($Results | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["Kind"] })
    $nameOf = { param ($Step) Get-TFToolkitText ([string](Get-TFToolkitJsonValue -Object $Step -Name "Etapa" -Default "")) }

    # As que falharam primeiro, depois as que terminaram com ressalvas, cada grupo na ordem em que rodou.
    $problems = @(@($steps | Where-Object { [string]$_.Kind -eq "Failed" }) + @($steps | Where-Object { [string]$_.Kind -eq "Warning" }))
    $gain = Format-TFToolkitMaintenanceGain -Before $Before -After $After

    $next = ""
    $nextLabel = ""

    foreach ($step in $problems) {
        $target = Get-TFToolkitMaintenanceStepTarget -Id ([string](Get-TFToolkitJsonValue -Object $step -Name "StepId" -Default ""))
        if ([string]::IsNullOrEmpty($target)) { continue }

        try {
            $item = Get-TFToolkitNavItem -Id $target
            if ($null -ne $item) { $next = [string]$item.Id; $nextLabel = [string]$item.Label; break }
        }
        catch {
            Write-Verbose "Próximo passo do Otimizar: $($_.Exception.Message)"
        }
    }

    # O motivo de uma etapa, para depois de "Nome: ": legível, sem o ponto final e com a primeira letra minúscula, menos
    # quando ele começa por um nome ("Firefox: estava aberto", "Documentos: não abriu no Explorador"). Longo demais para a
    # faixa, nenhum: a frase diz só o nome, e o motivo inteiro fica no resumo. Cortar no primeiro ";" pegaria a parte que
    # deu certo ("Edge: atualizado para …; Firefox: estava aberto").
    $reasonOf = {
        param ([string]$Text)

        $why = ([string](ConvertTo-TFToolkitReadableError -Text $Text)).Trim().TrimEnd('.').Trim()

        if (-not $why -or $why.Length -gt 90) { return "" }

        if ($why -notmatch '^[^\s:]+( [^\s:]+)?: ' -and $why.Length -gt 1 -and [char]::IsUpper($why[0]) -and -not [char]::IsUpper($why[1])) {
            $why = $why.Substring(0, 1).ToLowerInvariant() + $why.Substring(1)
        }

        return $why
    }

    # Uma etapa com problema: o nome e o motivo ("Atualizar o Windows: sem conexão com a internet"), ou só o nome quando
    # o motivo não cabe na faixa (ele continua no resumo). Com mais, os nomes.
    $problemNote = ""

    if ($problems.Count -eq 1) {
        $why = & $reasonOf ([string](Get-TFToolkitJsonValue -Object $problems[0] -Name "Detail" -Default ""))
        $problemNote = $(if ($why) { (Get-TFToolkitText '{0}: {1}' "$(& $nameOf $problems[0])" "$why") } else { (Get-TFToolkitText 'Com problema: {0}' "$(& $nameOf $problems[0])") })
    }
    elseif ($problems.Count -gt 1) {
        $problemNote = (Get-TFToolkitText 'Com problema: {0}' "$(Join-TFToolkitShortList -Items @($problems | ForEach-Object { & $nameOf $_ }))")
    }

    if ($AutoCancelled) {
        $partial = Get-TFToolkitMaintenanceResult -Results $steps -Before $Before -After $After
        $done = $(if ([string]$partial.Kind -eq "Skipped") { (Get-TFToolkitText 'nada mudou') } else { [string]$partial.Detail })

        return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'Parte automática cancelada') `
                -Note (Get-TFToolkitText 'O que já foi feito continua valendo: {0}.' "$done") -Next $next -NextLabel $nextLabel)
    }

    switch ([string]$Result.Kind) {
        "Ok" {
            return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'PC otimizado') -Note "$(([string]$Result.Detail).Trim().TrimEnd('.'))." )
        }
        "Warning" {
            $headline = Format-TFToolkitCount -Count $problems.Count -One (Get-TFToolkitText 'etapa pede atenção') -Many (Get-TFToolkitText 'etapas pedem atenção')
            return (Set-TFToolkitResultView -Result $Result -Headline $headline -Note "$problemNote$gain." -Next $next -NextLabel $nextLabel)
        }
        "Failed" {
            # Só uma etapa rodou (as outras não tinham o que fazer) e ela falhou: o título diz qual.
            if ($problems.Count -eq 1) {
                return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText '{0} falhou' "$(& $nameOf $problems[0])") -Note "$problemNote." -Next $next -NextLabel $nextLabel)
            }

            # Todas pelo mesmo motivo (sem internet, por exemplo): a frase diz qual; senão, cada motivo está no resumo.
            $reasons = @($problems | ForEach-Object { ([string](Get-TFToolkitJsonValue -Object $_ -Name "Detail" -Default "")).Trim() } | Select-Object -Unique)
            $why = $(if ($reasons.Count -eq 1) { & $reasonOf $reasons[0] } else { "" })
            $note = $(if ($why) { (Get-TFToolkitText 'As {0} etapas falharam: {1}.' "$($problems.Count)" "$why") } else { (Get-TFToolkitText 'As {0} etapas falharam; o motivo de cada uma está no resumo.' "$($problems.Count)") })

            return (Set-TFToolkitResultView -Result $Result -Headline (Get-TFToolkitText 'Nenhuma etapa funcionou') -Note $note)
        }
        default { return $Result }
    }
}


function Get-TFToolkitMaintenanceResult {
    <#
    O desfecho do Otimizar, que a janela mostra na faixa de resultado: Falhou quando nenhuma etapa
    funcionou, Atenção quando alguma falhou ou terminou com ressalvas, Ok nos demais casos e Ignorado quando todas as
    etapas foram ignoradas. RestartPending: o Windows ainda precisa reiniciar (a faixa lembra disso).
    #>
    param (
        [object[]]$Results,
        [bool]$RestartPending = $false,

        # Fotos do começo e do fim (Get-TFToolkitMaintenanceSnapshot): com 100 MB ou mais de espaço livre a mais, a faixa
        # diz isso, que é o que a pessoa percebe da manutenção.
        $Before = $null,
        $After = $null
    )

    $steps = @($Results | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["Kind"] })
    $count = { param ([string]$Kind) @($steps | Where-Object { $_.Kind -eq $Kind }).Count }
    # Os nomes das etapas de um desfecho; sem nome em alguma delas, a frase usa a contagem.
    $namesOf = {
        param ([string]$Kind)
        @($steps | Where-Object { $_.Kind -eq $Kind } | ForEach-Object { Get-TFToolkitText ([string](Get-TFToolkitJsonValue -Object $_ -Name "Etapa" -Default "")) })
    }
    # Até três nomes ("A, B e C"); passando disso, "A, B, C e mais 2".
    $listOf = {
        param ([string[]]$Names)
        if ($Names.Count -gt 3) { return (Get-TFToolkitText '{0} e mais {1}' "$(@($Names | Select-Object -First 3) -join ', ')" "$($Names.Count - 3)") }
        return (Join-TFToolkitList -Items $Names)
    }

    $failed = [int](& $count "Failed")
    $warned = [int](& $count "Warning")
    $skipped = [int](& $count "Skipped")
    $done = $steps.Count - $skipped

    $data = @{}

    if ($RestartPending) { $data.RebootRequired = $true }

    $gain = Format-TFToolkitMaintenanceGain -Before $Before -After $After

    if ($steps.Count -eq 0) {
        return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'nenhuma etapa rodou') -Data $data)
    }

    if ($done -eq 0) {
        return (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'todas as etapas foram ignoradas') -Data $data)
    }

    if ($failed -eq $done) {
        return (New-TFToolkitResult -Kind Failed -Detail $(if ($failed -eq 1) { (Get-TFToolkitText 'a única etapa falhou') } else { (Get-TFToolkitText 'as {0} etapas falharam' "$failed") }) -Data $data)
    }

    if ($failed -gt 0 -or $warned -gt 0) {
        $failedNames = @(& $namesOf "Failed")
        $warnedNames = @(& $namesOf "Warning")
        # Até duas etapas, a faixa diz quais são, para a pessoa saber onde olhar no resumo; com mais, a lista de nomes não
        # caberia numa frase, e a faixa diz quantas (o resumo, logo abaixo, tem uma linha por etapa).
        $named = (($failed + $warned) -le 2 -and @(@($failedNames) + @($warnedNames) | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0)
        $parts = @()

        if ($named) {
            if ($failed -gt 0) { $parts += $(if ($failed -eq 1) { (Get-TFToolkitText '{0} falhou' "$(& $listOf $failedNames)") } else { (Get-TFToolkitText '{0} falharam' "$(& $listOf $failedNames)") }) }
            if ($warned -gt 0) { $parts += $(if ($warned -eq 1) { (Get-TFToolkitText '{0} terminou com ressalvas' "$(& $listOf $warnedNames)") } else { (Get-TFToolkitText '{0} terminaram com ressalvas' "$(& $listOf $warnedNames)") }) }

            return (New-TFToolkitResult -Kind Warning -Detail (($parts -join "; ") + $gain) -Data $data)
        }

        if ($failed -gt 0) { $parts += $(if ($failed -eq 1) { (Get-TFToolkitText '1 etapa falhou') } else { (Get-TFToolkitText '{0} etapas falharam' "$failed") }) }

        if ($warned -gt 0) {
            # Depois de "1 etapa falhou e", a palavra "etapa" fica subentendida; sozinha, a frase precisa dela.
            $parts += $(
                if ($failed -gt 0 -and $warned -eq 1) { (Get-TFToolkitText '1 terminou com ressalvas') }
                elseif ($failed -gt 0) { (Get-TFToolkitText '{0} terminaram com ressalvas' "$warned") }
                elseif ($warned -eq 1) { (Get-TFToolkitText '1 etapa terminou com ressalvas') }
                else { (Get-TFToolkitText '{0} etapas terminaram com ressalvas' "$warned") }
            )
        }

        return (New-TFToolkitResult -Kind Warning -Detail ((Join-TFToolkitList -Items $parts) + $gain) -Data $data)
    }

    $text = $(if ($done -eq 1) { (Get-TFToolkitText '1 etapa executada') } else { (Get-TFToolkitText '{0} etapas executadas' "$done") })

    if ($skipped -gt 0) { $text += $(if ($skipped -eq 1) { (Get-TFToolkitText ' e 1 ignorada') } else { (Get-TFToolkitText ' e {0} ignoradas' "$skipped") }) }

    return (New-TFToolkitResult -Kind Ok -Detail ($text + $gain) -Data $data)
}


# ---------------------------------------------------------------------------
# Ação principal
# ---------------------------------------------------------------------------

function Invoke-TFToolkitRecommendedMaintenance {
    # O Otimizar (o botão do Início e Manutenção > Otimizar): veja as fases no alto deste arquivo.
    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Otimizar')

    if (-not (Test-TFToolkitElevation -Reason (Get-TFToolkitText 'O Otimizar exige privilégios de Administrador.'))) {
        Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Detail (Get-TFToolkitText 'requer Administrador'))
        return
    }

    $cancelled = {
        Write-Host ""
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Otimização cancelada.')
        Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'operação cancelada'))
    }

    # Fase 1: preparação. "Restarting": a pessoa escolheu reiniciar antes (havia um reinício pendente) e o Windows já
    # está reiniciando; o Otimizar fica para depois.
    $preflight = Confirm-TFToolkitMaintenancePreflight

    if ($preflight -is [string] -and $preflight -eq "Restarting") {
        Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Skipped -Detail (Get-TFToolkitText 'o PC está reiniciando; depois, abra o TF-Toolkit e clique em Otimizar de novo'))
        return
    }

    if (-not $preflight) {
        & $cancelled
        return
    }

    # Fase 2: o plano é sempre o inteiro, sem lista para escolher: cada etapa decide sozinha se tem o que fazer (e as
    # telas com você deixam escolher o que entra nelas).
    $items = @(Get-TFToolkitMaintenancePlanItems)
    $beforeIds = @($items | Where-Object { $_.Phase -eq "Before" } | ForEach-Object { $_.Id })
    $autoIds = @($items | Where-Object { $_.Phase -eq "Auto" } | ForEach-Object { $_.Id })
    $afterIds = @($items | Where-Object { $_.Phase -eq "After" } | ForEach-Object { $_.Id })
    $total = $items.Count

    # A foto do "antes" vem antes de tudo: desinstalar e desativar programas da inicialização também contam.
    $before = Get-TFToolkitMaintenanceSnapshot
    $startedAt = Get-Date
    $runId = [guid]::NewGuid().ToString("N")

    $details = New-TFToolkitMaintenanceDetails

    # Fase 3: com você, no começo. O ponto de restauração vem antes de qualquer mudança, e sem ele (Proteção do Sistema
    # desligada e a pessoa não quis ligá-la, o Windows recusou, ou a criação falhou) a pessoa decide se segue sem a rede
    # de segurança, com Cancelar como padrão: desinstalar, a inicialização, a rede e os ajustes não teriam para onde voltar.
    $results = @(Invoke-TFToolkitMaintenancePhase -Phase Before -StepIds @("restore-point") -Details $details -Start 1 -Total $total)

    if (@($results | Where-Object { [string]$_.Kind -eq "Failed" -or (Test-TFToolkitResultFlag -Result $_ -Name "NotCreated") }).Count -gt 0) {
        Write-Host ""

        if (-not (Confirm-TFToolkitAction (Get-TFToolkitText 'Continuar sem o ponto de restauração?') -DefaultKey N -YesLabel (Get-TFToolkitText 'Continuar sem o ponto') -NoLabel (Get-TFToolkitText 'Cancelar'))) {
            & $cancelled
            return
        }
    }

    # Os programas primeiro: desinstalar e remover aplicativos mudam a lista do winget. Depois deles, a consulta das
    # atualizações começa em segundo plano e corre enquanto a pessoa revisa a inicialização e as pastas; na pergunta, a
    # lista já está pronta. Isso conta com a ordem do plano: o ponto, desinstalar, os aplicativos do Windows e o resto.
    $programIds = @($beforeIds | Where-Object { $_ -in @("uninstall", "windows-apps") })
    $results += @(Invoke-TFToolkitMaintenancePhase -Phase Before -StepIds $programIds -Details $details -Start 2 -Total $total)

    $wingetRead = $null

    try {
        if ($autoIds -contains "winget") {
            try {
                $wingetRead = Start-TFToolkitWingetUpgradeRead
            }
            catch {
                # Sem a consulta adiantada, a pergunta consulta o winget na hora, como antes.
                Write-Verbose "Consulta do winget em segundo plano: $($_.Exception.Message)"
            }
        }

        $results += @(Invoke-TFToolkitMaintenancePhase -Phase Before -StepIds @($beforeIds | Where-Object { $_ -notin @("restore-point", "uninstall", "windows-apps") }) -Details $details -Start (2 + $programIds.Count) -Total $total)

        # Fase 4: as perguntas da parte automática. Não são uma etapa: na janela, o destaque do alto deixa de dizer a
        # última etapa com você e diz em que parte o Otimizar está.
        Write-TFToolkitPhase -Title (Get-TFToolkitText 'Antes da parte automática')
        $details = Read-TFToolkitMaintenanceDetails -AutoIds $autoIds -WingetRead $wingetRead
    }
    finally {
        # Recebida na pergunta, a consulta já terminou; sem ela (a conexão limitada deixou os programas para depois, ou o
        # Otimizar parou antes), ela é largada.
        Stop-TFToolkitInBackground -Task $wingetRead
    }

    if (-not (Confirm-TFToolkitAutomaticPhase)) {
        # Nada mudou até aqui (todas as telas com você foram puladas e o ponto não foi criado): é só um cancelamento.
        if (@($results | Where-Object { [string]$_.Kind -ne "Skipped" }).Count -eq 0) {
            & $cancelled
            return
        }

        # As telas com você já mudaram o PC: o resumo mostra o que foi feito, mas a execução não conta como manutenção
        # (segurança, atualizações e reparos não rodaram, e o Início continua lembrando do Otimizar).
        Write-TFToolkitPhase -Title (Get-TFToolkitText 'Para terminar')
        Write-TFToolkitStatus -Type Warning -Message (Get-TFToolkitText 'Parte automática cancelada. O que já foi feito continua valendo.')

        $after = Get-TFToolkitMaintenanceSnapshot
        $partial = Get-TFToolkitMaintenanceResult -Results $results -Before $before -After $after
        $verdict = New-TFToolkitResult -Kind Warning -Detail (Get-TFToolkitText 'a parte automática foi cancelada; {0}' "$($partial.Detail)") -Data $partial.Data

        Show-TFToolkitMaintenanceSummary -Results $results -StartedAt $startedAt -Before $before -After $after -Verdict $verdict -NoRecord
        $restartPending = [bool](@(Invoke-TFToolkitMaintenanceClosing -Results $results -StepIds @() -OnlyWhenNeeded) | Select-Object -Last 1)

        $outcome = New-TFToolkitResult -Kind Warning -Detail $verdict.Detail -Data $(if ($restartPending) { @{ RebootRequired = $true } } else { @{} })
        [void](Set-TFToolkitMaintenanceView -Result $outcome -Results $results -Before $before -After $after -AutoCancelled)
        Exit-TFToolkitAction -Result $outcome
        return
    }

    # Fase 5: automática. No fim dela, o resultado já fica gravado: a revisão dos ajustes espera a pessoa, e uma janela
    # fechada ou um reinício do Windows Update nessa espera não podem apagar uma hora de manutenção. O fim do Otimizar
    # grava de novo, por cima da mesma execução (o mesmo RunId).
    $results += @(Invoke-TFToolkitMaintenancePhase -Phase Auto -StepIds $autoIds -Details $details -Start ($beforeIds.Count + 1) -Total $total -KeepAwake)

    try {
        Set-TFToolkitLastMaintenance -Results $results -StartedAt $startedAt -Before $before -After (Get-TFToolkitMaintenanceSnapshot) -ProfileId "optimize" -RunId $runId
    }
    catch {
        Write-Verbose "Gravação parcial do Otimizar: $($_.Exception.Message)"
    }

    # Fase 6: com você, no fim
    $results += @(Invoke-TFToolkitMaintenancePhase -Phase After -StepIds $afterIds -Details $details -Start ($beforeIds.Count + $autoIds.Count + 1) -Total $total)

    # Fase 7: resumo e encerramento
    Write-TFToolkitPhase -Title (Get-TFToolkitText 'Para terminar')
    $after = Get-TFToolkitMaintenanceSnapshot
    Show-TFToolkitMaintenanceSummary -Results $results -StartedAt $startedAt -Before $before -After $after -ProfileId "optimize" -RunId $runId

    $restartPending = [bool](@(Invoke-TFToolkitMaintenanceClosing -Results $results -StepIds $autoIds) | Select-Object -Last 1)

    # O desfecho é o das etapas: a contagem das mensagens de estado trataria o aviso do preparo ("Salve seu trabalho...")
    # como uma ressalva e mostraria só a última mensagem de erro.
    $outcome = Get-TFToolkitMaintenanceResult -Results $results -RestartPending $restartPending -Before $before -After $after
    [void](Set-TFToolkitMaintenanceView -Result $outcome -Results $results -Before $before -After $after)

    Exit-TFToolkitAction -Result $outcome
}


# ---------------------------------------------------------------------------
# Histórico
# ---------------------------------------------------------------------------

function Format-TFToolkitHistoryLine {
    <#
    Uma manutenção do histórico em uma linha: como rodou (Otimizar, ou o perfil das manutenções da 3.50 e anteriores),
    duração, o desfecho das etapas e a variação de espaço ("Otimizar · 1h 12min · 18 ok, 1 com ressalvas · espaço: +1,2
    GB"). A data vai no rótulo da linha (Show-TFToolkitMaintenanceHistory). O que não foi registrado (o jeito de uma versão
    antiga, espaço sem medição) fica de fora.
    #>
    param (
        [Parameter(Mandatory)]
        $Entry
    )

    $parts = @()

    # Um jeito que esta versão não conhece fica de fora, em vez de virar outro.
    $label = Get-TFToolkitMaintenanceProfileLabel -Id ([string](Get-TFToolkitJsonValue -Object $Entry -Name "ProfileId" -Default ""))

    if ($label) {
        $parts += $label
    }

    if ([int]$Entry.DurationSeconds -gt 0) {
        $parts += Format-TFToolkitDuration -Span ([TimeSpan]::FromSeconds($Entry.DurationSeconds))
    }

    $steps = @()

    if ([int]$Entry.Ok -gt 0) { $steps += "$($Entry.Ok) ok" }
    if ([int]$Entry.Warning -gt 0) { $steps += $(if ([int]$Entry.Warning -eq 1) { (Get-TFToolkitText '1 com ressalva') } else { (Get-TFToolkitText '{0} com ressalvas' "$($Entry.Warning)") }) }
    if ([int]$Entry.Failed -gt 0) { $steps += $(if ([int]$Entry.Failed -eq 1) { (Get-TFToolkitText '1 falhou') } else { (Get-TFToolkitText '{0} falharam' "$($Entry.Failed)") }) }
    if ([int]$Entry.Skipped -gt 0) { $steps += $(if ([int]$Entry.Skipped -eq 1) { (Get-TFToolkitText '1 ignorada') } else { (Get-TFToolkitText '{0} ignoradas' "$($Entry.Skipped)") }) }

    if ($steps.Count -gt 0) { $parts += ($steps -join ", ") }

    if ($null -ne $Entry.FreeBefore -and $null -ne $Entry.FreeAfter) {
        $parts += (Get-TFToolkitText 'espaço: {0}' "$(Format-TFToolkitSignedBytes -Delta ([int64]$Entry.FreeAfter - [int64]$Entry.FreeBefore))")
    }

    return ($parts -join " · ")
}


function Get-TFToolkitMaintenanceTrends {
    # Tendências das últimas manutenções (a lista vem da mais recente para a mais antiga, na ordem em que foram gravadas).
    # Cada linha tem Label, Text e Level (Info | Success | Warning). Com uma manutenção só não há tendência: as linhas
    # que comparam (primeira e última, média) dizem só o que ela registrou.
    param (
        [object[]]$History
    )

    $entries = @($History | Where-Object { $null -ne $_ })
    $rows = @()

    if ($entries.Count -eq 0) {
        return @()
    }

    $newest = $entries[0]
    $oldest = $entries[$entries.Count - 1]

    $rows += [PSCustomObject]@{
        Label = (Get-TFToolkitText 'Manutenções registradas')
        Text  = $(if ($entries.Count -eq 1) { (Get-TFToolkitText '1 (em {0})' "$(Format-TFToolkitDateTime -When $newest.StartedAt)") } else { (Get-TFToolkitText '{0}, de {1} a {2}' "$($entries.Count)" "$(Format-TFToolkitDateTime -When $oldest.StartedAt)" "$(Format-TFToolkitDateTime -When $newest.StartedAt)") })
        Level = "Info"
    }

    $durations = @($entries | Where-Object { $_.DurationSeconds -gt 0 } | ForEach-Object { [double]$_.DurationSeconds })

    if ($entries.Count -eq 1 -and $durations.Count -eq 1) {
        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Duração'); Text = (Format-TFToolkitDuration -Span ([TimeSpan]::FromSeconds($durations[0]))); Level = "Info" }
    }
    elseif ($durations.Count -gt 0) {
        $average = ($durations | Measure-Object -Average).Average
        $text = (Get-TFToolkitText 'média de {0}' "$(Format-TFToolkitDuration -Span ([TimeSpan]::FromSeconds($average)))")

        # Uma entrada antiga sem duração registrada não vira "a última levou 0s".
        if ([int]$newest.DurationSeconds -gt 0) {
            $text += (Get-TFToolkitText '; a última levou {0}' "$(Format-TFToolkitDuration -Span ([TimeSpan]::FromSeconds($newest.DurationSeconds)))")
        }

        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Duração'); Text = $text; Level = "Info" }
    }

    # O espaço: o que as etapas liberaram, somado, e o espaço livre da primeira à última. A variação de cada manutenção
    # (que mistura o que a limpeza liberou com o que as atualizações, o ponto de restauração e o DISM ocuparam) fica na
    # linha dela, em "Últimas manutenções": uma média dela aqui seria um terceiro número de espaço, diferente dos outros
    # dois, sem dizer nada a mais.

    # O que as etapas disseram ter liberado (a limpeza, os componentes, os restos de programas): o mesmo número do Início,
    # em "Histórico neste PC". As manutenções gravadas antes da 4.0 não têm essa medida.
    $measured = @($entries | Where-Object { $null -ne $_.PSObject.Properties["Freed"] -and $null -ne $_.Freed })

    if ($measured.Count -gt 0) {
        $total = [int64]0
        foreach ($entry in $measured) { if ([int64]$entry.Freed -gt 0) { $total += [int64]$entry.Freed } }

        $text = Format-TFToolkitBytes -Bytes $total
        if ($measured.Count -lt $entries.Count) { $text += (Get-TFToolkitText ' (em {0} com medição)' "$(Format-TFToolkitCount -Count $measured.Count -One (Get-TFToolkitText 'manutenção') -Many (Get-TFToolkitText 'manutenções'))") }

        $rows += [PSCustomObject]@{ Label = (Get-TFToolkitText 'Liberado nas manutenções'); Text = $text; Level = "Info" }
    }

    $withFree = @($entries | Where-Object { $null -ne $_.FreeAfter })

    if ($withFree.Count -ge 2) {
        $first = $withFree[$withFree.Count - 1]
        $last = $withFree[0]
        $delta = [int64]$last.FreeAfter - [int64]$first.FreeAfter

        $rows += [PSCustomObject]@{
            Label = (Get-TFToolkitText 'Espaço livre, da primeira à última')
            Text  = (Get-TFToolkitText 'de {0} para {1} ({2})' "$(Format-TFToolkitBytes -Bytes ([int64]$first.FreeAfter))" "$(Format-TFToolkitBytes -Bytes ([int64]$last.FreeAfter))" "$(Format-TFToolkitSignedBytes -Delta $delta)")
            Level = $(if ($delta -le -(5GB)) { "Warning" } else { "Info" })
        }
    }

    $withStartupBefore = @($entries | Where-Object { $null -ne $_.StartupBefore })
    $withStartupAfter = @($entries | Where-Object { $null -ne $_.StartupAfter })

    if ($withStartupBefore.Count -gt 0 -and $withStartupAfter.Count -gt 0) {
        $from = $withStartupBefore[$withStartupBefore.Count - 1].StartupBefore
        $to = $withStartupAfter[0].StartupAfter

        $rows += [PSCustomObject]@{
            Label = (Get-TFToolkitText 'Programas que abrem com o Windows')
            Text  = $(if ($entries.Count -eq 1) { (Get-TFToolkitText 'de {0} para {1}' "$from" "$to") } else { (Get-TFToolkitText 'de {0} na primeira para {1} na última' "$from" "$to") })
            Level = "Info"
        }
    }

    # Etapas que deram ressalva ou falha em pelo menos duas das últimas cinco manutenções.
    $recent = @($entries | Select-Object -First 5)
    $problems = @{}

    foreach ($entry in $recent) {
        $seen = @{}

        foreach ($step in @($entry.Steps)) {
            # O nome no idioma de agora: uma etapa gravada em português e a mesma em inglês contam juntas.
            $stepName = Get-TFToolkitText ([string]$step.Etapa)
            if ($step.Kind -in @("Warning", "Failed") -and -not [string]::IsNullOrWhiteSpace($stepName) -and -not $seen.ContainsKey($stepName)) {
                $seen[$stepName] = $true
                $problems[$stepName] = 1 + $(if ($problems.ContainsKey($stepName)) { [int]$problems[$stepName] } else { 0 })
            }
        }
    }

    foreach ($name in @($problems.Keys | Sort-Object)) {
        if ([int]$problems[$name] -ge 2) {
            # O próximo passo: rodar a etapa sozinha mostra o motivo, sem o resto da manutenção em volta.
            $reference = Get-TFToolkitMaintenanceStepReference -Name $name
            # A mesma frase da seção da última manutenção, logo acima.
            $next = $(if ($reference) { (Get-TFToolkitText '; rode de novo em {0}' "$reference") } else { "" })

            $rows += [PSCustomObject]@{
                Label = (Get-TFToolkitText 'Etapa com problema repetido')
                Text  = (Get-TFToolkitText '{0}: ressalva ou falha em {1} das últimas {2} manutenções{3}' "${name}" "$($problems[$name])" "$($recent.Count)" "$next")
                Level = "Warning"
            }
        }
    }

    return @($rows)
}


function Get-TFToolkitMaintenanceStepReference {
    <#
    Onde rodar sozinha uma etapa automática da manutenção, como "Página > Item" (a janela faz disso um link), pelo nome
    da etapa (o que o histórico guarda). Uma tabela fixa, e não uma busca na navegação: a tela do histórico não pede
    Administrador e não pode depender da tabela inteira de ações (um teste confere que cada referência existe). Sem
    correspondência, "".
    #>
    param ([AllowEmptyString()][string]$Name)

    # Os nomes antigos (Verificação de segurança, Aplicar ajustes recomendados) continuam: o histórico guarda manutenções
    # da 3.50 e anteriores.
    $references = @{
        "Criar ponto de restauração"               = (Get-TFToolkitText 'Manutenção > Criar ponto de restauração')
        "Desinstalar programas"                    = (Get-TFToolkitText 'Programas > Desinstalar programas')
        "Remover aplicativos do Windows"           = (Get-TFToolkitText 'Programas > Remover aplicativos do Windows')
        "Revisar o que abre com o Windows"         = (Get-TFToolkitText 'Desempenho > Gerenciar inicialização')
        "Verificar vírus"                          = (Get-TFToolkitText 'Segurança > Verificar vírus')
        "Verificação de segurança"                 = (Get-TFToolkitText 'Segurança > Verificar vírus')
        "Atualizar o Windows"                      = (Get-TFToolkitText 'Atualizações > Instalar atualizações do Windows')
        "Detectar dispositivos e drivers"          = (Get-TFToolkitText 'Reparo > Detectar dispositivos e drivers')
        "Atualizar programas (winget)"             = (Get-TFToolkitText 'Atualizações > Atualizar programas (winget)')
        "Atualizar aplicativos da Microsoft Store" = (Get-TFToolkitText 'Atualizações > Atualizar aplicativos da Microsoft Store')
        "Remover atalhos quebrados"                = (Get-TFToolkitText 'Limpeza > Remover atalhos quebrados')
        "Restos de programas desinstalados"        = (Get-TFToolkitText 'Limpeza > Restos de programas desinstalados')
        "Limpar o registro"                        = (Get-TFToolkitText 'Limpeza > Limpar o registro')
        "Limpar componentes do Windows (WinSxS)"   = (Get-TFToolkitText 'Limpeza > Limpar componentes do Windows (WinSxS)')
        "Limpeza rápida"                           = (Get-TFToolkitText 'Limpeza > Limpeza rápida')
        "Reparar rede e DNS"                       = (Get-TFToolkitText 'Rede > Reparar rede e DNS')
        "Reparar o Windows (DISM + SFC)"           = (Get-TFToolkitText 'Reparo > Reparar o Windows (DISM + SFC)')
        "Verificar o sistema de arquivos (CHKDSK)" = (Get-TFToolkitText 'Reparo > Verificar o sistema de arquivos (CHKDSK)')
        "Otimizar a unidade do sistema"            = (Get-TFToolkitText 'Reparo > Otimizar a unidade do sistema')
        "Aplicar ajustes recomendados"             = (Get-TFToolkitText 'Ajustes do Windows > Aplicar ajustes recomendados')
        "Revisar os ajustes do Windows"            = (Get-TFToolkitText 'Ajustes do Windows > Aplicar ajustes recomendados')
    }

    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    if ($references.ContainsKey($Name)) { return [string]$references[$Name] }

    # Etapa gravada noutro idioma da interface (o histórico guarda o nome como apareceu na tela).
    foreach ($key in $references.Keys) {
        if ((Get-TFToolkitText $key) -ceq $Name) { return [string]$references[$key] }
    }

    return ""
}


function Write-TFToolkitLastMaintenanceSteps {
    <#
    A primeira seção do histórico: a última manutenção e, uma por linha, as etapas que pediram atenção nela, com o
    motivo guardado e onde rodá-la sozinha de novo ("Página > Item"). É o que o cartão Última manutenção (do Início e da
    página) resume em "2 etapas com atenção". Sem registro, não escreve nada; registro ilegível é um aviso.
    #>
    $last = $null

    try {
        $last = Get-TFToolkitLastMaintenance -Strict
    }
    catch {
        Write-TFToolkitStatus -Type Warning -Notice -Message (Get-TFToolkitText 'Não foi possível ler a última manutenção agora: o arquivo está em uso ou sem permissão.')
        return
    }

    if ($null -eq $last) { return }

    Write-TFToolkitSection -Title (Get-TFToolkitText 'A última manutenção ({0})' "$(Format-TFToolkitDateTime -When ([datetime]$last.StartedAt))")

    $attention = @(@($last.Results) | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties["Kind"] -and [string]$_.Kind -in @("Warning", "Failed") })

    if ($attention.Count -eq 0) {
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhuma etapa pediu atenção.')
        return
    }

    foreach ($step in $attention) {
        # Gravados como apareceram na tela: de uma versão em português, saem no idioma de agora.
        $status = Get-TFToolkitText ([string](Get-TFToolkitJsonValue -Object $step -Name "Status" -Default ""))
        if ([string]::IsNullOrWhiteSpace($status)) { $status = $(if ([string]$step.Kind -eq "Failed") { (Get-TFToolkitText 'Falhou') } else { (Get-TFToolkitText 'Atenção') }) }

        $name = Get-TFToolkitText ([string](Get-TFToolkitJsonValue -Object $step -Name "Etapa" -Default ""))
        if ([string]::IsNullOrWhiteSpace($name)) { $name = (Get-TFToolkitText 'Etapa sem nome') }

        $text = "$($name): $status"
        $reference = Get-TFToolkitMaintenanceStepReference -Name $name
        if (-not [string]::IsNullOrEmpty($reference)) { $text += (Get-TFToolkitText '; rode de novo em {0}' "$reference") }

        # Aviso à vista (com o ícone), mas não um desfecho: só olhar o histórico não termina "com ressalvas".
        Write-TFToolkitStatus -Type Warning -Notice -Message $text
    }
}


function Show-TFToolkitMaintenanceHistory {
    # Uma tela de consulta: termina sem veredito (sem a faixa "Tudo certo"); o que pede atenção aparece com o ícone de
    # aviso, mas não vira desfecho. Primeiro a última manutenção, com o que pediu atenção nela (é por isso que a pessoa
    # chega aqui pelo cartão Última manutenção); depois a última verificação, as tendências e a lista.
    Enter-TFToolkitAction -Title (Get-TFToolkitText 'Histórico de manutenções')

    try {
        Write-TFToolkitLastMaintenanceSteps

        # O último Verificar o PC: o cartão Última manutenção conta os dois, e a pessoa que clicou nele precisa ver aqui
        # a verificação que ele citou. Uma data no futuro (relógio adiantado) não vira "agora há pouco".
        # Preferências presas por outro programa não viram "ainda não feita".
        $checkupText = (Get-TFToolkitText 'ainda não feita')

        try {
            $checkupAt = Get-TFToolkitLastCheckup -Strict

            if ($null -ne $checkupAt -and $checkupAt -gt (Get-Date).AddDays(1)) {
                $checkupText = (Get-TFToolkitText 'registrada com data depois da de hoje no relógio do Windows')
            }
            elseif ($null -ne $checkupAt) {
                $checkupText = "$(Format-TFToolkitRelativeTime -When $checkupAt) ($(Format-TFToolkitDateTime -When $checkupAt))"
            }
        }
        catch {
            $checkupText = (Get-TFToolkitText 'não foi possível ler')
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Verificar o PC')
        Write-TFToolkitKeyValue -Label (Get-TFToolkitText 'Última verificação') -Value $checkupText -LabelWidth 34

        $read = Get-TFToolkitMaintenanceHistory -Status
        $history = @($read.Entries)

        # Um histórico que existe, mas não abriu agora (preso por outro programa, sem permissão), não é "nenhuma manutenção".
        if ($read.Status -eq "Unreadable") {
            Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível ler o histórico de manutenções agora: o arquivo está em uso ou sem permissão. Tente de novo em instantes.')
            Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Title (Get-TFToolkitText 'Histórico de manutenções') -Detail (Get-TFToolkitText 'o arquivo do histórico está em uso ou sem permissão'))
            return
        }

        if ($history.Count -eq 0) {
            Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'Nenhuma manutenção registrada ainda. Ela aparece aqui depois de Manutenção > Otimizar; a execução mensal fica em Manutenção > Manutenção agendada.')
            Exit-TFToolkitAction
            return
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Tendências')

        foreach ($row in @(Get-TFToolkitMaintenanceTrends -History $history)) {
            if ($row.Level -eq "Warning") {
                # Aviso à vista (com o ícone), mas não um desfecho: só olhar o histórico não termina "com ressalvas".
                Write-TFToolkitStatus -Type Warning -Notice -Message "$($row.Label): $($row.Text)"
            }
            else {
                Write-TFToolkitKeyValue -Label $row.Label -Value $row.Text -LabelWidth 34
            }
        }

        Write-TFToolkitSection -Title (Get-TFToolkitText 'Últimas manutenções')

        foreach ($entry in $history) {
            Write-TFToolkitKeyValue -Label (Format-TFToolkitDateTime -When $entry.StartedAt) -Value (Format-TFToolkitHistoryLine -Entry $entry) -LabelWidth 18
        }

        Write-Host ""
        Write-TFToolkitStatus -Type Info -Message (Get-TFToolkitText 'O TF-Toolkit guarda as últimas {0} manutenções neste computador (pasta de dados do TF-Toolkit).' "$(Get-TFToolkitMaintenanceHistoryLimit)")
    }
    catch {
        Write-TFToolkitStatus -Type Error -Message (Get-TFToolkitText 'Não foi possível ler o histórico: {0}' "$($_.Exception.Message)")
        Exit-TFToolkitAction -Result (New-TFToolkitResult -Kind Failed -Title (Get-TFToolkitText 'Histórico de manutenções') -Detail $_.Exception.Message)
        return
    }

    Exit-TFToolkitAction
}


function Get-TFToolkitMaintenancePageStatus {
    <#
    O resumo no alto da página Manutenção, como o das outras páginas (New-GuiPageStatus): a última manutenção, com a mesma
    leitura do Início (Read-TFToolkitHomeMaintenance, só arquivos pequenos do TF-Toolkit). A linha leva ao Histórico de
    manutenções (Opens, o mesmo destino do Início), onde está o que pediu atenção nela. Cada linha tem Label, Text,
    Level (Normal | Warn | Muted) e Opens.
    #>
    $label = (Get-TFToolkitText 'Última manutenção')
    $opens = Get-TFToolkitHomeFactTarget -Id "maintenance"
    $fact = $null

    try {
        $fact = @(@((Read-TFToolkitHomeMaintenance).Facts) | Where-Object { $null -ne $_ })[0]
    }
    catch {
        $fact = $null
    }

    if ($null -eq $fact) {
        return @([PSCustomObject]@{ Label = $label; Text = (Get-TFToolkitText 'não foi possível ler'); Level = "Muted"; Opens = $opens })
    }

    # A frase do Início (o valor, a data e o que pede atenção) e, quando ela não o traz, o complemento do cartão ("o ideal
    # é uma por mês", "confira o relógio").
    $text = [string]$fact.Text
    $detail = [string](Get-TFToolkitJsonValue -Object $fact -Name "Detail" -Default "")
    if ($detail -and -not $text.Contains($detail)) { $text = "$text · $detail" }

    $level = $(switch ([string]$fact.Level) { "Warn" { "Warn" } "Muted" { "Muted" } default { "Normal" } })

    return @([PSCustomObject]@{ Label = $label; Text = $text; Level = $level; Opens = $opens })
}


Export-ModuleMember -Function *
