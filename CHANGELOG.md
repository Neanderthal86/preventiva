# Changelog

Todas as mudanças relevantes do **TF-Toolkit** são documentadas neste arquivo.

## [3.0] — 2026-11-27
### Arquitetura & Limpeza
* **Nova estrutura de repositório limpa:** raiz organizada em `assets/`, `config/`, `gui/`, `modules/`, `tools/`, `docs/` e `.github/`.
* **Separação completa do XAML:** interface WPF movida para `gui/MainWindow.xaml` (UTF-8 limpo) e lógica isolada em `TF-Toolkit.ps1`.
* **100% autoral Tech Fontes:** removido o fork legado do WinUtil (`Dev/winutil-main/` e `TechFontes-Utility.ps1`), reduzindo o repositório de ~300 para ~25 arquivos e o download do `run.ps1` para **~65 KB**.
* **Governança & Release:** adicionados `LICENSE` (MIT), `CHANGELOG.md`, `.gitattributes`, `.editorconfig`, `.github/` (templates de Issue e `SECURITY.md`) e `tools/New-ReleasePackage.ps1` (gera `.zip` + `SHA-256`).

## [2.0] — 2026-11-26
### Novos Recursos
* **Aba `Rede & Suporte`:** diagnóstico ao vivo (IP, Gateway, DNS, MAC, IP Público, Latência), troca de DNS em 1 clique (`Cloudflare`, `Google`, `Quad9`, `DHCP`) e ações rápidas (Flush DNS, Renovar IP, Reiniciar Spooler + limpar fila de impressão).
* **Temas `Auto` / `Claro` / `Escuro`** em tempo real no painel WPF e no relatório HTML executivo (com modo PDF/Impressão e logo Base64 embutido).
* **16 Tweaks Corporativos 100% Reversíveis** (`Aplicar Tweaks` e `Desfazer`) com preset *Corporativo Seguro*.
* **Atualização em massa (`winget upgrade --all`)** na aba *Softwares* + botão dedicado *Instalar Selecionados*.
* **Índice de Saúde (`0–100`)** calculado automaticamente no relatório HTML e exportado no JSON.
* **Perfis de Pós-Formatação** configuráveis em `config/settings.json` (*Desktop Escritório* e *Notebook Corporativo*).
* **Runner em 1 linha** (`irm techfontes.com.br/p | iex`) com banner ASCII `TF`.

## [1.0] — 2026-07-29
* Refatoração inicial do script monolítico para arquitetura modular em PowerShell (`.psm1`), painel WPF inicial, agendamento semanal (`SYSTEM`) e relatório HTML/JSON.
