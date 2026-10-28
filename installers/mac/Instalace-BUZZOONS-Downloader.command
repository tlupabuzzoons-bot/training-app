#!/bin/bash
# =====================================================================
#  BUZZOONS Downloader - instalace na Mac jednim kliknutim
#  Nainstaluje vsechno potrebne a vytvori ikonu na Plose.
#  Lze spustit opakovane (aktualizuje appku).
# =====================================================================
REPO="tlupabuzzoons-bot/training-app"
BRANCH="${BUZZOONS_BRANCH:-claude/blissful-albattani-5oyzkb}"
APPDIR="$HOME/Library/Application Support/BUZZOONS Downloader"
APP="$HOME/Desktop/BUZZOONS Downloader.app"
LOGDIR="$HOME/Library/Logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/BUZZOONS Downloader install.log"
PORT=8000

exec > >(tee -a "$LOG") 2>&1
set -o pipefail

G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; B='\033[1m'; N='\033[0m'
step(){ echo; echo -e "${B}${G}==> $1${N}"; }
ok(){ echo -e "   ${G}✔ $1${N}"; }
die(){ echo; echo -e "${R}✖ CHYBA: $1${N}"; echo -e "   Detail je v: $LOG"; echo -e "   Posli tenhle soubor nebo screenshot a opravime to. 🐒"; echo; read -r -p "Stiskni Enter pro zavreni..." _; exit 1; }

echo
echo -e "${B}🐒💚  BUZZOONS Downloader - instalace${N}"
echo "    Vsechno probehne automaticky. Mac si muze vyzadat heslo (kvuli instalaci Homebrew)."
echo "    Log: $LOG"
echo

