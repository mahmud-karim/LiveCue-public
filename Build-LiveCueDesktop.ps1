$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework C# compiler is required.' }
$automation = Get-ChildItem (Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation') -Filter System.Management.Automation.dll -Recurse | Select-Object -ExpandProperty FullName -First 1
& (Join-Path $PSScriptRoot 'Build-LiveCueIcon.ps1')
& $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll "/reference:$automation" "/win32icon:$PSScriptRoot\Assets\LiveCue.ico" "/out:$PSScriptRoot\LiveCue Desktop Fluent.exe" "$PSScriptRoot\DesktopLauncher.cs"
if ($LASTEXITCODE -ne 0) { throw 'Desktop launcher compilation failed.' }
Write-Host 'LiveCue Desktop Fluent.exe is ready.'
