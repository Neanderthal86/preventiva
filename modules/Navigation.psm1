# Navegação: a única tabela com as páginas e ações do TF-Toolkit. A barra lateral da janela e os menus do console
# leem daqui, então a ordem e os nomes nunca ficam diferentes entre as duas interfaces.
#
# Ordem das páginas: primeiro o caminho guiado (Manutenção); depois as ferramentas manuais na sequência natural de
# quem cuida de um PC: olhar o estado, limpar, consertar, atualizar, instalar programas, conferir a rede e, por fim,
# personalizar. A página do próprio TF-Toolkit fica no rodapé da barra lateral (Placement = Footer).
#
# Nomes: o rótulo de uma ação é o mesmo texto do título que ela mostra ao abrir (um teste confere), para que o botão
# clicado e a tela aberta nunca tenham nomes diferentes. Ações usam verbo no infinitivo; telas de consulta usam o
# nome do que mostram; atalhos para o Windows usam o nome do painel e a descrição começa com "Abre".
# Dentro de cada página a ordem vai do mais seguro (só olhar) ao que mexe mais fundo no sistema.

$script:TFToolkitNavigation = $null


function New-TFToolkitNavItem {
    # Kind = Action (executa uma função do TF-Toolkit) ou Shortcut (abre uma janela do Windows).
    # RequiresAdmin: a ação só funciona elevada (a janela aberta sem Administrador, quando o aviso do Windows foi recusado,
    # pede de novo antes).
    # Keywords: palavras extras que a busca reconhece (sinônimos, nomes de ferramentas, sintomas).
    # Group: a seção da página em que o item aparece ("Liberar espaço", "Ferramentas do Windows"); os itens de uma seção
    # ficam juntos na tabela, e a janela e o console mostram o nome da seção antes deles.
    # Unlisted: a janela não mostra o item como cartão da página (ele é aberto por outro caminho, como o cartão de
    # informação no alto dela); a busca, o console e os links "Página > Item" continuam chegando nele.
    # Description: uma linha, de até 60 caracteres (a janela mostra numa linha só); Detail: a frase inteira, quando a
    # da linha é a curta (a dica ao passar o mouse, o leitor de tela e a busca).
    # ListCategory: numa página de ajustes, o item vira uma linha no fim do grupo dessa categoria, e não um botão no alto.
    param (
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Description,
        [string]$Command = "",
        [string]$Shortcut = "",
        [switch]$Accent,
        [switch]$Admin,
        [string]$Keywords = "",
        [string]$Group = "",
        [switch]$Unlisted,
        [string]$Detail = "",
        [string]$ListCategory = "",

        # O texto do botão no destaque da página (o item com Accent, New-GuiHeroCard): o verbo do que ele faz.
        [string]$ButtonText = ""
    )

    return [PSCustomObject]@{
        Id            = $Id
        Label         = $Label
        Group         = $Group
        Description   = $Description
        Kind          = $(if ([string]::IsNullOrEmpty($Shortcut)) { "Action" } else { "Shortcut" })
        Command       = $Command
        Shortcut      = $Shortcut
        Accent        = [bool]$Accent
        RequiresAdmin = [bool]$Admin
        Keywords      = $Keywords
        Unlisted      = [bool]$Unlisted
        Detail        = $Detail
        ListCategory  = $ListCategory
        ButtonText    = $ButtonText
    }
}


function New-TFToolkitNavPage {
    # Kind = List (cartões) ou Tweaks (lista de interruptores montada a partir do catálogo de ajustes; os Items são a
    # barra de ações da página). Placement = Main (lista principal da barra lateral) ou Footer (rodapé).
    param (
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Summary,
        [object[]]$Items = @(),
        [ValidateSet("List", "Tweaks")]
        [string]$Kind = "List",
        [ValidateSet("Main", "Footer")]
        [string]$Placement = "Main"
    )

    return [PSCustomObject]@{
        Id        = $Id
        Title     = $Title
        Summary   = $Summary
        Kind      = $Kind
        Placement = $Placement
        Items     = @($Items)
    }
}


