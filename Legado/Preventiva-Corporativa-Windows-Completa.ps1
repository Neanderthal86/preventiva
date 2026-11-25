
# ============================================
# TECH FONTES - PREVENTIVA CORPORATIVA WINDOWS
# ============================================
# MODOS (escopo/profundidade):
# Light    = Limpeza e verificacoes basicas + startup/drivers (leitura)
# Moderate = Light + Windows Update + Defender Quick Scan + SSD TRIM
# Heavy    = Moderate + DISM + SFC + WinSxS Cleanup + Restore Point
# Recovery = Heavy + Reset Windows Update + Rede
#
# SUBMODOS (o que realmente executa):
# Diagnostico = SO LEITURA. Nada e instalado, apagado ou alterado no sistema.
#               Ideal para rodar rapido em varias maquinas e decidir o que precisa de Execucao.
# Execucao    = Aplica de fato as acoes do nivel (Mode) selecionado. Comportamento completo.
#
# Todos os modos/submodos geram relatorio HTML final em C:\ProgramData\Preventiva\
# ============================================
# USO:
# .\Preventiva.ps1 -Mode Heavy -SubModo Diagnostico   (rapido, so relatorio)
# .\Preventiva.ps1 -Mode Heavy -SubModo Execucao       (aplica tudo do nivel Heavy)
# ============================================

param(
    [ValidateSet("Light","Moderate","Heavy","Recovery")]
    [string]$Mode = "Light",

    [ValidateSet("Diagnostico","Execucao")]
    [string]$SubModo = "Execucao"
)

# ---------------- CONFIG -------------------
$TempAgeDays    = 3
$EventLimit     = 20
$MinFreeSpaceGB = 15
$ExecutarAcoes  = ($SubModo -eq "Execucao")

switch ($Mode) {
    "Light"    { $RunWU=$false; $RunDISM=$false; $RunSFC=$false; $RunRecovery=$false; $RunDefender=$false; $RunTrim=$false; $RunWinSxS=$false; $RunRestorePoint=$false; $RunVarredura=$true;  $RunVarreduraCompleta=$false }
    "Moderate" { $RunWU=$true;  $RunDISM=$false; $RunSFC=$false; $RunRecovery=$false; $RunDefender=$true;  $RunTrim=$true;  $RunWinSxS=$false; $RunRestorePoint=$false; $RunVarredura=$true;  $RunVarreduraCompleta=$false }
    "Heavy"    { $RunWU=$true;  $RunDISM=$true;  $RunSFC=$true;  $RunRecovery=$false; $RunDefender=$true;  $RunTrim=$true;  $RunWinSxS=$true;  $RunRestorePoint=$true;  $RunVarredura=$true;  $RunVarreduraCompleta=$true }
    "Recovery" { $RunWU=$true;  $RunDISM=$true;  $RunSFC=$true;  $RunRecovery=$true;  $RunDefender=$true;  $RunTrim=$true;  $RunWinSxS=$true;  $RunRestorePoint=$true;  $RunVarredura=$true;  $RunVarreduraCompleta=$true }
    default    { $RunWU=$false; $RunDISM=$false; $RunSFC=$false; $RunRecovery=$false; $RunDefender=$false; $RunTrim=$false; $RunWinSxS=$false; $RunRestorePoint=$false; $RunVarredura=$true;  $RunVarreduraCompleta=$false }
}

# ---------------- SUBCLASSE: DIAGNOSTICO trava tudo que e lento ou destrutivo -------------------
# Em Diagnostico: sem instalar update, sem Quick Scan, sem TRIM, sem DISM/SFC, sem WinSxS,
# sem restore point, sem varredura completa de arquivos e sem apagar nada. So relatorio.
$RunWU                = $RunWU                -and $ExecutarAcoes
$RunTrim               = $RunTrim              -and $ExecutarAcoes
$RunDISM               = $RunDISM              -and $ExecutarAcoes
$RunSFC                = $RunSFC               -and $ExecutarAcoes
$RunWinSxS              = $RunWinSxS           -and $ExecutarAcoes
$RunRestorePoint        = $RunRestorePoint     -and $ExecutarAcoes
$RunRecovery            = $RunRecovery         -and $ExecutarAcoes
$RunVarreduraCompleta   = $RunVarreduraCompleta -and $ExecutarAcoes
$RunScanDefenderReal    = $RunDefender         -and $ExecutarAcoes   # deteccao de AV continua rodando sempre que $RunDefender=true
$RunLimpezaReal         = $ExecutarAcoes                              # limpeza sempre calcula/estima; so apaga em Execucao

