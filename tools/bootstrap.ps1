param([switch]$SkipStudioPlugin)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path $PSScriptRoot -Parent
Push-Location $repoRoot
try {
    # Pinned upstream release, verified before execution. No admin or shell profile edits.
    $rokitVersion = '1.2.0'
    $archiveHash = 'f9ba1704014ff67d51e8005f605955c7c26d2429a5312a9419dc477fc310e96d'
    $rokitBin = Join-Path $env:USERPROFILE '.rokit/bin'
    $rokit = Join-Path $rokitBin 'rokit.exe'
    $installedVersion = if (Test-Path $rokit) { & $rokit --version } else { '' }
    if ($installedVersion -ne "Rokit $rokitVersion" -and $installedVersion -ne "rokit $rokitVersion") {
        New-Item -ItemType Directory -Path '.tools' -Force | Out-Null
        $archive = Join-Path $repoRoot '.tools/rokit.zip'
        Invoke-WebRequest "https://github.com/rojo-rbx/rokit/releases/download/v$rokitVersion/rokit-$rokitVersion-windows-x86_64.zip" -OutFile $archive
        if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $archiveHash) {
            throw 'Rokit download checksum did not match the pinned upstream artifact.'
        }
        Expand-Archive $archive -DestinationPath '.tools/rokit' -Force
        & '.tools/rokit/rokit.exe' self-install
        if ($LASTEXITCODE -ne 0) { throw 'Rokit installation failed.' }
    }
    & $rokit trust rojo-rbx/rojo JohnnyMorganz/StyLua Kampfkarren/selene lune-org/lune
    if ($LASTEXITCODE -ne 0) { throw 'Could not trust the specified tool publishers.' }
    & $rokit install
    if ($LASTEXITCODE -ne 0) { throw 'Tool installation failed.' }
    if (-not $SkipStudioPlugin) {
        # Fresh Studio installs may lack the registry key Rojo uses for discovery.
        # The supported process-local override avoids changing the registry.
        $previousStudioPath = $env:ROBLOX_STUDIO_PATH
        try {
            if (-not $env:ROBLOX_STUDIO_PATH) {
                $env:ROBLOX_STUDIO_PATH = Join-Path $env:LOCALAPPDATA 'Roblox'
            }
            & (Join-Path $rokitBin 'rojo.exe') plugin install
            if ($LASTEXITCODE -ne 0) { throw 'Rojo Studio plugin installation failed.' }
        } finally {
            $env:ROBLOX_STUDIO_PATH = $previousStudioPath
        }
    }
    Write-Host 'Tool setup complete. Run: .\tools\dev.ps1 check'
} finally {
    Pop-Location
}
