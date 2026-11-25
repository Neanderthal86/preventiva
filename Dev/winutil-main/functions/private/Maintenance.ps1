function Invoke-PreventivaMaintenance {
    param (
        [bool]$ExecutarAcoes,
        [int]$TempAgeDays,
        [array]$CriticalServices,
        [bool]$RunWU,
        [bool]$RunTrim,
        [bool]$RunWinSxS,
        [bool]$RunRestorePoint,
        [bool]$RunRecovery
    )

    # 1. Servicos Criticos
    foreach($svc in $CriticalServices){
        try{
            $s = Get-Service $svc
            if($s.Status -ne "Running" -and $ExecutarAcoes){ Start-Service $svc }
            Write-PreventivaLog "Serviço $svc : $((Get-Service $svc).Status)" -Secao "Servicos"
        } catch {
            Write-PreventivaLog "Serviço $svc não encontrado ou erro." -Secao "Servicos"
        }
    }

    # 2. Limpeza Temporarios
    $Paths = @("$env:windir\Temp","C:\Windows\System32\config\systemprofile\AppData\Local\Temp")
    Get-CimInstance Win32_UserProfile | Where-Object {$_.LocalPath -like "C:\Users\*" -and !$_.Special} | ForEach-Object{
        $Paths += "$($_.LocalPath)\AppData\Local\Temp"
    }

    $CutDate = (Get-Date).AddDays(-$TempAgeDays)
    $TotalArquivosLimpos = 0
    $TotalBytesLimpos = 0
    $AcaoLimpeza = if ($ExecutarAcoes) { "removidos" } else { "elegíveis p/ remoção (Diagnóstico - nada foi apagado)" }

    foreach($P in $Paths | Select-Object -Unique){
        if(Test-Path $P){
            try{
                $ArquivosAntigos = Get-ChildItem $P -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Where-Object {$_.LastWriteTime -lt $CutDate}

                $Qtd = ($ArquivosAntigos | Measure-Object).Count
                if ($Qtd -gt 0) {
                    $Bytes = ($ArquivosAntigos | Measure-Object -Property Length -Sum).Sum
                    if ($ExecutarAcoes) { $ArquivosAntigos | Remove-Item -Force -ErrorAction SilentlyContinue }

                    $TotalArquivosLimpos += $Qtd
                    $TotalBytesLimpos    += $Bytes

                    $MB = [math]::Round($Bytes/1MB,1)
                    Write-PreventivaLog "$P : $Qtd arquivos $AcaoLimpeza ($MB MB)" -Secao "Limpeza"
                }
            } catch {}
        }
    }

    if ($TotalArquivosLimpos -gt 0) {
        $TotalMB = [math]::Round($TotalBytesLimpos/1MB,1)
        $TotalGB = [math]::Round($TotalBytesLimpos/1GB,2)
        Write-PreventivaLog "Total: $TotalArquivosLimpos arquivos $AcaoLimpeza, $TotalMB MB ($TotalGB GB)" -Secao "Limpeza"
    } else {
        Write-PreventivaLog "Nenhum arquivo temporário elegível para limpeza" -Secao "Limpeza"
    }

    # Lixeira
    try{
        $LixeiraQtd = 0
        $Shell = New-Object -ComObject Shell.Application
        $Lixeira = $Shell.Namespace(10)
        if ($Lixeira) { $LixeiraQtd = $Lixeira.Items().Count }

        if ($ExecutarAcoes) {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            if ($LixeiraQtd -gt 0) {
                Write-PreventivaLog "Lixeira esvaziada: $LixeiraQtd itens removidos" -Secao "Limpeza"
            } else {
                Write-PreventivaLog "Lixeira já estava vazia" -Secao "Limpeza"
            }
        } else {
            Write-PreventivaLog "Lixeira: $LixeiraQtd itens (Diagnóstico - não foi esvaziada)" -Secao "Limpeza"
        }
    }catch{
        Write-PreventivaLog "Falha ao checar/limpar lixeira: $_" -Secao "Limpeza"
    }

    # DNS Flush
    try{
        if ($ExecutarAcoes) {
            ipconfig /flushdns | Out-Null
            Write-PreventivaLog "Flush DNS executado" -Secao "Limpeza"
        }
    }catch{}

    # TRIM
    if ($RunTrim -and $ExecutarAcoes) {
        try {
            $Volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -eq "NTFS" }
            foreach ($vol in $Volumes) {
                try {
                    $physicalDisk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq (Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction SilentlyContinue).DiskNumber }
                    if ($physicalDisk.MediaType -eq "SSD") {
                        Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction SilentlyContinue
                        Write-PreventivaLog "TRIM executado no volume $($vol.DriveLetter): (SSD)" -Secao "Performance"
                    } else {
                        Write-PreventivaLog "Volume $($vol.DriveLetter): é HDD - defrag não executado automaticamente." -Secao "Performance"
                    }
                } catch { Write-PreventivaLog "Falha ao otimizar volume $($vol.DriveLetter): $_" -Secao "Performance" }
            }
        } catch { Write-PreventivaLog "Falha geral no TRIM: $_" -Secao "Performance" }
    }

    # WinSxS
    if ($RunWinSxS -and $ExecutarAcoes) {
        try {
            Write-PreventivaLog "Executando limpeza de componentes WinSxS" -Secao "Performance"
            DISM /Online /Cleanup-Image /StartComponentCleanup
            Write-PreventivaLog "Limpeza WinSxS concluída" -Secao "Performance"
        } catch { Write-PreventivaLog "Falha na limpeza WinSxS: $_" -Secao "Performance" }
    }

    # Windows Update
    if($RunWU -and $ExecutarAcoes){
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
                Write-PreventivaLog "Updates encontrados: $($Updates.Count)" -Secao "WindowsUpdate"
                Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false
                Write-PreventivaLog "Updates instalados" -Secao "WindowsUpdate"
            } else {
                Write-PreventivaLog "Nenhum update pendente" -Secao "WindowsUpdate"
            }
        }catch{
            Write-PreventivaLog "Falha Windows Update: $_" -Secao "WindowsUpdate"
            Write-PreventivaAlerta "Falha ao processar Windows Update"
        }
    }

    # Ponto de Restauracao
    if ($RunRestorePoint -and $ExecutarAcoes) {
        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "TechFontes_Preventiva_$(Get-Date -Format 'yyyy-MM-dd')" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
            Write-PreventivaLog "Ponto de restauração criado com sucesso" -Secao "Integridade"
        } catch {
            Write-PreventivaLog "Falha ao criar ponto de restauração: $_" -Secao "Integridade"
        }
    }

    # Recovery
    if($RunRecovery -and $ExecutarAcoes){
        Write-PreventivaLog "Recovery iniciado (Modo Emergência)" -Secao "Recovery"
        try{
            Stop-Service wuauserv -Force
            Stop-Service bits -Force
            if(Test-Path "C:\Windows\SoftwareDistribution"){
                Rename-Item "C:\Windows\SoftwareDistribution" "SoftwareDistribution.old.$(Get-Date -Format 'yyyyMMddHHmmss')" -Force
            }
            Start-Service wuauserv
            Start-Service bits
            netsh winsock reset
            netsh int ip reset
            Write-PreventivaLog "Recovery concluído" -Secao "Recovery"
        }catch{
            Write-PreventivaLog "Falha no Recovery: $_" -Secao "Recovery"
        }
    }
}