$BaseLogDir = "$env:ProgramData\Preventiva"
New-Item -ItemType Directory -Path $BaseLogDir -Force | Out-Null

$Data           = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile        = Join-Path $BaseLogDir "Preventiva_$Mode`_$SubModo`_$Data.log"
$TranscriptFile = Join-Path $BaseLogDir "Transcript_$Mode`_$SubModo`_$Data.txt"
$ReportFile     = Join-Path $BaseLogDir "Relatorio_$Mode`_$SubModo`_$Data.html"

Start-Transcript -Path $TranscriptFile -Force

# Estrutura que alimenta o relatorio HTML final
$Report = [ordered]@{
    Inventario   = @()
    Disco        = @()
    Servicos     = @()
    Limpeza      = @()
    Startup      = @()
    Drivers      = @()
    Seguranca    = @()
    Performance  = @()
    Varredura    = @()
    WindowsUpdate= @()
    Integridade  = @()
    Recovery     = @()
    Alertas      = @()
}

function Write-Log {
    param([string]$Mensagem, [string]$Secao = $null)
    $Linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Mensagem"
    $Linha | Tee-Object -FilePath $LogFile -Append
    if ($Secao -and $Report.Contains($Secao)) {
        $Report[$Secao] += $Mensagem
    }
}

function Write-Alerta {
    param([string]$Mensagem)
    Write-Log "[ALERTA] $Mensagem" "Alertas"
}

function Get-FreeSpaceGB {
    try { [math]::Round((Get-PSDrive C).Free/1GB,2) }
    catch { 0 }
}

function Test-PendingReboot {
    $CBS = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $WU  = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    return ($CBS -or $WU)
}

Write-Log "======================================"
Write-Log "INICIO PREVENTIVA - TECH FONTES"
Write-Log "Modo: $Mode | SubModo: $SubModo"
Write-Log "======================================"

# ---------------- INVENTARIO -------------------
try {
    $OS   = Get-CimInstance Win32_OperatingSystem
    $CS   = Get-CimInstance Win32_ComputerSystem
    $BIOS = Get-CimInstance Win32_BIOS
    Write-Log "Hostname: $env:COMPUTERNAME" "Inventario"
    Write-Log "Windows: $($OS.Caption)" "Inventario"
    Write-Log "Build: $($OS.BuildNumber)" "Inventario"
    Write-Log "Fabricante: $($CS.Manufacturer)" "Inventario"
    Write-Log "Modelo: $($CS.Model)" "Inventario"
    Write-Log "Serial: $($BIOS.SerialNumber)" "Inventario"
    Write-Log "RAM GB: $([math]::Round($CS.TotalPhysicalMemory/1GB,2))" "Inventario"
} catch {}

# ---------------- DISCO -------------------
$SpaceBefore = Get-FreeSpaceGB
Write-Log "Espaco livre inicial: $SpaceBefore GB" "Disco"
if ($SpaceBefore -lt $MinFreeSpaceGB) {
    Write-Alerta "Espaco livre abaixo do minimo recomendado ($MinFreeSpaceGB GB)"
}

try {
    Get-PhysicalDisk | ForEach-Object {
        $linha = "Disco: $($_.FriendlyName) | Tipo: $($_.MediaType) | Saude: $($_.HealthStatus)"
        Write-Log $linha "Disco"
        if ($_.HealthStatus -ne "Healthy") { Write-Alerta "Disco $($_.FriendlyName) com saude '$($_.HealthStatus)'" }
    }
} catch {}

# ---------------- SERVICOS CRITICOS -------------------
foreach($svc in @("BITS","wuauserv","Spooler","CryptSvc","LanmanWorkstation")){
    try{
        $s = Get-Service $svc
        if($s.Status -ne "Running" -and $RunLimpezaReal){ Start-Service $svc }
        Write-Log "Servico $svc : $((Get-Service $svc).Status)" "Servicos"
    } catch {}
}

# ---------------- LIMPEZA TEMPORARIOS -------------------
$Paths = @("$env:windir\Temp","C:\Windows\System32\config\systemprofile\AppData\Local\Temp")
Get-CimInstance Win32_UserProfile | Where-Object {$_.LocalPath -like "C:\Users\*" -and !$_.Special} | ForEach-Object{
    $Paths += "$($_.LocalPath)\AppData\Local\Temp"
}

