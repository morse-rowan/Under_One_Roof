<#
Runs the roommate bridge behind a public HTTPS tunnel, so a *published* Roblox
server can reach it. A published place cannot use the loopback URL: 127.0.0.1
on Roblox infrastructure is Roblox's own machine, not this laptop.

    .\tools\serve_gateway.ps1 -Offline        # stub decisions, no inference spent
    .\tools\serve_gateway.ps1                 # real Nemotron, uses the stored key
    .\tools\serve_gateway.ps1 -ShowToken      # also print the shared secret

The bridge binds to loopback only; cloudflared is what is exposed. The shared
gateway token is generated once, encrypted for this Windows user, and reused, so
it keeps matching the Roblox secret across restarts. The tunnel URL is NOT
stable: a free quick tunnel gets a new hostname every run, and the place must be
republished with the new URL each time.
#>
param(
    [switch]$Offline,
    [int]$Port = 8787,
    [int]$MaxCalls = 120,
    [switch]$ShowToken,
    [int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$runDirectory = Join-Path $repoRoot '.tools'
$tunnelExe = Join-Path $runDirectory 'cloudflared.exe'
if (-not (Test-Path -LiteralPath $tunnelExe)) {
    throw "cloudflared is missing. Download cloudflared-windows-amd64.exe to $tunnelExe"
}

# One stable secret, encrypted for this Windows user, shared with the Roblox secret store.
$secretDirectory = Join-Path $env:LOCALAPPDATA 'SteelhacksRoommate'
$tokenPath = Join-Path $secretDirectory 'gateway-token.dpapi'
New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath $tokenPath)) {
    $bytes = New-Object byte[] 36
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $fresh = [Convert]::ToBase64String($bytes).Replace('+', 'A').Replace('/', 'B').Replace('=', '')
    ConvertTo-SecureString $fresh -AsPlainText -Force | ConvertFrom-SecureString |
        Set-Content -LiteralPath $tokenPath -Encoding utf8
    Write-Host "Generated a new gateway token and encrypted it for this Windows user."
}
$tokenPointer = [IntPtr]::Zero
try {
    $stored = (Get-Content -Raw -LiteralPath $tokenPath).Trim() | ConvertTo-SecureString
    $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($stored)
    $gatewayToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
} finally {
    if ($tokenPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
    }
}

$bridgeLog = Join-Path $runDirectory 'bridge.log'
$tunnelLog = Join-Path $runDirectory 'tunnel.log'
Remove-Item -LiteralPath $bridgeLog, $tunnelLog -ErrorAction SilentlyContinue

$bridgeArgs = @('-3', (Join-Path $PSScriptRoot 'nemotron_proxy.py'), '--port', $Port, '--max-calls', $MaxCalls)
if ($Offline) { $bridgeArgs += '--offline' }
$environment = @{ ROOMMATE_GATEWAY_TOKEN = $gatewayToken }
if (-not $Offline) {
    $keyPath = Join-Path $secretDirectory 'nvidia-api-key.dpapi'
    if (-not (Test-Path -LiteralPath $keyPath)) {
        throw 'No encrypted NVIDIA key. Run .\tools\save_nvidia_key.ps1, or pass -Offline.'
    }
    $keyPointer = [IntPtr]::Zero
    try {
        $secret = (Get-Content -Raw -LiteralPath $keyPath).Trim() | ConvertTo-SecureString
        $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        $environment.NVIDIA_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
    } finally {
        if ($keyPointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
        }
    }
}
foreach ($name in $environment.Keys) { Set-Item -Path "env:$name" -Value $environment[$name] }
try {
    $bridge = Start-Process -FilePath 'py' -ArgumentList $bridgeArgs -PassThru -NoNewWindow `
        -RedirectStandardOutput $bridgeLog -RedirectStandardError "$bridgeLog.err"
} finally {
    # The child has its own copy; do not leave credentials in this shell.
    $env:NVIDIA_API_KEY = $null
}

$tunnel = Start-Process -FilePath $tunnelExe `
    -ArgumentList @('tunnel', '--no-autoupdate', '--url', "http://127.0.0.1:$Port") `
    -PassThru -NoNewWindow -RedirectStandardOutput $tunnelLog -RedirectStandardError "$tunnelLog.err"

$publicUrl = $null
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and -not $publicUrl) {
    Start-Sleep -Milliseconds 700
    foreach ($file in @("$tunnelLog.err", $tunnelLog)) {
        if (Test-Path -LiteralPath $file) {
            $match = Select-String -LiteralPath $file -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' `
                -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) { $publicUrl = $match.Matches[0].Value; break }
        }
    }
    if ($tunnel.HasExited) { throw "cloudflared exited early; see $tunnelLog.err" }
    if ($bridge.HasExited) { throw "The bridge exited early; see $bridgeLog.err" }
}
if (-not $publicUrl) { throw "No tunnel hostname after $TimeoutSeconds seconds; see $tunnelLog.err" }

Write-Host ''
Write-Host "Bridge PID $($bridge.Id) on 127.0.0.1:$Port ($(if ($Offline) { 'offline stub' } else { 'live Nemotron' }))"
Write-Host "Tunnel PID $($tunnel.Id)"
Write-Host "Gateway:  $publicUrl/decide"
if ($ShowToken) { Write-Host "Token:    $gatewayToken" }
else { Write-Host 'Token:    stored; rerun with -ShowToken to print it for the Roblox secret store.' }
Write-Host ''
Write-Host 'Next:'
Write-Host "  1. Roblox secret ROOMMATE_GATEWAY_TOKEN = the token above, domain $(([uri]$publicUrl).Host)"
Write-Host "  2. .\tools\publish_place.ps1 -GatewayUrl $publicUrl/decide -Invite <userId>"
Write-Host ("  Stop both with: Stop-Process -Id {0},{1}" -f $bridge.Id, $tunnel.Id)
