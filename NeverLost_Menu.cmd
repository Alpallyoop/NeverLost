@echo off
rem NeverLost menu - double-click to open.
setlocal
cd /d "%~dp0"
title NeverLost
set "NL=powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\nl.ps1""

:menu
cls
echo  ============================================================
echo   NeverLost - identity, signing, trust and provenance
echo  ============================================================
echo.
echo    1  Status
echo    2  Update   (pull, verify trust + ledger, run all tests)
echo    3  Push     (commit, test, push this branch)
echo    4  Check identities (git, GitHub, trust, keys, session)
echo    5  Run all tests
echo    6  What NeverLost needs (Constellation + other projects)
echo    7  Doctor   (tools and ecosystem files)
echo    8  Authority: start session
echo    9  Authority: confirm session
echo    E  Authority: end session
echo    S  Rebuild allowed_signers from the trust bundle
echo    H  Help (all commands)
echo    Q  Quit
echo.
choice /c 123456789ESHQ /n /m "  Choose: "
set "PICK=%ERRORLEVEL%"
if "%PICK%"=="13" goto :eof
if "%PICK%"=="1"  call :run status
if "%PICK%"=="2"  call :run update
if "%PICK%"=="3"  call :run push
if "%PICK%"=="4"  call :run identity --online
if "%PICK%"=="5"  call :run test
if "%PICK%"=="6"  call :run constellation
if "%PICK%"=="7"  call :run doctor
if "%PICK%"=="8"  call :run authority start
if "%PICK%"=="9"  call :run authority confirm
if "%PICK%"=="10" call :run authority end
if "%PICK%"=="11" call :run signers make
if "%PICK%"=="12" call :run help
goto menu

:run
echo.
%NL% %*
echo.
if "%ERRORLEVEL%"=="0" (echo Finished OK.) else (echo Finished with problems - exit code %ERRORLEVEL%.)
echo.
pause
exit /b 0