$CutDate = (Get-Date).AddDays(-$TempAgeDays)
$TotalArquivosLimpos = 0
$TotalBytesLimpos = 0
$AcaoLimpeza = if ($RunLimpezaReal) { "removidos" } else { "elegiveis p/ remocao (Diagnostico - nada foi apagado)" }

foreach($P in $Paths | Select-Object -Unique){
    if(Test-Path $P){
        try{
            $ArquivosAntigos = Get-ChildItem $P -Recurse -Force -File -ErrorAction SilentlyContinue |
                Where-Object {$_.LastWriteTime -lt $CutDate}

            $Qtd = ($ArquivosAntigos | Measure-Object).Count
            if ($Qtd -gt 0) {
                $Bytes = ($ArquivosAntigos | Measure-Object -Property Length -Sum).Sum
                if ($RunLimpezaReal) { $ArquivosAntigos | Remove-Item -Force -ErrorAction SilentlyContinue }

                $TotalArquivosLimpos += $Qtd
                $TotalBytesLimpos    += $Bytes

                $MB = [math]::Round($Bytes/1MB,1)
                Write-Log "$P : $Qtd arquivos $AcaoLimpeza ($MB MB)" "Limpeza"
            }
        } catch {}
    }
}

if ($TotalArquivosLimpos -gt 0) {
    $TotalMB = [math]::Round($TotalBytesLimpos/1MB,1)
    $TotalGB = [math]::Round($TotalBytesLimpos/1GB,2)
    Write-Log "Total: $TotalArquivosLimpos arquivos $AcaoLimpeza, $TotalMB MB ($TotalGB GB)" "Limpeza"
} else {
    Write-Log "Nenhum arquivo temporario elegivel para limpeza" "Limpeza"
}

try{
    $LixeiraQtd = 0
    $Shell = New-Object -ComObject Shell.Application
    $Lixeira = $Shell.Namespace(10)
    if ($Lixeira) { $LixeiraQtd = $Lixeira.Items().Count }

    if ($RunLimpezaReal) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        if ($LixeiraQtd -gt 0) {
            Write-Log "Lixeira esvaziada: $LixeiraQtd itens removidos" "Limpeza"
        } else {
            Write-Log "Lixeira ja estava vazia" "Limpeza"
        }
    } else {
        Write-Log "Lixeira: $LixeiraQtd itens (Diagnostico - nao foi esvaziada)" "Limpeza"
    }
}catch{
    Write-Log "Falha ao checar/limpar lixeira: $_" "Limpeza"
}

try{
    ipconfig /flushdns | Out-Null
    Write-Log "Flush DNS executado" "Limpeza"
}catch{}

try{
    Get-WinEvent -FilterHashtable @{LogName='System';Level=2} -MaxEvents $EventLimit |
    ForEach-Object {
        Write-Log "Erro Sistema | ID $($_.Id) | Fonte $($_.ProviderName)" "Limpeza"
    }
}catch{}

# ---------------- STARTUP (todos os modos - leitura) -------------------
try {
    $StartupItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
    if ($StartupItems) {
        Write-Log "Total de itens de inicializacao: $($StartupItems.Count)" "Startup"

        # Agrupa por nome - o mesmo item costuma aparecer varias vezes (uma por perfil/SID de usuario)
        $StartupAgrupado = $StartupItems | Group-Object -Property Name | Sort-Object Name
        foreach ($grupo in $StartupAgrupado) {
            if ($grupo.Count -gt 1) {
                Write-Log "$($grupo.Name) (aparece em $($grupo.Count) perfis)" "Startup"
            } else {
                Write-Log "$($grupo.Name)" "Startup"
            }
        }

        if ($StartupItems.Count -gt 12) {
            Write-Alerta "Maquina com $($StartupItems.Count) itens na inicializacao - candidato a revisao de boot"
        }
    }
} catch { Write-Log "Falha ao ler itens de startup: $_" "Startup" }

# ---------------- DRIVERS (todos os modos - leitura) -------------------
try {
    $DriverIssues = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -notin @("OK","Unknown") }
    if ($DriverIssues) {
        foreach ($d in $DriverIssues) {
            Write-Log "Driver com problema: $($d.FriendlyName) | Status: $($d.Status) | Classe: $($d.Class)" "Drivers"
            Write-Alerta "Dispositivo '$($d.FriendlyName)' com status '$($d.Status)'"
        }
    } else {
        Write-Log "Nenhum dispositivo com driver problematico encontrado" "Drivers"
    }
} catch { Write-Log "Falha ao checar drivers: $_" "Drivers" }

