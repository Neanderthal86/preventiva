function Install-PreventivaSoftware {
    param(
        [string[]]$AppIds
    )
    if (-not $AppIds -or $AppIds.Count -eq 0) { return }

    Write-PreventivaLog "Iniciando instalação de $($AppIds.Count) aplicativos via Winget..." -Secao "Software"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-PreventivaAlerta "Winget não encontrado nesta máquina. Não é possível instalar softwares automaticamente."
        return
    }

    foreach ($appId in $AppIds) {
        Write-PreventivaLog "Instalando pacote: $appId" -Secao "Software"
        try {
            $proc = Start-Process winget -ArgumentList "install --id `"$appId`" --exact --accept-package-agreements --accept-source-agreements --silent" -Wait -NoNewWindow -PassThru
            
            # 0 = Sucesso. Algumas vezes winget retorna códigos específicos se já estiver instalado, mas trataremos 0 como padrão absoluto de sucesso.
            if ($proc.ExitCode -eq 0) {
                Write-PreventivaLog "$appId instalado/atualizado com sucesso." -Secao "Software"
            } else {
                Write-PreventivaAlerta "Falha ao instalar $appId (Código: $($proc.ExitCode)). Talvez já esteja instalado ou falhou no download."
            }
        } catch {
            Write-PreventivaAlerta "Exceção ao chamar winget para $($appId): $_"
        }
    }
}

