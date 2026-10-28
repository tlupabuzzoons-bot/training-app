@echo off
setlocal EnableExtensions
REM =====================================================================
REM  BUZZOONS Downloader - instalace na Windows jednim kliknutim
REM  Nainstaluje vsechno potrebne a vytvori zastupce na Plose.
REM  Lze spustit opakovane (aktualizuje appku).
REM =====================================================================
set "REPO=tlupabuzzoons-bot/training-app"
if "%BUZZOONS_BRANCH%"=="" (set "BRANCH=claude/blissful-albattani-5oyzkb") else (set "BRANCH=%BUZZOONS_BRANCH%")
set "APPDIR=%LOCALAPPDATA%\BUZZOONS Downloader"
set "LOG=%APPDIR%\install.log"
set "PORT=8000"
set "WINGET_ARGS=--accept-package-agreements --accept-source-agreements --silent"

title BUZZOONS Downloader - instalace
echo.
echo  BUZZOONS Downloader - instalace
echo  Vsechno probehne automaticky. Muze to trvat par minut.
echo.
if not exist "%APPDIR%" mkdir "%APPDIR%"
echo [%date% %time%] start >> "%LOG%"

REM ---------------------------------------------------------------- winget
echo ==^> 1/6 Kontrola winget (instalator balicku Windows)
where winget >nul 2>nul || (
  echo    CHYBA: winget neni k dispozici. Otevri Microsoft Store, nainstaluj/aktualizuj "App Installer" a spust tohle znovu.
  goto fail
)
echo    OK

REM ---------------------------------------------------------------- Python
echo ==^> 2/6 Python
call :findpython
if "%PYCMD%"=="" (
  echo    Python chybi, instaluji...
  winget install -e --id Python.Python.3.12 --scope user %WINGET_ARGS% >> "%LOG%" 2>&1
  call :refreshpath
  call :findpython
)
if "%PYCMD%"=="" (
  echo    CHYBA: Python se nepodarilo nainstalovat. Nainstaluj ho rucne z https://www.python.org/downloads/ a zaskrtni "Add Python to PATH".
  goto fail
)
for /f "delims=" %%v in ('%PYCMD% --version 2^>^&1') do echo    OK: %%v

REM ---------------------------------------------------------------- ffmpeg
echo ==^> 3/6 ffmpeg
where ffmpeg >nul 2>nul || (
  echo    ffmpeg chybi, instaluji...
  winget install -e --id Gyan.FFmpeg %WINGET_ARGS% >> "%LOG%" 2>&1
  call :refreshpath
)
where ffmpeg >nul 2>nul || (
  echo    CHYBA: ffmpeg se nepodarilo nainstalovat. Zkus v PowerShellu: winget install Gyan.FFmpeg
  goto fail
)
echo    OK

REM ---------------------------------------------------------------- stazeni
echo ==^> 4/6 Stahuji appku z GitHubu
set "TMPD=%TEMP%\buzzoons-dl"
if exist "%TMPD%" rmdir /s /q "%TMPD%"
mkdir "%TMPD%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest -Uri 'https://codeload.github.com/%REPO%/zip/refs/heads/%BRANCH%' -OutFile '%TMPD%\app.zip'" >> "%LOG%" 2>&1 || (
  echo    CHYBA: Stazeni selhalo. Jsi pripojeny k internetu?
  goto fail
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force '%TMPD%\app.zip' '%TMPD%\src'" >> "%LOG%" 2>&1 || (
  echo    CHYBA: Rozbaleni selhalo.
  goto fail
)
set "SRC="
for /d %%d in ("%TMPD%\src\*") do set "SRC=%%d"
if not exist "%SRC%\requirements.txt" (
  echo    CHYBA: Stazeny balik nevypada jako BUZZOONS Downloader.
  goto fail
)
robocopy "%SRC%" "%APPDIR%" /E /NFL /NDL /NJH /NJS /XD .venv downloads >> "%LOG%" 2>&1
if errorlevel 8 (
  echo    CHYBA: Kopirovani do "%APPDIR%" selhalo.
  goto fail
)
rmdir /s /q "%TMPD%"
echo    OK: %APPDIR%

