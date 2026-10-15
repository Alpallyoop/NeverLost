@echo off
rem Update: pull, verify trust and ledger, run all tests
rem Double-click to run. Uses Windows PowerShell 5.1; the window stays open so you can read the result.
setlocal
cd /d "%~dp0"
title NeverLost - Update: pull, verify trust and ledger, run all tests
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\nl.ps1" update %*
set "NL_RC=%ERRORLEVEL%"
echo.
if "%NL_RC%"=="0" (echo Finished OK.) else (echo Finished with problems - exit code %NL_RC%. Read the [FAIL] lines above.)
echo.
pause
exit /b %NL_RC%
