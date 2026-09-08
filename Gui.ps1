<#
.SYNOPSIS
    Interfaz grafica (WinForms) para el optimizador de FPS de League of Legends.

.DESCRIPTION
    Se autoeleva a Administrador si hace falta. Ejecuta Optimize-LoL.ps1 /
    Restore-LoL.ps1 / los scripts de benchmark como trabajos en segundo plano
    y muestra el log en vivo.
#>
[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = $PSScriptRoot

function Test-IsAdminLocal {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdminLocal)) {
    $psExe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -WindowStyle Minimized
    exit
}

Import-Module (Join-Path $root "modules\Common.psm1") -Force

# ---------------- Formulario ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Optimizador de FPS - League of Legends"
$form.Size = New-Object System.Drawing.Size(650, 560)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 15)
$statusLabel.Size = New-Object System.Drawing.Size(600, 20)
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($statusLabel)

function Update-StatusLabel {
    if (Test-Path (Get-BackupFilePath)) {
        $statusLabel.Text = "Estado: OPTIMIZADO (hay cambios activos sin restaurar)"
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    else {
        $statusLabel.Text = "Estado: sin optimizar"
        $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    }
}
Update-StatusLabel

$chkServices = New-Object System.Windows.Forms.CheckBox
$chkServices.Text = "Pausar servicios en segundo plano (SysMain, DiagTrack)"
$chkServices.Location = New-Object System.Drawing.Point(20, 50)
$chkServices.Size = New-Object System.Drawing.Size(580, 20)
$chkServices.Checked = $true
$form.Controls.Add($chkServices)

$chkNetwork = New-Object System.Windows.Forms.CheckBox
$chkNetwork.Text = "Ajustes de red (Nagle + politica de QoS)"
$chkNetwork.Location = New-Object System.Drawing.Point(20, 75)
$chkNetwork.Size = New-Object System.Drawing.Size(580, 20)
$chkNetwork.Checked = $true
$form.Controls.Add($chkNetwork)

$chkAggressive = New-Object System.Windows.Forms.CheckBox
$chkAggressive.Text = "Prioridad de proceso agresiva (High en vez de AboveNormal)"
$chkAggressive.Location = New-Object System.Drawing.Point(20, 100)
$chkAggressive.Size = New-Object System.Drawing.Size(580, 20)
$form.Controls.Add($chkAggressive)

$chkWaitProcess = New-Object System.Windows.Forms.CheckBox
$chkWaitProcess.Text = "Esperar a que abras League (hasta 5 min) para ajustar su prioridad"
$chkWaitProcess.Location = New-Object System.Drawing.Point(20, 125)
$chkWaitProcess.Size = New-Object System.Drawing.Size(580, 20)
$form.Controls.Add($chkWaitProcess)

$btnOptimize = New-Object System.Windows.Forms.Button
$btnOptimize.Text = "Optimizar"
$btnOptimize.Location = New-Object System.Drawing.Point(20, 160)
$btnOptimize.Size = New-Object System.Drawing.Size(120, 35)
$form.Controls.Add($btnOptimize)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "Restaurar"
$btnRestore.Location = New-Object System.Drawing.Point(150, 160)
$btnRestore.Size = New-Object System.Drawing.Size(120, 35)
$form.Controls.Add($btnRestore)

$lblBenchmarkHelp = New-Object System.Windows.Forms.Label
$lblBenchmarkHelp.Text = "Medir la mejora real (opcional): PresentMon es una herramienta oficial (de Intel) que registra el FPS real de tu partida. Orden sugerido: (1) Descargar PresentMon  ->  (2) Medir 'Antes' jugando SIN optimizar todavia  ->  (3) click en Optimizar (arriba)  ->  (4) Medir 'Despues' ya optimizado  ->  (5) Comparar resultados."
$lblBenchmarkHelp.Location = New-Object System.Drawing.Point(20, 200)
$lblBenchmarkHelp.Size = New-Object System.Drawing.Size(600, 45)
$lblBenchmarkHelp.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$lblBenchmarkHelp.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblBenchmarkHelp)

