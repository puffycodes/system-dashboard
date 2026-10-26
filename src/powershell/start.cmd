@echo off
rem Double-click launcher: starts the dashboard server and opens it in the browser.
rem Extra arguments are passed through, e.g. start.cmd -Port 9000
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Open %*
