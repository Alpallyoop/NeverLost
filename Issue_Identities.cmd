@echo off
rem Issue the signing identities other services are waiting for (config\issuance_plan.v1.json).
rem Shows the plan first (ISSUED / READY / WAITING) and changes nothing until you type ISSUE.
rem Keys are created on this computer, readable only by your Windows account, and never committed.
setlocal
cd /d "%~dp0"
title NeverLost - Issue identities
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\nl.ps1" issue-plan --apply %*
set "NL_RC=%ERRORLEVEL%"
echo.
if "%NL_RC%"=="0" (echo Finished OK. Each service's settings: proofs\published\^<service^>\HANDOFF.md) else (echo Finished with problems - exit code %NL_RC%.)
echo.
pause
exit /b %NL_RC%
