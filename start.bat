@echo off
REM BUZZOONS Downloader - spusteni na Windows. Staci poklepat na start.bat
cd /d "%~dp0"

where python >nul 2>nul || (
  echo Chybi Python. Nainstaluj ho z https://www.python.org/downloads/ ^(zaskrtni "Add Python to PATH"^) a spust znovu.
  pause & exit /b 1
)
where ffmpeg >nul 2>nul || (
  echo Chybi ffmpeg. Nainstaluj ho prikazem:  winget install Gyan.FFmpeg
  echo ...a pak spust tenhle soubor znovu.
  pause & exit /b 1
)

if not exist .venv python -m venv .venv
call .venv\Scripts\activate.bat
pip install -q -r requirements.txt

echo.
echo BUZZOONS Downloader bezi na http://127.0.0.1:8000  (ukoncis zavrenim okna)
start "" http://127.0.0.1:8000
uvicorn app.main:app --port 8000
pause
