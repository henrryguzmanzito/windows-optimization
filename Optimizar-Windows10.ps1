#Requires -Version 5.1
<#
.SYNOPSIS
    Optimización segura y reversible de Windows 10 en un solo archivo.

.DESCRIPTION
    Ejecutar como Administrador:
        powershell -ExecutionPolicy Bypass -File ".\Optimizar-Windows10.ps1"

    Menú interactivo con todas las áreas de optimización ordenadas de lo más
    seguro a lo más avanzado. No desactiva Windows Update ni Windows Defender.

.NOTES
    Autor   : Guía de optimización Windows 10
    Versión : 1.0
    SO      : Windows 10

.PARAMETER Auto
    Ejecuta automáticamente todas las optimizaciones SEGURAS sin preguntar
    ni mostrar el menú. Ideal para lanzarlo desde el .bat con doble clic.
    No incluye pasos muy lentos (DISM/SFC) salvo que se use también -Deep.

.PARAMETER Deep
    Junto con -Auto, incluye además DISM + SFC (puede tardar 20-45 min).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ".\Optimizar-Windows10.ps1" -Auto
#>

param(
    [switch]$Auto,
    [switch]$Deep
)

# =============================================================================
# CONFIGURACIÓN GLOBAL
# =============================================================================

$ErrorActionPreference = 'Continue'
$Script:AutoMode = [bool]$Auto
$Script:LogFile = Join-Path $env:TEMP "Optimizar-Windows10_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Script:BackupDir = Join-Path $env:USERPROFILE "Optimizar-Windows10_Backup"

# =============================================================================
# UTILIDADES
# =============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8

    switch ($Level) {
        'OK'   { Write-Host $Message -ForegroundColor Green }
        'WARN' { Write-Host $Message -ForegroundColor Yellow }
        'ERROR'{ Write-Host $Message -ForegroundColor Red }
        'STEP' { Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
        default { Write-Host $Message }
    }
}

function Test-IsAdmin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
    if (-not (Test-IsAdmin)) {
        Write-Log "Este paso requiere permisos de Administrador." 'ERROR'
        Write-Log "Cierra y vuelve a abrir PowerShell como Administrador." 'WARN'
        return $false
    }
    return $true
}

function Confirm-Action {
    param(
        [string]$Message,
        [switch]$DefaultNo
    )
    # En modo automático se aceptan solo las acciones seguras (las que NO son DefaultNo).
    if ($Script:AutoMode) {
        if ($DefaultNo) {
            Write-Log "[AUTO] Omitido (requiere confirmación manual): $Message" 'INFO'
            return $false
        }
        Write-Log "[AUTO] Sí: $Message" 'INFO'
        return $true
    }
    if ($DefaultNo) {
        $r = Read-Host "$Message [s/N]"
        return ($r -match '^(s|si|sí|y|yes)$')
    }
    $r = Read-Host "$Message [S/n]"
    return ($r -notmatch '^(n|no)$')
}

function Pause-Continue {
    if ($Script:AutoMode) { return }
    Read-Host "`nPulsa Enter para continuar"
}

function Ensure-BackupDir {
    if (-not (Test-Path $Script:BackupDir)) {
        New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null
    }
}

function Get-DiskType {
    param([string]$DriveLetter = 'C')
    try {
        $partition = Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
        $diskNumber = $partition.DiskNumber
        $physical = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $diskNumber }
        if (-not $physical) {
            $physical = Get-PhysicalDisk | Select-Object -First 1
        }
        if (-not $physical) { return 'Desconocido' }

        switch ($physical.MediaType) {
            'SSD' { return 'SSD' }
            'HDD' { return 'HDD' }
            'Unspecified' {
                if ($physical.SpindleSpeed -eq 0) { return 'SSD' }
                return 'HDD'
            }
            default { return 'Desconocido' }
        }
    }
    catch {
        return 'Desconocido'
    }
}

function Get-SystemProfile {
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $ramGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $diskType = Get-DiskType -DriveLetter 'C'
    $isLaptop = $cs.PCSystemType -in 2, 3, 4, 9, 10, 11, 12  # portátil / notebook / handheld

    [PSCustomObject]@{
        Hostname  = $env:COMPUTERNAME
        RAM_GB    = $ramGB
        DiskType  = $diskType
        IsLaptop  = $isLaptop
        OS        = $os.Caption
        Build     = $os.BuildNumber
    }
}

function Show-SystemInfo {
    $info = Get-SystemProfile
    Write-Log "Sistema detectado:" 'STEP'
    Write-Host "  Equipo   : $($info.Hostname)"
    Write-Host "  Windows  : $($info.OS) (Build $($info.Build))"
    Write-Host "  RAM      : $($info.RAM_GB) GB"
    Write-Host "  Disco C: : $($info.DiskType)"
    Write-Host "  Tipo PC  : $(if ($info.IsLaptop) { 'Portátil' } else { 'Escritorio' })"
    Write-Host "  Log      : $Script:LogFile"
    Write-Host "  Backups  : $Script:BackupDir"
}

# =============================================================================
# 0. PUNTO DE RESTAURACIÓN
# =============================================================================

