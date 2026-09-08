<#
.SYNOPSIS
    Aplica un conjunto de optimizaciones de sistema, red y GPU orientadas a
    reducir tirones y mejorar FPS/fluidez en League of Legends.

.DESCRIPTION
    Requiere ejecutarse como Administrador. Guarda un respaldo de todo lo que
    modifica en state\backup.json para poder revertirlo con Restore-LoL.ps1.

    No modifica archivos de configuracion del juego que Riot sincroniza con
    el servidor, ni interactua con el proceso/memoria del juego o del
    cliente (Vanguard, el anti-cheat de League, opera a nivel de kernel y
    cualquier interaccion con el proceso del juego puede derivar en sancion).
    Todos los ajustes aqui son a nivel de sistema operativo.

.PARAMETER SkipServices
    No pausar servicios en segundo plano (SysMain, DiagTrack).

.PARAMETER SkipNetwork
    No aplicar ajustes de red (Nagle, QoS).

.PARAMETER SkipQos
    Aplicar el ajuste de Nagle pero omitir la politica de QoS.

.PARAMETER SkipProcessWait
    No esperar a que se abra League of Legends para ajustar su prioridad de
    proceso. Util si solo quieres aplicar los ajustes de sistema ahora y
    lanzar el juego mas tarde.

.PARAMETER ProcessWaitTimeoutSeconds
    Tiempo maximo de espera (segundos) al proceso del juego. Por defecto 300.

.PARAMETER Aggressive
    Usa prioridad de proceso "High" en vez de "AboveNormal" (mas agresivo,
    puede afectar la respuesta de otras apps mientras juegas).

.EXAMPLE
    .\Optimize-LoL.ps1
    Aplica todos los ajustes y espera a que abras el juego.

.EXAMPLE
    .\Optimize-LoL.ps1 -SkipProcessWait
    Aplica los ajustes de sistema/red/GPU sin esperar al proceso del juego.
#>
[CmdletBinding()]
param(
    [switch]$SkipServices,
    [switch]$SkipNetwork,
    [switch]$SkipQos,
    [switch]$SkipProcessWait,
    [int]$ProcessWaitTimeoutSeconds = 300,
    [switch]$Aggressive
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot "modules\Common.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\SystemTweaks.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\NetworkTweaks.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\GpuTweaks.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\LolConfig.psm1") -Force

Assert-Admin

Write-Log "=== Optimizador de FPS para League of Legends: iniciando ===" -Level INFO

if (Test-Path (Get-BackupFilePath)) {
    Write-Log "Ya existe un respaldo sin restaurar (ejecucion previa no revertida). Se sobrescribira; si prefieres, cancela (Ctrl+C) y corre primero Restore-LoL.ps1." -Level WARN
}

$backup = New-BackupState

try {
    Write-Log "Ajustando plan de energia a maximo rendimiento..."
    Set-HighPerformancePower -BackupState $backup

    Write-Log "Ajustando perfil MMCSS para juegos..."
    Set-MMCSSGamingProfile -BackupState $backup

    Write-Log "Deshabilitando Game DVR / grabacion en segundo plano y activando Modo Juego..."
    Disable-GameDvrAndFullscreenOptimizations -BackupState $backup

    Show-GpuVendorRecommendations

    if (-not $SkipServices) {
        Write-Log "Pausando servicios en segundo plano no esenciales..."
        Set-BackgroundServicesForGaming -BackupState $backup
    }

    if (-not $SkipNetwork) {
        Write-Log "Deshabilitando algoritmo de Nagle en interfaces de red activas..."
        Disable-NagleAlgorithm -BackupState $backup

        if (-not $SkipQos) {
            Write-Log "Creando politica de QoS para priorizar el trafico de League of Legends..."
            Set-QosPolicyForLeague -BackupState $backup
        }
    }

    $lolPath = Find-LeagueInstall
    if ($lolPath) {
        Write-Log "League of Legends detectado en: $lolPath" -Level OK
        $exePath = Join-Path $lolPath "Game\League of Legends.exe"
        if (Test-Path $exePath) {
            Write-Log "Forzando GPU de alto rendimiento para League of Legends.exe..."
            Set-HighPerformanceGpuPreference -ExePath $exePath -BackupState $backup
        }
        else {
            Write-Log "No se encontro League of Legends.exe en '$exePath'; se omite el ajuste de preferencia de GPU por ejecutable." -Level WARN
        }
        Show-RecommendedGraphicsSettings
    }
    else {
        Write-Log "No se pudo detectar automaticamente la instalacion de League of Legends; se omiten los ajustes especificos del juego." -Level WARN
    }

    Save-BackupState -State $backup
    Write-Log "Respaldo de configuracion original guardado en state\backup.json" -Level OK

    if (-not $SkipProcessWait) {
        $priority = if ($Aggressive) { 'High' } else { 'AboveNormal' }
        Write-Log "Esperando a que League of Legends se inicie para ajustar su prioridad de proceso a '$priority' (timeout ${ProcessWaitTimeoutSeconds}s). Los demas ajustes ya quedaron aplicados; puedes cancelar con Ctrl+C sin perderlos."
        Wait-ForLeagueProcessAndBoost -TimeoutSeconds $ProcessWaitTimeoutSeconds -Priority $priority
    }

    Write-Log "=== Optimizacion completada. Cuando termines de jugar, ejecuta Restore-LoL.ps1 para revertir todos los cambios. ===" -Level OK
}
catch {
    Write-Log "Error durante la optimizacion: $_" -Level ERROR
    Save-BackupState -State $backup
    Write-Log "Se guardo el progreso parcial en state\backup.json; ejecuta Restore-LoL.ps1 para revertirlo." -Level WARN
    throw
}
