# Ajustes de GPU. Nos limitamos a la preferencia oficial de Windows para
# forzar el uso de la GPU dedicada (evita que un laptop con GPU integrada +
# dedicada corra el juego en la integrada). No se automatiza el NVIDIA
# Control Panel en si: requiere su API privada/COM o una herramienta de
# terceros (ej. NVIDIA Profile Inspector) que no fue autorizada para
# descargar en este proyecto; se documenta como paso manual recomendado.

Import-Module (Join-Path $PSScriptRoot "Common.psm1") -Force

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

    Write-Log "GPU de alto rendimiento (dedicada) asignada a '$ExePath'." -Level OK
    Write-Log "Recomendado manual: en NVIDIA Control Panel > Administrar configuracion 3D > Modo de administracion de energia, selecciona 'Preferir maximo rendimiento' para League of Legends.exe." -Level INFO
}

Export-ModuleMember -Function *