function Get-TFToolkitNavigation {
    if ($null -ne $script:TFToolkitNavigation) {
        return $script:TFToolkitNavigation
    }

    $pages = @()

    # Manutenção: na janela, a faixa "Última manutenção" no alto abre o histórico, e os dois grupos têm três linhas cada.
    # O histórico e o Agendador de Tarefas não viram linha (Unlisted), mas a busca e o console chegam neles.
    $pages += New-TFToolkitNavPage -Id "maintenance" -Title (Get-TFToolkitText 'Manutenção') -Summary (Get-TFToolkitText 'Cuide do PC e volte atrás se algo der errado.') -Items @(
        (New-TFToolkitNavItem -Id "maintenance.recommended" -Label (Get-TFToolkitText 'Otimizar') -ButtonText (Get-TFToolkitText 'Otimizar agora') -Group (Get-TFToolkitText 'Cuidar do PC') -Admin -Accent `
            -Keywords (Get-TFToolkitText 'manutenção recomendada completa profunda windows acelerar lento tudo guiada limpeza reparo atualizar') `
            -Description (Get-TFToolkitText 'A manutenção completa, em ordem; pode passar de uma hora') -Detail (Get-TFToolkitText 'A manutenção completa do PC, em ordem; pode levar mais de uma hora') -Command "Invoke-TFToolkitRecommendedMaintenance"),
        (New-TFToolkitNavItem -Id "maintenance.checkup" -Label (Get-TFToolkitText 'Verificar o PC') -Group (Get-TFToolkitText 'Cuidar do PC') -Admin `
            -Keywords (Get-TFToolkitText 'escanear examinar scan check-up checkup diagnóstico um clique corrigir problemas saúde') `
            -Description (Get-TFToolkitText 'Confere o PC e corrige num clique o que é seguro') -Detail (Get-TFToolkitText 'Confere o PC em uma passada e corrige, num clique, o que é seguro') -Command "Invoke-TFToolkitCheckup"),
        (New-TFToolkitNavItem -Id "maintenance.schedule" -Label (Get-TFToolkitText 'Manutenção agendada') -Group (Get-TFToolkitText 'Cuidar do PC') -Admin `
            -Keywords (Get-TFToolkitText 'automática mensal tarefa sozinha agendar') `
            -Description (Get-TFToolkitText 'Limpeza leve e relatório todo mês, sem abrir o TF-Toolkit') -Detail (Get-TFToolkitText 'Uma limpeza leve e um relatório todo mês, sem você abrir o TF-Toolkit') -Command "Show-TFToolkitScheduledMaintenance"),
        (New-TFToolkitNavItem -Id "maintenance.history" -Label (Get-TFToolkitText 'Histórico de manutenções') -Group (Get-TFToolkitText 'Cuidar do PC') -Unlisted `
            -Keywords (Get-TFToolkitText 'última manutenção tendência espaço duração falhas atenção') `
            -Description (Get-TFToolkitText 'A última manutenção e a variação de espaço das anteriores') -Detail (Get-TFToolkitText 'A última manutenção, o que pediu atenção nela e a variação de espaço das anteriores') -Command "Show-TFToolkitMaintenanceHistory"),
        (New-TFToolkitNavItem -Id "maintenance.task-scheduler" -Label (Get-TFToolkitText 'Agendador de Tarefas') -Group (Get-TFToolkitText 'Cuidar do PC') -Unlisted `
            -Keywords (Get-TFToolkitText 'taskschd agendar tarefas') `
            -Description (Get-TFToolkitText 'Abre o Agendador de Tarefas, onde fica a tarefa do TF-Toolkit') -Detail (Get-TFToolkitText 'Abre o Agendador de Tarefas do Windows, onde a tarefa do TF-Toolkit aparece') -Shortcut "TaskScheduler"),
        (New-TFToolkitNavItem -Id "maintenance.restore-point" -Label (Get-TFToolkitText 'Criar ponto de restauração') -Group (Get-TFToolkitText 'Se algo der errado') -Admin `
            -Keywords (Get-TFToolkitText 'backup segurança voltar atrás proteção do sistema') `
            -Description (Get-TFToolkitText 'Guarda o Windows de agora, para voltar a ele depois') -Detail (Get-TFToolkitText 'Guarda o estado do Windows de agora, para voltar a ele depois') -Command "Invoke-TFToolkitRestorePoint"),
        (New-TFToolkitNavItem -Id "maintenance.changes" -Label (Get-TFToolkitText 'Histórico de mudanças') -Group (Get-TFToolkitText 'Se algo der errado') `
            -Keywords (Get-TFToolkitText 'desfazer voltar atrás reverter restaurar registro backup central de resgate mudanças feitas') `
            -Description (Get-TFToolkitText 'O que o TF-Toolkit mudou no PC; desfaça o que tiver volta') -Command "Show-TFToolkitChangeHistory"),
        (New-TFToolkitNavItem -Id "maintenance.restore" -Label (Get-TFToolkitText 'Restauração do Sistema') -Group (Get-TFToolkitText 'Se algo der errado') `
            -Keywords (Get-TFToolkitText 'voltar desfazer rstrui restore') `
            -Description (Get-TFToolkitText 'Abre a janela que volta o PC a um ponto de restauração') -Detail (Get-TFToolkitText 'Abre a janela do Windows que volta o PC a um ponto de restauração') -Shortcut "SystemRestore")
    )

    $pages += New-TFToolkitNavPage -Id "diagnostics" -Title (Get-TFToolkitText 'Diagnóstico') -Summary (Get-TFToolkitText 'Veja como o PC está antes de mexer em qualquer coisa.') -Items @(
        (New-TFToolkitNavItem -Id "diagnostics.about" -Label (Get-TFToolkitText 'Sobre este PC') -ButtonText (Get-TFToolkitText 'Ver detalhes') -Group (Get-TFToolkitText 'Visão geral') -Accent `
            -Keywords (Get-TFToolkitText 'cpu ram processador memória gpu placa de vídeo hardware especificações configuração xmp winver') `
            -Description (Get-TFToolkitText 'Windows, processador, memória, vídeo, discos e Secure Boot') -Detail (Get-TFToolkitText 'Windows, processador, memória, placa de vídeo, discos e Secure Boot') -Command "Show-TFToolkitSystemInfo"),
        (New-TFToolkitNavItem -Id "diagnostics.windows-support" -Label (Get-TFToolkitText 'Suporte do Windows') -Group (Get-TFToolkitText 'Visão geral') `
            -Keywords (Get-TFToolkitText 'fim do suporte windows 10 windows 11 atualizações de segurança esu requisitos tpm compatível upgrade versão 24h2 25h2') `
            -Description (Get-TFToolkitText 'Até quando há atualizações e se dá para ir ao Windows 11') -Detail (Get-TFToolkitText 'Até quando este Windows recebe atualizações de segurança e se o PC pode ir para o Windows 11') -Command "Show-TFToolkitWindowsSupport"),
        (New-TFToolkitNavItem -Id "diagnostics.report" -Label (Get-TFToolkitText 'Exportar relatório') -Group (Get-TFToolkitText 'Visão geral') `
            -Keywords (Get-TFToolkitText 'salvar html txt relatório laudo') `
            -Description (Get-TFToolkitText 'Salva o estado do PC em HTML e texto, para guardar ou mandar') -Detail (Get-TFToolkitText 'Salva o estado do PC em HTML e em texto, para guardar ou mandar a quem vai ajudar') -Command "Invoke-TFToolkitReport"),
        (New-TFToolkitNavItem -Id "diagnostics.disks" -Label (Get-TFToolkitText 'Discos e espaço livre') -Group (Get-TFToolkitText 'Hardware') `
            -Keywords (Get-TFToolkitText 'armazenamento ssd hdd hd cheio capacidade unidade') `
            -Description (Get-TFToolkitText 'SSD ou HDD, espaço livre e uso de cada unidade') -Command "Show-TFToolkitDisks"),
        (New-TFToolkitNavItem -Id "diagnostics.disk-health" -Label (Get-TFToolkitText 'Saúde dos discos') -Group (Get-TFToolkitText 'Hardware') -Admin `
            -Keywords (Get-TFToolkitText 'smart temperatura desgaste ssd hdd hd falha') `
            -Description (Get-TFToolkitText 'Estado, temperatura, desgaste e erros de cada disco') -Command "Show-TFToolkitDiskHealth"),
        (New-TFToolkitNavItem -Id "diagnostics.devices" -Label (Get-TFToolkitText 'Dispositivos com problema') -Group (Get-TFToolkitText 'Hardware') `
            -Keywords (Get-TFToolkitText 'driver drivers erro hardware câmera webcam som áudio microfone fone impressora teclado mouse bluetooth pendrive usb reconhecido tela piscando') `
            -Description (Get-TFToolkitText 'Drivers e hardware com erro') -Command "Show-TFToolkitProblemDevices"),
        (New-TFToolkitNavItem -Id "diagnostics.battery" -Label (Get-TFToolkitText 'Saúde da bateria') -Group (Get-TFToolkitText 'Hardware') `
            -Keywords (Get-TFToolkitText 'notebook laptop carga ciclos desgaste energia') `
            -Description (Get-TFToolkitText 'Capacidade de hoje e de fábrica, ciclos e carga atual') -Detail (Get-TFToolkitText 'Capacidade de hoje comparada à de fábrica, ciclos de carga e carga atual') -Command "Show-TFToolkitBatteryHealth"),
        (New-TFToolkitNavItem -Id "diagnostics.memory-test" -Label (Get-TFToolkitText 'Teste de memória') -Group (Get-TFToolkitText 'Hardware') -Admin `
            -Keywords (Get-TFToolkitText 'ram memória mdsched pente defeito tela azul memtest teste') `
            -Description (Get-TFToolkitText 'Testa a memória (RAM) no próximo reinício') -Detail (Get-TFToolkitText 'Testa a memória (RAM) no próximo reinício; o resultado aparece depois') -Command "Start-TFToolkitMemoryTest"),
        (New-TFToolkitNavItem -Id "diagnostics.events" -Label (Get-TFToolkitText 'Eventos críticos (7 dias)') -Group (Get-TFToolkitText 'Funcionamento do Windows') `
            -Keywords (Get-TFToolkitText 'erro tela azul preta travou travando travamento queda de energia falha log reiniciando reiniciou desligando desligou visualizador de eventos eventvwr') `
            -Description (Get-TFToolkitText 'Quedas de energia, tela azul, erros de disco e de hardware') -Command "Show-TFToolkitCriticalEvents"),
        (New-TFToolkitNavItem -Id "diagnostics.blue-screens" -Label (Get-TFToolkitText 'Telas azuis') -Group (Get-TFToolkitText 'Funcionamento do Windows') `
            -Keywords (Get-TFToolkitText 'tela azul bsod bugcheck stop code erro travou reiniciou reiniciando reinicia sozinho minidump') `
            -Description (Get-TFToolkitText 'Dos últimos 90 dias, com a causa provável') -Detail (Get-TFToolkitText 'As telas azuis dos últimos 90 dias, com a causa provável e o que fazer') -Command "Show-TFToolkitBlueScreens"),
        (New-TFToolkitNavItem -Id "diagnostics.pending-reboot" -Label (Get-TFToolkitText 'Reinício pendente') -Group (Get-TFToolkitText 'Funcionamento do Windows') `
            -Keywords (Get-TFToolkitText 'reiniciar reboot restart') `
            -Description (Get-TFToolkitText 'O que espera um reinício e se ele é mesmo necessário') -Detail (Get-TFToolkitText 'O que está esperando um reinício, se ele é mesmo necessário, e reiniciar quando quiser') -Command "Show-TFToolkitPendingReboot"),
        (New-TFToolkitNavItem -Id "diagnostics.startup" -Label (Get-TFToolkitText 'Tempo ligado e energia') -Group (Get-TFToolkitText 'Funcionamento do Windows') `
            -Keywords (Get-TFToolkitText 'boot lento ligar demora inicialização rápida hibernar hibernação energia uptime') `
            -Description (Get-TFToolkitText 'Tempo ligado, Inicialização Rápida e hibernação') -Detail (Get-TFToolkitText 'Quanto tempo o PC está ligado, Inicialização Rápida e hibernação') -Command "Show-TFToolkitStartupInfo"),
        (New-TFToolkitNavItem -Id "diagnostics.reliability" -Label (Get-TFToolkitText 'Monitor de Confiabilidade') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'falhas travamentos histórico confiabilidade perfmon') `
            -Description (Get-TFToolkitText 'Abre o histórico de falhas do Windows') -Shortcut "Reliability"),
        (New-TFToolkitNavItem -Id "diagnostics.device-manager" -Label (Get-TFToolkitText 'Gerenciador de Dispositivos') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'devmgmt drivers') `
            -Description (Get-TFToolkitText 'Abre o Gerenciador de Dispositivos do Windows') -Shortcut "DeviceManager")
    )

    $pages += New-TFToolkitNavPage -Id "security" -Title (Get-TFToolkitText 'Segurança') -Summary (Get-TFToolkitText 'Veja se o PC está protegido e rode a verificação do Windows.') -Items @(
        (New-TFToolkitNavItem -Id "security.status" -Label (Get-TFToolkitText 'Estado da proteção') -ButtonText (Get-TFToolkitText 'Ver a proteção') -Group (Get-TFToolkitText 'Proteção') -Accent `
            -Keywords (Get-TFToolkitText 'vírus malware defender firewall antivírus proteção ameaça') `
            -Description (Get-TFToolkitText 'Antivírus, assinaturas, firewall e ameaças ativas') -Detail (Get-TFToolkitText 'Antivírus, assinaturas, firewall, atualizações pendentes e ameaças ativas') -Command "Show-TFToolkitSecurityStatus"),
        (New-TFToolkitNavItem -Id "security.audit" -Label (Get-TFToolkitText 'Auditoria de segurança') -Group (Get-TFToolkitText 'Proteção') `
            -Description (Get-TFToolkitText 'Senhas, acesso remoto, criptografia e mais, com uma nota') -Detail (Get-TFToolkitText 'Além do antivírus e do firewall, confere senhas, acesso remoto e criptografia, e dá uma nota') -Command "Show-TFToolkitSecurityAudit" `
            -Keywords (Get-TFToolkitText 'nota uac smartscreen bitlocker criptografia secure boot remota rdp convidado senha entrada automática')),
        (New-TFToolkitNavItem -Id "security.bitlocker-key" -Label (Get-TFToolkitText 'Chave de recuperação do BitLocker') -Group (Get-TFToolkitText 'Proteção') -Admin `
            -Keywords (Get-TFToolkitText 'bitlocker chave recuperação criptografia bloqueado recovery key 48 números') `
            -Description (Get-TFToolkitText 'Se o disco está criptografado; guarda a chave fora do PC') -Detail (Get-TFToolkitText 'Mostra se o disco está criptografado e guarda uma cópia da chave fora do PC') -Command "Show-TFToolkitBitLockerKey"),
        (New-TFToolkitNavItem -Id "security.signatures" -Label (Get-TFToolkitText 'Atualizar assinaturas do antivírus') -Group (Get-TFToolkitText 'Proteção') -Admin `
            -Keywords (Get-TFToolkitText 'vírus malware definições atualizar defender') `
            -Description (Get-TFToolkitText 'Baixa a lista mais nova de vírus do Windows Defender') -Detail (Get-TFToolkitText 'Baixa do Windows Defender a lista mais nova de vírus conhecidos (as assinaturas)') -Command "Update-TFToolkitDefenderSignatures"),
        (New-TFToolkitNavItem -Id "security.scan" -Label (Get-TFToolkitText 'Verificar vírus') -Group (Get-TFToolkitText 'Procurar ameaças') -Admin `
            -Keywords (Get-TFToolkitText 'vírus antivírus malware ransomware trojan scan escanear examinar varredura assinaturas um clique verificação rápida') `
            -Description (Get-TFToolkitText 'Atualiza e faz a verificação rápida do Windows Defender') -Detail (Get-TFToolkitText 'Atualiza o antivírus e faz a verificação rápida do Windows Defender, em alguns minutos') -Command "Invoke-TFToolkitSecurityCheck"),
        (New-TFToolkitNavItem -Id "security.full-scan" -Label (Get-TFToolkitText 'Verificação completa de vírus') -Group (Get-TFToolkitText 'Procurar ameaças') -Admin `
            -Keywords (Get-TFToolkitText 'vírus malware ransomware trojan scan antivírus escanear examinar horas') `
            -Description (Get-TFToolkitText 'O Defender examina todos os arquivos; pode levar horas') -Detail (Get-TFToolkitText 'Atualiza o antivírus e o Windows Defender examina todos os arquivos; pode levar horas') -Command "Start-TFToolkitFullScan"),
        (New-TFToolkitNavItem -Id "security.folder-scan" -Label (Get-TFToolkitText 'Verificar uma pasta') -Group (Get-TFToolkitText 'Procurar ameaças') -Admin `
            -Keywords (Get-TFToolkitText 'vírus malware scan arquivo suspeito suspeita baixado download pendrive pen drive usb cartão de memória') `
            -Description (Get-TFToolkitText 'O Defender examina uma pasta, um arquivo ou um pendrive') -Detail (Get-TFToolkitText 'Atualiza o antivírus e o Windows Defender examina só a pasta, o arquivo ou o pendrive que você indicar') -Command "Start-TFToolkitFolderScan"),
        (New-TFToolkitNavItem -Id "security.windows-security" -Label (Get-TFToolkitText 'Segurança do Windows') -Group (Get-TFToolkitText 'Procurar ameaças') `
            -Keywords (Get-TFToolkitText 'windows security defender firewall vírus offline proteção quarentena histórico') `
            -Description (Get-TFToolkitText 'Abre o aplicativo do Windows, com a verificação offline') -Detail (Get-TFToolkitText 'Abre o aplicativo do Windows, com a verificação offline e o histórico de proteção') -Shortcut "WindowsSecurity")
    )

    $pages += New-TFToolkitNavPage -Id "cleanup" -Title (Get-TFToolkitText 'Limpeza') -Summary (Get-TFToolkitText 'Libere espaço, do mais seguro ao mais profundo.') -Items @(
        (New-TFToolkitNavItem -Id "cleanup.quick" -Label (Get-TFToolkitText 'Limpeza rápida') -ButtonText (Get-TFToolkitText 'Limpar agora') -Group (Get-TFToolkitText 'Liberar espaço') -Admin -Accent `
            -Keywords (Get-TFToolkitText 'limpar liberar espaço sem espaço lixo lento temp tmp temporários arquivos apagar limpeza de disco clean cleanup cleaner disk cleanmgr') `
            -Description (Get-TFToolkitText 'Temporários do usuário e do Windows, e a Lixeira se quiser') -Detail (Get-TFToolkitText 'Temporários do usuário e do Windows e, se você quiser, a Lixeira') -Command "Invoke-TFToolkitQuickCleanup"),
        (New-TFToolkitNavItem -Id "cleanup.space" -Label (Get-TFToolkitText 'Analisar uso de espaço') -Group (Get-TFToolkitText 'Liberar espaço') `
            -Keywords (Get-TFToolkitText 'disco cheio o que ocupa espaço maiores pastas tamanho armazenamento ocupa windows.old hiberfil hibernação pagefile memória virtual swapfile') `
            -Description (Get-TFToolkitText 'O que ocupa o disco e quanto a limpeza libera') -Detail (Get-TFToolkitText 'Mostra o que a limpeza libera, as maiores pastas do perfil e os arquivos grandes do sistema') -Command "Show-TFToolkitSpaceAnalysis"),
        (New-TFToolkitNavItem -Id "cleanup.custom" -Label (Get-TFToolkitText 'Limpeza personalizada') -Group (Get-TFToolkitText 'Liberar espaço') -Admin `
            -Keywords (Get-TFToolkitText 'escolher lista tamanhos temporários do usuário temporários do windows cache navegador relatórios de erro otimização de entrega delivery optimization despejo memória dump') `
            -Description (Get-TFToolkitText 'Escolha item por item, vendo o tamanho de cada um') -Detail (Get-TFToolkitText 'Você marca numa lista, com o tamanho de cada item: temporários, caches, despejos de falhas, Lixeira') -Command "Invoke-TFToolkitCustomCleanup"),
        (New-TFToolkitNavItem -Id "cleanup.recycle-bin" -Label (Get-TFToolkitText 'Esvaziar a Lixeira') -Group (Get-TFToolkitText 'Liberar espaço') `
            -Keywords (Get-TFToolkitText 'lixo excluídos apagados') `
            -Description (Get-TFToolkitText 'Apaga de vez o que está na Lixeira, em todas as unidades') -Detail (Get-TFToolkitText 'Remove em definitivo o que está na Lixeira, de todas as unidades') -Command "Clear-TFToolkitRecycleBin"),
        (New-TFToolkitNavItem -Id "cleanup.downloads" -Label (Get-TFToolkitText 'Limpar a pasta Downloads') -Group (Get-TFToolkitText 'Liberar espaço') `
            -Keywords (Get-TFToolkitText 'baixados arquivos antigos apagar excluir remover') `
            -Description (Get-TFToolkitText 'Prévia e filtro por idade antes de apagar') -Detail (Get-TFToolkitText 'Você vê uma prévia, filtra por idade e escolhe entre a Lixeira e a exclusão') -Command "Clear-TFToolkitDownloads"),
        (New-TFToolkitNavItem -Id "cleanup.storage" -Label (Get-TFToolkitText 'Configurações de armazenamento') -Group (Get-TFToolkitText 'Liberar espaço') `
            -Keywords (Get-TFToolkitText 'sensor de armazenamento configurações espaço') `
            -Description (Get-TFToolkitText 'Abre a página Armazenamento, nas Configurações') -Detail (Get-TFToolkitText 'Abre Armazenamento, nas Configurações do Windows, onde ficam os arquivos temporários e o Sensor de Armazenamento') -Shortcut "Storage"),
        (New-TFToolkitNavItem -Id "cleanup.shortcuts" -Label (Get-TFToolkitText 'Remover atalhos quebrados') -Group (Get-TFToolkitText 'Arrumar o que sobrou') `
            -Keywords (Get-TFToolkitText 'atalho quebrado inválido lnk ícone não abre') `
            -Description (Get-TFToolkitText 'Atalhos que apontam para o que não existe mais') -Detail (Get-TFToolkitText 'Atalhos que apontam para o que não existe mais; eles vão para a Lixeira') -Command "Remove-TFToolkitBrokenShortcuts"),
        (New-TFToolkitNavItem -Id "cleanup.duplicates" -Label (Get-TFToolkitText 'Encontrar arquivos duplicados') -Group (Get-TFToolkitText 'Arrumar o que sobrou') `
            -Keywords (Get-TFToolkitText 'duplicado duplicados cópia cópias repetidos iguais fotos espaço') `
            -Description (Get-TFToolkitText 'Arquivos iguais numa pasta; você escolhe o que sai') -Detail (Get-TFToolkitText 'Arquivos iguais (mesmo conteúdo) numa pasta; você escolhe o que vai para a Lixeira') -Command "Find-TFToolkitDuplicateFiles"),
        (New-TFToolkitNavItem -Id "cleanup.leftovers" -Label (Get-TFToolkitText 'Restos de programas desinstalados') -Group (Get-TFToolkitText 'Arrumar o que sobrou') `
            -Keywords (Get-TFToolkitText 'sobras resíduos desinstalado pastas vazias appdata program files revo') `
            -Description (Get-TFToolkitText 'Pastas de programas que o TF-Toolkit desinstalou') -Detail (Get-TFToolkitText 'Pastas que sobraram de programas desinstalados pelo TF-Toolkit; você escolhe o que vai para a Lixeira') -Command "Find-TFToolkitProgramLeftovers"),
        (New-TFToolkitNavItem -Id "cleanup.registry" -Label (Get-TFToolkitText 'Limpar o registro') -Group (Get-TFToolkitText 'Avançado') `
            -Keywords (Get-TFToolkitText 'registro regedit chaves inválidas quebradas órfãs erros do registro limpador') `
            -Description (Get-TFToolkitText 'Só referências quebradas, com backup e desfazer') -Detail (Get-TFToolkitText 'Só referências quebradas a programas e arquivos que não existem mais; com backup e desfazer') -Command "Invoke-TFToolkitRegistryCleanup"),
        (New-TFToolkitNavItem -Id "cleanup.components" -Label (Get-TFToolkitText 'Limpar componentes do Windows (WinSxS)') -Group (Get-TFToolkitText 'Avançado') -Admin `
            -Keywords (Get-TFToolkitText 'winsxs dism component store atualizações antigas espaço') `
            -Description (Get-TFToolkitText 'Versões antigas deixadas pelas atualizações (DISM)') -Detail (Get-TFToolkitText 'Remove versões antigas de componentes substituídos por atualizações (DISM)') -Command "Invoke-TFToolkitComponentCleanup"),
        (New-TFToolkitNavItem -Id "cleanup.wipe-free" -Label (Get-TFToolkitText 'Apagar o espaço livre') -Group (Get-TFToolkitText 'Avançado') -Admin `
            -Keywords (Get-TFToolkitText 'cipher apagar com segurança vender doar sobrescrever definitivo') `
            -Description (Get-TFToolkitText 'Impede recuperar o que já foi apagado do disco') -Detail (Get-TFToolkitText 'Sobrescreve o espaço livre do disco: o que já foi apagado não pode mais ser trazido de volta') -Command "Clear-TFToolkitFreeSpace")
    )

    $pages += New-TFToolkitNavPage -Id "performance" -Title (Get-TFToolkitText 'Desempenho') -Summary (Get-TFToolkitText 'Deixe o PC mais leve agora e veja o que está pesando.') -Items @(
        (New-TFToolkitNavItem -Id "performance.boost" -Label (Get-TFToolkitText 'Acelerar agora') -ButtonText (Get-TFToolkitText 'Acelerar') -Group (Get-TFToolkitText 'Deixar o PC mais leve') -Accent `
            -Keywords (Get-TFToolkitText 'lento lentidão travando turbo boost otimizar memória ram rápido pc') `
            -Description (Get-TFToolkitText 'Libera memória e apaga temporários; o efeito é passageiro') -Detail (Get-TFToolkitText 'Libera memória e apaga os seus temporários, num clique; o efeito na memória é passageiro') -Command "Invoke-TFToolkitBoost"),
        (New-TFToolkitNavItem -Id "performance.processes" -Label (Get-TFToolkitText 'Programas pesando agora') -Group (Get-TFToolkitText 'Deixar o PC mais leve') `
            -Keywords (Get-TFToolkitText 'processos processo pesados pesado cpu processador memória ram travando lento fechar encerrar uso alto disco 100% esquentando quente temperatura superaquecendo superaquecimento ventoinha cooler barulho') `
            -Description (Get-TFToolkitText 'O que mais usa processador e memória agora') -Detail (Get-TFToolkitText 'O que mais usa o processador e a memória neste momento; você pode fechar o que quiser') -Command "Show-TFToolkitHeavyProcesses"),
        (New-TFToolkitNavItem -Id "performance.memory" -Label (Get-TFToolkitText 'Liberar memória') -Group (Get-TFToolkitText 'Deixar o PC mais leve') `
            -Keywords (Get-TFToolkitText 'ram memória cheia otimizar limpar memória') `
            -Description (Get-TFToolkitText 'Tira da memória o que os programas abertos ocupam') -Detail (Get-TFToolkitText 'Tira da memória o que os programas abertos ocupam; ajuda antes de abrir algo pesado') -Command "Invoke-TFToolkitMemoryOptimization"),
        (New-TFToolkitNavItem -Id "performance.startup" -Label (Get-TFToolkitText 'Gerenciar inicialização') -Group (Get-TFToolkitText 'Para o PC continuar leve') `
            -Keywords (Get-TFToolkitText 'programas iniciam abrem junto boot demora msconfig desativar reativar lento lenta lentidão startup abrir iniciar com o windows') `
            -Description (Get-TFToolkitText 'O que abre junto com o Windows; desligue o que não precisa') -Detail (Get-TFToolkitText 'O que abre junto com o Windows; desligar o que não precisa deixa o PC leve desde o início') -Command "Set-TFToolkitStartupItems"),
        (New-TFToolkitNavItem -Id "performance.task-manager" -Label (Get-TFToolkitText 'Gerenciador de Tarefas') -Group (Get-TFToolkitText 'Para o PC continuar leve') `
            -Keywords (Get-TFToolkitText 'taskmgr task manager ctrl shift esc processos desempenho') `
            -Description (Get-TFToolkitText 'Abre o Gerenciador de Tarefas do Windows') -Detail (Get-TFToolkitText 'Abre o Gerenciador de Tarefas do Windows; os gráficos de uso ficam na aba Desempenho') -Shortcut "TaskManager")
    )

    $pages += New-TFToolkitNavPage -Id "repair" -Title (Get-TFToolkitText 'Reparo') -Summary (Get-TFToolkitText 'Conserte o Windows e o disco, e mantenha a unidade em forma.') -Items @(
        (New-TFToolkitNavItem -Id "repair.dism-sfc" -Label (Get-TFToolkitText 'Reparar o Windows (DISM + SFC)') -ButtonText (Get-TFToolkitText 'Reparar') -Group (Get-TFToolkitText 'Arquivos do Windows') -Admin -Accent `
            -Keywords (Get-TFToolkitText 'corrigir consertar arquivos corrompidos corrupção erro windows travando instável tela azul') `
            -Description (Get-TFToolkitText 'Conserta arquivos do Windows; leva de 20 a 60 minutos') -Detail (Get-TFToolkitText 'Conserta arquivos danificados do Windows; costuma levar de 20 a 60 minutos e não apaga nada seu') -Command "Invoke-TFToolkitDismAndSfc"),
        (New-TFToolkitNavItem -Id "repair.dism" -Label (Get-TFToolkitText 'Reparar imagem e componentes (DISM)') -Group (Get-TFToolkitText 'Arquivos do Windows') -Admin `
            -Keywords (Get-TFToolkitText 'imagem corrompida componente store restorehealth cleanup-image update com erro atualização falhando travado travada falhou') `
            -Description (Get-TFToolkitText 'Restaura a base do Windows pela internet; 10 a 30 minutos') -Detail (Get-TFToolkitText 'Restaura os arquivos-base do Windows pela internet (Windows Update); leva de 10 a 30 minutos') -Command "Invoke-TFToolkitDism"),
        (New-TFToolkitNavItem -Id "repair.sfc" -Label (Get-TFToolkitText 'Verificar arquivos do sistema (SFC)') -Group (Get-TFToolkitText 'Arquivos do Windows') -Admin `
            -Keywords (Get-TFToolkitText 'scannow corrompidos arquivos protegidos integridade verificar integridade cbs') `
            -Description (Get-TFToolkitText 'Confere e conserta os arquivos protegidos; 5 a 20 minutos') -Detail (Get-TFToolkitText 'Confere os arquivos protegidos do Windows e conserta os danificados; leva de 5 a 20 minutos') -Command "Invoke-TFToolkitSfc"),
        (New-TFToolkitNavItem -Id "repair.chkdsk" -Label (Get-TFToolkitText 'Verificar o sistema de arquivos (CHKDSK)') -Group (Get-TFToolkitText 'Disco e dispositivos') -Admin `
            -Keywords (Get-TFToolkitText 'disco erros setores defeituosos bad sector verificar hd com problema ntfs fsutil disco corrompido') `
            -Description (Get-TFToolkitText 'Procura erros no disco sem reiniciar') -Detail (Get-TFToolkitText 'Procura erros no disco sem reiniciar; se precisar de reparo na reinicialização, pergunta antes') -Command "Start-TFToolkitChkdsk"),
        (New-TFToolkitNavItem -Id "repair.optimize" -Label (Get-TFToolkitText 'Otimizar a unidade do sistema') -Group (Get-TFToolkitText 'Disco e dispositivos') -Admin `
            -Keywords (Get-TFToolkitText 'trim ssd desfragmentar desfragmentação hdd defrag disco lento') `
            -Description (Get-TFToolkitText 'O que o Windows já faz toda semana, feito agora') -Detail (Get-TFToolkitText 'O que o Windows já faz sozinho toda semana (o TRIM num SSD, desfragmentar num HD), feito agora') -Command "Start-TFToolkitDriveOptimization"),
        (New-TFToolkitNavItem -Id "repair.device-scan" -Label (Get-TFToolkitText 'Detectar dispositivos e drivers') -Group (Get-TFToolkitText 'Disco e dispositivos') -Admin `
            -Keywords (Get-TFToolkitText 'driver drivers hardware novo pnp pnputil usb não reconhecido dispositivo não reconhecido') `
            -Description (Get-TFToolkitText 'Procura hardware novo e instala os drivers disponíveis') -Detail (Get-TFToolkitText 'Procura hardware novo e instala os drivers que já estejam disponíveis') -Command "Invoke-TFToolkitDeviceScan"),
        (New-TFToolkitNavItem -Id "repair.print-queue" -Label (Get-TFToolkitText 'Destravar a impressão') -Group (Get-TFToolkitText 'Disco e dispositivos') -Admin `
            -Keywords (Get-TFToolkitText 'impressora não imprime fila de impressão travada presa documento preso cancelar impressão spooler spool') `
            -Description (Get-TFToolkitText 'Reinicia o Spooler de Impressão; apagar a fila é escolha sua') -Detail (Get-TFToolkitText 'Para a impressora que não imprime: reinicia o Spooler de Impressão e, se você escolher, esvazia a fila') -Command "Reset-TFToolkitPrintQueue"),
        (New-TFToolkitNavItem -Id "repair.system-restore" -Label (Get-TFToolkitText 'Restauração do Sistema') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'voltar rstrui desfazer') `
            -Description (Get-TFToolkitText 'Abre a janela que volta o PC a um ponto de restauração') -Detail (Get-TFToolkitText 'Abre a janela do Windows que volta o PC a um ponto de restauração') -Shortcut "SystemRestore"),
        (New-TFToolkitNavItem -Id "repair.recovery" -Label (Get-TFToolkitText 'Recuperação') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'restaurar pc restaurar o pc restaurar este pc reinstalar formatar inicialização avançada modo de segurança reset') `
            -Description (Get-TFToolkitText 'Abre a Recuperação: restaurar o PC e inicialização avançada') -Detail (Get-TFToolkitText 'Abre a Recuperação do Windows: restaurar o PC e a inicialização avançada') -Shortcut "Recovery")
    )

    $pages += New-TFToolkitNavPage -Id "updates" -Title (Get-TFToolkitText 'Atualizações') -Summary (Get-TFToolkitText 'Windows, drivers, Microsoft Store e programas.') -Items @(
        (New-TFToolkitNavItem -Id "updates.install" -Label (Get-TFToolkitText 'Instalar atualizações do Windows') -ButtonText (Get-TFToolkitText 'Procurar atualizações') -Group (Get-TFToolkitText 'Windows e drivers') -Admin -Accent `
            -Keywords (Get-TFToolkitText 'baixar instalar atualizar windows update pendentes progresso reiniciar atualização atualizações pendente kb cumulativa segurança patch desatualizado pc') `
            -Description (Get-TFToolkitText 'Procura, baixa e instala aqui mesmo as atualizações') -Detail (Get-TFToolkitText 'Procura, baixa e instala aqui mesmo as atualizações pendentes, com o progresso na tela') -Command "Install-TFToolkitWindowsUpdates"),
        (New-TFToolkitNavItem -Id "updates.drivers" -Label (Get-TFToolkitText 'Atualizar drivers') -Group (Get-TFToolkitText 'Windows e drivers') -Admin `
            -Keywords (Get-TFToolkitText 'driver drivers placa de vídeo som rede wifi bluetooth chipset desatualizado opcionais') `
            -Description (Get-TFToolkitText 'Drivers do Windows Update; você marca quais instalar') -Detail (Get-TFToolkitText 'Procura drivers no Windows Update e instala os que você marcar; os opcionais vêm desmarcados') -Command "Install-TFToolkitDriverUpdates"),
        (New-TFToolkitNavItem -Id "updates.vendor-tools" -Label (Get-TFToolkitText 'Ferramentas do fabricante') -Group (Get-TFToolkitText 'Windows e drivers') `
            -Keywords (Get-TFToolkitText 'dell lenovo hp intel nvidia amd geforce radeon fabricante bios firmware support assistant command update') `
            -Description (Get-TFToolkitText 'O programa oficial do fabricante para drivers e BIOS') -Detail (Get-TFToolkitText 'Indica o programa oficial do fabricante do PC e da placa de vídeo, que acha drivers e BIOS') -Command "Show-TFToolkitVendorTools"),
        (New-TFToolkitNavItem -Id "updates.repair" -Label (Get-TFToolkitText 'Corrigir o Windows Update') -Group (Get-TFToolkitText 'Windows e drivers') -Admin `
            -Keywords (Get-TFToolkitText 'erro falha falhou falhando travado atualização travada preso parado cache softwaredistribution catroot2 resetar redefinir consertar') `
            -Description (Get-TFToolkitText 'Quando as atualizações falham: refaz o cache e os serviços') -Detail (Get-TFToolkitText 'Quando as atualizações falham ou travam: refaz o cache do Windows Update e religa os serviços') -Command "Repair-TFToolkitWindowsUpdate"),
        (New-TFToolkitNavItem -Id "updates.winget" -Label (Get-TFToolkitText 'Atualizar programas (winget)') -Group (Get-TFToolkitText 'Programas e aplicativos') `
            -Keywords (Get-TFToolkitText 'atualizar programas apps upgrade todos tudo desatualizado desatualizados navegador chrome firefox') `
            -Description (Get-TFToolkitText 'Programas com versão nova no winget; você escolhe quais') -Detail (Get-TFToolkitText 'Mostra os programas com versão nova no winget e atualiza os que você escolher') -Command "Update-TFToolkitSoftware"),
        (New-TFToolkitNavItem -Id "updates.winget-hold" -Label (Get-TFToolkitText 'Manter programas na versão atual') -Group (Get-TFToolkitText 'Programas e aplicativos') `
            -Keywords (Get-TFToolkitText 'não atualizar segurar bloquear travar fixar congelar versão antiga pin winget pausar atualização de programa') `
            -Description (Get-TFToolkitText 'Marque os programas que o TF-Toolkit não deve atualizar') -Detail (Get-TFToolkitText 'Marque os programas que devem ficar na versão de agora: eles saem das atualizações do TF-Toolkit') -Command "Set-TFToolkitWingetPins"),
        (New-TFToolkitNavItem -Id "updates.store" -Label (Get-TFToolkitText 'Atualizar aplicativos da Microsoft Store') -Group (Get-TFToolkitText 'Programas e aplicativos') `
            -Keywords (Get-TFToolkitText 'loja aplicativos apps') `
            -Description (Get-TFToolkitText 'Pede à Microsoft Store as atualizações dos aplicativos') -Detail (Get-TFToolkitText 'Pede à Microsoft Store as atualizações dos aplicativos e abre a lista para acompanhar') -Command "Update-TFToolkitStoreApps"),
        (New-TFToolkitNavItem -Id "updates.windows" -Label (Get-TFToolkitText 'Windows Update') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'windows update atualizar configurações patch desatualizado verificar pausar adiar desativar atualizações') `
            -Description (Get-TFToolkitText 'Abre o Windows Update nas Configurações do Windows') -Shortcut "WindowsUpdate"),
        (New-TFToolkitNavItem -Id "updates.optional" -Label (Get-TFToolkitText 'Atualizações opcionais') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'opcionais prévia preview recursos') `
            -Description (Get-TFToolkitText 'Abre as opcionais: drivers e prévias da próxima atualização') -Detail (Get-TFToolkitText 'Abre nas Configurações do Windows as opcionais: drivers e prévias da próxima atualização') -Shortcut "OptionalUpdates")
    )

    $pages += New-TFToolkitNavPage -Id "software" -Title (Get-TFToolkitText 'Programas') -Summary (Get-TFToolkitText 'Instale, remova e organize o que roda no PC.') -Items @(
        (New-TFToolkitNavItem -Id "software.essentials" -Label (Get-TFToolkitText 'Instalar programas essenciais') -ButtonText (Get-TFToolkitText 'Escolher programas') -Group (Get-TFToolkitText 'Instalar e remover') -Accent `
            -Keywords (Get-TFToolkitText 'instalar baixar navegador chrome firefox 7zip 7-zip vlc pdf acrobat libreoffice zoom git aplicativos discord steam vscode code python node nodejs java jdk powershell notepad everything powertoys') `
            -Description (Get-TFToolkitText 'Navegadores, leitor de PDF, 7-Zip, VLC e outros comuns') -Detail (Get-TFToolkitText 'Escolha numa lista de programas comuns, como navegadores, leitor de PDF, 7-Zip e VLC') -Command "Install-TFToolkitEssentialSoftware"),
        (New-TFToolkitNavItem -Id "software.find" -Label (Get-TFToolkitText 'Buscar e instalar programas') -Group (Get-TFToolkitText 'Instalar e remover') `
            -Keywords (Get-TFToolkitText 'pesquisar procurar instalar baixar winget app') `
            -Description (Get-TFToolkitText 'Procura um programa pelo nome e instala o que você marcar') -Command "Find-TFToolkitSoftware"),
        (New-TFToolkitNavItem -Id "software.list" -Label (Get-TFToolkitText 'Listar programas instalados') -Group (Get-TFToolkitText 'Instalar e remover') `
            -Keywords (Get-TFToolkitText 'winget lista programas apps instalados') `
            -Description (Get-TFToolkitText 'Os programas instalados e quantos têm versão nova') -Detail (Get-TFToolkitText 'Conta os programas instalados e quantos têm versão nova, com a lista completa do winget') -Command "Show-TFToolkitInstalledSoftware"),
        (New-TFToolkitNavItem -Id "software.uninstall" -Label (Get-TFToolkitText 'Desinstalar programas') -Group (Get-TFToolkitText 'Instalar e remover') `
            -Keywords (Get-TFToolkitText 'remover apagar excluir app programa uninstall') `
            -Description (Get-TFToolkitText 'Lista os programas e remove os que você marcar') -Command "Uninstall-TFToolkitSoftware"),
        (New-TFToolkitNavItem -Id "software.remove-apps" -Label (Get-TFToolkitText 'Remover aplicativos do Windows') -Group (Get-TFToolkitText 'Instalar e remover') `
            -Keywords (Get-TFToolkitText 'bloatware pré-instalados candy crush xbox spotify tiktok teams clima notícias cortana bing linkedin office copilot outlook') `
            -Description (Get-TFToolkitText 'Os aplicativos que vêm com o PC; remove só os marcados') -Detail (Get-TFToolkitText 'Mostra os aplicativos que vêm com o PC e remove só os que você marcar') -Command "Remove-TFToolkitPreinstalledApps"),
        (New-TFToolkitNavItem -Id "software.winget-repair" -Label (Get-TFToolkitText 'Reparar o Instalador de Aplicativo') -Group (Get-TFToolkitText 'Instalar e remover') -Unlisted `
            -Keywords (Get-TFToolkitText 'winget não encontrado não reconhecido sumiu falta app installer registrar consertar') `
            -Description (Get-TFToolkitText 'Registra de novo o winget quando ele some do PC') -Detail (Get-TFToolkitText 'Registra de novo o winget para esta conta, como a Microsoft indica; se não resolver, abre a Microsoft Store') -Command "Repair-TFToolkitWinget"),
        # A mesma ação de Desempenho > Gerenciar inicialização, com as mesmas frases e palavras de busca: a busca, que mostra
        # uma ação uma vez só, traz sempre a de Desempenho, a casa dela (antes, a palavra decidia qual das duas aparecia).
        (New-TFToolkitNavItem -Id "software.startup-manager" -Label (Get-TFToolkitText 'Gerenciar inicialização') -Group (Get-TFToolkitText 'Inicialização e recursos') `
            -Keywords (Get-TFToolkitText 'programas iniciam abrem junto boot demora msconfig desativar reativar lento lenta lentidão startup abrir iniciar com o windows') `
            -Description (Get-TFToolkitText 'O que abre junto com o Windows; desligue o que não precisa') -Detail (Get-TFToolkitText 'O que abre junto com o Windows; desligar o que não precisa deixa o PC leve desde o início') -Command "Set-TFToolkitStartupItems"),
        (New-TFToolkitNavItem -Id "software.features" -Label (Get-TFToolkitText 'Recursos opcionais do Windows') -Group (Get-TFToolkitText 'Inicialização e recursos') -Admin `
            -Keywords (Get-TFToolkitText 'wsl hyper-v sandbox virtualização net framework telnet smb smb1 powershell ativar desativar') `
            -Description (Get-TFToolkitText 'Liga ou desliga WSL, Hyper-V, Windows Sandbox, .NET 3.5...') -Detail (Get-TFToolkitText 'Liga ou desliga recursos como WSL, Hyper-V, Windows Sandbox e .NET 3.5') -Command "Set-TFToolkitWindowsFeatures"),
        (New-TFToolkitNavItem -Id "software.backup" -Label (Get-TFToolkitText 'Backup antes de formatar') -Group (Get-TFToolkitText 'Backup e formatação') -Admin `
            -Keywords (Get-TFToolkitText 'formatar reinstalar windows drivers wifi pendrive exportar lista') `
            -Description (Get-TFToolkitText 'Programas, drivers e ajustes; fotos e documentos à parte') -Detail (Get-TFToolkitText 'Guarda a lista de programas, os drivers e os ajustes; fotos e documentos você copia à parte') -Command "Invoke-TFToolkitBackupBeforeFormat"),
        (New-TFToolkitNavItem -Id "software.restore" -Label (Get-TFToolkitText 'Restaurar a partir de um backup') -Group (Get-TFToolkitText 'Backup e formatação') -Admin `
            -Keywords (Get-TFToolkitText 'formatar reinstalar windows drivers wifi importar') `
            -Description (Get-TFToolkitText 'Reinstala programas e drivers e reaplica os ajustes') -Detail (Get-TFToolkitText 'Reinstala os programas e os drivers e reaplica os ajustes de um backup do TF-Toolkit') -Command "Restore-TFToolkitFromBackup"),
        (New-TFToolkitNavItem -Id "software.installed-apps" -Label (Get-TFToolkitText 'Aplicativos instalados') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'remover desinstalar lista apps') `
            -Description (Get-TFToolkitText 'Abre a lista completa nas Configurações, para desinstalar') -Detail (Get-TFToolkitText 'Abre nas Configurações do Windows, em Aplicativos, a lista completa, com a opção de desinstalar') -Shortcut "InstalledApps"),
        (New-TFToolkitNavItem -Id "software.programs-features" -Label (Get-TFToolkitText 'Programas e Recursos') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'painel de controle appwiz desinstalar clássico') `
            -Description (Get-TFToolkitText 'Abre o painel de controle clássico, para programas antigos') -Shortcut "ProgramsAndFeatures"),
        (New-TFToolkitNavItem -Id "software.startup" -Label (Get-TFToolkitText 'Aplicativos de inicialização') -Group (Get-TFToolkitText 'Ferramentas do Windows') `
            -Keywords (Get-TFToolkitText 'iniciar inicialização abrir boot startup') `
            -Description (Get-TFToolkitText 'Abre nas Configurações o que abre junto com o Windows') -Detail (Get-TFToolkitText 'Abre nas Configurações do Windows, em Aplicativos, Inicialização, o que abre junto com o Windows') -Shortcut "StartupApps")
    )

    $pages += New-TFToolkitNavPage -Id "network" -Title (Get-TFToolkitText 'Rede') -Summary (Get-TFToolkitText 'Do mais simples ao que mexe mais: ver, testar, medir e consertar a conexão.') -Items @(
        (New-TFToolkitNavItem -Id "network.info" -Label (Get-TFToolkitText 'Informações de rede') -Group (Get-TFToolkitText 'Ver e testar') `
            -Keywords (Get-TFToolkitText 'ip gateway adaptador mac endereço internet dns meu público ipconfig placa proxy ssid banda canal') `
            -Description (Get-TFToolkitText 'Adaptadores, Wi-Fi, IP, DNS, gateway, proxy e IP público') -Detail (Get-TFToolkitText 'Adaptadores, rede Wi-Fi, IP, DNS, gateway, proxy e IP público') -Command "Show-TFToolkitNetworkInfo"),
        (New-TFToolkitNavItem -Id "network.ping" -Label (Get-TFToolkitText 'Testar conectividade (ping)') -ButtonText (Get-TFToolkitText 'Testar agora') -Group (Get-TFToolkitText 'Ver e testar') -Accent `
            -Keywords (Get-TFToolkitText 'latência perda de pacotes sem internet conexão teste lag alto jogo roteador') `
            -Description (Get-TFToolkitText 'Se a internet responde e se a conexão está estável') -Detail (Get-TFToolkitText 'Diz se a internet responde e se a conexão está estável ou perdendo dados') -Command "Test-TFToolkitPing"),
        (New-TFToolkitNavItem -Id "network.speed" -Label (Get-TFToolkitText 'Testar velocidade da internet') -Group (Get-TFToolkitText 'Ver e testar') `
            -Keywords (Get-TFToolkitText 'speedtest internet lenta wifi download upload mbps banda teste') `
            -Description (Get-TFToolkitText 'Latência, download e upload (usa cerca de 35 MB)') -Command "Test-TFToolkitInternetSpeed"),
        (New-TFToolkitNavItem -Id "network.wifi-report" -Label (Get-TFToolkitText 'Relatório de Wi-Fi') -Group (Get-TFToolkitText 'Ver e testar') -Admin `
            -Keywords (Get-TFToolkitText 'wlan quedas desconexoes sinal wireless wifi wi-fi sem fio caindo cai caiu desconectando instável fraco') `
            -Description (Get-TFToolkitText 'Relatório do Windows com as quedas do Wi-Fi recentes') -Detail (Get-TFToolkitText 'Gera o relatório do Windows com as sessões e as quedas do Wi-Fi dos últimos dias') -Command "Show-TFToolkitWifiReport"),
        (New-TFToolkitNavItem -Id "network.wifi-password" -Label (Get-TFToolkitText 'Senha do Wi-Fi') -Group (Get-TFToolkitText 'Ver e testar') -Admin `
            -Keywords (Get-TFToolkitText 'senha wifi wi-fi chave rede sem fio password esqueci visitante') `
            -Description (Get-TFToolkitText 'Mostra a senha de uma rede Wi-Fi salva neste PC, só na tela') -Command "Show-TFToolkitWifiPassword"),
        (New-TFToolkitNavItem -Id "network.time" -Label (Get-TFToolkitText 'Acertar a data e a hora') -Group (Get-TFToolkitText 'Consertar e configurar') -Admin `
            -Keywords (Get-TFToolkitText 'relógio hora errada data errada horário sincronizar ntp w32time fuso relógio atrasado adiantado erro de certificado') `
            -Description (Get-TFToolkitText 'Sincroniza o relógio do PC com o servidor de hora agora') -Detail (Get-TFToolkitText 'Pede ao Windows para sincronizar o relógio agora e confere a hora num servidor da Microsoft') -Command "Sync-TFToolkitTime"),
        (New-TFToolkitNavItem -Id "network.repair" -Label (Get-TFToolkitText 'Reparar rede e DNS') -Group (Get-TFToolkitText 'Consertar e configurar') -Admin `
            -Keywords (Get-TFToolkitText 'internet não funciona conecta conectar sem conexão caiu queda wifi wi-fi fio winsock flushdns ipconfig reset renovar reiniciar redefinir dhcp netsh roteador') `
            -Description (Get-TFToolkitText 'Refaz as configurações de rede; IP e DNS fixos ficam') -Detail (Get-TFToolkitText 'Para quando a internet não funciona: refaz as configurações de rede; IP e DNS fixos são mantidos') -Command "Invoke-TFToolkitNetworkRepair"),
        (New-TFToolkitNavItem -Id "network.dns" -Label (Get-TFToolkitText 'Trocar o servidor DNS') -Group (Get-TFToolkitText 'Consertar e configurar') -Admin `
            -Keywords (Get-TFToolkitText 'cloudflare google quad9 1.1.1.1 8.8.8.8 1.1.1.3 lento sites família filtro adulto controle parental bloquear') `
            -Description (Get-TFToolkitText 'Mede o DNS e troca por Cloudflare, Google ou Quad9') -Detail (Get-TFToolkitText 'Mede o tempo de resposta e troca para Cloudflare, Google, Quad9 ou o filtro para famílias') -Command "Set-TFToolkitDnsProvider"),
        (New-TFToolkitNavItem -Id "network.dns-undo" -Label (Get-TFToolkitText 'Desfazer a troca de DNS') -Group (Get-TFToolkitText 'Consertar e configurar') -Admin `
            -Keywords (Get-TFToolkitText 'voltar restaurar dns original automatico') `
            -Description (Get-TFToolkitText 'Devolve o DNS de antes da troca feita pelo TF-Toolkit') -Detail (Get-TFToolkitText 'Devolve o DNS que o PC usava antes da troca feita pelo TF-Toolkit') -Command "Undo-TFToolkitDnsChange")
    )

    $pages += New-TFToolkitNavPage -Id "tweaks" -Title (Get-TFToolkitText 'Ajustes do Windows') -Kind Tweaks `
        -Summary (Get-TFToolkitText 'Mudanças reversíveis, com backup do valor original.') -Items @(
        (New-TFToolkitNavItem -Id "tweaks.recommended" -Label (Get-TFToolkitText 'Aplicar ajustes recomendados') -Accent `
            -Keywords (Get-TFToolkitText 'extensão extensões publicidade anúncios propaganda sugestões') `
            -Description (Get-TFToolkitText 'Extensões à vista e menos dicas e sugestões; você escolhe') -Detail (Get-TFToolkitText 'Mostra as extensões de arquivos e tira dicas, sugestões e o ID de publicidade; você escolhe quais') -Command "Invoke-TFToolkitRecommendedTweaks"),
        (New-TFToolkitNavItem -Id "tweaks.profiles" -Label (Get-TFToolkitText 'Perfis de ajustes') -Admin `
            -Keywords (Get-TFToolkitText 'perfil essencial trabalho jogos privacidade notebook conjunto telemetria rastreamento') `
            -Description (Get-TFToolkitText 'Essencial, Trabalho, Jogos, Privacidade e Notebook') -Detail (Get-TFToolkitText 'Conjuntos prontos: Essencial, Trabalho, Jogos, Privacidade e Notebook; você escolhe o que aplicar') -Command "Invoke-TFToolkitTweakProfile"),
        (New-TFToolkitNavItem -Id "tweaks.keyboard-language" -Label (Get-TFToolkitText 'Teclas que trocam o idioma do teclado') -ListCategory (Get-TFToolkitText 'Notificações e teclado') `
            -Keywords (Get-TFToolkitText 'alt shift ctrl trocar mudar idioma teclado layout abnt abnt2 internacional muda troca sozinho') `
            -Description (Get-TFToolkitText 'Alt + Shift, Ctrl + Shift, as duas ou nenhuma') -Detail (Get-TFToolkitText 'Escolhe as teclas que trocam o idioma e o teclado: Alt + Shift, Ctrl + Shift, as duas ou nenhuma') -Command "Set-TFToolkitKeyboardLanguageHotkey"),
        (New-TFToolkitNavItem -Id "tweaks.notifications" -Label (Get-TFToolkitText 'Notificações e Não incomodar') -ListCategory (Get-TFToolkitText 'Notificações e teclado') `
            -Keywords (Get-TFToolkitText 'assistente de foco silenciar avisos notificação concentração quiet hours') `
            -Description (Get-TFToolkitText 'Abre as notificações e o Não incomodar nas Configurações') -Detail (Get-TFToolkitText 'Abre nas Configurações do Windows as notificações e o Não incomodar (assistente de foco)') -Shortcut "Notifications"),
        (New-TFToolkitNavItem -Id "tweaks.restore-point" -Label (Get-TFToolkitText 'Criar ponto de restauração') -Admin `
            -Keywords (Get-TFToolkitText 'backup segurança voltar atrás proteção do sistema') `
            -Description (Get-TFToolkitText 'Um ponto para voltar atrás se algo der errado') -Command "Invoke-TFToolkitRestorePoint"),
        (New-TFToolkitNavItem -Id "tweaks.export" -Label (Get-TFToolkitText 'Exportar ajustes aplicados') `
            -Keywords (Get-TFToolkitText 'salvar backup levar outro pc') `
            -Description (Get-TFToolkitText 'Salva os ajustes aplicados, para repetir em outro PC') -Detail (Get-TFToolkitText 'Salva em um arquivo os ajustes aplicados neste PC, para repetir em outro') -Command "Export-TFToolkitTweaks"),
        (New-TFToolkitNavItem -Id "tweaks.import" -Label (Get-TFToolkitText 'Importar ajustes') -Admin `
            -Keywords (Get-TFToolkitText 'restaurar carregar arquivo outro pc') `
            -Description (Get-TFToolkitText 'Aplica ajustes de um arquivo exportado; você escolhe quais') -Detail (Get-TFToolkitText 'Aplica ajustes de um arquivo exportado antes, depois de você escolher quais') -Command "Import-TFToolkitTweaks"),
        (New-TFToolkitNavItem -Id "tweaks.revert-all" -Label (Get-TFToolkitText 'Desfazer ajustes do TF-Toolkit') -Admin `
            -Keywords (Get-TFToolkitText 'reverter voltar padrão original normal tudo') `
            -Description (Get-TFToolkitText 'Desfaz tudo o que o TF-Toolkit aplicou, usando o backup') -Detail (Get-TFToolkitText 'Desfaz tudo o que o TF-Toolkit aplicou aqui e na Personalização, usando o backup') -Command "Invoke-TFToolkitRevertAllTweaks")
    )

    # O visual do Windows: os ajustes das categorias da Personalização (Get-TFToolkitTweakPages) e os atalhos para as telas
    # do Windows que o TF-Toolkit não faz. A cor de destaque se escolhe nas Configurações: o Windows não tem um jeito
    # documentado de um programa trocá-la (os valores do registro não são documentados e nem sempre pegam na hora).
    $pages += New-TFToolkitNavPage -Id "personalize" -Title (Get-TFToolkitText 'Personalização') -Kind Tweaks `
        -Summary (Get-TFToolkitText 'O visual do Windows: barra de tarefas, área de trabalho, cores e tela de bloqueio.') -Items @(
        (New-TFToolkitNavItem -Id "personalize.accent-color" -Label (Get-TFToolkitText 'Cor de destaque') -ListCategory (Get-TFToolkitText 'Cores e transparência') `
            -Keywords (Get-TFToolkitText 'cor accent azul verde roxo vermelho rosa laranja cinza automática colorir') `
            -Description (Get-TFToolkitText 'Abre as Cores do Windows, onde se escolhe a cor') -Detail (Get-TFToolkitText 'Abre nas Configurações do Windows as Cores, onde se escolhe a cor de destaque') -Shortcut "Colors"),
        (New-TFToolkitNavItem -Id "personalize.lock-screen" -Label (Get-TFToolkitText 'Tela de bloqueio do Windows') -ListCategory (Get-TFToolkitText 'Tela de bloqueio') `
            -Keywords (Get-TFToolkitText 'imagem foto destaque do windows spotlight bloqueio lock screen') `
            -Description (Get-TFToolkitText 'Abre a tela de bloqueio: a imagem e o que aparece nela') -Detail (Get-TFToolkitText 'Abre nas Configurações do Windows a tela de bloqueio: a imagem e o que aparece nela') -Shortcut "LockScreen"),
        (New-TFToolkitNavItem -Id "personalize.settings" -Label (Get-TFToolkitText 'Personalização do Windows') `
            -Keywords (Get-TFToolkitText 'papel de parede tela de fundo temas fonte wallpaper') `
            -Description (Get-TFToolkitText 'Abre a tela de fundo, os temas, as cores e as fontes') -Detail (Get-TFToolkitText 'Abre nas Configurações do Windows a tela de fundo, os temas, as cores e as fontes') -Shortcut "Personalization")
    )

    $pages += New-TFToolkitNavPage -Id "app" -Title (Get-TFToolkitText 'Sobre o TF-Toolkit') -Placement Footer `
        -Summary (Get-TFToolkitText 'A versão, o suporte e as preferências do TF-Toolkit.') -Items @(
        (New-TFToolkitNavItem -Id "app.about" -Label (Get-TFToolkitText 'Versão e pastas') -Group (Get-TFToolkitText 'Versão e dados') `
            -Keywords (Get-TFToolkitText 'build powershell instalar tf-toolkit desinstalar tf-toolkit instalação') `
            -Description (Get-TFToolkitText 'A versão aberta, a pasta dela e onde ficam os logs') -Detail (Get-TFToolkitText 'Qual versão está aberta, de que pasta, se está instalada e onde ficam os logs e relatórios') -Command "Show-TFToolkitAbout"),
        (New-TFToolkitNavItem -Id "app.update" -Label (Get-TFToolkitText 'Verificar nova versão') -Group (Get-TFToolkitText 'Versão e dados') `
            -Keywords (Get-TFToolkitText 'atualizar tf-toolkit atualização baixar release github') `
            -Description (Get-TFToolkitText 'Procura uma versão nova e instala com um clique') -Detail (Get-TFToolkitText 'Vê se há uma versão mais nova do TF-Toolkit e instala com um clique, conferindo o SHA-256') -Command "Invoke-TFToolkitUpdateCheck"),
        (New-TFToolkitNavItem -Id "app.catalog" -Label (Get-TFToolkitText 'Conferir dados online') -Group (Get-TFToolkitText 'Versão e dados') `
            -Keywords (Get-TFToolkitText 'catálogo lista essenciais datas suporte') `
            -Description (Get-TFToolkitText 'Atualiza a lista de essenciais e as datas de suporte') -Detail (Get-TFToolkitText 'Confere na internet a lista de essenciais e as datas de suporte do Windows mais recentes') -Command "Update-TFToolkitOnlineData"),
        (New-TFToolkitNavItem -Id "app.logs" -Label (Get-TFToolkitText 'Pasta de logs e relatórios') -Group (Get-TFToolkitText 'Versão e dados') `
            -Keywords (Get-TFToolkitText 'log arquivo txt html') `
            -Description (Get-TFToolkitText 'Abre a pasta com os logs e os relatórios gerados') -Shortcut "LogFolder"),
        (New-TFToolkitNavItem -Id "app.support" -Label (Get-TFToolkitText 'Pacote de suporte') -Group (Get-TFToolkitText 'Versão e dados') `
            -Keywords (Get-TFToolkitText 'suporte ajuda log logs zip problema erro bug enviar mandar técnico') `
            -Description (Get-TFToolkitText 'Logs, verificação e versões num zip, para quem vai ajudar') -Detail (Get-TFToolkitText 'Junta logs, verificação e versões num zip para mandar a quem vai ajudar') -Command "New-TFToolkitSupportPackage"),
        (New-TFToolkitNavItem -Id "app.website" -Label (Get-TFToolkitText 'Site do TF-Toolkit') -Group (Get-TFToolkitText 'Versão e dados') `
            -Keywords (Get-TFToolkitText 'site página internet web novidades techfontes') `
            -Description (Get-TFToolkitText 'Abre o site do TF-Toolkit no navegador') -Shortcut "Website"),
        (New-TFToolkitNavItem -Id "app.shortcut" -Label (Get-TFToolkitText 'Criar atalho do TF-Toolkit') -ButtonText (Get-TFToolkitText 'Criar atalho') -Group (Get-TFToolkitText 'Integração com o Windows') -Accent `
            -Keywords (Get-TFToolkitText 'fixar barra tarefas') `
            -Description (Get-TFToolkitText 'Põe o TF-Toolkit na Área de Trabalho ou no Menu Iniciar') -Detail (Get-TFToolkitText 'Coloca o TF-Toolkit, com o ícone dele, na Área de Trabalho ou no Menu Iniciar') -Command "New-TFToolkitAppShortcut"),
        (New-TFToolkitNavItem -Id "app.monitor" -Label (Get-TFToolkitText 'Monitor na bandeja') -Group (Get-TFToolkitText 'Integração com o Windows') `
            -Keywords (Get-TFToolkitText 'bandeja ícone relógio alertas avisos notificação notificações tf-toolkit segundo plano vigiar') `
            -Description (Get-TFToolkitText 'Avisa perto do relógio quando algo no PC pede atenção') -Detail (Get-TFToolkitText 'Avisa, perto do relógio, quando o disco enche ou falha, a proteção desliga ou falta manutenção') -Command "Set-TFToolkitMonitor"),
        # Na janela, o cartão Idioma da página faz o mesmo (por isso fica fora dos cartões): o menu de texto chega aqui, e a
        # busca da janela leva ao cartão (Get-TFToolkitSearchCardItem).
        (New-TFToolkitNavItem -Id "app.language" -Label (Get-TFToolkitText 'Idioma') -Group (Get-TFToolkitText 'Integração com o Windows') -Unlisted `
            -Keywords 'idioma idiomas lingua lengua language english ingles espanol espanhol portugues traducao traduccion' `
            -Description (Get-TFToolkitText 'Português, inglês ou espanhol; ou o idioma do Windows') -Detail (Get-TFToolkitText 'Português, inglês ou espanhol; no automático, o mesmo idioma do Windows') -Command "Set-TFToolkitInterfaceLanguage")
    )

    $script:TFToolkitNavigation = @($pages)
    return $script:TFToolkitNavigation
}


function Get-TFToolkitNavPage {
    param (
        [Parameter(Mandatory)]
        [string]$Id
    )

    return (Get-TFToolkitNavigation | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}


function Get-TFToolkitNavItem {
    param (
        [Parameter(Mandatory)]
        [string]$Id
    )

    foreach ($page in (Get-TFToolkitNavigation)) {
        $item = @($page.Items | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1

        if ($null -ne $item) {
            return $item
        }
    }

    return $null
}


function Find-TFToolkitNavReference {
    <#
    A primeira referência "Página > Item" de um texto (como em "Use Limpeza > Limpar o registro para..."), resolvida para
    o item da navegação, para o resumo da janela fazer dela um link. Devolve ItemId, Start e Length (o trecho
    "Página > Item" no texto), ou $null. Com dois itens que começam igual, vale o de nome mais longo.
    #>
    param ([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.IndexOf(" > ", [System.StringComparison]::Ordinal) -lt 0) { return $null }

    $best = $null

    foreach ($page in (Get-TFToolkitNavigation)) {
        $prefix = "$($page.Title) > "
        $position = $Text.IndexOf($prefix, [System.StringComparison]::Ordinal)

        if ($position -lt 0) { continue }

        $rest = $Text.Substring($position + $prefix.Length)

        foreach ($item in @($page.Items)) {
            $label = [string]$item.Label

            if (-not $rest.StartsWith($label, [System.StringComparison]::Ordinal)) { continue }

            # O nome termina ali: "Limpar o registro" não casa com "Limpar o registro do Windows" se este não existir;
            # depois do nome vem fim de texto, espaço ou pontuação.
            $after = $rest.Substring($label.Length)
            if ($after.Length -gt 0 -and [char]::IsLetterOrDigit($after[0])) { continue }

            if ($null -eq $best -or $position -lt $best.Start -or ($position -eq $best.Start -and ($prefix.Length + $label.Length) -gt $best.Length)) {
                $best = [PSCustomObject]@{ ItemId = [string]$item.Id; Start = $position; Length = $prefix.Length + $label.Length }
            }
        }
    }

    return $best
}


# ---------------------------------------------------------------------------
# Busca (Ctrl+K na janela)
# ---------------------------------------------------------------------------

# O índice: os textos de todas as ações, atalhos, partes de página e ajustes, já normalizados, montado uma vez por sessão
# (a janela o prepara logo depois de aparecer, com o vocabulário da correção de digitação). Cada tecla só compara textos
# prontos: uma busca leva de 5 a 20 ms; uma com erro de digitação ou que só acha parte das palavras passa o índice mais
# duas ou três vezes. Montar o índice leva de 0,1 a 0,5 s (mais na primeira leitura do catálogo de ajustes).
$script:TFToolkitSearchIndex = $null
$script:TFToolkitSearchTweaks = $null
$script:TFToolkitSearchEntries = $null
$script:TFToolkitSearchAllText = ""
$script:TFToolkitSearchPageIndex = $null
$script:TFToolkitSearchVocabulary = $null
$script:TFToolkitSearchCorrections = @{}
$script:TFToolkitSearchSynonymMap = $null

# Uma busca usa no máximo estes caracteres e palavras: um texto colado por engano não trava a janela. O nome e a descrição
# mais longos da janela, juntos, têm menos de 170 caracteres.
$script:TFToolkitSearchMaxLength = 200
$script:TFToolkitSearchMaxWords = 8

# O que o caminho recomendado de uma página ganha quando a busca acha a página pelo nome: com a palavra no nome ou nas
# palavras-chave dele, ele passa as outras ações que começam com ela (17); fica sempre abaixo de um nome exato (36 ou mais).
$script:TFToolkitSearchHighlightBonus = 10

# Acentos do português (e do espanhol/francês mais comuns). Tabela própria em vez de String.Normalize: funciona igual em
# qualquer edição do Windows e com a globalização reduzida.
$script:TFToolkitAccentFrom = "áàâãäåéèêëíìîïóòôõöøúùûüçñýÿ"
$script:TFToolkitAccentTo = "aaaaaaeeeeiiiioooooouuuucnyy"


function ConvertTo-TFToolkitSearchText {
    # Minúsculas e sem acentos, para "limpeza", "LIMPEZA" e "limpêza" acharem o mesmo. Marcas de acento soltas (texto
    # decomposto, comum ao colar de outros programas) e caracteres invisíveis de formatação (hífen opcional, espaço de
    # largura zero, marca de direção do texto) são descartados: no meio de uma palavra, eles a partiriam em duas.
    param ([AllowEmptyString()][AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return "" }

    $lower = $Text.ToLowerInvariant()

    # Texto só ASCII (a maioria) não precisa de tradução.
    if ($lower -notmatch '[^\x00-\x7F]') { return $lower }

    for ($i = 0; $i -lt $script:TFToolkitAccentFrom.Length; $i++) {
        $lower = $lower.Replace($script:TFToolkitAccentFrom[$i], $script:TFToolkitAccentTo[$i])
    }

    return [regex]::Replace($lower, '[̀-ͯ\p{Cf}]', '')
}


function ConvertTo-TFToolkitSearchWords {
    # As palavras do texto (letras e números sem acento, em minúsculas) separadas por um espaço: "Wi-Fi (DNS)" vira
    # "wi fi dns". Pontuação e símbolos nunca atrapalham o que a pessoa digitou.
    param ([AllowEmptyString()][AllowNull()][string]$Text)

    return ([regex]::Replace((ConvertTo-TFToolkitSearchText -Text $Text), '[^a-z0-9]+', ' ')).Trim()
}


function Join-TFToolkitSearchHyphens {
    # Uma palavra escrita com hífen vira uma só ("wi-fi" vira "wifi", "pré-instalados" vira "preinstalados"), como o
    # índice também guarda. Vale para o hífen comum e para os de texto colado (U+2010 e o sem quebra, U+2011). O texto já
    # vem sem acentos e em minúsculas (ConvertTo-TFToolkitSearchText).
    param ([AllowEmptyString()][AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return "" }

    return [regex]::Replace($Text, '(?<=[a-z0-9])[\-\u2010\u2011](?=[a-z0-9])', '')
}


function ConvertTo-TFToolkitSearchIndexWords {
    # As palavras de um texto do índice. O que é escrito com hífen vale também junto, para "wifi" achar "Wi-Fi" e "hyperv"
    # achar "Hyper-V". Essas palavras extras vão no fim, depois das do texto.
    param ([AllowEmptyString()][AllowNull()][string]$Text)

    $plain = ConvertTo-TFToolkitSearchText -Text $Text
    $words = ([regex]::Replace($plain, '[^a-z0-9]+', ' ')).Trim()
    $joined = @(foreach ($match in [regex]::Matches($plain, '[a-z0-9]+(-[a-z0-9]+)+')) { $match.Value.Replace("-", "") })

    if ($joined.Count -eq 0) { return $words }

    return "$words $($joined -join ' ')".Trim()
}


# Palavras de ligação que não ajudam a achar nada ("meu pc está lento", "o som não funciona", "deixar mais rápido"): saem
# da busca quando sobra outra palavra. "pc" e "computador" são opcionais: valem 1 ponto quando o texto tem a palavra
# inteira, mas não impedem o resultado.
$script:TFToolkitSearchStopWords = @(
    "a", "o", "as", "os", "um", "uma", "uns", "umas", "de", "do", "da", "dos", "das", "em", "no", "na", "nos", "nas", "ao", "aos",
    "para", "pra", "por", "com", "sem", "e", "ou", "que", "se", "eu", "me", "meu", "minha", "meus", "minhas", "como", "esta", "estao",
    "estou", "ta", "muito", "muita", "mais", "nao", "funciona", "funcionando", "funcionou", "sozinho", "sozinha", "pouco", "pouca",
    "deixar", "deixa", "ficar", "fica", "ficou", "quando", "quero", "preciso", "fazer", "isso", "esse", "essa", "tem", "ele", "ela",
    "consigo", "conseguir", "consegue", "posso", "pode", "qual", "quais", "melhorar", "aumentar", "este", "estes", "estas"
)
$script:TFToolkitSearchSoftWords = @("pc", "computador")

# Prefixos que invertem o sentido: um pedaço depois deles não conta como achado ("ativar" em "desativar").
$script:TFToolkitSearchNegations = @("des", "re", "in", "im", "dis")

# As terminações que Get-TFToolkitSearchStem tira (da mais longa para a mais curta).
$script:TFToolkitSearchSuffixes = @("acoes", "acao", "mentos", "mento", "ando", "endo", "indo", "ados", "adas", "ado", "ada", "idos", "idas", "ido", "ida", "ar", "er", "ir", "am", "em", "s")

# As mesmas tabelas em inglês e espanhol (as de cima são as do português): a busca procura no texto da tela, que está no
# idioma da interface, então as palavras de ligação, os sinônimos e as terminações são as desse idioma. Sem acento, como
# a busca compara (ConvertTo-TFToolkitSearchText).
$script:TFToolkitSearchLanguageTables = @{
    en = @{
        StopWords = @(
            "a", "an", "the", "of", "to", "for", "in", "on", "at", "by", "with", "without", "and", "or", "my", "mine", "i", "me", "is",
            "are", "it", "its", "this", "that", "these", "those", "how", "do", "does", "doesnt", "dont", "not", "no", "too", "very",
            "more", "make", "get", "want", "need", "when", "what", "which", "why", "can", "cant", "cannot", "working", "works", "work",
            "keeps", "keep", "really", "much", "so", "be", "being", "improve", "increase", "itself"
        )
        SoftWords = @("pc", "computer", "laptop")
        Negations = @("dis", "un", "de", "re", "in", "im")
        Suffixes  = @("ations", "ation", "ments", "ment", "ings", "ing", "ers", "ied", "ies", "ed", "er", "es", "s")
        Synonyms  = @(
            "disable deactivate hide",
            "disable deactivate off",
            "enable activate",
            "delete remove erase",
            "fix repair",
            "freezing frozen freezes freeze hanging hangs stuck crashing",
            "slow sluggish laggy",
            "app apps application applications"
        )
    }
    es = @{
        StopWords = @(
            "el", "la", "los", "las", "lo", "un", "una", "unos", "unas", "de", "del", "al", "a", "en", "para", "por", "con", "sin", "y",
            "e", "o", "u", "que", "se", "yo", "me", "mi", "mis", "como", "esta", "estan", "estoy", "muy", "mucho", "mucha", "mas", "no",
            "funciona", "funcionando", "funciono", "solo", "sola", "poco", "poca", "dejar", "deja", "quedar", "queda", "quedo", "cuando",
            "quiero", "necesito", "hacer", "esto", "eso", "ese", "esa", "tiene", "tengo", "puedo", "puede", "cual", "cuales", "mejorar",
            "aumentar", "este", "estos", "estas", "hay"
        )
        SoftWords = @("pc", "computadora", "ordenador", "equipo")
        Negations = @("des", "re", "in", "im", "dis")
        Suffixes  = @("aciones", "acion", "mientos", "miento", "ando", "iendo", "ados", "adas", "ado", "ada", "idos", "idas", "ido", "ida", "ar", "er", "ir", "an", "en", "s")
        Synonyms  = @(
            "desactivar deshabilitar ocultar esconder",
            "desactivar deshabilitar apagar",
            "activar habilitar encender",
            "borrar eliminar suprimir",
            "arreglar reparar corregir",
            "congelado congelada congela congelando colgado colgada cuelga trabado trabada traba",
            "lento lenta",
            "app apps aplicacion aplicaciones"
        )
    }
}

# Palavras que a busca trata como parecidas (cada grupo vale em todos os sentidos). O sinônimo vale 4 pontos a menos que
# a própria palavra: no rótulo, ele fica abaixo da palavra exata em qualquer ponto do rótulo.
$script:TFToolkitSearchSynonymPenalty = 4
$script:TFToolkitSearchSynonyms = @(
    "desativar desabilitar ocultar esconder",
    "desativar desabilitar desligar",
    "ativar habilitar ligar",
    "apagar excluir deletar",
    "consertar reparar corrigir arrumar",
    "travando travado travou trava congelando congelado congelou congela",
    "lento lenta devagar lerdo lerda",
    "app apps aplicativo aplicativos"
)

# Palavras extras de cada ajuste do Windows (o catálogo de ajustes não tem campo de palavras-chave). Um teste confere
# que todos os Ids existem.
$script:TFToolkitSearchTweakKeywords = @{
    "file-extensions"      = (Get-TFToolkitText 'extensao tipo exe pdf nome do arquivo')
    "hidden-files"         = (Get-TFToolkitText 'ocultos ocultas escondidos escondidas invisiveis pastas')
    "taskbar-left"         = (Get-TFToolkitText 'iniciar alinhar centralizar windows 11')
    "classic-context-menu" = (Get-TFToolkitText 'botao direito mostrar mais opcoes windows 11')
    "dark-mode"            = (Get-TFToolkitText 'dark mode theme tema escuro noite aparencia cores')
    "no-transparency"      = (Get-TFToolkitText 'efeitos acrilico visual leve desempenho')
    "show-seconds"         = (Get-TFToolkitText 'hora relogio')
    "hide-widgets"         = (Get-TFToolkitText 'noticias clima painel windows 11')
    "hide-copilot"         = (Get-TFToolkitText 'ia inteligencia artificial assistente windows 11')
    "tips-suggestions"     = (Get-TFToolkitText 'anuncios propaganda sugestoes notificacoes telemetria')
    "lock-screen-tips"     = (Get-TFToolkitText 'bloqueio lock screen spotlight anuncios')
    "explorer-recent"      = (Get-TFToolkitText 'acesso rapido recentes frequentes historico privacidade arquivos abertos')
    "explorer-sync-ads"    = (Get-TFToolkitText 'anuncios propaganda onedrive microsoft 365 avisos sincronizacao')
    "search-highlights"    = (Get-TFToolkitText 'pesquisa busca destaques ilustracoes noticias datas')
    "storage-sense"        = (Get-TFToolkitText 'sensor armazenamento espaco disco cheio limpeza automatica lixeira temporarios')
    "background-apps"      = (Get-TFToolkitText 'segundo plano aplicativos memoria bateria windows 10')
    "advertising-id"       = (Get-TFToolkitText 'publicidade anuncios rastreamento telemetria privacidade')
    "bing-start"           = (Get-TFToolkitText 'pesquisa web internet busca menu iniciar')
    "recall"               = (Get-TFToolkitText 'ia captura de tela historico privacidade copilot')
    "game-bar"             = (Get-TFToolkitText 'jogo jogos gamer xbox gravacao fps')
    "fast-startup"         = (Get-TFToolkitText 'inicializacao rapida hibrida desligar lento boot')
    "high-performance"     = (Get-TFToolkitText 'plano de energia alto desempenho velocidade')
    "pcie-aspm"            = (Get-TFToolkitText 'pcie pci express placa de video ssd travamento energia')
    "no-sleep-timeouts"    = (Get-TFToolkitText 'suspender tela apagar dormir energia')
    "hibernation"          = (Get-TFToolkitText 'hiberfil espaco disco hibernar')
    "explorer-this-pc"     = (Get-TFToolkitText 'este computador meu pc acesso rapido explorador abrir')
    "taskbar-end-task"     = (Get-TFToolkitText 'finalizar tarefa travado travou fechar programa windows 11')
    "autoplay-off"         = (Get-TFToolkitText 'reproducao automatica autorun pendrive usb seguranca')
    "taskbar-search"       = (Get-TFToolkitText 'caixa busca pesquisar lupa esconder espaco')
    "task-view-button"     = (Get-TFToolkitText 'multitarefa desktops virtuais esconder')
    "start-recommendations" = (Get-TFToolkitText 'recomendados recomendacoes menu iniciar sugestoes windows 11')
    "tailored-experiences" = (Get-TFToolkitText 'experiencias personalizadas privacidade dados de diagnostico anuncios')
    "feedback-requests"    = (Get-TFToolkitText 'feedback opiniao pesquisa avaliacao notificacoes')
    "activity-history"     = (Get-TFToolkitText 'historico de atividades linha do tempo timeline privacidade')
    "diagnostic-data"      = (Get-TFToolkitText 'telemetria dados de diagnostico privacidade coleta envio microsoft')
    "app-tracking"         = (Get-TFToolkitText 'rastreamento programas mais usados menu iniciar privacidade')
    "online-speech"        = (Get-TFToolkitText 'voz fala ditado reconhecimento privacidade cortana')
    "inking-typing"        = (Get-TFToolkitText 'digitacao teclado caneta escrita dicionario privacidade')
    "delivery-peers"       = (Get-TFToolkitText 'otimizacao de entrega p2p compartilhar atualizacoes banda internet')
    "early-updates"        = (Get-TFToolkitText 'windows update novidades antecipadas antes previa preview instabilidade recursos assim que saem')
    "gpu-scheduling"       = (Get-TFToolkitText 'hags placa de video gpu jogos latencia agendamento')
    "taskbar-never-combine" = (Get-TFToolkitText 'agrupar combinar desagrupar botoes janelas rotulos nomes windows 11')
    "desktop-recycle-bin"  = (Get-TFToolkitText 'lixeira icone area de trabalho esconder remover')
    "desktop-this-pc"      = (Get-TFToolkitText 'este computador meu icone area de trabalho')
    "accent-taskbar"       = (Get-TFToolkitText 'cor de destaque colorir barra iniciar')
    "accent-titlebars"     = (Get-TFToolkitText 'cor de destaque colorir janelas bordas titulo')
    "lock-screen-widgets"  = (Get-TFToolkitText 'bloqueio lock screen clima noticias cotacoes widgets')
    "lock-screen-notifications" = (Get-TFToolkitText 'bloqueio lock screen avisos notificacoes privacidade')
    "notifications-off"    = (Get-TFToolkitText 'avisos notificacoes silenciar desativar toast balao')
    "sticky-keys-shortcut" = (Get-TFToolkitText 'teclas de aderencia shift cinco vezes acessibilidade jogos filtragem alternancia')
    "clipboard-history"    = (Get-TFToolkitText 'area de transferencia copiar colar windows v historico')
    "game-mode"            = (Get-TFToolkitText 'modo de jogo jogos gamer desempenho fps')
    "mouse-acceleration"   = (Get-TFToolkitText 'mouse aceleracao precisao do ponteiro mira jogos fps')
}


function Get-TFToolkitSearchStem {
    # O começo de uma palavra sem a terminação mais comum do idioma, para "iniciar" achar "inicialização", "limpar"
    # achar "limpeza" e "programas" achar "programa". Vazio quando sobraria menos de 4 letras.
    param ([string]$Token)

    foreach ($suffix in @(Get-TFToolkitSearchTable -Name "Suffixes")) {
        if ($Token.Length -ge ($suffix.Length + 4) -and $Token.EndsWith($suffix)) {
            return $Token.Substring(0, $Token.Length - $suffix.Length)
        }
    }

    return ""
}


function Get-TFToolkitSearchTable {
    # Uma das tabelas da busca (StopWords, SoftWords, Negations, Suffixes, Synonyms) no idioma da interface.
    param ([Parameter(Mandatory)][ValidateSet("StopWords", "SoftWords", "Negations", "Suffixes", "Synonyms")][string]$Name)

    $language = Get-TFToolkitLanguage

    if ($script:TFToolkitSearchLanguageTables.ContainsKey($language)) { return @($script:TFToolkitSearchLanguageTables[$language][$Name]) }

    switch ($Name) {
        "StopWords" { return @($script:TFToolkitSearchStopWords) }
        "SoftWords" { return @($script:TFToolkitSearchSoftWords) }
        "Negations" { return @($script:TFToolkitSearchNegations) }
        "Suffixes" { return @($script:TFToolkitSearchSuffixes) }
        default { return @($script:TFToolkitSearchSynonyms) }
    }
}


function Get-TFToolkitSearchBase {
    # O singular simples de uma palavra de 5 letras ou mais terminada em "s" ("erros" vira "erro", "drivers" vira "driver"):
    # com ele, a busca acha as duas formas. As demais palavras ficam como estão.
    param ([string]$Token)

    if ($Token.Length -ge 5 -and $Token.EndsWith("s") -and -not $Token.EndsWith("ss")) { return $Token.Substring(0, $Token.Length - 1) }

    return $Token
}


function Get-TFToolkitSearchSynonyms {
    # Os sinônimos de uma palavra (sem ela mesma), da tabela TFToolkitSearchSynonyms. Uma palavra em dois grupos fica com
    # os dois ("disable" acha "hide" e "off"), sem juntar os grupos entre si ("hide" não acha "off").
    param ([string]$Token)

    if ($null -eq $script:TFToolkitSearchSynonymMap) {
        $map = @{}

        foreach ($group in @(Get-TFToolkitSearchTable -Name "Synonyms")) {
            $words = @($group -split ' ')

            foreach ($word in $words) {
                $others = @($words | Where-Object { $_ -ne $word })

                if ($map.ContainsKey($word)) { $others = @(@($map[$word]) + $others | Select-Object -Unique) }

                $map[$word] = $others
            }
        }

        $script:TFToolkitSearchSynonymMap = $map
    }

    $found = $script:TFToolkitSearchSynonymMap[$Token]

    if ($null -eq $found) { return @() }

    return @($found)
}


function New-TFToolkitSearchEntry {
    param (
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$PageId,
        [Parameter(Mandatory)][string]$PageTitle,
        [Parameter(Mandatory)][string]$Label,
        [string]$Description = "",

        # Mais texto que a busca reconhece como descrição, sem aparecer no resultado (a frase inteira de um item, Detail).
        [string]$More = "",
        [string]$Keywords = "",
        [string]$PageText = "",
        $Item = $null,
        $Tweak = $null,
        [string]$Section = "",
        [int]$Order = 0,

        # Desempate entre resultados de mesma pontuação: 1 para as ações do TF-Toolkit e as partes de página, 2 para os atalhos
        # que só abrem uma janela do Windows, 3 para os ajustes (as páginas, que vêm pelo título, têm 0).
        [int]$Rank = 1,

        # O caminho recomendado da página (o item com Accent): vem logo depois da página quando a busca acha a página pelo
        # nome (Find-TFToolkitSearchHits).
        [switch]$Accent
    )

    # O que a entrada abre: duas entradas com o mesmo destino (a mesma ação em duas páginas) aparecem uma vez só.
    $target = switch ($Kind) {
        "Item" { $(if ($Item.Kind -eq "Shortcut") { "shortcut:$($Item.Shortcut)" } else { "command:$($Item.Command)" }) }
        "Tweak" { "tweak:$($Tweak.Id)" }
        default { "section:$PageId.$Section" }
    }

    # Os textos levam um espaço em cada ponta: " palavra" acha o começo de uma palavra, "palavra" acha em qualquer ponto.
    # All junta os quatro: uma palavra que não está nele não está em nenhum (a busca pula a entrada com uma comparação só).
    $labelWords = " $(ConvertTo-TFToolkitSearchIndexWords -Text $Label) "
    $descWords = " $(ConvertTo-TFToolkitSearchIndexWords -Text ("$Description $More".Trim())) "
    $keyWords = " $(ConvertTo-TFToolkitSearchIndexWords -Text $Keywords) "
    $pageWords = " $(ConvertTo-TFToolkitSearchIndexWords -Text $PageText) "

    return [PSCustomObject]@{
        Kind        = $Kind
        PageId      = $PageId
        PageTitle   = $PageTitle
        Label       = $Label
        Description = $Description
        Item        = $Item
        Tweak       = $Tweak
        Section     = $Section
        Order       = $Order
        Rank        = $Rank
        Accent      = [bool]$Accent
        Target      = $target
        LabelPlain  = " $(ConvertTo-TFToolkitSearchWords -Text $Label) "
        LabelGlued  = " $(([regex]::Replace((Join-TFToolkitSearchHyphens -Text (ConvertTo-TFToolkitSearchText -Text $Label)), '[^a-z0-9]+', ' ')).Trim()) "
        LabelWords  = $labelWords
        DescWords   = $descWords
        KeyWords    = $keyWords
        PageWords   = $pageWords
        All         = "$labelWords$keyWords$descWords$pageWords"
    }
}


function Get-TFToolkitSearchSections {
    # Partes de uma página que a busca acha pelo nome, além das ações: a Aparência de Sobre o TF-Toolkit é um quadro da
    # página, e não uma ação, mas é o que a pessoa procura com "tema" ou "modo escuro".
    return @(
        [PSCustomObject]@{
            Id          = "appearance"
            PageId      = "app"
            Label       = (Get-TFToolkitText 'Aparência do TF-Toolkit')
            Description = (Get-TFToolkitText 'Claro, escuro ou automático, acompanhando o tema do Windows')
            Keywords    = (Get-TFToolkitText 'tema modo escuro claro noturno cores automatico')
        }
    )
}


function Get-TFToolkitSearchTweakEntries {
    # Os ajustes do Windows que a página de ajustes mostra neste Windows (um ajuste do Windows 11 no 10, ou o botão do
    # Copilot na 24H2, levaria a uma página sem ele). Sem o catálogo (módulo ausente), nenhum: a busca tenta de novo na
    # próxima vez. Um ajuste com defeito fica de fora sozinho.
    try {
        $catalog = @(Get-TFToolkitTweakCatalog)
    }
    catch {
        Write-Verbose "Busca sem os ajustes do Windows: $($_.Exception.Message)"
        return @()
    }

    $entries = New-Object System.Collections.ArrayList
    $order = 100000

    # A página (e o título dela) de cada categoria, procurada uma vez só: são poucas categorias para dezenas de ajustes.
    $pages = @{}

    # Cada ajuste é uma chave: "ligar o modo escuro" e "desligar a telemetria" acham a chave, que liga e desliga. Os verbos
    # contam como o texto da página (o menor peso): sozinhos, eles não passam na frente das palavras de cada ajuste.
    $toggle = (Get-TFToolkitText 'ativar desativar ligar desligar')

    foreach ($tweak in $catalog) {
        $order++

        try {
            if (-not (Test-TFToolkitTweakAvailable -Tweak $tweak)) { continue }

            # Cada ajuste leva à página dele: a Personalização ou os Ajustes do Windows.
            $category = [string]$tweak.Category

            if (-not $pages.ContainsKey($category)) {
                $id = Get-TFToolkitTweakPageId -Tweak $tweak
                $page = Get-TFToolkitNavPage -Id $id
                $pages[$category] = [PSCustomObject]@{ Id = $id; Title = $(if ($null -ne $page) { [string]$page.Title } else { (Get-TFToolkitText 'Ajustes do Windows') }) }
            }

            $pageId = $pages[$category].Id
            $title = $pages[$category].Title
            $extra = [string]$script:TFToolkitSearchTweakKeywords[[string]$tweak.Id]

            # O cartão diz o que a página mostra (o recurso do Windows e o que ele é); o nome do ajuste ("Desativar...")
            # também acha o cartão, entre as palavras de busca.
            $feature = [string](Get-TFToolkitTweakField -Entry $tweak -Name "Feature" -Default $tweak.Name)
            $about = [string](Get-TFToolkitTweakField -Entry $tweak -Name "About" -Default $tweak.Description)

            [void]$entries.Add((New-TFToolkitSearchEntry -Kind "Tweak" -PageId $pageId -PageTitle $title -Label $feature `
                        -Description $about -Keywords "$extra $($tweak.Name)" -PageText "$($title.ToLowerInvariant()) $category $toggle" -Tweak $tweak -Order $order -Rank 3))
        }
        catch {
            Write-Verbose "Busca: o ajuste $($tweak.Id) ficou de fora: $($_.Exception.Message)"
        }
    }

    return @($entries)
}


