# 🐒 BUZZOONS Downloader

Vložíš odkaz na video (YouTube, Instagram, TikTok, Facebook, X, Vimeo a stovky dalších),
vybereš formát a stáhneš. Hotovo za pár sekund, rovnou připravené do střihu.

| Formát | Co dostaneš |
|--------|-------------|
| **MP4** | video H.264 + AAC (DaVinci / Premiere friendly), volitelně max. 1080p / 720p / 480p |
| **MOV** | to samé v QuickTime kontejneru |
| **MP3** | jen zvuk, nejlepší kvalita (VBR) |

Pod kapotou běží [yt-dlp](https://github.com/yt-dlp/yt-dlp) + [ffmpeg](https://ffmpeg.org),
nad tím malý FastAPI server a jednostránkové webové UI.

## Nejrychlejší spuštění (bez terminálu)

1. Stáhni repo (tlačítko **Code → Download ZIP** na GitHubu) a rozbal ho.
2. Nainstaluj Python z https://www.python.org/downloads/ (na Windows zaškrtni *Add Python to PATH*).
3. Nainstaluj ffmpeg: Mac `brew install ffmpeg`, Windows `winget install Gyan.FFmpeg`.
4. Spusť **`start.sh`** (Mac/Linux) nebo poklepej na **`start.bat`** (Windows). Prohlížeč se otevře sám.

## Spuštění ručně z terminálu

Potřebuješ Python 3.11+ a `ffmpeg` v PATH (`brew install ffmpeg` / `apt install ffmpeg`).

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Otevři http://127.0.0.1:8000 🎥✨

## Spuštění v Dockeru

```bash
docker build -t buzzoons-downloader .
docker run -p 8000:8000 -v $(pwd)/downloads:/app/downloads buzzoons-downloader
```

## Nastavení (env proměnné)

| Proměnná | Výchozí | K čemu |
|----------|---------|--------|
| `DOWNLOAD_DIR` | `downloads` | kam se ukládají hotové soubory |
| `KEEP_HOURS` | `6` | po kolika hodinách se hotové soubory automaticky mažou |
| `MAX_WORKERS` | `2` | kolik stahování běží paralelně |
| `COOKIES_FILE` | – | cesta k `cookies.txt` (Netscape formát) pro Instagram / privátní videa |

### Instagram a přihlášení

Instagram často odmítne anonymní stahování. Řešení: v prohlížeči (přihlášený na IG) exportuj cookies
rozšířením typu *Get cookies.txt LOCALLY*, soubor ulož jako `cookies.txt` do kořene projektu a spusť:

```bash
COOKIES_FILE=cookies.txt uvicorn app.main:app
```

Totéž pomůže u videí jen pro přihlášené na YouTube.

## API

Všechno, co dělá UI, jde volat i přímo:

```bash
# náhled (název, thumbnail, délka)
curl -X POST localhost:8000/api/info -H 'Content-Type: application/json' -d '{"url":"https://youtu.be/..."}'

# spustit stahování -> vrátí job
curl -X POST localhost:8000/api/download -H 'Content-Type: application/json' \
  -d '{"url":"https://www.tiktok.com/@x/video/123","format":"mp4","quality":"1080"}'

# stav jobu / seznam / stažení souboru / smazání
curl localhost:8000/api/jobs/<id>
curl localhost:8000/api/jobs
curl -OJ localhost:8000/api/jobs/<id>/file
curl -X DELETE localhost:8000/api/jobs/<id>
```

`format`: `mp4` | `mov` | `mp3`, `quality`: `best` | `1080` | `720` | `480` (jen pro video).

## Jak to funguje

1. `yt-dlp` stáhne nejlepší dostupné streamy (přednostně H.264 + AAC) a spojí je do MP4.
2. `ffprobe` zkontroluje kodeky. Když platforma dala VP9/AV1/Opus, `ffmpeg` překóduje do H.264/AAC,
   aby soubor bez problémů otevřel každý střihový program. MOV je pak jen přebalení bez ztráty kvality.
3. Pro MP3 se stáhne jen audio stream a převede se přes `libmp3lame` v nejlepší kvalitě.
4. Hotové soubory se po `KEEP_HOURS` hodinách samy promažou.

Stahuj jen obsah, na který máš práva. 🐒💚