function New-RestorePoint {
    Write-Log "0. Crear punto de restauración" 'STEP'
    Write-Log "Qué hace: guarda una foto del sistema para revertir cambios." 'INFO'
    Write-Log "Requiere: Administrador. Puede tardar 1-2 minutos." 'WARN'

    if (-not (Require-Admin)) { Pause-Continue; return }

  if (-not (Confirm-Action "¿Crear punto de restauración ahora?")) {
        Write-Log "Cancelado por el usuario." 'WARN'
        return
    }

    try {
        # Habilitar protección del sistema en C: si está desactivada
        $enableScript = @"
`$cs = Get-CimInstance -ClassName 'SoftwareLicensingService' -ErrorAction SilentlyContinue
`$rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
Enable-ComputerRestore -Drive 'C:\' -ErrorAction SilentlyContinue
"@
        Invoke-Expression $enableScript

        $desc = "Optimizar-Windows10 - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log "Punto de restauración creado: $desc" 'OK'
        Write-Log "Revertir: Win+R -> rstrui.exe -> elegir punto anterior." 'INFO'
    }
    catch {
        Write-Log "No se pudo crear el punto de restauración: $($_.Exception.Message)" 'ERROR'
        Write-Log "Alternativa manual: Win+R -> sysdm.cpl -> Protección del sistema -> Crear" 'INFO'
    }
    Pause-Continue
}

# =============================================================================
# 1. LIMPIEZA DE ARCHIVOS
# =============================================================================

function Clear-TempFiles {
    Write-Log "1. Limpieza de archivos temporales y papelera" 'STEP'
    Write-Log "Qué hace: elimina temporales, caché local y vacía la papelera." 'INFO'
    Write-Log "Reversible: No aplica (archivos regenerables)." 'INFO'

    if (-not (Confirm-Action "¿Ejecutar limpieza de temporales y papelera?")) { return }

    $paths = @(
        $env:TEMP,
        "C:\Windows\Temp",
        "$env:LOCALAPPDATA\Temp"
    )

    $totalFreed = 0
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Write-Log "Limpiando: $path" 'INFO'
            Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $size = if ($_.PSIsContainer) {
                        (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum
                    } else { $_.Length }
                    Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
                    if ($size) { $totalFreed += $size }
                }
                catch { }
            }
        }
    }

    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Log "Papelera vaciada." 'OK'
    }
    catch {
        Write-Log "No se pudo vaciar la papelera (puede requerir admin)." 'WARN'
    }

    $freedMB = [math]::Round($totalFreed / 1MB, 2)
    Write-Log "Limpieza completada. Espacio liberado aprox.: $freedMB MB" 'OK'
    Pause-Continue
}

function Invoke-DiskCleanup {
    Write-Log "1b. Liberador de espacio en disco (cleanmgr)" 'STEP'
    Write-Log "Qué hace: abre la herramienta oficial de Microsoft para limpiar caché del sistema." 'INFO'
    Write-Log "Requiere: Administrador para 'Limpiar archivos del sistema'." 'WARN'

    if (-not (Require-Admin)) {
        Write-Log "Abriendo cleanmgr sin privilegios (limpieza básica)..." 'WARN'
    }

    if (Confirm-Action "¿Abrir Liberador de espacio en disco?") {
        Start-Process cleanmgr.exe -ArgumentList '/d C:' -ErrorAction SilentlyContinue
        Write-Log "En la ventana: clic en 'Limpiar archivos del sistema' y marca las casillas deseadas." 'INFO'
    }
    Pause-Continue
}

# =============================================================================
# 2. SALUD DEL SISTEMA (DISM + SFC)
# =============================================================================

function Repair-SystemFiles {
    Write-Log "2. Reparación del sistema (DISM + SFC)" 'STEP'
    Write-Log "Qué hace: DISM repara la imagen de Windows; SFC repara archivos del sistema." 'INFO'
    Write-Log "Requiere: Administrador. Puede tardar 20-45 min. Posible reinicio." 'WARN'

    if (-not (Require-Admin)) { Pause-Continue; return }
    if (-not (Confirm-Action "¿Ejecutar DISM y SFC? (tardará bastante)" -DefaultNo)) { return }

    Write-Log "Ejecutando DISM /Online /Cleanup-Image /RestoreHealth ..." 'INFO'
    $dism = Start-Process -FilePath 'DISM.exe' -ArgumentList '/Online','/Cleanup-Image','/RestoreHealth' -Wait -PassThru -NoNewWindow
    if ($dism.ExitCode -eq 0) {
        Write-Log "DISM completado correctamente." 'OK'
    }
    else {
        Write-Log "DISM terminó con código $($dism.ExitCode). Revisa el log." 'WARN'
    }

    Write-Log "Ejecutando sfc /scannow ..." 'INFO'
    $sfc = Start-Process -FilePath 'sfc.exe' -ArgumentList '/scannow' -Wait -PassThru -NoNewWindow
    if ($sfc.ExitCode -eq 0) {
        Write-Log "SFC completado correctamente." 'OK'
    }
    else {
        Write-Log "SFC terminó con código $($sfc.ExitCode)." 'WARN'
    }

    Write-Log "Revertir: No aplica. Reinicia si Windows lo solicita." 'INFO'
    Pause-Continue
}

