# Ajustes a nivel de Windows: plan de energia, prioridad del proceso del juego,
# perfil de scheduler multimedia (MMCSS), Game DVR / optimizaciones de pantalla
# completa, y pausa reversible de servicios en segundo plano no esenciales.

Import-Module (Join-Path $PSScriptRoot "Common.psm1") -Force

# Servicios que se pausan durante la sesion de juego. Se cambian a Manual
# (nunca Disabled) y se restauran a su estado/tipo de inicio original al
# ejecutar Restore-LoL.ps1. Lista deliberadamente conservadora.
$script:GamingServiceList = @(
    'SysMain',   # Superfetch/Prefetch: puede causar uso de disco en segundo plano
    'DiagTrack'  # Telemetria de Windows
)

function Get-PowerSchemeAlias {
    param([Parameter(Mandatory)] [string]$Alias)
    # powercfg -aliases mapea nombres independientes del idioma (SCHEME_MAX, etc.)
    # a su GUID real, evitando depender del nombre visible del plan (que cambia
    # segun el idioma del sistema).
    $output = powercfg -aliases
    foreach ($line in $output) {
        if ($line -match "^\s*$Alias\s+([0-9a-fA-F-]{36})") {
            return $Matches[1]
        }
    }
    return $null
}

function Get-ActivePowerSchemeGuid {
    $output = powercfg /getactivescheme
    if ($output -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        return $Matches[1]
    }
    return $null
}

function Set-HighPerformancePower {
    param([Parameter(Mandatory)] $BackupState)

    $BackupState.PowerScheme = Get-ActivePowerSchemeGuid

    # GUID publico y fijo del plan plantilla "Ultimate Performance" documentado
    # por Microsoft. No todas las ediciones de Windows lo soportan.
    $ultimateTemplate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $targetGuid = $null

    $existingUltimate = (powercfg /list) | Select-String -Pattern $ultimateTemplate -SimpleMatch
    if (-not $existingUltimate) {
        try {
            $dup = powercfg -duplicatescheme $ultimateTemplate
            if ($dup -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                $targetGuid = $Matches[1]
            }
        }
        catch {
            Write-Log "No se pudo crear el plan 'Ultimate Performance' (no soportado en esta edicion de Windows)." -Level WARN
        }
    }
    else {
        $targetGuid = $ultimateTemplate
    }

    if (-not $targetGuid) {
        $targetGuid = Get-PowerSchemeAlias -Alias 'SCHEME_MAX'
    }

    if (-not $targetGuid) {
        Write-Log "No se encontro un plan de alto rendimiento disponible; se mantiene el plan actual." -Level WARN
        return
    }

    powercfg /setactive $targetGuid | Out-Null
    Write-Log "Plan de energia activo: $targetGuid" -Level OK
}

function Restore-PowerScheme {
    param([Parameter(Mandatory)] [string]$OriginalGuid)
    try {
        powercfg /setactive $OriginalGuid | Out-Null
        Write-Log "Plan de energia restaurado a $OriginalGuid" -Level OK
    }
    catch {
        Write-Log "No se pudo restaurar el plan de energia original: $_" -Level WARN
    }
}

function Set-MMCSSGamingProfile {
    param([Parameter(Mandatory)] $BackupState)

    $profilePath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-RegistryValueTracked -Path $profilePath -Name 'SystemResponsiveness' -Value 0 -Type DWord -BackupState $BackupState

    $gamesTaskPath = "$profilePath\Tasks\Games"
    Set-RegistryValueTracked -Path $gamesTaskPath -Name 'GPU Priority' -Value 8 -Type DWord -BackupState $BackupState
    Set-RegistryValueTracked -Path $gamesTaskPath -Name 'Priority' -Value 6 -Type DWord -BackupState $BackupState
    Set-RegistryValueTracked -Path $gamesTaskPath -Name 'Scheduling Category' -Value 'High' -Type String -BackupState $BackupState
    Set-RegistryValueTracked -Path $gamesTaskPath -Name 'SFIO Priority' -Value 'High' -Type String -BackupState $BackupState

    Write-Log "Perfil MMCSS de juegos aplicado (prioridad de GPU/CPU para procesos de juego)." -Level OK
}

