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

## Instalace jedním kliknutím (pro celou tlupu)

### Mac

1. Stáhni [**Instalace-BUZZOONS-Downloader-Mac.zip**](https://github.com/tlupabuzzoons-bot/training-app/raw/claude/blissful-albattani-5oyzkb/installers/Instalace-BUZZOONS-Downloader-Mac.zip). Safari ho sám rozbalí na soubor `Instalace-BUZZOONS-Downloader.command` ve Stažených.
2. Poklepej na něj. Mac zobrazí varování, že soubor je od neznámého vývojáře. Otevři **Nastavení systému → Soukromí a zabezpečení**, sjeď dolů a klikni **Přesto otevřít**. (Na starším macOS stačí pravý klik → Otevřít.)
3. Otevře se Terminál a všechno proběhne samo: Homebrew, Python, ffmpeg, appka. Když si Mac vyžádá heslo, zadej ho. Trvá to 3 až 10 minut.
4. Na konci se na Ploše objeví ikona **BUZZOONS Downloader** a stránka se sama otevře.

Alternativa bez stahování souboru: otevři Terminál, vlož tenhle řádek a stiskni Enter.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tlupabuzzoons-bot/training-app/claude/blissful-albattani-5oyzkb/installers/mac/Instalace-BUZZOONS-Downloader.command)
```

### Windows

1. Stáhni [**Instalace-BUZZOONS-Downloader.bat**](https://github.com/tlupabuzzoons-bot/training-app/raw/claude/blissful-albattani-5oyzkb/installers/windows/Instalace-BUZZOONS-Downloader.bat) (pravý klik → Uložit odkaz jako, pokud se zobrazí jako text).
2. Poklepej na něj. Windows zobrazí SmartScreen: klikni **Další informace → Přesto spustit**.
3. Všechno proběhne samo přes winget (Python, ffmpeg, appka). Trvá to 3 až 10 minut.
4. Na Ploše se objeví zástupce **BUZZOONS Downloader** a stránka se sama otevře.

### Používání

- Klik na ikonu na Ploše spustí appku na pozadí a otevře stránku v prohlížeči.
- Zavřením panelu v prohlížeči (nebo tlačítkem **Vypnout** na stránce) se appka sama vypne. Rozdělané stahování nechá doběhnout.
- Instalátor jde spustit znovu kdykoliv, jen appku aktualizuje. Knihovna yt-dlp se navíc tiše aktualizuje při každém spuštění.
- Vše běží jen na tvém počítači (adresa 127.0.0.1). Nikdo jiný nevidí, co stahuješ.

Kde to je: appka v `~/Library/Application Support/BUZZOONS Downloader` (Mac) nebo `%LOCALAPPDATA%\BUZZOONS Downloader` (Windows), logy v `~/Library/Logs/` (Mac) nebo ve stejné složce jako appka (Windows).

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