# =============================================================================
# 3. DISCO (SSD TRIM / HDD DEFRAG)
# =============================================================================

function Optimize-SystemDisk {
    Write-Log "3. Optimización de disco" 'STEP'

    $diskType = (Get-SystemProfile).DiskType
    Write-Log "Disco C: detectado como: $diskType" 'INFO'

    if ($diskType -eq 'SSD') {
        Write-Log "SSD: se usa TRIM/optimización. NO desfragmentación clásica." 'INFO'
        Write-Log "Qué hace TRIM: informa al SSD qué bloques ya no se usan." 'INFO'
    }
    elseif ($diskType -eq 'HDD') {
        Write-Log "HDD: se usa desfragmentación para reordenar archivos fragmentados." 'INFO'
    }

    if (-not (Require-Admin)) { Pause-Continue; return }
    if (-not (Confirm-Action "¿Optimizar unidad C: ahora?")) { return }

    # Verificar TRIM en SSD
    if ($diskType -eq 'SSD') {
        $trimStatus = fsutil behavior query DisableDeleteNotify 2>&1
        Write-Log "Estado TRIM: $trimStatus" 'INFO'
        if ($trimStatus -match 'DisableDeleteNotify\s*=\s*1') {
            if (Confirm-Action "TRIM desactivado. ¿Activarlo?" -DefaultNo) {
                fsutil behavior set DisableDeleteNotify 0 | Out-Null
                Write-Log "TRIM activado." 'OK'
                Write-Log "Revertir TRIM: fsutil behavior set DisableDeleteNotify 1 (no recomendado en SSD)" 'INFO'
            }
        }
    }

    Write-Log "Ejecutando: defrag C: /O (optimización según tipo de disco)..." 'INFO'
    $defrag = Start-Process -FilePath 'defrag.exe' -ArgumentList 'C:','/O','/U' -Wait -PassThru -NoNewWindow
    if ($defrag.ExitCode -eq 0) {
        Write-Log "Optimización de disco completada." 'OK'
    }
    else {
        Write-Log "defrag terminó con código $($defrag.ExitCode)." 'WARN'
    }

  Write-Log "Revertir: No aplica. Programar en dfrgui.exe si quieres automatizar." 'INFO'
    Pause-Continue
}

# =============================================================================
# 4. PROGRAMAS DE INICIO
# =============================================================================

function Show-StartupPrograms {
    Write-Log "4. Programas de inicio" 'STEP'
    Write-Log "Qué hace: muestra apps que ralentizan el arranque. Desactívalas en el Administrador de tareas." 'INFO'
    Write-Log "Revertir: Administrador de tareas -> Inicio -> Habilitar." 'INFO'

    Write-Host "`n--- Programas de inicio (WMI) ---`n"
    Get-CimInstance Win32_StartupCommand |
        Select-Object Name, Command, Location |
        Format-Table -AutoSize -Wrap

    Write-Host "`n--- Registro (Run / RunOnce) ---`n"
    $regPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            Write-Host "[$rp]"
            Get-ItemProperty $rp -ErrorAction SilentlyContinue |
                Select-Object * -ExcludeProperty PS* |
                Format-List
        }
    }

    Write-Log "Abriendo Administrador de tareas (pestaña Inicio)..." 'INFO'
    Start-Process taskmgr.exe -ErrorAction SilentlyContinue
    Write-Log "Desactiva programas con 'Alto' impacto que no necesites al encender." 'WARN'
    Write-Log "NO desactives: audio, red, touchpad (portátil), utilidades del fabricante." 'WARN'
    Pause-Continue
}

# =============================================================================
# 5. SERVICIOS DE WINDOWS
# =============================================================================

$Script:SafeServices = @{
    'SysMain' = @{
        Description = 'Superfetch/Prefetch. En SSD a veces conviene desactivarlo.'
        SafeWhen    = 'SSD y quieres reducir uso de disco en segundo plano'
        Caution     = 'En HDD puede mejorar tiempos de carga de apps frecuentes'
    }
    'Fax' = @{
        Description = 'Servicio de fax. Casi nadie lo usa.'
        SafeWhen    = 'No usas fax ni escáner con fax'
        Caution     = 'Ninguna si no usas fax'
    }
    'WSearch' = @{
        Description = 'Indexación de Windows Search.'
        SafeWhen    = 'No usas la búsqueda del menú Inicio'
        Caution     = 'La búsqueda será más lenta'
    }
    'XblAuthManager' = @{
        Description = 'Autenticación Xbox Live.'
        SafeWhen    = 'No juegas con cuenta Xbox ni usas Game Bar'
        Caution     = 'Puede afectar funciones Xbox'
    }
    'XblGameSave' = @{
        Description = 'Guardado en la nube Xbox.'
        SafeWhen    = 'No usas juegos Xbox'
        Caution     = 'Puede afectar sincronización de partidas Xbox'
    }
    'XboxNetApiSvc' = @{
        Description = 'Red Xbox Live.'
        SafeWhen    = 'No usas Xbox ni multiplayer Xbox'
        Caution     = 'Puede afectar juegos con servicios Xbox'
    }
}

