function Get-PreventivaDiskHealth {
    param([int]$MinFreeSpaceGB)
    
    # 1. Espaco Livre
    try { 
        $SpaceBefore = [math]::Round((Get-PSDrive C).Free/1GB,2) 
        Write-PreventivaLog "Espaço livre atual: $SpaceBefore GB" -Secao "Disco"
        if ($SpaceBefore -lt $MinFreeSpaceGB) {
            Write-PreventivaAlerta "Espaço livre abaixo do mínimo recomendado ($MinFreeSpaceGB GB)"
        }
        
        $global:PreventivaEspacoAntes = $SpaceBefore
    } catch { }

    # 2. Saude do disco
    try {
        Get-PhysicalDisk | ForEach-Object {
            $linha = "Disco: $($_.FriendlyName) | Tipo: $($_.MediaType) | Saúde: $($_.HealthStatus)"
            Write-PreventivaLog $linha -Secao "Disco"
            if ($_.HealthStatus -ne "Healthy") { 
                Write-PreventivaAlerta "Disco $($_.FriendlyName) com saúde '$($_.HealthStatus)'" 
            }
        }
    } catch {}
}

function Get-PreventivaStartupAndDrivers {
    # Startup
    try {
        $StartupItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
        if ($StartupItems) {
            Write-PreventivaLog "Total de itens de inicialização: $($StartupItems.Count)" -Secao "Startup"
            $StartupAgrupado = $StartupItems | Group-Object -Property Name | Sort-Object Name
            foreach ($grupo in $StartupAgrupado) {
                if ($grupo.Count -gt 1) {
                    Write-PreventivaLog "$($grupo.Name) (aparece em $($grupo.Count) perfis)" -Secao "Startup"
                } else {
                    Write-PreventivaLog "$($grupo.Name)" -Secao "Startup"
                }
            }
            if ($StartupItems.Count -gt 12) {
                Write-PreventivaAlerta "Máquina com $($StartupItems.Count) itens na inicialização - candidato a revisão"
            }
        }
    } catch {}

    # Drivers
    try {
        $DriverIssues = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -notin @("OK","Unknown") }
        if ($DriverIssues) {
            foreach ($d in $DriverIssues) {
                Write-PreventivaLog "Driver com problema: $($d.FriendlyName) | Status: $($d.Status)" -Secao "Drivers"
                Write-PreventivaAlerta "Dispositivo '$($d.FriendlyName)' com status '$($d.Status)'"
            }
        } else {
            Write-PreventivaLog "Nenhum dispositivo com driver problemático encontrado" -Secao "Drivers"
        }
    } catch {}
}

function Test-PreventivaEvents {
    param([int]$EventLimit)

    # Detecção de BSOD (Event ID 41, Source Kernel-Power)
    try {
        $bsodEvents = Get-WinEvent -FilterHashtable @{LogName='System';Id=41} -MaxEvents 3 -ErrorAction SilentlyContinue
        if ($bsodEvents) {
            $recent = $bsodEvents | Select-Object -First 1
            Write-PreventivaAlerta "Eventos de BSOD/Queda de energia detectados. Último: $($recent.TimeCreated)"
        }
    } catch {}

    # Erros gerais do sistema
    try{
        $sysErrs = Get-WinEvent -FilterHashtable @{LogName='System';Level=2} -MaxEvents $EventLimit -ErrorAction SilentlyContinue
        foreach($e in $sysErrs) {
            Write-PreventivaLog "Erro Sist. | ID $($e.Id) | Fonte $($e.ProviderName)" -Secao "Integridade"
        }
    }catch{}
}

