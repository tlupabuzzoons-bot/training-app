"""BUZZOONS Video Downloader - FastAPI server."""
from __future__ import annotations

import asyncio
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import downloader

app = FastAPI(title="BUZZOONS Downloader", version="1.0.0")
STATIC_DIR = Path(__file__).resolve().parent.parent / "static"


class InfoRequest(BaseModel):
    url: str


class DownloadRequest(BaseModel):
    url: str
    format: str = "mp4"  # mp4 | mov | mp3
    quality: str = "best"  # best | 1080 | 720 | 480


@app.on_event("startup")
def _startup() -> None:
    downloader.start_cleanup()


@app.get("/")
def index() -> RedirectResponse:
    return RedirectResponse("/static/index.html")


@app.post("/api/info")
async def info(req: InfoRequest) -> dict:
    try:
        return await asyncio.wait_for(asyncio.to_thread(downloader.fetch_info, req.url), timeout=45)
    except ValueError as e:
        raise HTTPException(400, str(e))
    except asyncio.TimeoutError:
        raise HTTPException(504, "Nacteni informaci trvalo moc dlouho.")
    except Exception as e:  # noqa: BLE001
        raise HTTPException(422, downloader._friendly_error(str(e), downloader.detect_platform(req.url)))


@app.post("/api/download", status_code=202)
def download(req: DownloadRequest) -> dict:
    try:
        job = downloader.create_job(req.url, req.format, req.quality)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return job.public()


@app.get("/api/jobs")
def jobs() -> list[dict]:
    return [j.public() for j in downloader.list_jobs()]


@app.get("/api/jobs/{job_id}")
def job_status(job_id: str) -> dict:
    job = downloader.get_job(job_id)
    if not job:
        raise HTTPException(404, "Job nenalezen")
    return job.public()


@app.get("/api/jobs/{job_id}/file")
def job_file(job_id: str) -> FileResponse:
    job = downloader.get_job(job_id)
    if not job:
        raise HTTPException(404, "Job nenalezen")
    if job.status != "done" or not job.filepath or not Path(job.filepath).exists():
        raise HTTPException(409, "Soubor jeste neni hotovy")
    media = {"mp4": "video/mp4", "mov": "video/quicktime", "mp3": "audio/mpeg"}[job.fmt]
    return FileResponse(job.filepath, media_type=media, filename=job.filename)


@app.delete("/api/jobs/{job_id}")
def job_delete(job_id: str) -> dict:
    if not downloader.delete_job(job_id):
        raise HTTPException(404, "Job nenalezen")
    return {"ok": True}


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