$Script:NeverDisableServices = @(
    'wuauserv',      # Windows Update
    'WinDefend',     # Windows Defender
    'WdNisSvc',      # Defender Network Inspection
    'SecurityHealthService',
    'RpcSs', 'RpcEptMapper', 'DcomLaunch',
    'PlugPlay', 'Power', 'Themes',
    'Dhcp', 'Dnscache', 'NlaSvc',
    'EventLog', 'Schedule', 'Winmgmt'
)

function Backup-ServiceState {
    param([string]$ServiceName)
    Ensure-BackupDir
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        $backup = @{
            Name        = $svc.Name
            StartType   = (Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").StartMode
            Status      = $svc.Status.ToString()
            BackupDate  = (Get-Date).ToString('o')
        }
        $file = Join-Path $Script:BackupDir "servicio_$ServiceName.json"
        $backup | ConvertTo-Json | Set-Content -Path $file -Encoding UTF8
        return $file
    }
    return $null
}

function Set-SafeServiceState {
    param(
        [string]$ServiceName,
        [ValidateSet('Disable', 'Enable')]
        [string]$Action
    )

    if ($Script:NeverDisableServices -contains $ServiceName) {
        Write-Log "BLOQUEADO: $ServiceName es un servicio crítico. No se modificará." 'ERROR'
        return
    }

    if (-not (Require-Admin)) { return }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "Servicio '$ServiceName' no encontrado en este equipo." 'WARN'
        return
    }

    Backup-ServiceState -ServiceName $ServiceName | Out-Null

    if ($Action -eq 'Disable') {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop
        Write-Log "Servicio $ServiceName desactivado." 'OK'
        Write-Log "Revertir: menú 5b o services.msc -> Automático -> Iniciar" 'INFO'
    }
    else {
        Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop
        Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
        Write-Log "Servicio $ServiceName activado." 'OK'
    }
}

function Manage-Services {
    Write-Log "5. Servicios de Windows (solo los seguros)" 'STEP'
    Write-Log "NO se tocarán: Windows Update, Defender, RPC, red, audio, etc." 'WARN'

    Write-Host "`nServicios que PUEDES desactivar si no los usas:`n"
    $i = 1
    foreach ($name in $Script:SafeServices.Keys) {
        $info = $Script:SafeServices[$name]
        $status = (Get-Service -Name $name -ErrorAction SilentlyContinue).Status
        Write-Host "  $i. $name [$status]"
        Write-Host "     $($info.Description)"
        Write-Host "     Seguro cuando: $($info.SafeWhen)"
        Write-Host "     Precaución: $($info.Caution)`n"
        $i++
    }

    Write-Host "  R. Revertir TODOS los servicios respaldados"
    Write-Host "  0. Volver al menú principal`n"

    $choice = Read-Host "Elige número para desactivar (o 0 para volver)"
    if ($choice -eq '0') { return }
    if ($choice -eq 'R' -or $choice -eq 'r') {
        Restore-AllServices
        Pause-Continue
        return
    }

    $names = @($Script:SafeServices.Keys)
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $names.Count) {
        $selected = $names[[int]$choice - 1]
        if (Confirm-Action "¿Desactivar servicio '$selected'?" -DefaultNo) {
            Set-SafeServiceState -ServiceName $selected -Action Disable
        }
    }
    Pause-Continue
}

function Restore-AllServices {
    Write-Log "Restaurando servicios desde backup..." 'STEP'
    if (-not (Require-Admin)) { return }

    Ensure-BackupDir
    $files = Get-ChildItem -Path $Script:BackupDir -Filter 'servicio_*.json' -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Log "No hay backups de servicios en $Script:BackupDir" 'WARN'
        return
    }

    foreach ($file in $files) {
        $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $startMode = switch ($data.StartType) {
            'Auto'   { 'Automatic' }
            'Manual' { 'Manual' }
            'Disabled' { 'Disabled' }
            default  { 'Manual' }
        }
        try {
            Set-Service -Name $data.Name -StartupType $startMode -ErrorAction Stop
            if ($startMode -ne 'Disabled') {
                Start-Service -Name $data.Name -ErrorAction SilentlyContinue
            }
            Write-Log "Restaurado: $($data.Name) -> $startMode" 'OK'
        }
        catch {
            Write-Log "Error restaurando $($data.Name): $($_.Exception.Message)" 'ERROR'
        }
    }
}

# =============================================================================
# 6. RENDIMIENTO VISUAL
# =============================================================================

