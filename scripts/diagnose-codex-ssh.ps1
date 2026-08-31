[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$HostAlias,

    [int]$ConnectTimeoutSeconds = 10,

    [switch]$IncludeVerboseSsh
)

$ErrorActionPreference = 'Stop'

function Add-CheckResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail
    )

    [pscustomobject]@{
        Check  = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw 'OpenSSH client (ssh.exe) is not available on PATH.'
}

$results = [System.Collections.Generic.List[object]]::new()

$effective = & ssh -G $HostAlias 2>&1
$effectiveExit = $LASTEXITCODE
if ($effectiveExit -ne 0) {
    $results.Add((Add-CheckResult 'ssh-config' $false ($effective -join [Environment]::NewLine)))
    $results | Format-Table -AutoSize -Wrap
    exit 1
}

$wantedPattern = '^(hostname|user|port|identityfile|hostkeyalias|proxycommand|proxyjump)\s+'
$effectiveWanted = @($effective | Where-Object { $_ -match $wantedPattern })
$results.Add((Add-CheckResult 'ssh-config' $true ($effectiveWanted -join '; ')))

$effectiveMap = @{}
foreach ($line in $effectiveWanted) {
    if ($line -match '^(\S+)\s+(.+)$') {
        $effectiveMap[$matches[1].ToLowerInvariant()] = $matches[2].Trim()
    }
}

if ($effectiveMap.ContainsKey('proxyjump') -and $effectiveMap['proxyjump'] -ne 'none') {
    $results.Add((Add-CheckResult 'unexpected-proxy' $false "ProxyJump=$($effectiveMap['proxyjump']). Test every hop or remove it."))
} elseif ($effectiveMap.ContainsKey('proxycommand') -and $effectiveMap['proxycommand'] -ne 'none') {
    $results.Add((Add-CheckResult 'unexpected-proxy' $false "ProxyCommand=$($effectiveMap['proxycommand']). Review the forwarding target."))
} else {
    $results.Add((Add-CheckResult 'unexpected-proxy' $true 'No effective ProxyJump or ProxyCommand.'))
}

if ($effectiveMap.ContainsKey('hostname') -and $effectiveMap['hostname'] -in @('127.0.0.1', 'localhost', '::1')) {
    $results.Add((Add-CheckResult 'loopback-target' $false "Resolved HostName is $($effectiveMap['hostname']); this is usually wrong for direct WSL SSH."))
} else {
    $results.Add((Add-CheckResult 'loopback-target' $true 'Target is not loopback.'))
}

$agentOutput = & ssh-add -l 2>&1
$agentExit = $LASTEXITCODE
if ($agentExit -eq 0) {
    $results.Add((Add-CheckResult 'ssh-agent' $true ($agentOutput -join '; ')))
} else {
    $results.Add((Add-CheckResult 'ssh-agent' $false ($agentOutput -join '; ')))
}

$sshArgs = @(
    '-o', 'BatchMode=yes',
    '-o', "ConnectTimeout=$ConnectTimeoutSeconds",
    $HostAlias,
    'echo SSH_READY; whoami; command -v codex; codex --version; codex app-server --help >/dev/null && echo APP_SERVER_READY; codex app-server daemon version 2>&1 || true'
)

$remoteOutput = & ssh @sshArgs 2>&1
$remoteExit = $LASTEXITCODE
$remoteText = $remoteOutput -join [Environment]::NewLine
$remotePassed = $remoteExit -eq 0 -and $remoteText -match 'SSH_READY' -and $remoteText -match 'APP_SERVER_READY'
$results.Add((Add-CheckResult 'remote-codex' $remotePassed $remoteText))

if ($IncludeVerboseSsh) {
    $verboseArgs = @(
        '-vvv',
        '-o', 'BatchMode=yes',
        '-o', "ConnectTimeout=$ConnectTimeoutSeconds",
        $HostAlias,
        'echo SSH_READY'
    )
    $verboseOutput = & ssh @verboseArgs 2>&1
    $results.Add((Add-CheckResult 'verbose-ssh' ($LASTEXITCODE -eq 0) ($verboseOutput -join [Environment]::NewLine)))
}

$results | Format-Table -AutoSize -Wrap

if ($results.Where({ -not $_.Passed }).Count -gt 0) {
    exit 1
}

exit 0
