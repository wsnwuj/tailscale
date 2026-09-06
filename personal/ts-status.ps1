#Requires -Version 5.1
[CmdletBinding()]
param([switch]$AsObject)
$ErrorActionPreference = 'Stop'

$cli = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $cli) { throw 'Tailscale CLI not found. Install official Tailscale and reopen PowerShell.' }
$raw = & $cli status --json
if ($LASTEXITCODE -ne 0) { throw 'tailscale status failed.' }
$status = ($raw -join "`n") | ConvertFrom-Json
if ($status.BackendState -ne 'Running') { throw "Tailscale is not running: $($status.BackendState)" }
$rows = @(foreach ($entry in $status.Peer.PSObject.Properties) {
    $peer = $entry.Value
    $address = @($peer.TailscaleIPs)[0]
    $route = 'Offline'
    $rtt = $null
    if ($peer.Online) {
        $route = 'Unknown'
        if ($address) {
            # A single observed path, not a claim about steady-state connectivity.
            # Windows PowerShell can turn native stderr into terminating errors.
            $savedPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $reply = & $cli ping --c=1 --timeout=3s --until-direct=false $address 2>&1
                $pingExit = $LASTEXITCODE
            } finally { $ErrorActionPreference = $savedPreference }
            if ($pingExit -eq 0 -and ($reply -join "`n") -match 'pong from .+ via (\S+) in ([0-9.]+(?:ms|s))') {
                $via = $Matches[1]
                $rtt = $Matches[2]
                if ($via -like 'DERP(*)') { $route = $via }
                elseif ($via -like 'peer-relay(*)') { $route = 'PeerRelay' }
                elseif ($via -match '^\[?[0-9a-fA-F:.]+\]?:\d+$') { $route = 'Direct' }
            }
        }
    }
    [pscustomobject]@{
        Name = $peer.HostName
        Online = [bool]$peer.Online
        Connection = $route
        RTT = $rtt
        Address = $address
        WindTermHost = if ($peer.DNSName) { $peer.DNSName.TrimEnd('.') } else { $address }
    }
})
if ($AsObject) { $rows } else { $rows | Format-Table -AutoSize }
