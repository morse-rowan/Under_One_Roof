param(
    [ValidateSet('check', 'build', 'test', 'format', 'serve', 'doctor', 'open', 'release')]
    [string]$Task = 'check',
    [switch]$SkipWiki
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path $PSScriptRoot -Parent
$toolBin = Join-Path $env:USERPROFILE '.rokit/bin'

function Invoke-Tool([string]$Name, [string[]]$ToolArgs) {
    $exe = Join-Path $toolBin "$Name.exe"
    if (-not (Test-Path $exe)) { throw "Missing $Name. Run .\tools\bootstrap.ps1 first." }
    & $exe @ToolArgs
    if ($LASTEXITCODE -ne 0) { throw "$Name failed (exit $LASTEXITCODE)." }
}

function Open-Studio([string]$PlacePath) {
    $studioRoot = Join-Path $env:LOCALAPPDATA 'Roblox/Versions'
    $studio = Get-ChildItem -Path "$studioRoot/*/RobloxStudioBeta.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $studio) { throw 'Install Roblox Studio before opening the place.' }
    # This command intentionally opens the interactive Studio window.
    Start-Process -FilePath $studio.FullName -ArgumentList ('"' + $PlacePath + '"')
}

function Build-Place {
    New-Item -ItemType Directory -Path 'build' -Force | Out-Null
    Invoke-Tool 'rojo' @('build', 'default.project.json', '--output', 'build/RoommateDev.rbxlx')
}

Push-Location $repoRoot
try {
    switch ($Task) {
        'check' {
            Invoke-Tool 'stylua' @('--check', 'src', 'tests')
            Invoke-Tool 'selene' @('src', 'tests')
            Build-Place
            Invoke-Tool 'lune' @('run', 'tests/run.luau')
            & py -3 -m unittest discover -s tests/python -p 'test_*.py'
            if ($LASTEXITCODE -ne 0) { throw 'Simulation Python tests failed.' }
            if (-not $SkipWiki) {
                & py -3 tools/wiki_lint.py
                if ($LASTEXITCODE -ne 0) { throw 'Wiki check failed.' }
            }
            Write-Host 'All development checks passed. Studio playtest is a separate check.'
        }
        'build' { Build-Place }
        'test' {
            Build-Place
            Invoke-Tool 'lune' @('run', 'tests/run.luau')
            & py -3 -m unittest discover -s tests/python -p 'test_*.py'
            if ($LASTEXITCODE -ne 0) { throw 'Simulation Python tests failed.' }
        }
        'format' { Invoke-Tool 'stylua' @('src', 'tests') }
        'serve' { Invoke-Tool 'rojo' @('serve', 'default.project.json') }
        'doctor' {
            foreach ($name in @('rokit', 'rojo', 'stylua', 'selene', 'lune')) {
                Invoke-Tool $name @('--version')
            }
            & git --version
            if ($LASTEXITCODE -ne 0) { throw 'Git is unavailable.' }
            & py -3 --version
            if ($LASTEXITCODE -ne 0) { throw 'Python 3 is unavailable.' }
            $studioRoot = Join-Path $env:LOCALAPPDATA 'Roblox/Versions'
            $studio = Get-ChildItem -Path "$studioRoot/*/RobloxStudioBeta.exe" -ErrorAction SilentlyContinue
            if (-not $studio) { throw 'Roblox Studio was not found in its standard user install directory.' }
            $studio | ForEach-Object { Write-Host "Studio: $($_.FullName)" }
        }
        'release' {
            # Builds the verified offline release and opens it so it can be published
            # from Studio: File > Publish to Roblox As... Deterministic roommates play
            # the whole household, so this configuration needs no gateway and no secrets.
            & py -3 (Join-Path $PSScriptRoot 'package_presentation.py') --offline
            if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
            $releasePlace = Join-Path $repoRoot 'build/presentation/RoommatePresentation.rbxlx'
            if (-not (Test-Path $releasePlace)) { throw 'Release place was not produced.' }
            Open-Studio $releasePlace
            Write-Host ''
            Write-Host 'Studio is opening the verified release place.'
            Write-Host 'Publish it with File > Publish to Roblox As... (first time creates the experience).'
            Write-Host 'Then set the experience to Private and join from any laptop signed in as you.'
        }
        'open' {
            Build-Place
            Open-Studio (Join-Path $repoRoot 'build/RoommateDev.rbxlx')
        }
    }
} finally {
    Pop-Location
}
