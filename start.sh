#!/usr/bin/env bash
# BUZZOONS Downloader - spusteni na Macu / Linuxu. Staci: ./start.sh
set -e
cd "$(dirname "$0")"

# --- najdi dostatecne novy Python (yt-dlp potrebuje 3.10+) ---
PY=""
for c in python3.13 python3.12 python3.11 python3.10 /opt/homebrew/bin/python3 /usr/local/bin/python3 python3; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
    PY="$(command -v "$c")"; break
  fi
done
if [ -z "$PY" ]; then
  echo "Chybi Python 3.10 nebo novejsi (systemovy Python na Macu je moc stary)."
  if command -v brew >/dev/null; then
    echo "Instaluji pres Homebrew..."; brew install python
    PY="$(brew --prefix)/bin/python3"
  else
    echo "Nainstaluj Homebrew (https://brew.sh) a pak 'brew install python', nebo Python z https://www.python.org/downloads/"; exit 1
  fi
fi
echo "Pouzivam Python: $PY ($("$PY" --version))"

# --- ffmpeg ---
if ! command -v ffmpeg >/dev/null; then
  echo "Chybi ffmpeg."
  if command -v brew >/dev/null; then
    echo "Instaluji pres Homebrew..."; brew install ffmpeg
  else
    echo "Na Macu: nainstaluj Homebrew (https://brew.sh) a pak 'brew install ffmpeg'."
    echo "Na Linuxu: sudo apt install ffmpeg"; exit 1
  fi
fi

# --- virtualni prostredi (kdyz je ze stareho Pythonu, zaloz znovu) ---
if [ -d .venv ] && ! .venv/bin/python -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
  echo "Stare prostredi .venv, zakladam znovu..."; rm -rf .venv
fi
[ -d .venv ] || "$PY" -m venv .venv
source .venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt

echo
echo "🐒 BUZZOONS Downloader bezi na http://127.0.0.1:8000  (ukoncis Ctrl+C)"
( sleep 2; open "http://127.0.0.1:8000" 2>/dev/null || xdg-open "http://127.0.0.1:8000" 2>/dev/null ) &
uvicorn app.main:app --port 8000
