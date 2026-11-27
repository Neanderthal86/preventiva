# ============================================
# Optimization.psm1 - Tweaks Corporativos Reversiveis (Tech Fontes)
# Chaves de registro corporativas e GPOs oficiais Microsoft (100% reversiveis)
# ============================================

function Set-PreventivaRegistryEntries {
    param(
        [array]$Entries,
        [switch]$Undo
    )
    foreach ($e in $Entries) {
        try {
            $val = if ($Undo) { $e.Original } else { $e.Value }
            if ($val -eq "<RemoveEntry>") {
                if (Test-Path -LiteralPath $e.Path) {
                    Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -ErrorAction SilentlyContinue
                }
            } else {
                if (-not (Test-Path -LiteralPath $e.Path)) {
                    New-Item -Path $e.Path -Force | Out-Null
                }
                Set-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value $val -Type $e.Type -Force
            }
        } catch {
            Write-PreventivaLog "Aviso registro ($($e.Path)\$($e.Name)): $_" -Secao "Otimizacao"
        }
    }
}

function Set-PreventivaHighPerformance {
    param([switch]$Undo)
    if ($Undo) {
        Write-PreventivaLog "Restaurando plano de energia para Equilibrado..." -Secao "Otimizacao"
        try {
            powercfg -setactive "381b4222-f694-41f0-9685-ff5bb260df2e" | Out-Null
            Write-PreventivaLog "Plano de energia Equilibrado restaurado." -Secao "Otimizacao"
        } catch {
            Write-PreventivaAlerta "Falha ao restaurar plano de energia Equilibrado."
        }
    } else {
        Write-PreventivaLog "Configurando plano de energia para Alto Desempenho..." -Secao "Otimizacao"
        try {
            powercfg -setactive "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" | Out-Null
            Write-PreventivaLog "Plano de energia Alto Desempenho ativado com sucesso." -Secao "Otimizacao"
        } catch {
            Write-PreventivaAlerta "Falha ao definir plano de energia Alto Desempenho."
        }
    }
}