function Set-VisualPerformance {
    param(
        [ValidateSet('Performance', 'Default')]
        [string]$Mode = 'Performance'
    )

    Write-Log "6. Efectos visuales" 'STEP'

    $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    Ensure-BackupDir
    $backupFile = Join-Path $Script:BackupDir 'visual_effects.json'

    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    $current = Get-ItemProperty -Path $regPath -Name 'VisualFXSetting' -ErrorAction SilentlyContinue
    if ($current) {
        @{ VisualFXSetting = $current.VisualFXSetting; Date = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content $backupFile -Encoding UTF8
    }

    if ($Mode -eq 'Performance') {
        Write-Log "Qué hace: desactiva animaciones y efectos para ganar fluidez." 'INFO'
        Set-ItemProperty -Path $regPath -Name 'VisualFXSetting' -Value 2 -Type DWord
        # Desactivar animaciones adicionales
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ListviewAlphaSelect' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-Log "Efectos visuales: optimizado para rendimiento." 'OK'
        Write-Log "Cierra sesión o reinicia para ver todos los cambios." 'WARN'
        Write-Log "Revertir: menú 6b o sysdm.cpl -> Rendimiento -> Dejar que Windows elija" 'INFO'
    }
    else {
        if (Test-Path $backupFile) {
            $bak = Get-Content $backupFile -Raw | ConvertFrom-Json
            Set-ItemProperty -Path $regPath -Name 'VisualFXSetting' -Value ([int]$bak.VisualFXSetting) -Type DWord
        }
        else {
            Set-ItemProperty -Path $regPath -Name 'VisualFXSetting' -Value 0 -Type DWord
        }
        Write-Log "Efectos visuales restaurados a predeterminado." 'OK'
    }
    Pause-Continue
}

# =============================================================================
# 7. ENERGÍA
# =============================================================================

function Set-PowerPlan {
    Write-Log "7. Plan de energía" 'STEP'

    $info = Get-SystemProfile
    if ($info.IsLaptop) {
        Write-Log "Portátil detectado: Alto rendimiento enchufado; Equilibrado con batería recomendado." 'INFO'
    }
    else {
        Write-Log "Escritorio: Alto rendimiento suele ser adecuado." 'INFO'
    }

    if (-not (Require-Admin)) { Pause-Continue; return }

    Write-Host "`nPlanes disponibles:`n"
    powercfg /list

    Write-Host "`n  1. Alto rendimiento"
    Write-Host "  2. Equilibrado"
    Write-Host "  3. Ahorro de energía"
    Write-Host "  0. Volver`n"

    $choice = Read-Host "Elige plan"
    $guids = @{
        '1' = 'e9a42b02-d5df-448d-aa00-03f14749eb61'  # Alto rendimiento
        '2' = '381b9ba2-9e8f-442c-8b68-5b6c7b2b2b2b'  # Equilibrado (puede variar)
        '3' = 'a1841308-3541-4fab-bc81-f71556f20b4a'  # Ahorro de energía
    }

    if ($choice -eq '0') { return }

    if ($choice -eq '1') {
        # Crear esquema si no existe
        powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
    }

    if ($guids.ContainsKey($choice)) {
        powercfg /setactive $guids[$choice]
        Write-Log "Plan de energía activado." 'OK'
        powercfg /getactivescheme
        Write-Log "Revertir: powercfg /setactive <GUID del plan anterior> o desde Panel de control" 'INFO'

        if ($info.IsLaptop -and $choice -eq '1') {
            Write-Log "En portátil con batería, Alto rendimiento reduce autonomía." 'WARN'
        }
    }
    Pause-Continue
}

# =============================================================================
# 8. RED
# =============================================================================

function Optimize-Network {
    Write-Log "8. Optimización de red" 'STEP'
    Write-Log "Qué hace: limpia caché DNS y opcionalmente configura DNS públicos." 'INFO'

    if (Require-Admin) {
        if (Confirm-Action "¿Limpiar caché DNS (ipconfig /flushdns)?") {
            ipconfig /flushdns | Out-Null
            Write-Log "Caché DNS limpiada." 'OK'
            Write-Log "Revertir: No aplica (se regenera sola)." 'INFO'
        }
    }

    # En modo automático no cambiamos los DNS del usuario (decisión de red personal).
    if ($Script:AutoMode) {
        Write-Log "[AUTO] DNS del sistema sin cambios (usa el menú manual para Cloudflare/Google)." 'INFO'
        return
    }

    Write-Host "`n  1. Configurar DNS Cloudflare (1.1.1.1 / 1.0.0.1)"
    Write-Host "  2. Configurar DNS Google (8.8.8.8 / 8.8.4.4)"
    Write-Host "  3. Restaurar DNS automático (DHCP)"
    Write-Host "  0. Volver`n"

    $choice = Read-Host "Opción DNS"
    if ($choice -eq '0') { Pause-Continue; return }

    if (-not (Require-Admin)) { Pause-Continue; return }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface }
    if (-not $adapters) {
        Write-Log "No se encontraron adaptadores de red activos." 'WARN'
        Pause-Continue
        return
    }

    Write-Host "`nAdaptadores activos:"
    $i = 1
    foreach ($a in $adapters) { Write-Host "  $i. $($a.Name) ($($a.InterfaceDescription))"; $i++ }
    $adapterChoice = Read-Host "Elige adaptador (número)"
    if ($adapterChoice -notmatch '^\d+$') { Pause-Continue; return }
    $adapter = $adapters[[int]$adapterChoice - 1]

    Ensure-BackupDir
    $dnsBackup = Join-Path $Script:BackupDir "dns_$($adapter.Name).json"
    $currentDns = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
    @{ Interface = $adapter.Name; DNS = $currentDns.ServerAddresses; Date = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content $dnsBackup -Encoding UTF8

    switch ($choice) {
        '1' {
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses ('1.1.1.1', '1.0.0.1')
            Write-Log "DNS Cloudflare configurado en $($adapter.Name)." 'OK'
        }
        '2' {
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses ('8.8.8.8', '8.8.4.4')
            Write-Log "DNS Google configurado en $($adapter.Name)." 'OK'
        }
        '3' {
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
            Write-Log "DNS restaurado a automático (DHCP) en $($adapter.Name)." 'OK'
        }
    }

    Write-Log "Revertir DNS: opción 3 o Configuración -> Red -> DNS automático" 'INFO'

    if ((Get-SystemProfile).IsLaptop) {
        Write-Log "Tip portátil: en Administrador de dispositivos, desactiva 'apagar adaptador Wi-Fi' para evitar cortes." 'INFO'
    }
    Pause-Continue
}

# =============================================================================
# 9. MEMORIA / ARCHIVO DE PAGINACIÓN
# =============================================================================

function Show-PageFileInfo {
    Write-Log "9. Memoria RAM y archivo de paginación" 'STEP'

    $os = Get-CimInstance Win32_OperatingSystem
    $totalRAM = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeRAM  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedRAM  = [math]::Round($totalRAM - $freeRAM, 2)
    $pct = if ($totalRAM -gt 0) { [math]::Round(($usedRAM / $totalRAM) * 100, 1) } else { 0 }

    Write-Host "`n  RAM total  : $totalRAM GB"
    Write-Host "  RAM en uso : $usedRAM GB ($pct%)"
    Write-Host "  RAM libre  : $freeRAM GB`n"

    $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
    if ($pf) {
        Write-Host "  Archivo de paginación:"
        Write-Host "    Ubicación : $($pf.Name)"
        Write-Host "    Tamaño actual: $([math]::Round($pf.CurrentUsage, 0)) MB usados / $([math]::Round($pf.AllocatedBaseSize, 0)) MB asignados"
    }

    Write-Log "Recomendación: dejar 'Tamaño administrado por el sistema' (no poner 0)." 'INFO'
    Write-Log "Mito: desactivar paginación NO hace el PC más rápido; puede causar cuelgues." 'WARN'
    Write-Log "Mejora real si RAM siempre >80%: instalar más RAM física." 'INFO'
    Write-Log "Configurar: sysdm.cpl -> Opciones avanzadas -> Rendimiento -> Memoria virtual" 'INFO'

    if ($totalRAM -le 8) {
        Write-Log "Con 8 GB o menos: NO desactives el archivo de paginación." 'WARN'
    }

    Write-Host "`n--- Top 10 procesos por RAM ---`n"
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 |
        ForEach-Object {
            [PSCustomObject]@{
                Proceso = $_.ProcessName
                RAM_MB  = [math]::Round($_.WorkingSet64 / 1MB, 1)
            }
        } | Format-Table -AutoSize

    Pause-Continue
}

# =============================================================================
# 10. PRIVACIDAD / TELEMETRÍA
# =============================================================================

function Set-PrivacySettings {
    Write-Log "10. Privacidad y telemetría (nivel razonable)" 'STEP'
    Write-Log "Qué hace: reduce telemetría sin desactivar Update ni Defender." 'INFO'
    Write-Log "Requiere: Administrador para algunos cambios." 'WARN'

    Ensure-BackupDir
    $privacyBackup = Join-Path $Script:BackupDir 'privacidad.json'
    $backup = @{ Date = (Get-Date).ToString('o'); Items = @() }

    # Diagnóstico: básico (valor 1) en lugar de completo (3)
    $diagPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    if (-not (Test-Path $diagPath)) { New-Item -Path $diagPath -Force | Out-Null }
    $prevDiag = (Get-ItemProperty -Path $diagPath -Name 'AllowTelemetry' -ErrorAction SilentlyContinue).AllowTelemetry
    $backup.Items += @{ Key = 'AllowTelemetry'; Value = $prevDiag }
    $backup | ConvertTo-Json -Depth 5 | Set-Content $privacyBackup -Encoding UTF8

    if (Confirm-Action "¿Configurar telemetría en nivel Básico?") {
        if (Require-Admin) {
            Set-ItemProperty -Path $diagPath -Name 'AllowTelemetry' -Value 1 -Type DWord
            Write-Log "Telemetría configurada en Básico (1)." 'OK'
        }
    }

    # Publicidad
    $adPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
    if (-not (Test-Path $adPath)) { New-Item -Path $adPath -Force | Out-Null }
    if (Confirm-Action "¿Desactivar ID de publicidad?") {
        Set-ItemProperty -Path $adPath -Name 'Enabled' -Value 0 -Type DWord
        Write-Log "ID de publicidad desactivado." 'OK'
    }

    # Sugerencias en Inicio
    $contentPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    if (Test-Path $contentPath) {
        if (Confirm-Action "¿Desactivar sugerencias y contenido promocional en Inicio?") {
            @(
                'SystemPaneSuggestionsEnabled',
                'SubscribedContent-310093Enabled',
                'SubscribedContent-338389Enabled',
                'SubscribedContent-353694Enabled',
                'SubscribedContent-353696Enabled'
            ) | ForEach-Object {
                Set-ItemProperty -Path $contentPath -Name $_ -Value 0 -Type DWord -ErrorAction SilentlyContinue
            }
            Write-Log "Sugerencias promocionales reducidas." 'OK'
        }
    }

    # DiagTrack (opcional, con precaución)
    if (Require-Admin) {
        if (Confirm-Action "¿Desactivar servicio DiagTrack (telemetría extendida)?" -DefaultNo) {
            Backup-ServiceState -ServiceName 'DiagTrack' | Out-Null
            Stop-Service -Name 'DiagTrack' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "DiagTrack desactivado." 'OK'
            Write-Log "Revertir: services.msc -> DiagTrack -> Automático -> Iniciar" 'INFO'
        }
    }

    Write-Log "Revertir telemetría: elimina AllowTelemetry en políticas o usa menú Revertir privacidad." 'INFO'
    Pause-Continue
}

function Restore-PrivacySettings {
    Write-Log "Revertir configuración de privacidad" 'STEP'
    $privacyBackup = Join-Path $Script:BackupDir 'privacidad.json'
    if (-not (Test-Path $privacyBackup)) {
        Write-Log "No hay backup de privacidad." 'WARN'
        Pause-Continue
        return
    }

    if (Require-Admin) {
        Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -ErrorAction SilentlyContinue
        Set-Service -Name 'DiagTrack' -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue
        Write-Log "Privacidad restaurada a valores predeterminados del sistema." 'OK'
    }
    Pause-Continue
}

# =============================================================================
# 11. ACTUALIZACIONES
# =============================================================================

function Check-Updates {
    Write-Log "11. Actualizaciones de Windows y drivers" 'STEP'
    Write-Log "Qué hace: abre Windows Update. NO desactiva el servicio de actualizaciones." 'INFO'

    if (Confirm-Action "¿Abrir Windows Update ahora?") {
        Start-Process 'ms-settings:windowsupdate'
        Write-Log "Busca actualizaciones e instala las pendientes." 'INFO'
    }

    if (Confirm-Action "¿Abrir Administrador de dispositivos para revisar drivers?") {
        Start-Process devmgmt.msc
        Write-Log "Actualiza drivers desde el fabricante (Intel, AMD, NVIDIA, Dell, HP, Lenovo)." 'INFO'
        Write-Log "Evita programas 'driver booster' automáticos." 'WARN'
    }

    Write-Log "Revertir driver: Propiedades -> Controlador -> Revertir (si está disponible)." 'INFO'
    Pause-Continue
}

# =============================================================================
# 12. MANTENIMIENTO PERIÓDICO / OPTIMIZACIÓN COMPLETA
# =============================================================================

function Invoke-FullOptimization {
    Write-Log "OPTIMIZACIÓN COMPLETA (segura)" 'STEP'
    Write-Log "Ejecutará en orden: restauración -> limpieza -> disco -> visual -> red" 'INFO'
    Write-Log "NO incluye: DISM/SFC (muy lento), desactivar Defender/Update." 'WARN'

    if (-not (Confirm-Action "¿Continuar con optimización completa?")) { return }
    if (-not (Require-Admin)) { return }

    New-RestorePoint
    Clear-TempFiles
    Optimize-SystemDisk
    Set-VisualPerformance -Mode Performance
    Optimize-Network

    Write-Log "Optimización completa finalizada. Reinicia el PC para aplicar todos los cambios." 'OK'
    if (Confirm-Action "¿Reiniciar ahora?" -DefaultNo) {
        Restart-Computer -Force
    }
}

function Invoke-AutoOptimization {
    Write-Log "MODO AUTOMÁTICO: ejecutando optimizaciones seguras sin intervención" 'STEP'
    Write-Log "No se desactiva Windows Update ni Defender. Todo reversible." 'INFO'

    if (-not (Test-IsAdmin)) {
        Write-Log "No se ejecuta como Administrador: algunos pasos se omitirán." 'WARN'
    }

    # 1. Punto de restauración (seguridad primero)
    New-RestorePoint

    # 2. Limpieza de temporales y papelera
    Clear-TempFiles

    # 3. Optimización de disco (TRIM en SSD / defrag en HDD)
    Optimize-SystemDisk

    # 4. Efectos visuales -> rendimiento
    Set-VisualPerformance -Mode Performance

    # 5. Red: solo limpiar caché DNS
    Optimize-Network

    # 6. Privacidad razonable (solo acciones seguras)
    Set-PrivacySettings

    # 7. Opcional profundo: DISM + SFC
    if ($Deep) {
        Repair-SystemFiles
    }
    else {
        Write-Log "DISM/SFC omitido (usa -Deep para incluirlo)." 'INFO'
    }

    Write-Log "OPTIMIZACIÓN AUTOMÁTICA COMPLETADA." 'OK'
    Write-Log "Log detallado: $Script:LogFile" 'INFO'
    Write-Log "Backups (para revertir): $Script:BackupDir" 'INFO'
    Write-Log "Reinicia el PC para aplicar todos los cambios." 'WARN'
}

function Show-MaintenanceSchedule {
    Write-Log "12. Rutina de mantenimiento periódico" 'STEP'

    @"

  SEMANAL
  ------
  [ ] Reiniciar el PC al menos una vez
  [ ] Revisar programas de inicio si instalaste software nuevo
  [ ] ipconfig /flushdns (solo si hay problemas de red)

  MENSUAL
  -------
  [ ] Liberador de espacio (cleanmgr /sagerun:1)
  [ ] Optimizar unidades (defrag C: /O)
  [ ] Buscar actualizaciones de Windows
  [ ] Mantener >15% libre en C:
  [ ] Revisar apps instaladas y desinstalar las que no uses

  TRIMESTRAL
  ----------
  [ ] DISM + SFC si hay inestabilidad
  [ ] Revisar salud del disco (herramienta del fabricante)
  [ ] Punto de restauración antes de cambios grandes

  ANUAL
  -----
  [ ] Limpieza física (polvo en ventiladores)
  [ ] Backup de archivos importantes
  [ ] Revisar drivers desde web del fabricante

"@ | Write-Host

    Write-Log "Mitos a EVITAR:" 'WARN'
    @"
  X Programas 'PC Accelerator' o 'Registry Cleaner' agresivos
  X Desactivar Windows Update o Windows Defender
  X Borrar archivos de C:\Windows\System32
  X 'Limpiadores de RAM' que liberan memoria a la fuerza
  X Desactivar archivo de paginación (pagefile)
  X Tweaks masivos de registro de foros
  X Desfragmentar SSD como si fuera HDD
  X Desactivar servicios al azar sin saber qué hacen
"@ | Write-Host

    Pause-Continue
}

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================

function Show-Banner {
    Clear-Host
    Write-Host @"

  ============================================================
   OPTIMIZAR WINDOWS 10 - Script seguro y reversible
  ============================================================
   Ejecutar como Administrador para todas las funciones.
   Log: $Script:LogFile
  ============================================================

"@ -ForegroundColor Cyan
}

function Show-MainMenu {
    Show-Banner
    Show-SystemInfo

    Write-Host @"

  --- MENU PRINCIPAL (de mas seguro a mas avanzado) ---

   0. Crear punto de restauracion          [Admin] [Reinicio: no]
   1. Limpiar temporales y papelera       [Reversible: N/A]
   2. Liberador de espacio (cleanmgr)     [Admin recomendado]
   3. Reparar sistema (DISM + SFC)        [Admin] [20-45 min]
   4. Optimizar disco (SSD TRIM / HDD)    [Admin]
   5. Ver programas de inicio
   6. Gestionar servicios seguros         [Admin] [Precaucion]
   7. Efectos visuales -> rendimiento
   8. Plan de energia                     [Admin] [Portatil: ojo bateria]
   9. Red (DNS flush + DNS publicos)      [Admin parcial]
  10. Info RAM y archivo de paginacion
  11. Privacidad / telemetria razonable    [Admin parcial]
  12. Windows Update y drivers
  13. Rutina de mantenimiento + mitos

  --- ACCIONES RAPIDAS ---

  A. Optimizacion completa (sin DISM/SFC)
  R. Revertir servicios respaldados      [Admin]
  V. Revertir efectos visuales
  P. Revertir privacidad                 [Admin]
  X. Salir

"@

    return Read-Host "Elige una opcion"
}

# =============================================================================
# PUNTO DE ENTRADA
# =============================================================================

function Main {
    if (-not (Test-IsAdmin)) {
        Write-Host "`nAVISO: No ejecutas como Administrador. Algunas funciones estarán limitadas.`n" -ForegroundColor Yellow
        Write-Host "Para todas las funciones: clic derecho en PowerShell -> Ejecutar como administrador`n"
    }

    Write-Log "Script iniciado. Log: $Script:LogFile" 'INFO'

    # Modo automático: ejecuta todo y termina, sin menú.
    if ($Script:AutoMode) {
        Show-Banner
        Show-SystemInfo
        Invoke-AutoOptimization
        Write-Host "`nProceso automático finalizado. Revisa el log arriba." -ForegroundColor Green
        return
    }

    do {
        $choice = Show-MainMenu
        switch ($choice.ToUpper()) {
            '0'  { New-RestorePoint }
            '1'  { Clear-TempFiles }
            '2'  { Invoke-DiskCleanup }
            '3'  { Repair-SystemFiles }
            '4'  { Optimize-SystemDisk }
            '5'  { Show-StartupPrograms }
            '6'  { Manage-Services }
            '7'  { Set-VisualPerformance -Mode Performance }
            '8'  { Set-PowerPlan }
            '9'  { Optimize-Network }
            '10' { Show-PageFileInfo }
            '11' { Set-PrivacySettings }
            '12' { Check-Updates }
            '13' { Show-MaintenanceSchedule }
            'A'  { Invoke-FullOptimization }
            'R'  { Restore-AllServices; Pause-Continue }
            'V'  { Set-VisualPerformance -Mode Default }
            'P'  { Restore-PrivacySettings }
            'X'  { Write-Log "Saliendo. Hasta luego." 'OK'; return }
            default { Write-Log "Opción no válida." 'WARN'; Pause-Continue }
        }
    } while ($true)
}

Main
