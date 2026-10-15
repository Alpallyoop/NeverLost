@echo off
rem NeverLost CLI for a terminal:  nl help
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\nl.ps1" %*
exit /b %ERRORLEVEL%
