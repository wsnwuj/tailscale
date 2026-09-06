#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$global:LASTEXITCODE = 0
$global:PersonalTestMode = 'normal'
function tailscale {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'status') {
        if ($global:PersonalTestMode -eq 'failed') { $global:LASTEXITCODE = 1; return '{}' }
        if ($global:PersonalTestMode -eq 'stopped') { return '{"BackendState":"Stopped"}' }
        return '{"BackendState":"Running","Peer":{"a":{"HostName":"direct","Online":true,"TailscaleIPs":["100.64.0.1"],"DNSName":"direct.example."},"b":{"HostName":"relay","Online":true,"TailscaleIPs":["100.64.0.2"]},"c":{"HostName":"offline","Online":false,"TailscaleIPs":["100.64.0.3"]},"d":{"HostName":"error","Online":true,"TailscaleIPs":["100.64.0.4"]},"e":{"HostName":"peer","Online":true,"TailscaleIPs":["100.64.0.5"]}}}'
    }
    switch ($args[-1]) {
        '100.64.0.1' { 'pong from direct (100.64.0.1) via [2001:db8::1]:41641 in 12ms' }
        '100.64.0.2' { 'pong from relay (100.64.0.2) via DERP(tok) in 1.2s' }
        '100.64.0.3' { throw 'Offline node must not be probed' }
        '100.64.0.4' { $global:LASTEXITCODE = 1; 'no reply' }
        '100.64.0.5' { 'pong from peer (100.64.0.5) via peer-relay(100.64.0.9) in 25ms' }
    }
}
$rows = @(& "$PSScriptRoot\ts-status.ps1" -AsObject)
Assert ($rows.Count -eq 5) 'Missing peers'
Assert ($rows[0].Connection -eq 'Direct' -and $rows[0].RTT -eq '12ms') 'Direct parsing'
Assert ($rows[0].WindTermHost -eq 'direct.example') 'MagicDNS normalization'
Assert ($rows[1].Connection -eq 'DERP(tok)' -and $rows[1].RTT -eq '1.2s') 'DERP parsing'
Assert ($rows[2].Connection -eq 'Offline') 'Offline state'
Assert ($rows[3].Connection -eq 'Unknown' -and $null -eq $rows[3].RTT) 'Failed probe must be unknown'
Assert ($rows[4].Connection -eq 'PeerRelay') 'Peer relay parsing'
foreach ($mode in @('failed', 'stopped')) {
    $global:PersonalTestMode = $mode
    $rejected = $false
    try { & "$PSScriptRoot\ts-status.ps1" -AsObject } catch { $rejected = $true }
    Assert $rejected 'Invalid daemon state must fail'
}
Remove-Item Function:\tailscale

$temp = [IO.Path]::GetTempFileName()
try {
    foreach ($csv in @("Name,TailnetIP,PublicIP", "Name,TailnetIP,PublicIP`nx,127.0.0.1,", "Name,TailnetIP,PublicIP`nx,100.64.0.1,invalid")) {
        Set-Content -LiteralPath $temp -Value $csv
        $rejected = $false
        try { & "$PSScriptRoot\ts-audit.ps1" -NodesPath $temp -AsObject } catch { $rejected = $true }
        Assert $rejected 'Invalid inventory must fail before probing'
    }
} finally { Remove-Item -LiteralPath $temp }

# Load only the TCP function to exercise real sockets without contacting a VPS.
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\ts-audit.ps1", [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'Audit syntax'
$definition = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-TcpPort'}, $true)
. ([scriptblock]::Create($definition.Extent.Text))
$TimeoutMs = 3000
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
try { Assert ((Test-TcpPort ([Net.IPAddress]::Loopback) $port) -eq 'Reachable') 'Listening port' }
finally { $listener.Stop() }
Assert ((Test-TcpPort ([Net.IPAddress]::Loopback) $port) -eq 'RefusedHere') 'Refused port'
$policy = Get-Content "$PSScriptRoot\policy.example.hujson" -Raw | ConvertFrom-Json
Assert ($policy.acls.Count -eq 2 -and $policy.tests.Count -eq 3) 'Policy structure'
Assert (($policy.acls | Where-Object { $_.proto -ne 'tcp' -or $_.action -ne 'accept' }).Count -eq 0) 'Policy transport'
'PASS: status scenarios, invalid input, real loopback sockets, policy structure'
