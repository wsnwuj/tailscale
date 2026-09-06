#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$NodesPath,
    [ValidateRange(100, 10000)][int]$TimeoutMs = 2000,
    [switch]$AsObject
)
$ErrorActionPreference = 'Stop'

function Test-TcpPort([System.Net.IPAddress]$Address, [int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient($Address.AddressFamily)
    try {
        $pending = $client.BeginConnect($Address, $Port, $null, $null)
        try {
            if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMs)) { return 'TimeoutUnknown' }
            $client.EndConnect($pending)
            return 'Reachable'
        } finally { $pending.AsyncWaitHandle.Close() }
    } catch {
        $cause = $_.Exception.GetBaseException()
        if ($cause -is [System.Net.Sockets.SocketException] -and $cause.SocketErrorCode -eq 'ConnectionRefused') {
            return 'RefusedHere'
        }
        return 'ErrorUnknown'
    } finally { $client.Close() }
}

$nodes = @(Import-Csv -LiteralPath $NodesPath)
if (-not $nodes.Count) { throw 'Node CSV is empty.' }
# Validate the whole inventory before opening any connections. Literal IPs avoid DNS ambiguity.
foreach ($node in $nodes) {
    if (-not $node.Name -or -not $node.TailnetIP) { throw 'Each row needs Name and TailnetIP.' }
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($node.TailnetIP, [ref]$ip)) { throw 'Invalid TailnetIP.' }
    $bytes = $ip.GetAddressBytes()
    $isV4 = $bytes.Length -eq 4 -and $bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127
    $isV6 = $ip.ToString() -like 'fd7a:115c:a1e0:*'
    if (-not ($isV4 -or $isV6)) { throw 'TailnetIP must be a Tailscale address.' }
    if ($node.PublicIP -and -not [System.Net.IPAddress]::TryParse($node.PublicIP, [ref]$ip)) {
        throw 'Invalid PublicIP. Use one literal IPv4 or IPv6 address per row.'
    }
}
$rows = @(foreach ($node in $nodes) {
    foreach ($path in @('TailnetIP', 'PublicIP')) {
        foreach ($port in @(22, 9100)) {
            $result = 'NotConfigured'
            if ($node.$path) { $result = Test-TcpPort ([System.Net.IPAddress]::Parse($node.$path)) $port }
            [pscustomobject]@{ Name = $node.Name; Path = $path; Port = $port; Result = $result }
        }
    }
})
if ($AsObject) { $rows } else { $rows | Format-Table -AutoSize }
