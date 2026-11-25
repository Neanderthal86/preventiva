function Set-PreventivaHighPerformance {
    Write-PreventivaLog "Configurando plano de energia para Alto Desempenho..." -Secao "Otimizacao"
    try {
        # High Performance GUID padrão no Windows
        $guid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        powercfg -setactive $guid
        Write-PreventivaLog "Plano de energia alterado com sucesso." -Secao "Otimizacao"
    } catch {
        Write-PreventivaAlerta "Falha ao definir plano de energia Alto Desempenho."
    }
}

