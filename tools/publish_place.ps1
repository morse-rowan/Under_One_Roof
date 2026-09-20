param(
    [switch]$Offline,
    [string]$GatewayUrl,
    [long]$Universe = 0,
    [long]$Place = 0,
    [long[]]$Invite = @(),
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$publishScript = Join-Path $PSScriptRoot 'publish_place.py'
$publishArgs = @()
if ($Offline) { $publishArgs += '--offline' }
elseif ($GatewayUrl) { $publishArgs += @('--gateway-url', $GatewayUrl) }
else { throw 'Pass -Offline for deterministic roommates, or -GatewayUrl https://<host>/decide.' }
if ($Universe -gt 0) { $publishArgs += @('--universe', $Universe) }
if ($Place -gt 0) { $publishArgs += @('--place', $Place) }
foreach ($id in $Invite) { $publishArgs += @('--invite', $id) }
if ($DryRun) { $publishArgs += '--dry-run' }

if ($DryRun) {
    & py -3 $publishScript @publishArgs
    exit $LASTEXITCODE
}

# Same current-Windows-user DPAPI store as the NVIDIA key. Never print or persist it.
$publishSecretPath = Join-Path $env:LOCALAPPDATA 'SteelhacksRoommate/roblox-api-key.dpapi'
if (-not (Test-Path -LiteralPath $publishSecretPath)) {
    throw 'No encrypted Roblox key found. Run .\tools\save_roblox_key.ps1 first.'
}
$publishPreviousKey = $env:ROBLOX_API_KEY
$publishPointer = [IntPtr]::Zero
try {
    $publishSecret = (Get-Content -Raw -LiteralPath $publishSecretPath).Trim() | ConvertTo-SecureString
    $publishPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($publishSecret)
    $env:ROBLOX_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($publishPointer)
    & py -3 $publishScript @publishArgs
    $publishExitCode = $LASTEXITCODE
} finally {
    if ($publishPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($publishPointer)
    }
    $env:ROBLOX_API_KEY = $publishPreviousKey
}
exit $publishExitCode