function Invoke-PreventivaScans {
    param(
        [bool]$RunVarreduraCompleta,
        [bool]$ExecutarAcoes,
        [int]$LimitFileScanMB,
        [int]$LargeFolderThresholdMB
    )
    
    Write-PreventivaLog "Iniciando varredura de espaço" -Secao "Varredura"
    $SubpastasUsuario = if ($ExecutarAcoes) {
        @("Downloads","Desktop","Documents","Pictures","Videos","AppData\Local")
    } else {
        @("Downloads","Desktop","Documents","Pictures","Videos")
    }

    $ResultadosPastas = @()
    function Get-TamanhoPasta([string]$Caminho) {
        try {
            $bytes = (Get-ChildItem -LiteralPath $Caminho -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if (-not $bytes) { return 0 }
            return $bytes
        } catch { return 0 }
    }

    try {
        $PerfisUsuario = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object {$_.LocalPath -like "C:\Users\*" -and !$_.Special}
        foreach ($perfil in $PerfisUsuario) {
            foreach ($sub in $SubpastasUsuario) {
                $caminho = Join-Path $perfil.LocalPath $sub
                if (Test-Path $caminho) {
                    $tamanho = Get-TamanhoPasta $caminho
                    if ($tamanho -gt ($LargeFolderThresholdMB * 1MB)) {
                        $ResultadosPastas += [PSCustomObject]@{ Caminho = $caminho; Bytes = $tamanho }
                    }
                }
            }
        }
    } catch {}

    if ($ExecutarAcoes) {
        foreach ($caminho in @("C:\Program Files","C:\Program Files (x86)","C:\ProgramData","C:\Windows\Installer")) {
            if (Test-Path $caminho) {
                $tamanho = Get-TamanhoPasta $caminho
                if ($tamanho -gt ($LargeFolderThresholdMB * 1MB)) {
                    $ResultadosPastas += [PSCustomObject]@{ Caminho = $caminho; Bytes = $tamanho }
                }
            }
        }
    }

    $TopPastas = $ResultadosPastas | Sort-Object Bytes -Descending | Select-Object -First 10
    foreach ($p in $TopPastas) {
        $gb = [math]::Round($p.Bytes/1GB,2)
        Write-PreventivaLog "$($p.Caminho) : $gb GB" -Secao "Varredura"
        if ($gb -gt 20) { Write-PreventivaAlerta "Pasta '$($p.Caminho)' ocupando $gb GB" }
    }

    if ($RunVarreduraCompleta) {
        try {
            $MaioresArquivos = Get-ChildItem "C:\" -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt ($LimitFileScanMB * 1MB) -and $_.FullName -notmatch "\\Windows\\WinSxS\\" } |
                Sort-Object Length -Descending | Select-Object -First 15

            foreach ($arq in $MaioresArquivos) {
                $gb = [math]::Round($arq.Length/1GB,2)
                Write-PreventivaLog "Arquivo: $($arq.FullName) ($gb GB)" -Secao "Varredura"
                if ($gb -gt 5) { Write-PreventivaAlerta "Arquivo único '$($arq.Name)' ocupando $gb GB" }
            }
        } catch {}
    }
}

function Get-PreventivaSecurity {
    param([bool]$RunDefenderScan)
    
    $AntivirusResumo = "Não verificado"
    $TemAntivirusTerceiro = $false
    
    try {
        $ProdutosAV = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop
        if ($ProdutosAV) {
            foreach ($av in $ProdutosAV) {
                $ehMicrosoft = $av.displayName -match "Windows Defender|Microsoft Defender"
                $tipo = if ($ehMicrosoft) { "Nativo" } else { "Terceiro" }
                Write-PreventivaLog "Antivírus: $($av.displayName) ($tipo)" -Secao "Seguranca"
                if (-not $ehMicrosoft) {
                    $TemAntivirusTerceiro = $true
                    $AntivirusResumo = "$($av.displayName) (terceiro)"
                }
            }
            if (-not $TemAntivirusTerceiro) { $AntivirusResumo = "Windows Defender (nativo)" }
        } else {
            Write-PreventivaAlerta "Nenhum antivírus registrado no Windows Security Center"
            $AntivirusResumo = "Nenhum detectado"
        }
    } catch {
        $AntivirusResumo = "Falha na detecção"
    }

    $global:PreventivaAVStatus = $AntivirusResumo

    # --- NOVA AUDITORIA DE SEGURANÇA ---
    
    # 1. Firewall
    try {
        $fw = Get-NetFirewallProfile -Name Domain,Private,Public | Where-Object Enabled -eq 1
        if (-not $fw) { Write-PreventivaAlerta "Firewall do Windows está DESATIVADO!" }
        else { Write-PreventivaLog "Firewall do Windows ativo em $($fw.Count) perfis" -Secao "Seguranca" }
    } catch { Write-PreventivaLog "Falha ao checar Firewall" -Secao "Seguranca" }

    # 2. RDP Exposto (Verifica se 3389 está ouvindo em 0.0.0.0, perigoso se sem VPN)
    try {
        $rdp = netstat -ano | Select-String "0.0.0.0:3389\s+LISTENING"
        if ($rdp) { Write-PreventivaAlerta "Porta RDP (3389) está aberta e escutando (Possível brecha)" }
    } catch { }

    # 3. BitLocker (Disco C)
    try {
        $bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
        if ($bl.VolumeStatus -eq "FullyDecrypted") {
            Write-PreventivaAlerta "BitLocker está DESATIVADO no disco C:"
        } elseif ($bl.VolumeStatus -eq "FullyEncrypted") {
            Write-PreventivaLog "BitLocker Ativo no disco C:" -Secao "Seguranca"
        }
    } catch { Write-PreventivaLog "Falha ao checar BitLocker (requer execução como Admin)" -Secao "Seguranca" }

    # 4. Ativação do Windows
    try {
        $license = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey is not NULL" -ErrorAction Stop | Select-Object -First 1
        if ($license) {
            if ($license.LicenseStatus -eq 1) {
                Write-PreventivaLog "Windows Ativado (Key: $($license.PartialProductKey))" -Secao "Seguranca"
            } else {
                Write-PreventivaAlerta "Windows NÃO está ativado! (Status: $($license.LicenseStatus))"
            }
        }
    } catch { Write-PreventivaLog "Falha ao checar Ativação do Windows" -Secao "Seguranca" }

    # --- FIM NOVA AUDITORIA ---

    if ($RunDefenderScan) {
        if (-not $TemAntivirusTerceiro) {
            Write-PreventivaLog "Iniciando Quick Scan do Defender" -Secao "Seguranca"
            try {
                Start-MpScan -ScanType QuickScan -ErrorAction Stop
                Write-PreventivaLog "Quick Scan concluído" -Secao "Seguranca"
                $Threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
                if ($Threats) {
                    foreach ($t in $Threats) { Write-PreventivaAlerta "Ameaça detectada: ID $($t.ThreatID)" }
                }
            } catch { Write-PreventivaLog "Falha ao rodar Defender Scan: $_" -Secao "Seguranca" }
        } else {
            Write-PreventivaLog "Scan do Defender ignorado (AV de terceiro ativo)" -Secao "Seguranca"
        }
    }
}

function Invoke-PreventivaIntegrity {
    param([bool]$RunDISM, [bool]$RunSFC)
    if($RunDISM){
        Write-PreventivaLog "Executando DISM /RestoreHealth" -Secao "Integridade"
        DISM /Online /Cleanup-Image /RestoreHealth
    }
    if($RunSFC){
        Write-PreventivaLog "Executando SFC /scannow" -Secao "Integridade"
        sfc /scannow
    }
}

