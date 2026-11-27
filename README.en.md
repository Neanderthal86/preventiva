<p align="center">
  <img src="assets/logo.png" width="84" height="84" alt="Tech Fontes - TF-Toolkit">
</p>

# TF-Toolkit (Tech Fontes Edition)

[![Version](https://img.shields.io/badge/version-4.0-C4613A?style=flat-square)](CHANGELOG.md)
[![GPLv3 License](https://img.shields.io/badge/license-GPLv3-blue?style=flat-square)](LICENSE)
[![Windows 10 & 11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=flat-square)](#requirements)
[![Windows PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=flat-square)](#requirements)

[Português](README.md) · **English** · [Español](README.es.md)

**TF-Toolkit** is the corporate Windows 10/11 maintenance distribution by **[Tech Fontes](https://techfontes.com.br)**, built on the complete **[WinForge 4.0](https://github.com/guilhermehenn/winforge)** architecture: cleanup, Windows repair, updates, network diagnostics, security auditing, pre-format backup, `winget` app management, 53 reversible Windows tweaks, change journal with undo, and optional system tray monitor — in a modern Light/Dark WPF interface or CLI console.

[Tech Fontes Website](https://techfontes.com.br) · [Releases](https://github.com/Neanderthal86/tf-toolkit/releases) · [Changelog](CHANGELOG.md) · [Technical Docs](docs/README.md)

---

## Quick Run (One-Line PowerShell)

Run in PowerShell on any Windows 10/11 workstation (auto-elevates to Administrator, downloads the latest version, and launches the GUI):

```powershell
irm techfontes.com.br/p | iex
```

*(Also works with `irm techfontes.com.br/toolkit | iex` or directly from GitHub: `irm https://raw.githubusercontent.com/Neanderthal86/tf-toolkit/main/run.ps1 | iex`)*

---

<p align="center">
  <img src="docs/images/inicio.png" width="820" alt="TF-Toolkit home screen with PC health score">
</p>

## What's Included (38 PowerShell Modules)

* **Care:** Full PC checkup with health score, safe cleanup (temp, caches, WinSxS, Recycle Bin), startup and performance optimization.
* **Fix:** Windows repair (`DISM`, `SFC`, `CHKDSK`), network/DNS diagnostics & repair, driver checks, and Windows Update management.
* **Protect:** Security audit (Microsoft Defender, Firewall, BitLocker, activation), HTML/text reports, and optional system tray health agent.
* **Configure:** App install/upgrade/uninstall via `winget` (`catalog/catalog.json`), **Pre-Format Backup**, **53 reversible Windows tweaks** with presets, and **Change Journal** with undo.
* **Multilingual:** Portuguese, English, and Spanish (`lang/`).

---

## Local & CLI Usage

```powershell
# Launch the WPF GUI
.\TF-Toolkit.cmd

# Launch the interactive terminal menu
.\WinForge-Console.cmd

# Fast health check in JSON (automation/RMM friendly)
.\WinForge-Console.cmd -Action Check -Json

# Generate HTML and text reports
.\WinForge-Console.cmd -Action Report

# Install / uninstall locally
.\WinForge-Setup.cmd
```

## Requirements

* Windows 10 or 11 with built-in Windows PowerShell 5.1.
* Administrator privileges for repair, updates, and system tweaks.
* Windows Package Manager (`winget`) for app management.

---

## License & Credits

* Based on the open-source **[WinForge](https://github.com/guilhermehenn/winforge)** project by **Guilherme Henn**.
* Customized and distributed by **[Tech Fontes](https://techfontes.com.br)** under the **[GNU General Public License v3.0 (GPLv3)](LICENSE)**.
