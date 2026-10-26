@echo off
setlocal DisableDelayedExpansion
rem ---------------------------------------------------------------
rem  list_installed_software.bat
rem  Lists installed software (name + version) by reading the same
rem  registry Uninstall keys that "Programs and Features" uses.
rem
rem  Usage:  list_installed_software.bat [output_file]
rem          Default output file: installed_software.txt (next to this script)
rem ---------------------------------------------------------------

set "OUT=%~1"
if not defined OUT set "OUT=%~dp0installed_software.txt"
set "TMPFILE=%TEMP%\installed_software_%RANDOM%.tmp"
if exist "%TMPFILE%" del "%TMPFILE%"

for %%R in (
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
) do (
    for /f "delims=" %%K in ('reg query %%R 2^>nul ^| findstr /b /i "HKEY_"') do call :ReadKey "%%K"
)

if not exist "%TMPFILE%" (
    echo No installed software found.
    exit /b 1
)

rem Sort and remove duplicates (same app can appear in multiple hives)
(
    echo Installed software on %COMPUTERNAME% - %DATE% %TIME%
    echo ------------------------------------------------------------
    set "PREV="
    for /f "usebackq delims=" %%L in (`sort "%TMPFILE%"`) do call :PrintUnique "%%L"
) > "%OUT%"
del "%TMPFILE%"

type "%OUT%"
echo.
echo Saved to: %OUT%
exit /b 0


:ReadKey
set "NAME="
set "VER="
set "SYSCOMP="
for /f "tokens=2,*" %%A in ('reg query "%~1" /v DisplayName 2^>nul ^| findstr /i "REG_"') do set "NAME=%%B"
if not defined NAME exit /b
rem Skip hidden system components, as Programs and Features does
for /f "tokens=3" %%A in ('reg query "%~1" /v SystemComponent 2^>nul ^| findstr /i "REG_DWORD"') do set "SYSCOMP=%%A"
if "%SYSCOMP%"=="0x1" exit /b
for /f "tokens=2,*" %%A in ('reg query "%~1" /v DisplayVersion 2^>nul ^| findstr /i "REG_"') do set "VER=%%B"
if not defined VER set "VER=N/A"
setlocal EnableDelayedExpansion
>>"!TMPFILE!" echo(!NAME!  ^|  !VER!
endlocal
exit /b


:PrintUnique
set "LINE=%~1"
setlocal EnableDelayedExpansion
if "!LINE!"=="!PREV!" (endlocal & exit /b)
echo(!LINE!
endlocal
set "PREV=%~1"
exit /b
