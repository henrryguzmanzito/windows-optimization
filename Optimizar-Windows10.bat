@echo off
REM ============================================================
REM  Lanzador automatico de Optimizar-Windows10.ps1
REM  Doble clic para ejecutar TODO sin hacer nada manual.
REM  Se auto-eleva a Administrador y corre en modo automatico.
REM ============================================================

setlocal
set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%Optimizar-Windows10.ps1"

REM Comprobar que el .ps1 existe junto a este .bat
if not exist "%PS1%" (
    echo No se encontro "Optimizar-Windows10.ps1" en esta carpeta:
    echo   %SCRIPT_DIR%
    echo Coloca el .bat y el .ps1 en la MISMA carpeta.
    pause
    exit /b 1
)

REM Comprobar permisos de administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permisos de Administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================
echo   Ejecutando optimizacion AUTOMATICA de Windows 10
echo   No cierres esta ventana hasta que termine.
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Auto

echo.
echo ============================================================
echo   Proceso terminado. Revisa los mensajes de arriba.
echo   Se recomienda REINICIAR el equipo.
echo ============================================================
pause
endlocal