function Disable-GameDvrAndFullscreenOptimizations {
    param([Parameter(Mandatory)] $BackupState)

    $gameConfigPath = 'HKCU:\System\GameConfigStore'
    Set-RegistryValueTracked -Path $gameConfigPath -Name 'GameDVR_Enabled' -Value 0 -Type DWord -BackupState $BackupState
    Set-RegistryValueTracked -Path $gameConfigPath -Name 'GameDVR_FSEBehaviorMode' -Value 2 -Type DWord -BackupState $BackupState
    Set-RegistryValueTracked -Path $gameConfigPath -Name 'GameDVR_HonorUserFSEBehaviorMode' -Value 1 -Type DWord -BackupState $BackupState

    $gameBarPath = 'HKCU:\SOFTWARE\Microsoft\GameBar'
    Set-RegistryValueTracked -Path $gameBarPath -Name 'AutoGameModeEnabled' -Value 1 -Type DWord -BackupState $BackupState
    Set-RegistryValueTracked -Path $gameBarPath -Name 'AllowAutoGameMode' -Value 1 -Type DWord -BackupState $BackupState

    Write-Log "Game DVR (grabacion en segundo plano) deshabilitado y Modo Juego activado." -Level OK
}

function Set-BackgroundServicesForGaming {
    param([Parameter(Mandatory)] $BackupState)

    foreach ($name in $script:GamingServiceList) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) { continue }

        $BackupState.Services[$name] = [ordered]@{
            OriginalStatus    = $svc.Status.ToString()
            OriginalStartType = $svc.StartType.ToString()
        }

        try {
            if ($svc.StartType -ne 'Disabled') {
                Set-Service -Name $name -StartupType Manual -ErrorAction Stop
            }
            if ($svc.Status -eq 'Running') {
                Stop-Service -Name $name -Force -ErrorAction Stop
            }
            Write-Log "Servicio '$name' pausado (se restaurara al ejecutar Restore-LoL.ps1)." -Level OK
        }
        catch {
            Write-Log "No se pudo pausar el servicio '$name': $_" -Level WARN
        }
    }
}

function Restore-BackgroundServices {
    param([Parameter(Mandatory)] $ServicesBackup)

    foreach ($prop in $ServicesBackup.PSObject.Properties) {
        $name = $prop.Name
        $info = $prop.Value
        try {
            Set-Service -Name $name -StartupType $info.OriginalStartType -ErrorAction Stop
            if ($info.OriginalStatus -eq 'Running') {
                Start-Service -Name $name -ErrorAction Stop
            }
            Write-Log "Servicio '$name' restaurado (StartType=$($info.OriginalStartType), Status=$($info.OriginalStatus))." -Level OK
        }
        catch {
            Write-Log "No se pudo restaurar el servicio '$name': $_" -Level WARN
        }
    }
}

function Wait-ForLeagueProcessAndBoost {
    param(
        [string[]]$ProcessNames = @('League of Legends'),
        [int]$TimeoutSeconds = 300,
        [ValidateSet('AboveNormal', 'High')] [string]$Priority = 'AboveNormal'
    )

    $elapsed = 0
    $proc = $null
    while ($elapsed -lt $TimeoutSeconds) {
        foreach ($name in $ProcessNames) {
            $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($proc) { break }
        }
        if ($proc) { break }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    if (-not $proc) {
        Write-Log "No se detecto el proceso del juego tras $TimeoutSeconds s; omitiendo ajuste de prioridad (los demas ajustes siguen aplicados)." -Level WARN
        return
    }

    try {
        $proc.PriorityClass = $Priority
        Write-Log "Prioridad de '$($proc.ProcessName)' (PID $($proc.Id)) ajustada a $Priority." -Level OK
    }
    catch {
        Write-Log "No se pudo ajustar la prioridad del proceso: $_" -Level WARN
    }
}

Export-ModuleMember -Function * -Variable GamingServiceList
