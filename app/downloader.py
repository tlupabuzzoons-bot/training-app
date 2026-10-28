"""Stahovaci jadro: yt-dlp + ffmpeg.

Jeden Job = jeden odkaz + jeden cilovy format (mp4 / mov / mp3).
Vsechno bezi v pozadi ve vlaknech, stav jobu se cte pres get_job().
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import yt_dlp

DOWNLOAD_DIR = Path(os.environ.get("DOWNLOAD_DIR", "downloads")).resolve()
COOKIES_FILE = os.environ.get("COOKIES_FILE")  # volitelne: cookies.txt (Netscape format) pro IG / privatni videa
KEEP_HOURS = float(os.environ.get("KEEP_HOURS", "6"))
MAX_WORKERS = int(os.environ.get("MAX_WORKERS", "2"))

FORMATS = {"mp4", "mov", "mp3"}
QUALITIES = {"best": None, "1080": 1080, "720": 720, "480": 480}

PLATFORMS = (
    ("youtube", ("youtube.com", "youtu.be", "music.youtube.com")),
    ("instagram", ("instagram.com", "instagr.am")),
    ("tiktok", ("tiktok.com", "vm.tiktok.com", "vt.tiktok.com")),
    ("facebook", ("facebook.com", "fb.watch", "fb.com")),
    ("x", ("x.com", "twitter.com")),
    ("vimeo", ("vimeo.com",)),
)


def detect_platform(url: str) -> str:
    host = (urlparse(url).hostname or "").lower()
    host = host[4:] if host.startswith("www.") else host
    for name, domains in PLATFORMS:
        if any(host == d or host.endswith("." + d) for d in domains):
            return name
    return "other"


def validate_url(url: str) -> str:
    url = (url or "").strip()
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError("Zadej platny odkaz zacinajici http:// nebo https://")
    return url


@dataclass
class Job:
    id: str
    url: str
    fmt: str
    quality: str
    platform: str
    status: str = "queued"  # queued | fetching | downloading | converting | done | error
    progress: float = 0.0
    message: str = ""
    title: Optional[str] = None
    thumbnail: Optional[str] = None
    duration: Optional[float] = None
    uploader: Optional[str] = None
    filename: Optional[str] = None
    filepath: Optional[str] = None
    size: Optional[int] = None
    error: Optional[str] = None
    created_at: float = field(default_factory=time.time)
    finished_at: Optional[float] = None

    def public(self) -> dict:
        d = asdict(self)
        d.pop("filepath", None)
        d["download_url"] = f"/api/jobs/{self.id}/file" if self.status == "done" else None
        return d


_jobs: dict[str, Job] = {}
_lock = threading.Lock()
_pool = ThreadPoolExecutor(max_workers=MAX_WORKERS)


def _base_opts() -> dict:
    opts: dict = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "nocheckcertificate": False,
        "restrictfilenames": False,
        "windowsfilenames": True,  # bezpecne nazvy souboru napric OS
        "retries": 3,
        "fragment_retries": 3,
        "concurrent_fragment_downloads": 4,
        "overwrites": True,
    }
    if COOKIES_FILE and Path(COOKIES_FILE).exists():
        opts["cookiefile"] = COOKIES_FILE
    return opts


def _video_format_selector(max_height: Optional[int]) -> str:
    h = f"[height<={max_height}]" if max_height else ""
    # Preferuj h264 + aac (mp4/m4a) kvuli kompatibilite se strihacimi programy,
    # pak cokoli nejlepsiho, pak jednosouborove formaty.
    return (
        f"bv*{h}[vcodec^=avc1][ext=mp4]+ba[acodec^=mp4a][ext=m4a]/"
        f"bv*{h}[ext=mp4]+ba[ext=m4a]/"
        f"bv*{h}+ba/"
        f"b{h}/b"
    )


def fetch_info(url: str) -> dict:
    """Rychly nahled (nazev, nahled, delka) bez stahovani."""
    url = validate_url(url)
    opts = _base_opts()
    opts["skip_download"] = True
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)
    if info.get("_type") == "playlist" and info.get("entries"):
        info = next((e for e in info["entries"] if e), info)
    return {
        "platform": detect_platform(url),
        "title": info.get("title"),
        "thumbnail": info.get("thumbnail"),
        "duration": info.get("duration"),
        "uploader": info.get("uploader") or info.get("channel"),
        "extractor": info.get("extractor_key"),
    }


def create_job(url: str, fmt: str, quality: str = "best") -> Job:
    url = validate_url(url)
    fmt = (fmt or "mp4").lower()
    if fmt not in FORMATS:
        raise ValueError(f"Nepodporovany format '{fmt}'. Vyber z: mp4, mov, mp3")
    quality = quality if quality in QUALITIES else "best"
    job = Job(id=uuid.uuid4().hex[:12], url=url, fmt=fmt, quality=quality, platform=detect_platform(url))
    with _lock:
        _jobs[job.id] = job
    _pool.submit(_run_job, job)
    return job


def get_job(job_id: str) -> Optional[Job]:
    return _jobs.get(job_id)


def list_jobs() -> list[Job]:
    return sorted(_jobs.values(), key=lambda j: j.created_at, reverse=True)


def delete_job(job_id: str) -> bool:
    with _lock:
        job = _jobs.pop(job_id, None)
    if not job:
        return False
    shutil.rmtree(DOWNLOAD_DIR / job.id, ignore_errors=True)
    return True


# ---------------------------------------------------------------- pipeline

def _run_job(job: Job) -> None:
    job_dir = DOWNLOAD_DIR / job.id
    job_dir.mkdir(parents=True, exist_ok=True)
    try:
        job.status = "fetching"
        job.message = "Zjistuji informace o videu..."
        path = _download(job, job_dir)
        job.status = "converting"
        job.progress = 100.0
        job.message = f"Pripravuji {job.fmt.upper()}..."
        final = _finalize(job, path, job_dir)
        job.filepath = str(final)
        job.filename = final.name
        job.size = final.stat().st_size
        job.status = "done"
        job.message = "Hotovo!"
    except yt_dlp.utils.DownloadError as e:
        job.status = "error"
        job.error = _friendly_error(str(e), job.platform)
    except Exception as e:  # noqa: BLE001
        job.status = "error"
        job.error = _friendly_error(str(e), job.platform)
    finally:
        job.finished_at = time.time()
        # uklid mezisouboru, nechame jen vysledek
        if job.status == "done" and job.filepath:
            for p in job_dir.iterdir():
                if str(p) != job.filepath:
                    try:
                        p.unlink()
                    except OSError:
                        pass


def _download(job: Job, job_dir: Path) -> Path:
    def hook(d: dict) -> None:
        if d["status"] == "downloading":
            job.status = "downloading"
            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            done = d.get("downloaded_bytes") or 0
            if total:
                job.progress = round(done / total * 100, 1)
            speed = d.get("speed")
            eta = d.get("eta")
            parts = []
            if speed:
                parts.append(f"{speed / 1_000_000:.1f} MB/s")
            if eta:
                parts.append(f"zbyva ~{int(eta)} s")
            job.message = "Stahuji... " + " · ".join(parts)
        elif d["status"] == "finished":
            job.progress = 100.0
            job.message = "Stazeno, zpracovavam..."

    opts = _base_opts()
    opts["outtmpl"] = str(job_dir / "%(title).100s [%(id)s].%(ext)s")
    opts["progress_hooks"] = [hook]

    if job.fmt == "mp3":
        opts["format"] = "ba[ext=m4a]/ba/b"
        opts["postprocessors"] = [
            {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "0"},
        ]
    else:
        opts["format"] = _video_format_selector(QUALITIES[job.quality])
        opts["merge_output_format"] = "mp4"
        opts["postprocessors"] = [{"key": "FFmpegVideoRemuxer", "preferedformat": "mp4"}]

    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(job.url, download=True)
        if info.get("_type") == "playlist" and info.get("entries"):
            info = next((e for e in info["entries"] if e), info)
        job.title = info.get("title")
        job.thumbnail = info.get("thumbnail")
        job.duration = info.get("duration")
        job.uploader = info.get("uploader") or info.get("channel")

        # yt-dlp po postprocessingu uklada finalni cestu do requested_downloads
        path = None
        for rd in info.get("requested_downloads") or []:
            if rd.get("filepath"):
                path = Path(rd["filepath"])
                break
        if path is None:
            path = Path(ydl.prepare_filename(info))
    if not path.exists():
        # fallback: nejvetsi soubor ve slozce
        candidates = [p for p in job_dir.iterdir() if p.is_file() and not p.name.endswith(".part")]
        if not candidates:
            raise RuntimeError("Stazeni selhalo, soubor nevznikl.")
        path = max(candidates, key=lambda p: p.stat().st_size)
    return path


def _probe(path: Path) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout
    streams = json.loads(out).get("streams", [])
    v = next((s for s in streams if s.get("codec_type") == "video"), None)
    a = next((s for s in streams if s.get("codec_type") == "audio"), None)
    return {"video": v["codec_name"] if v else None, "audio": a["codec_name"] if a else None}


def _finalize(job: Job, path: Path, job_dir: Path) -> Path:
    """Zajisti cilovy kontejner + kodeky kompatibilni se strihem (h264/aac)."""
    if job.fmt == "mp3":
        if path.suffix.lower() != ".mp3":
            out = path.with_suffix(".mp3")
            _ffmpeg(["-i", str(path), "-vn", "-c:a", "libmp3lame", "-q:a", "0", str(out)])
            return out
        return path

    codecs = _probe(path)
    compatible = codecs["video"] in ("h264", "hevc") and codecs["audio"] in ("aac", "mp3", None)
    target = path.with_name(f"{path.stem}.{job.fmt}")
    if target == path and compatible:
        return path
    final_name = target
    if target == path:
        # prekodovani "na miste": pisu do docasneho souboru a pak prejmenuju
        target = path.with_name(f"{path.stem}.tmp.{job.fmt}")

    if compatible:
        job.message = f"Prebaluji do {job.fmt.upper()}..."
        _ffmpeg(["-i", str(path), "-c", "copy", "-movflags", "+faststart", str(target)])
    else:
        job.message = f"Prekoduji do H.264 ({job.fmt.upper()}), chvilku to potrva..."
        _ffmpeg([
            "-i", str(path),
            "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k",
            "-movflags", "+faststart",
            str(target),
        ])
    if target != final_name:
        path.unlink(missing_ok=True)
        target.replace(final_name)
        return final_name
    return target


def _ffmpeg(args: list[str]) -> None:
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *args]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"ffmpeg selhal: {res.stderr.strip()[-500:]}")


def _friendly_error(msg: str, platform: str) -> str:
    msg = re.sub(r"\x1b\[[0-9;]*m", "", msg)
    low = msg.lower()
    if "login" in low or "cookies" in low or "rate-limit" in low or "not available" in low and platform == "instagram":
        return ("Platforma vyzaduje prihlaseni (typicky Instagram). Nastav COOKIES_FILE "
                "s exportovanymi cookies prohlizece a zkus to znovu. Detail: " + msg[:300])
    if "private" in low:
        return "Video je soukrome, bez prihlaseni ho nejde stahnout."
    if "unsupported url" in low:
        return "Tenhle odkaz neumim zpracovat. Zkus primy odkaz na video (YouTube, Instagram, TikTok...)."
    if "proxy" in low or "connection" in low or "timed out" in low:
        return "Nepodarilo se pripojit k platforme (sit / proxy). Detail: " + msg[:300]
    return msg[:500]


# ---------------------------------------------------------------- uklid

def _cleanup_loop() -> None:
    while True:
        time.sleep(600)
        cutoff = time.time() - KEEP_HOURS * 3600
        for job in list_jobs():
            if job.finished_at and job.finished_at < cutoff:
                delete_job(job.id)
        # osirele slozky (po restartu serveru)
        if DOWNLOAD_DIR.exists():
            for d in DOWNLOAD_DIR.iterdir():
                if d.is_dir() and d.name not in _jobs and d.stat().st_mtime < cutoff:
                    shutil.rmtree(d, ignore_errors=True)


def start_cleanup() -> None:
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    threading.Thread(target=_cleanup_loop, daemon=True).start()
