<#
.SYNOPSIS
    Revierte todos los cambios aplicados por Optimize-LoL.ps1, usando el
    respaldo guardado en state\backup.json.

.DESCRIPTION
    Requiere ejecutarse como Administrador. Es seguro ejecutarlo aunque
    Optimize-LoL.ps1 haya fallado a medias: solo revierte lo que quedo
    registrado en el respaldo.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot "modules\Common.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\SystemTweaks.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\NetworkTweaks.psm1") -Force

Assert-Admin

$state = Load-BackupState
if (-not $state) {
    Write-Log "No hay ningun respaldo que restaurar (state\backup.json no existe). Nada que hacer." -Level WARN
    return
}

Write-Log "=== Restaurando configuracion original ===" -Level INFO

if ($state.PowerScheme) {
    Write-Log "Restaurando plan de energia original..."
    Restore-PowerScheme -OriginalGuid $state.PowerScheme
}

if ($state.Services -and $state.Services.PSObject.Properties.Count -gt 0) {
    Write-Log "Restaurando servicios en segundo plano..."
    Restore-BackgroundServices -ServicesBackup $state.Services
}

if ($state.RegistryValues -and $state.RegistryValues.Count -gt 0) {
    Write-Log "Restaurando valores de registro modificados..."
    Restore-RegistryValues -Entries $state.RegistryValues
}

if ($state.QosPolicies -and $state.QosPolicies.Count -gt 0) {
    Write-Log "Eliminando politicas de QoS creadas..."
    Remove-QosPolicies -Names $state.QosPolicies
}

Remove-BackupState
Write-Log "=== Restauracion completada. Todo quedo como estaba antes de optimizar. ===" -Level OK
