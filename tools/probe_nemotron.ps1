param([switch]$Live)
$ErrorActionPreference = 'Stop'
$probeScript = Join-Path $PSScriptRoot 'probe_nemotron.py'
if (-not $Live) {
    & py -3 $probeScript
    exit $LASTEXITCODE
}

# Current-Windows-user DPAPI storage, outside the repository. Never print the key.
$probeSecretPath = Join-Path $env:LOCALAPPDATA 'SteelhacksRoommate/nvidia-api-key.dpapi'
if (-not (Test-Path -LiteralPath $probeSecretPath)) {
    throw 'No encrypted project key found. Use the Python probe directly for a hidden key prompt.'
}
$probePreviousKey = $env:NVIDIA_API_KEY
$probePointer = [IntPtr]::Zero
try {
    $probeSecret = (Get-Content -Raw -LiteralPath $probeSecretPath).Trim() | ConvertTo-SecureString
    $probePointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($probeSecret)
    $env:NVIDIA_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($probePointer)
    & py -3 $probeScript --live
    $probeExitCode = $LASTEXITCODE
} finally {
    if ($probePointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($probePointer)
    }
    $env:NVIDIA_API_KEY = $probePreviousKey
}
exit $probeExitCode
