# Optimización Windows 10

Script único en PowerShell para optimizar Windows 10 de forma segura y reversible.

## Uso

1. Copia `Optimizar-Windows10.ps1` a tu PC con Windows 10.
2. Clic derecho en **PowerShell** → **Ejecutar como administrador**.
3. Ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Optimizar-Windows10.ps1"
```

## Qué incluye

- Punto de restauración
- Limpieza de temporales y papelera
- DISM + SFC
- Optimización de disco (SSD TRIM / HDD defrag)
- Programas de inicio
- Servicios seguros (sin tocar Update ni Defender)
- Efectos visuales, energía, red, privacidad
- Rutina de mantenimiento y mitos a evitar

Los backups de servicios, DNS y efectos visuales se guardan en `%USERPROFILE%\Optimizar-Windows10_Backup`.
