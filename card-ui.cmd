@echo off
rem Abre a pagina local do card-sigcon (http://localhost:8765/). Ctrl+C para parar.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ui\servidor.ps1" %*