# ---------------- VARREDURA DE ESPACO EM DISCO -------------------
function Get-TamanhoPasta {
    param([string]$Caminho)
    try {
        $bytes = (Get-ChildItem -LiteralPath $Caminho -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if (-not $bytes) { return 0 }
        return $bytes
    } catch { return 0 }
}

if ($RunVarredura) {
    Write-Log "Iniciando varredura de espaco em disco" "Varredura"

    # Em Diagnostico, pulamos AppData\Local e as pastas de sistema (Program Files/ProgramData/Installer)
    # porque sao as arvores mais pesadas pra escanear e o objetivo aqui e velocidade.
    # Essas entram na varredura completa quando SubModo=Execucao em Heavy/Recovery.
    $SubpastasUsuario = if ($ExecutarAcoes) {
        @("Downloads","Desktop","Documents","Pictures","Videos","AppData\Local")
    } else {
        @("Downloads","Desktop","Documents","Pictures","Videos")
    }

    # 1) Maiores pastas dentro de cada perfil de usuario
    $ResultadosPastas = @()
    try {
        $PerfisUsuario = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object {$_.LocalPath -like "C:\Users\*" -and !$_.Special}
        foreach ($perfil in $PerfisUsuario) {
            foreach ($sub in $SubpastasUsuario) {
                $caminho = Join-Path $perfil.LocalPath $sub
                if (Test-Path $caminho) {
                    $tamanho = Get-TamanhoPasta -Caminho $caminho
                    if ($tamanho -gt 100MB) {
                        $ResultadosPastas += [PSCustomObject]@{ Caminho = $caminho; Bytes = $tamanho }
                    }
                }
            }
        }
    } catch {}

    # 2) Pastas do sistema que costumam acumular espaco (so na Execucao - arvores grandes)
    if ($ExecutarAcoes) {
        foreach ($caminho in @("C:\Program Files","C:\Program Files (x86)","C:\ProgramData","C:\Windows\Installer")) {
            if (Test-Path $caminho) {
                $tamanho = Get-TamanhoPasta -Caminho $caminho
                if ($tamanho -gt 100MB) {
                    $ResultadosPastas += [PSCustomObject]@{ Caminho = $caminho; Bytes = $tamanho }
                }
            }
        }
    } else {
        Write-Log "Pastas de sistema (Program Files/ProgramData/Installer) e AppData\Local nao escaneadas no Diagnostico (arvores grandes - use Execucao)" "Varredura"
    }

    $TopPastas = $ResultadosPastas | Sort-Object Bytes -Descending | Select-Object -First 10
    foreach ($p in $TopPastas) {
        $gb = [math]::Round($p.Bytes/1GB,2)
        Write-Log "$($p.Caminho) : $gb GB" "Varredura"
        if ($gb -gt 20) {
            Write-Alerta "Pasta '$($p.Caminho)' ocupando $gb GB - candidata a revisao com o usuario/cliente"
        }
    }

    # 3) Maiores arquivos individuais - varredura completa do C: (apenas Heavy/Recovery, mais demorado)
    if ($RunVarreduraCompleta) {
        try {
            $LimiteBytes = 200MB
            $MaioresArquivos = Get-ChildItem "C:\" -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt $LimiteBytes -and $_.FullName -notmatch "\\Windows\\WinSxS\\" } |
                Sort-Object Length -Descending |
                Select-Object -First 15

            foreach ($arq in $MaioresArquivos) {
                $gb = [math]::Round($arq.Length/1GB,2)
                Write-Log "Arquivo: $($arq.FullName) ($gb GB)" "Varredura"
                if ($gb -gt 5) {
                    Write-Alerta "Arquivo unico '$($arq.Name)' ocupando $gb GB"
                }
            }
            if (-not $MaioresArquivos) {
                Write-Log "Nenhum arquivo individual acima de 200 MB encontrado" "Varredura"
            }
        } catch { Write-Log "Falha na varredura completa de arquivos: $_" "Varredura" }
    } else {
        Write-Log "Varredura completa de arquivos individuais roda apenas nos modos Heavy/Recovery (evita alongar o Light/Moderate)" "Varredura"
    }

    Write-Log "Varredura de espaco concluida" "Varredura"
}

# ---------------- WINDOWS UPDATE -------------------
if($RunWU){
    try{
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if(!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)){
            Install-PackageProvider -Name NuGet -Force | Out-Null
        }

        try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted } catch {}

        if(!(Get-Module -ListAvailable PSWindowsUpdate)){
            Install-Module PSWindowsUpdate -Force -AllowClobber -Scope AllUsers -Confirm:$false
        }

        Import-Module PSWindowsUpdate -Force

        $Updates = Get-WindowsUpdate
        if($Updates){
            Write-Log "Updates encontrados: $($Updates.Count)" "WindowsUpdate"
            Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false
        } else {
            Write-Log "Nenhum update pendente" "WindowsUpdate"
        }
    }catch{
        Write-Log "Falha Windows Update: $_" "WindowsUpdate"
        Write-Alerta "Falha ao processar Windows Update"
    }
}

