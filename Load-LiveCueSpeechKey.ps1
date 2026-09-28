# Windows DPAPI: the credential stays outside the repository and can only be read by this Windows user.
function Get-LiveCueSpeechKey {
    $credentialPath = Join-Path $env:LOCALAPPDATA 'LiveCue\meta-stt-key.xml'
    if (Test-Path -LiteralPath $credentialPath) {
        try { return (Import-Clixml -LiteralPath $credentialPath).GetNetworkCredential().Password }
        catch { throw 'Cannot unlock the local Meta credential. Use the Windows account that saved it.' }
    }
    return $null
}
