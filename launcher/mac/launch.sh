#!/bin/bash
# Spoustec BUZZOONS Downloaderu (bezi uvnitr .app na plose).
# 1) pokud server nebezi, spusti ho tise na pozadi  2) otevre prohlizec  3) na pozadi aktualizuje yt-dlp
APPDIR="$HOME/Library/Application Support/BUZZOONS Downloader"
LOG="$HOME/Library/Logs/BUZZOONS Downloader.log"
URL="http://127.0.0.1:8000"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # Finder nezna cestu k ffmpeg z Homebrew

cd "$APPDIR" 2>/dev/null || {
  osascript -e 'display alert "BUZZOONS Downloader" message "Nenasel jsem nainstalovanou appku. Spust prosim znovu instalator." as critical'
  exit 1
}

if ! curl -fs -m 2 "$URL/api/health" >/dev/null 2>&1; then
  echo "[$(date)] start" >> "$LOG"
  AUTO_SHUTDOWN=1 nohup .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 >> "$LOG" 2>&1 &
  for _ in $(seq 1 40); do
    curl -fs -m 2 "$URL/api/health" >/dev/null 2>&1 && break
    sleep 0.5
  done
  if ! curl -fs -m 2 "$URL/api/health" >/dev/null 2>&1; then
    osascript -e 'display alert "BUZZOONS Downloader" message "Server se nepodarilo spustit. Detail je v souboru ~/Library/Logs/BUZZOONS Downloader.log" as critical'
    exit 1
  fi
fi

open "$URL"
# tichá aktualizace yt-dlp (projeví se při příštím spuštění)
(nohup .venv/bin/python -m pip install -q -U yt-dlp >/dev/null 2>&1 &)
