# Funciones compartidas: elevacion, logging y manejo del respaldo de estado
# usado para poder revertir TODOS los cambios que aplica el optimizador.

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        throw "Este script requiere privilegios de administrador. Abre PowerShell como Administrador y vuelve a ejecutarlo."
    }
}

function Get-ProjectRoot {
    Resolve-Path (Join-Path $PSScriptRoot "..")
}

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    $color = switch ($Level) {
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        'OK' { 'Green' }
        default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color

    $stateDir = Join-Path (Get-ProjectRoot) "state"
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    Add-Content -Path (Join-Path $stateDir "optimizer.log") -Value $line
}

function Get-BackupFilePath {
    Join-Path (Get-ProjectRoot) "state\backup.json"
}

function New-BackupState {
    [ordered]@{
        CreatedAt        = (Get-Date).ToString('o')
        PowerScheme      = $null
        Services         = [ordered]@{}
        RegistryValues   = @()
        QosPolicies      = @()
    }
}

function Save-BackupState {
    param([Parameter(Mandatory)] $State)
    $path = Get-BackupFilePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
}

function Load-BackupState {
    $path = Get-BackupFilePath
    if (-not (Test-Path $path)) { return $null }
    Get-Content $path -Raw | ConvertFrom-Json
}

function Remove-BackupState {
    $path = Get-BackupFilePath
    if (Test-Path $path) { Remove-Item $path -Force }
}

# Aplica un valor de registro y deja constancia del valor/estado original
# (incluyendo si la clave no existia) para poder revertirlo despues.
function Set-RegistryValueTracked {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] $Value,
        [Parameter(Mandatory)] [Microsoft.Win32.RegistryValueKind]$Type,
        [Parameter(Mandatory)] $BackupState
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    $existed = $null -ne $existing

    $BackupState.RegistryValues += [ordered]@{
        Path          = $Path
        Name          = $Name
        Existed       = $existed
        OriginalValue = if ($existed) { $existing.$Name } else { $null }
        OriginalType  = if ($existed) { (Get-Item $Path).GetValueKind($Name).ToString() } else { $Type.ToString() }
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Restore-RegistryValues {
    param([Parameter(Mandatory)] $Entries)
    foreach ($entry in $Entries) {
        try {
            if ($entry.Existed) {
                $kind = [Microsoft.Win32.RegistryValueKind]::Parse([Microsoft.Win32.RegistryValueKind], $entry.OriginalType)
                New-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.OriginalValue -PropertyType $kind -Force | Out-Null
            }
            else {
                Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log "No se pudo restaurar $($entry.Path)\$($entry.Name): $_" -Level WARN
        }
    }
}

Export-ModuleMember -Function *
