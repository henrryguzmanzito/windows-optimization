# Optimización Windows 10

Script único en PowerShell para optimizar Windows 10 de forma segura y reversible.

## Uso rápido (automático, sin hacer nada)

La forma más cómoda en Windows: **doble clic en `Optimizar-Windows10.bat`**.

- Se auto-eleva a Administrador (aparece el aviso de UAC → pulsa **Sí**).
- Ejecuta todas las optimizaciones **seguras** solo, sin preguntar.
- Al terminar, recomienda reiniciar.

> Importante: `Optimizar-Windows10.bat` y `Optimizar-Windows10.ps1` deben estar en la **misma carpeta**.

Para incluir también la reparación profunda (DISM + SFC, más lenta), desde una consola:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Optimizar-Windows10.ps1" -Auto -Deep
```

### Alternativa Git Bash / WSL

```bash
bash optimizar-windows10.sh          # automático
bash optimizar-windows10.sh --deep   # incluye DISM + SFC
```

## Uso manual (menú interactivo)

1. Copia `Optimizar-Windows10.ps1` a tu PC con Windows 10.
2. Clic derecho en **PowerShell** → **Ejecutar como administrador**.
3. Ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Optimizar-Windows10.ps1"
```

## Modo automático: qué hace solo

En modo `-Auto` se ejecutan únicamente pasos seguros y reversibles:

1. Punto de restauración
2. Limpieza de temporales y papelera
3. Optimización de disco (TRIM en SSD / desfrag en HDD)
4. Efectos visuales → rendimiento
5. Limpieza de caché DNS (sin cambiar tus DNS)
6. Privacidad razonable (telemetría básica, ID de publicidad)

No desactiva servicios que requieren decisión manual, ni cambia DNS, ni toca Windows Update/Defender. Todo queda registrado en un log y con backups para revertir.

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
