<#
.SYNOPSIS
    Compara dos capturas de PresentMon (antes/despues) y evalua si la
    fluidez realmente mejoro: FPS promedio, 1% low / 0.1% low (los frames
    mas lentos, que es lo que se siente como "tiron"), y la variabilidad del
    frame time (jitter).

.DESCRIPTION
    Si no se especifican -BeforeFile/-AfterFile, usa automaticamente el
    archivo 'antes-*.csv' y 'despues-*.csv' mas reciente de la carpeta logs.

.EXAMPLE
    .\Compare-Sessions.ps1
#>
[CmdletBinding()]
param(
    [string]$BeforeFile,
    [string]$AfterFile,
    [string]$LogsDir = (Join-Path $PSScriptRoot "..\logs")
)

$ErrorActionPreference = 'Stop'

function Get-LatestFile {
    param([string]$Pattern)
    Get-ChildItem -Path $LogsDir -Filter $Pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

if (-not $BeforeFile) {
    $f = Get-LatestFile -Pattern 'antes-*.csv'
    if (-not $f) { throw "No se encontro ninguna captura 'antes'. Corre primero: .\Measure-Session.ps1 -Label antes" }
    $BeforeFile = $f.FullName
}
if (-not $AfterFile) {
    $f = Get-LatestFile -Pattern 'despues-*.csv'
    if (-not $f) { throw "No se encontro ninguna captura 'despues'. Corre primero: .\Measure-Session.ps1 -Label despues" }
    $AfterFile = $f.FullName
}

function Get-SessionStats {
    param([string]$Path)

    $rows = Import-Csv -Path $Path
    if (-not $rows -or -not ($rows[0].PSObject.Properties.Name -contains 'MsBetweenPresents')) {
        throw "El archivo '$Path' no tiene la columna esperada 'MsBetweenPresents'. Verifica que sea un CSV de PresentMon valido."
    }

    $frameTimes = $rows | ForEach-Object { [double]$_.MsBetweenPresents } | Where-Object { $_ -gt 0 }
    if ($frameTimes.Count -lt 10) {
        throw "El archivo '$Path' no tiene suficientes muestras validas para un analisis confiable (minimo 10)."
    }

    $count = $frameTimes.Count
    $avgFrameTime = ($frameTimes | Measure-Object -Average).Average
    $avgFps = 1000.0 / $avgFrameTime

    $sortedDesc = $frameTimes | Sort-Object -Descending
    $onePercentCount = [Math]::Max(1, [Math]::Ceiling($count * 0.01))
    $pointOnePercentCount = [Math]::Max(1, [Math]::Ceiling($count * 0.001))
    $onePercentLowFps = 1000.0 / (($sortedDesc | Select-Object -First $onePercentCount | Measure-Object -Average).Average)
    $pointOnePercentLowFps = 1000.0 / (($sortedDesc | Select-Object -First $pointOnePercentCount | Measure-Object -Average).Average)

    $variance = (($frameTimes | ForEach-Object { [Math]::Pow($_ - $avgFrameTime, 2) }) | Measure-Object -Sum).Sum / $count
    $stdevFrameTime = [Math]::Sqrt($variance)
    $maxFrameTime = ($frameTimes | Measure-Object -Maximum).Maximum

    [ordered]@{
        File               = Split-Path $Path -Leaf
        Samples            = $count
        AvgFps             = [Math]::Round($avgFps, 1)
        OnePercentLowFps   = [Math]::Round($onePercentLowFps, 1)
        PointOnePercentLowFps = [Math]::Round($pointOnePercentLowFps, 1)
        FrameTimeStdevMs   = [Math]::Round($stdevFrameTime, 2)
        MaxFrameTimeMs     = [Math]::Round($maxFrameTime, 2)
    }
}

$before = Get-SessionStats -Path $BeforeFile
$after = Get-SessionStats -Path $AfterFile

function Format-Delta {
    param([double]$From, [double]$To, [switch]$LowerIsBetter)
    $delta = $To - $From
    $pct = if ($From -ne 0) { ($delta / $From) * 100 } else { 0 }
    $better = if ($LowerIsBetter) { $delta -lt 0 } else { $delta -gt 0 }
    $sign = if ($delta -ge 0) { '+' } else { '' }
    $arrow = if ($better) { 'mejora' } else { 'empeora' }
    "$sign$([Math]::Round($delta,2)) ($sign$([Math]::Round($pct,1))%) -> $arrow"
}

Write-Host ""
Write-Host "=== Comparacion de sesiones ===" -ForegroundColor Cyan
Write-Host ("{0,-24} {1,15} {2,15} {3,25}" -f "Metrica", "Antes", "Despues", "Cambio")
Write-Host ("{0,-24} {1,15} {2,15} {3,25}" -f "FPS promedio", $before.AvgFps, $after.AvgFps, (Format-Delta $before.AvgFps $after.AvgFps))
Write-Host ("{0,-24} {1,15} {2,15} {3,25}" -f "1% low (FPS)", $before.OnePercentLowFps, $after.OnePercentLowFps, (Format-Delta $before.OnePercentLowFps $after.OnePercentLowFps))
Write-Host ("{0,-24} {1,15} {2,15} {3,25}" -f "0.1% low (FPS)", $before.PointOnePercentLowFps, $after.PointOnePercentLowFps, (Format-Delta $before.PointOnePercentLowFps $after.PointOnePercentLowFps))
Write-Host ("{0,-24} {1,15} {2,15} {3,25}" -f "Jitter (stdev ms)", $before.FrameTimeStdevMs, $after.FrameTimeStdevMs, (Format-Delta $before.FrameTimeStdevMs $after.FrameTimeStdevMs -LowerIsBetter))
Write-Host ("{0,-24} {1,15} {2,15} {3,25}" -f "Peor frame (ms)", $before.MaxFrameTimeMs, $after.MaxFrameTimeMs, (Format-Delta $before.MaxFrameTimeMs $after.MaxFrameTimeMs -LowerIsBetter))
Write-Host ""

# El 1% low y el jitter son los que mas se correlacionan con la sensacion de
# "tiron"/stutter; el FPS promedio solo no lo captura bien.
$onePercentImproved = $after.OnePercentLowFps -gt $before.OnePercentLowFps
$jitterImproved = $after.FrameTimeStdevMs -lt $before.FrameTimeStdevMs
$avgImproved = $after.AvgFps -gt $before.AvgFps

if ($onePercentImproved -and $jitterImproved) {
    $verdict = "MEJORA CLARA: menos tirones (1% low mas alto) y mas estabilidad (menos jitter)."
    $color = 'Green'
}
elseif ($onePercentImproved -or $jitterImproved) {
    $verdict = "MEJORA PARCIAL: mejoro un indicador de fluidez pero no el otro. Revisa la tabla."
    $color = 'Yellow'
}
elseif ($avgImproved) {
    $verdict = "SIN MEJORA CLARA EN FLUIDEZ: el FPS promedio subio, pero los tirones (1% low) y/o el jitter no mejoraron. La sensacion de juego puede no haber cambiado."
    $color = 'Yellow'
}
else {
    $verdict = "SIN MEJORA: ningun indicador de fluidez mejoro en esta comparacion."
    $color = 'Red'
}

Write-Host "Veredicto: $verdict" -ForegroundColor $color
Write-Host ""

$reportPath = Join-Path $LogsDir "report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
@"
Comparacion de sesiones - League of Legends FPS Optimizer
Antes:   $($before.File)
Despues: $($after.File)

Metrica                 Antes           Despues         Cambio
FPS promedio            $($before.AvgFps)           $($after.AvgFps)           $(Format-Delta $before.AvgFps $after.AvgFps)
1% low (FPS)             $($before.OnePercentLowFps)           $($after.OnePercentLowFps)           $(Format-Delta $before.OnePercentLowFps $after.OnePercentLowFps)
0.1% low (FPS)           $($before.PointOnePercentLowFps)           $($after.PointOnePercentLowFps)           $(Format-Delta $before.PointOnePercentLowFps $after.PointOnePercentLowFps)
Jitter (stdev ms)        $($before.FrameTimeStdevMs)           $($after.FrameTimeStdevMs)           $(Format-Delta $before.FrameTimeStdevMs $after.FrameTimeStdevMs -LowerIsBetter)
Peor frame (ms)          $($before.MaxFrameTimeMs)           $($after.MaxFrameTimeMs)           $(Format-Delta $before.MaxFrameTimeMs $after.MaxFrameTimeMs -LowerIsBetter)

Veredicto: $verdict
"@ | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "Reporte guardado en: $reportPath"
