@echo off
rem release-starten.cmd - startet release.sh in der Git-Bash.
rem Doppelklick genuegt; das Fenster bleibt am Ende offen.
rem Liegt Git woanders, die Zeile mit BASH anpassen.

cd /d "%~dp0"

set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not exist "%BASH%" (
  echo Git-Bash nicht gefunden. Bitte den Pfad in dieser Datei eintragen.
  pause
  exit /b 1
)

"%BASH%" -l release.sh --skip-pack %*

echo.
pause
