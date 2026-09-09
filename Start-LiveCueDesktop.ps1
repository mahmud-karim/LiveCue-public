[CmdletBinding()]
param([switch]$SelfTest, [string]$EvidencePath, [switch]$AutoStart)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[xml]$layout = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="LiveCue Desktop" Width="1120" Height="790" MinWidth="900" MinHeight="650" Background="#101724" Foreground="#EDF2FA" WindowStartupLocation="CenterScreen">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="15,9"/><Setter Property="Margin" Value="0,0,8,8"/><Setter Property="Background" Value="#364966"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderThickness" Value="0"/></Style>
  <Style TargetType="TextBox"><Setter Property="Background" Value="#172236"/><Setter Property="Foreground" Value="#EDF2FA"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="12"/><Setter Property="IsReadOnly" Value="True"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="VerticalScrollBarVisibility" Value="Auto"/></Style>
 </Window.Resources>
 <Grid Margin="24">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel><TextBlock Text="LiveCue Desktop" FontSize="29" FontWeight="Bold"/><TextBlock Text="Your private iPhone-to-PC assistant" Foreground="#AABBD5" Margin="0,5,0,18"/></StackPanel>
  <StackPanel Grid.Row="1">
   <WrapPanel><Button x:Name="StartButton" Content="Start relay"/><Button x:Name="StopButton" Content="Stop relay" IsEnabled="False"/><Button x:Name="PauseButton" Content="Pause requests" IsEnabled="False"/><Button x:Name="ClearButton" Content="Clear activity"/></WrapPanel>
   <TextBlock x:Name="Status" Text="Relay stopped" FontSize="16" Margin="0,3,0,5"/>
   <TextBlock x:Name="PhoneStatus" Text="Phone: not seen yet" Foreground="#AABBD5" Margin="0,0,0,16"/>
  </StackPanel>
  <Grid Grid.Row="2">
   <Grid.ColumnDefinitions><ColumnDefinition Width="300"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Border Background="#172236" CornerRadius="12" Padding="16">
    <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
     <TextBlock Text="Pair your iPhone" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,12"/>
     <Border Background="White" Padding="8"><Viewbox Width="240" Height="240"><Canvas x:Name="QRCanvas" Width="240" Height="240" Background="White"/></Viewbox></Border>
     <TextBlock x:Name="QRHint" Text="Existing pairing stays valid. Generate a new QR only if you need to pair again." TextWrapping="Wrap" Foreground="#AABBD5" Margin="0,12,0,12"/>
     <Button x:Name="PairButton" Content="Generate new pairing QR" IsEnabled="False"/>
     <Button x:Name="HideQRButton" Content="Hide QR"/>
     <TextBlock Text="PC address" Foreground="#AABBD5" Margin="0,10,0,4"/>
     <TextBox x:Name="Endpoint" MaxHeight="72"/>
     <TextBlock Text="Codex: gpt-5.6-sol / low reasoning" Foreground="#AABBD5" TextWrapping="Wrap" Margin="0,12,0,0"/>
    </StackPanel></ScrollViewer>
   </Border>
   <Grid Grid.Column="2">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <TextBlock Text="Live activity - transcript in / answer out" FontSize="18" Margin="0,0,0,10"/>
    <TextBox x:Name="Activity" Grid.Row="1" FontFamily="Consolas" FontSize="13" Text="Start the relay, then tap Assist on your iPhone."/>
   </Grid>
  </Grid>
  <TextBlock Grid.Row="3" Text="Activity stays in memory only. Closing this window stops its relay. Keep the pairing QR private." Foreground="#AABBD5" Margin="0,16,0,0" TextWrapping="Wrap"/>
 </Grid>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $layout))
$ui = @{}
foreach ($name in 'StartButton','StopButton','PauseButton','ClearButton','Status','PhoneStatus','QRCanvas','QRHint','PairButton','HideQRButton','Endpoint','Activity') { $ui[$name] = $window.FindName($name) }
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
    $ui.Status.Text = 'Relay stopped'; $ui.PhoneStatus.Text = 'Phone: relay stopped'
    $ui.StartButton.IsEnabled = $true
    $ui.StopButton.IsEnabled = $false; $ui.PauseButton.IsEnabled = $false; $ui.PairButton.IsEnabled = $false
    $ui.QRCanvas.Children.Clear(); $script:qrShownAt = $null
}
function Handle-Event($event) {
    switch ($event.type) {
        'ready' {
            $ui.StartButton.IsEnabled = $false
            $ui.Status.Text = 'Relay ready - accepting requests'; $ui.Endpoint.Text = [string]$event.endpoint
            $ui.StopButton.IsEnabled = $true; $ui.PauseButton.IsEnabled = $true; $ui.PairButton.IsEnabled = $true
            $script:paused = $false; $ui.PauseButton.Content = 'Pause requests'
            Add-Activity 'Relay started. Waiting for your iPhone.'
        }
        'phone-seen' { $script:lastSeen = Get-Date }
        'state' {
            $script:paused = -not [bool]$event.accepting
            if ($script:paused) { $ui.Status.Text = 'Relay paused - new requests blocked'; $ui.PauseButton.Content = 'Resume requests' }
            else { $ui.Status.Text = 'Relay ready - accepting requests'; $ui.PauseButton.Content = 'Pause requests' }
        }
        'pairing' {
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
            $ui.Status.Text = 'Processing with Codex...'
            Add-Activity ("INCOMING " + $event.kind + ' [' + $event.requestId + "]`r`n" + ($event.payload | ConvertTo-Json -Depth 16))
        }
        'reply' {
            $ui.Status.Text = if ($script:paused) { 'Relay paused' } else { 'Reply sent - ready' }
            Add-Activity ("REPLY [" + $event.requestId + '] ' + ([Math]::Round($event.durationMs / 1000.0, 2)) + " s`r`n" + ($event.payload | ConvertTo-Json -Depth 16))
        }
        'request-error' { $ui.Status.Text = 'Request failed - ready to retry'; Add-Activity ([string]$event.message) }
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
$ui.ClearButton.Add_Click({ $ui.Activity.Clear() })
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
            $ui.PhoneStatus.Text = 'Phone: relay stopped'
            if ($ui.Status.Text -notmatch 'port|failed|Could not') { $ui.Status.Text = 'Relay stopped - click Start relay to reconnect' }
            $script:relayProcess.Dispose(); $script:relayProcess = $null
        }
        if ($script:lastSeen) {
            $age = [int]((Get-Date) - $script:lastSeen).TotalSeconds
            $ui.PhoneStatus.Text = if ($age -le 15) { 'Phone: active (authenticated heartbeat)' } else { "Phone: last seen $age seconds ago - app may be backgrounded" }
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
    if ($ui.Activity.Text -notmatch 'Your audio stays' -or -not $ui.PairButton.IsEnabled) { throw 'Desktop self-test failed' }
    $window.Show(); $window.UpdateLayout()
    if ($EvidencePath) {
        $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$window.ActualWidth),([int]$window.ActualHeight),96,96,([Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($window)
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $file = [IO.File]::Create($EvidencePath); try { $encoder.Save($file) } finally { $file.Dispose() }
    }
    $window.Close(); Write-Output 'Desktop self-test passed'; exit 0
}
$timer.Start()
if ($AutoStart) { $window.Add_ContentRendered({ Start-Relay }) }
$null = $window.ShowDialog()