# ---------------- SEGURANCA: DETECCAO DE ANTIVIRUS + SCAN -------------------
$AntivirusResumo = "Nao verificado"
$TemAntivirusTerceiro = $false
$TemAntivirusAtivo = $false

if ($RunDefender) {
    # Consulta o Windows Security Center - enxerga QUALQUER antivirus registrado no Windows,
    # nao so o Defender (Norton, Kaspersky, Avast, ESET, McAfee, etc.)
    try {
        $ProdutosAV = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop

        if ($ProdutosAV) {
            foreach ($av in $ProdutosAV) {
                # Decodificacao heuristica do productState (padrao usado pela industria,
                # pode variar levemente entre fabricantes)
                $hex = "{0:x6}" -f [int]$av.productState
                $flagAtivo = $hex.Substring(2,2)
                $flagDefinicao = $hex.Substring(4,2)

                $statusAtivo = if ($flagAtivo -in @("10","11","01")) { "Ativo" } else { "Inativo" }
                $statusDefinicao = if ($flagDefinicao -eq "00") { "Atualizado" } else { "Pode estar desatualizado" }

                $ehMicrosoft = $av.displayName -match "Windows Defender|Microsoft Defender"
                $tipo = if ($ehMicrosoft) { "Microsoft Defender" } else { "Terceiro" }

                Write-Log "Antivirus detectado: $($av.displayName) | Tipo: $tipo | Status: $statusAtivo | Definicoes: $statusDefinicao" "Seguranca"

                if (-not $ehMicrosoft) {
                    $TemAntivirusTerceiro = $true
                    $AntivirusResumo = "$($av.displayName) (terceiro)"
                }
                if ($statusAtivo -eq "Ativo") { $TemAntivirusAtivo = $true }
                if ($statusAtivo -ne "Ativo") {
                    Write-Alerta "Antivirus '$($av.displayName)' aparenta estar INATIVO"
                }
                if ($statusDefinicao -ne "Atualizado") {
                    Write-Alerta "Antivirus '$($av.displayName)' com definicoes possivelmente desatualizadas"
                }
            }

            if (-not $TemAntivirusTerceiro) {
                $AntivirusResumo = "Windows Defender (nativo)"
            }
        } else {
            Write-Alerta "Nenhum antivirus registrado no Windows Security Center"
            $AntivirusResumo = "Nenhum detectado"
        }
    } catch {
        Write-Log "Falha ao consultar SecurityCenter2: $_" "Seguranca"
        $AntivirusResumo = "Falha na deteccao"
    }

    # Quick Scan do Defender - so tenta rodar se o Defender for o motor ativo E o SubModo for Execucao.
    # Em Diagnostico, so a deteccao acima roda (rapida); o scan em si (lento) fica de fora.
    try {
        if (-not $RunScanDefenderReal) {
            if (-not $ExecutarAcoes) {
                Write-Log "Quick Scan nao executado (modo Diagnostico - somente deteccao)" "Seguranca"
            } elseif ($TemAntivirusTerceiro) {
                Write-Log "Antivirus de terceiro ativo ($AntivirusResumo) - Defender provavelmente em modo passivo, Quick Scan nao sera forcado" "Seguranca"
            }
        } else {
            Write-Log "Iniciando Quick Scan do Windows Defender" "Seguranca"
            Start-MpScan -ScanType QuickScan -ErrorAction Stop
            Write-Log "Quick Scan concluido" "Seguranca"

            $Threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
            if ($Threats) {
                foreach ($t in $Threats) {
                    Write-Alerta "Ameaca detectada: ID $($t.ThreatID) em $($t.InitialDetectionTime)"
                }
            }
        }
    } catch {
        Write-Log "Falha ao executar Quick Scan: $_" "Seguranca"
    }
}

