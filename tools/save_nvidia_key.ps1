# Stores an NVIDIA API key for this Windows user only, outside the repository.
# Run this yourself in a terminal: the prompt is hidden and the key is never printed,
# logged, or written in plaintext. Delete the file below to revoke local access.
$ErrorActionPreference = 'Stop'
$keyDirectory = Join-Path $env:LOCALAPPDATA 'SteelhacksRoommate'
$keyPath = Join-Path $keyDirectory 'nvidia-api-key.dpapi'

$entered = Read-Host -AsSecureString 'Paste your NVIDIA API key (hidden)'
$pointer = [IntPtr]::Zero
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($entered)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($plain)) { throw 'No key entered; nothing was saved.' }
    $plain = $plain.Trim()
    if ($plain -notmatch '^nvapi-') {
        Write-Warning 'That does not look like an NVIDIA Catalog key (they normally start with "nvapi-"). Saving it anyway.'
    }
    $trimmed = ConvertTo-SecureString $plain -AsPlainText -Force
} finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

New-Item -ItemType Directory -Path $keyDirectory -Force | Out-Null
ConvertFrom-SecureString $trimmed | Set-Content -LiteralPath $keyPath -Encoding utf8

# Confirm the encrypted copy decrypts to the same length, without revealing it.
$check = (Get-Content -Raw -LiteralPath $keyPath).Trim() | ConvertTo-SecureString
if ($check.Length -ne $trimmed.Length) { throw 'Saved key did not round-trip; try again.' }
Write-Host "Saved $($trimmed.Length) characters, encrypted for this Windows user, to:"
Write-Host "  $keyPath"
Write-Host 'Next: .\tools\probe_nemotron.ps1 -Live   then   .\tools\nemotron_proxy.ps1'
