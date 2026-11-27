function Get-PreventivaInventory {
    try {
        $OS   = Get-CimInstance Win32_OperatingSystem
        $CS   = Get-CimInstance Win32_ComputerSystem
        $BIOS = Get-CimInstance Win32_BIOS
        
        $RAMGB = [math]::Round($CS.TotalPhysicalMemory/1GB,2)
        
        Write-PreventivaLog "Hostname: $env:COMPUTERNAME" -Secao "Inventario"
        Write-PreventivaLog "Windows: $($OS.Caption)" -Secao "Inventario"
        Write-PreventivaLog "Build: $($OS.BuildNumber)" -Secao "Inventario"
        Write-PreventivaLog "Fabricante: $($CS.Manufacturer)" -Secao "Inventario"
        Write-PreventivaLog "Modelo: $($CS.Model)" -Secao "Inventario"
        Write-PreventivaLog "Serial: $($BIOS.SerialNumber)" -Secao "Inventario"
        Write-PreventivaLog "RAM GB: $RAMGB" -Secao "Inventario"
    } catch {
        Write-PreventivaLog "Falha ao coletar inventário: $_" -Secao "Inventario"
    }
}

function Get-PreventivaBatteryHealth {
    try {
        # Utiliza WMI (root\wmi) para pegar DesignCapacity e FullChargeCapacity
        $fullCap = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue
        $designCap = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
        
        if ($fullCap -and $designCap) {
            $f = $fullCap.FullChargedCapacity
            $d = $designCap.DesignedCapacity
            if ($d -gt 0) {
                $health = [math]::Round(($f / $d) * 100, 2)
                Write-PreventivaLog "Saúde da Bateria (Estimada): $health%" -Secao "Inventario"
                if ($health -lt 70) {
                    Write-PreventivaAlerta "Bateria com saúde abaixo de 70% ($health%). Recomendada a troca."
                }
            }
        } else {
            # Se for desktop não tem bateria na maioria das vezes, então omitimos o log pra não poluir, ou testamos:
            $isLaptop = (Get-CimInstance Win32_ComputerSystem).PCSystemType -eq 2
            if ($isLaptop) {
                 Write-PreventivaLog "Bateria: Dados de degradação não disponíveis via WMI" -Secao "Inventario"
            }
        }
    } catch {}
}

function Test-PreventivaNetwork {
    Write-PreventivaLog "Testando latência de internet (8.8.8.8)" -Secao "Inventario"
    try {
        $ping = Test-Connection -ComputerName 8.8.8.8 -Count 2 -ErrorAction SilentlyContinue
        if ($ping) {
            $avgLatency = ($ping | Measure-Object -Property ResponseTime -Average).Average
            Write-PreventivaLog "Conectividade Internet: OK (Latência média: $([math]::Round($avgLatency,2)) ms)" -Secao "Inventario"
            if ($avgLatency -gt 200) {
                Write-PreventivaAlerta "Latência de internet alta ($([math]::Round($avgLatency,2)) ms)"
            }
        } else {
            Write-PreventivaAlerta "Teste de Ping para 8.8.8.8 falhou. Sem acesso externo?"
        }
    } catch {
        Write-PreventivaLog "Falha ao testar rede: $_" -Secao "Inventario"
    }
}

Export-ModuleMember -Function Get-PreventivaInventory, Get-PreventivaBatteryHealth, Test-PreventivaNetwork
