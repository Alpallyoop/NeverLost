@echo off
rem Check identities (git, GitHub, trust, keys, session)
rem Double-click to run. Uses Windows PowerShell 5.1; the window stays open so you can read the result.
setlocal
cd /d "%~dp0"
title NeverLost - Check identities (git, GitHub, trust, keys, session)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\nl.ps1" identity --online %*
set "NL_RC=%ERRORLEVEL%"
echo.
if "%NL_RC%"=="0" (echo Finished OK.) else (echo Finished with problems - exit code %NL_RC%. Read the [FAIL] lines above.)
echo.
pause
exit /b %NL_RC%
