"""Automaticke vypinani serveru.

Aktivni jen kdyz je nastaveno AUTO_SHUTDOWN=1 (nastavuje spoustec z ikony na plose).
- stranka posila kazdych par sekund /api/ping
- pri zavreni panelu posle /api/bye -> vypnuti za BYE_GRACE s (pokud se stranka nevrati)
- bez pingu dele nez IDLE_TIMEOUT s -> vypnuti (prohlizec spadl, panel na pozadi apod.)
- /api/shutdown -> vypnuti hned
Bezici stahovani se vzdy necha dobehnout.
"""
from __future__ import annotations

import os
import signal
import threading
import time

from . import downloader

ENABLED = os.environ.get("AUTO_SHUTDOWN", "0") == "1"
BYE_GRACE = float(os.environ.get("BYE_GRACE", "5"))
IDLE_TIMEOUT = float(os.environ.get("IDLE_TIMEOUT", "90"))
STARTUP_GRACE = float(os.environ.get("STARTUP_GRACE", "180"))

_started = time.time()
_last_ping = 0.0
_bye_at = 0.0
_shutting_down = False
_lock = threading.Lock()


def ping() -> None:
    global _last_ping, _bye_at
    with _lock:
        _last_ping = time.time()
        _bye_at = 0.0


def bye() -> None:
    global _bye_at
    with _lock:
        _bye_at = time.time()


def is_shutting_down() -> bool:
    return _shutting_down


def _jobs_running() -> bool:
    return any(j.status not in ("done", "error") for j in downloader.list_jobs())


def shutdown(force: bool = False) -> None:
    """Ukonci proces. Bez force ceka, az dobehnou stahovani."""
    global _shutting_down
    with _lock:
        if _shutting_down:
            return
        _shutting_down = True

    def _go() -> None:
        while not force and _jobs_running():
            time.sleep(2)
        os.kill(os.getpid(), signal.SIGINT)  # uvicorn: graceful shutdown
        time.sleep(5)
        os._exit(0)

    threading.Thread(target=_go, daemon=True).start()


def _watchdog() -> None:
    while not _shutting_down:
        time.sleep(2)
        now = time.time()
        with _lock:
            last_ping, bye_at = _last_ping, _bye_at
        if bye_at and now - bye_at > BYE_GRACE:
            shutdown()
        elif last_ping and now - last_ping > IDLE_TIMEOUT:
            shutdown()
        elif not last_ping and now - _started > STARTUP_GRACE:
            shutdown()


def start() -> None:
    if ENABLED:
        threading.Thread(target=_watchdog, daemon=True).start()
