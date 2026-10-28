#!/usr/bin/env bash
# BUZZOONS Downloader - spusteni na Macu / Linuxu. Staci: ./start.sh
set -e
cd "$(dirname "$0")"

if ! command -v python3 >/dev/null; then
  echo "Chybi Python 3. Nainstaluj ho z https://www.python.org/downloads/ a spust znovu."; exit 1
fi
if ! command -v ffmpeg >/dev/null; then
  echo "Chybi ffmpeg."
  if command -v brew >/dev/null; then
    echo "Instaluji pres Homebrew..."; brew install ffmpeg
  else
    echo "Na Macu: nainstaluj Homebrew (https://brew.sh) a pak 'brew install ffmpeg'."
    echo "Na Linuxu: sudo apt install ffmpeg"; exit 1
  fi
fi

[ -d .venv ] || python3 -m venv .venv
source .venv/bin/activate
pip install -q -r requirements.txt

echo
echo "🐒 BUZZOONS Downloader bezi na http://127.0.0.1:8000  (ukoncis Ctrl+C)"
( sleep 2; open "http://127.0.0.1:8000" 2>/dev/null || xdg-open "http://127.0.0.1:8000" 2>/dev/null ) &
uvicorn app.main:app --port 8000
