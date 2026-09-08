<#
.SYNOPSIS
    Captura FPS/frame time de una sesion de juego con PresentMon y la guarda
    en un CSV etiquetado, para comparar "antes" vs "despues" de optimizar.

.DESCRIPTION
    Ejecuta primero benchmark\Get-PresentMon.ps1 una vez para descargar la
    herramienta. Este script espera a que el proceso de League este corriendo,
    inicia la captura, y la detiene automaticamente cuando el proceso se
    cierra (o al llegar a -DurationSeconds si se especifica).

.PARAMETER Label
    'antes' o 'despues'. Se usa para nombrar el archivo de salida.

.EXAMPLE
    .\Measure-Session.ps1 -Label antes
    Corre esto ANTES de aplicar Optimize-LoL.ps1, jugando una partida normal.

.EXAMPLE
    .\Measure-Session.ps1 -Label despues
    Corre esto DESPUES de aplicar Optimize-LoL.ps1, jugando otra partida.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('antes', 'despues')] [string]$Label,
    [string]$ProcessName = "League of Legends",
    [int]$DurationSeconds = 0,
    [string]$LogsDir = (Join-Path $PSScriptRoot "..\logs")
)

$ErrorActionPreference = 'Stop'

$presentMonExe = Get-ChildItem -Path (Join-Path $PSScriptRoot "..\tools\PresentMon") -Recurse -Filter 'PresentMon*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $presentMonExe) {
    throw "No se encontro PresentMon. Ejecuta primero: .\benchmark\Get-PresentMon.ps1"
}

if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $LogsDir "$Label-$timestamp.csv"

Write-Host "Captura '$Label' lista. Esperando a que '$ProcessName' este en ejecucion..."
$proc = $null
while (-not $proc) {
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) { Start-Sleep -Seconds 2 }
}
Write-Host "Proceso detectado (PID $($proc.Id)). Iniciando captura -> $outFile" -ForegroundColor Green

$argList = @('--process_name', "$ProcessName.exe", '--output_file', $outFile, '--terminate_on_proc_exit')
if ($DurationSeconds -gt 0) { $argList += @('--timed', $DurationSeconds) }

Write-Host "Juega tu partida con normalidad. La captura se detendra sola cuando cierres el juego"
if ($DurationSeconds -gt 0) { Write-Host "(o a los $DurationSeconds segundos)." } else { Write-Host "(o presiona Ctrl+C para detenerla antes)." }

& $presentMonExe.FullName @argList

if (Test-Path $outFile) {
    Write-Host "Captura guardada en: $outFile" -ForegroundColor Green
}
else {
    Write-Host "PresentMon termino pero no se genero el archivo esperado; revisa la salida de arriba." -ForegroundColor Yellow
}
