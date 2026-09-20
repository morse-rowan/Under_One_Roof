param([switch]$Offline, [int]$Port = 8787, [int]$MaxCalls = 40)
$ErrorActionPreference = 'Stop'
$bridgeScript = Join-Path $PSScriptRoot 'nemotron_proxy.py'
if ($Offline) {
    & py -3 $bridgeScript --offline --port $Port --max-calls $MaxCalls
    exit $LASTEXITCODE
}

# Same current-Windows-user DPAPI store as the probe. Never print or persist the key.
$bridgeSecretPath = Join-Path $env:LOCALAPPDATA 'SteelhacksRoommate/nvidia-api-key.dpapi'
if (-not (Test-Path -LiteralPath $bridgeSecretPath)) {
    throw 'No encrypted project key found. Run with -Offline, or start the Python bridge directly for a hidden key prompt.'
}
$bridgePreviousKey = $env:NVIDIA_API_KEY
$bridgePointer = [IntPtr]::Zero
try {
    $bridgeSecret = (Get-Content -Raw -LiteralPath $bridgeSecretPath).Trim() | ConvertTo-SecureString
    $bridgePointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($bridgeSecret)
    $env:NVIDIA_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bridgePointer)
    & py -3 $bridgeScript --port $Port --max-calls $MaxCalls
    $bridgeExitCode = $LASTEXITCODE
} finally {
    if ($bridgePointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bridgePointer)
    }
    $env:NVIDIA_API_KEY = $bridgePreviousKey
}
exit $bridgeExitCode
