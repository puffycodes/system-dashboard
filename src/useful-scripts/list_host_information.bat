@echo off
setlocal DisableDelayedExpansion
rem ---------------------------------------------------------------
rem  list_host_information.bat
rem  Lists the information that identifies this machine: host name,
rem  IP addresses and current timestamp.
rem
rem  Usage:  list_host_information.bat [output_file]
rem          Default output file: host_information.txt (next to this script)
rem ---------------------------------------------------------------

set "OUT=%~1"
if not defined OUT set "OUT=%~dp0host_information.txt"

rem IPv4 first. Link-local and 169.254.x.x addresses are skipped, as
rem they don't identify the machine.
set "IPS="
for /f "tokens=1,* delims=:" %%A in ('ipconfig ^| findstr /c:"IPv4"') do call :AddIP %%B
for /f "tokens=1,* delims=:" %%A in ('ipconfig ^| findstr /c:"IPv6" ^| findstr /v /i /c:"Link-local" /c:"fe80:"') do call :AddIP %%B
if not defined IPS set "IPS=N/A"

(
    echo Host Name:    %COMPUTERNAME%
    echo IP Addresses: %IPS%
    echo Timestamp:    %DATE% %TIME%
) > "%OUT%"

type "%OUT%"
echo.
echo Saved to: %OUT%
exit /b 0


:AddIP
set "ADDR=%~1"
if not defined ADDR exit /b
if "%ADDR:~0,8%"=="169.254." exit /b
if defined IPS (set "IPS=%IPS%, %ADDR%") else set "IPS=%ADDR%"
exit /b
