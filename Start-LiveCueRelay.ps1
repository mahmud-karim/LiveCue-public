[CmdletBinding()]
param(
    [switch]$ResetPairing,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$relayRoot = Join-Path $PSScriptRoot 'Relay'
$tailscale = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'

if (-not (Test-Path -LiteralPath $tailscale)) { throw 'Tailscale is not installed in Program Files.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 24 or newer is required.' }
if (-not (Test-Path -LiteralPath (Join-Path $relayRoot 'node_modules'))) { throw 'Relay dependencies are missing. Run npm install once inside the Relay folder.' }

$codexCommand = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue
$codexExecutable = if ($codexCommand) { $codexCommand.Source } else { $null }
if (-not $codexExecutable) {
    $codexInstallRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $codexExecutable = Get-ChildItem -LiteralPath $codexInstallRoot -Filter codex.exe -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -ExpandProperty FullName -First 1
}
if (-not $codexExecutable -or -not (Test-Path -LiteralPath $codexExecutable)) {
    throw 'Codex CLI was not found. Install or update the Codex desktop app, then open it once and sign in.'
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$codexLoginStatus = (& $codexExecutable login status 2>&1 | Out-String).Trim()
$codexLoginExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($codexLoginExitCode -ne 0) { throw "Codex is installed but not signed in. Open Codex and sign in with ChatGPT. $codexLoginStatus" }
$env:LIVECUE_CODEX_EXECUTABLE = $codexExecutable

$status = & $tailscale status --json | ConvertFrom-Json
if (-not $status.Self.Online) { throw 'Tailscale is not online. Open Tailscale and connect first.' }
$dnsName = [string]$status.Self.DNSName
if ([string]::IsNullOrWhiteSpace($dnsName)) { throw 'Tailscale did not return this PC DNS name.' }
$dnsName = $dnsName.TrimEnd('.')
$publicEndpoint = "https://$dnsName/"
$env:LIVECUE_PUBLIC_ENDPOINT = $publicEndpoint
$env:LIVECUE_PORT = '47831'

Write-Host "Codex ready: $codexExecutable" -ForegroundColor Green
Write-Host "Tailscale ready: $dnsName" -ForegroundColor Green
if ($CheckOnly) {
    Write-Host 'LiveCue Relay prerequisites passed.' -ForegroundColor Green
    return
}

& $tailscale serve --bg 47831 | Out-Host
$env:LIVECUE_PUBLIC_ENDPOINT = $publicEndpoint
$env:LIVECUE_PORT = '47831'

Write-Host "`nLiveCue will be private at $publicEndpoint" -ForegroundColor Cyan
Push-Location $relayRoot
try {
    if ($ResetPairing) { npm run reset-pairing } else { npm start }
} finally {
    Pop-Location
}
