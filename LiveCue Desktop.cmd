@echo off
if not exist "%~dp0LiveCue Desktop Fluent.exe" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-LiveCueDesktop.ps1"
start "" "%~dp0LiveCue Desktop Fluent.exe"
