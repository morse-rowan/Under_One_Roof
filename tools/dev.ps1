param(
    [ValidateSet('check', 'build', 'test', 'format', 'serve', 'doctor', 'open')]
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
        'open' {
            Build-Place
            $studioRoot = Join-Path $env:LOCALAPPDATA 'Roblox/Versions'
            $studio = Get-ChildItem -Path "$studioRoot/*/RobloxStudioBeta.exe" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $studio) { throw 'Install Roblox Studio before opening the place.' }
            # This command intentionally opens the interactive Studio window for playtesting.
            $placePath = Join-Path $repoRoot 'build/RoommateDev.rbxlx'
            Start-Process -FilePath $studio.FullName -ArgumentList ('"' + $placePath + '"')
        }
    }
} finally {
    Pop-Location
}
