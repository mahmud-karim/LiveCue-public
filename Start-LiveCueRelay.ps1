[CmdletBinding()]
param([switch]$ResetPairing)

$ErrorActionPreference = 'Stop'
$relayRoot = Join-Path $PSScriptRoot 'Relay'
$tailscale = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'

if (-not (Test-Path -LiteralPath $tailscale)) { throw 'Tailscale is not installed in Program Files.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 24 or newer is required.' }
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'Codex CLI is required. Open Codex once and sign in with your ChatGPT account.' }
if (-not (Test-Path -LiteralPath (Join-Path $relayRoot 'node_modules'))) { throw 'Relay dependencies are missing. Run npm install once inside the Relay folder.' }

$status = & $tailscale status --json | ConvertFrom-Json
if (-not $status.Self.Online) { throw 'Tailscale is not online. Open Tailscale and connect first.' }
$dnsName = [string]$status.Self.DNSName
if ([string]::IsNullOrWhiteSpace($dnsName)) { throw 'Tailscale did not return this PC DNS name.' }
$dnsName = $dnsName.TrimEnd('.')
$publicEndpoint = "https://$dnsName/"

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

