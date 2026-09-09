$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework C# compiler is required.' }
$automation = Get-ChildItem (Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation') -Filter System.Management.Automation.dll -Recurse | Select-Object -ExpandProperty FullName -First 1
& $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll "/reference:$automation" "/out:$PSScriptRoot\LiveCue Desktop.exe" "$PSScriptRoot\DesktopLauncher.cs"
if ($LASTEXITCODE -ne 0) { throw 'Desktop launcher compilation failed.' }
Write-Host 'LiveCue Desktop.exe is ready.'
