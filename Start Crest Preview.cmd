@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0experiments\water-lab\start-preview.ps1"
if errorlevel 1 pause