$btnPresentMon = New-Object System.Windows.Forms.Button
$btnPresentMon.Text = "1. Descargar PresentMon"
$btnPresentMon.Location = New-Object System.Drawing.Point(20, 250)
$btnPresentMon.Size = New-Object System.Drawing.Size(140, 35)
$form.Controls.Add($btnPresentMon)

$btnMeasureBefore = New-Object System.Windows.Forms.Button
$btnMeasureBefore.Text = "2. Medir 'Antes'"
$btnMeasureBefore.Location = New-Object System.Drawing.Point(170, 250)
$btnMeasureBefore.Size = New-Object System.Drawing.Size(140, 35)
$form.Controls.Add($btnMeasureBefore)

$btnMeasureAfter = New-Object System.Windows.Forms.Button
$btnMeasureAfter.Text = "4. Medir 'Despues'"
$btnMeasureAfter.Location = New-Object System.Drawing.Point(320, 250)
$btnMeasureAfter.Size = New-Object System.Drawing.Size(140, 35)
$form.Controls.Add($btnMeasureAfter)

$btnCompare = New-Object System.Windows.Forms.Button
$btnCompare.Text = "5. Comparar"
$btnCompare.Location = New-Object System.Drawing.Point(470, 250)
$btnCompare.Size = New-Object System.Drawing.Size(140, 35)
$form.Controls.Add($btnCompare)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::Black
$txtLog.ForeColor = [System.Drawing.Color]::LightGray
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Location = New-Object System.Drawing.Point(20, 295)
$txtLog.Size = New-Object System.Drawing.Size(595, 215)
$form.Controls.Add($txtLog)

$allButtons = @($btnOptimize, $btnRestore, $btnPresentMon, $btnMeasureBefore, $btnMeasureAfter, $btnCompare)

$script:currentJob = $null
$script:currentTaskName = $null
$script:logLength = 0
$logPath = Join-Path $root "state\optimizer.log"

function Start-Task {
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList, [string]$TaskName = '')

    if ($script:currentJob) {
        [System.Windows.Forms.MessageBox]::Show("Ya hay una tarea en ejecucion. Espera a que termine.", "Optimizador") | Out-Null
        return
    }

    foreach ($b in $allButtons) { $b.Enabled = $false }
    $script:logLength = if (Test-Path $logPath) { (Get-Content $logPath -Raw -ErrorAction SilentlyContinue).Length } else { 0 }
    $script:currentTaskName = $TaskName
    $script:currentJob = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
        if (Test-Path $logPath) {
            $content = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Length -gt $script:logLength) {
                $txtLog.AppendText($content.Substring($script:logLength))
                $script:logLength = $content.Length
            }
        }

        if ($script:currentJob -and $script:currentJob.State -ne 'Running') {
            $jobState = $script:currentJob.State
            $out = Receive-Job -Job $script:currentJob -ErrorAction SilentlyContinue
            if ($out) { $txtLog.AppendText(($out | Out-String)) }
            Remove-Job -Job $script:currentJob -ErrorAction SilentlyContinue
            $finishedTask = $script:currentTaskName
            $script:currentJob = $null
            $script:currentTaskName = $null
            foreach ($b in $allButtons) { $b.Enabled = $true }
            Update-StatusLabel

            if ($finishedTask -eq 'PresentMon') {
                if ($jobState -eq 'Completed') {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Que es PresentMon: una herramienta oficial (de Intel, open-source) que mide el FPS real de tu partida, para poder comparar objetivamente el antes/despues de optimizar." + [Environment]::NewLine + [Environment]::NewLine +
                        "Ya se descargo. Proximo paso:" + [Environment]::NewLine +
                        "1) Click en '2. Medir Antes' y juega una partida SIN optimizar todavia (asi capturas la linea base)." + [Environment]::NewLine +
                        "2) Click en 'Optimizar' (arriba)." + [Environment]::NewLine +
                        "3) Juega otra partida con '4. Medir Despues'." + [Environment]::NewLine +
                        "4) Click en '5. Comparar' para ver si realmente mejoro (FPS, 1% low, jitter).",
                        "PresentMon listo"
                    ) | Out-Null
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("La descarga de PresentMon no se completo correctamente. Revisa el log de abajo para el detalle del error (por ejemplo, sin conexion a internet).", "PresentMon") | Out-Null
                }
            }
        }
    })