# ---------------------------------------------------------------- Homebrew
step "1/6 Homebrew (spravce balicku pro Mac)"
if [ "$(uname)" = "Darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "   Homebrew chybi, instaluji (muze trvat nekolik minut, zadej heslo k Macu kdyz si ho vyzada)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty || die "Instalace Homebrew se nepovedla."
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
    command -v brew >/dev/null 2>&1 || die "Homebrew se nainstaloval, ale nenasel jsem ho. Zavri Terminal, otevri ho znovu a spust instalator jeste jednou."
    BREWLINE="eval \"\$($(command -v brew) shellenv)\""
    grep -qs "brew shellenv" "$HOME/.zprofile" 2>/dev/null || echo "$BREWLINE" >> "$HOME/.zprofile"
  fi
  ok "Homebrew: $(brew --version | head -1)"
  BREWPREFIX="$(brew --prefix)"
else
  echo "   (ne-Mac system, Homebrew preskakuji)"; BREWPREFIX="/usr"
fi

# ---------------------------------------------------------------- Python + ffmpeg
step "2/6 Python a ffmpeg"
PY=""
for c in "$BREWPREFIX/bin/python3" python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then PY="$(command -v "$c")"; break; fi
done
if [ -z "$PY" ]; then
  [ "$(uname)" = "Darwin" ] || die "Chybi Python 3.10+."
  echo "   Instaluji Python..."; brew install python || die "Instalace Pythonu selhala."
  PY="$BREWPREFIX/bin/python3"
fi
ok "Python: $("$PY" --version) ($PY)"
export PATH="$BREWPREFIX/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v ffmpeg >/dev/null 2>&1; then
  [ "$(uname)" = "Darwin" ] || die "Chybi ffmpeg."
  echo "   Instaluji ffmpeg (vetsi balik, chvili to trva)..."; brew install ffmpeg || die "Instalace ffmpeg selhala."
fi
ok "ffmpeg: $(ffmpeg -version 2>/dev/null | head -1 | cut -d' ' -f3)"

# ---------------------------------------------------------------- stazeni appky
step "3/6 Stahuji appku z GitHubu"
TMP="$(mktemp -d)"
ZIPURL="https://codeload.github.com/$REPO/zip/refs/heads/$BRANCH"
curl -fsSL "$ZIPURL" -o "$TMP/app.zip" || die "Nepodarilo se stahnout appku ($ZIPURL). Jsi pripojeny k internetu?"
unzip -q "$TMP/app.zip" -d "$TMP/src" || die "Rozbaleni selhalo."
SRC="$(find "$TMP/src" -mindepth 1 -maxdepth 1 -type d | head -1)"
[ -f "$SRC/requirements.txt" ] || die "Stazeny balik nevypada jako BUZZOONS Downloader."
mkdir -p "$APPDIR"
cp -R "$SRC"/. "$APPDIR"/ || die "Kopirovani do $APPDIR selhalo."
rm -rf "$TMP"
ok "Appka je v: $APPDIR"

# ---------------------------------------------------------------- python prostredi
step "4/6 Instaluji knihovny (yt-dlp, FastAPI...)"
cd "$APPDIR" || die "Nelze otevrit $APPDIR"
if [ -d .venv ] && ! .venv/bin/python -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then rm -rf .venv; fi
[ -d .venv ] || "$PY" -m venv .venv || die "Vytvoreni prostredi selhalo."
.venv/bin/python -m pip install -q --upgrade pip >/dev/null 2>&1
.venv/bin/python -m pip install -q -r requirements.txt || die "Instalace knihoven selhala."
.venv/bin/python -c "import yt_dlp, fastapi, uvicorn" || die "Knihovny se nainstalovaly, ale nejdou nacist."
ok "Knihovny: yt-dlp $(.venv/bin/python -c 'import yt_dlp; print(yt_dlp.version.__version__)')"

# ---------------------------------------------------------------- ikona na plose
step "5/6 Vytvarim ikonu na Plose"
if [ "$(uname)" = "Darwin" ]; then
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp launcher/mac/launch.sh "$APP/Contents/MacOS/launch"; chmod +x "$APP/Contents/MacOS/launch"
  cp launcher/mac/Info.plist "$APP/Contents/Info.plist"
  ICONSET="$(mktemp -d)/icon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s assets/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
    sips -z $((s*2)) $((s*2)) assets/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/icon.icns" 2>/dev/null || cp assets/icon.png "$APP/Contents/Resources/icon.png"
  touch "$APP"
  ok "Ikona: $APP"
else
  echo "   (ne-Mac system, .app preskakuji)"
fi

# ---------------------------------------------------------------- kontrola
step "6/6 Kontrola, ze vsechno funguje"
export PATH="$BREWPREFIX/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
if curl -fs -m 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
  echo "   Appka uz bezi, vypinam ji kvuli aktualizaci..."
  curl -fs -m 2 -X POST "http://127.0.0.1:$PORT/api/shutdown" >/dev/null 2>&1; sleep 3
fi
AUTO_SHUTDOWN=1 nohup .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port $PORT >"$LOGDIR/BUZZOONS Downloader.log" 2>&1 &
HEALTH=""
for _ in $(seq 1 40); do HEALTH="$(curl -fs -m 2 "http://127.0.0.1:$PORT/api/health" 2>/dev/null)" && break; sleep 0.5; done
echo "$HEALTH" | grep -q '"ok":true' || { curl -fs -m 2 -X POST "http://127.0.0.1:$PORT/api/shutdown" >/dev/null 2>&1; die "Testovaci spusteni selhalo (odpoved: ${HEALTH:-zadna}). Log: $LOGDIR/BUZZOONS Downloader.log"; }
curl -fs -m 2 -X POST "http://127.0.0.1:$PORT/api/shutdown" >/dev/null 2>&1
ok "Server nabehl, ffmpeg i yt-dlp odpovidaji"

echo
echo -e "${B}${G}🎉 HOTOVO! BUZZOONS Downloader je nainstalovany.${N}"
echo
echo "   Na Plose mas ikonu 'BUZZOONS Downloader'. Klikni na ni a otevre se stranka."
echo "   Appka se sama vypne, kdyz zavres panel v prohlizeci."
echo "   Tohle okno Terminalu muzes zavrit."
echo
if [ "$(uname)" = "Darwin" ]; then
  sleep 1; open "$APP"
fi
