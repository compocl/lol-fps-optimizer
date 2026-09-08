# Ajustes de GPU. La parte que se APLICA (preferencia de GPU de alto
# rendimiento) es agnostica de fabricante: usa la preferencia oficial de
# Windows (DirectX UserGpuPreferences), que funciona igual con NVIDIA, AMD
# o Intel -- es la que decide que adaptador usa el juego en equipos con mas
# de una GPU (ej. laptop con Intel UHD integrada + NVIDIA/AMD dedicada).
#
# Lo que SI depende del fabricante es el panel de control propio de cada
# marca (NVIDIA Control Panel, AMD Software, Intel Graphics Command Center):
# ninguno expone una API de registro publica y estable para automatizar su
# modo de rendimiento, asi que se detecta el/los fabricante(s) presentes y
# se imprime la recomendacion manual correcta para cada uno, en vez de
# mostrar siempre el mismo tip de NVIDIA sin importar el hardware real.

Import-Module (Join-Path $PSScriptRoot "Common.psm1") -Force

function Get-GpuVendors {
    $adapters = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
    $vendors = [ordered]@{
        Nvidia = $false
        Amd    = $false
        Intel  = $false
        Names  = @()
    }

    foreach ($gpu in $adapters) {
        if (-not $gpu.Name) { continue }
        $vendors.Names += $gpu.Name
        if ($gpu.Name -match 'NVIDIA') { $vendors.Nvidia = $true }
        if ($gpu.Name -match 'AMD|Radeon|ATI\b') { $vendors.Amd = $true }
        if ($gpu.Name -match 'Intel') { $vendors.Intel = $true }
    }

    return $vendors
}

function Set-HighPerformanceGpuPreference {
    param(
        [Parameter(Mandatory)] [string]$ExePath,
        [Parameter(Mandatory)] $BackupState
    )

    if (-not (Test-Path $ExePath)) {
        Write-Log "Ruta de ejecutable no encontrada ($ExePath); se omite la preferencia de GPU." -Level WARN
        return
    }

    $path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    Set-RegistryValueTracked -Path $path -Name $ExePath -Value 'GpuPreference=2;' -Type String -BackupState $BackupState

    Write-Log "GPU de alto rendimiento asignada a '$ExePath' (ajuste valido para cualquier fabricante; en equipos con GPU integrada + dedicada, fuerza el uso de la dedicada)." -Level OK
}

function Show-GpuVendorRecommendations {
    $vendors = Get-GpuVendors

    if ($vendors.Names.Count -eq 0) {
        Write-Log "No se pudo detectar el fabricante de GPU en este equipo (WMI sin datos); se omiten recomendaciones especificas de panel de control." -Level WARN
        return
    }

    Write-Log "GPU(s) detectada(s): $($vendors.Names -join ', ')" -Level INFO

    if ($vendors.Nvidia) {
        Write-Log "Recomendado manual (NVIDIA Control Panel): Administrar configuracion 3D > pestana Programa > League of Legends.exe > Modo de administracion de energia = 'Preferir maximo rendimiento'." -Level INFO
    }
    if ($vendors.Amd) {
        Write-Log "Recomendado manual (AMD Software / Radeon Settings): Graficos > League of Legends > Perfil grafico = 'Rendimiento estandar' o 'Rendimiento' (evitar 'Ahorro de energia'), y Radeon Chill desactivado para este juego." -Level INFO
    }
    if ($vendors.Intel) {
        Write-Log "Recomendado manual (Intel Graphics Command Center, o el panel clasico 'Intel Graphics Control Panel' en equipos que no tengan la app moderna): System > Power > Plugged in = 'Maximum Performance' (o 3D > Application Optimal Mode = Performance en el panel clasico)." -Level INFO
        if (-not $vendors.Nvidia -and -not $vendors.Amd) {
            Write-Log "Este equipo solo tiene GPU integrada Intel: el mayor margen de mejora ya viene de los ajustes de energia/MMCSS/servicios aplicados antes, ya que el rendimiento de la iGPU depende directamente del presupuesto termico/energetico de la CPU." -Level INFO
        }
    }
    if (-not $vendors.Nvidia -and -not $vendors.Amd -and -not $vendors.Intel) {
        Write-Log "Fabricante de GPU no reconocido automaticamente ($($vendors.Names -join ', ')); revisa el panel de control de tu tarjeta grafica para poner el modo de rendimiento en maximo." -Level INFO
    }
}

Export-ModuleMember -Function *
