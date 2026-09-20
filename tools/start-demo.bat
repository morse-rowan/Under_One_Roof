@echo off
setlocal
rem One click for the whole local demo: build the current tree, start the
rem roommate bridge, wait until it actually answers, then open the place in
rem Studio. The bridge is a separate Windows process, so Studio cannot start
rem it, and a session that opens without it plays the deterministic household
rem with no visible sign that the model was never reached.
set "ROOT=%~dp0.."
set "ROJO=%USERPROFILE%\.rokit\bin\rojo.exe"
set "PLACE=%ROOT%\build\UnderOneRoof-Live.rbxlx"

if exist "%ROJO%" (
    echo Building the local demo place...
    pushd "%ROOT%"
    "%ROJO%" build local-demo.project.json --output build\UnderOneRoof-Live.rbxlx
    popd
) else (
    echo Pinned rojo not found; opening the place already in build\.
)

if not exist "%PLACE%" (
    echo.
    echo Could not find "%PLACE%".
    echo Run tools\bootstrap.ps1 first, then try again.
    pause
    exit /b 1
)

rem An already-running bridge is reused rather than fought over: a second one
rem cannot bind 8787 and would exit looking like a failure.
call :probe
if not errorlevel 1 (
    echo Bridge is already running.
    goto :ready
)

echo Starting the roommate bridge...
start "Under One Roof bridge" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nemotron_proxy.ps1"

echo Waiting for the bridge to answer on 127.0.0.1:8787 ...
set /a TRIES=0
:wait
set /a TRIES+=1
call :probe
if not errorlevel 1 goto :ready
if %TRIES% geq 20 goto :nobridge
timeout /t 1 >nul
goto :wait

:nobridge
echo.
echo WARNING: the bridge never answered. The demo still runs, but the
echo deterministic household plays every turn instead of the model.
echo Check the bridge window for the reason.
echo.
goto :open

:ready
echo Bridge is up. Roommates will use the model.

:open
echo Opening the place in Roblox Studio...
start "" "%PLACE%"
echo.
echo Press Play ^(F5^) in Studio. Leave the bridge window open.
timeout /t 8 >nul
exit /b 0

:probe
powershell -NoProfile -Command "try { $null = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/health' -TimeoutSec 2 -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1
exit /b %errorlevel%