function Get-TFToolkitSearchIndex {
    # As entradas pesquisáveis, na ordem em que empatam: ações e atalhos de todas as páginas (na ordem da barra lateral),
    # as partes de página que a busca acha (a Aparência) e, por último, os ajustes do Windows.
    if ($null -eq $script:TFToolkitSearchIndex) {
        $entries = New-Object System.Collections.ArrayList
        $order = 0

        foreach ($page in (Get-TFToolkitNavigation)) {
            foreach ($item in $page.Items) {
                $order++
                $rank = $(if ($item.Kind -eq "Shortcut") { 2 } else { 1 })

                [void]$entries.Add((New-TFToolkitSearchEntry -Kind "Item" -PageId $page.Id -PageTitle $page.Title -Label $item.Label `
                            -Description $item.Description -More ([string]$item.Detail) -Keywords $item.Keywords -PageText $page.Title -Item $item -Order $order -Rank $rank `
                            -Accent:([bool]$item.Accent)))
            }
        }

        foreach ($section in (Get-TFToolkitSearchSections)) {
            $order++
            $page = Get-TFToolkitNavPage -Id $section.PageId

            if ($null -eq $page) { continue }

            [void]$entries.Add((New-TFToolkitSearchEntry -Kind "Page" -PageId $page.Id -PageTitle $page.Title -Label $section.Label `
                        -Description $section.Description -Keywords $section.Keywords -PageText $page.Title -Section $section.Id -Order $order))
        }

        $script:TFToolkitSearchIndex = @($entries)
        $script:TFToolkitSearchEntries = $null
    }

    if ($null -eq $script:TFToolkitSearchTweaks) {
        $tweaks = @(Get-TFToolkitSearchTweakEntries)

        if ($tweaks.Count -gt 0) {
            $script:TFToolkitSearchTweaks = $tweaks
            $script:TFToolkitSearchEntries = $null
        }
    }

    if ($null -eq $script:TFToolkitSearchEntries) {
        $all = @($script:TFToolkitSearchIndex)

        if ($null -ne $script:TFToolkitSearchTweaks) { $all += $script:TFToolkitSearchTweaks }

        $script:TFToolkitSearchEntries = $all
        $script:TFToolkitSearchAllText = (@($all | ForEach-Object { $_.All }) -join "")
        $script:TFToolkitSearchVocabulary = $null
        $script:TFToolkitSearchCorrections = @{}
    }

    return $script:TFToolkitSearchEntries
}


function Get-TFToolkitSearchPages {
    # As páginas que a busca sabe abrir: o Início e as da tabela de navegação (inclusive a do rodapé).
    $pages = @([PSCustomObject]@{ Id = "home"; Title = (Get-TFToolkitText 'Início'); Summary = (Get-TFToolkitText 'O estado do PC, a nota de saúde e os atalhos mais procurados.') })

    foreach ($page in (Get-TFToolkitNavigation)) {
        $pages += [PSCustomObject]@{ Id = $page.Id; Title = $page.Title; Summary = $page.Summary }
    }

    return $pages
}


function Get-TFToolkitSearchPageIndex {
    # As páginas com o título já normalizado (Words) e as palavras dele (TitleWords), montadas uma vez.
    if ($null -eq $script:TFToolkitSearchPageIndex) {
        $order = -1000

        $script:TFToolkitSearchPageIndex = @(
            foreach ($page in (Get-TFToolkitSearchPages)) {
                $order++
                $words = ConvertTo-TFToolkitSearchWords -Text $page.Title

                [PSCustomObject]@{
                    Id = $page.Id; Title = $page.Title; Summary = $page.Summary; Words = $words; TitleWords = @($words -split ' '); Order = $order
                }
            }
        )
    }

    return $script:TFToolkitSearchPageIndex
}


function Get-TFToolkitSearchVocabulary {
    # As palavras do índice com 4 letras ou mais, agrupadas pela primeira letra, cada uma com um peso (rótulo e
    # palavras-chave pesam mais que descrição e página). A correção de digitação procura aqui a palavra mais parecida.
    $entries = Get-TFToolkitSearchIndex

    if ($null -ne $script:TFToolkitSearchVocabulary) { return $script:TFToolkitSearchVocabulary }

    $weights = @{}

    foreach ($entry in $entries) {
        foreach ($field in @(@($entry.LabelWords, 3), @($entry.KeyWords, 3), @($entry.DescWords, 1), @($entry.PageWords, 1))) {
            foreach ($word in ([string]$field[0]).Split([char]32)) {
                if ($word.Length -ge 4) { $weights[$word] = [int]$weights[$word] + [int]$field[1] }
            }
        }
    }

    foreach ($page in (Get-TFToolkitSearchPageIndex)) {
        foreach ($word in $page.Words.Split([char]32)) {
            if ($word.Length -ge 4) { $weights[$word] = [int]$weights[$word] + 3 }
        }
    }

    foreach ($group in @(Get-TFToolkitSearchTable -Name "Synonyms")) {
        foreach ($word in ($group -split ' ')) {
            if ($word.Length -ge 4) { $weights[$word] = [int]$weights[$word] + 1 }
        }
    }

    $byLetter = @{}

    # get_Keys(), e não .Keys: as palavras são as chaves, e num índice com a palavra "keys" (o inglês tem, de "Sticky keys")
    # $weights.Keys devolveria o peso dela, e o vocabulário ficaria com uma palavra só.
    foreach ($word in (@($weights.get_Keys()) | Sort-Object)) {
        $letter = [string]$word[0]

        if (-not $byLetter.ContainsKey($letter)) { $byLetter[$letter] = New-Object System.Collections.ArrayList }

        [void]$byLetter[$letter].Add([PSCustomObject]@{ Word = $word; Weight = $weights[$word] })
    }

    $script:TFToolkitSearchVocabulary = $byLetter

    return $byLetter
}


function Get-TFToolkitSearchCorrection {
    <#
    A palavra do índice mais parecida com uma que não aparece em lugar nenhum ("limpesa" vira "limpeza", "antevirus" vira
    "antivirus"). Só corrige palavras de 6 letras ou mais, com as mesmas duas primeiras letras, e aceita 1 letra trocada,
    sobrando, faltando ou invertida com a vizinha (2 nas palavras de 9 letras ou mais). A palavra do índice pode ser maior
    (quem ainda está digitando: "atualisa" acha "atualizar"), mas só 1 letra menor, e só nas palavras de 8 letras ou mais:
    "filmes" não vira "files" nem "carregador" vira "carregar". Empate: a palavra mais usada no índice. Vazio quando
    nenhuma serve. A resposta de cada palavra fica guardada até o índice mudar.
    #>
    param ([Parameter(Mandatory)][AllowEmptyString()][string]$Token)

    if ($Token.Length -lt 6 -or $Token -notmatch '^[a-z]+$') { return "" }

    $vocabulary = Get-TFToolkitSearchVocabulary

    if ($script:TFToolkitSearchCorrections.ContainsKey($Token)) { return [string]$script:TFToolkitSearchCorrections[$Token] }

    $candidates = $vocabulary[[string]$Token[0]]
    $best = ""

    if ($null -ne $candidates) {
        $n = $Token.Length
        $limit = $(if ($n -ge 9) { 2 } else { 1 })
        $width = $n + $limit + 1
        $before = [int[]]::new($width)
        $previous = [int[]]::new($width)
        $current = [int[]]::new($width)
        $bestDistance = $limit + 1
        $bestWeight = 0

        foreach ($candidate in $candidates) {
            $word = [string]$candidate.Word

            if ($word[1] -cne $Token[1]) { continue }
            if ($word.Length -lt $n -and -not ($n -ge 8 -and $word.Length -eq $n - 1)) { continue }

            # Distância de Damerau (alinhamento ótimo) entre a palavra digitada e os começos da palavra do índice de n a
            # n + limit letras (ou a palavra inteira, quando ela é menor).
            $other = $(if ($word.Length -gt $n + $limit) { $word.Substring(0, $n + $limit) } else { $word })
            $m = $other.Length

            for ($j = 0; $j -le $m; $j++) { $previous[$j] = $j }

            $rowMin = 0
            $lastRowMin = 0

            for ($i = 1; $i -le $n; $i++) {
                $current[0] = $i
                $rowMin = $i
                $a = $Token[$i - 1]

                for ($j = 1; $j -le $m; $j++) {
                    $b = $other[$j - 1]
                    $value = $previous[$j - 1] + $(if ($a -ceq $b) { 0 } else { 1 })

                    if ($previous[$j] + 1 -lt $value) { $value = $previous[$j] + 1 }
                    if ($current[$j - 1] + 1 -lt $value) { $value = $current[$j - 1] + 1 }

                    if ($i -gt 1 -and $j -gt 1 -and $a -ceq $other[$j - 2] -and $Token[$i - 2] -ceq $b -and $before[$j - 2] + 1 -lt $value) {
                        $value = $before[$j - 2] + 1
                    }

                    $current[$j] = $value
                    if ($value -lt $rowMin) { $rowMin = $value }
                }

                if ($rowMin -gt $limit -and $lastRowMin -gt $limit) { break }

                $lastRowMin = $rowMin
                $swap = $before
                $before = $previous
                $previous = $current
                $current = $swap
            }

            if ($rowMin -gt $limit) { continue }

            # A última linha completa ficou em $previous: vale o melhor começo de n letras ou mais (ou a palavra inteira).
            $distance = $limit + 1

            for ($j = [Math]::Min($n, $m); $j -le $m; $j++) {
                if ($previous[$j] -lt $distance) { $distance = $previous[$j] }
            }

            # Uma palavra do índice menor que a digitada só vale com 1 letra de diferença.
            if ($m -lt $n -and $distance -gt 1) { continue }
            if ($distance -gt $limit -or $distance -eq 0) { continue }

            if ($distance -lt $bestDistance -or ($distance -eq $bestDistance -and [int]$candidate.Weight -gt $bestWeight)) {
                $best = $word
                $bestDistance = $distance
                $bestWeight = [int]$candidate.Weight
            }
        }
    }

    $script:TFToolkitSearchCorrections[$Token] = $best

    return $best
}


function Test-TFToolkitSearchKnown {
    # A palavra aparece em algum texto do índice (inteira, no meio de outra, pelo singular ou pelo radical) ou tem
    # sinônimos: não é erro de digitação.
    param ([Parameter(Mandatory)][string]$Token)

    [void](Get-TFToolkitSearchIndex)
    $all = $script:TFToolkitSearchAllText

    if ($all.Contains($Token)) { return $true }

    $base = Get-TFToolkitSearchBase -Token $Token
    if ($base -ne $Token -and $all.Contains(" $base")) { return $true }

    $stem = Get-TFToolkitSearchStem -Token $Token
    if ($stem -and $all.Contains(" $stem")) { return $true }

    return (@(Get-TFToolkitSearchSynonyms -Token $Token).Count -gt 0)
}


function Test-TFToolkitSearchInside {
    # A palavra aparece no meio de outra do texto, mas não logo depois de um prefixo que inverte o sentido: "ativar" não
    # acha "desativar", "fazer" não acha "desfazer" e "iniciar" não acha "reiniciar"; "virus" acha "antivirus".
    param ([string]$Text, [string]$Token)

    $index = $Text.IndexOf($Token, [System.StringComparison]::Ordinal)

    while ($index -ge 0) {
        $wordStart = $Text.LastIndexOf([char]32, $index) + 1
        $prefix = $Text.Substring($wordStart, $index - $wordStart)

        if ($prefix.Length -gt 0 -and $prefix -notin @(Get-TFToolkitSearchTable -Name "Negations")) { return $true }

        $index = $Text.IndexOf($Token, $index + 1, [System.StringComparison]::Ordinal)
    }

    return $false
}


function Get-TFToolkitSearchQuery {
    # O texto digitado pronto para a busca: Words (as palavras, sem repetir, para o bônus do nome exato), Tokens (as que
    # contam: sem as de ligação, quando sobra outra) e Hard (quantas são obrigatórias; "pc" e "computador" não são).
    # Uma palavra com hífen vale como uma só ("wi-fi" é "wifi"), e Joined diz que houve uma; -SplitHyphens separa as
    # partes ("limpeza-rápida", quando o hífen não era de uma palavra composta). $null quando não há o que buscar:
    # vazio, só símbolos ou uma letra só.
    param (
        [AllowEmptyString()][AllowNull()][string]$Query,
        [switch]$SplitHyphens
    )

    if ([string]::IsNullOrEmpty($Query)) { return $null }

    if ($Query.Length -gt $script:TFToolkitSearchMaxLength) { $Query = $Query.Substring(0, $script:TFToolkitSearchMaxLength) }

    $plain = ConvertTo-TFToolkitSearchText -Text $Query
    $joined = $false

    if (-not $SplitHyphens) {
        $glued = Join-TFToolkitSearchHyphens -Text $plain
        $joined = ($glued -ne $plain)
        $plain = $glued
    }

    $words = ([regex]::Replace($plain, '[^a-z0-9]+', ' ')).Trim()

    if ($words.Replace(" ", "").Length -lt 2) { return $null }

    # Palavra repetida vale uma vez só.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $unique = @(foreach ($word in $words.Split([char]32)) { if ($seen.Add($word)) { $word } })
    $unique = @($unique | Select-Object -First $script:TFToolkitSearchMaxWords)
    $stopWords = @(Get-TFToolkitSearchTable -Name "StopWords")
    $softWords = @(Get-TFToolkitSearchTable -Name "SoftWords")
    $meaningful = @($unique | Where-Object { $_ -notin $stopWords })

    # Só palavras de ligação ("de", "para"): valem como estão, para quem ainda está digitando "desinstalar".
    $tokens = @(if ($meaningful.Count -gt 0) { $meaningful } else { $unique })
    $hard = @($tokens | Where-Object { $_ -notin $softWords })

    # Só "pc" ou "computador": elas mesmas são o que se procura.
    if ($hard.Count -eq 0) { $hard = @($tokens) }

    return [PSCustomObject]@{
        Words = ($unique -join ' '); Phrase = ($tokens -join ' '); All = $unique; Tokens = @($tokens); Hard = $hard.Count; Meaningful = $meaningful.Count
        Joined = $joined
    }
}


function New-TFToolkitSearchSpecs {
    # Como procurar cada palavra: as formas que valem (a própria palavra; o singular simples, que vale 1 ponto a menos, e
    # os sinônimos, 4 a menos), se ela é opcional ("pc" com outra palavra) e se é curta (uma ou duas letras) e não a última
    # da frase: aí ela só vale como palavra inteira ("wi" em "wi fi" não acha "Windows"). A última pode estar sendo
    # digitada e vale pelo começo, como uma palavra sozinha. O singular vale como palavra inteira: no começo de outra
    # palavra, ele é só o radical ("programas" acha "Programas" pelo nome e "programador" pelo radical, com o peso dele).
    param ([string[]]$Tokens)

    # "pc" e "computador" só são opcionais quando há outra palavra que conta.
    $softWords = @(Get-TFToolkitSearchTable -Name "SoftWords")
    $soft = (@($Tokens | Where-Object { $_ -notin $softWords }).Count -gt 0)
    $last = $(if (@($Tokens).Count -gt 0) { [string]@($Tokens)[-1] } else { "" })

    return @(
        foreach ($token in $Tokens) {
            $base = Get-TFToolkitSearchBase -Token $token
            $stem = Get-TFToolkitSearchStem -Token $token

            # Probe: o pedaço que precisa estar no texto para qualquer forma de achar valer (o radical é o começo da palavra).
            $variants = @([PSCustomObject]@{
                    Start = " $token"; Whole = " $token "; Token = $token; Inside = ($token.Length -ge 5)
                    Stem = $(if ($stem) { " $stem" } else { "" }); Penalty = 0; Probe = $(if ($stem) { $stem } else { $token })
                })

            if ($base -ne $token) {
                $variants += [PSCustomObject]@{ Start = " $base "; Whole = " $base "; Token = $base; Inside = $false; Stem = ""; Penalty = 1; Probe = " $base" }
            }

            foreach ($synonym in (Get-TFToolkitSearchSynonyms -Token $token)) {
                $variants += [PSCustomObject]@{
                    Start = " $synonym"; Whole = " $synonym "; Token = $synonym; Inside = $false; Stem = ""; Penalty = $script:TFToolkitSearchSynonymPenalty; Probe = " $synonym"
                }
            }

            [PSCustomObject]@{
                Token = $token; Soft = ($soft -and $token -in $softWords); Variants = $variants
                Short = ($token.Length -le 2); Last = ($token -eq $last)
            }
        }
    )
}


function Find-TFToolkitSearchHits {
    <#
    Uma passada pelo índice e pelos títulos das páginas. A pontuação de cada palavra é a do melhor lugar em que ela
    aparece (do maior para o menor):
      17/16  começo do rótulo (17 com a palavra inteira)       9  radical no rótulo ("limp" de limpar)
      13/12  começo de outra palavra do rótulo               9/8  palavras-chave (9 com a palavra inteira)
       7     no meio de uma palavra do rótulo (5+ letras)      6  radical nas palavras-chave
       5     descrição; 4 radical; 3 no meio dela              3  título da página; 2 no meio ou radical
    O singular simples vale 1 a menos, e um sinônimo, 4 a menos. O nome exato do item ganha 20; uma frase inteira das palavras-chave,
    10 (5 quando a frase só bate sem as palavras de ligação). "pc" soma 1 quando
    o texto tem a palavra. Uma página cujo título começa com a busca vale 40 (60 com o título inteiro): acima de qualquer
    item de até três palavras. O caminho recomendado de uma página achada assim ganha 10 (TFToolkitSearchHighlightBonus):
    vem logo depois dela, sem passar um nome exato. Sem -Partial, todas as palavras obrigatórias precisam aparecer; com
    ele, basta uma. Uma palavra de uma ou duas letras que não é a última (e qualquer uma delas com -Partial) só vale inteira.
    #>
    param (
        [Parameter(Mandatory)]$Query,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Specs,
        [switch]$Partial
    )

    $words = [string]$Query.Words
    $phrase = " $($Query.Phrase) "
    $multiWord = $words.Contains(" ")
    $multiPhrase = ([string]$Query.Phrase).Contains(" ")
    $found = New-Object System.Collections.ArrayList

    foreach ($entry in (Get-TFToolkitSearchIndex)) {
        $total = 0
        $matched = 0
        $missing = $false
        $label = $entry.LabelWords

        foreach ($spec in $Specs) {
            if ($spec.Soft) {
                $whole = " $($spec.Token) "
                if ($label.Contains($whole) -or $entry.KeyWords.Contains($whole) -or $entry.DescWords.Contains($whole)) { $total += 1 }
                continue
            }

            $best = 0

            # Curta e no meio da frase (ou numa busca por parte das palavras): só a palavra inteira vale.
            $wholeOnly = ($spec.Short -and ($Partial -or -not $spec.Last))

            foreach ($variant in $spec.Variants) {
                if (-not $entry.All.Contains($variant.Probe)) { continue }

                $start = $variant.Start
                $value = 0

                if ($wholeOnly) {
                    $whole = $variant.Whole

                    if ($label.Contains($whole)) { $value = $(if ($label.StartsWith($whole)) { 17 } else { 13 }) }
                    elseif ($entry.KeyWords.Contains($whole)) { $value = 9 }
                    elseif ($entry.DescWords.Contains($whole)) { $value = 5 }
                    elseif ($entry.PageWords.Contains($whole)) { $value = 3 }
                }
                elseif ($label.Contains($start)) {
                    $value = $(if ($label.StartsWith($start)) { 16 } else { 12 })
                    if ($label.Contains($variant.Whole)) { $value += 1 }
                }
                elseif ($variant.Stem -and $label.Contains($variant.Stem)) { $value = 9 }
                elseif ($entry.KeyWords.Contains($start)) { $value = $(if ($entry.KeyWords.Contains($variant.Whole)) { 9 } else { 8 }) }
                elseif ($variant.Inside -and $label.Contains($variant.Token) -and (Test-TFToolkitSearchInside -Text $label -Token $variant.Token)) { $value = 7 }
                elseif ($variant.Stem -and $entry.KeyWords.Contains($variant.Stem)) { $value = 6 }
                elseif ($entry.DescWords.Contains($start)) { $value = 5 }
                elseif ($variant.Stem -and $entry.DescWords.Contains($variant.Stem)) { $value = 4 }
                elseif ($variant.Inside -and $entry.DescWords.Contains($variant.Token) -and (Test-TFToolkitSearchInside -Text $entry.DescWords -Token $variant.Token)) { $value = 3 }
                elseif ($entry.PageWords.Contains($start)) { $value = 3 }
                elseif ($variant.Inside -and $entry.PageWords.Contains($variant.Token) -and (Test-TFToolkitSearchInside -Text $entry.PageWords -Token $variant.Token)) { $value = 2 }
                elseif ($variant.Stem -and $entry.PageWords.Contains($variant.Stem)) { $value = 2 }

                # Vale a forma que acha melhor: a palavra exata nas palavras-chave (8) perde para o sinônimo no rótulo (15).
                if ($value -gt 0) {
                    $value = [Math]::Max(1, $value - [int]$variant.Penalty)
                    if ($value -gt $best) { $best = $value }
                }
            }

            if ($best -eq 0) {
                if ($Partial) { continue }

                $missing = $true
                break
            }

            $matched++
            $total += $best
        }

        if ($missing -or $matched -eq 0) { continue }

        if ($entry.LabelPlain -eq " $words " -or $entry.LabelGlued -eq " $words ") { $total += 20 }
        elseif ($multiWord -and $entry.KeyWords.Contains(" $words ")) { $total += 10 }
        elseif ($multiPhrase -and $entry.KeyWords.Contains($phrase)) { $total += 5 }

        [void]$found.Add([PSCustomObject]@{
                Kind = $entry.Kind; PageId = $entry.PageId; PageTitle = $entry.PageTitle; Label = $entry.Label
                Description = $entry.Description; Item = $entry.Item; Tweak = $entry.Tweak; Section = $entry.Section
                Score = $total; Matched = $matched; Rank = $entry.Rank; Accent = $entry.Accent; Order = $entry.Order; Target = $entry.Target
                Partial = [bool]$Partial; Corrected = ""
            })
    }

    if (-not $Partial -and $words.Length -ge 2) {
        # Uma busca de uma palavra só (fora "pc") acha também a página por qualquer palavra do título, pelo singular ou pelo
        # radical: "redes" acha Rede, "limpar" acha Limpeza, "atualizar" acha Atualizações, "tweaks" acha Windows tweaks e
        # "tf-toolkit" acha Sobre o TF-Toolkit. O Início fica de fora ("iniciar" é de inicialização). Uma palavra de ligação já
        # faz mais de uma: "about this pc" é o nome de Sobre este PC, e não o começo de About TF-Toolkit.
        $softWords = @(Get-TFToolkitSearchTable -Name "SoftWords")
        $plainWords = @($Query.All | Where-Object { $_ -notin $softWords })
        $single = $(if ($Query.Hard -eq 1 -and $plainWords.Count -eq 1) { @($Specs | Where-Object { -not $_.Soft })[0] } else { $null })
        $alternatives = @()

        if ($null -ne $single) {
            $alternatives = @($single.Token, (Get-TFToolkitSearchBase -Token $single.Token), $single.Variants[0].Stem.Trim()) | Where-Object { $_.Length -ge 4 }
        }

        $pages = New-Object 'System.Collections.Generic.HashSet[string]'

        foreach ($page in (Get-TFToolkitSearchPageIndex)) {
            $score = 0

            if ($page.Words.StartsWith($words)) { $score = $(if ($page.Words -eq $words) { 60 } else { 40 }) }
            elseif ($page.Id -ne "home") {
                foreach ($alternative in $alternatives) {
                    foreach ($titleWord in $page.TitleWords) {
                        if ($titleWord.StartsWith($alternative)) { $score = 40; break }
                    }

                    if ($score -gt 0) { break }
                }
            }

            if ($score -gt 0) {
                [void]$pages.Add([string]$page.Id)
                [void]$found.Add([PSCustomObject]@{
                        Kind = "Page"; PageId = $page.Id; PageTitle = $page.Title; Label = $page.Title; Description = $page.Summary
                        Item = $null; Tweak = $null; Section = ""; Score = $score; Matched = $Query.Hard; Rank = 0; Accent = $false; Order = $page.Order
                        Target = "page:$($page.Id)"; Partial = $false; Corrected = ""
                    })
            }
        }

        # A página achada pelo nome traz logo depois o caminho recomendado dela ("limpar": Limpeza e, em seguida, a Limpeza
        # rápida), quando ele também tem as palavras.
        if ($pages.Count -gt 0) {
            foreach ($hit in $found) {
                if ($hit.Accent -and $hit.Kind -eq "Item" -and $pages.Contains([string]$hit.PageId)) { $hit.Score += $script:TFToolkitSearchHighlightBonus }
            }
        }
    }

    return , $found
}


function Search-TFToolkitNavigation {
    <#
    Procura nas ações, atalhos, páginas e ajustes do Windows pelo texto digitado (pontuação em Find-TFToolkitSearchHits).
    Quando nada tem todas as palavras, a busca tenta, nesta ordem: separar as partes de uma palavra com hífen
    ("limpeza-rápida"), trocar uma palavra que não existe no índice pela mais parecida (erro de digitação; Corrected diz a busca corrigida) e aceitar o que tem parte das palavras (Partial, com
    os que têm mais palavras primeiro). A mesma ação em duas páginas aparece uma vez só. Devolve Kind (Item | Tweak |
    Page), PageId, PageTitle, Label, Description, Item (ou Tweak), Section, Score, Rank, Accent, Order, Partial e Corrected,
    do melhor para o pior; empates: as páginas, depois as ações, os atalhos do Windows e os ajustes, e então a ordem da
    barra lateral e de cada página (que vai do mais seguro ao que mexe mais fundo). -First limita a quantidade.
    #>
    param (
        [AllowEmptyString()][AllowNull()][string]$Query,
        [int]$First = 0
    )

    $prepared = Get-TFToolkitSearchQuery -Query $Query

    if ($null -eq $prepared) { return @() }

    $hits = Find-TFToolkitSearchHits -Query $prepared -Specs (New-TFToolkitSearchSpecs -Tokens $prepared.Tokens)
    $corrected = ""

    # Um hífen que não era de palavra composta ("limpeza-rápida"): as partes, separadas, acham o que a pessoa quis dizer.
    if ($hits.Count -eq 0 -and $prepared.Joined) {
        $split = Get-TFToolkitSearchQuery -Query $Query -SplitHyphens

        if ($null -ne $split) {
            $splitHits = Find-TFToolkitSearchHits -Query $split -Specs (New-TFToolkitSearchSpecs -Tokens $split.Tokens)

            if ($splitHits.Count -gt 0) {
                $prepared = $split
                $hits = $splitHits
            }
        }
    }

    if ($hits.Count -eq 0) {
        # Uma palavra que não aparece em lugar nenhum do índice pode ser erro de digitação: vale a mais parecida. Com mais
        # de duas palavras desconhecidas, não é erro de digitação (é outro assunto, ou um texto colado).
        $softWords = @(Get-TFToolkitSearchTable -Name "SoftWords")
        $unknown = @($prepared.Tokens | Where-Object { $_ -notin $softWords -and -not (Test-TFToolkitSearchKnown -Token $_) })
        $fixed = @{}

        if ($unknown.Count -le 2) {
            foreach ($token in $unknown) {
                $correction = Get-TFToolkitSearchCorrection -Token $token
                if ($correction) { $fixed[$token] = $correction }
            }
        }

        if ($fixed.Count -gt 0) {
            $prepared = Get-TFToolkitSearchQuery -Query (@($prepared.All | ForEach-Object { if ($fixed.ContainsKey($_)) { $fixed[$_] } else { $_ } }) -join ' ')
            $hits = Find-TFToolkitSearchHits -Query $prepared -Specs (New-TFToolkitSearchSpecs -Tokens $prepared.Tokens)
            $corrected = $prepared.Words
        }
    }

    # Parte das palavras só vale com duas ou mais palavras que contam (só palavras de ligação, como "o que fazer", não).
    if ($hits.Count -eq 0 -and $prepared.Hard -gt 1 -and $prepared.Meaningful -gt 1) {
        $hits = Find-TFToolkitSearchHits -Query $prepared -Specs (New-TFToolkitSearchSpecs -Tokens $prepared.Tokens) -Partial
    }

    if ($hits.Count -eq 0) { return @() }

    $sorted = @($hits | Sort-Object @{ Expression = "Matched"; Descending = $true }, @{ Expression = "Score"; Descending = $true },
        @{ Expression = "Rank"; Descending = $false }, @{ Expression = "Order"; Descending = $false })

    $targets = New-Object 'System.Collections.Generic.HashSet[string]'
    $unique = New-Object System.Collections.ArrayList

    foreach ($hit in $sorted) {
        if (-not $targets.Add([string]$hit.Target)) { continue }

        $hit.Corrected = $corrected
        [void]$unique.Add($hit)

        if ($First -gt 0 -and $unique.Count -ge $First) { break }
    }

    return @($unique)
}


function Test-TFToolkitSearchEnterOpens {
    # O Enter na caixa de busca abre o primeiro resultado só quando ele achou o que foi digitado. Numa busca corrigida ou
    # que achou só parte das palavras, ele só abre uma página (ou um ajuste, que leva à página); uma ação ou uma janela do
    # Windows fica selecionada, para a pessoa conferir antes: nada roda por um palpite.
    param ($Hit)

    if ($null -eq $Hit) { return $false }
    if (-not [bool]$Hit.Partial -and [string]::IsNullOrEmpty([string]$Hit.Corrected)) { return $true }

    return ($Hit.Kind -eq "Page" -or $Hit.Kind -eq "Tweak")
}


function Test-TFToolkitSearchTooShort {
    # Uma letra só (ou um algarismo): a busca espera a segunda, em vez de mostrar quase tudo.
    param ([AllowEmptyString()][AllowNull()][string]$Query)

    $compact = (ConvertTo-TFToolkitSearchWords -Text $Query).Replace(" ", "")

    return ($compact.Length -eq 1)
}


# Os itens que, na janela, são um cartão da página (o Idioma de Sobre o TF-Toolkit): a busca leva ao cartão, com o foco na
# escolha marcada, e não à pergunta do menu de texto.
$script:TFToolkitSearchCardSections = @{ "app.language" = "language" }


function Test-TFToolkitNavItemHidden {
    <#
    Se a janela tira um item das páginas neste PC (e, pelo mesmo motivo, da busca): com outro antivírus protegendo o PC,
    as ações do Windows Defender, que não fariam nada; sem bateria, a Saúde da bateria, que só diria isso. AntivirusMode
    e HasBattery vêm da leitura do Início; enquanto ela não termina ("" e $null), nada sai.
    #>
    param (
        [AllowEmptyString()][string]$Id,
        [AllowEmptyString()][string]$AntivirusMode = "",
        $HasBattery = $null
    )

    if ($AntivirusMode -eq "Other" -and $Id -in @("security.signatures", "security.scan", "security.full-scan", "security.folder-scan")) { return $true }
    if ($HasBattery -is [bool] -and -not $HasBattery -and $Id -eq "diagnostics.battery") { return $true }

    return $false
}


function Get-TFToolkitSearchCardItem {
    # O item que a janela desenha como cartão para um resultado, e que o clique (ou o Enter no primeiro) executa. Ações e
    # atalhos são os próprios itens da tabela; uma página, uma parte de página, um ajuste e um item que na janela é um
    # cartão (TFToolkitSearchCardSections) viram um item "Page" que leva à página. Um ajuste avançado leva junto
    # TweakAdvanced, para a página de ajustes abrir o grupo recolhido onde ele está; uma parte de página leva Section, para
    # a página levar o foco até ela.
    param ([Parameter(Mandatory)]$Hit)

    $section = ""
    if ($Hit.Kind -eq "Item") { $section = [string]$script:TFToolkitSearchCardSections[[string]$Hit.Item.Id] }

    if ($section) {
        # Um item que, na janela, é um cartão da página: a busca leva ao cartão, como a Aparência.
        return [PSCustomObject]@{
            Id = "search.page.$($Hit.PageId).$section"; Label = $Hit.Label; Description = $Hit.Description; Kind = "Page"; Command = $Hit.PageId
            Shortcut = ""; Accent = $false; RequiresAdmin = $false; Keywords = ""; TweakId = ""; TweakAdvanced = $false; Section = $section
        }
    }

    switch ($Hit.Kind) {
        "Item" { return $Hit.Item }
        "Page" {
            $section = [string]$Hit.Section

            return [PSCustomObject]@{
                Id = $(if ($section) { "search.page.$($Hit.PageId).$section" } else { "search.page.$($Hit.PageId)" })
                Label = $Hit.Label; Description = $Hit.Description; Kind = "Page"; Command = $Hit.PageId; Shortcut = ""
                Accent = $false; RequiresAdmin = $false; Keywords = ""; TweakId = ""; TweakAdvanced = $false; Section = $section
            }
        }
        default {
            return [PSCustomObject]@{
                Id = "search.tweak.$($Hit.PageId).$($Hit.Tweak.Id)"; Label = $Hit.Label; Description = $Hit.Description; Kind = "Page"
                Command = [string]$Hit.PageId; Shortcut = ""; Accent = $false; RequiresAdmin = $false; Keywords = ""; TweakId = [string]$Hit.Tweak.Id
                TweakAdvanced = [bool]$Hit.Tweak.Advanced; Section = ""
            }
        }
    }
}


function Get-TFToolkitSearchFocus {
    # O que a página aberta por um resultado da busca destaca: TweakId (o ajuste; vazio quando o item não é um ajuste),
    # Advanced (o ajuste está no grupo recolhido, que precisa abrir) e Section (a parte da página que recebe o foco, como a
    # Aparência). Serve para qualquer item.
    param ($Item)

    $id = ""
    $advanced = $false
    $section = ""

    if ($null -ne $Item) {
        $idProperty = $Item.PSObject.Properties["TweakId"]
        $advancedProperty = $Item.PSObject.Properties["TweakAdvanced"]
        $sectionProperty = $Item.PSObject.Properties["Section"]

        if ($null -ne $idProperty -and $null -ne $idProperty.Value) { $id = [string]$idProperty.Value }
        if ($id -and $null -ne $advancedProperty) { $advanced = [bool]$advancedProperty.Value }
        if ($null -ne $sectionProperty -and $null -ne $sectionProperty.Value) { $section = [string]$sectionProperty.Value }
    }

    return [PSCustomObject]@{ TweakId = $id; Advanced = $advanced; Section = $section }
}


function Get-TFToolkitSearchContext {
    # O texto discreto acima do título de um resultado: de onde ele vem. Um ajuste (e um item que, na janela, é uma linha
    # no grupo de uma categoria, como a Cor de destaque) leva a categoria em que está na página: "Ajustes do Windows >
    # Explorador".
    param ([Parameter(Mandatory)]$Hit)

    switch ($Hit.Kind) {
        "Page" { return $(if ([string]$Hit.Section) { [string]$Hit.PageTitle } else { (Get-TFToolkitText 'Ir para a página') }) }
        "Tweak" { return "$($Hit.PageTitle) > $($Hit.Tweak.Category)" }
        default {
            $category = $(if ($null -ne $Hit.Item -and $null -ne $Hit.Item.PSObject.Properties["ListCategory"]) { [string]$Hit.Item.ListCategory } else { "" })

            if ($category) { return "$($Hit.PageTitle) > $category" }

            return [string]$Hit.PageTitle
        }
    }
}


function Format-TFToolkitSearchQuote {
    # O texto da busca para o cabeçalho, abreviado em 40 caracteres sem partir um emoji ao meio.
    param ([AllowEmptyString()][AllowNull()][string]$Text)

    $value = ([string]$Text).Trim()

    if ($value.Length -le 40) { return $value }

    $cut = 40
    if ([char]::IsHighSurrogate($value[$cut - 1])) { $cut-- }

    return $value.Substring(0, $cut) + "…"
}


function Get-TFToolkitSearchSummary {
    # A linha sob o título "Busca": quantos resultados, se a busca foi corrigida ou só achou parte das palavras, e o Enter
    # (-EnterSelects: o Enter só seleciona o primeiro, sem abrir; veja Test-TFToolkitSearchEnterOpens).
    param (
        [AllowEmptyString()][string]$Query,
        [int]$Total,
        [int]$Shown,
        [switch]$Partial,
        [AllowEmptyString()][string]$Corrected = "",
        [switch]$EnterSelects
    )

    if (Test-TFToolkitSearchTooShort -Query $Query) { return (Get-TFToolkitText 'Continue digitando: a busca começa na segunda letra') }

    $text = Format-TFToolkitSearchQuote -Text $Query

    if ($Total -le 0) { return (Get-TFToolkitText 'Nada encontrado para ''{0}''' "$text") }

    $what = $(if ($Corrected) { (Get-TFToolkitText '''{0}'' (você digitou ''{1}'')' "$(Format-TFToolkitSearchQuote -Text $Corrected)" "$text") } else { "'$text'" })
    $enter = $(if ($Total -eq 1) { (Get-TFToolkitText 'Enter abre') } else { (Get-TFToolkitText 'Enter abre o primeiro') })
    if ($EnterSelects) { $enter = $(if ($Total -eq 1) { (Get-TFToolkitText 'Enter seleciona') } else { (Get-TFToolkitText 'Enter seleciona o primeiro') }) }

    if ($Partial) {
        $closest = $(if ($Shown -le 1) { (Get-TFToolkitText 'o mais próximo') } else { (Get-TFToolkitText 'os {0} mais próximos' "$Shown") })
        return (Get-TFToolkitText 'Nada tem todas as palavras de {0}; {1} · {2}' "$what" "$closest" "$enter")
    }

    if ($Total -eq 1) { return (Get-TFToolkitText '1 resultado para {0} · {1}' "$what" "$enter") }
    if ($Shown -lt $Total) { return (Get-TFToolkitText 'Mostrando os {0} melhores de {1} resultados para {2} · {3}' "$Shown" "$Total" "$what" "$enter") }

    return (Get-TFToolkitText '{0} resultados para {1} · {2}' "$Total" "$what" "$enter")
}


function Get-TFToolkitSearchSuggestions {
    # As buscas sugeridas quando nada foi encontrado, do jeito que a pessoa diria: todas devolvem resultados (um teste
    # confere).
    return @((Get-TFToolkitText 'pc lento'), (Get-TFToolkitText 'sem espaço'), (Get-TFToolkitText 'internet lenta'), (Get-TFToolkitText 'vírus'))
}


# ---------------------------------------------------------------------------
# Teclas de atalho da janela
# ---------------------------------------------------------------------------

function Get-TFToolkitPageShortcutKey {
    # A tecla que abre a página de posição Index na lista dos atalhos (0 = Início): "Ctrl+1" a "Ctrl+9", e "Ctrl+0" para a
    # décima. Vazio depois disso.
    param ([int]$Index)

    if ($Index -lt 0 -or $Index -gt 9) { return "" }

    return (Get-TFToolkitText 'Ctrl+{0}' "$(($Index + 1) % 10)")
}


function Resolve-TFToolkitKeyAction {
    <#
    O que uma tecla faz na janela. A janela só traduz o evento do WPF (nome da tecla, Ctrl/Alt/Shift e o estado da tela)
    e executa a resposta; as regras ficam aqui para serem testadas. Action:
      FocusSearch        Ctrl+K, e Ctrl+F fora de uma lista com filtro
      FocusPromptFilter  Ctrl+F com uma lista de marcação com filtro na tela
      OpenPage           Ctrl+1 a Ctrl+9 e Ctrl+0 (PageIndex é a posição na lista de páginas)
      Refresh            F5 numa página
      LeaveRun           Esc na tela de execução já terminada
      LeaveSearch        Esc com resultados da busca na tela (volta à página de onde ela começou)
      ClearSearch        Esc com texto na caixa, antes de a busca aparecer (só esvazia a caixa)
      None               a tecla segue o caminho normal
    Ctrl precisa estar sozinho: no teclado ABNT2, AltGr chega como Ctrl+Alt, e AltGr+1/2/3 digitam ¹ ² ³ (e Ctrl+Shift
    é combinação de outros programas).
    #>
    param (
        [Parameter(Mandatory)][string]$Key,
        [bool]$Control = $false,
        [bool]$Alt = $false,
        [bool]$Shift = $false,
        [int]$PageCount = 0,
        [bool]$SearchActive = $false,
        [bool]$SearchHasText = $false,
        [bool]$PagesVisible = $false,
        [bool]$RunViewVisible = $false,
        [bool]$Running = $false,
        [bool]$PromptShown = $false,
        [bool]$PromptFilterVisible = $false
    )

    $none = [PSCustomObject]@{ Action = "None"; PageIndex = -1 }
    $plain = (-not $Control -and -not $Alt -and -not $Shift)
    $ctrlOnly = ($Control -and -not $Alt -and -not $Shift)

    if ($ctrlOnly -and $Key -ieq "F" -and $RunViewVisible -and $PromptShown -and $PromptFilterVisible) {
        return [PSCustomObject]@{ Action = "FocusPromptFilter"; PageIndex = -1 }
    }

    if ($ctrlOnly -and ($Key -ieq "K" -or $Key -ieq "F")) {
        return [PSCustomObject]@{ Action = "FocusSearch"; PageIndex = -1 }
    }

    if ($ctrlOnly -and $Key -match '^(D|NumPad)([0-9])$') {
        $number = [int]$Matches[2]
        $index = $(if ($number -eq 0) { 9 } else { $number - 1 })

        if ($index -lt $PageCount) {
            return [PSCustomObject]@{ Action = "OpenPage"; PageIndex = $index }
        }

        return $none
    }

    if ($plain -and $Key -eq "F5" -and $PagesVisible -and -not $SearchActive) {
        return [PSCustomObject]@{ Action = "Refresh"; PageIndex = -1 }
    }

    if ($plain -and $Key -eq "Escape") {
        # Esc volta um passo. Na tela de execução, só depois de a ação terminar (de volta aos resultados da busca, se a ação
        # saiu de lá): nunca interrompe uma ação nem uma pergunta na tela, nem a tira da frente. Fora dela, limpa a busca
        # e volta à página de onde ela começou; com texto na caixa e a busca ainda por aparecer, só esvazia a caixa.
        if ($RunViewVisible) {
            if (-not $Running -and -not $PromptShown) { return [PSCustomObject]@{ Action = "LeaveRun"; PageIndex = -1 } }

            return $none
        }

        if ($SearchActive) { return [PSCustomObject]@{ Action = "LeaveSearch"; PageIndex = -1 } }
        if ($SearchHasText) { return [PSCustomObject]@{ Action = "ClearSearch"; PageIndex = -1 } }
    }

    return $none
}


Export-ModuleMember -Function *
