<p align="center">
  <img src="assets/logo.png" width="84" height="84" alt="Tech Fontes - TF-Toolkit">
</p>

# TF-Toolkit (Tech Fontes Edition)

[![Versão](https://img.shields.io/badge/vers%C3%A3o-4.0-C4613A?style=flat-square)](CHANGELOG.md)
[![Licença GPLv3](https://img.shields.io/badge/licen%C3%A7a-GPLv3-blue?style=flat-square)](LICENSE)
[![Windows 10 e 11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=flat-square)](#requisitos)
[![Windows PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=flat-square)](#requisitos)

**Português** · [English](README.en.md) · [Español](README.es.md)

**TF-Toolkit** é a distribuição corporativa da **[Tech Fontes](https://techfontes.com.br)** baseada na arquitetura completa do **[WinForge 4.0](https://github.com/guilhermehenn/winforge)**: limpeza, reparo do Windows, atualizações, rede, segurança, backup pré-formatação, gerenciamento de programas via `winget`, 53 ajustes reversíveis do Windows, histórico de mudanças e monitor na bandeja — tudo num único painel WPF moderno (temas Claro e Escuro) ou via console.

[Site Tech Fontes](https://techfontes.com.br) · [Releases](https://github.com/Neanderthal86/tf-toolkit/releases) · [O que mudou](CHANGELOG.md) · [Documentação Técnica](docs/README.md)

---

## Execução Rápida (1 Linha no PowerShell)

Execute no PowerShell em qualquer estação Windows 10/11 (eleva automaticamente para Administrador, baixa a versão mais recente e abre o painel):

```powershell
irm techfontes.com.br/p | iex
```

*(Também funciona com `irm techfontes.com.br/toolkit | iex` ou diretamente via GitHub: `irm https://raw.githubusercontent.com/Neanderthal86/tf-toolkit/main/run.ps1 | iex`)*

---

<p align="center">
  <img src="docs/images/inicio.png" width="820" alt="Tela inicial do TF-Toolkit com nota de saúde do PC">
</p>

## O que o TF-Toolkit inclui (38 Módulos)

* **Otimização:** Checkup completo com nota de saúde, limpeza segura (temporários, caches, WinSxS, Lixeira), otimização de inicialização e performance.
* **Ferramentas:** Reparo do Windows (`DISM`, `SFC`, `CHKDSK`), diagnóstico completo com **Relatório Técnico em PDF (para analista)** em padrão editorial corporativo (com cabeçalho/rodapé fixos, paginação, Service Tag, KPIs e recomendações automáticas), além de correção de rede/DNS e drivers.
* **Segurança:** Auditoria de segurança (Microsoft Defender, Firewall, BitLocker, ativação), atualizações do Windows/apps e monitor opcional na bandeja com alertas proativos.
* **Sistema:** Instalação/atualização/desinstalação de apps via `winget` (`catalog/catalog.json`), **Backup antes de formatar**, **53 ajustes reversíveis do Windows** com perfis prontos, **Histórico de Mudanças (Journal)** com desfazer e menu lateral recolhível.
* **Três idiomas:** Português, Inglês e Espanhol (`lang/`).

---

## Execução Local e Linha de Comando

```powershell
# Abrir a interface gráfica (WPF)
.\TF-Toolkit.cmd

# Abrir o menu no terminal
.\TF-Toolkit-Console.cmd

# Verificação rápida em JSON (ideal para automação/RMM)
.\TF-Toolkit-Console.cmd -Action Check -Json

# Gerar relatório HTML e texto
.\TF-Toolkit-Console.cmd -Action Report

# Instalar/desinstalar na máquina
.\TF-Toolkit-Setup.cmd
```

## Requisitos

* Windows 10 ou 11 com Windows PowerShell 5.1 (nativo do sistema).
* Privilégios de Administrador para ações de reparo, atualizações e ajustes do sistema.
* App Installer (`winget`) para gestão de aplicativos.

---

## Licença & Créditos

* Baseado no projeto open-source **[WinForge](https://github.com/guilhermehenn/winforge)** de **Guilherme Henn**.
* Customizado, mantido e distribuído pela **[Tech Fontes](https://techfontes.com.br)** sob a licença **[GNU General Public License v3.0 (GPLv3)](LICENSE)**.