# ---------------- PERFORMANCE: SSD TRIM -------------------
if ($RunTrim) {
    try {
        $Volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -eq "NTFS" }
        foreach ($vol in $Volumes) {
            try {
                $physicalDisk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq (Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction SilentlyContinue).DiskNumber }
                if ($physicalDisk.MediaType -eq "SSD") {
                    Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction SilentlyContinue
                    Write-Log "TRIM executado no volume $($vol.DriveLetter): (SSD)" "Performance"
                } else {
                    Write-Log "Volume $($vol.DriveLetter): e HDD - defrag nao executado automaticamente (recomenda-se agendamento fora do horario comercial)" "Performance"
                }
            } catch { Write-Log "Falha ao otimizar volume $($vol.DriveLetter): $_" "Performance" }
        }
    } catch { Write-Log "Falha geral no TRIM/otimizacao de disco: $_" "Performance" }
}

# ---------------- RESTORE POINT (antes de DISM/SFC/Recovery) -------------------
if ($RunRestorePoint) {
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "TechFontes_Preventiva_$Mode`_$Data" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "Ponto de restauracao criado com sucesso" "Integridade"
    } catch {
        Write-Log "Falha ao criar ponto de restauracao (pode estar limitado por politica/frequencia do Windows): $_" "Integridade"
    }
}

# ---------------- DISM / SFC -------------------
if($RunDISM){
    Write-Log "Executando DISM /RestoreHealth" "Integridade"
    DISM /Online /Cleanup-Image /RestoreHealth
}

if($RunSFC){
    Write-Log "Executando SFC /scannow" "Integridade"
    sfc /scannow
}

# ---------------- WINSXS CLEANUP -------------------
if ($RunWinSxS) {
    try {
        Write-Log "Executando limpeza de componentes WinSxS" "Performance"
        DISM /Online /Cleanup-Image /StartComponentCleanup
        Write-Log "Limpeza WinSxS concluida" "Performance"
    } catch { Write-Log "Falha na limpeza WinSxS: $_" "Performance" }
}

# ---------------- RECOVERY -------------------
if($RunRecovery){
    Write-Log "Recovery iniciado" "Recovery"

    try{
        Stop-Service wuauserv -Force
        Stop-Service bits -Force

        if(Test-Path "C:\Windows\SoftwareDistribution"){
            Rename-Item "C:\Windows\SoftwareDistribution" "SoftwareDistribution.old.$Data" -Force
        }

        Start-Service wuauserv
        Start-Service bits
    }catch{}

    netsh winsock reset
    netsh int ip reset

    Write-Log "Recovery concluido" "Recovery"
}

$SpaceAfter = Get-FreeSpaceGB
$PendingRebootFlag = Test-PendingReboot

Write-Log "Pending Reboot: $PendingRebootFlag" "Integridade"
Write-Log "Espaco livre final: $SpaceAfter GB" "Disco"
Write-Log "FINALIZADO"

Stop-Transcript

