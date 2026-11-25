# Tech Fontes — Preventiva Corporativa Windows

Conjunto de ferramentas em PowerShell para diagnóstico, manutenção preventiva, otimização, instalação de softwares (Winget) e geração de relatórios HTML/JSON em estações Windows.

---

## Execução Rápida (1 Linha no PowerShell)

Execute no PowerShell (eleva automaticamente para Administrador, baixa a versão mais recente da pasta `Dist/` e abre o Painel Visual):

```powershell
irm techfontes.com.br/p | iex
```

*(Também funciona com `irm techfontes.com.br/preventiva | iex` ou diretamente via GitHub: `irm https://raw.githubusercontent.com/Neanderthal86/preventiva/main/run.ps1 | iex`)*

---

## Estrutura de Pastas

```text
Tech Fontes - Preventiva/
├── Dist/                          # Pacote pronto para copiar/zipar para o cliente
│   ├── Rodar-Preventiva.bat       # Abre o Painel Visual WPF como Administrador
│   ├── Rodar-Utilitario.bat       # Abre o TechFontes-Utility (WinUtil) como Administrador
│   ├── Painel-Preventiva.ps1      # Interface gráfica (WPF) da Preventiva
│   ├── Invoke-Preventiva.ps1      # Orquestrador CLI modular
│   ├── Install-Agendamento.ps1    # Registra preventiva semanal (sexta às 18h, SYSTEM)
│   ├── TechFontes-Utility.ps1     # Utilitário avançado compilado (fork do WinUtil)
│   ├── Assets/logo.png            # Logo exibido no painel
│   ├── Config/settings.json       # Parâmetros gerais, Webhook e lista de softwares
│   └── Modules/                   # Módulos PowerShell (.psm1)
│       ├── SystemInventory.psm1
│       ├── Diagnostics.psm1
│       ├── Maintenance.psm1
│       ├── Optimization.psm1
│       ├── Software.psm1
│       └── Reporting.psm1
├── Dev/                           # Código-fonte e scripts de build (não enviar ao cliente)
│   ├── Build-Utility.ps1          # Sincroniza módulos, compila e publica em Dist/
│   └── winutil-main/              # Base customizada do Chris Titus WinUtil
├── Legado/                        # Versões antigas mantidas apenas para histórico
│   └── Preventiva-Corporativa-Windows-Completa.ps1
└── README.md
```

---

## Como Usar (Pasta `Dist/`)

Para levar a ferramenta a um cliente, copie ou compacte apenas a pasta **`Dist/`**.

### 1. Modo Visual (Recomendado)
* **Painel da Preventiva:** execute `Dist\Rodar-Preventiva.bat` (solicita elevação automática).
* **Utilitário Avançado (WinUtil Tech Fontes):** execute `Dist\Rodar-Utilitario.bat`.

### 2. Linha de Comando (CLI)
```powershell
# Auditoria somente leitura (não altera nada no sistema)
.\Dist\Invoke-Preventiva.ps1 -Mode Heavy -SubModo Diagnostico

# Execução completa nível Moderate com plano Alto Desempenho
.\Dist\Invoke-Preventiva.ps1 -Mode Moderate -SubModo Execucao -OptimizePower

# Execução Light instalando softwares via Winget
.\Dist\Invoke-Preventiva.ps1 -Mode Light -SubModo Execucao -SoftwareToInstall "Google.Chrome","7zip.7zip"
```

### 3. Agendamento Automático
Execute como Administrador na máquina do cliente:
```powershell
.\Dist\Install-Agendamento.ps1
```
Cria a tarefa `TechFontes-Preventiva-Semanal` (toda sexta-feira às 18:00, conta `SYSTEM`, silenciosa, modo `Light / Execucao`).

### 4. Relatórios e Logs
Salvos por padrão em `C:\ProgramData\Preventiva\` (configurável em `Dist\Config\settings.json`):
* `Relatorio_<Modo>_<SubModo>_<Data>.html` — Relatório visual Tech Fontes.
* `Relatorio_<Modo>_<SubModo>_<Data>.json` — Dados estruturados (enviados via `WebhookUrl`, se configurado).
* `Preventiva_*.log` e `Transcript_*.txt` — Logs detalhados da execução.

---

## Configuração (`Dist\Config\settings.json`)
* `TempAgeDays`, `MinFreeSpaceGB`, `EventLimit`, `LimitFileScanMB`, `LargeFolderThresholdMB`: limites de limpeza e alertas.
* `CriticalServices`: serviços monitorados/reiniciados automaticamente.
* `ReportSettings.WebhookUrl`: URL de destino para telemetria/alertas em JSON (`SendWebhookOnlyOnAlerts` controla se envia sempre ou apenas com alertas).
* `SoftwareList`: lista de aplicativos exibidos na aba *Softwares (Winget)* do painel.

---

## Como Recompilar o `TechFontes-Utility.ps1`
Sempre que editar os módulos em `Dist\Modules\` ou os tweaks em `Dev\winutil-main\config\tweaks.json`, execute:
```powershell
.\Dev\Build-Utility.ps1
```
O script sincroniza os módulos (removendo `Export-ModuleMember` automaticamente), compila com UTF-8 preservado e atualiza `Dist\TechFontes-Utility.ps1`.
