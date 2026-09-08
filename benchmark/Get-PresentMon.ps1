<#
.SYNOPSIS
    Descarga la ultima release oficial de PresentMon (GameTechDev/PresentMon,
    Intel) desde GitHub y la deja lista en tools\PresentMon.

.DESCRIPTION
    PresentMon es la herramienta open-source estandar de la industria para
    medir FPS y frame time desde linea de comandos, usada por benchmarks
    como CapFrameX. Se descarga siempre desde el repositorio oficial.
#>
[CmdletBinding()]
param(
    [string]$DestinationDir = (Join-Path $PSScriptRoot "..\tools\PresentMon")
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$apiUrl = "https://api.github.com/repos/GameTechDev/PresentMon/releases/latest"
$headers = @{ 'User-Agent' = 'LoL-FPS-Optimizer' }

Write-Host "Consultando la ultima version de PresentMon en GitHub..."
$release = Invoke-RestMethod -Uri $apiUrl -Headers $headers

$asset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
if (-not $asset) {
    $asset = $release.assets | Where-Object { $_.name -match '\.exe$' } | Select-Object -First 1
}
if (-not $asset) {
    throw "No se encontro ningun asset descargable en el release $($release.tag_name)."
}

if (-not (Test-Path $DestinationDir)) { New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null }

$downloadPath = Join-Path $DestinationDir $asset.name
Write-Host "Descargando $($asset.name) ($($release.tag_name)) desde el repositorio oficial GameTechDev/PresentMon..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -Headers $headers

if ($downloadPath -like '*.zip') {
    Write-Host "Extrayendo..."
    Expand-Archive -Path $downloadPath -DestinationPath $DestinationDir -Force
}

$exe = Get-ChildItem -Path $DestinationDir -Recurse -Filter 'PresentMon*.exe' | Select-Object -First 1
if (-not $exe) {
    throw "La descarga se completo pero no se encontro el ejecutable de PresentMon tras extraerla."
}

Write-Host "PresentMon listo en: $($exe.FullName)" -ForegroundColor Green
Write-Host "Version: $($release.tag_name)"