REM ---------------------------------------------------------------- venv
echo ==^> 5/6 Instaluji knihovny (yt-dlp, FastAPI...)
cd /d "%APPDIR%"
if exist ".venv\Scripts\python.exe" (
  ".venv\Scripts\python.exe" -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" >nul 2>nul || rmdir /s /q ".venv"
)
if not exist ".venv\Scripts\python.exe" %PYCMD% -m venv ".venv" >> "%LOG%" 2>&1
if not exist ".venv\Scripts\python.exe" (
  echo    CHYBA: Vytvoreni prostredi selhalo.
  goto fail
)
".venv\Scripts\python.exe" -m pip install -q --upgrade pip >> "%LOG%" 2>&1
".venv\Scripts\python.exe" -m pip install -q -r requirements.txt >> "%LOG%" 2>&1 || (
  echo    CHYBA: Instalace knihoven selhala.
  goto fail
)
".venv\Scripts\python.exe" -c "import yt_dlp, fastapi, uvicorn" >> "%LOG%" 2>&1 || (
  echo    CHYBA: Knihovny se nainstalovaly, ale nejdou nacist.
  goto fail
)
echo    OK

REM ---------------------------------------------------------------- zastupce + kontrola
echo ==^> 6/6 Zastupce na Plose a kontrola
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d=[Environment]::GetFolderPath('Desktop'); $s=(New-Object -ComObject WScript.Shell).CreateShortcut(\"$d\BUZZOONS Downloader.lnk\"); $s.TargetPath='wscript.exe'; $s.Arguments='\"%APPDIR%\launcher\windows\launch.vbs\"'; $s.WorkingDirectory='%APPDIR%'; $s.IconLocation='%APPDIR%\assets\icon.ico'; $s.Description='BUZZOONS Downloader'; $s.Save()" >> "%LOG%" 2>&1 || (
  echo    CHYBA: Zastupce se nepodarilo vytvorit.
  goto fail
)

curl -s -m 2 -o nul "http://127.0.0.1:%PORT%/api/health" && (
  echo    Appka uz bezi, vypinam ji kvuli aktualizaci...
  curl -s -m 2 -X POST -o nul "http://127.0.0.1:%PORT%/api/shutdown"
  timeout /t 3 /nobreak >nul
)
set AUTO_SHUTDOWN=1
start "" /B ".venv\Scripts\python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port %PORT% > "%APPDIR%\server.log" 2>&1
set "HEALTH="
for /l %%i in (1,1,40) do (
  (
    curl -s -m 2 "http://127.0.0.1:%PORT%/api/health" 2>nul | findstr /C:"\"ok\":true" >nul && goto healthy
    timeout /t 1 /nobreak >nul
  )
)
curl -s -m 2 -X POST -o nul "http://127.0.0.1:%PORT%/api/shutdown"
echo    CHYBA: Testovaci spusteni selhalo. Detail: "%APPDIR%\server.log"
goto fail

:healthy
curl -s -m 2 -X POST -o nul "http://127.0.0.1:%PORT%/api/shutdown"
echo    OK: server nabehl, ffmpeg i yt-dlp odpovidaji
echo.
echo  HOTOVO! BUZZOONS Downloader je nainstalovany.
echo.
echo  Na Plose mas zastupce "BUZZOONS Downloader". Klikni na nej a otevre se stranka.
echo  Appka se sama vypne, kdyz zavres panel v prohlizeci.
echo.
timeout /t 2 /nobreak >nul
start "" wscript.exe "%APPDIR%\launcher\windows\launch.vbs"
echo  Tohle okno muzes zavrit.
pause
exit /b 0

:fail
echo.
echo  Instalace se nezdarila. Log: "%LOG%"
echo  Posli log nebo screenshot a opravime to.
pause
exit /b 1

REM ---------------------------------------------------------------- pomocne funkce
:findpython
set "PYCMD="
for %%v in (3.13 3.12 3.11 3.10) do (
  if "%PYCMD%"=="" py -%%v -c "import sys" >nul 2>nul && set "PYCMD=py -%%v"
)
if "%PYCMD%"=="" python -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" >nul 2>nul && set "PYCMD=python"
exit /b 0

:refreshpath
for /f "delims=" %%p in ('powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')"') do set "PATH=%%p"
exit /b 0
