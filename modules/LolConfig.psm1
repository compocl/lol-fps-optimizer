# Deteccion de la instalacion de League of Legends y recomendaciones de
# configuracion grafica in-game.
#
# IMPORTANTE: se investigo editar PersistedSettings.json (configuracion
# grafica) automaticamente, pero Riot sincroniza ese archivo con el servidor
# por cuenta -- un valor editado a mano puede ser sobrescrito en el siguiente
# login sin aviso, dando una falsa sensacion de "ya quedo optimizado". Por
# eso este modulo NO edita esa configuracion: solo la detecta y muestra una
# checklist para aplicarla manualmente en el cliente, que es el metodo
# confiable segun la propia documentacion de soporte de Riot.

Import-Module (Join-Path $PSScriptRoot "Common.psm1") -Force

function Get-JsonStringLeaves {
    param($Node)
    $results = @()
    if ($null -eq $Node) { return $results }
    if ($Node -is [string]) { return @($Node) }
    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        foreach ($item in $Node) { $results += Get-JsonStringLeaves $item }
        return $results
    }
    if ($Node -is [PSCustomObject]) {
        foreach ($prop in $Node.PSObject.Properties) { $results += Get-JsonStringLeaves $prop.Value }
    }
    return $results
}

function Find-LeagueInstall {
    $candidates = @()

    $installsJson = Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
    if (Test-Path $installsJson) {
        try {
            $data = Get-Content $installsJson -Raw | ConvertFrom-Json
            $leaves = Get-JsonStringLeaves $data
            $candidates += $leaves | Where-Object { $_ -like '*League of Legends*' }
        }
        catch {
            Write-Log "No se pudo leer RiotClientInstalls.json: $_" -Level WARN
        }
    }

    $candidates += @(
        "C:\Riot Games\League of Legends",
        (Join-Path $env:ProgramFiles 'Riot Games\League of Legends'),
        (Join-Path ${env:ProgramFiles(x86)} 'Riot Games\League of Legends')
    )

    # Fallback: barrer la raiz de cada unidad fija por si esta instalado en otro disco.
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
        $candidates += Join-Path "$($drive.Root)" 'Riot Games\League of Legends'
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        # Un candidato puede apuntar al .exe o a la carpeta; nos quedamos con la carpeta de instalacion.
        $dir = if (Test-Path $candidate -PathType Leaf) { Split-Path $candidate -Parent } else { $candidate }
        if (Test-Path (Join-Path $dir 'Config')) {
            return (Resolve-Path $dir).Path
        }
    }

    return $null
}

function Show-RecommendedGraphicsSettings {
    Write-Log "Configuracion in-game recomendada para maximizar FPS (aplicala manualmente en Ajustes > Video, dentro del cliente de League):" -Level INFO
    $recommendations = @(
        'Calidad de sombras: Desactivado',
        'Antialiasing: Desactivado',
        'Calidad de efectos: Muy baja',
        'Calidad de personajes: Muy baja',
        'Calidad del entorno: Muy baja',
        'Limite de FPS: sin limite, o igual a la tasa de refresco de tu monitor',
        'VSync / Esperar sincronizacion vertical: Desactivado',
        'Modo de ventana: Pantalla completa (no ventana sin bordes)'
    )
    foreach ($r in $recommendations) { Write-Log "  - $r" -Level INFO }
    Write-Log "No se edita PersistedSettings.json automaticamente: Riot lo sincroniza con el servidor por cuenta y una edicion manual puede ser sobrescrita sin aviso." -Level WARN
}

Export-ModuleMember -Function *
