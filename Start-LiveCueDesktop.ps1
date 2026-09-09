[CmdletBinding()]
param([switch]$SelfTest, [string]$EvidencePath, [switch]$AutoStart, [switch]$TestExpanded)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[xml]$layout = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'Desktop.xaml')
$window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $layout))
$ui = @{}
foreach ($name in 'StartButton','StopButton','PauseButton','ClearButton','Status','PhoneStatus','QRCanvas','QRHint','PairButton','HideQRButton','Endpoint','Activity','Transcript','Reply','ResponseTime','TranscriptHint','ShowPairButton','PairingPanel','BrandIcon','PhoneDot','PairFooterButton','ClosePairButton','ActivityPanel','ShowActivityButton','CloseActivityButton','MinimizeButton','MaximizeButton','CloseButton') { $ui[$name] = $window.FindName($name) }
$ui.BrandIcon.Source = [Windows.Media.Imaging.BitmapFrame]::Create([uri](Join-Path $PSScriptRoot 'Assets/LiveCue.png'))
$ui.TranscriptLayout = $window.FindName('TranscriptLayout')
$ui.ReplyLayout = $window.FindName('ReplyLayout')
$window.Add_SizeChanged({
    $window.UpdateLayout()
    $ui.Transcript.MaxHeight = [Math]::Max(36, $ui.TranscriptLayout.RowDefinitions[1].ActualHeight - 130)
    $ui.Reply.MaxHeight = [Math]::Max(36, $ui.ReplyLayout.RowDefinitions[1].ActualHeight - 88)
})
$window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([uri](Join-Path $PSScriptRoot 'Assets/LiveCue.ico'))
$script:relayProcess = $null
$script:readTask = $null
$script:errorTask = $null
$script:lastSeen = $null
$script:paused = $false
$script:qrShownAt = $null
function Add-Activity([string]$text) {
    $ui.Activity.AppendText("`r`n" + $text + "`r`n")
    if ($ui.Activity.Text.Length -gt 200000) { $ui.Activity.Text = "[Older activity removed from memory]`r`n" + $ui.Activity.Text.Substring($ui.Activity.Text.Length - 150000) }
    $ui.Activity.ScrollToEnd()
}
function Send-Control($command) {
    if ($script:relayProcess -and -not $script:relayProcess.HasExited) {
        $script:relayProcess.StandardInput.WriteLine(($command | ConvertTo-Json -Compress)); $script:relayProcess.StandardInput.Flush()
    }
}
function Stop-Relay {
    if ($script:relayProcess) {
        if (-not $script:relayProcess.HasExited) { Send-Control @{action='shutdown'}; if (-not $script:relayProcess.WaitForExit(2500)) { $script:relayProcess.Kill() } }
        $script:relayProcess.Dispose(); $script:relayProcess = $null
    }
    $script:readTask = $null; $script:errorTask = $null; $script:lastSeen = $null
    $ui.Status.Text = 'Stopped'; $ui.PhoneStatus.Text = 'iPhone not connected'
    $ui.PhoneDot.Fill = '#A1B1C8'
    $ui.StartButton.Visibility = 'Visible'; $ui.PauseButton.Visibility = 'Collapsed'
    $ui.StartButton.IsEnabled = $true
    $ui.StopButton.IsEnabled = $false; $ui.PauseButton.IsEnabled = $false; $ui.PairButton.IsEnabled = $false
    $ui.QRCanvas.Children.Clear(); $script:qrShownAt = $null
}
function Handle-Event($event) {
    switch ($event.type) {
        'ready' {
            $ui.StartButton.IsEnabled = $false
            $ui.Status.Text = 'Ready'; $ui.Endpoint.Text = [string]$event.endpoint
            $ui.StartButton.Visibility = 'Collapsed'; $ui.PauseButton.Visibility = 'Visible'
            $ui.StopButton.IsEnabled = $true; $ui.PauseButton.IsEnabled = $true; $ui.PairButton.IsEnabled = $true
            $script:paused = $false; $ui.PauseButton.Content = 'Pause relay'
            Add-Activity 'Relay started. Waiting for your iPhone.'
        }
        'phone-seen' { $script:lastSeen = Get-Date; $ui.PhoneStatus.Text = 'iPhone connected'; $ui.PhoneDot.Fill = '#35B665' }
        'state' {
            $script:paused = -not [bool]$event.accepting
            if ($script:paused) { $ui.Status.Text = 'Paused'; $ui.PauseButton.Content = 'Resume relay' }
            else { $ui.Status.Text = 'Ready'; $ui.PauseButton.Content = 'Pause relay' }
        }
        'pairing' {
            $ui.PairingPanel.Visibility = 'Visible'
            $ui.QRCanvas.Children.Clear()
            $count = $event.modules.Count; $cell = 240.0 / ($count + 8)
            for ($row = 0; $row -lt $count; $row++) { for ($col = 0; $col -lt $count; $col++) {
                if ($event.modules[$row][$col]) {
                    $rect = New-Object Windows.Shapes.Rectangle
                    $rect.Width = $cell + 0.15; $rect.Height = $cell + 0.15; $rect.Fill = [Windows.Media.Brushes]::Black
                    [Windows.Controls.Canvas]::SetLeft($rect, ($col + 4) * $cell); [Windows.Controls.Canvas]::SetTop($rect, ($row + 4) * $cell)
                    $null = $ui.QRCanvas.Children.Add($rect)
                }
            } }
            $script:qrShownAt = Get-Date
            $ui.QRHint.Text = 'On iPhone: Pair Windows PC > Scan PC QR code, then Verify and pair. QR hides after 2 minutes.'
            $ui.Endpoint.Text = [string]$event.endpoint
        }
        'request' {
            $ui.Status.Text = 'Thinking...'
            $ui.Transcript.Text = [string]$event.payload.transcript
            if ($event.payload.partialTranscript) { $ui.Transcript.Text += "`r`n`r`n[In progress] " + [string]$event.payload.partialTranscript }
            if ($event.payload.instruction) { $ui.Transcript.Text += "`r`n`r`nInstruction: " + [string]$event.payload.instruction }
            if (-not $ui.Transcript.Text) { $ui.Transcript.Text = ($event.payload | ConvertTo-Json -Depth 16) }
            $ui.TranscriptHint.Text = if ($event.kind -eq 'summary') { 'Session summary requested' } else { 'Received from your iPhone' }
            $ui.Reply.Text = 'Thinking...'
            $ui.ResponseTime.Text = 'Processing with Codex on your PC'
            Add-Activity ("INCOMING " + $event.kind + ' [' + $event.requestId + "]`r`n" + ($event.payload | ConvertTo-Json -Depth 16))
        }
        'reply' {
            $ui.Reply.Text = [string]$event.payload.answer
            if (-not $ui.Reply.Text) { $ui.Reply.Text = [string]$event.payload.summary }
            if ($event.payload.details) { $ui.Reply.Text += "`r`n`r`n" + [string]$event.payload.details }
            if ($event.payload.keyPoints) { $ui.Reply.Text += "`r`n`r`nKey points`r`n" + ($event.payload.keyPoints -join "`r`n") }
            if ($event.payload.actionItems) { $ui.Reply.Text += "`r`n`r`nAction items`r`n" + ($event.payload.actionItems -join "`r`n") }
            if (-not $ui.Reply.Text) { $ui.Reply.Text = ($event.payload | ConvertTo-Json -Depth 16) }
            $ui.ResponseTime.Text = 'Sent to iPhone  /  ' + ([Math]::Round($event.durationMs / 1000.0, 2)) + ' s'
            $ui.Status.Text = if ($script:paused) { 'Paused' } else { 'Ready' }
            Add-Activity ("REPLY [" + $event.requestId + '] ' + ([Math]::Round($event.durationMs / 1000.0, 2)) + " s`r`n" + ($event.payload | ConvertTo-Json -Depth 16))
        }
        'request-error' { $ui.Status.Text = 'Request failed - ready to retry'; $ui.Reply.Text = [string]$event.message; $ui.ResponseTime.Text = 'Not sent - try Assist again'; Add-Activity ([string]$event.message) }
        'fatal' { $ui.Status.Text = [string]$event.message; Add-Activity ([string]$event.message) }
        'notice' { Add-Activity ([string]$event.message) }
    }
}
function Start-Relay {
    try {
        $ui.StartButton.IsEnabled = $false; $ui.Status.Text = 'Checking Codex and Tailscale...'
        & (Join-Path $PSScriptRoot 'Start-LiveCueRelay.ps1') -CheckOnly | Out-Null
        $tailscalePath = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
        & $tailscalePath serve --bg 47831 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Tailscale HTTPS setup failed. Check that Tailscale is connected.' }
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = (Get-Command node -CommandType Application).Source
        $info.Arguments = '--experimental-strip-types "' + (Join-Path $PSScriptRoot 'Relay\src\desktop.ts') + '"'
        $info.WorkingDirectory = Join-Path $PSScriptRoot 'Relay'
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
        $script:relayProcess = New-Object Diagnostics.Process
        $script:relayProcess.StartInfo = $info
        $null = $script:relayProcess.Start()
        $script:readTask = $script:relayProcess.StandardOutput.ReadLineAsync()
        $script:errorTask = $script:relayProcess.StandardError.ReadLineAsync()
        $ui.Activity.Clear()
    } catch { $ui.Status.Text = $_.Exception.Message; $ui.StartButton.IsEnabled = $true }
}
$ui.StartButton.Add_Click({ Start-Relay })
$ui.StopButton.Add_Click({ Stop-Relay })
$ui.PauseButton.Add_Click({ Send-Control @{action='pause'; paused=(-not $script:paused)} })
$ui.ClearButton.Add_Click({ $ui.Activity.Clear(); $ui.Transcript.Clear(); $ui.Reply.Clear(); $ui.ResponseTime.Text = 'Activity cleared' })
$ui.ShowPairButton.Add_Click({ $ui.PairingPanel.Visibility = 'Visible' })
$ui.PairFooterButton.Add_Click({ $ui.PairingPanel.Visibility = 'Visible' })
$ui.ClosePairButton.Add_Click({ $ui.PairingPanel.Visibility = 'Collapsed' })
$ui.ShowActivityButton.Add_Click({ $ui.ActivityPanel.Visibility = 'Visible' })
$ui.CloseActivityButton.Add_Click({ $ui.ActivityPanel.Visibility = 'Collapsed' })
$ui.MinimizeButton.Add_Click({ $window.WindowState = 'Minimized' })
$ui.MaximizeButton.Add_Click({ $window.WindowState = if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } })
$ui.CloseButton.Add_Click({ $window.Close() })
$window.Add_KeyDown({ if ($_.Key -eq 'Escape') { $ui.PairingPanel.Visibility = 'Collapsed'; $ui.ActivityPanel.Visibility = 'Collapsed' } })
$ui.Status.SetBinding([Windows.FrameworkElement]::ToolTipProperty, (New-Object Windows.Data.Binding 'Text' -Property @{Source=$ui.Status})) | Out-Null
$ui.HideQRButton.Add_Click({ $ui.QRCanvas.Children.Clear(); $script:qrShownAt = $null; $ui.QRHint.Text = 'QR hidden. Existing pairing remains valid.' })
$ui.PairButton.Add_Click({
    if ([Windows.MessageBox]::Show('Generate a new QR? This invalidates the previous pairing token. Re-pair your iPhone afterward.', 'Replace pairing', 'YesNo', 'Question') -eq 'Yes') { Send-Control @{action='pair'} }
})
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    try {
        for ($i = 0; $i -lt 16 -and $script:readTask -and $script:readTask.IsCompleted; $i++) {
            $line = $script:readTask.GetAwaiter().GetResult()
            if ($null -eq $line) { $script:readTask = $null; break }
            Handle-Event ($line | ConvertFrom-Json)
            $script:readTask = $script:relayProcess.StandardOutput.ReadLineAsync()
        }
        if ($script:errorTask -and $script:errorTask.IsCompleted) {
            $line = $script:errorTask.GetAwaiter().GetResult()
            if ($null -ne $line) { Add-Activity ('Relay diagnostic: ' + $line); $script:errorTask = $script:relayProcess.StandardError.ReadLineAsync() }
            else { $script:errorTask = $null }
        }
        if ($script:relayProcess -and $script:relayProcess.HasExited -and -not $script:readTask) {
            $ui.StartButton.IsEnabled = $true; $ui.StopButton.IsEnabled = $false; $ui.PauseButton.IsEnabled = $false; $ui.PairButton.IsEnabled = $false
            $ui.QRCanvas.Children.Clear(); $script:lastSeen = $null
            $ui.PhoneStatus.Text = 'iPhone not connected'; $ui.PhoneDot.Fill = '#A1B1C8'
            $ui.StartButton.Visibility = 'Visible'; $ui.PauseButton.Visibility = 'Collapsed'
            if ($ui.Status.Text -notmatch 'port|failed|Could not') { $ui.Status.Text = 'Relay stopped - click Start relay to reconnect' }
            $script:relayProcess.Dispose(); $script:relayProcess = $null
        }
        if ($script:lastSeen) {
            $age = [int]((Get-Date) - $script:lastSeen).TotalSeconds
            $ui.PhoneStatus.Text = if ($age -le 15) { 'iPhone connected' } else { 'iPhone idle' }
            $ui.PhoneStatus.ToolTip = "Last authenticated heartbeat: $age seconds ago"
            $ui.PhoneDot.Fill = if ($age -le 15) { '#35B665' } else { '#D9A23E' }
        }
        if ($script:qrShownAt -and ((Get-Date) - $script:qrShownAt).TotalSeconds -gt 120) { $ui.QRCanvas.Children.Clear(); $script:qrShownAt = $null; $ui.QRHint.Text = 'QR hidden for privacy. Existing pairing remains valid.' }
    } catch { $ui.Status.Text = 'Desktop connection interrupted. Stop and restart the relay.' }
})
$window.Add_Closed({ $timer.Stop(); Stop-Relay })
if ($SelfTest) {
    Handle-Event ([pscustomobject]@{type='ready'; endpoint='https://demo.example.test/'})
    Handle-Event ((& node (Join-Path $PSScriptRoot 'Relay\test\qr-fixture.cjs')) | ConvertFrom-Json)
    Handle-Event ([pscustomobject]@{type='phone-seen'})
    Handle-Event ([pscustomobject]@{type='request';kind='assist';requestId='demo';payload=@{transcript='What is the advantage of local transcription?'}})
    Handle-Event ([pscustomobject]@{type='reply';requestId='demo';durationMs=850;payload=@{answer='Your audio stays on your phone.'}})
    if ($ui.Activity.Text -notmatch 'Your audio stays' -or -not $ui.PairButton.IsEnabled -or $ui.Reply.Text -notmatch 'Your audio stays' -or $ui.Transcript.Text -notmatch 'advantage' -or $ui.ResponseTime.Text -notmatch '0.85') { throw 'Desktop self-test failed' }
    if ($ui.QRCanvas.Children.Count -eq 0) { throw 'Pairing QR was not rendered' }
    Handle-Event ([pscustomobject]@{type='state';accepting=$false})
    if (-not $script:paused) { throw 'Pause state failed' }
    Handle-Event ([pscustomobject]@{type='state';accepting=$true})
    $ui.PairingPanel.Visibility = if ($TestExpanded) { 'Visible' } else { 'Collapsed' }
    if ($TestExpanded) { $window.Width = 900; $window.Height = 650 }
    $window.Show(); $window.UpdateLayout()
    if ($EvidencePath) {
        $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$window.ActualWidth),([int]$window.ActualHeight),96,96,([Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($window)
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $file = [IO.File]::Create($EvidencePath); try { $encoder.Save($file) } finally { $file.Dispose() }
    }
    $ui.ClearButton.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    if ($ui.Transcript.Text -or $ui.Reply.Text -or $ui.Activity.Text) { throw 'Clear activity did not clear all text views' }
    $window.Close(); Write-Output 'Desktop self-test passed'; exit 0
}
$timer.Start()
if ($AutoStart) { $window.Add_ContentRendered({ Start-Relay }) }
$null = $window.ShowDialog()
