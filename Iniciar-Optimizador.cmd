@echo off
rem Doble clic para abrir la GUI sin preocuparte por la politica de ejecucion
rem de PowerShell: el flag -ExecutionPolicy Bypass aqui solo aplica a este
rem proceso, no cambia ninguna configuracion del sistema.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gui.ps1"