# ============================================
# RELATORIO HTML - IDENTIDADE TECH FONTES
# ============================================
function New-HtmlReport {
    param($ReportData, $OutFile, $AntivirusTexto, $PendingReboot, $EspacoAntes, $EspacoDepois)

    $secaoConfig = [ordered]@{
        Inventario    = @{ Titulo = "Inventario da Maquina";     Icone = "&#128421;" }
        Disco         = @{ Titulo = "Disco e Armazenamento";     Icone = "&#128190;" }
        Servicos      = @{ Titulo = "Servicos Criticos";         Icone = "&#9881;"   }
        Limpeza       = @{ Titulo = "Limpeza e Manutencao";      Icone = "&#129529;" }
        Startup       = @{ Titulo = "Itens de Inicializacao";    Icone = "&#9203;"   }
        Drivers       = @{ Titulo = "Drivers e Dispositivos";    Icone = "&#128268;" }
        Seguranca     = @{ Titulo = "Seguranca (Antivirus)";     Icone = "&#128737;" }
        Performance   = @{ Titulo = "Performance (SSD/WinSxS)";  Icone = "&#9889;"   }
        Varredura     = @{ Titulo = "Varredura de Espaco";       Icone = "&#128269;" }
        WindowsUpdate = @{ Titulo = "Windows Update";            Icone = "&#128260;" }
        Integridade   = @{ Titulo = "Integridade do Sistema";    Icone = "&#10003;"  }
        Recovery      = @{ Titulo = "Recovery / Emergencia";     Icone = "&#128680;" }
    }

    $BadgeSubModoTexto = if ($ExecutarAcoes) { "Execucao Completa" } else { "Diagnostico (somente leitura)" }
    $BadgeSubModoCor   = if ($ExecutarAcoes) { "" } else { "info" }
    $BannerDiagnostico = ""
    if (-not $ExecutarAcoes) {
        $BannerDiagnostico = "<div class='alertas info'><h2>&#128269; Modo Diagnostico</h2><p>Esta execucao so leu e analisou o sistema - nenhum arquivo foi apagado, nenhum update instalado e nenhuma configuracao alterada. Os valores de limpeza/atualizacoes abaixo sao estimativas do que seria feito em uma Execucao completa.</p></div>"
    }

    # ---------- Cards de resumo (KPIs) ----------
    $qtdAlertas = $ReportData.Alertas.Count
    $statusGeral = if ($qtdAlertas -eq 0) { "Sistema OK" } else { "Requer Atencao" }
    $statusCor   = if ($qtdAlertas -eq 0) { "ok" } else { "alerta" }
    $rebootTexto = if ($PendingReboot) { "Pendente" } else { "Nao necessario" }
    $rebootCor   = if ($PendingReboot) { "alerta" } else { "ok" }
    $avCor       = if ($AntivirusTexto -match "terceiro") { "info" } elseif ($AntivirusTexto -match "Nenhum|Falha") { "alerta" } else { "ok" }

    $cardsHtml = @"
    <div class="cards">
      <div class="card $statusCor">
        <div class="card-label">Status Geral</div>
        <div class="card-value">$statusGeral</div>
      </div>
      <div class="card">
        <div class="card-label">Espaco em Disco</div>
        <div class="card-value">$EspacoDepois GB</div>
        <div class="card-sub">antes: $EspacoAntes GB</div>
      </div>
      <div class="card $avCor">
        <div class="card-label">Antivirus</div>
        <div class="card-value-sm">$AntivirusTexto</div>
      </div>
      <div class="card $rebootCor">
        <div class="card-label">Reinicializacao</div>
        <div class="card-value-sm">$rebootTexto</div>
      </div>
    </div>
"@

    $alertasHtml = ""
    if ($qtdAlertas -gt 0) {
        $itens = ($ReportData.Alertas | ForEach-Object { "<li>$_</li>" }) -join "`n"
        $alertasHtml = "<div class='alertas'><h2>&#9888; Pontos de Atencao ($qtdAlertas)</h2><ul>$itens</ul></div>"
    } else {
        $alertasHtml = "<div class='alertas ok'><h2>&#9989; Pontos de Atencao</h2><p>Nenhum alerta identificado nesta execucao.</p></div>"
    }

    $secoesHtml = ""
    foreach ($key in $secaoConfig.Keys) {
        $linhas = $ReportData[$key]
        if ($linhas -and $linhas.Count -gt 0) {
            $cfg = $secaoConfig[$key]
            $itens = ($linhas | ForEach-Object { "<li>$_</li>" }) -join "`n"
            $secoesHtml += "<div class='secao'><h2><span class='icone'>$($cfg.Icone)</span>$($cfg.Titulo)</h2><ul>$itens</ul></div>`n"
        }
    }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Relatorio de Preventiva - Tech Fontes</title>
<style>
  * { box-sizing:border-box; }
  body {
    background:#1a1a1f;
    background-image: radial-gradient(circle at 20% 0%, rgba(61,82,112,0.15), transparent 40%),
                       radial-gradient(circle at 80% 10%, rgba(196,97,58,0.10), transparent 40%);
    color:#e8e8ea; font-family:'Segoe UI',Arial,sans-serif; margin:0; padding:0 0 60px 0;
  }
  .container { max-width:980px; margin:0 auto; padding:0 24px; }
  .topbar { background:#111114; border-bottom:1px solid #2a2a30; padding:18px 24px; margin-bottom:32px; }
  .topbar-inner { max-width:980px; margin:0 auto; display:flex; align-items:center; justify-content:space-between; }
  .logo { font-style:italic; font-weight:800; font-size:20px; letter-spacing:0.5px; color:#ffffff; }
  .logo .accent { color:#C4613A; }
  .topbar .tagline { font-size:11px; color:#6a6a72; text-transform:uppercase; letter-spacing:1px; }

  .header { padding-top:8px; margin-bottom:28px; }
  .header h1 { font-style:italic; font-weight:700; font-size:24px; margin:0 0 10px 0; color:#ffffff; }
  .header .meta { color:#9a9aa2; font-size:13px; line-height:1.8; }
  .header .meta b { color:#d5d5d9; font-weight:600; }
  .badge { display:inline-block; background:#3D5270; color:#fff; padding:5px 16px; border-radius:20px; font-size:12px; font-weight:700; letter-spacing:0.5px; text-transform:uppercase; margin-top:8px; margin-right:8px; }
  .badge.info { background:#5a7ba8; }

  .cards { display:grid; grid-template-columns:repeat(4, 1fr); gap:14px; margin-bottom:28px; }
  .card { background:#212127; border:1px solid #2c2c33; border-radius:10px; padding:16px 18px; border-top:3px solid #3D5270; }
  .card.ok { border-top-color:#4a7a5c; }
  .card.alerta { border-top-color:#C4613A; }
  .card.info { border-top-color:#5a7ba8; }
  .card-label { font-size:11px; text-transform:uppercase; letter-spacing:0.5px; color:#8a8a92; margin-bottom:8px; }
  .card-value { font-size:22px; font-weight:700; color:#ffffff; }
  .card-value-sm { font-size:14px; font-weight:600; color:#ffffff; line-height:1.3; }
  .card-sub { font-size:11px; color:#6a6a72; margin-top:4px; }

  .alertas { background:#2b1f1a; border:1px solid #4a3226; border-radius:10px; padding:18px 22px; margin-bottom:24px; }
  .alertas.ok { border-color:#26332c; background:#1a2420; }
  .alertas.info { border-color:#2c3a4a; background:#1a2430; }
  .alertas.info h2 { color:#7fa8d9; }
  .alertas.info p { margin:0; font-size:13px; color:#b8c9dc; }
  .alertas h2 { color:#e0a184; font-size:15px; margin:0 0 12px 0; font-style:italic; font-weight:700; }
  .alertas.ok h2 { color:#7fb894; }
  .alertas ul { margin:0; padding-left:20px; font-size:13px; color:#f0d5c8; line-height:1.8; }
  .alertas.ok p { margin:0; font-size:13px; color:#a8c9b4; }

  .grid { display:grid; grid-template-columns:1fr 1fr; gap:16px; }
  .secao { background:#212127; border:1px solid #2c2c33; border-radius:10px; padding:18px 22px; margin-bottom:0; }
  .secao h2 { font-size:14px; color:#ffffff; margin:0 0 12px 0; font-style:italic; font-weight:700; display:flex; align-items:center; gap:8px; border-bottom:1px solid #2c2c33; padding-bottom:10px; }
  .secao .icone { font-style:normal; }
  .secao ul { margin:0; padding-left:18px; font-size:12.5px; line-height:1.7; color:#c5c5cc; }
  .secao li { margin-bottom:2px; }

  .footer { margin-top:40px; padding-top:20px; border-top:1px solid #2a2a30; color:#5a5a62; font-size:11px; text-align:center; }
  .footer .marca { color:#C4613A; font-weight:700; }

  @media (max-width: 700px) {
    .cards { grid-template-columns:1fr 1fr; }
    .grid { grid-template-columns:1fr; }
  }
</style>
</head>
<body>
  <div class="topbar">
    <div class="topbar-inner">
      <div class="logo">Tech<span class="accent">Fontes</span></div>
      <div class="tagline">Preventiva Corporativa</div>
    </div>
  </div>

  <div class="container">
    <div class="header">
      <h1>Relatorio de Manutencao Preventiva</h1>
      <div class="meta">
        <b>Host:</b> $env:COMPUTERNAME &nbsp;&nbsp;|&nbsp;&nbsp;
        <b>Data:</b> $Data &nbsp;&nbsp;|&nbsp;&nbsp;
        <b>Windows:</b> $env:OS
      </div>
      <div class="badge">Modo: $Mode</div>
      <div class="badge $BadgeSubModoCor">$BadgeSubModoTexto</div>
    </div>

    $BannerDiagnostico
    $cardsHtml
    $alertasHtml

    <div class="grid">
      $secoesHtml
    </div>

    <div class="footer">
      Gerado automaticamente pela rotina de Preventiva Corporativa &middot; <span class="marca">Tech Fontes</span> &middot; suporte@techfontes.com.br
    </div>
  </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutFile -Encoding UTF8
}

try {
    New-HtmlReport -ReportData $Report -OutFile $ReportFile `
        -AntivirusTexto $AntivirusResumo -PendingReboot $PendingRebootFlag `
        -EspacoAntes $SpaceBefore -EspacoDepois $SpaceAfter
    Write-Host "Relatorio HTML gerado em: $ReportFile"
} catch {
    Write-Host "Falha ao gerar relatorio HTML: $_"
}
