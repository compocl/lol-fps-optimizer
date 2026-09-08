<#
.SYNOPSIS
    Bootstrap: descarga el optimizador de FPS de League of Legends y abre su
    interfaz grafica. Pensado para ejecutarse como:

    irm https://raw.githubusercontent.com/compocl/lol-fps-optimizer/main/install.ps1 | iex

.DESCRIPTION
    No requiere admin para descargar (solo copia archivos a %LOCALAPPDATA%);
    Gui.ps1 se autoeleva por su cuenta cuando hace falta.
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$owner = "compocl"
$repo = "lol-fps-optimizer"
$branch = "main"
$installDir = Join-Path $env:LOCALAPPDATA $repo

Write-Host "=== Optimizador de FPS para League of Legends ===" -ForegroundColor Cyan
Write-Host "Descargando $repo desde GitHub..."

$zipUrl = "https://github.com/$owner/$repo/archive/refs/heads/$branch.zip"
$zipPath = Join-Path $env:TEMP "$repo.zip"
$extractTemp = Join-Path $env:TEMP "$repo-extract-$([guid]::NewGuid().ToString('N'))"

Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $extractTemp -Force

$extractedFolder = Get-ChildItem $extractTemp -Directory | Select-Object -First 1
if (-not $extractedFolder) { throw "No se pudo extraer el contenido descargado." }

if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
Move-Item $extractedFolder.FullName $installDir

Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Instalado en: $installDir" -ForegroundColor Green
Write-Host "Iniciando interfaz grafica (te pedira permisos de Administrador)..." -ForegroundColor Cyan

& (Join-Path $installDir "Gui.ps1")
