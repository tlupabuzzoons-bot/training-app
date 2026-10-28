@echo off
REM Spoustec BUZZOONS Downloaderu (Windows). Bezi skryte, vola ho launch.vbs.
cd /d "%~dp0.."
set "URL=http://127.0.0.1:8000"
set "LOG=%LOCALAPPDATA%\BUZZOONS Downloader\server.log"

curl -s -m 2 -o nul "%URL%/api/health" && goto open

echo [%date% %time%] start >> "%LOG%"
set AUTO_SHUTDOWN=1
start "" /B ".venv\Scripts\python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port 8000 >> "%LOG%" 2>&1

for /l %%i in (1,1,40) do (
  curl -s -m 2 -o nul "%URL%/api/health" && goto open
  timeout /t 1 /nobreak >nul
)
powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Server se nepodarilo spustit. Detail je v souboru %LOG%','BUZZOONS Downloader')" 2>nul
exit /b 1

:open
start "" "%URL%"
start "" /B ".venv\Scripts\python.exe" -m pip install -q -U yt-dlp >nul 2>&1
exit /b 0