function Invoke-PreventivaTweaks {
    param(
        [string[]]$Tweaks,
        [switch]$Undo
    )

    if (-not $Tweaks -or $Tweaks.Count -eq 0) { return }
    $acao = if ($Undo) { "Desfazendo" } else { "Aplicando" }
    Write-PreventivaLog "$acao $($Tweaks.Count) tweak(s) de otimização..." -Secao "Otimizacao"

    $needsExplorerRestart = $false

    foreach ($tweak in $Tweaks) {
        switch ($tweak) {
            "HighPerformance" {
                Set-PreventivaHighPerformance -Undo:$Undo
            }

            "DisableTelemetry" {
                $entries = @(
                    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; Name = "AllowTelemetry"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name = "TailoredExperiencesWithDiagnosticDataEnabled"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"; Name = "HasAccepted"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Input\TIPC"; Name = "Enabled"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules"; Name = "NumberOfSIUFInPeriod"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                try {
                    if ($Undo) {
                        Set-Service -Name diagtrack -StartupType Automatic -ErrorAction SilentlyContinue
                        Set-Service -Name wermgr -StartupType Manual -ErrorAction SilentlyContinue
                        [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '', 'Machine')
                    } else {
                        Set-Service -Name diagtrack -StartupType Disabled -ErrorAction SilentlyContinue
                        Stop-Service -Name diagtrack -Force -ErrorAction SilentlyContinue
                        Set-Service -Name wermgr -StartupType Disabled -ErrorAction SilentlyContinue
                        [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
                    }
                } catch {}
                Write-PreventivaLog "Telemetria do Windows: $(if ($Undo) {'Restaurada'} else {'Desativada'})" -Secao "Otimizacao"
            }

            "DisableBGApps" {
                $entries = @(
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; Value = 1; Original = 0; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                Write-PreventivaLog "Apps em Segundo Plano: $(if ($Undo) {'Reativados'} else {'Desativados'})" -Secao "Otimizacao"
            }

            "VisualEffects" {
                $entries = @(
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"; Name = "VisualFXSetting"; Value = 3; Original = 1; Type = "DWord" },
                    @{ Path = "HKCU:\Control Panel\Desktop"; Name = "DragFullWindows"; Value = "0"; Original = "1"; Type = "String" },
                    @{ Path = "HKCU:\Control Panel\Desktop"; Name = "MenuShowDelay"; Value = "200"; Original = "400"; Type = "String" },
                    @{ Path = "HKCU:\Control Panel\Desktop\WindowMetrics"; Name = "MinAnimate"; Value = "0"; Original = "1"; Type = "String" },
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ListviewAlphaSelect"; Value = 0; Original = 1; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ListviewShadow"; Value = 0; Original = 1; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAnimations"; Value = 0; Original = 1; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Windows\DWM"; Name = "EnableAeroPeek"; Value = 0; Original = 1; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                $needsExplorerRestart = $true
                Write-PreventivaLog "Efeitos Visuais: $(if ($Undo) {'Padrão Windows restaurado'} else {'Otimizados para desempenho'})" -Secao "Otimizacao"
            }

            "DisableDeliveryOpt" {
                $entries = @(
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"; Name = "DODownloadMode"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                Write-PreventivaLog "Delivery Optimization (P2P Update): $(if ($Undo) {'Restaurado'} else {'Desativado'})" -Secao "Otimizacao"
            }

            "DisableHibernation" {
                $entries = @(
                    @{ Path = "HKLM:\System\CurrentControlSet\Control\Session Manager\Power"; Name = "HibernateEnabled"; Value = 0; Original = 1; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"; Name = "ShowHibernateOption"; Value = 0; Original = 1; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                try {
                    if ($Undo) { powercfg.exe /hibernate on | Out-Null }
                    else { powercfg.exe /hibernate off | Out-Null }
                } catch {}
                Write-PreventivaLog "Hibernação (hiberfil.sys): $(if ($Undo) {'Reativada'} else {'Desativada'})" -Secao "Otimizacao"
            }

            "DisableConsumerFeatures" {
                $entries = @(
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1; Original = "<RemoveEntry>"; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                Write-PreventivaLog "Consumer Features (Apps/Anúncios MS): $(if ($Undo) {'Restaurado'} else {'Bloqueado'})" -Secao "Otimizacao"
            }

            "DisableBingSearch" {
                $entries = @(
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Value = 0; Original = 1; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Value = 1; Original = "<RemoveEntry>"; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                $needsExplorerRestart = $true
                Write-PreventivaLog "Busca Bing no Menu Iniciar: $(if ($Undo) {'Reativada'} else {'Desativada'})" -Secao "Otimizacao"
            }

            "DisableActivityHistory" {
                $entries = @(
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "EnableActivityFeed"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "UploadUserActivities"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                Write-PreventivaLog "Histórico de Atividades: $(if ($Undo) {'Restaurado'} else {'Desativado'})" -Secao "Otimizacao"
            }

            "ClassicRightClick" {
                $clsid = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
                try {
                    if ($Undo) {
                        if (Test-Path -LiteralPath $clsid) {
                            Remove-Item -LiteralPath $clsid -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        New-Item -Path $clsid -Name "InprocServer32" -Value "" -Force | Out-Null
                    }
                    $needsExplorerRestart = $true
                    Write-PreventivaLog "Menu Botão Direito Clássico (Win11): $(if ($Undo) {'Restaurado padrão Win11'} else {'Ativado'})" -Secao "Otimizacao"
                } catch {
                    Write-PreventivaAlerta "Falha ao alterar Menu de Contexto Clássico: $_"
                }
            }

            "EndTaskTaskbar" {
                $entries = @(
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"; Name = "TaskbarEndTask"; Value = 1; Original = "<RemoveEntry>"; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                Write-PreventivaLog "Finalizar Tarefa na Barra de Tarefas: $(if ($Undo) {'Desativado'} else {'Ativado'})" -Secao "Otimizacao"
            }

            "ShowFileExtensions" {
                $entries = @(
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideFileExt"; Value = 0; Original = 1; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                $needsExplorerRestart = $true
                Write-PreventivaLog "Mostrar Extensões de Arquivos no Explorer: $(if ($Undo) {'Ocultas (padrão)'} else {'Visíveis'})" -Secao "Otimizacao"
            }

            "EdgeDebloat" {
                $entries = @(
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"; Name = "CreateDesktopShortcutDefault"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "PersonalizationReportingEnabled"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "ShowRecommendationsEnabled"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "HideFirstRunExperience"; Value = 1; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "UserFeedbackAllowed"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "EdgeCollectionsEnabled"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "EdgeShoppingAssistantEnabled"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "ShowMicrosoftRewards"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "DiagnosticData"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "DefaultBrowserSettingsCampaignEnabled"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                Write-PreventivaLog "Debloat Microsoft Edge (GPO): $(if ($Undo) {'Políticas removidas'} else {'Aplicado'})" -Secao "Otimizacao"
            }

            "DisableWidgets" {
                $entries = @(
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarDa"; Value = 0; Original = 1; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                $needsExplorerRestart = $true
                Write-PreventivaLog "Widgets / Notícias na Barra (GPO): $(if ($Undo) {'Reativados'} else {'Desativados'})" -Secao "Otimizacao"
            }

            "DisableCopilotAI" {
                $entries = @(
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Value = 1; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\WindowsNotepad"; Name = "DisableAIFeatures"; Value = 1; Original = "<RemoveEntry>"; Type = "DWord" },
                    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name = "DisableAIDataAnalysis"; Value = 1; Original = "<RemoveEntry>"; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                Write-PreventivaLog "Windows Copilot / AI (GPO): $(if ($Undo) {'Reativado'} else {'Desativado'})" -Secao "Otimizacao"
            }

            "EnableLongPaths" {
                $entries = @(
                    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"; Name = "LongPathsEnabled"; Value = 1; Original = 0; Type = "DWord" }
                )
                Set-PreventivaRegistryEntries -Entries $entries -Undo:$Undo
                Write-PreventivaLog "Caminhos Longos NTFS (>260 chars): $(if ($Undo) {'Desativado'} else {'Ativado'})" -Secao "Otimizacao"
            }
        }
    }

    if ($needsExplorerRestart) {
        try {
            Write-PreventivaLog "Reiniciando Windows Explorer para aplicar alterações visuais..." -Secao "Otimizacao"
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600
            if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
                Start-Process explorer.exe
            }
        } catch {}
    }
}

Export-ModuleMember -Function Set-PreventivaHighPerformance, Invoke-PreventivaTweaks
