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

function Update-PreventivaAllSoftware {
    Write-PreventivaLog "Iniciando atualização em massa de aplicativos via Winget (winget upgrade --all)..." -Secao "Software"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-PreventivaAlerta "Winget não encontrado nesta máquina. Não é possível atualizar aplicativos."
        return
    }

    try {
        $proc = Start-Process winget -ArgumentList "upgrade --all --silent --accept-package-agreements --accept-source-agreements --include-unknown" -Wait -NoNewWindow -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-PreventivaLog "Atualização em massa (Winget) concluída com sucesso." -Secao "Software"
        } else {
            Write-PreventivaLog "Atualização em massa (Winget) finalizada com código $($proc.ExitCode) (alguns apps podem não suportar atualização silenciosa)." -Secao "Software"
        }
    } catch {
        Write-PreventivaAlerta "Falha ao executar atualização em massa via Winget: $_"
    }
}

Export-ModuleMember -Function Install-PreventivaSoftware, Update-PreventivaAllSoftware
