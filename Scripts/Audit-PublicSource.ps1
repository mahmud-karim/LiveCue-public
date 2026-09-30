$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Load-LiveCueSpeechKey.ps1')
$secret = Get-LiveCueSpeechKey
if (-not $secret) { throw 'Local credential unavailable; exact-key audit not performed.' }
$files = @(& git -C $root ls-files --cached --others --exclude-standard) | Select-Object -Unique
$blocked = @()
foreach ($relative in $files) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $content = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path))
    $wide = [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($path))
    if ($content.Contains($secret) -or $wide.Contains($secret) -or $content.Contains([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secret)))) { $blocked += $relative }
    if ($content -match '(?<![A-Za-z0-9_])LLM_[A-Za-z0-9_.-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}') { $blocked += $relative }
    if ($relative -match '(?i)(meta-stt-key|relay\.json|auth\.json|\.env$|\.wav$|credential.*\.xml$)') { $blocked += $relative }
}
$secret = $null
if ($blocked.Count) { throw ('Publication blocked; inspect these paths locally: ' + ($blocked -join ', ')) }
Write-Output ('Public-source audit passed: ' + $files.Count + ' files; no exact API key, encoded key, private key or credential file.')
