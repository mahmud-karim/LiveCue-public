function Get-LiveCueConnection([string]$DnsName) {
    $path = Join-Path $env:LOCALAPPDATA 'LiveCue\connection.json'
    if (Test-Path -LiteralPath $path) {
        $config = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $address = [uri]$config.endpoint
        if ($config.mode -ne 'funnel' -or $address.Scheme -ne 'https' -or $address.Host -ne $DnsName -or
            $address.AbsolutePath -ne '/' -or $address.Query -or $address.Fragment -or $address.UserInfo -or
            $address.Port -notin @(443,8443,10000)) { throw 'Invalid local LiveCue Funnel configuration.' }
        return @{ Endpoint = $address.AbsoluteUri; Mode = 'funnel' }
    }
    return @{ Endpoint = "https://$DnsName/"; Mode = 'private' }
}
