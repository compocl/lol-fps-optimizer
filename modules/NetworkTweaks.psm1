# Ajustes de red: deshabilitar el algoritmo de Nagle (reduce latencia en
# paquetes pequenos, tipico de juegos como LoL) y una politica de QoS local
# que prioriza el trafico de League of Legends.exe.
#
# Nota: NO se modifica el DNS del sistema por defecto -- es un cambio que
# afecta a todo el equipo (no solo al juego) y se considero fuera de alcance
# sin una decision explicita del usuario.

Import-Module (Join-Path $PSScriptRoot "Common.psm1") -Force

function Disable-NagleAlgorithm {
    param([Parameter(Mandatory)] $BackupState)

    $interfacesRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    if (-not (Test-Path $interfacesRoot)) {
        Write-Log "No se encontro la clave de interfaces TCP/IP; se omite el ajuste de Nagle." -Level WARN
        return
    }

    $activeInterfaces = Get-ChildItem $interfacesRoot | Where-Object {
        (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'DhcpIPAddress' -or
        (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains 'IPAddress'
    }

    if (-not $activeInterfaces) {
        Write-Log "No se detectaron interfaces de red activas; se omite el ajuste de Nagle." -Level WARN
        return
    }

    foreach ($iface in $activeInterfaces) {
        Set-RegistryValueTracked -Path $iface.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord -BackupState $BackupState
        Set-RegistryValueTracked -Path $iface.PSPath -Name 'TCPNoDelay' -Value 1 -Type DWord -BackupState $BackupState
    }

    Write-Log "Algoritmo de Nagle deshabilitado en $($activeInterfaces.Count) interfaz(ces) de red activa(s)." -Level OK
}

function Set-QosPolicyForLeague {
    param([Parameter(Mandatory)] $BackupState)

    if (-not (Get-Command New-NetQosPolicy -ErrorAction SilentlyContinue)) {
        Write-Log "El modulo de QoS de red no esta disponible en este sistema; se omite la politica de QoS." -Level WARN
        return
    }

    $policyName = 'LoL-FPS-Optimizer'
    try {
        Get-NetQosPolicy -Name $policyName -ErrorAction SilentlyContinue | Remove-NetQosPolicy -Confirm:$false -ErrorAction SilentlyContinue

        New-NetQosPolicy -Name $policyName `
            -AppPathNameMatchCondition 'League of Legends.exe' `
            -DSCPAction 46 `
            -NetworkProfile All `
            -ErrorAction Stop | Out-Null

        $BackupState.QosPolicies += $policyName
        Write-Log "Politica de QoS '$policyName' creada para priorizar el trafico del juego." -Level OK
    }
    catch {
        Write-Log "No se pudo crear la politica de QoS (puede requerir Windows Pro/Enterprise): $_" -Level WARN
    }
}

function Remove-QosPolicies {
    param([Parameter(Mandatory)] $Names)

    foreach ($name in $Names) {
        try {
            Get-NetQosPolicy -Name $name -ErrorAction SilentlyContinue | Remove-NetQosPolicy -Confirm:$false -ErrorAction Stop
            Write-Log "Politica de QoS '$name' eliminada." -Level OK
        }
        catch {
            Write-Log "No se pudo eliminar la politica de QoS '$name': $_" -Level WARN
        }
    }
}

Export-ModuleMember -Function *
