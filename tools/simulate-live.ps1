[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$EntryPoint = '',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$LabArgs
)
$ErrorActionPreference = 'Stop'
if (-not $EntryPoint) { $EntryPoint = Join-Path $PSScriptRoot 'simulate.py' }
$labSecretPath = Join-Path $env:LOCALAPPDATA 'SteelhacksRoommate/nvidia-api-key.dpapi'
$labPreviousKey = $env:NVIDIA_API_KEY
$labPointer = [IntPtr]::Zero
try {
    if (-not $env:NVIDIA_API_KEY) {
        if (-not (Test-Path -LiteralPath $labSecretPath)) { throw 'No NVIDIA_API_KEY or encrypted project key available.' }
        $labSecret = (Get-Content -Raw -LiteralPath $labSecretPath).Trim() | ConvertTo-SecureString
        $labPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($labSecret)
        $env:NVIDIA_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($labPointer)
    }
    & py -3 $EntryPoint @LabArgs
    $labExit = $LASTEXITCODE
} finally {
    if ($labPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($labPointer) }
    $env:NVIDIA_API_KEY = $labPreviousKey
}
exit $labExit
