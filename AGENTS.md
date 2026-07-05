# windows-optimization

## Cursor Cloud specific instructions

### What this repo is
- This project is a set of **Windows 10 optimization scripts** (PowerShell + batch, with a Bash launcher). It is not a web app or a service — there is nothing that stays running.
- The `main` branch is currently an **empty placeholder** (only this file and `README.md`). The actual scripts live on the branch `cursor/windows10-optimizacion-script-bdf2`:
  - `Optimizar-Windows10.ps1` — main PowerShell optimizer (menu + `-Auto` / `-Deep` modes).
  - `Optimizar-Windows10.bat` / `Optimizar-Windows10-TODO-EN-UNO.bat` — self-elevating launchers (the "TODO-EN-UNO" one embeds the whole PowerShell script).
  - `optimizar-windows10.sh` — Git Bash/WSL launcher that just shells out to `powershell.exe`.

### Important runtime caveat (non-obvious)
- **The scripts cannot actually run their core functionality on this Linux Cloud VM.** They require Windows-only facilities: the registry, `DISM`, `SFC`, restore points, disk TRIM/defrag, and `powershell.exe` (the `.sh` exits immediately if `powershell.exe` is absent). Executing the optimizer is only meaningful on a real Windows 10 machine.
- Therefore, "development" in this environment means **editing and statically validating** the scripts, not executing them.

### Dev workflow on Linux (lint / validate)
There is **no package manager, lockfile, build system, test suite, or service** in this repo. Validation is static analysis only:
- Bash launcher: `shellcheck optimizar-windows10.sh`
- PowerShell parse-check: `pwsh -NoProfile -Command '$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "Optimizar-Windows10.ps1"),[ref]$t,[ref]$e)|Out-Null; "ParseErrors: $($e.Count)"'`
- PowerShell lint: `pwsh -NoProfile -Command 'Import-Module PSScriptAnalyzer; Invoke-ScriptAnalyzer -Path ./Optimizar-Windows10.ps1 -Severity Error,Warning'`

### Tooling
- `shellcheck`, PowerShell Core (`pwsh` 7.4.x), and the `PSScriptAnalyzer` module are used for the checks above. These are **system-level dev tools, not codebase dependencies**, so they are intentionally kept out of the startup update script.
- If they are missing on a fresh VM, install them manually:
  - `sudo apt-get update && sudo apt-get install -y shellcheck`
  - PowerShell: download the `.deb` from the PowerShell GitHub releases (e.g. `powershell_7.4.6-1.deb_amd64.deb`) and `sudo apt-get install -y ./<file>.deb`
  - `pwsh -NoProfile -Command 'Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AcceptLicense'`
