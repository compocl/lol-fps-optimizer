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

$btnPresentMon = New-Object System.Windows.Forms.Button
$btnPresentMon.Text = "Descargar PresentMon"
$btnPresentMon.Location = New-Object System.Drawing.Point(280, 160)
$btnPresentMon.Size = New-Object System.Drawing.Size(160, 35)
$form.Controls.Add($btnPresentMon)

$btnMeasureBefore = New-Object System.Windows.Forms.Button
$btnMeasureBefore.Text = "Medir 'Antes'"
$btnMeasureBefore.Location = New-Object System.Drawing.Point(20, 205)
$btnMeasureBefore.Size = New-Object System.Drawing.Size(120, 35)
$form.Controls.Add($btnMeasureBefore)

$btnMeasureAfter = New-Object System.Windows.Forms.Button
$btnMeasureAfter.Text = "Medir 'Despues'"
$btnMeasureAfter.Location = New-Object System.Drawing.Point(150, 205)
$btnMeasureAfter.Size = New-Object System.Drawing.Size(120, 35)
$form.Controls.Add($btnMeasureAfter)

$btnCompare = New-Object System.Windows.Forms.Button
$btnCompare.Text = "Comparar resultados"
$btnCompare.Location = New-Object System.Drawing.Point(280, 205)
$btnCompare.Size = New-Object System.Drawing.Size(160, 35)
$form.Controls.Add($btnCompare)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::Black
$txtLog.ForeColor = [System.Drawing.Color]::LightGray
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Location = New-Object System.Drawing.Point(20, 250)
$txtLog.Size = New-Object System.Drawing.Size(595, 260)
$form.Controls.Add($txtLog)

$allButtons = @($btnOptimize, $btnRestore, $btnPresentMon, $btnMeasureBefore, $btnMeasureAfter, $btnCompare)

$script:currentJob = $null
$script:logLength = 0
$logPath = Join-Path $root "state\optimizer.log"

function Start-Task {
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList)

    if ($script:currentJob) {
        [System.Windows.Forms.MessageBox]::Show("Ya hay una tarea en ejecucion. Espera a que termine.", "Optimizador") | Out-Null
        return
    }

    foreach ($b in $allButtons) { $b.Enabled = $false }
    $script:logLength = if (Test-Path $logPath) { (Get-Content $logPath -Raw -ErrorAction SilentlyContinue).Length } else { 0 }
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
            $out = Receive-Job -Job $script:currentJob -ErrorAction SilentlyContinue
            if ($out) { $txtLog.AppendText(($out | Out-String)) }
            Remove-Job -Job $script:currentJob -ErrorAction SilentlyContinue
            $script:currentJob = $null
            foreach ($b in $allButtons) { $b.Enabled = $true }
            Update-StatusLabel
        }
    })
$timer.Start()

$btnOptimize.Add_Click({
        $sb = {
            param($scriptPath, $skipServices, $skipNetwork, $aggressive, $waitProcess)
            & $scriptPath -SkipServices:$skipServices -SkipNetwork:$skipNetwork -Aggressive:$aggressive -SkipProcessWait:(-not $waitProcess)
        }
        Start-Task -ScriptBlock $sb -ArgumentList @(
            (Join-Path $root "Optimize-LoL.ps1"),
            (-not $chkServices.Checked),
            (-not $chkNetwork.Checked),
            $chkAggressive.Checked,
            $chkWaitProcess.Checked
        )
    })

$btnRestore.Add_Click({
        $sb = { param($scriptPath) & $scriptPath }
        Start-Task -ScriptBlock $sb -ArgumentList @((Join-Path $root "Restore-LoL.ps1"))
    })

$btnPresentMon.Add_Click({
        $sb = { param($scriptPath) & $scriptPath }
        Start-Task -ScriptBlock $sb -ArgumentList @((Join-Path $root "benchmark\Get-PresentMon.ps1"))
    })

$btnMeasureBefore.Add_Click({
        [System.Windows.Forms.MessageBox]::Show("Se abrira una ventana de consola. Juega tu partida con normalidad; la captura se detiene sola al cerrar el juego.", "Medir 'Antes'") | Out-Null
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$(Join-Path $root 'benchmark\Measure-Session.ps1')`" -Label antes"
    })

$btnMeasureAfter.Add_Click({
        [System.Windows.Forms.MessageBox]::Show("Se abrira una ventana de consola. Juega tu partida con normalidad; la captura se detiene sola al cerrar el juego.", "Medir 'Despues'") | Out-Null
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