$timer.Start()

$btnOptimize.Add_Click({
        $sb = {
            param($scriptPath, $skipServices, $skipNetwork, $aggressive, $waitProcess)
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
            & $scriptPath -SkipServices:$skipServices -SkipNetwork:$skipNetwork -Aggressive:$aggressive -SkipProcessWait:(-not $waitProcess)
        }
        Start-Task -TaskName 'Optimize' -ScriptBlock $sb -ArgumentList @(
            (Join-Path $root "Optimize-LoL.ps1"),
            (-not $chkServices.Checked),
            (-not $chkNetwork.Checked),
            $chkAggressive.Checked,
            $chkWaitProcess.Checked
        )
    })

$btnRestore.Add_Click({
        $sb = {
            param($scriptPath)
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
            & $scriptPath
        }
        Start-Task -TaskName 'Restore' -ScriptBlock $sb -ArgumentList @((Join-Path $root "Restore-LoL.ps1"))
    })

$btnPresentMon.Add_Click({
        $sb = {
            param($scriptPath)
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
            & $scriptPath
        }
        Start-Task -TaskName 'PresentMon' -ScriptBlock $sb -ArgumentList @((Join-Path $root "benchmark\Get-PresentMon.ps1"))
    })

$btnMeasureBefore.Add_Click({
        if (-not (Get-ChildItem -Path (Join-Path $root "tools\PresentMon") -Recurse -Filter 'PresentMon*.exe' -ErrorAction SilentlyContinue)) {
            [System.Windows.Forms.MessageBox]::Show("Primero necesitas descargar PresentMon: click en '1. Descargar PresentMon'.", "Falta PresentMon") | Out-Null
            return
        }
        [System.Windows.Forms.MessageBox]::Show("Se abrira una ventana de consola aparte que va a esperar a que abras League of Legends y luego grabar tu FPS real durante la partida (no interfiere con el juego)." + [Environment]::NewLine + [Environment]::NewLine + "Juega una partida CON NORMALIDAD, SIN optimizar todavia -- esta es tu linea base. La captura se detiene sola cuando cierres el juego.", "Medir 'Antes' (linea base)") | Out-Null
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$(Join-Path $root 'benchmark\Measure-Session.ps1')`" -Label antes"
    })

$btnMeasureAfter.Add_Click({
        if (-not (Test-Path (Get-BackupFilePath))) {
            [System.Windows.Forms.MessageBox]::Show("Todavia no aplicaste la optimizacion. Click en 'Optimizar' (arriba) antes de medir 'Despues', si no vas a comparar dos partidas sin optimizar.", "Sin optimizar") | Out-Null
        }
        [System.Windows.Forms.MessageBox]::Show("Se abrira una ventana de consola aparte que va a esperar a que abras League of Legends y luego grabar tu FPS real durante la partida." + [Environment]::NewLine + [Environment]::NewLine + "Juega otra partida, ya con la optimizacion aplicada. La captura se detiene sola cuando cierres el juego.", "Medir 'Despues'") | Out-Null
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$(Join-Path $root 'benchmark\Measure-Session.ps1')`" -Label despues"
    })

$btnCompare.Add_Click({
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$(Join-Path $root 'benchmark\Compare-Sessions.ps1')`""
    })

$form.Add_FormClosing({
        if ($script:currentJob) {
            Stop-Job -Job $script:currentJob -ErrorAction SilentlyContinue
            Remove-Job -Job $script:currentJob -Force -ErrorAction SilentlyContinue
        }
        $timer.Stop()
    })

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
