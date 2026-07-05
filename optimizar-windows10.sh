#!/usr/bin/env bash
# ============================================================
#  Lanzador .sh para Git Bash / WSL en Windows 10
#  Ejecuta Optimizar-Windows10.ps1 en modo AUTOMATICO.
#
#  NOTA: En Windows lo mas comodo es el doble clic en
#        "Optimizar-Windows10.bat". Este .sh es para quienes
#        usan Git Bash o WSL.
#
#  Uso:
#     bash optimizar-windows10.sh          # modo automatico
#     bash optimizar-windows10.sh --deep   # incluye DISM + SFC
# ============================================================

set -euo pipefail

# Carpeta donde esta este script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS1_PATH="${SCRIPT_DIR}/Optimizar-Windows10.ps1"

if [ ! -f "${PS1_PATH}" ]; then
    echo "No se encontro Optimizar-Windows10.ps1 junto a este script."
    echo "Colocalo en la misma carpeta: ${SCRIPT_DIR}"
    exit 1
fi

# Localizar powershell.exe (Git Bash) o powershell.exe via interop (WSL)
if command -v powershell.exe >/dev/null 2>&1; then
    PS_EXE="powershell.exe"
elif command -v powershell >/dev/null 2>&1; then
    PS_EXE="powershell"
else
    echo "No se encontro powershell.exe."
    echo "Ejecuta este optimizador en Windows (Git Bash o WSL con interoperabilidad)."
    exit 1
fi

# Argumentos: -Auto siempre; -Deep si se pide (entrecomillados para PowerShell)
PS_ARGS="'-Auto'"
if [ "${1:-}" = "--deep" ] || [ "${1:-}" = "-Deep" ]; then
    PS_ARGS="'-Auto','-Deep'"
fi

# Convertir ruta a formato Windows si estamos en WSL
WIN_PS1="${PS1_PATH}"
if command -v wslpath >/dev/null 2>&1; then
    WIN_PS1="$(wslpath -w "${PS1_PATH}")"
fi

echo "============================================================"
echo "  Ejecutando optimizacion AUTOMATICA de Windows 10"
echo "  Se pediran permisos de Administrador."
echo "============================================================"

# Auto-elevar a Administrador y ejecutar en modo automatico
"${PS_EXE}" -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${WIN_PS1}',${PS_ARGS}"

echo "Proceso lanzado. Revisa la ventana de PowerShell (Administrador)."
echo "Se recomienda REINICIAR el equipo al terminar."
